import CoreGraphics
import Foundation
import IOKit.ps

/// Pure-math helpers for the Asymmetric Moonphase (Lange 1 Moonphase homage)
/// dial. Per ADR-001 (test boundary): the angle / phase / digit decomposition
/// functions are XCTest-covered; the renderer + layer code is not.
///
/// `powerReserveFraction()` IS exposed here even though it has an external
/// side-effect (reads IOKit power-source state). Per the Story 1.6 spec it's
/// the right home for the function (the renderer should ask the math file
/// what value to render, not perform IOKit queries itself). The function is
/// defensive: any error path returns `1.0` (full power) rather than throwing.
public enum AsymmetricMoonphaseMath {

    // MARK: - Lunar phase

    /// Astronomical reference: 2000-01-06 18:14:00 UTC was a documented new
    /// moon (JD 2451550.26, well-attested in Meeus's "Astronomical Algorithms"
    /// and the USNO almanacs).
    ///
    /// `Date(timeIntervalSince1970: 947182440)` resolves to that moment.
    private static let referenceNewMoon = Date(timeIntervalSince1970: 947182440)

    /// Mean synodic month (period between consecutive new moons), in days.
    /// Source: standard astronomical constant.
    public static let synodicMonthDays: Double = 29.530588868

    /// Mean synodic month in seconds (`synodicMonthDays * 86400`).
    public static let synodicMonthSeconds: Double = synodicMonthDays * 86400.0

    /// Returns the moonphase as a fraction `[0, 1)` of the synodic cycle.
    ///
    /// - `0.0` = new moon (dark)
    /// - `0.25` = waxing first quarter
    /// - `0.5` = full moon
    /// - `0.75` = waning third quarter
    ///
    /// Accurate to ±1 day of astronomical truth (per Story 1.6 AC14), which
    /// is well within the visual fidelity required for a watch face.
    public static func moonPhaseFraction(for date: Date) -> Double {
        let elapsed = date.timeIntervalSince(referenceNewMoon)
        let cycles = elapsed / synodicMonthSeconds
        var fraction = cycles.truncatingRemainder(dividingBy: 1.0)
        if fraction < 0 { fraction += 1.0 }
        return fraction
    }

    // MARK: - Hand angles (main time sub-dial)

    /// Hour-hand rotation angle in radians, measured clockwise from 12.
    /// Accounts for the minute fraction within the hour so the hand creeps
    /// smoothly. Same convention as `RoyaleMath.subdialHourAngle`.
    public static func mainTimeHourAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let position = CGFloat(h % 12) + CGFloat(m) / 60.0
        return position * (.pi / 6.0)
    }

    /// Minute-hand rotation angle in radians, clockwise from 12. Accounts for
    /// the seconds fraction within the minute.
    public static func mainTimeMinuteAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        let comps = calendar.dateComponents([.minute, .second], from: date)
        let m = comps.minute ?? 0
        let s = comps.second ?? 0
        let position = CGFloat(m) + CGFloat(s) / 60.0
        return position * (.pi / 30.0)
    }

    /// Sub-seconds hand rotation in radians, clockwise from 12. The sub-seconds
    /// dial completes one revolution per minute (60 positions).
    public static func subSecondsAngle(
        from date: Date,
        calendar: Calendar
    ) -> CGFloat {
        let s = calendar.dateComponents([.second], from: date).second ?? 0
        return CGFloat(s) * (.pi / 30.0)
    }

    // MARK: - Big date (Lange's outsize date)

    /// Day-of-month decomposed into two digits for the big-date window.
    /// `1 → (0, 1)`, `25 → (2, 5)`, `31 → (3, 1)`.
    public static func bigDateDigits(
        from date: Date,
        calendar: Calendar
    ) -> (d1: Int, d2: Int) {
        let day = calendar.dateComponents([.day], from: date).day ?? 1
        return (d1: day / 10, d2: day % 10)
    }

    // MARK: - Power reserve (battery-backed)

    /// Returns the current battery level as a fraction in `[0, 1]`.
    /// - On laptops: actual battery percentage.
    /// - On desktop Macs (no battery in the power-sources array): `1.0`.
    /// - On any error path: `1.0` (defensive per P10 — never crash the
    ///   renderer for an obscure power-source state).
    public static func powerReserveFraction() -> Double {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return 1.0
        }
        guard let sourcesRef = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else {
            return 1.0
        }
        let sources = sourcesRef as [CFTypeRef]
        guard let first = sources.first else {
            // No power sources → desktop Mac. Show full.
            return 1.0
        }
        guard let descRef = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue(),
              let dict = descRef as? [String: Any] else {
            return 1.0
        }
        guard let current = dict[kIOPSCurrentCapacityKey as String] as? Int,
              let maximum = dict[kIOPSMaxCapacityKey as String] as? Int,
              maximum > 0 else {
            return 1.0
        }
        return min(max(Double(current) / Double(maximum), 0.0), 1.0)
    }
}
