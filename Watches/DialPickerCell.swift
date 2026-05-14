import AppKit
import WatchesCore

/// One cell in the prefs `NSCollectionView` dial picker (Story 3.1).
///
/// Programmatic — no xib. Lays out a preview image above a label, draws a
/// rounded selection background when `isSelected == true`.
final class DialPickerCell: NSCollectionViewItem {

    /// Reuse identifier used by `WatchesPreferencesController` to register
    /// + dequeue cells.
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("DialPickerCell")

    /// Stable cell size used by the flow layout so the view doesn't have to
    /// negotiate sizes via Auto Layout intrinsic content size.
    static let itemSize = CGSize(width: 168, height: 196)

    // MARK: Subviews

    private let containerView = NSView()
    private let imageView_ = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    // MARK: NSCollectionViewItem

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.itemSize))
        root.wantsLayer = true
        self.view = root

        // Container draws the rounded selection background. Sits inside
        // root so root's bounds stays clip-free for hit-testing.
        containerView.frame = root.bounds
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8
        containerView.layer?.borderWidth = 0
        root.addSubview(containerView)

        // Image: 152x152 area at the top of the cell.
        imageView_.frame = NSRect(x: 8, y: 36, width: 152, height: 152)
        imageView_.imageScaling = .scaleProportionallyUpOrDown
        imageView_.imageAlignment = .alignCenter
        imageView_.wantsLayer = true
        imageView_.layer?.cornerRadius = 6
        imageView_.layer?.masksToBounds = true
        // Subtle border so an absent / opaque image doesn't blend into the
        // window background.
        imageView_.layer?.borderWidth = 0.5
        imageView_.layer?.borderColor = NSColor(white: 0.5, alpha: 0.35).cgColor
        containerView.addSubview(imageView_)

        // Title: centered below the image.
        titleLabel.frame = NSRect(x: 8, y: 8, width: 152, height: 22)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        containerView.addSubview(titleLabel)

        // Selection state visible to the system (used by accessibility +
        // collection-view defaults).
        self.imageView = imageView_
        self.textField = titleLabel
    }

    /// Populate the cell from a registered dial type.
    func configure(with dialType: DialRenderer.Type) {
        titleLabel.stringValue = dialType.identity.displayName
        imageView_.image = DialRegistry.previewImage(for: dialType)
    }

    override var isSelected: Bool {
        didSet { applySelectionStyle() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { applySelectionStyle() }
    }

    private func applySelectionStyle() {
        let highlightedOrSelected = isSelected
            || highlightState == .forSelection
            || highlightState == .forDeselection
        containerView.layer?.backgroundColor = highlightedOrSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
            : NSColor.clear.cgColor
        containerView.layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
        containerView.layer?.borderWidth = isSelected ? 2 : 0
    }
}
