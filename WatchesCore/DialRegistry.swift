import AppKit
import Foundation

/// Static registry of all `DialRenderer` types in the bundle.
///
/// Stories 1.5+ append entries to `all` as each dial lands. Per D6 in the
/// architecture: manual registration (no reflection, no folder-scan) keeps
/// Swift 5 simple and the dial order predictable.
///
/// The host instantiates dials via `init()` on the metatype, so each
/// renderer's `DialRenderer.init()` runs to produce the per-display instance.
public enum DialRegistry {

    /// All registered dial types, in picker order (Story 3.1).
    public static let all: [DialRenderer.Type] = [
        ProofOfHostRenderer.self,
        RoyaleRenderer.self,
        AsymmetricMoonphaseRenderer.self,
        CokeGMTRenderer.self,
        // Story 2.2: + OctagonRenderer.self
        // Story 2.3: + MoonchronoRenderer.self
        // Story 2.4: + DiverRenderer.self
    ]

    /// Returns dial types whose visibility matches the filter.
    /// `includingHidden: false` excludes `.hidden` dials (default for the
    /// user-facing picker). `includingHidden: true` returns all dials.
    public static func visible(includingHidden: Bool) -> [DialRenderer.Type] {
        all.filter { $0.visibility == .default || includingHidden }
    }

    /// Looks up a registered dial type by its `identity.id`. Returns `nil` if
    /// no dial with that ID is registered. Used by the host to resolve the
    /// user's `selectedDialID` from `ScreenSaverDefaults`.
    public static func byID(_ id: String) -> DialRenderer.Type? {
        all.first { $0.identity.id == id }
    }

    /// Loads the picker thumbnail for a registered dial from its home bundle.
    /// Returns `nil` if `previewAssetName` is empty (hidden dials marked as
    /// "no thumbnail") or if the resource can't be found.
    ///
    /// Per the per-dial-unique-filename convention established in Story 1.6,
    /// the `previewAssetName` matches the actual PNG filename on disk (e.g.
    /// `"royale-preview"` → `royale-preview.png` in the Royale source dir).
    public static func previewImage(for dialType: DialRenderer.Type) -> NSImage? {
        let name = dialType.identity.previewAssetName
        guard !name.isEmpty else { return nil }
        // `DialRenderer: AnyObject` — all conformers are classes, so the
        // cast to AnyClass is always safe.
        let cls: AnyClass = dialType as AnyClass
        return Bundle(for: cls).image(forResource: name)
    }
}
