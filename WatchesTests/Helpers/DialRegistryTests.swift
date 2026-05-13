import XCTest
@testable import WatchesCore

/// Tests `DialRegistry` — the static dial-type registry used by the host to
/// instantiate renderers and by the prefs picker (Story 3.1) to enumerate
/// visible dials.
final class DialRegistryTests: XCTestCase {

    // MARK: byID()

    func test_byID_proofOfHost_returnsProofOfHostRenderer() {
        let type = DialRegistry.byID("proofOfHost")
        XCTAssertNotNil(type)
        XCTAssertTrue(type == ProofOfHostRenderer.self)
    }

    func test_byID_unknownID_returnsNil() {
        XCTAssertNil(DialRegistry.byID("nonexistent"))
    }

    func test_byID_emptyString_returnsNil() {
        XCTAssertNil(DialRegistry.byID(""))
    }

    // MARK: visible()

    func test_visible_excludingHidden_omitsProofOfHost() {
        let visible = DialRegistry.visible(includingHidden: false)
        XCTAssertFalse(
            visible.contains { $0.identity.id == "proofOfHost" },
            "Hidden proof-of-host dial should not appear in default picker."
        )
    }

    func test_visible_includingHidden_includesProofOfHost() {
        let visible = DialRegistry.visible(includingHidden: true)
        XCTAssertTrue(
            visible.contains { $0.identity.id == "proofOfHost" },
            "Including hidden, proof-of-host should appear in the list."
        )
    }
}
