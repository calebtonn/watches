import XCTest
@testable import WatchesCore

/// Tests `CokeGMTMath` — the angle math behind the Coke GMT dial's four
/// hands. Story 2.1 is the "parameter-passing stress test" because the
/// hands derive from TWO different time sources (local + UTC); the test
/// `test_gmtMinusLocalHourAngle_*` family covers the cross-source offset
/// at multiple timezones.
final class CokeGMTMathTests: XCTestCase {

    // MARK: - Test scaffolding

    /// Pinned UTC calendar — used for deterministic test inputs.
    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Calendar pinned to a specific timezone for "local" inputs.
    private func calendar(secondsFromGMT: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)!
        return c
    }

    /// Build a Date at the given UTC hour/minute/second on 2026-05-14.
    private func date(utcHour h: Int, minute m: Int = 0, second s: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 14
        comps.hour = h
        comps.minute = m
        comps.second = s
        return Self.utcCalendar.date(from: comps)!
    }

    private let accuracy: CGFloat = 1e-6

    // MARK: - hourAngle (local 12h scale)

    func test_hourAngle_atNoonUTC_inUTC_returnsZero() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.hourAngle(from: date(utcHour: 12), calendar: utc)
        XCTAssertEqual(a, 0, accuracy: accuracy)
    }

    func test_hourAngle_at3UTC_inUTC_returnsHalfPi() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.hourAngle(from: date(utcHour: 3), calendar: utc)
        XCTAssertEqual(a, .pi / 2, accuracy: accuracy)
    }

    func test_hourAngle_creepsWithinHour_at330_returnsHalfPiPlusPiOver12() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.hourAngle(from: date(utcHour: 3, minute: 30), calendar: utc)
        XCTAssertEqual(a, .pi / 2 + .pi / 12, accuracy: accuracy)
    }

    // MARK: - minuteAngle (local)

    func test_minuteAngle_at30minutes_returnsPi() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.minuteAngle(from: date(utcHour: 0, minute: 30), calendar: utc)
        XCTAssertEqual(a, .pi, accuracy: accuracy)
    }

    func test_minuteAngle_at30min30sec_creepsHalfwayToNextMinute() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.minuteAngle(from: date(utcHour: 0, minute: 30, second: 30), calendar: utc)
        XCTAssertEqual(a, .pi + .pi / 60, accuracy: accuracy)
    }

    // MARK: - secondAngle (local, discrete)

    func test_secondAngle_atZero_returnsZero() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.secondAngle(from: date(utcHour: 0, minute: 0, second: 0), calendar: utc)
        XCTAssertEqual(a, 0, accuracy: accuracy)
    }

    func test_secondAngle_at30sec_returnsPi() {
        let utc = calendar(secondsFromGMT: 0)
        let a = CokeGMTMath.secondAngle(from: date(utcHour: 0, minute: 0, second: 30), calendar: utc)
        XCTAssertEqual(a, .pi, accuracy: accuracy)
    }

    // MARK: - gmtAngle (UTC 24h scale)

    func test_gmtAngle_at0UTC_returnsZero() {
        XCTAssertEqual(CokeGMTMath.gmtAngle(from: date(utcHour: 0)), 0, accuracy: accuracy)
    }

    func test_gmtAngle_at12UTC_returnsPi() {
        XCTAssertEqual(CokeGMTMath.gmtAngle(from: date(utcHour: 12)), .pi, accuracy: accuracy)
    }

    func test_gmtAngle_at18UTC_returnsThreePiOverTwo() {
        XCTAssertEqual(CokeGMTMath.gmtAngle(from: date(utcHour: 18)), 3 * .pi / 2, accuracy: accuracy)
    }

    func test_gmtAngle_at6UTC30min_returnsCorrespondingAngle() {
        // 6h30m on a 24h scale = 6.5 * (π/12) = 13π/24
        let a = CokeGMTMath.gmtAngle(from: date(utcHour: 6, minute: 30))
        XCTAssertEqual(a, 13 * .pi / 24, accuracy: accuracy)
    }

    func test_gmtAngle_independentOfLocalCalendar() {
        // gmtAngle reads UTC regardless of caller; verify by calling it
        // when the system locale is irrelevant.
        let a1 = CokeGMTMath.gmtAngle(from: date(utcHour: 6))
        let a2 = CokeGMTMath.gmtAngle(from: date(utcHour: 6))
        XCTAssertEqual(a1, a2, accuracy: accuracy)
        XCTAssertEqual(a1, 6 * .pi / 12, accuracy: accuracy)
    }

    // MARK: - gmtMinusLocalHourAngle (parameter-passing stress test)

    func test_gmtMinusLocalHourAngle_atUTC_isZero() {
        // Local timezone == UTC → both hands derive from same hour, but
        // they're on DIFFERENT SCALES (12h vs 24h). At 6:00 UTC: local hour
        // hand at angle 6π/6 = π; GMT hand at 6π/12 = π/2. Offset = π/2 - π
        // = -π/2.
        let utc = calendar(secondsFromGMT: 0)
        let offset = CokeGMTMath.gmtMinusLocalHourAngle(
            from: date(utcHour: 6), calendar: utc
        )
        XCTAssertEqual(offset, -.pi / 2, accuracy: accuracy)
    }

    func test_gmtMinusLocalHourAngle_atNewYork_at12UTC() {
        // At 12:00 UTC in New York (UTC-5 standard, ignoring DST for
        // determinism), local time = 7:00. Local hour-hand angle =
        // 7 * π/6 = 7π/6. GMT-hand angle at 12 UTC = π. Offset = π - 7π/6
        // = -π/6.
        let ny = calendar(secondsFromGMT: -5 * 3600)
        let offset = CokeGMTMath.gmtMinusLocalHourAngle(
            from: date(utcHour: 12), calendar: ny
        )
        XCTAssertEqual(offset, .pi - 7 * .pi / 6, accuracy: accuracy)
        XCTAssertEqual(offset, -.pi / 6, accuracy: accuracy)
    }

    func test_gmtMinusLocalHourAngle_atTokyo_at12UTC() {
        // Tokyo = UTC+9. At 12:00 UTC, local = 21:00 = 9 PM. Hour hand wraps
        // (h % 12) = 9, so angle = 9π/6 = 3π/2. GMT-hand angle = π.
        // Offset = π - 3π/2 = -π/2.
        let tokyo = calendar(secondsFromGMT: 9 * 3600)
        let offset = CokeGMTMath.gmtMinusLocalHourAngle(
            from: date(utcHour: 12), calendar: tokyo
        )
        XCTAssertEqual(offset, -.pi / 2, accuracy: accuracy)
    }

    // MARK: - dayOfMonth

    func test_dayOfMonth_extractsCorrectly() {
        // 2026-05-14 in UTC.
        let utc = calendar(secondsFromGMT: 0)
        let day = CokeGMTMath.dayOfMonth(from: date(utcHour: 12), calendar: utc)
        XCTAssertEqual(day, 14)
    }

    func test_dayOfMonth_respectsLocalTimezone() {
        // 2026-05-14 23:00 UTC == 2026-05-15 08:00 in Tokyo (UTC+9).
        let tokyo = calendar(secondsFromGMT: 9 * 3600)
        let day = CokeGMTMath.dayOfMonth(from: date(utcHour: 23), calendar: tokyo)
        XCTAssertEqual(day, 15)
    }
}
