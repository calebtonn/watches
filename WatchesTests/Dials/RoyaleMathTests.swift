import XCTest
@testable import WatchesCore

final class RoyaleMathTests: XCTestCase {

    // MARK: - 7-segment digit topology

    func test_segments_forDigitZero_returnsAllRimSegments() {
        let on = RoyaleMath.segments(forDigit: 0)
        XCTAssertEqual(on, [.top, .topRight, .bottomRight, .bottom, .bottomLeft, .topLeft])
        XCTAssertFalse(on.contains(.middle))
    }

    func test_segments_forDigitOne_returnsRightVerticalOnly() {
        let on = RoyaleMath.segments(forDigit: 1)
        XCTAssertEqual(on, [.topRight, .bottomRight])
    }

    func test_segments_forDigitEight_returnsEverySegment() {
        let on = RoyaleMath.segments(forDigit: 8)
        XCTAssertEqual(on, Set(RoyaleMath.Segment.allCases))
    }

    func test_segments_forOutOfRangeDigit_returnsEmpty() {
        XCTAssertTrue(RoyaleMath.segments(forDigit: -1).isEmpty)
        XCTAssertTrue(RoyaleMath.segments(forDigit: 10).isEmpty)
        XCTAssertTrue(RoyaleMath.segments(forDigit: 99).isEmpty)
    }

    // MARK: - 5×7 pixel-block alphabet

    func test_pixels_forUppercaseLetter_returnsNonEmptyPattern() {
        XCTAssertFalse(RoyaleMath.pixels(forLetter: "A").isEmpty)
        XCTAssertFalse(RoyaleMath.pixels(forLetter: "M").isEmpty)
        XCTAssertFalse(RoyaleMath.pixels(forLetter: "Z").isEmpty)
    }

    func test_pixels_forLowercaseLetter_isCaseInsensitive() {
        XCTAssertEqual(
            RoyaleMath.pixels(forLetter: "m"),
            RoyaleMath.pixels(forLetter: "M")
        )
    }

    func test_pixels_forNonLetter_returnsEmpty() {
        XCTAssertTrue(RoyaleMath.pixels(forLetter: "1").isEmpty)
        XCTAssertTrue(RoyaleMath.pixels(forLetter: "!").isEmpty)
        XCTAssertTrue(RoyaleMath.pixels(forLetter: " ").isEmpty)
    }

