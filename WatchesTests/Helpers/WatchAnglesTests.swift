import XCTest
@testable import WatchesCore

/// Tests `WatchAngles` — the watch-position → CG-rotation-radian helper.
///
/// Convention reminder (per architecture P3): returned values are CG-rotation-
/// ready radians, NEGATED from watch-convention so that applying them via
/// `CGAffineTransform(rotationAngle:)` in a Y-up coordinate space produces
/// visually-clockwise rotation. Tests assert against the negated form.
final class WatchAnglesTests: XCTestCase {

    // MARK: second()

    func test_second_atZero_returnsZero() {
        XCTAssertEqual(WatchAngles.second(0), 0, accuracy: 1e-10)
    }

    func test_second_at15_returnsNegativeHalfPi() {
        // 15 seconds is the 3 o'clock position.
        // CG-rotation convention (Y-up): -π/2 produces visually-clockwise 90°.
        XCTAssertEqual(Double(WatchAngles.second(15)), -.pi / 2, accuracy: 1e-10)
    }

    func test_second_at30_returnsNegativePi() {
        XCTAssertEqual(Double(WatchAngles.second(30)), -.pi, accuracy: 1e-10)
    }

    func test_second_at45_returnsNegativeThreeHalvesPi() {
        XCTAssertEqual(Double(WatchAngles.second(45)), -1.5 * .pi, accuracy: 1e-10)
    }

    func test_second_at60_wrapsToZero() {
        // truncatingRemainder(dividingBy: 60) makes 60 → 0
        XCTAssertEqual(WatchAngles.second(60), 0, accuracy: 1e-10)
    }

    func test_second_atFractional_returnsProportionalAngle() {
        // Just under wrap — should be close to but not exactly 0.
        let angle = Double(WatchAngles.second(59.999))
        XCTAssertEqual(angle, -59.999 / 60 * 2 * .pi, accuracy: 1e-10)
    }

    // MARK: minute()

    func test_minute_atZero_returnsZero() {
        XCTAssertEqual(WatchAngles.minute(0), 0, accuracy: 1e-10)
    }

    func test_minute_at30_returnsNegativePi() {
        XCTAssertEqual(Double(WatchAngles.minute(30)), -.pi, accuracy: 1e-10)
    }

    func test_minute_at30_withSecond30_advancesHalfwayToNextMinute() {
        // 30 min + 30 sec = 30.5 of 60 minutes.
        let expected = -30.5 / 60 * 2 * .pi
        XCTAssertEqual(Double(WatchAngles.minute(30, second: 30)), expected, accuracy: 1e-10)
    }

    // MARK: hour()

    func test_hour_atZero_returnsZero() {
        XCTAssertEqual(WatchAngles.hour(0), 0, accuracy: 1e-10)
    }

    func test_hour_at3_returnsNegativeHalfPi() {
        XCTAssertEqual(Double(WatchAngles.hour(3)), -.pi / 2, accuracy: 1e-10)
    }

    func test_hour_at12_wrapsToZero() {
        // truncatingRemainder(dividingBy: 12) makes 12 → 0
        XCTAssertEqual(WatchAngles.hour(12), 0, accuracy: 1e-10)
    }

    func test_hour_at3_withMinute30_returnsThreeThirtyPosition() {
        // 3.5 of 12 hours.
        let expected = -3.5 / 12.0 * 2 * .pi
        XCTAssertEqual(Double(WatchAngles.hour(3, minute: 30)), expected, accuracy: 1e-10)
    }

    // MARK: Edge cases captured for deferred-work follow-up

    /// Documents the current behavior of negative input. Per Story 1.3
    /// review-defer item: `WatchAngles.second(-1)` returns a *positive*
    /// small angle (because `truncatingRemainder` preserves sign and the
    /// helper negates the result, so a negative input becomes positive
    /// output). ProofOfHostRenderer never passes negative values today
    /// (it reads from `Calendar.dateComponents`, which returns non-negative
    /// integers). When a future delta-time consumer arrives (Story 1.5+),
    /// rename this test to `..._returnsNormalizedClockwiseAngle()` and
    /// flip the expected value to `WatchAngles.second(59)` form.
    func test_second_negativeInput_currentBehavior_returnsPositiveSmall() {
        // truncatingRemainder(-1, by: 60) = -1; helper negates → +1/60 * 2π.
        let angle = Double(WatchAngles.second(-1))
        XCTAssertEqual(angle, 1.0 / 60 * 2 * .pi, accuracy: 1e-10)
    }
}
