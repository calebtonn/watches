import AppKit
import QuartzCore

/// Minimal proof-of-host dial: a circle outline + ticking second hand.
///
/// Exists to validate the `DialRenderer` protocol surface end-to-end before
/// any real dial lands. Visibility is `.hidden` — users never see it in the
/// picker. May be removed in a future story once Royale (1.5) and Asymmetric
/// Moonphase (1.6) prove the protocol against the two hardest stress cases.
public final class ProofOfHostRenderer: DialRenderer {

    // MARK: DialRenderer static metadata

    public static let identity = DialIdentity(
        id: "proofOfHost",
        displayName: "Proof of Host",
        homageCredit: "Internal developer dial; no horological inspiration.",
        previewAssetName: ""    // no thumbnail; not user-visible
    )

    public static let visibility: DialVisibility = .hidden

    // MARK: State

    private weak var rootLayer: CALayer?
    private var canvas: CGSize = .zero
    private var timeSource: TimeSource?

    private let circleLayer = CAShapeLayer()
    private let secondHandLayer = CAShapeLayer()

    /// Last integer-second value rendered. Used by `tick(reduceMotion:)` under
    /// reduce-motion mode to suppress redundant transform updates when the
    /// integer second has not advanced.
    private var lastRenderedSecond: Int?

    // MARK: Init

    public init() {
        // No setup here; the host calls attach() with everything we need.
    }

    // MARK: DialRenderer

    public func attach(rootLayer: CALayer, canvas: CGSize, timeSource: TimeSource) {
        self.rootLayer = rootLayer
        self.canvas = canvas
        self.timeSource = timeSource

        installLayers()
        layoutLayers(for: canvas)

        // Apply the correct rotation immediately so the FIRST visible frame
        // shows the hand at the current-time position — not the identity-
        // transform default (12 o'clock). Caught visually in Story 1.4
        // verification: previously the hand rendered at 12 then jumped to
        // its correct angle on the first display-link tick.
        // `reduceMotion: false` here is fine — the difference between sweep
        // and snap modes at attach time is sub-pixel.
        _ = tick(reduceMotion: false)
    }

    @discardableResult
    public func tick(reduceMotion: Bool) -> [CGRect] {
        guard let timeSource else { return [] }

        // Decompose to seconds-with-subsecond once per tick (P4 — through TimeSource only).
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.second, .nanosecond], from: timeSource.now
        )
        let secondValue = Double(components.second ?? 0)
                        + Double(components.nanosecond ?? 0) / 1_000_000_000

        // Reduce-motion contract: hand truly ticks at 1 FPS — skip the transform
        // update entirely when the integer second has not advanced. Avoids 30 redundant
        // transform writes per second to the same angle. (P7, addressed in Story 1.2 review.)
        if reduceMotion {
            let integerSecond = Int(floor(secondValue))
            if integerSecond == lastRenderedSecond {
                return []   // nothing changed; no dirty rects
            }
            lastRenderedSecond = integerSecond
            let angle = WatchAngles.second(Double(integerSecond))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            secondHandLayer.setAffineTransform(.init(rotationAngle: angle))
            CATransaction.commit()
            return [secondHandLayer.frame]
        }

        // Normal mode: sweep with sub-second precision.
        lastRenderedSecond = nil   // reset so reduce-motion can re-arm on toggle
        let angle = WatchAngles.second(secondValue)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        secondHandLayer.setAffineTransform(.init(rotationAngle: angle))
        CATransaction.commit()
        return [secondHandLayer.frame]
    }

    public func canvasDidChange(to canvas: CGSize) {
        self.canvas = canvas
        layoutLayers(for: canvas)
    }

    public func detach() {
        circleLayer.removeFromSuperlayer()
        secondHandLayer.removeFromSuperlayer()
        rootLayer = nil
        timeSource = nil
    }

    // MARK: Layer construction

    private func installLayers() {
        guard let rootLayer else { return }

        // Suppress implicit animations on the initial setup so the first frame
        // doesn't fade in over ~0.25s. Caught visually in Story 1.4 verification.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        circleLayer.name = "proofOfHost.circle"
        circleLayer.strokeColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).cgColor
        circleLayer.fillColor = nil
        circleLayer.lineWidth = 2

        secondHandLayer.name = "proofOfHost.secondHand"
        secondHandLayer.strokeColor = NSColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1).cgColor
        secondHandLayer.fillColor = nil
        secondHandLayer.lineWidth = 2
        secondHandLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)  // rotate around base

        rootLayer.addSublayer(circleLayer)
        rootLayer.addSublayer(secondHandLayer)
    }

    private func layoutLayers(for canvas: CGSize) {
        // Guard against degenerate canvas sizes. ScreenSaverView can instantiate
        // with NSRect.zero in preview-thumbnail or first-load paths; we skip
        // layout until a real size arrives via `canvasDidChange`.
        guard canvas.width > 0, canvas.height > 0 else { return }

        // Suppress implicit animations on geometry changes (frame/position/bounds
        // are all animatable by default).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let radius = min(canvas.width, canvas.height) * 0.4

        // Circle outline
        let circleRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        circleLayer.frame = rootLayer?.bounds ?? .zero
        circleLayer.path = CGPath(ellipseIn: circleRect, transform: nil)

        // Second hand: base at center, tip pointing up by default (0 rad = 12 o'clock).
        let handLength = radius * 0.9
        let handPath = CGMutablePath()
        handPath.move(to: .zero)
        handPath.addLine(to: CGPoint(x: 0, y: handLength))
        secondHandLayer.path = handPath
        secondHandLayer.position = center
        secondHandLayer.bounds = CGRect(x: -2, y: 0, width: 4, height: handLength)
    }
}
