import Foundation
import QuartzCore

/// Abstraction over wall-clock + monotonic time, injected into every dial renderer.
///
/// All time reads in the `Watches` module go through this protocol (per P4 in the
/// architecture). Direct calls to `Date()` or `CACurrentMediaTime()` outside
/// `SystemTimeSource` are forbidden — the abstraction lets `FixedTimeSource`
/// substitute for renderer XCTest in Story 1.4.
protocol TimeSource: AnyObject {
    /// Current wall-clock time. Reflects NTP corrections; may jump.
    var now: Date { get }

    /// Monotonic time source for animation continuity across clock corrections.
    /// Does not jump backward when NTP adjusts the wall clock.
    var monotonic: TimeInterval { get }
}

/// Production time source backed by `Date()` and `CACurrentMediaTime()`.
final class SystemTimeSource: TimeSource {
    var now: Date { Date() }
    var monotonic: TimeInterval { CACurrentMediaTime() }
}

/// Test-time source with explicit, mutable time.
///
/// Used by Story 1.4 XCTest fixtures. Production code MUST NOT instantiate this.
final class FixedTimeSource: TimeSource {
    private(set) var now: Date
    private(set) var monotonic: TimeInterval

    init(now: Date, monotonic: TimeInterval = 0) {
        self.now = now
        self.monotonic = monotonic
    }

    /// Advance both wall-clock and monotonic by the same interval.
    /// Use this in tests to simulate the passage of time.
    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
        monotonic += interval
    }
}
