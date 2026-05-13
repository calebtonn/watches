import CoreGraphics
import Foundation
import QuartzCore

/// The contract every dial implements.
///
/// **Designed to NOT bake concentric-layout or analog-paradigm assumptions** —
/// see ADR-002 for the rationale. Asymmetric Moonphase (Story 1.6) breaks the
/// concentric assumption; Royale (Story 1.5) breaks the analog assumption. Both
/// must satisfy this protocol without retrofit.
///
/// Renderers are classes (`AnyObject`-constrained) because their state is layer-
/// owning — `CALayer`, `CABasicAnimation`, `CADisplayLink` are all reference-
/// typed. Value semantics would fight Swift's ergonomics for the renderer's
/// natural shape (D2 in the architecture).
public protocol DialRenderer: AnyObject {
    /// Static metadata for the registry and prefs picker.
    static var identity: DialIdentity { get }

    /// Whether the dial appears in the picker by default.
    static var visibility: DialVisibility { get }

    /// Required initializer so the host can instantiate via metatype.
    init()

    /// Called once when the host attaches this renderer.
    ///
    /// - Parameter rootLayer: the dial's exclusive sublayer space. Install
    ///   sublayers here; do not touch `rootLayer`'s parents.
    /// - Parameter canvas: the renderable area in points. Retina handled
    ///   automatically via the layer's `contentsScale`.
    /// - Parameter timeSource: injected; the dial reads time only through it.
    ///   Direct `Date()` / `CACurrentMediaTime()` calls in renderers are
    ///   forbidden (P4 in the architecture).
    func attach(rootLayer: CALayer, canvas: CGSize, timeSource: TimeSource)

    /// Called once per display-link tick.
    ///
    /// - Parameter reduceMotion: when `true`, the dial reduces animation per
    ///   its `notes.md` reduce-motion contract (P7). Sweep → tick, ambient
    ///   animations freeze.
    /// - Returns: the dirty regions to invalidate this frame. Empty array
    ///   means no redraw needed (NFR1 efficiency).
    @discardableResult
    func tick(reduceMotion: Bool) -> [CGRect]

    /// Called when the host's canvas size changes (display change, prefs
    /// preview resize). The dial re-lays out sublayers for the new size.
    func canvasDidChange(to canvas: CGSize)

    /// Called when the host detaches the renderer. Remove sublayers,
    /// invalidate any timers or observers owned by the renderer.
    func detach()
}

/// Static metadata for a dial: identity, display name, credit, preview asset.
public struct DialIdentity {
    /// Stable identifier matching the camelCase form of the type prefix.
    /// e.g. `AsymmetricMoonphaseRenderer` → `"asymmetricMoonphase"`.
    /// Persisted as `selectedDialID` in `ScreenSaverDefaults`.
    public let id: String

    /// Human-readable label shown in the prefs picker.
    public let displayName: String

    /// One-sentence inline credit. Used in the prefs pane and the README.
    /// e.g. `"Inspired by the A. Lange & Söhne Lange 1 Moonphase"`.
    public let homageCredit: String

    /// Bundle resource name for the picker thumbnail (Story 3.1).
    /// Empty string indicates no thumbnail (hidden dials).
    public let previewAssetName: String

    public init(id: String, displayName: String, homageCredit: String, previewAssetName: String) {
        self.id = id
        self.displayName = displayName
        self.homageCredit = homageCredit
        self.previewAssetName = previewAssetName
    }
}

/// Default visibility means the dial appears in the picker normally.
/// Hidden dials require the reveal gesture (Story 3.2; Royale uses this).
public enum DialVisibility {
    case `default`
    case hidden
}
