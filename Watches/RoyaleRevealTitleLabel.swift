import AppKit

/// `NSTextField` subclass that detects an Option-click (Story 3.2 reveal
/// gesture) and routes it to the supplied closure. Regular clicks fall
/// through to the default `NSTextField` behavior so the label still looks
/// and feels like a normal label.
final class RoyaleRevealTitleLabel: NSTextField {

    /// Invoked when the user Option-clicks the label. The owning prefs
    /// controller installs a closure that flips the `royaleRevealed`
    /// default and reloads the picker.
    var onOptionClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            onOptionClick?()
            return
        }
        super.mouseDown(with: event)
    }
}
