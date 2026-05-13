import CoreGraphics
import Foundation

/// Watch-position → `CGAffineTransform`/`CATransform3D`-compatible rotation angle.
///
/// **Returned angles, when applied via `CGAffineTransform(rotationAngle:)` or
/// `CATransform3DMakeRotation(angle, 0, 0, 1)` to a layer whose anchor and
/// initial orientation point at 12 o'clock, produce visually-clockwise
/// rotation as watch positions increase.**
///
/// Concretely:
///   - `second(0)`  → 0   → hand at 12 o'clock
///   - `second(15)` → -π/2 → hand at 3 o'clock (visually CW from 12)
///   - `second(30)` → -π   → hand at 6 o'clock
///   - `second(45)` → -3π/2 → hand at 9 o'clock
///
/// The negation accounts for the fact that `NSView`/`CALayer` default to a
/// Y-up coordinate system (mathematical convention), in which positive
/// rotation angles are counter-clockwise. We negate inside the helper so
/// callers don't have to remember the convention — they just say "this is
/// the watch position" and get visually-correct clockwise motion.
///
/// Per P3 in the architecture: every dial that uses watch-angle math uses
/// this helper. Never re-derive radian conversions inline.
enum WatchAngles {

    /// Hour hand angle. `h` is in [0, 12); `m` is the minute supplement.
    /// e.g. `hour(3, minute: 30)` → 3:30 hour position (between 3 and 4).
    static func hour(_ h: Double, minute m: Double = 0) -> CGFloat {
        let totalHours = h.truncatingRemainder(dividingBy: 12) + m / 60.0
        return CGFloat(-totalHours / 12.0 * 2 * .pi)
    }

    /// Minute hand angle. `m` is in [0, 60); `s` is the second supplement.
    static func minute(_ m: Double, second s: Double = 0) -> CGFloat {
        let totalMinutes = m.truncatingRemainder(dividingBy: 60) + s / 60.0
        return CGFloat(-totalMinutes / 60.0 * 2 * .pi)
    }

    /// Second hand angle. `s` is in [0, 60) and may have sub-second precision.
    static func second(_ s: Double) -> CGFloat {
        let totalSeconds = s.truncatingRemainder(dividingBy: 60)
        return CGFloat(-totalSeconds / 60.0 * 2 * .pi)
    }
}
