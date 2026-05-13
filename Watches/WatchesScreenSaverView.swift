import ScreenSaver

/// Principal class for the Watches screen saver bundle.
///
/// This is a stub for Story 1.1 (scaffold). Story 1.2 installs the
/// `DialRenderer` protocol, time source, registry, and proof-of-host dial.
/// Story 1.3 adds the Sonoma `legacyScreenSaver` exit-bug workaround.
final class WatchesScreenSaverView: ScreenSaverView {

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // Story 1.2 will install the renderer + display link here.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // .saver bundles are not instantiated from nibs/storyboards.
        // The NSCoding initializer must exist syntactically (Swift requirement)
        // but is never invoked at runtime. This is one of the rare permitted
        // uses of fatalError per project pattern P10.
        fatalError("init(coder:) is not supported for .saver bundles")
    }
}
