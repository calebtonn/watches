import Foundation

/// Pure-math helpers for the Royale (digital LCD) dial.
///
/// Royale uses a hybrid glyph topology:
/// - **Digits 0–9** render as classic 7-segment LCD glyphs.
/// - **Letters A–Z** render as 5-wide × 7-tall pixel-block bitmap glyphs.
///
/// Per the test boundary (ADR-001): this file's pure functions are the only
/// part of Royale covered by XCTest. Renderer logic, layer state, color values,
/// and canvas geometry are validated visually only.
public enum RoyaleMath {

    // MARK: - 7-segment digit topology

    /// Segments of a classic 7-segment LCD digit, named with the traditional
    /// `a`–`g` mapping made readable.
    ///
    /// ```text
    ///    top
    ///   ┌───┐
    /// topLeft topRight
    ///   ├ middle ┤
    /// bottomLeft bottomRight
    ///   └───┘
    ///   bottom
    /// ```
    public enum Segment: CaseIterable, Hashable {
        case top          // a
        case topRight     // b
        case bottomRight  // c
        case bottom       // d
        case bottomLeft   // e
        case topLeft      // f
        case middle       // g
    }

    /// On-segment set for the given decimal digit (0–9). Returns the empty set
    /// for any other input. Per P10: no `fatalError` in renderer paths.
    public static func segments(forDigit digit: Int) -> Set<Segment> {
        switch digit {
        case 0: return [.top, .topRight, .bottomRight, .bottom, .bottomLeft, .topLeft]
        case 1: return [.topRight, .bottomRight]
        case 2: return [.top, .topRight, .middle, .bottomLeft, .bottom]
        case 3: return [.top, .topRight, .middle, .bottomRight, .bottom]
        case 4: return [.topLeft, .topRight, .middle, .bottomRight]
        case 5: return [.top, .topLeft, .middle, .bottomRight, .bottom]
        case 6: return [.top, .topLeft, .middle, .bottomLeft, .bottomRight, .bottom]
        case 7: return [.top, .topRight, .bottomRight]
        case 8: return [.top, .topRight, .bottomRight, .bottom, .bottomLeft, .topLeft, .middle]
        case 9: return [.top, .topLeft, .topRight, .middle, .bottomRight, .bottom]
        default: return []
        }
    }

    // MARK: - 5×7 pixel-block alphabet

    /// A single cell in the 5-wide × 7-tall pixel grid of a bitmap letter.
    /// `row` ∈ [0, 6] (0 = top), `col` ∈ [0, 4] (0 = left).
    public struct PixelCell: Hashable {
        public let row: Int
        public let col: Int
        public init(row: Int, col: Int) {
            self.row = row
            self.col = col
        }
    }

    /// On-pixel set for the given uppercase ASCII letter (A–Z). Lowercase
    /// inputs are upcased. Any non-letter input returns the empty set
    /// (P10: no fatalError).
    public static func pixels(forLetter letter: Character) -> Set<PixelCell> {
        let key = String(letter).uppercased()
        guard let pattern = alphabet[key] else { return [] }
        return decode(pattern)
    }

    // MARK: - Time / date decomposition

    /// Decomposes the given `Date` into the six digits of an `HH:MM:SS`
    /// display, using the supplied calendar (locale and time zone come from
    /// the calendar, NOT `Calendar.current` directly — keeps the function
    /// testable with a pinned timezone).
    public static func timeDigits(
        from date: Date,
        calendar: Calendar
    ) -> (h1: Int, h2: Int, m1: Int, m2: Int, s1: Int, s2: Int) {
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let s = comps.second ?? 0
        return (h / 10, h % 10, m / 10, m % 10, s / 10, s % 10)
    }

    /// Decomposes the given `Date` into the four digits of an `MM-DD` date
    /// display.
    public static func dateDigits(
        from date: Date,
        calendar: Calendar
    ) -> (mo1: Int, mo2: Int, d1: Int, d2: Int) {
        let comps = calendar.dateComponents([.month, .day], from: date)
        let mo = comps.month ?? 1
        let d = comps.day ?? 1
        return (mo / 10, mo % 10, d / 10, d % 10)
    }

    /// Day-of-week label sourced from the calendar's locale's standalone
    /// short weekday symbols. Returned uppercased with any trailing periods
    /// stripped (some locales abbreviate as `"lun."` — we want `"LUN"`).
    ///
    /// Per design note D5: Royale respects the machine's locale. US Macs see
    /// `MON`, German Macs see `MO`, French Macs see `LUN`, etc.
    public static func dayOfWeekLabel(
        for date: Date,
        calendar: Calendar
    ) -> String {
        let weekday = calendar.component(.weekday, from: date) // Gregorian: 1=Sun ... 7=Sat
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let index = weekday - 1
        guard index >= 0, index < symbols.count else { return "" }
        return symbols[index]
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
    }

    // MARK: - Alphabet bitmap (private)

    /// 5×7 pixel patterns for the Latin uppercase alphabet. `#` = on, `.` = off.
    /// Each entry is exactly 7 rows of exactly 5 columns. Authored by hand to
    /// match the AE-1200WH's pixel-block letter style: blocky, readable at
    /// small sizes, no rounded corners.
    private static let alphabet: [String: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
        "J": ["####.", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#...#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    ]

    private static func decode(_ rows: [String]) -> Set<PixelCell> {
        var cells = Set<PixelCell>()
        for (r, row) in rows.enumerated() {
            for (c, char) in row.enumerated() where char == "#" {
                cells.insert(PixelCell(row: r, col: c))
            }
        }
        return cells
    }
}
