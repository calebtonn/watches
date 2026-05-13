import Foundation

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
    /// Called when `com.apple.screensaver.willstop` is posted.
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
///      we arm a 5-second watchdog. If the process is still alive when
///      the timer fires, we force `exit(0)` — taking the bug out of
///      macOS's hands.
///
/// Per ADR-003: the 5-second interval is davenicoll's tuned value. Long
/// enough for normal exit to land first (the watchdog should rarely fire
/// on healthy systems); short enough that, when the bug fires, the
/// user's unlock feels responsive.
///
/// **Multi-display behavior:** each `WatchesScreenSaverView` instance
/// owns its own `ExitWatchdog`. On multi-display systems this means N
/// watchdogs all racing on `didstop` — first to fire `exit(0)` wins,
/// the rest are no-ops since the process is gone. Wasteful but correct;
/// singleton refactor is a v1.1 candidate if multi-display testing
/// surfaces real issues.
final class ExitWatchdog {

    /// Per ADR-003: 5 seconds is davenicoll's tuned value — long enough
    /// for a normal exit to land, short enough that the bug-path force-
    /// exit feels responsive on unlock.
    static let watchdogInterval: TimeInterval = 5.0

    private weak var owner: ExitWatchdogOwner?

    private var willStopObserver: NSObjectProtocol?
    private var didStopObserver: NSObjectProtocol?
    private var watchdogTimer: Timer?

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
            willStopObserver = nil
        }
        if let token = didStopObserver {
            dnc.removeObserver(token)
            didStopObserver = nil
        }
    }

    // MARK: Handlers

    private func handleWillStop() {
        Logging.exit.info("Received com.apple.screensaver.willstop; tearing down resources.")
        owner?.tearDownForExit()
    }

    private func handleDidStop() {
        Logging.exit.info("Received com.apple.screensaver.didstop; arming \(Int(Self.watchdogInterval))s watchdog.")
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(
            withTimeInterval: Self.watchdogInterval,
            repeats: false
        ) { [weak self] _ in
            self?.handleWatchdogFire()
        }
    }

    private func handleWatchdogFire() {
        Logging.exit.info("Watchdog fired — process still alive 5s post-didstop; forcing exit(0).")
        exit(0)
    }
}
