import AppKit
import CoreGraphics

/// Color constants for the Coke GMT (Tudor Black Bay GMT homage) dial.
///
/// All colors are sRGB. Values calibrated by the Pass E2-style design-spec
/// produced by the designer agent — every constant maps to a row in
/// `design-spec.md`'s palette table.
public enum CokeGMTPalette {

    // MARK: Case (stainless steel)

    public static let caseSteel: CGColor = NSColor(
        srgbRed: 0.78, green: 0.79, blue: 0.82, alpha: 1.0
    ).cgColor

    public static let caseSteelHighlight: CGColor = NSColor(
        srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1.0
    ).cgColor

    public static let caseSteelShadow: CGColor = NSColor(
        srgbRed: 0.42, green: 0.43, blue: 0.46, alpha: 1.0
    ).cgColor

    // MARK: Bezel — bicolor ceramic

    public static let bezelBlack: CGColor = NSColor(
        srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1.0
    ).cgColor

    public static let bezelBlackHighlight: CGColor = NSColor(
        srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 1.0
    ).cgColor

    public static let bezelBlackShadow: CGColor = NSColor(
        srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1.0
    ).cgColor

    public static let bezelRed: CGColor = NSColor(
        srgbRed: 0.62, green: 0.10, blue: 0.10, alpha: 1.0
    ).cgColor

    public static let bezelRedHighlight: CGColor = NSColor(
        srgbRed: 0.86, green: 0.20, blue: 0.18, alpha: 1.0
    ).cgColor

    public static let bezelRedShadow: CGColor = NSColor(
        srgbRed: 0.36, green: 0.05, blue: 0.05, alpha: 1.0
    ).cgColor

    public static let bezelNumeralCream: CGColor = NSColor(
        srgbRed: 0.93, green: 0.86, blue: 0.66, alpha: 1.0
    ).cgColor

    public static let ceramicSheenWhite: CGColor = NSColor(
        srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.20
    ).cgColor

    public static let chamferShadow: CGColor = NSColor(
        srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 0.70
    ).cgColor

    // MARK: Dial face

    public static let dialBlack: CGColor = NSColor(
        srgbRed: 0.045, green: 0.045, blue: 0.050, alpha: 1.0
    ).cgColor

    // MARK: Lume cream (markers + snowflake hands)

    public static let lumeCream: CGColor = NSColor(
        srgbRed: 0.95, green: 0.88, blue: 0.68, alpha: 1.0
    ).cgColor

    public static let lumeCreamOutline: CGColor = NSColor(
        srgbRed: 0.76, green: 0.62, blue: 0.36, alpha: 0.95
    ).cgColor

    public static let lumeSpecularHi: CGColor = NSColor(
        srgbRed: 1.00, green: 0.96, blue: 0.82, alpha: 0.40
    ).cgColor

    public static let lumeSpecularMid: CGColor = NSColor(
        srgbRed: 1.00, green: 0.92, blue: 0.74, alpha: 0.12
    ).cgColor

    public static let lumeSpecularLo: CGColor = NSColor(
        srgbRed: 0.50, green: 0.36, blue: 0.18, alpha: 0.25
    ).cgColor

    // MARK: Gold family (seconds + GMT + hub + date frame)

    public static let secondHandCream: CGColor = NSColor(
        srgbRed: 0.92, green: 0.84, blue: 0.62, alpha: 1.0
    ).cgColor

    public static let gmtHandGold: CGColor = NSColor(
        srgbRed: 0.88, green: 0.72, blue: 0.40, alpha: 1.0
    ).cgColor

    public static let goldOutline: CGColor = NSColor(
        srgbRed: 0.52, green: 0.38, blue: 0.16, alpha: 0.95
    ).cgColor

    public static let goldSpecularHi: CGColor = NSColor(
        srgbRed: 1.00, green: 0.92, blue: 0.72, alpha: 0.55
    ).cgColor

    public static let goldSpecularMid: CGColor = NSColor(
        srgbRed: 0.96, green: 0.82, blue: 0.52, alpha: 0.22
    ).cgColor

    public static let goldSpecularLo: CGColor = NSColor(
        srgbRed: 0.36, green: 0.22, blue: 0.08, alpha: 0.35
    ).cgColor

    // MARK: Date window

    public static let dateBoxWhite: CGColor = NSColor(
        srgbRed: 0.96, green: 0.94, blue: 0.88, alpha: 1.0
    ).cgColor

    public static let dateNumeralBlack: CGColor = NSColor(
        srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1.0
    ).cgColor

    public static let dateFrameGold: CGColor = NSColor(
        srgbRed: 0.84, green: 0.66, blue: 0.34, alpha: 1.0
    ).cgColor
}
