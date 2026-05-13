import XCTest
@testable import WatchesCore

/// Tests `FixedTimeSource` — the test fixture for renderer time injection.
///
/// `SystemTimeSource` is deliberately NOT tested here: it wraps `Date()` and
/// `CACurrentMediaTime()`, both non-deterministic and impure. Testing them
/// would violate ADR-001 / D12 (the test boundary).
final class FixedTimeSourceTests: XCTestCase {

    func test_init_storesNowAndMonotonic() {
        let reference = Date(timeIntervalSince1970: 1000)
        let source = FixedTimeSource(now: reference, monotonic: 100)
        XCTAssertEqual(source.now, reference)
        XCTAssertEqual(source.monotonic, 100, accuracy: 1e-10)
    }

    func test_init_defaultMonotonicIsZero() {
        let source = FixedTimeSource(now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(source.monotonic, 0, accuracy: 1e-10)
    }

    func test_advance_movesBothNowAndMonotonic() {
        let reference = Date(timeIntervalSince1970: 1000)
        let source = FixedTimeSource(now: reference, monotonic: 0)
        source.advance(by: 5)
        XCTAssertEqual(source.now, reference.addingTimeInterval(5))
        XCTAssertEqual(source.monotonic, 5, accuracy: 1e-10)
    }

    func test_advance_zeroIntervalIsNoop() {
        let reference = Date(timeIntervalSince1970: 1000)
        let source = FixedTimeSource(now: reference, monotonic: 100)
        source.advance(by: 0)
        XCTAssertEqual(source.now, reference)
        XCTAssertEqual(source.monotonic, 100, accuracy: 1e-10)
    }

    func test_advance_calledMultipleTimes_accumulates() {
        let reference = Date(timeIntervalSince1970: 1000)
        let source = FixedTimeSource(now: reference, monotonic: 0)
        source.advance(by: 2)
        source.advance(by: 3)
        XCTAssertEqual(source.now, reference.addingTimeInterval(5))
        XCTAssertEqual(source.monotonic, 5, accuracy: 1e-10)
    }
}
