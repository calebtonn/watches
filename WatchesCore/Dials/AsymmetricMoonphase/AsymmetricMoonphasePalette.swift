import AppKit
import CoreGraphics

/// Color constants for the Asymmetric Moonphase (Lange 1 Moonphase homage) dial.
///
/// All colors are sRGB. Inline `NSColor(srgbRed:...)` constants — no asset
/// catalogs for dial colors per the architecture's per-dial conventions.
///
/// Values calibrated by the Pass E design-spec.md after side-by-side
/// reference comparison.
public enum AsymmetricMoonphasePalette {

    // MARK: Case / bezel — gold

    public static let caseGold: CGColor = NSColor(
        srgbRed: 0.78, green: 0.60, blue: 0.32, alpha: 1.0
    ).cgColor

    public static let caseGoldHighlight: CGColor = NSColor(
        srgbRed: 0.98, green: 0.88, blue: 0.62, alpha: 1.0
    ).cgColor

    public static let caseGoldShadow: CGColor = NSColor(
        srgbRed: 0.42, green: 0.28, blue: 0.12, alpha: 1.0
    ).cgColor

    /// Mid-tone between gold and highlight — bezel gradient stop.
    public static let caseGoldMid: CGColor = NSColor(
        srgbRed: 0.92, green: 0.76, blue: 0.45, alpha: 1.0
    ).cgColor

    public static let caseRim: CGColor = NSColor(
        srgbRed: 1.00, green: 0.94, blue: 0.78, alpha: 1.0
    ).cgColor

    /// Engraved inner lip at the bezel/dial boundary (semi-transparent).
    public static let caseInnerLip: CGColor = NSColor(
        srgbRed: 0.30, green: 0.20, blue: 0.10, alpha: 0.7
    ).cgColor

    // MARK: Dial face — silver / champagne

    public static let dialFace: CGColor = NSColor(
        srgbRed: 0.945, green: 0.935, blue: 0.905, alpha: 1.0
    ).cgColor

    /// Warm shadow tone for the faceplate vignette perimeter.
    public static let dialFaceShadow: CGColor = NSColor(
        srgbRed: 0.55, green: 0.50, blue: 0.40, alpha: 0.18
    ).cgColor

    public static let subDialFace: CGColor = NSColor(
        srgbRed: 0.965, green: 0.955, blue: 0.925, alpha: 1.0
    ).cgColor

    /// Recessed-edge shadow tone (semi-transparent so it blends with the face).
    public static let subDialShadow: CGColor = NSColor(
        srgbRed: 0.55, green: 0.50, blue: 0.40, alpha: 0.70
    ).cgColor

    // MARK: Hands + numerals + tick marks — gold "applied" alloy

    /// Warm gold used for hands, hour markers, Roman numerals, hub, date
    /// frames, aperture rim — every "applied" gold element shares this tone.
    public static let handGold: CGColor = NSColor(
        srgbRed: 0.86, green: 0.68, blue: 0.36, alpha: 1.0
    ).cgColor

    /// Near-black printed text/tick color (slightly translucent so it doesn't
    /// read as a stark line on the warm silver face).
    public static let numeralBlack: CGColor = NSColor(
        srgbRed: 0.12, green: 0.10, blue: 0.08, alpha: 0.92
    ).cgColor

    /// Sub-dial Arabic numerals + major ticks — same warm dark as numeralBlack
    /// but slightly heavier so they read in the smaller sub-dial.
    public static let subDialNumeral: CGColor = NSColor(
        srgbRed: 0.20, green: 0.16, blue: 0.10, alpha: 1.0
    ).cgColor

    // MARK: Moonphase

    public static let moonSky: CGColor = NSColor(
        srgbRed: 0.09, green: 0.14, blue: 0.30, alpha: 1.0
    ).cgColor

    public static let moonGold: CGColor = NSColor(
        srgbRed: 0.95, green: 0.82, blue: 0.50, alpha: 1.0
    ).cgColor

    /// Darker bronze for the man-in-the-moon eye dots + smile arc.
    public static let moonFaceBronze: CGColor = NSColor(
        srgbRed: 0.55, green: 0.36, blue: 0.16, alpha: 1.0
    ).cgColor

    public static let starGold: CGColor = NSColor(
        srgbRed: 1.00, green: 0.92, blue: 0.62, alpha: 1.0
    ).cgColor

    // MARK: Big date window

    public static let dateBackground: CGColor = NSColor(
        srgbRed: 1.00, green: 0.99, blue: 0.96, alpha: 1.0
    ).cgColor

    public static let dateNumeral: CGColor = NSColor(
        srgbRed: 0.05, green: 0.04, blue: 0.03, alpha: 1.0
    ).cgColor

    /// Subtle inner-shadow stroke at the white-box edge under the gold frame.
    public static let dateBoxInnerShadow: CGColor = NSColor(
        white: 0.0, alpha: 0.15
    ).cgColor

    // MARK: Power reserve indicator

    public static let powerReserveRed: CGColor = NSColor(
        srgbRed: 0.80, green: 0.16, blue: 0.14, alpha: 1.0
    ).cgColor

    /// Minor power-reserve tick color (lighter than major ticks so the
    /// AUF / midpoint / AB majors dominate).
    public static let powerReserveTrack: CGColor = NSColor(
        srgbRed: 0.40, green: 0.34, blue: 0.22, alpha: 0.70
    ).cgColor
}
