import Foundation

/// Defaults keys + pure resolvers for the per-user dial preferences
/// (Story 3.1 dial picker + Story 3.2 Royale reveal).
///
/// Lives in `WatchesCore` so XCTest can reach it (D12 / ADR-001). The
/// actual `ScreenSaverDefaults` plumbing happens in the `Watches` bundle
/// — these helpers take an opaque `defaults` parameter so unit tests can
/// pass a plain `UserDefaults` instance.
public enum DialPreferences {

    // MARK: Defaults keys (also documented for `defaults` CLI use)

    /// Dial picker selection. Value: `String` matching a registered
    /// `DialIdentity.id`. Missing/unknown values fall back to
    /// `fallbackDialID`.
    public static let selectedDialIDKey = "selectedDialID"

    /// Royale easter-egg reveal flag. Value: `Bool`. Missing key is
    /// treated as `false`.
    public static let royaleRevealedKey = "royaleRevealed"

    /// Picker fallback when the persisted ID is missing, empty, or names
    /// a dial no longer in the registry.
    public static let fallbackDialID = "asymmetricMoonphase"

    // MARK: Resolvers (pure functions — tests pass any DefaultsBacking)

    /// Resolves `selectedDialID` to a concrete `DialRenderer.Type` from
    /// the registry. Returns the fallback type if the ID is missing,
    /// empty, or unregistered.
    ///
    /// - Parameter id: the raw value read from defaults.
    /// - Parameter registry: the dial registry to look up in. Defaults to
    ///   the live `DialRegistry`; tests can pass a different collection.
    /// - Returns: the resolved dial type. NEVER returns nil — the fallback
    ///   path is guaranteed because `fallbackDialID` is always present in
    ///   `DialRegistry.all` (compile-time invariant; we crash early at
    ///   install if it's ever removed, per the "fallback must exist" rule).
    public static func resolveSelectedDialType(
        id: String?,
        registry: [DialRenderer.Type] = DialRegistry.all
    ) -> DialRenderer.Type {
        if let id = id, !id.isEmpty,
           let match = registry.first(where: { $0.identity.id == id }) {
            return match
        }
        if let fallback = registry.first(where: { $0.identity.id == fallbackDialID }) {
            return fallback
        }
        // No fallback in the registry — this is an unrecoverable
        // configuration error. Return the first registered dial so the
        // screensaver at least shows SOMETHING; log via the caller (host).
        // Per P10 we don't fatalError; we degrade gracefully.
        return registry[0]
    }

    /// Returns true when the Royale-reveal flag is explicitly set in the
    /// provided defaults; false otherwise (including the missing-key case).
    public static func resolveRoyaleRevealed(in defaults: DefaultsBacking) -> Bool {
        defaults.bool(forKey: royaleRevealedKey)
    }

    /// Returns the persisted dial ID, or nil if the key is missing/empty.
    public static func storedDialID(in defaults: DefaultsBacking) -> String? {
        let raw = defaults.string(forKey: selectedDialIDKey)
        return (raw?.isEmpty == false) ? raw : nil
    }

    /// Writes the selected dial ID and flushes defaults. The flush matters
    /// because System Settings hosts the prefs pane in a different process
    /// than the running screensaver — without `synchronize`, the running
    /// screensaver wouldn't see the update on its next install cycle.
    public static func writeSelectedDialID(_ id: String, to defaults: DefaultsBacking) {
        defaults.set(id, forKey: selectedDialIDKey)
        defaults.synchronizeForCrossProcessRead()
    }

    /// Writes the Royale-revealed flag.
    public static func writeRoyaleRevealed(_ revealed: Bool, to defaults: DefaultsBacking) {
        defaults.set(revealed, forKey: royaleRevealedKey)
        defaults.synchronizeForCrossProcessRead()
    }
}

/// Minimal abstraction over `UserDefaults`/`ScreenSaverDefaults` so the
/// pure resolvers above stay testable. Both `UserDefaults` and
/// `ScreenSaverDefaults` (NSUserDefaults subclass) satisfy this protocol
/// once we add the synchronize shim below.
public protocol DefaultsBacking: AnyObject {
    func string(forKey: String) -> String?
    func bool(forKey: String) -> Bool
    func set(_ value: Any?, forKey: String)
    func synchronizeForCrossProcessRead()
}

extension UserDefaults: DefaultsBacking {
    /// `synchronize()` is technically deprecated for app-internal use but
    /// remains the documented mechanism for cross-process defaults
    /// visibility — and ScreenSaverDefaults explicitly needs it because
    /// the screensaver and System Settings run in different processes.
    public func synchronizeForCrossProcessRead() {
        synchronize()
    }
}