    func test_pixels_eachLetterFitsWithin5x7Grid() {
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            for cell in RoyaleMath.pixels(forLetter: letter) {
                XCTAssertTrue(
                    cell.row >= 0 && cell.row < 7,
                    "Letter \(letter) has out-of-range row \(cell.row)"
                )
                XCTAssertTrue(
                    cell.col >= 0 && cell.col < 5,
                    "Letter \(letter) has out-of-range col \(cell.col)"
                )
            }
        }
    }

    // MARK: - Time decomposition

    func test_timeDigits_atOneTwentyThreeFortyFiveUTC_returnsZeroOneTwoThreeFourFive() {
        // 2026-05-13T01:23:45Z
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(
            calendar: cal, year: 2026, month: 5, day: 13,
            hour: 1, minute: 23, second: 45
        )
        let date = cal.date(from: comps)!

        let d = RoyaleMath.timeDigits(from: date, calendar: cal)
        XCTAssertEqual(d.h1, 0)
        XCTAssertEqual(d.h2, 1)
        XCTAssertEqual(d.m1, 2)
        XCTAssertEqual(d.m2, 3)
        XCTAssertEqual(d.s1, 4)
        XCTAssertEqual(d.s2, 5)
    }

    func test_timeDigits_atMidnightUTC_returnsAllZeros() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(
            calendar: cal, year: 2026, month: 1, day: 1,
            hour: 0, minute: 0, second: 0
        )
        let date = cal.date(from: comps)!

        let d = RoyaleMath.timeDigits(from: date, calendar: cal)
        XCTAssertEqual(d.h1, 0); XCTAssertEqual(d.h2, 0)
        XCTAssertEqual(d.m1, 0); XCTAssertEqual(d.m2, 0)
        XCTAssertEqual(d.s1, 0); XCTAssertEqual(d.s2, 0)
    }

    // MARK: - Date decomposition

    func test_dateDigits_atMarchFirst_returnsZeroThreeZeroOne() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(calendar: cal, year: 2026, month: 3, day: 1)
        let date = cal.date(from: comps)!

        let d = RoyaleMath.dateDigits(from: date, calendar: cal)
        XCTAssertEqual(d.mo1, 0)
        XCTAssertEqual(d.mo2, 3)
        XCTAssertEqual(d.d1, 0)
        XCTAssertEqual(d.d2, 1)
    }

    func test_dateDigits_atDecemberThirtyOne_returnsOneTwoThreeOne() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = DateComponents(calendar: cal, year: 2026, month: 12, day: 31)
        let date = cal.date(from: comps)!

        let d = RoyaleMath.dateDigits(from: date, calendar: cal)
        XCTAssertEqual(d.mo1, 1)
        XCTAssertEqual(d.mo2, 2)
        XCTAssertEqual(d.d1, 3)
        XCTAssertEqual(d.d2, 1)
    }

    // MARK: - Day-of-week label

    func test_dayOfWeekLabel_forMondayWithUSLocale_returnsMon() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US")
        // 2026-05-11 is a Monday (verified via NSCalendar).
        let comps = DateComponents(calendar: cal, year: 2026, month: 5, day: 11)
        let date = cal.date(from: comps)!

        XCTAssertEqual(RoyaleMath.dayOfWeekLabel(for: date, calendar: cal), "MON")
    }

    func test_dayOfWeekLabel_forMondayWithGermanLocale_returnsMo() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "de_DE")
        let comps = DateComponents(calendar: cal, year: 2026, month: 5, day: 11)
        let date = cal.date(from: comps)!

        XCTAssertEqual(RoyaleMath.dayOfWeekLabel(for: date, calendar: cal), "MO")
    }

    // MARK: - Subdial analog angles (Story 1.5.2)

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

    func test_subdialHourAngle_atNoon_returnsZero() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 0)
        let angle = RoyaleMath.subdialHourAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, 0, accuracy: Self.angleTolerance)
    }

    func test_subdialHourAngle_at3pm_returnsHalfPi() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 15, minute: 0)
        let angle = RoyaleMath.subdialHourAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi / 2, accuracy: Self.angleTolerance)
    }

    func test_subdialHourAngle_at3pm30min_advancesHalfTowardFour() {
        // 3:30 → hour hand halfway between 3 and 4 positions
        // = π/2 + (π/6)*(30/60) = π/2 + π/12
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 15, minute: 30)
        let angle = RoyaleMath.subdialHourAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi / 2 + .pi / 12, accuracy: Self.angleTolerance)
    }

    func test_subdialMinuteAngle_at30minutes_returnsPi() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 30)
        let angle = RoyaleMath.subdialMinuteAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi, accuracy: Self.angleTolerance)
    }

    func test_subdialMinuteAngle_at30min30sec_advancesHalfTowardNextMinute() {
        // XX:30:30 → minute hand halfway between 30 and 31 positions
        // = π + (π/30)*(30/60) = π + π/60
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 30, second: 30)
        let angle = RoyaleMath.subdialMinuteAngle(from: date, calendar: Self.utcCalendar())
        XCTAssertEqual(angle, .pi + .pi / 60, accuracy: Self.angleTolerance)
    }

    func test_subdialSecondTickIndex_atZeroSeconds_returnsZero() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 30, second: 0)
        XCTAssertEqual(
            RoyaleMath.subdialSecondTickIndex(from: date, calendar: Self.utcCalendar()),
            0
        )
    }

    func test_subdialSecondTickIndex_at59Seconds_returns59() {
        let date = Self.utcDate(year: 2026, month: 5, day: 13, hour: 12, minute: 30, second: 59)
        XCTAssertEqual(
            RoyaleMath.subdialSecondTickIndex(from: date, calendar: Self.utcCalendar()),
            59
        )
    }
}
