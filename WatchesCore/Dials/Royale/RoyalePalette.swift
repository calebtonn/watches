import AppKit
import CoreGraphics

/// Color constants for the Royale (digital LCD) dial.
///
/// All colors are sRGB. Per architecture (no asset catalogs for dial colors),
/// these are inline `NSColor(srgbRed:...)` constants. Values tuned by eye
/// against `faces/AE-1200WH-1CV_1.png.avif`.
public enum RoyalePalette {

    /// LCD body — the panel behind every glyph and the world-map region.
    /// The AE-1200WH-WH ships a **positive** LCD (olive-yellow background,
    /// dark digits), not the inverted "lit green pixels on black" look of
    /// the WHD variant. This color matches the warm yellow-olive of the
    /// reference photo.
    public static let background: CGColor = NSColor(
        srgbRed: 0.76, green: 0.77, blue: 0.62, alpha: 1.0
    ).cgColor

    /// Lit LCD pixel — the "on" state for digit segments and letter pixels.
    /// On a positive LCD this is dark gray / near-black, NOT a lit color.
    public static let litSegment: CGColor = NSColor(
        srgbRed: 0.10, green: 0.11, blue: 0.10, alpha: 1.0
    ).cgColor

    /// Ghosted "off" segment — barely-visible silhouette of unlit segments.
    /// On a positive LCD this is a faint darkening of the background.
    public static let offSegment: CGColor = NSColor(
        srgbRed: 0.10, green: 0.11, blue: 0.10, alpha: 0.07
    ).cgColor

    /// The world-map region's interior color. Same family as `background`
    /// but slightly cooler/darker so the map region reads as a distinct
    /// panel within the LCD.
    public static let mapBackground: CGColor = NSColor(
        srgbRed: 0.72, green: 0.74, blue: 0.58, alpha: 1.0
    ).cgColor

    /// Continent dot color, for the dot-matrix world map. Dark — same family
    /// as `litSegment` since we're a positive LCD.
    public static let mapDot: CGColor = NSColor(
        srgbRed: 0.18, green: 0.19, blue: 0.17, alpha: 1.0
    ).cgColor

    // MARK: Case / bezel / faceplate

    /// The deep-black surround filling the canvas outside the watch case.
    /// The screensaver's host already paints black; this is here so the
    /// renderer is self-contained and the watch isn't dependent on host paint.
    public static let caseBackground: CGColor = NSColor(
        srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1.0
    ).cgColor

    /// Brushed-silver bezel — mid-tone of the vertical gradient used to
    /// fake a top-lit polished-metal effect.
    public static let bezel: CGColor = NSColor(
        srgbRed: 0.78, green: 0.79, blue: 0.80, alpha: 1.0
    ).cgColor

    /// Top-edge highlight of the bezel gradient (lit by an imagined
    /// top-front light source).
    public static let bezelHighlight: CGColor = NSColor(
        srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 1.0
    ).cgColor

    /// Bottom-edge shadow of the bezel gradient (under-side).
    public static let bezelEdgeShadow: CGColor = NSColor(
        srgbRed: 0.48, green: 0.49, blue: 0.50, alpha: 1.0
    ).cgColor

    /// The dark inner frame between the bezel and the LCD — mid-tone of
    /// the faceplate's subtle vertical gradient.
    public static let faceplate: CGColor = NSColor(
        srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1.0
    ).cgColor

    /// Top-edge highlight of the faceplate gradient — lighter than
    /// `faceplate`, suggesting molded plastic catching top-front light.
    public static let faceplateHighlight: CGColor = NSColor(
        srgbRed: 0.18, green: 0.19, blue: 0.21, alpha: 1.0
    ).cgColor

    /// Bottom-edge shadow of the faceplate gradient — true black, the
    /// under-lit side of the molded plastic.
    public static let faceplateEdgeShadow: CGColor = NSColor(
        srgbRed: 0.01, green: 0.01, blue: 0.02, alpha: 1.0
    ).cgColor

    /// Subtle highlight stroke around faceplate cutouts — suggests the
    /// cutouts have a slight bevel / depth.
    public static let faceplateCutoutBevel: CGColor = NSColor(
        srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1.0
    ).cgColor

    /// Light-silver color used for graphics PRINTED ON the dark faceplate:
    /// the subdial ring, tick marks, and number labels around the circular
    /// cutout, plus the MODE / ADJUST / LIGHT / SEARCH labels at the
    /// pusher locations. Reads as silkscreen on matte plastic.
    public static let faceplatePrint: CGColor = NSColor(
        srgbRed: 0.82, green: 0.83, blue: 0.83, alpha: 1.0
    ).cgColor

    /// Black rivets at the corners around the subdial cutout — pure-black
    /// dots on the dark faceplate; just dark enough to read.
    public static let faceplateRivet: CGColor = NSColor(
        srgbRed: 0.02, green: 0.02, blue: 0.02, alpha: 1.0
    ).cgColor

    /// Screw heads at the four bezel corners — mid-tone of a radial
    /// gradient that fakes a polished-metal sphere under top-left light.
    public static let screw: CGColor = NSColor(
        srgbRed: 0.55, green: 0.56, blue: 0.57, alpha: 1.0
    ).cgColor

    /// Bright spot of each screw — the specular highlight.
    public static let screwHighlight: CGColor = NSColor(
        srgbRed: 0.88, green: 0.89, blue: 0.90, alpha: 1.0
    ).cgColor

    /// Dark side of each screw — opposite the highlight.
    public static let screwShadow: CGColor = NSColor(
        srgbRed: 0.22, green: 0.23, blue: 0.24, alpha: 1.0
    ).cgColor

    /// The small slit/cross on each screw head.
    public static let screwSlot: CGColor = NSColor(
        srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1.0
    ).cgColor

    /// Button-pusher mid-tone — center of a horizontal gradient that
    /// reads as a cylindrical side surface lit from the front.
    public static let pusher: CGColor = NSColor(
        srgbRed: 0.74, green: 0.75, blue: 0.76, alpha: 1.0
    ).cgColor

    /// Pusher center highlight (where the cylinder catches the most light).
    public static let pusherHighlight: CGColor = NSColor(
        srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1.0
    ).cgColor

    /// Pusher edge shadow (cylinder edges roll away into shadow).
    public static let pusherShadow: CGColor = NSColor(
        srgbRed: 0.42, green: 0.43, blue: 0.44, alpha: 1.0
    ).cgColor

}
