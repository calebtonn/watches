import AppKit

/// Observes `NSWorkspace.accessibilityDisplayShouldReduceMotion` and exposes
/// the current value via `isEnabled`.
///
/// The host (`WatchesScreenSaverView`) instantiates one per screen-saver instance
/// and reads `isEnabled` on every `tick(reduceMotion:)` call. macOS posts
/// `accessibilityDisplayOptionsDidChangeNotification` for any a11y display option
/// change (reduce motion, reduce transparency, etc.), so we re-read the current
/// value when the notification fires.
///
/// Honors NFR14 per the architecture.
public final class ReduceMotionObserver: NSObject {
    public private(set) var isEnabled: Bool

    private var notificationToken: NSObjectProtocol?

    public override init() {
        self.isEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.init()

        notificationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    deinit {
        if let token = notificationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
}
