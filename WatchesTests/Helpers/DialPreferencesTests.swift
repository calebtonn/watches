import XCTest
@testable import WatchesCore

/// Tests `DialPreferences` — the user-defaults helpers behind the prefs
/// picker (Story 3.1) and Royale reveal flag (Story 3.2). The resolvers
/// are pure functions that take a `DefaultsBacking` and a registry; tests
/// pass an in-memory `UserDefaults(suiteName:)` instance and a synthetic
/// registry so nothing leaks across test runs.
final class DialPreferencesTests: XCTestCase {

    // MARK: Test scaffolding

    /// Fresh in-memory defaults per test. Using a unique suite name per
    /// test method avoids cross-test interference even if `synchronize`
    /// flushes to disk on the CI runner.
    private func makeDefaults(name: String = #function) -> UserDefaults {
        let suite = "watches.tests.DialPreferences." + name
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: resolveSelectedDialType — happy path

    func test_resolveSelectedDialType_knownID_returnsMatchingType() {
        let type = DialPreferences.resolveSelectedDialType(id: "asymmetricMoonphase")
        XCTAssertTrue(type == AsymmetricMoonphaseRenderer.self)
    }

    func test_resolveSelectedDialType_anotherKnownID_returnsRoyale() {
        let type = DialPreferences.resolveSelectedDialType(id: "royale")
        XCTAssertTrue(type == RoyaleRenderer.self)
    }

    // MARK: resolveSelectedDialType — fallback path

    func test_resolveSelectedDialType_nilID_returnsFallback() {
        let type = DialPreferences.resolveSelectedDialType(id: nil)
        XCTAssertEqual(type.identity.id, DialPreferences.fallbackDialID)
    }

    func test_resolveSelectedDialType_emptyString_returnsFallback() {
        let type = DialPreferences.resolveSelectedDialType(id: "")
        XCTAssertEqual(type.identity.id, DialPreferences.fallbackDialID)
    }

    func test_resolveSelectedDialType_unknownID_returnsFallback() {
        let type = DialPreferences.resolveSelectedDialType(id: "definitelyNotADial")
        XCTAssertEqual(type.identity.id, DialPreferences.fallbackDialID)
    }

    func test_resolveSelectedDialType_fallbackIsAsymmetricMoonphase() {
        XCTAssertEqual(DialPreferences.fallbackDialID, "asymmetricMoonphase")
    }

    // MARK: storedDialID — read path

    func test_storedDialID_missingKey_returnsNil() {
        let d = makeDefaults()
        XCTAssertNil(DialPreferences.storedDialID(in: d))
    }

    func test_storedDialID_emptyString_returnsNil() {
        let d = makeDefaults()
        d.set("", forKey: DialPreferences.selectedDialIDKey)
        XCTAssertNil(DialPreferences.storedDialID(in: d))
    }

    func test_storedDialID_setValue_roundTrips() {
        let d = makeDefaults()
        DialPreferences.writeSelectedDialID("royale", to: d)
        XCTAssertEqual(DialPreferences.storedDialID(in: d), "royale")
    }

    // MARK: Royale-reveal flag

    func test_resolveRoyaleRevealed_missingKey_returnsFalse() {
        let d = makeDefaults()
        XCTAssertFalse(DialPreferences.resolveRoyaleRevealed(in: d))
    }

    func test_resolveRoyaleRevealed_writeTrue_returnsTrue() {
        let d = makeDefaults()
        DialPreferences.writeRoyaleRevealed(true, to: d)
        XCTAssertTrue(DialPreferences.resolveRoyaleRevealed(in: d))
    }

    func test_resolveRoyaleRevealed_writeFalse_returnsFalse() {
        let d = makeDefaults()
        // Pre-seed to true so writing false is observably effective.
        DialPreferences.writeRoyaleRevealed(true, to: d)
        DialPreferences.writeRoyaleRevealed(false, to: d)
        XCTAssertFalse(DialPreferences.resolveRoyaleRevealed(in: d))
    }
}
