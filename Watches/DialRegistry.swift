import Foundation

/// Static registry of all `DialRenderer` types in the bundle.
///
/// Stories 1.5+ append entries to `all` as each dial lands. Per D6 in the
/// architecture: manual registration (no reflection, no folder-scan) keeps
/// Swift 5 simple and the dial order predictable.
///
/// The host instantiates dials via `init()` on the metatype, so each
/// renderer's `DialRenderer.init()` runs to produce the per-display instance.
enum DialRegistry {

    /// All registered dial types, in picker order (Story 3.1).
    static let all: [DialRenderer.Type] = [
        ProofOfHostRenderer.self,
        // Story 1.5: + RoyaleRenderer.self
        // Story 1.6: + AsymmetricMoonphaseRenderer.self
        // Story 2.1: + CokeGMTRenderer.self
        // Story 2.2: + OctagonRenderer.self
        // Story 2.3: + MoonchronoRenderer.self
        // Story 2.4: + DiverRenderer.self
    ]

    /// Returns dial types whose visibility matches the filter.
    /// `includingHidden: false` excludes `.hidden` dials (default for the
    /// user-facing picker). `includingHidden: true` returns all dials.
    static func visible(includingHidden: Bool) -> [DialRenderer.Type] {
        all.filter { $0.visibility == .default || includingHidden }
    }

    /// Looks up a registered dial type by its `identity.id`. Returns `nil` if
    /// no dial with that ID is registered. Used by the host to resolve the
    /// user's `selectedDialID` from `ScreenSaverDefaults`.
    static func byID(_ id: String) -> DialRenderer.Type? {
        all.first { $0.identity.id == id }
    }
}
