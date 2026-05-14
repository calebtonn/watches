import AppKit
import CoreGraphics

/// Color constants for the Asymmetric Moonphase (Lange 1 Moonphase homage) dial.
///
/// All colors are sRGB. Inline `NSColor(srgbRed:...)` constants — no asset
/// catalogs for dial colors per the architecture's per-dial conventions.
public enum AsymmetricMoonphasePalette {

    // MARK: Case / bezel — gold

    /// Warm gold case body — mid-tone of the bezel's vertical gradient.
    public static let caseGold: CGColor = NSColor(
        srgbRed: 0.82, green: 0.65, blue: 0.40, alpha: 1.0
    ).cgColor

    /// Top-edge highlight of the gold bezel — lit by an imagined top-front
    /// light source.
    public static let caseGoldHighlight: CGColor = NSColor(
        srgbRed: 0.96, green: 0.85, blue: 0.62, alpha: 1.0
    ).cgColor

    /// Bottom-edge shadow of the gold bezel.
    public static let caseGoldShadow: CGColor = NSColor(
        srgbRed: 0.50, green: 0.38, blue: 0.22, alpha: 1.0
    ).cgColor

    /// Outer rim accent — a thin bright stroke at the very outer edge.
    public static let caseRim: CGColor = NSColor(
        srgbRed: 1.00, green: 0.92, blue: 0.72, alpha: 1.0
    ).cgColor

    // MARK: Dial face — silver / champagne

    /// Main dial face — silver-champagne with a slight warm cast.
    public static let dialFace: CGColor = NSColor(
        srgbRed: 0.95, green: 0.93, blue: 0.88, alpha: 1.0
    ).cgColor

    /// Sub-dial face — slightly lighter than the main dial so the sub-dials
    /// visually pop. The Lange 1's sub-dials have this barely-perceptible
    /// halo.
    public static let subDialFace: CGColor = NSColor(
        srgbRed: 0.97, green: 0.95, blue: 0.91, alpha: 1.0
    ).cgColor

    /// Soft edge shadow at the sub-dial boundary — sells the recessed look.
    public static let subDialShadow: CGColor = NSColor(
        srgbRed: 0.74, green: 0.72, blue: 0.66, alpha: 1.0
    ).cgColor

    // MARK: Hands + numerals + tick marks

    /// Gold hand color — slightly darker than the case so the hands read
    /// against the silver dial without disappearing into the bezel.
    public static let handGold: CGColor = NSColor(
        srgbRed: 0.72, green: 0.55, blue: 0.28, alpha: 1.0
    ).cgColor

    /// Roman numeral + tick mark color — near-black with a slight warm cast
    /// to match the dial's champagne tint.
    public static let numeralBlack: CGColor = NSColor(
        srgbRed: 0.13, green: 0.11, blue: 0.08, alpha: 1.0
    ).cgColor

    /// Sub-dial Arabic numerals + ticks — slightly lighter than the main
    /// dial's black so the visual hierarchy stays right.
    public static let subDialNumeral: CGColor = NSColor(
        srgbRed: 0.20, green: 0.16, blue: 0.10, alpha: 1.0
    ).cgColor

    // MARK: Moonphase

    /// Moonphase aperture sky — deep blue/navy with a hint of indigo.
    public static let moonSky: CGColor = NSColor(
        srgbRed: 0.10, green: 0.16, blue: 0.32, alpha: 1.0
    ).cgColor

    /// Moon disc — lighter than the case gold so it reads against the navy sky.
    public static let moonGold: CGColor = NSColor(
        srgbRed: 0.94, green: 0.82, blue: 0.50, alpha: 1.0
    ).cgColor

    /// Decorative gold stars dotted on the navy aperture.
    public static let starGold: CGColor = NSColor(
        srgbRed: 1.00, green: 0.92, blue: 0.62, alpha: 1.0
    ).cgColor

    // MARK: Big date window (Lange's iconic outsize date)

    /// Big-date box background — white, paper-bright.
    public static let dateBackground: CGColor = NSColor(
        srgbRed: 1.00, green: 0.99, blue: 0.96, alpha: 1.0
    ).cgColor

    /// Big-date numeral — true black.
    public static let dateNumeral: CGColor = NSColor(
        srgbRed: 0.05, green: 0.04, blue: 0.03, alpha: 1.0
    ).cgColor

    /// Thin separator line between the two date digit boxes.
    public static let dateSeparator: CGColor = NSColor(
        srgbRed: 0.60, green: 0.55, blue: 0.45, alpha: 1.0
    ).cgColor

    // MARK: Power reserve indicator

    /// Red triangular markers at the AUF (top) and AB (bottom) of the
    /// power-reserve arc.
    public static let powerReserveRed: CGColor = NSColor(
        srgbRed: 0.78, green: 0.20, blue: 0.18, alpha: 1.0
    ).cgColor

    /// Power-reserve arc track — thin engraved-looking line.
    public static let powerReserveTrack: CGColor = NSColor(
        srgbRed: 0.55, green: 0.50, blue: 0.40, alpha: 1.0
    ).cgColor
}
