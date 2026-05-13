import ScreenSaver
import QuartzCore

/// Principal class for the Watches screen saver bundle.
///
/// Hosts the active `DialRenderer`, drives the draw loop via `CADisplayLink`,
/// adapts frame rate to low-power mode, and forwards reduce-motion state to
/// the renderer each tick.
///
/// Story 1.2: host + protocol + proof-of-host dial.
/// Story 1.3 adds: Sonoma `legacyScreenSaver` exit-bug workaround (ExitWatchdog).
/// Story 3.1 adds: read selected dial from `ScreenSaverDefaults` (currently
///                 hardcoded to proof-of-host).
final class WatchesScreenSaverView: ScreenSaverView {

    // MARK: Collaborators

    private let timeSource: TimeSource = SystemTimeSource()
    private let reduceMotion = ReduceMotionObserver()
    private var renderer: DialRenderer?
    private var displayLink: CADisplayLink?
    private var powerStateObserver: NSObjectProtocol?

    // MARK: Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsScale = backingScaleFactorBestGuess()

        installRenderer()
        observePowerState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // .saver bundles are not instantiated from nibs/storyboards.
        // The NSCoding initializer must exist syntactically (Swift requirement)
        // but is never invoked at runtime. This is one of the rare permitted
        // uses of fatalError per project pattern P10.
        fatalError("init(coder:) is not supported for .saver bundles")
    }

    deinit {
        if let token = powerStateObserver {
            NotificationCenter.default.removeObserver(token)
        }
        displayLink?.invalidate()
        renderer?.detach()
    }

    // MARK: ScreenSaverView overrides

    override func startAnimation() {
        super.startAnimation()
        startDisplayLink()
        Logging.host.info("startAnimation: display link started")
    }

    override func stopAnimation() {
        super.stopAnimation()
        stopDisplayLink()
        Logging.host.info("stopAnimation: display link stopped")
    }

    override func draw(_ rect: NSRect) {
        // Intentionally empty — rendering happens via CALayer on the display-link tick.
        // Overridden to suppress ScreenSaverView's default background draw.
    }

    override func layout() {
        super.layout()
        layer?.contentsScale = backingScaleFactorBestGuess()
        renderer?.canvasDidChange(to: bounds.size)
    }

    // MARK: Renderer wiring

    private func installRenderer() {
        // Story 1.2 hardcodes the proof-of-host dial.
        // Story 3.1 will replace this with a `ScreenSaverDefaults` read,
        // with fallback to a registered dial if the ID is unknown (P10).
        guard let dialType = DialRegistry.byID("proofOfHost") else {
            Logging.host.error("Default dial 'proofOfHost' not registered; rendering blank canvas.")
            return
        }

        let dial = dialType.init()
        let host = layer ?? CALayer()
        dial.attach(rootLayer: host, canvas: bounds.size, timeSource: timeSource)
        self.renderer = dial

        Logging.host.info("Installed renderer: \(dialType.identity.displayName, privacy: .public)")
    }

    // MARK: Display link

    private func startDisplayLink() {
        stopDisplayLink()  // idempotent

        // macOS-specific: use NSView.displayLink(target:selector:), not
        // CADisplayLink.init(target:selector:) (the latter is iOS-only on
        // current SDKs). NSView's method returns a properly-scoped CADisplayLink
        // attached to this view's display.
        let link = self.displayLink(
            target: self,
            selector: #selector(displayLinkDidFire(_:))
        )
        link.preferredFrameRateRange = currentFrameRateRange()
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkDidFire(_ sender: CADisplayLink) {
        _ = renderer?.tick(reduceMotion: reduceMotion.isEnabled)
    }

    // MARK: Power state

    private func observePowerState() {
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let range = self.currentFrameRateRange()
            self.displayLink?.preferredFrameRateRange = range
            // os.Logger interpolation does not support Float directly; cast to Int.
            // `preferred` is Float? on macOS (0 indicates "no preferred rate"); use 0 default.
            let preferredFps = Int(range.preferred ?? 0)
            Logging.host.info(
                "Power state changed; frame rate range now [\(Int(range.minimum))-\(Int(range.maximum))] preferred=\(preferredFps)"
            )
        }
    }

    private func currentFrameRateRange() -> CAFrameRateRange {
        ProcessInfo.processInfo.isLowPowerModeEnabled
            ? CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
            : CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
    }

    // MARK: Helpers

    private func backingScaleFactorBestGuess() -> CGFloat {
        window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }
}
