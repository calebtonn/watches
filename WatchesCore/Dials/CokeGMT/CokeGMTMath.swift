import CoreGraphics
import Foundation

/// Pure-math helpers for the Coke GMT (Tudor Black Bay GMT homage) dial.
///
/// The four hands derive from TWO different time sources:
///   - Hour, minute, second hands → LOCAL time via the injected `Calendar`.
///   - GMT (24-hour) hand → UTC, regardless of the user's locale.
///
/// Per ADR-001 / D12, this file is the test boundary: math YES, renderer
/// NO. `CokeGMTMathTests` covers every function below.
public enum CokeGMTMath {

    // MARK: - Local-time hand angles (12-hour scale)

    /// UTC `Calendar` used for the GMT hand. Built once and reused — the
    /// `TimeZone` lookup is cheap but not free, and the renderer ticks
    /// at 30 FPS.
    static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// Hour-hand rotation angle in radians, measured clockwise from 12.
    /// Accounts for the minute fraction within the hour so the hand creeps
    /// smoothly. Same convention as `AsymmetricMoonphaseMath.mainTimeHourAngle`.
    ///
    /// At 3:00 local → π/2 (pointing right).
    /// At 3:30 local → π/2 + π/12 (advanced halfway toward 4).
    public static func hourAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let position = CGFloat(h % 12) + CGFloat(m) / 60.0
        return position * (.pi / 6.0)
    }

    /// Minute-hand rotation angle in radians, clockwise from 12. Accounts
    /// for the seconds fraction so the minute hand creeps within a minute.
    public static func minuteAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        let comps = calendar.dateComponents([.minute, .second], from: date)
        let m = comps.minute ?? 0
        let s = comps.second ?? 0
        let position = CGFloat(m) + CGFloat(s) / 60.0
        return position * (.pi / 30.0)
    }

    /// Second-hand rotation angle in radians, clockwise from 12.
    /// **Pass-3 update:** smooth sweep using sub-second precision from
    /// the date's nanosecond component, matching a mechanical
    /// sweeping-seconds movement. Reduce-motion freezes the hand
    /// entirely (the renderer skips the update under reduce-motion).
    ///
    /// At second.nanosecond == 0 the angle is identical to the prior
    /// per-second-tick math; tests at exact integer seconds still pass.
    public static func secondAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        let comps = calendar.dateComponents([.second, .nanosecond], from: date)
        let s = CGFloat(comps.second ?? 0)
        let n = CGFloat(comps.nanosecond ?? 0) / 1_000_000_000.0
        return (s + n) * (.pi / 30.0)
    }

    // MARK: - GMT hand angle (24-hour scale, UTC source)

    /// GMT-hand rotation angle in radians, clockwise from the 24h bezel's
    /// top (00 / 24 mark). Reads UTC hours+minutes+seconds and maps them
    /// onto the 24h dial: 0:00 UTC → 0, 12:00 UTC → π, 18:00 UTC → 3π/2,
    /// 24:00 UTC (= 0:00 next day) → 2π (= 0).
    ///
    /// Returns sub-hour-precision so the hand creeps smoothly (matches the
    /// reference Tudor's behavior — the GMT hand is continuous, not jumpy).
    public static func gmtAngle(from date: Date) -> CGFloat {
        let comps = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        let h = CGFloat(comps.hour ?? 0)
        let m = CGFloat(comps.minute ?? 0)
        let s = CGFloat(comps.second ?? 0)
        let position = h + m / 60.0 + s / 3600.0    // 0..24
        return position * (.pi / 12.0)              // 24 × (π/12) = 2π
    }

    /// Convenience for tests: returns `gmtAngle(date) - hourAngle(date,
    /// calendar)` so a test can verify the OFFSET between the two hands
    /// at a given moment + timezone, independent of the absolute clock
    /// time. This is the headline expression of Story 2.1's
    /// "parameter-passing stress test."
    ///
    /// Note: the GMT hand uses a 24h scale and the hour hand uses a 12h
    /// scale, so this offset is NOT simply the timezone offset in radians.
    /// At 12:00 UTC with UTC-5 local: local hour hand = 7:00 (angle
    /// 7π/6), GMT hand = 12:00 (angle π). Offset = π - 7π/6 = -π/6.
    public static func gmtMinusLocalHourAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        gmtAngle(from: date) - hourAngle(from: date, calendar: calendar)
    }

    // MARK: - Date window

    /// Day-of-month as a single integer (`1...31`). Used by the renderer's
    /// date-window text path. No leading zero — the reference Tudor's date
    /// window shows single digits as just the digit.
    public static func dayOfMonth(
        from date: Date,
        calendar: Calendar
    ) -> Int {
        calendar.dateComponents([.day], from: date).day ?? 1
    }
}
