import XCTest
@testable import WatchesCore

final class AsymmetricMoonphaseMathTests: XCTestCase {

    // MARK: - Helpers

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func utcDate(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0
    ) -> Date {
        let cal = utcCalendar()
        let comps = DateComponents(
            calendar: cal, year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return cal.date(from: comps)!
    }

    private static let angleTolerance: CGFloat = 1e-9

    // MARK: - Moonphase

    func test_moonPhaseFraction_atKnownNewMoon_returnsNearZero() {
        // 2000-01-06 18:14 UTC was a documented new moon.
        let date = Date(timeIntervalSince1970: 947182440)
        let fraction = AsymmetricMoonphaseMath.moonPhaseFraction(for: date)
        // Should be exactly 0 since this IS the reference epoch.
        XCTAssertEqual(fraction, 0.0, accuracy: 1e-12)
    }

    func test_moonPhaseFraction_atFifteenDaysAfterNewMoon_returnsAboutHalf() {
        // ~15 days past the reference new moon = near full moon (fraction ≈ 0.5).
        // The synodic month is 29.53 days, so 14.77 days = exactly 0.5.
        let reference = Date(timeIntervalSince1970: 947182440)
        let halfCycle = AsymmetricMoonphaseMath.synodicMonthSeconds / 2.0
        let halfMoonDate = reference.addingTimeInterval(halfCycle)
        let fraction = AsymmetricMoonphaseMath.moonPhaseFraction(for: halfMoonDate)
        XCTAssertEqual(fraction, 0.5, accuracy: 1e-9)
    }

    func test_moonPhaseFraction_atOneFullCycle_returnsNearZero() {
        // Exactly one synodic month after the reference new moon — should be
        // back to phase 0 (next new moon).
        let reference = Date(timeIntervalSince1970: 947182440)
        let oneCycle = AsymmetricMoonphaseMath.synodicMonthSeconds
        let nextNewMoon = reference.addingTimeInterval(oneCycle)
        let fraction = AsymmetricMoonphaseMath.moonPhaseFraction(for: nextNewMoon)
        // truncatingRemainder of 1.0 by 1.0 == 0.0
        XCTAssertEqual(fraction, 0.0, accuracy: 1e-9)
    }

    func test_moonPhaseFraction_beforeReferenceEpoch_returnsValidFraction() {
        // Before the reference epoch the elapsed time is negative; the
        // `if fraction < 0 { fraction += 1.0 }` clamp keeps the result in [0,1).
        let beforeReference = Date(timeIntervalSince1970: 947182440 - 100_000)
        let fraction = AsymmetricMoonphaseMath.moonPhaseFraction(for: beforeReference)
        XCTAssertGreaterThanOrEqual(fraction, 0.0)
        XCTAssertLessThan(fraction, 1.0)
    }

    // MARK: - Hand angles

    func test_mainTimeHourAngle_atNoon_returnsZero() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let angle = AsymmetricMoonphaseMath.mainTimeHourAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, 0, accuracy: Self.angleTolerance)
    }

    func test_mainTimeHourAngle_at3pm_returnsHalfPi() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 15, minute: 0)
        let angle = AsymmetricMoonphaseMath.mainTimeHourAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi / 2, accuracy: Self.angleTolerance)
    }

    func test_mainTimeMinuteAngle_at30minutes_returnsPi() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 30)
        let angle = AsymmetricMoonphaseMath.mainTimeMinuteAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi, accuracy: Self.angleTolerance)
    }

    func test_subSecondsAngle_at30seconds_returnsPi() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0, second: 30)
        let angle = AsymmetricMoonphaseMath.subSecondsAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi, accuracy: Self.angleTolerance)
    }

    // MARK: - Big date

    func test_bigDateDigits_atFirstOfMonth_returnsZeroOne() {
        let date = Self.utcDate(year: 2026, month: 1, day: 1)
        let digits = AsymmetricMoonphaseMath.bigDateDigits(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(digits.d1, 0)
        XCTAssertEqual(digits.d2, 1)
    }

    func test_bigDateDigits_atTwentyFifth_returnsTwoFive() {
        let date = Self.utcDate(year: 2026, month: 5, day: 25)
        let digits = AsymmetricMoonphaseMath.bigDateDigits(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(digits.d1, 2)
        XCTAssertEqual(digits.d2, 5)
    }

    func test_bigDateDigits_atThirtyFirst_returnsThreeOne() {
        let date = Self.utcDate(year: 2026, month: 1, day: 31)
        let digits = AsymmetricMoonphaseMath.bigDateDigits(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(digits.d1, 3)
        XCTAssertEqual(digits.d2, 1)
    }

    // MARK: - Power reserve

    func test_powerReserveFraction_returnsValueInValidRange() {
        // Whatever the test host returns (battery on a laptop, 1.0 on a
        // desktop, 1.0 on error), it MUST be in [0, 1] per the contract.
        let fraction = AsymmetricMoonphaseMath.powerReserveFraction()
        XCTAssertGreaterThanOrEqual(fraction, 0.0)
        XCTAssertLessThanOrEqual(fraction, 1.0)
    }
}
