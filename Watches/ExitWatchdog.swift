import Foundation
import os

// Sonoma legacyScreenSaver exit-bug workaround pattern informed by:
//   davenicoll/swiss-railway-clock-screensaver (MIT)
//   https://github.com/davenicoll/swiss-railway-clock-screensaver
// Re-implemented for the Watches project. The bug, the diagnosis, and
// the watchdog-timer mitigation are credited to davenicoll's work. See
// ADR-003 for the full context.

/// Owner protocol the ExitWatchdog calls back into.
///
/// Implemented by `WatchesScreenSaverView` so the watchdog can trigger
/// teardown without depending on the concrete host type. This narrow
/// callback contract keeps `ExitWatchdog` decoupled from the host's
/// display-link / renderer / observer plumbing.
protocol ExitWatchdogOwner: AnyObject {
    /// Called when `com.apple.screensaver.willstop` is posted (or defensively
    /// at `didstop` if `willstop` was skipped).
    /// Must be idempotent — safe to call multiple times.
    func tearDownForExit()
}

/// Listens for the macOS screensaver session lifecycle distributed
/// notifications and ensures the screensaver process actually exits.
///
/// **Why this exists:** on Sonoma+ there is a known bug where
/// `legacyScreenSaver` does not always cleanly exit after a screensaver
/// session ends — the process leaks, with CPU/RAM bleed and occasional
/// unlock-screen artifacts. The fix has two layers:
///
///   1. On `com.apple.screensaver.willstop` (system tells us to wind down),
///      we tear down our resources promptly via the owner callback.
///   2. On `com.apple.screensaver.didstop` (system says session has ended),
///      we tear down defensively (in case willstop was skipped) and arm
///      a 5-second watchdog timer. If the process is still alive when
///      the timer fires AND we're running inside legacyScreenSaver AND
///      the elapsed wall-clock is within tolerance, we force `exit(0)`.
///
/// Per ADR-003: the 5-second interval is davenicoll's tuned value.
///
/// **Process-gate (Story 1.3 review patch):** `exit(0)` only fires when
/// `ProcessInfo.processInfo.processName == "legacyScreenSaver"`. This
/// prevents the rare case where our bundle is loaded into a different
/// host process (e.g., System Settings preview) and a stray distributed
/// notification would terminate the wrong process.
///
/// **Fire-once semantics (Story 1.3 review patch):** observers are
/// unregistered as soon as the watchdog arms, so a second screensaver
/// session re-using the process doesn't accidentally arm a new
/// watchdog against the new session's state.
///
/// **Sleep-wake guard (Story 1.3 review patch):** the wall-clock arm
/// time is captured at didstop. If the timer fires more than 2× the
/// configured interval after arm (e.g., because the system slept during
/// the window), we bail without `exit(0)`. Prevents wrong-session kill.
///
/// **Multi-display behavior:** each `WatchesScreenSaverView` instance
/// owns its own `ExitWatchdog`. On multi-display systems this means N
/// watchdogs all racing on `didstop` — first to fire `exit(0)` wins,
/// the rest are no-ops since the process is gone. Wasteful but correct.
final class ExitWatchdog {

    /// Per ADR-003: 5 seconds is davenicoll's tuned value — long enough
    /// for a normal exit to land, short enough that the bug-path force-
    /// exit feels responsive on unlock.
    static let watchdogInterval: TimeInterval = 5.0

    /// Tolerance for stale-timer detection (Story 1.3 review patch).
    /// If `Date().timeIntervalSince(armTime)` exceeds this, the timer
    /// has been delayed past usefulness (e.g., system slept) and we
    /// refuse to call `exit(0)`. 2× the configured interval.
    static let staleTimerThreshold: TimeInterval = watchdogInterval * 2

    private weak var owner: ExitWatchdogOwner?

    private var willStopObserver: NSObjectProtocol?
    private var didStopObserver: NSObjectProtocol?
    private var watchdogTimer: Timer?

    /// Wall-clock timestamp when the watchdog was armed. Used to detect
    /// stale fires after sleep/wake (Story 1.3 review patch).
    private var armTime: Date?

    /// Once true, no further willstop/didstop handling occurs. Prevents
    /// observer re-arm across screensaver sessions in a reused process
    /// (Story 1.3 review patch).
    private var hasFired: Bool = false

    init(owner: ExitWatchdogOwner) {
        self.owner = owner
        installObservers()
        Logging.exit.info("ExitWatchdog installed.")
    }

    deinit {
        removeObservers()
        watchdogTimer?.invalidate()
    }

    // MARK: Observers

    private func installObservers() {
        let dnc = DistributedNotificationCenter.default()
        willStopObserver = dnc.addObserver(
            forName: Notification.Name("com.apple.screensaver.willstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillStop()
        }
        didStopObserver = dnc.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidStop()
        }
    }

    private func removeObservers() {
        let dnc = DistributedNotificationCenter.default()
        if let token = willStopObserver {
            dnc.removeObserver(token)
        }
        if let token = didStopObserver {
            dnc.removeObserver(token)
        }
        willStopObserver = nil
        didStopObserver = nil
    }

    // MARK: Handlers

    private func handleWillStop() {
        guard !hasFired else { return }
        Logging.exit.info("Received com.apple.screensaver.willstop; tearing down resources.")
        owner?.tearDownForExit()
    }

    private func handleDidStop() {
        guard !hasFired else { return }
        hasFired = true

        Logging.exit.info("Received com.apple.screensaver.didstop; arming \(Int(Self.watchdogInterval))s watchdog.")

        // Defensive teardown (Story 1.3 review patch): willstop may have been
        // skipped (Apple does not guarantee paired delivery). tearDownForExit
        // is idempotent per the owner contract.
        owner?.tearDownForExit()

        // Unregister observers immediately — a second screensaver session
        // re-using this process must not re-arm this watchdog instance
        // (Story 1.3 review patch).
        removeObservers()

        armTime = Date()
        watchdogTimer?.invalidate()

        // Use Timer.init + RunLoop.main.add(forMode: .common) instead of
        // Timer.scheduledTimer (which attaches in .default mode). The
        // watchdog's purpose is to fire during conditions like the unlock
        // password sheet and Touch ID prompt, both of which put the main
        // run loop into tracking mode. .default mode would be starved
        // precisely when the watchdog is most needed (Story 1.3 review patch).
        let timer = Timer(
            timeInterval: Self.watchdogInterval,
            repeats: false
        ) { [weak self] _ in
            self?.handleWatchdogFire()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func handleWatchdogFire() {
        // Sleep-wake guard (Story 1.3 review patch): if the elapsed wall-clock
        // since arming exceeds tolerance, the timer has been suspended (system
        // slept during the window) and resumed against potentially the wrong
        // session. Refuse to exit(0).
        if let armTime, Date().timeIntervalSince(armTime) > Self.staleTimerThreshold {
            Logging.exit.info(
                "Watchdog fired but elapsed wall-clock exceeds threshold; suppressing exit(0)."
            )
            return
        }

        // Host-process gate (Story 1.3 review patch): exit(0) only fires inside
        // legacyScreenSaver. If the bundle is loaded into a different host
        // process (e.g., System Settings preview), don't terminate that host.
        let hostProcess = ProcessInfo.processInfo.processName
        guard hostProcess == "legacyScreenSaver" else {
            Logging.exit.info(
                "Watchdog fired but host process is '\(hostProcess, privacy: .public)', not legacyScreenSaver; suppressing exit(0)."
            )
            return
        }

        Logging.exit.info("Watchdog fired — process still alive 5s post-didstop; forcing exit(0).")
        exit(0)
    }
}
