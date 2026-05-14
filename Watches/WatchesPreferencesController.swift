import AppKit
import ScreenSaver
import WatchesCore

/// Owns the prefs sheet (Story 3.1 dial picker + Story 3.2 Royale reveal).
///
/// Programmatic — no xib. The sheet is a window containing:
///   - A small "Watches" title label (option-clickable for the Royale reveal).
///   - A scrollable `NSCollectionView` populated from
///     `DialRegistry.visible(includingHidden:)`.
///   - A "Done" button that dismisses the sheet.
///
/// Selection writes `selectedDialID` to the supplied `DefaultsBacking`.
/// Cross-process visibility is handled by `DialPreferences.writeSelectedDialID`
/// (calls `synchronize`).
final class WatchesPreferencesController: NSObject {

    // MARK: Dependencies

    /// Bundle ID used to address `ScreenSaverDefaults`. Passed from the
    /// owning view so production code uses the host bundle's
    /// `bundleIdentifier`; if `ScreenSaverDefaults` returns nil for some
    /// reason we fall back to `UserDefaults.standard`.
    private let defaults: DefaultsBacking

    /// Closure invoked when the user clicks "Done". Owner uses this to
    /// dismiss the sheet via the appropriate API.
    var onDone: (() -> Void)?

    // MARK: UI

    private(set) var window: NSWindow!
    private var titleLabel: RoyaleRevealTitleLabel!
    private var collectionView: NSCollectionView!
    private var doneButton: NSButton!

    // MARK: Data

    /// Current visible dial list — reloaded whenever the picker repaints.
    /// Source of truth: `DialRegistry.visible(includingHidden:)` filtered
    /// by the live Royale-reveal flag.
    private var visibleDials: [DialRenderer.Type] = []

    // MARK: Init

    init(defaults: DefaultsBacking) {
        self.defaults = defaults
        super.init()
        buildWindow()
        reloadDialList()
    }

    // MARK: Window construction

    private func buildWindow() {
        let contentSize = NSSize(width: 560, height: 460)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Watches Preferences"
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        window.contentView?.wantsLayer = true
        self.window = window

        installTitleLabel()
        installPickerScrollView()
        installDoneButton()
    }

    private func installTitleLabel() {
        let label = RoyaleRevealTitleLabel(labelWithString: "Watches")
        label.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 412, width: 560, height: 26)
        label.autoresizingMask = [.width, .minYMargin]
        label.onOptionClick = { [weak self] in self?.handleRoyaleReveal() }
        window.contentView?.addSubview(label)
        titleLabel = label
    }

    private func installPickerScrollView() {
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 60, width: 528, height: 340))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.drawsBackground = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = DialPickerCell.itemSize
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 12

        let cv = NSCollectionView(frame: scroll.contentView.bounds)
        cv.collectionViewLayout = layout
        cv.allowsMultipleSelection = false
        cv.allowsEmptySelection = false
        cv.isSelectable = true
        cv.backgroundColors = [NSColor.windowBackgroundColor]
        cv.delegate = self
        cv.dataSource = self
        cv.register(DialPickerCell.self, forItemWithIdentifier: DialPickerCell.reuseIdentifier)

        scroll.documentView = cv
        window.contentView?.addSubview(scroll)
        collectionView = cv
    }

    private func installDoneButton() {
        let button = NSButton(title: "Done", target: self, action: #selector(handleDone))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.frame = NSRect(x: 460, y: 16, width: 84, height: 30)
        button.autoresizingMask = [.minXMargin, .maxYMargin]
        window.contentView?.addSubview(button)
        doneButton = button
    }

    // MARK: Picker reload

    /// Re-reads the Royale-reveal flag and rebuilds the visible dial list,
    /// then reloads the collection view and re-selects whichever cell
    /// matches the currently-stored `selectedDialID` (or the fallback).
    func reloadDialList() {
        let includingHidden = DialPreferences.resolveRoyaleRevealed(in: defaults)
        visibleDials = DialRegistry.visible(includingHidden: includingHidden)
        collectionView?.reloadData()
        applyPersistedSelection()
    }

    private func applyPersistedSelection() {
        guard let cv = collectionView else { return }
        let storedID = DialPreferences.storedDialID(in: defaults)
        let resolvedType = DialPreferences.resolveSelectedDialType(id: storedID)
        let idx = visibleDials.firstIndex(where: { $0.identity.id == resolvedType.identity.id }) ?? 0
        let indexPath = IndexPath(item: idx, section: 0)
        cv.selectItems(at: [indexPath], scrollPosition: .nearestVerticalEdge)
    }

    // MARK: Actions

    @objc private func handleDone() {
        onDone?()
    }

    private func handleRoyaleReveal() {
        // Idempotent — if the flag is already true the second click is a
        // no-op (still rewrites + reloads, but visibly nothing changes).
        DialPreferences.writeRoyaleRevealed(true, to: defaults)
        reloadDialList()
    }
}

// MARK: - NSCollectionViewDataSource

extension WatchesPreferencesController: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        visibleDials.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: DialPickerCell.reuseIdentifier,
            for: indexPath
        )
        if let cell = item as? DialPickerCell,
           indexPath.item < visibleDials.count {
            cell.configure(with: visibleDials[indexPath.item])
        }
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension WatchesPreferencesController: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first,
              indexPath.item < visibleDials.count else { return }
        let dial = visibleDials[indexPath.item]
        DialPreferences.writeSelectedDialID(dial.identity.id, to: defaults)
    }
}
