import AppKit
import CoreText
import QuartzCore

/// Asymmetric Moonphase — homage of the A. Lange & Söhne Lange 1 Moonphase.
///
/// Story 1.6's purpose is the second falsification test for the
/// `DialRenderer` protocol — the **non-concentric layout** stress test.
/// Royale (Story 1.5) broke the analog-paradigm assumption; this dial breaks
/// the concentric-layout assumption by anchoring each sub-readout
/// independently:
///
/// - Main time sub-dial (large, offset LEFT) — Roman numerals + hour/minute
///   hands + moonphase aperture inside
/// - Big Date window (top-right) — Lange's iconic outsize date
/// - Sub-seconds dial (bottom-right) — small dial with sweeping seconds hand
/// - Power reserve indicator (right side) — `AUF / AB` arc tied to the
///   laptop's battery level (full on desktops)
///
/// See `notes.md` for design decisions.
public final class AsymmetricMoonphaseRenderer: DialRenderer {

    // MARK: DialRenderer static metadata

    public static let identity = DialIdentity(
        id: "asymmetricMoonphase",
        displayName: "Asymmetric Moonphase",
        homageCredit: "Inspired by the A. Lange & Söhne Lange 1 Moonphase",
        previewAssetName: "asymmetric-moonphase-preview"
    )

    public static let visibility: DialVisibility = .default

    // MARK: State

    private weak var rootLayer: CALayer?
    private var canvas: CGSize = .zero
    private var timeSource: TimeSource?
    private let calendar: Calendar = .autoupdatingCurrent

    /// Last rendered integer second — used for the reduce-motion dedup in
    /// `tick(reduceMotion:)` (same pattern as Royale).
    private var lastRenderedSecond: Int?

    /// Last rendered moonphase fraction (for reduce-motion dedup so we don't
    /// rewrite the moon transform every second).
    private var lastRenderedMoonPhase: Double = -1

    // MARK: Case + dial layers

    private let caseBackgroundLayer = CALayer()
    private let vignetteLayer = CAGradientLayer()

    /// Gold bezel — `CAGradientLayer` clipped to a circular mask.
    private let bezelLayer = CAGradientLayer()
    private let bezelMaskShape = CAShapeLayer()
    /// Thin bright rim at the very outer edge (silhouette pop).
    private let bezelRimLight = CAShapeLayer()
    /// Thin darker stroke just inside the bezel/dial boundary (depth cue).
    private let bezelInnerShadow = CAShapeLayer()

    /// Silver dial face (smaller circle inside the bezel).
    private let dialFaceLayer = CAShapeLayer()

    // MARK: Main time sub-dial layers

    private let mainTimeFaceLayer = CAShapeLayer()
    private let mainTimeRecessShade = CAGradientLayer()
    private let mainTimeGlossLayer = CAGradientLayer()    // polished-silver highlight
    private let mainTimeOuterRing = CAShapeLayer()
    private let mainTimeRimUpperShadow = CAShapeLayer()   // dark crescent at the top of the well
    private let mainTimeRimLowerHighlight = CAShapeLayer() // bounce-light at the bottom of the well
    private let mainTimeNumeralsLayer = CAShapeLayer()
    private let mainTimeTicksLayer = CAShapeLayer()
    private let mainTimeHourMarkersLayer = CAShapeLayer()   // gold lozenges at 1,2,4,5,7,8,10,11
    private let mainTimeHourHand = CAShapeLayer()
    private let mainTimeMinuteHand = CAShapeLayer()
    private let mainTimeCenterHub = CAShapeLayer()

    // MARK: Moonphase aperture layers

    private let moonphaseClipShape = CAShapeLayer()  // mask for the aperture
    private let moonphaseSkyLayer = CAShapeLayer()    // navy background
    private let moonphaseDiscLayer = CAShapeLayer()   // gold moon
    private let moonphaseFaceLayer = CAShapeLayer()   // man-in-the-moon (eyes + smile)
    private let moonphaseStarsLayer = CAShapeLayer()  // decorative gold stars
    private let moonphaseFrameLayer = CAShapeLayer()  // gold rim around the aperture
    /// Stationary container holding the aperture clip mask. Its mask must
    /// NOT translate with the moon, otherwise sliding the moon doesn't
    /// visibly reveal phases.
    private let moonphaseDiscContainer = CALayer()
    /// Translates left/right based on phase fraction; child of the stationary
    /// container. Holds the moon disc + face — they move together past the
    /// stationary aperture mask above.
    private let moonphaseMovingLayer = CALayer()

    // MARK: Big date window layers

    private let bigDateGoldFrame1 = CAShapeLayer()
    private let bigDateGoldFrame2 = CAShapeLayer()
    private let bigDateBox1 = CAShapeLayer()
    private let bigDateBox2 = CAShapeLayer()
    private let bigDateDigit1Layer = CAShapeLayer()
    private let bigDateDigit2Layer = CAShapeLayer()
    private var bigDateBox1Rect: CGRect = .zero
    private var bigDateBox2Rect: CGRect = .zero
    private var bigDateNumeralFont: NSFont?

    // MARK: Sub-seconds dial layers

    private let subSecondsFaceLayer = CAShapeLayer()
    private let subSecondsRecessShade = CAGradientLayer()
    private let subSecondsGlossLayer = CAGradientLayer()    // polished-silver highlight
    private let subSecondsRimUpperShadow = CAShapeLayer()
    private let subSecondsRimLowerHighlight = CAShapeLayer()
    private let subSecondsNumeralsLayer = CAShapeLayer()
    private let subSecondsTicksLayer = CAShapeLayer()       // minor ticks
    private let subSecondsTicksMajorLayer = CAShapeLayer()  // 5-second majors
    private let subSecondsHand = CAShapeLayer()
    private let subSecondsHub = CAShapeLayer()

    // MARK: Power reserve indicator layers

    private let powerReserveArcLayer = CAShapeLayer()         // minor ticks
    private let powerReserveTicksMajorLayer = CAShapeLayer()  // major ticks at AUF / midpoint / AB
    private let powerReserveLabelsLayer = CAShapeLayer()
    private let powerReserveRedTrianglesLayer = CAShapeLayer()
    private let powerReserveIndicatorHand = CAShapeLayer()
    /// Cached arc endpoints for positioning the indicator hand each tick.
    private var powerReserveAUFAngle: CGFloat = 0
    private var powerReserveABAngle: CGFloat = 0
    private var powerReservePivot: CGPoint = .zero

    // MARK: Layout anchors (computed each layoutLayers pass)

    private struct LayoutAnchors {
        let caseCenter: CGPoint
        let caseRadius: CGFloat        // outer bezel radius
        let dialRadius: CGFloat        // inner dial radius (silver face)
        let mainTimeCenter: CGPoint    // offset LEFT
        let mainTimeRadius: CGFloat
        let moonphaseCenter: CGPoint   // inside main time sub-dial, above hands
        let moonphaseHalfWidth: CGFloat
        let moonphaseHalfHeight: CGFloat
        let bigDateCenter: CGPoint     // offset top-right
        let bigDateHeight: CGFloat
        let subSecondsCenter: CGPoint  // offset bottom-right
        let subSecondsRadius: CGFloat
        let powerReserveCenter: CGPoint // offset right
        let powerReserveRadius: CGFloat
    }
    private var anchors: LayoutAnchors?

    // MARK: Init

    public init() {}

    // MARK: DialRenderer

    public func attach(rootLayer: CALayer, canvas: CGSize, timeSource: TimeSource) {
        self.rootLayer = rootLayer
        self.canvas = canvas
        self.timeSource = timeSource

        installLayers()
        layoutLayers(for: canvas)
        _ = tick(reduceMotion: false)

        Logging.renderer.info(
            "AsymmetricMoonphaseRenderer attached: canvas=\(Int(canvas.width), privacy: .public)×\(Int(canvas.height), privacy: .public)"
        )
    }

    @discardableResult
    public func tick(reduceMotion: Bool) -> [CGRect] {
        guard let timeSource else { return [] }
        let now = timeSource.now
        let integerSecond = Int(now.timeIntervalSince1970)

        // Integer-second dedup in reduce-motion mode.
        if reduceMotion, integerSecond == lastRenderedSecond {
            return []
        }
        lastRenderedSecond = integerSecond

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Hour + minute hands always update (movement is per-minute, no
        // animation between positions — `setDisableActions` suppresses it).
        let hourAngle = AsymmetricMoonphaseMath.mainTimeHourAngle(from: now, calendar: calendar)
        let minuteAngle = AsymmetricMoonphaseMath.mainTimeMinuteAngle(from: now, calendar: calendar)
        mainTimeHourHand.setAffineTransform(CGAffineTransform(rotationAngle: -hourAngle))
        mainTimeMinuteHand.setAffineTransform(CGAffineTransform(rotationAngle: -minuteAngle))

        // Sub-seconds hand: sweep per second. Skip the write in reduce-motion.
        if !reduceMotion {
            let secAngle = AsymmetricMoonphaseMath.subSecondsAngle(from: now, calendar: calendar)
            subSecondsHand.setAffineTransform(CGAffineTransform(rotationAngle: -secAngle))
        }

        // Big date — update when the day actually changes (cheap day-of-month
        // dedup). We re-render glyphs only on day boundary.
        let digits = AsymmetricMoonphaseMath.bigDateDigits(from: now, calendar: calendar)
        updateBigDateGlyphs(d1: digits.d1, d2: digits.d2)

        // Moonphase — update transform when the fraction changes
        // perceptibly. In reduce-motion, we freeze.
        if !reduceMotion {
            let phase = AsymmetricMoonphaseMath.moonPhaseFraction(for: now)
            if abs(phase - lastRenderedMoonPhase) > 0.0001 {
                updateMoonphaseTransform(fraction: phase)
                lastRenderedMoonPhase = phase
            }
        }

        // Power reserve — read battery each tick (state can change quickly
        // when charging).
        let pr = AsymmetricMoonphaseMath.powerReserveFraction()
        updatePowerReserveHand(fraction: pr)

        return [
            mainTimeHourHand.frame,
            mainTimeMinuteHand.frame,
            subSecondsHand.frame,
            bigDateBox1Rect,
            bigDateBox2Rect,
            powerReserveIndicatorHand.frame,
            moonphaseDiscContainer.frame,
        ]
    }

    public func canvasDidChange(to canvas: CGSize) {
        self.canvas = canvas
        layoutLayers(for: canvas)
    }

    public func detach() {
        caseBackgroundLayer.removeFromSuperlayer()
        rootLayer = nil
        timeSource = nil
        anchors = nil
    }

    // MARK: Install (called once at attach)

    private func installLayers() {
        guard let rootLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Canvas background — deep black behind the watch.
        caseBackgroundLayer.name = "asymmetric.caseBackground"
        caseBackgroundLayer.backgroundColor = NSColor(white: 0.02, alpha: 1.0).cgColor
        rootLayer.addSublayer(caseBackgroundLayer)

        // Soft radial vignette.
        vignetteLayer.name = "asymmetric.vignette"
        vignetteLayer.type = .radial
        vignetteLayer.colors = [
            NSColor(white: 0.09, alpha: 1.0).cgColor,
            NSColor(white: 0.02, alpha: 1.0).cgColor,
            NSColor(white: 0.00, alpha: 1.0).cgColor,
        ]
        vignetteLayer.locations = [0.0, 0.55, 1.0]
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        caseBackgroundLayer.addSublayer(vignetteLayer)

        // Gold bezel — 4-stop vertical gradient, nearly vertical with a
        // slight tilt that matches the upper-left light.
        bezelLayer.name = "asymmetric.bezel"
        bezelLayer.colors = [
            AsymmetricMoonphasePalette.caseGoldHighlight,
            AsymmetricMoonphasePalette.caseGoldMid,
            AsymmetricMoonphasePalette.caseGold,
            AsymmetricMoonphasePalette.caseGoldShadow,
        ]
        bezelLayer.locations = [0.00, 0.30, 0.62, 1.00]
        bezelLayer.startPoint = CGPoint(x: 0.30, y: 1.0)
        bezelLayer.endPoint = CGPoint(x: 0.70, y: 0.0)
        bezelMaskShape.fillColor = NSColor.white.cgColor
        bezelLayer.mask = bezelMaskShape
        caseBackgroundLayer.addSublayer(bezelLayer)

        // Outer rim light (thin bright stroke at the very outer edge).
        bezelRimLight.name = "asymmetric.bezel.rim"
        bezelRimLight.fillColor = nil
        bezelRimLight.strokeColor = AsymmetricMoonphasePalette.caseRim
        caseBackgroundLayer.addSublayer(bezelRimLight)

        // Engraved inner lip where bezel meets dial face.
        bezelInnerShadow.name = "asymmetric.bezel.innerShadow"
        bezelInnerShadow.fillColor = nil
        bezelInnerShadow.strokeColor = AsymmetricMoonphasePalette.caseInnerLip
        caseBackgroundLayer.addSublayer(bezelInnerShadow)

        // Dial face — silver circle.
        dialFaceLayer.name = "asymmetric.dial"
        dialFaceLayer.fillColor = AsymmetricMoonphasePalette.dialFace
        dialFaceLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(dialFaceLayer)

        // Main time sub-dial face
        mainTimeFaceLayer.fillColor = AsymmetricMoonphasePalette.subDialFace
        mainTimeFaceLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(mainTimeFaceLayer)

        // Recess depth gradient — vertical: dark at top of well, bright bounce
        // at bottom of well. Softened so the gloss highlight reads cleanly.
        mainTimeRecessShade.startPoint = CGPoint(x: 0.5, y: 1.0)
        mainTimeRecessShade.endPoint = CGPoint(x: 0.5, y: 0.0)
        mainTimeRecessShade.colors = [
            NSColor(white: 0.0, alpha: 0.13).cgColor,
            NSColor(white: 0.0, alpha: 0.00).cgColor,
            NSColor(white: 1.0, alpha: 0.06).cgColor,
        ]
        mainTimeRecessShade.locations = [0.0, 0.55, 1.0]
        caseBackgroundLayer.addSublayer(mainTimeRecessShade)

        // Polished-silver radial gloss — subtle highlight at upper-left.
        mainTimeGlossLayer.type = .radial
        mainTimeGlossLayer.startPoint = CGPoint(x: 0.32, y: 0.78)
        mainTimeGlossLayer.endPoint = CGPoint(x: 0.95, y: 0.20)
        mainTimeGlossLayer.colors = [
            NSColor(white: 1.0, alpha: 0.18).cgColor,
            NSColor(white: 1.0, alpha: 0.06).cgColor,
            NSColor(white: 1.0, alpha: 0.00).cgColor,
        ]
        mainTimeGlossLayer.locations = [0.0, 0.45, 1.0]
        caseBackgroundLayer.addSublayer(mainTimeGlossLayer)

        // Upper-rim shadow — the dark crescent at the top of the recess,
        // simulating the lip blocking the light from above.
        mainTimeRimUpperShadow.fillColor = nil
        mainTimeRimUpperShadow.strokeColor = AsymmetricMoonphasePalette.subDialShadow
        mainTimeRimUpperShadow.shadowColor = NSColor.black.cgColor
        mainTimeRimUpperShadow.shadowOpacity = 0.6
        caseBackgroundLayer.addSublayer(mainTimeRimUpperShadow)

        // Lower-rim highlight — faint warm bounce-light along the bottom of
        // the recess. Masked to the lower half so it reads as a moon.
        mainTimeRimLowerHighlight.fillColor = nil
        mainTimeRimLowerHighlight.strokeColor = NSColor(white: 1.0, alpha: 0.45).cgColor
        caseBackgroundLayer.addSublayer(mainTimeRimLowerHighlight)

        // Engraved perimeter line.
        mainTimeOuterRing.fillColor = nil
        mainTimeOuterRing.strokeColor = AsymmetricMoonphasePalette.subDialShadow
        caseBackgroundLayer.addSublayer(mainTimeOuterRing)

        mainTimeTicksLayer.fillColor = nil
        mainTimeTicksLayer.strokeColor = AsymmetricMoonphasePalette.numeralBlack
        caseBackgroundLayer.addSublayer(mainTimeTicksLayer)

        // Roman numerals as RAISED gold embossings (applied to the dial,
        // not painted). Drop shadow + thin dark stroke sells the
        // dimensional applied-gold look.
        mainTimeNumeralsLayer.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeNumeralsLayer.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        mainTimeNumeralsLayer.lineWidth = 0.4
        mainTimeNumeralsLayer.shadowColor = NSColor.black.cgColor
        mainTimeNumeralsLayer.shadowOpacity = 0.40
        mainTimeNumeralsLayer.shadowOffset = CGSize(width: 0.6, height: -0.6)
        mainTimeNumeralsLayer.shadowRadius = 1.0
        caseBackgroundLayer.addSublayer(mainTimeNumeralsLayer)

        mainTimeHourMarkersLayer.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeHourMarkersLayer.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        // Drop shadow gives the markers a raised/applied 3D feel matching
        // the reference detail shot's "polished gold stud" appearance.
        mainTimeHourMarkersLayer.shadowColor = NSColor.black.cgColor
        mainTimeHourMarkersLayer.shadowOpacity = 0.35
        mainTimeHourMarkersLayer.shadowOffset = CGSize(width: 0.5, height: -0.5)
        mainTimeHourMarkersLayer.shadowRadius = 0.8
        caseBackgroundLayer.addSublayer(mainTimeHourMarkersLayer)

        // Moonphase — z-order: sky → stars → disc → clip-mask (applied as
        // layer.mask on a container).
        moonphaseClipShape.fillColor = NSColor.white.cgColor
        moonphaseSkyLayer.fillColor = AsymmetricMoonphasePalette.moonSky
        moonphaseSkyLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(moonphaseSkyLayer)

        moonphaseStarsLayer.fillColor = AsymmetricMoonphasePalette.starGold
        moonphaseStarsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(moonphaseStarsLayer)

        // Moving sublayer inside the stationary aperture-masked container.
        moonphaseDiscContainer.addSublayer(moonphaseMovingLayer)
        moonphaseMovingLayer.actions = ["transform": NSNull(), "position": NSNull()]
        moonphaseMovingLayer.addSublayer(moonphaseDiscLayer)
        moonphaseDiscLayer.fillColor = AsymmetricMoonphasePalette.moonGold
        moonphaseDiscLayer.strokeColor = nil
        // Man-in-the-moon: two eye dots (filled) + curved smile (stroked).
        // Parented to moving layer so it slides with the moon disc.
        moonphaseMovingLayer.addSublayer(moonphaseFaceLayer)
        moonphaseFaceLayer.fillColor = AsymmetricMoonphasePalette.moonFaceBronze
        moonphaseFaceLayer.strokeColor = AsymmetricMoonphasePalette.moonFaceBronze
        moonphaseFaceLayer.lineCap = .round
        caseBackgroundLayer.addSublayer(moonphaseDiscContainer)

        // Thin gold frame around the aperture perimeter with subtle drop
        // shadow so it reads as an applied gold ring.
        moonphaseFrameLayer.fillColor = nil
        moonphaseFrameLayer.strokeColor = AsymmetricMoonphasePalette.handGold
        moonphaseFrameLayer.shadowColor = NSColor.black.cgColor
        moonphaseFrameLayer.shadowOpacity = 0.50
        moonphaseFrameLayer.shadowOffset = CGSize(width: 0.6, height: -0.6)
        moonphaseFrameLayer.shadowRadius = 1.0
        caseBackgroundLayer.addSublayer(moonphaseFrameLayer)

        // Hands — anchor at the PIVOT (tail extends behind in layer bounds).
        // Drop shadow gives them the "above the dial" feel; thin dark stroke
        // gives a faceted-edge cue on the gold.
        mainTimeHourHand.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeHourHand.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        mainTimeHourHand.lineWidth = 0.4
        mainTimeHourHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        mainTimeHourHand.actions = ["transform": NSNull(), "position": NSNull()]
        mainTimeHourHand.shadowColor = NSColor.black.cgColor
        mainTimeHourHand.shadowOpacity = 0.40
        mainTimeHourHand.shadowOffset = CGSize(width: 1.2, height: -1.8)
        mainTimeHourHand.shadowRadius = 2.5
        caseBackgroundLayer.addSublayer(mainTimeHourHand)

        mainTimeMinuteHand.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeMinuteHand.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        mainTimeMinuteHand.lineWidth = 0.4
        mainTimeMinuteHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        mainTimeMinuteHand.actions = ["transform": NSNull(), "position": NSNull()]
        mainTimeMinuteHand.shadowColor = NSColor.black.cgColor
        mainTimeMinuteHand.shadowOpacity = 0.40
        mainTimeMinuteHand.shadowOffset = CGSize(width: 1.2, height: -1.8)
        mainTimeMinuteHand.shadowRadius = 2.5
        caseBackgroundLayer.addSublayer(mainTimeMinuteHand)

        mainTimeCenterHub.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeCenterHub.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        mainTimeCenterHub.lineWidth = 0.4
        mainTimeCenterHub.shadowColor = NSColor.black.cgColor
        mainTimeCenterHub.shadowOpacity = 0.45
        mainTimeCenterHub.shadowOffset = CGSize(width: 0.5, height: -0.6)
        mainTimeCenterHub.shadowRadius = 1.0
        caseBackgroundLayer.addSublayer(mainTimeCenterHub)

        // Big date — gold frame BEHIND with drop shadow, white inner box with
        // thin inner-edge stroke, digits with drop shadow. No separator (the
        // gap + the two frame edges already separate the digits).
        bigDateGoldFrame1.fillColor = AsymmetricMoonphasePalette.handGold
        bigDateGoldFrame1.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        bigDateGoldFrame1.shadowColor = NSColor.black.cgColor
        bigDateGoldFrame1.shadowOpacity = 0.50
        bigDateGoldFrame1.shadowOffset = CGSize(width: 0.8, height: -1.2)
        bigDateGoldFrame1.shadowRadius = 1.6
        caseBackgroundLayer.addSublayer(bigDateGoldFrame1)

        bigDateGoldFrame2.fillColor = AsymmetricMoonphasePalette.handGold
        bigDateGoldFrame2.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        bigDateGoldFrame2.shadowColor = NSColor.black.cgColor
        bigDateGoldFrame2.shadowOpacity = 0.50
        bigDateGoldFrame2.shadowOffset = CGSize(width: 0.8, height: -1.2)
        bigDateGoldFrame2.shadowRadius = 1.6
        caseBackgroundLayer.addSublayer(bigDateGoldFrame2)

        bigDateBox1.fillColor = AsymmetricMoonphasePalette.dateBackground
        bigDateBox1.strokeColor = AsymmetricMoonphasePalette.dateBoxInnerShadow
        bigDateBox1.lineWidth = 0.5
        caseBackgroundLayer.addSublayer(bigDateBox1)

        bigDateBox2.fillColor = AsymmetricMoonphasePalette.dateBackground
        bigDateBox2.strokeColor = AsymmetricMoonphasePalette.dateBoxInnerShadow
        bigDateBox2.lineWidth = 0.5
        caseBackgroundLayer.addSublayer(bigDateBox2)

        // Digit drop shadow — the printed numerals sit physically on the
        // white plate beneath the gold frame.
        bigDateDigit1Layer.fillColor = AsymmetricMoonphasePalette.dateNumeral
        bigDateDigit1Layer.strokeColor = nil
        bigDateDigit1Layer.shadowColor = NSColor.black.cgColor
        bigDateDigit1Layer.shadowOpacity = 0.30
        bigDateDigit1Layer.shadowOffset = CGSize(width: 0.5, height: -0.8)
        bigDateDigit1Layer.shadowRadius = 0.8
        caseBackgroundLayer.addSublayer(bigDateDigit1Layer)

        bigDateDigit2Layer.fillColor = AsymmetricMoonphasePalette.dateNumeral
        bigDateDigit2Layer.strokeColor = nil
        bigDateDigit2Layer.shadowColor = NSColor.black.cgColor
        bigDateDigit2Layer.shadowOpacity = 0.30
        bigDateDigit2Layer.shadowOffset = CGSize(width: 0.5, height: -0.8)
        bigDateDigit2Layer.shadowRadius = 0.8
        caseBackgroundLayer.addSublayer(bigDateDigit2Layer)

        // Sub-seconds — same recess + gloss recipe as main time, scaled down.
        subSecondsFaceLayer.fillColor = AsymmetricMoonphasePalette.subDialFace
        subSecondsFaceLayer.strokeColor = AsymmetricMoonphasePalette.subDialShadow
        caseBackgroundLayer.addSublayer(subSecondsFaceLayer)

        subSecondsRecessShade.startPoint = CGPoint(x: 0.5, y: 1.0)
        subSecondsRecessShade.endPoint = CGPoint(x: 0.5, y: 0.0)
        subSecondsRecessShade.colors = [
            NSColor(white: 0.0, alpha: 0.13).cgColor,
            NSColor(white: 0.0, alpha: 0.00).cgColor,
            NSColor(white: 1.0, alpha: 0.06).cgColor,
        ]
        subSecondsRecessShade.locations = [0.0, 0.55, 1.0]
        caseBackgroundLayer.addSublayer(subSecondsRecessShade)

        subSecondsGlossLayer.type = .radial
        subSecondsGlossLayer.startPoint = CGPoint(x: 0.32, y: 0.78)
        subSecondsGlossLayer.endPoint = CGPoint(x: 0.95, y: 0.20)
        subSecondsGlossLayer.colors = [
            NSColor(white: 1.0, alpha: 0.18).cgColor,
            NSColor(white: 1.0, alpha: 0.06).cgColor,
            NSColor(white: 1.0, alpha: 0.00).cgColor,
        ]
        subSecondsGlossLayer.locations = [0.0, 0.45, 1.0]
        caseBackgroundLayer.addSublayer(subSecondsGlossLayer)

        subSecondsRimUpperShadow.fillColor = nil
        subSecondsRimUpperShadow.strokeColor = AsymmetricMoonphasePalette.subDialShadow
        subSecondsRimUpperShadow.shadowColor = NSColor.black.cgColor
        subSecondsRimUpperShadow.shadowOpacity = 0.6
        caseBackgroundLayer.addSublayer(subSecondsRimUpperShadow)

        subSecondsRimLowerHighlight.fillColor = nil
        subSecondsRimLowerHighlight.strokeColor = NSColor(white: 1.0, alpha: 0.45).cgColor
        caseBackgroundLayer.addSublayer(subSecondsRimLowerHighlight)

        // Minor minute ticks (every minute except multiples of 5).
        subSecondsTicksLayer.fillColor = nil
        subSecondsTicksLayer.strokeColor = AsymmetricMoonphasePalette.subDialNumeral
        caseBackgroundLayer.addSublayer(subSecondsTicksLayer)

        // Major 5-second ticks (longer, thicker).
        subSecondsTicksMajorLayer.fillColor = nil
        subSecondsTicksMajorLayer.strokeColor = AsymmetricMoonphasePalette.subDialNumeral
        caseBackgroundLayer.addSublayer(subSecondsTicksMajorLayer)

        subSecondsNumeralsLayer.fillColor = AsymmetricMoonphasePalette.subDialNumeral
        subSecondsNumeralsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(subSecondsNumeralsLayer)

        subSecondsHand.fillColor = AsymmetricMoonphasePalette.handGold
        subSecondsHand.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        subSecondsHand.lineWidth = 0.3
        subSecondsHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        subSecondsHand.actions = ["transform": NSNull(), "position": NSNull()]
        subSecondsHand.shadowColor = NSColor.black.cgColor
        subSecondsHand.shadowOpacity = 0.35
        subSecondsHand.shadowOffset = CGSize(width: 0.6, height: -0.8)
        subSecondsHand.shadowRadius = 1.0
        caseBackgroundLayer.addSublayer(subSecondsHand)

        subSecondsHub.fillColor = AsymmetricMoonphasePalette.handGold
        subSecondsHub.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        subSecondsHub.lineWidth = 0.4
        subSecondsHub.shadowColor = NSColor.black.cgColor
        subSecondsHub.shadowOpacity = 0.45
        subSecondsHub.shadowOffset = CGSize(width: 0.5, height: -0.6)
        subSecondsHub.shadowRadius = 1.0
        caseBackgroundLayer.addSublayer(subSecondsHub)

        // Power reserve — minor ticks (light/thin) below major ticks (dark/thicker).
        powerReserveArcLayer.fillColor = nil
        powerReserveArcLayer.strokeColor = AsymmetricMoonphasePalette.powerReserveTrack
        caseBackgroundLayer.addSublayer(powerReserveArcLayer)

        powerReserveTicksMajorLayer.fillColor = nil
        powerReserveTicksMajorLayer.strokeColor = AsymmetricMoonphasePalette.subDialNumeral
        caseBackgroundLayer.addSublayer(powerReserveTicksMajorLayer)

        powerReserveRedTrianglesLayer.fillColor = AsymmetricMoonphasePalette.powerReserveRed
        powerReserveRedTrianglesLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(powerReserveRedTrianglesLayer)

        powerReserveLabelsLayer.fillColor = AsymmetricMoonphasePalette.subDialNumeral
        powerReserveLabelsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(powerReserveLabelsLayer)

        powerReserveIndicatorHand.fillColor = AsymmetricMoonphasePalette.handGold
        powerReserveIndicatorHand.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        powerReserveIndicatorHand.lineWidth = 0.3
        powerReserveIndicatorHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        powerReserveIndicatorHand.actions = ["transform": NSNull(), "position": NSNull()]
        powerReserveIndicatorHand.shadowColor = NSColor.black.cgColor
        powerReserveIndicatorHand.shadowOpacity = 0.40
        powerReserveIndicatorHand.shadowOffset = CGSize(width: 0.8, height: -1.0)
        powerReserveIndicatorHand.shadowRadius = 1.5
        caseBackgroundLayer.addSublayer(powerReserveIndicatorHand)
    }

    // MARK: Layout (called on attach + canvasDidChange)

    private func layoutLayers(for canvas: CGSize) {
        guard canvas.width > 0, canvas.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        caseBackgroundLayer.frame = CGRect(origin: .zero, size: canvas)
        vignetteLayer.frame = caseBackgroundLayer.bounds

        // Round case centered, sized to ~85% of the smaller canvas dimension.
        let caseDiameter = min(canvas.width, canvas.height) * 0.85
        let caseRadius = caseDiameter / 2
        let caseCenter = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let caseRect = CGRect(
            x: caseCenter.x - caseRadius,
            y: caseCenter.y - caseRadius,
            width: caseDiameter, height: caseDiameter
        )

        // Bezel
        bezelLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelMaskShape.frame = bezelLayer.bounds
        bezelMaskShape.path = CGPath(ellipseIn: caseRect, transform: nil)

        bezelRimLight.frame = CGRect(origin: .zero, size: canvas)
        bezelRimLight.path = CGPath(ellipseIn: caseRect, transform: nil)
        bezelRimLight.lineWidth = max(0.5, caseRadius * 0.005)

        // Dial — inner circle at ~93% of case radius (bezel thickness ≈ 7%,
        // matching the Lange 1's slim bezel).
        let dialRadius = caseRadius * 0.93
        let dialRect = CGRect(
            x: caseCenter.x - dialRadius,
            y: caseCenter.y - dialRadius,
            width: dialRadius * 2, height: dialRadius * 2
        )
        dialFaceLayer.frame = CGRect(origin: .zero, size: canvas)
        dialFaceLayer.path = CGPath(ellipseIn: dialRect, transform: nil)

        // Bezel inner shadow stroke just at the dial boundary
        bezelInnerShadow.frame = CGRect(origin: .zero, size: canvas)
        bezelInnerShadow.path = CGPath(ellipseIn: dialRect, transform: nil)
        bezelInnerShadow.lineWidth = max(0.5, caseRadius * 0.006)

        // Per-readout anchors (canvas-coords). Pass E — mirror the design
        // spec values produced from side-by-side reference analysis.
        let mainTimeCenter = CGPoint(
            x: caseCenter.x - dialRadius * 0.18,
            y: caseCenter.y + dialRadius * 0.00
        )
        let mainTimeRadius = dialRadius * 0.55

        // Moonphase aperture inside main time sub-dial. `moonphaseCenter` is
        // the BASELINE-center of the aperture; top is a wide horizontal oval
        // (cubic Beziers; height = halfWidth × 0.58).
        let moonphaseCenter = CGPoint(
            x: mainTimeCenter.x,
            y: mainTimeCenter.y + mainTimeRadius * 0.36
        )
        let moonphaseHalfWidth = mainTimeRadius * 0.36
        let moonphaseHalfHeight = moonphaseHalfWidth * 0.58   // wide oval, h<w

        // Big date — upper center-right. Sits at the top-right corner with
        // its frames partially overlapping main time's silver face per the
        // reference. Drop shadow on frames sells "applied gold".
        let bigDateCenter = CGPoint(
            x: caseCenter.x + dialRadius * 0.30,
            y: caseCenter.y + dialRadius * 0.42
        )
        let bigDateHeight = dialRadius * 0.17

        // Sub-seconds — lower center-right, partially overlapping main time.
        let subSecondsCenter = CGPoint(
            x: caseCenter.x + dialRadius * 0.32,
            y: caseCenter.y - dialRadius * 0.40
        )
        let subSecondsRadius = dialRadius * 0.22

        // Power reserve — right edge, larger arc, tighter angular span for
        // the Lange's tall-vertical scale feel.
        let powerReserveCenter = CGPoint(
            x: caseCenter.x + dialRadius * 0.62,
            y: caseCenter.y - dialRadius * 0.05
        )
        let powerReserveRadius = dialRadius * 0.32

        anchors = LayoutAnchors(
            caseCenter: caseCenter,
            caseRadius: caseRadius,
            dialRadius: dialRadius,
            mainTimeCenter: mainTimeCenter,
            mainTimeRadius: mainTimeRadius,
            moonphaseCenter: moonphaseCenter,
            moonphaseHalfWidth: moonphaseHalfWidth,
            moonphaseHalfHeight: moonphaseHalfHeight,
            bigDateCenter: bigDateCenter,
            bigDateHeight: bigDateHeight,
            subSecondsCenter: subSecondsCenter,
            subSecondsRadius: subSecondsRadius,
            powerReserveCenter: powerReserveCenter,
            powerReserveRadius: powerReserveRadius
        )

        layoutMainTimeSubDial(canvas: canvas, anchors: anchors!)
        layoutMoonphase(canvas: canvas, anchors: anchors!)
        layoutBigDate(canvas: canvas, anchors: anchors!)
        layoutSubSeconds(canvas: canvas, anchors: anchors!)
        layoutPowerReserve(canvas: canvas, anchors: anchors!)
    }

    // MARK: Main time sub-dial layout

    private func layoutMainTimeSubDial(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.mainTimeCenter.x
        let cy = a.mainTimeCenter.y
        let r = a.mainTimeRadius

        let faceRect = CGRect(
            x: cx - r, y: cy - r, width: r * 2, height: r * 2
        )

        mainTimeFaceLayer.frame = CGRect(origin: .zero, size: canvas)
        mainTimeFaceLayer.path = CGPath(ellipseIn: faceRect, transform: nil)

        // Recess gradient + gloss highlight — both masked to the face circle,
        // applied in the sub-dial's local coordinate space so they span only
        // the face (not the whole canvas).
        let faceCirclePath = CGPath(
            ellipseIn: CGRect(origin: .zero, size: faceRect.size), transform: nil
        )

        mainTimeRecessShade.frame = faceRect
        let recessMask = CAShapeLayer()
        recessMask.path = faceCirclePath
        recessMask.fillColor = NSColor.white.cgColor
        mainTimeRecessShade.mask = recessMask

        mainTimeGlossLayer.frame = faceRect
        let glossMask = CAShapeLayer()
        glossMask.path = faceCirclePath
        glossMask.fillColor = NSColor.white.cgColor
        mainTimeGlossLayer.mask = glossMask

        // Upper-rim shadow — full-circle stroke with a downward-blurred shadow
        // that simulates the lip blocking light from above.
        let faceCirclePathCanvas = CGPath(ellipseIn: faceRect, transform: nil)
        mainTimeRimUpperShadow.frame = CGRect(origin: .zero, size: canvas)
        mainTimeRimUpperShadow.path = faceCirclePathCanvas
        mainTimeRimUpperShadow.lineWidth = max(0.6, r * 0.020)
        mainTimeRimUpperShadow.shadowOffset = CGSize(width: 0, height: -r * 0.010)
        mainTimeRimUpperShadow.shadowRadius = r * 0.010
        mainTimeRimUpperShadow.shadowPath = faceCirclePathCanvas

        // Lower-rim highlight — mask the full-circle stroke to only show in
        // the lower 40% of the face so it reads as a moon, not a full ring.
        mainTimeRimLowerHighlight.frame = CGRect(origin: .zero, size: canvas)
        mainTimeRimLowerHighlight.path = faceCirclePathCanvas
        mainTimeRimLowerHighlight.lineWidth = max(0.4, r * 0.012)
        let lowerHalfMask = CAShapeLayer()
        lowerHalfMask.path = CGPath(rect: CGRect(
            x: faceRect.minX, y: faceRect.minY,
            width: faceRect.width, height: faceRect.height * 0.40
        ), transform: nil)
        lowerHalfMask.fillColor = NSColor.white.cgColor
        mainTimeRimLowerHighlight.mask = lowerHalfMask

        // Engraved perimeter line.
        mainTimeOuterRing.frame = CGRect(origin: .zero, size: canvas)
        mainTimeOuterRing.path = faceCirclePathCanvas
        mainTimeOuterRing.lineWidth = max(0.5, r * 0.010)

        // Minute ticks — 60 thin hairlines around the perimeter, skipping
        // the 12 hour-marker positions (Romans at cardinals + lozenges at
        // non-cardinals). Crisp printed look: thin, butt-capped, near-black.
        let ticksPath = CGMutablePath()
        let minuteTickR = r * 0.985
        let minuteTickInner = r * 0.955
        for i in 0..<60 where i % 5 != 0 {
            let theta = .pi / 2 - (CGFloat(i) / 60) * 2 * .pi
            let dx = cos(theta)
            let dy = sin(theta)
            ticksPath.move(to: CGPoint(x: cx + dx * minuteTickInner, y: cy + dy * minuteTickInner))
            ticksPath.addLine(to: CGPoint(x: cx + dx * minuteTickR, y: cy + dy * minuteTickR))
        }
        mainTimeTicksLayer.frame = CGRect(origin: .zero, size: canvas)
        mainTimeTicksLayer.path = ticksPath
        mainTimeTicksLayer.lineWidth = max(0.4, r * 0.012)
        mainTimeTicksLayer.lineCap = .butt

        // Gold lozenge hour markers at the 8 non-cardinal positions
        // (1, 2, 4, 5, 7, 8, 10, 11). Slim vertical diamonds (~2.8:1
        // length:width) pointing radially outward, sharing radius with the
        // Roman numerals (r·0.86).
        let markersPath = CGMutablePath()
        let markerCenterR = r * 0.86
        let markerLong = r * 0.085          // radial length
        let markerWide = r * 0.030          // perpendicular width
        let nonCardinals = [1, 2, 4, 5, 7, 8, 10, 11]
        for i in nonCardinals {
            let theta = .pi / 2 - (CGFloat(i) / 12) * 2 * .pi
            let ux = cos(theta), uy = sin(theta)
            // perpendicular unit vector (90° CCW)
            let px = -uy, py = ux
            let mx = cx + ux * markerCenterR
            let my = cy + uy * markerCenterR
            let outer = CGPoint(x: mx + ux * markerLong / 2, y: my + uy * markerLong / 2)
            let inner = CGPoint(x: mx - ux * markerLong / 2, y: my - uy * markerLong / 2)
            let left = CGPoint(x: mx + px * markerWide / 2, y: my + py * markerWide / 2)
            let right = CGPoint(x: mx - px * markerWide / 2, y: my - py * markerWide / 2)
            markersPath.move(to: outer)
            markersPath.addLine(to: left)
            markersPath.addLine(to: inner)
            markersPath.addLine(to: right)
            markersPath.closeSubpath()
        }
        mainTimeHourMarkersLayer.frame = CGRect(origin: .zero, size: canvas)
        mainTimeHourMarkersLayer.path = markersPath
        mainTimeHourMarkersLayer.shadowPath = markersPath
        mainTimeHourMarkersLayer.lineWidth = max(0.3, r * 0.0035)

        // Roman numerals at 12 / 3 / 6 / 9 — applied gold (Book/Regular
        // weight serif). Same radius as the lozenges.
        let romans = ["XII", "III", "VI", "IX"]
        let romanAngles: [CGFloat] = [
            .pi / 2,     // 12 (top)
            0,           // 3 (right)
            -.pi / 2,    // 6 (bottom)
            .pi,         // 9 (left)
        ]
        let romanRadius = r * 0.86
        let romanFontSize = r * 0.13
        let romanFont = romanNumeralFont(size: romanFontSize)
        let romansPath = CGMutablePath()
        for (i, roman) in romans.enumerated() {
            let theta = romanAngles[i]
            let nx = cx + cos(theta) * romanRadius
            let ny = cy + sin(theta) * romanRadius
            if let glyphs = textPath(string: roman, font: romanFont) {
                // Translate glyph path so its center sits at (nx, ny)
                let bounds = glyphs.boundingBox
                let tx = nx - bounds.midX
                let ty = ny - bounds.midY
                let transform = CGAffineTransform(translationX: tx, y: ty)
                romansPath.addPath(glyphs, transform: transform)
            }
        }
        mainTimeNumeralsLayer.frame = CGRect(origin: .zero, size: canvas)
        mainTimeNumeralsLayer.path = romansPath
        mainTimeNumeralsLayer.shadowPath = romansPath

        // Hands — anchor at the PIVOT (tail extends behind in layer bounds).
        let tailFrac = Self.handTailFraction
        let anchorY = tailFrac / (1 + tailFrac)

        let hourLength = r * 0.50
        let hourWidth = r * 0.12
        let hourPath = goldHandPath(width: hourWidth, length: hourLength, taper: true)
        mainTimeHourHand.bounds = CGRect(
            x: 0, y: 0, width: hourWidth, height: hourLength * (1 + tailFrac)
        )
        mainTimeHourHand.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        mainTimeHourHand.position = a.mainTimeCenter
        mainTimeHourHand.path = hourPath
        mainTimeHourHand.shadowPath = hourPath

        let minuteLength = r * 0.78
        let minuteWidth = r * 0.08
        // No pivot eye on either hand per the reference detail shot.
        let minutePath = goldHandPath(width: minuteWidth, length: minuteLength, taper: true)
        mainTimeMinuteHand.bounds = CGRect(
            x: 0, y: 0, width: minuteWidth, height: minuteLength * (1 + tailFrac)
        )
        mainTimeMinuteHand.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        mainTimeMinuteHand.position = a.mainTimeCenter
        mainTimeMinuteHand.path = minutePath
        mainTimeMinuteHand.shadowPath = minutePath

        // Center hub — smaller (0.040) per spec.
        let hubR = r * 0.040
        let hubPath = CGPath(
            ellipseIn: CGRect(x: 0, y: 0, width: hubR * 2, height: hubR * 2),
            transform: nil
        )
        mainTimeCenterHub.frame = CGRect(
            x: cx - hubR, y: cy - hubR,
            width: hubR * 2, height: hubR * 2
        )
        mainTimeCenterHub.path = hubPath
        mainTimeCenterHub.shadowPath = hubPath
    }

    // MARK: Moonphase layout

    private func layoutMoonphase(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.moonphaseCenter.x        // baseline center
        let baseY = a.moonphaseCenter.y
        let hw = a.moonphaseHalfWidth
        let hh = a.moonphaseHalfHeight      // full apex height of the oval
        // Bounding rect of the aperture: width = 2·hw, height = hh, rising
        // upward from the baseline (Lange 1's wide-oval aperture).
        let apertureRect = CGRect(x: cx - hw, y: baseY, width: hw * 2, height: hh)
        let aperturePath = buildAperturePath(in: apertureRect)

        // Sky fills the aperture.
        moonphaseSkyLayer.frame = CGRect(origin: .zero, size: canvas)
        moonphaseSkyLayer.path = aperturePath

        // Stars in the left/right margins of the wide-oval aperture (where
        // the moon disc doesn't cover at the full-moon position). fx is
        // normalized to half-width; fy is normalized to full aperture height.
        // Positions per the design-spec star table.
        let starsPath = CGMutablePath()
        let starOuter = hw * 0.05
        let starInner = starOuter * 0.40
        let starPositions: [(CGFloat, CGFloat)] = [
            (-0.85, 0.40),
            (-0.62, 0.75),
            (-0.45, 0.20),
            (-0.92, 0.18),
            ( 0.45, 0.22),
            ( 0.62, 0.78),
            ( 0.85, 0.40),
            ( 0.92, 0.20),
        ]
        for (fx, fy) in starPositions {
            let sx = cx + fx * hw
            let sy = baseY + fy * hh
            starsPath.addPath(fourPointStar(at: CGPoint(x: sx, y: sy),
                                            outerRadius: starOuter,
                                            innerRadius: starInner))
        }
        moonphaseStarsLayer.frame = CGRect(origin: .zero, size: canvas)
        moonphaseStarsLayer.path = starsPath

        // Stationary container with the aperture mask. The moon translates
        // INSIDE this container (via moonphaseMovingLayer), past the
        // stationary aperture — that's what makes phases visible.
        let containerRect = apertureRect.insetBy(dx: -hw, dy: 0)
        moonphaseDiscContainer.frame = containerRect
        // Mask path in container-local coords.
        let localApertureRect = apertureRect.offsetBy(
            dx: -containerRect.origin.x, dy: -containerRect.origin.y
        )
        let localAperturePath = buildAperturePath(in: localApertureRect)
        let containerMask = CAShapeLayer()
        containerMask.frame = moonphaseDiscContainer.bounds
        containerMask.path = localAperturePath
        containerMask.fillColor = NSColor.white.cgColor
        moonphaseDiscContainer.mask = containerMask

        // Moving layer is the same size as the container (so its coordinate
        // system matches). The moon sits inside the moving layer at the
        // "full moon" position; translating the moving layer slides the moon
        // through the (stationary) aperture mask.
        moonphaseMovingLayer.frame = moonphaseDiscContainer.bounds

        // Moon disc — sized so it nearly touches the top of the upper arch
        // while leaving visible navy on left/right at the full-moon position.
        let discR = hh * 0.72
        let moonCenterLocal = CGPoint(
            x: localApertureRect.midX,
            y: localApertureRect.minY + hh * 0.58
        )
        moonphaseDiscLayer.frame = CGRect(
            x: moonCenterLocal.x - discR, y: moonCenterLocal.y - discR,
            width: discR * 2, height: discR * 2
        )
        moonphaseDiscLayer.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: moonphaseDiscLayer.bounds.size),
            transform: nil
        )

        // Man-in-the-moon: positioned in moonphaseMovingLayer's coords so it
        // tracks with the moon disc.
        moonphaseFaceLayer.frame = moonphaseDiscLayer.frame
        moonphaseFaceLayer.path = buildMoonFacePath(
            in: CGRect(origin: .zero, size: moonphaseFaceLayer.bounds.size)
        )
        moonphaseFaceLayer.lineWidth = max(0.4, discR * 0.06)

        // Gold frame around the aperture perimeter.
        moonphaseFrameLayer.frame = CGRect(origin: .zero, size: canvas)
        moonphaseFrameLayer.path = aperturePath
        moonphaseFrameLayer.lineWidth = max(0.6, hw * 0.055)
        moonphaseFrameLayer.shadowPath = aperturePath

        // Clip the sky, stars, and disc container to the aperture shape.
        applyMoonphaseClip(aperturePath: aperturePath, apertureRect: apertureRect, canvasSize: canvas)
    }

    /// 4-point star path centered at `c` with the specified outer/inner radii.
    private func fourPointStar(at c: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let nPoints = 4
        let totalSteps = nPoints * 2
        for step in 0..<totalSteps {
            let angle = .pi / 2 + CGFloat(step) * (.pi * 2 / CGFloat(totalSteps))
            let r = step % 2 == 0 ? outerRadius : innerRadius
            let p = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Builds the man-in-the-moon "face": two eye dots + a curved smile,
    /// positioned in the local coordinate space of the moon disc (so the
    /// path translates with the disc when the disc container moves).
    private func buildMoonFacePath(in discBounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = discBounds.midX
        let cy = discBounds.midY
        let r = discBounds.width / 2
        let eyeR = r * 0.06
        let eyeOffsetX = r * 0.30
        let eyeOffsetY = r * 0.18
        // Eyes (small filled dots — using strokeColor, lineWidth gives them their look)
        path.addEllipse(in: CGRect(
            x: cx - eyeOffsetX - eyeR, y: cy + eyeOffsetY - eyeR,
            width: eyeR * 2, height: eyeR * 2
        ))
        path.addEllipse(in: CGRect(
            x: cx + eyeOffsetX - eyeR, y: cy + eyeOffsetY - eyeR,
            width: eyeR * 2, height: eyeR * 2
        ))
        // Smile — a downward-opening arc below center (y-up coords: below means smaller y)
        let smileRadius = r * 0.38
        path.addArc(
            center: CGPoint(x: cx, y: cy + r * 0.30),
            radius: smileRadius,
            startAngle: -.pi * 0.85,
            endAngle: -.pi * 0.15,
            clockwise: false
        )
        return path
    }

    /// Build the aperture path: top **elliptical** arc + scalloped bottom
    /// with two subtle upward "rolling hills" cutting into the aperture.
    /// The top arc uses two cubic Beziers so width and height are
    /// independently controllable (`rect.height` ≠ `rect.width / 2`),
    /// matching the Lange 1's wide-horizontal-oval aperture proportion.
    private func buildAperturePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = rect.midX
        let baseY = rect.minY
        let leftX = rect.minX
        let rightX = rect.maxX
        let hw = rect.width / 2
        let hh = rect.height                  // full top-arc height (rect taller-than-half: yes — rect spans baseY..baseY+hh)

        // Hills are SUBTLE — they only need to nibble the bottom of the
        // moon disc as it slides through. Per the Lange 1 reference, the
        // arches are barely perceptible (often hidden behind the hands).
        let hillHalfWidth = hw * 0.30
        let hillGap = hw * 0.10
        let hillHeight = hh * 0.18           // scale relative to aperture height now

        let rightHillLeft = cx + hillGap
        let rightHillRight = rightHillLeft + hillHalfWidth * 2
        let leftHillRight = cx - hillGap
        let leftHillLeft = leftHillRight - hillHalfWidth * 2

        // Quadratic Bezier peak = midpoint of (baseY, controlY).
        let controlYOffset = hillHeight * 2

        // Cubic-Bezier ellipse-arc magic constant: 4·(√2−1)/3 ≈ 0.5523.
        // Approximates a quarter-ellipse using one cubic.
        let kappa: CGFloat = 0.5522847498307933

        path.move(to: CGPoint(x: leftX, y: baseY))
        // Top: two cubic-Bezier segments tracing the upper half of the
        // ellipse (-hw, 0) → (0, hh) → (hw, 0). Each is a quarter-ellipse.
        path.addCurve(
            to: CGPoint(x: cx, y: baseY + hh),
            control1: CGPoint(x: leftX,            y: baseY + hh * kappa),
            control2: CGPoint(x: cx - hw * kappa,  y: baseY + hh)
        )
        path.addCurve(
            to: CGPoint(x: rightX, y: baseY),
            control1: CGPoint(x: cx + hw * kappa,  y: baseY + hh),
            control2: CGPoint(x: rightX,           y: baseY + hh * kappa)
        )
        // Now at (rightX, baseY). Walk leftward across the baseline, with
        // two upward-curving hills cutting INTO the aperture.
        path.addLine(to: CGPoint(x: rightHillRight, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: rightHillLeft, y: baseY),
            control: CGPoint(
                x: (rightHillLeft + rightHillRight) / 2,
                y: baseY + controlYOffset
            )
        )
        path.addLine(to: CGPoint(x: leftHillRight, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: leftHillLeft, y: baseY),
            control: CGPoint(
                x: (leftHillLeft + leftHillRight) / 2,
                y: baseY + controlYOffset
            )
        )
        path.addLine(to: CGPoint(x: leftX, y: baseY))
        path.closeSubpath()
        return path
    }

    private func applyMoonphaseClip(aperturePath: CGPath, apertureRect: CGRect, canvasSize: CGSize) {
        // Clip the sky + stars to the aperture shape. (Disc-container mask
        // is set in `layoutMoonphase` itself — it needs a stationary mask in
        // the container's own local-coord space, independent of canvas.)
        for layer in [moonphaseSkyLayer, moonphaseStarsLayer] {
            let mask = CAShapeLayer()
            mask.frame = CGRect(origin: .zero, size: canvasSize)
            mask.path = aperturePath
            mask.fillColor = NSColor.white.cgColor
            layer.mask = mask
        }
    }

    private func updateMoonphaseTransform(fraction: Double) {
        // Slide the moon disc laterally past the (stationary) aperture mask.
        // The disc container is masked — translating the moving sublayer
        // makes the moon enter, transit, and exit the aperture.
        //
        // Direction convention (northern-hemisphere): at f=0 (new moon) the
        // moon is offscreen to the RIGHT. As f → 0.5 it slides leftward into
        // the aperture, fully visible (full moon) at center. As f → 1.0 it
        // continues leftward and exits to the LEFT.
        guard let a = anchors else { return }
        let hw = a.moonphaseHalfWidth
        let discR = moonphaseDiscLayer.bounds.width / 2
        let xMax = hw + discR
        let dx = xMax * CGFloat(1.0 - 2.0 * fraction)
        moonphaseMovingLayer.setAffineTransform(CGAffineTransform(translationX: dx, y: 0))
    }

    // MARK: Big date layout

    private func layoutBigDate(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.bigDateCenter.x
        let cy = a.bigDateCenter.y
        let h = a.bigDateHeight
        // Two side-by-side gold-framed white boxes (Lange 1 variant).
        let boxW = h * 0.78
        let gap = h * 0.04
        let totalW = boxW * 2 + gap
        let cornerR = h * 0.06              // barely rounded
        let frameInset = h * 0.045          // thin gold frame edge

        let box1Rect = CGRect(
            x: cx - totalW / 2, y: cy - h / 2,
            width: boxW, height: h
        )
        let box2Rect = CGRect(
            x: cx - totalW / 2 + boxW + gap, y: cy - h / 2,
            width: boxW, height: h
        )
        bigDateBox1Rect = box1Rect
        bigDateBox2Rect = box2Rect

        // Gold frame — a slightly larger rounded rect behind each box.
        let frame1Rect = box1Rect.insetBy(dx: -frameInset, dy: -frameInset)
        let frame2Rect = box2Rect.insetBy(dx: -frameInset, dy: -frameInset)
        let frameCornerR = cornerR + frameInset

        let frame1Path = CGPath(
            roundedRect: frame1Rect,
            cornerWidth: frameCornerR, cornerHeight: frameCornerR,
            transform: nil
        )
        let frame2Path = CGPath(
            roundedRect: frame2Rect,
            cornerWidth: frameCornerR, cornerHeight: frameCornerR,
            transform: nil
        )
        bigDateGoldFrame1.frame = CGRect(origin: .zero, size: canvas)
        bigDateGoldFrame1.path = frame1Path
        bigDateGoldFrame1.shadowPath = frame1Path
        bigDateGoldFrame1.lineWidth = max(0.4, h * 0.010)

        bigDateGoldFrame2.frame = CGRect(origin: .zero, size: canvas)
        bigDateGoldFrame2.path = frame2Path
        bigDateGoldFrame2.shadowPath = frame2Path
        bigDateGoldFrame2.lineWidth = max(0.4, h * 0.010)

        bigDateBox1.frame = CGRect(origin: .zero, size: canvas)
        bigDateBox1.path = CGPath(roundedRect: box1Rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

        bigDateBox2.frame = CGRect(origin: .zero, size: canvas)
        bigDateBox2.path = CGPath(roundedRect: box2Rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

        // Numeral font for the big date — Didot-Bold preferred for the
        // Lange-1-like high-contrast serif.
        bigDateNumeralFont = bigDateFont(size: h * 0.82)
        bigDateDigit1Layer.frame = CGRect(origin: .zero, size: canvas)
        bigDateDigit2Layer.frame = CGRect(origin: .zero, size: canvas)

        // Initial digits — will be overwritten by first tick.
        updateBigDateGlyphs(d1: 0, d2: 0)
    }

    /// High-contrast serif font for the big date (Lange-1-style numerals).
    /// Tries Didot-Bold first, then Bodoni 72 Bold, then system serif.
    private func bigDateFont(size: CGFloat) -> NSFont {
        let candidates = [
            "Didot-Bold",
            "BodoniSvtyTwoITCTT-Bold",
            "Bodoni 72 Bold",
            "TimesNewRomanPS-BoldMT",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return serifFont(size: size, bold: true)
    }

    /// Slim serif font for the main time sub-dial Roman numerals. The
    /// Lange 1 reference uses notably narrow serifs — Book/Regular weight,
    /// NOT Bold. Prefer Bodoni 72 Book; fall back to Didot regular, then
    /// the system serif.
    private func romanNumeralFont(size: CGFloat) -> NSFont {
        let candidates = [
            "BodoniSvtyTwoITCTT-Book",
            "Bodoni 72 Book",
            "Didot",
            "TimesNewRomanPSMT",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return serifFont(size: size, bold: false)
    }

    private func updateBigDateGlyphs(d1: Int, d2: Int) {
        guard let font = bigDateNumeralFont else { return }
        let p1 = centeredDigitPath(digit: d1, in: bigDateBox1Rect, font: font)
        let p2 = centeredDigitPath(digit: d2, in: bigDateBox2Rect, font: font)
        bigDateDigit1Layer.path = p1
        bigDateDigit1Layer.shadowPath = p1
        bigDateDigit2Layer.path = p2
        bigDateDigit2Layer.shadowPath = p2
    }

    private func centeredDigitPath(digit: Int, in rect: CGRect, font: NSFont) -> CGPath? {
        let str = "\(max(0, min(9, digit)))"
        guard let glyphs = textPath(string: str, font: font) else { return nil }
        let bounds = glyphs.boundingBox
        let tx = rect.midX - bounds.midX
        let ty = rect.midY - bounds.midY
        var transform = CGAffineTransform(translationX: tx, y: ty)
        return glyphs.copy(using: &transform)
    }

    // MARK: Sub-seconds layout

    private func layoutSubSeconds(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.subSecondsCenter.x
        let cy = a.subSecondsCenter.y
        let r = a.subSecondsRadius

        let faceRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        let faceCirclePathCanvas = CGPath(ellipseIn: faceRect, transform: nil)
        subSecondsFaceLayer.frame = CGRect(origin: .zero, size: canvas)
        subSecondsFaceLayer.path = faceCirclePathCanvas
        subSecondsFaceLayer.lineWidth = max(0.4, r * 0.020)

        let subFaceCirclePath = CGPath(
            ellipseIn: CGRect(origin: .zero, size: faceRect.size), transform: nil
        )

        subSecondsRecessShade.frame = faceRect
        let recessMask = CAShapeLayer()
        recessMask.path = subFaceCirclePath
        recessMask.fillColor = NSColor.white.cgColor
        subSecondsRecessShade.mask = recessMask

        subSecondsGlossLayer.frame = faceRect
        let glossMask = CAShapeLayer()
        glossMask.path = subFaceCirclePath
        glossMask.fillColor = NSColor.white.cgColor
        subSecondsGlossLayer.mask = glossMask

        // Rim shadow + lower-half highlight (same recipe as main time).
        subSecondsRimUpperShadow.frame = CGRect(origin: .zero, size: canvas)
        subSecondsRimUpperShadow.path = faceCirclePathCanvas
        subSecondsRimUpperShadow.lineWidth = max(0.5, r * 0.020)
        subSecondsRimUpperShadow.shadowOffset = CGSize(width: 0, height: -r * 0.010)
        subSecondsRimUpperShadow.shadowRadius = r * 0.010
        subSecondsRimUpperShadow.shadowPath = faceCirclePathCanvas

        subSecondsRimLowerHighlight.frame = CGRect(origin: .zero, size: canvas)
        subSecondsRimLowerHighlight.path = faceCirclePathCanvas
        subSecondsRimLowerHighlight.lineWidth = max(0.3, r * 0.012)
        let subLowerHalfMask = CAShapeLayer()
        subLowerHalfMask.path = CGPath(rect: CGRect(
            x: faceRect.minX, y: faceRect.minY,
            width: faceRect.width, height: faceRect.height * 0.40
        ), transform: nil)
        subLowerHalfMask.fillColor = NSColor.white.cgColor
        subSecondsRimLowerHighlight.mask = subLowerHalfMask

        // Minor ticks (every minute except multiples of 5) and major ticks
        // (every 5 seconds) live in separate layers so the line widths can
        // differ per the reference's clear major/minor hierarchy.
        let minorTicksPath = CGMutablePath()
        let majorTicksPath = CGMutablePath()
        let outer = r * 0.95
        let majorInner = r * 0.80
        let minorInner = r * 0.88
        for i in 0..<60 {
            let theta = .pi / 2 - (CGFloat(i) / 60) * 2 * .pi
            let dx = cos(theta), dy = sin(theta)
            let isFive = i % 5 == 0
            let innerR = isFive ? majorInner : minorInner
            let p1 = CGPoint(x: cx + dx * innerR, y: cy + dy * innerR)
            let p2 = CGPoint(x: cx + dx * outer, y: cy + dy * outer)
            if isFive {
                majorTicksPath.move(to: p1)
                majorTicksPath.addLine(to: p2)
            } else {
                minorTicksPath.move(to: p1)
                minorTicksPath.addLine(to: p2)
            }
        }
        subSecondsTicksLayer.frame = CGRect(origin: .zero, size: canvas)
        subSecondsTicksLayer.path = minorTicksPath
        subSecondsTicksLayer.lineWidth = max(0.3, r * 0.018)
        subSecondsTicksLayer.lineCap = .butt

        subSecondsTicksMajorLayer.frame = CGRect(origin: .zero, size: canvas)
        subSecondsTicksMajorLayer.path = majorTicksPath
        subSecondsTicksMajorLayer.lineWidth = max(0.5, r * 0.030)
        subSecondsTicksMajorLayer.lineCap = .butt

        // Numerals at 60 / 10 / 20 / 30 / 40 / 50 (Arabic).
        let numerals = ["60", "10", "20", "30", "40", "50"]
        let numeralRadius = r * 0.68
        let numeralFontSize = r * 0.22
        let numeralFont = serifFont(size: numeralFontSize, bold: false)
        let numeralsPath = CGMutablePath()
        for (i, str) in numerals.enumerated() {
            let theta = .pi / 2 - (CGFloat(i) / 6) * 2 * .pi
            let nx = cx + cos(theta) * numeralRadius
            let ny = cy + sin(theta) * numeralRadius
            if let glyphs = textPath(string: str, font: numeralFont) {
                let bounds = glyphs.boundingBox
                let tx = nx - bounds.midX
                let ty = ny - bounds.midY
                let t = CGAffineTransform(translationX: tx, y: ty)
                numeralsPath.addPath(glyphs, transform: t)
            }
        }
        subSecondsNumeralsLayer.frame = CGRect(origin: .zero, size: canvas)
        subSecondsNumeralsLayer.path = numeralsPath

        // Hand — slim needle, no counterweight tail (confirmed in reference).
        let handLength = r * 0.85
        let handWidth = r * 0.06
        let secondsHandPath = goldHandPath(width: handWidth, length: handLength, taper: false)
        subSecondsHand.bounds = CGRect(x: 0, y: 0, width: handWidth, height: handLength)
        subSecondsHand.position = a.subSecondsCenter
        subSecondsHand.path = secondsHandPath
        subSecondsHand.shadowPath = secondsHandPath

        // Hub
        let hubR = r * 0.06
        let subHubPath = CGPath(
            ellipseIn: CGRect(x: 0, y: 0, width: hubR * 2, height: hubR * 2),
            transform: nil
        )
        subSecondsHub.frame = CGRect(
            x: cx - hubR, y: cy - hubR,
            width: hubR * 2, height: hubR * 2
        )
        subSecondsHub.path = subHubPath
        subSecondsHub.shadowPath = subHubPath
    }

    // MARK: Power reserve layout

    private func layoutPowerReserve(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.powerReserveCenter.x
        let cy = a.powerReserveCenter.y
        let r = a.powerReserveRadius

        // Power reserve arc on the RIGHT edge, opening LEFT. Narrower
        // angular span (~75°) than 90° gives the Lange's tall-vertical feel.
        let arcSpan: CGFloat = .pi / 2.4
        let aufAngle: CGFloat = arcSpan / 2     // upper-right
        let abAngle: CGFloat = -arcSpan / 2     // lower-right
        powerReserveAUFAngle = aufAngle
        powerReserveABAngle = abAngle
        powerReservePivot = CGPoint(x: cx, y: cy)

        // Two separate tick layers: lightweight minors at the perimeter
        // (faint) and major ticks at AUF / midpoint / AB (darker, longer).
        let minorTicksPath = CGMutablePath()
        let majorTicksPath = CGMutablePath()
        let tickCount = 8
        let tickOuter = r
        let minorInner = r * 0.92
        let majorInner = r * 0.82
        for i in 0...tickCount {
            let t = CGFloat(i) / CGFloat(tickCount)
            let angle = aufAngle - t * (aufAngle - abAngle)
            let isMajor = (i == 0) || (i == tickCount / 2) || (i == tickCount)
            let innerR = isMajor ? majorInner : minorInner
            let dx = cos(angle), dy = sin(angle)
            let p1 = CGPoint(x: cx + dx * innerR, y: cy + dy * innerR)
            let p2 = CGPoint(x: cx + dx * tickOuter, y: cy + dy * tickOuter)
            if isMajor {
                majorTicksPath.move(to: p1)
                majorTicksPath.addLine(to: p2)
            } else {
                minorTicksPath.move(to: p1)
                minorTicksPath.addLine(to: p2)
            }
        }
        powerReserveArcLayer.frame = CGRect(origin: .zero, size: canvas)
        powerReserveArcLayer.path = minorTicksPath
        powerReserveArcLayer.lineWidth = max(0.3, r * 0.014)
        powerReserveArcLayer.lineCap = .butt

        powerReserveTicksMajorLayer.frame = CGRect(origin: .zero, size: canvas)
        powerReserveTicksMajorLayer.path = majorTicksPath
        powerReserveTicksMajorLayer.lineWidth = max(0.5, r * 0.030)
        powerReserveTicksMajorLayer.lineCap = .butt

        // Red triangles at AUF + AB ends — point OUTWARD (away from pivot).
        let triR = r * 0.085
        let trianglesPath = CGMutablePath()
        for angle in [aufAngle, abAngle] {
            let baseCx = cx + cos(angle) * r
            let baseCy = cy + sin(angle) * r
            let tipX = cx + cos(angle) * (r + triR * 0.9)
            let tipY = cy + sin(angle) * (r + triR * 0.9)
            let perpA = angle + .pi / 2
            let cornerAX = baseCx + cos(perpA) * triR * 0.5
            let cornerAY = baseCy + sin(perpA) * triR * 0.5
            let cornerBX = baseCx - cos(perpA) * triR * 0.5
            let cornerBY = baseCy - sin(perpA) * triR * 0.5
            trianglesPath.move(to: CGPoint(x: tipX, y: tipY))
            trianglesPath.addLine(to: CGPoint(x: cornerAX, y: cornerAY))
            trianglesPath.addLine(to: CGPoint(x: cornerBX, y: cornerBY))
            trianglesPath.closeSubpath()
        }
        powerReserveRedTrianglesLayer.frame = CGRect(origin: .zero, size: canvas)
        powerReserveRedTrianglesLayer.path = trianglesPath

        // Labels: AUF (top), AB (bottom). Smaller serif text inside the arc.
        let labelFontSize = r * 0.18
        let labelFont = serifFont(size: labelFontSize, bold: false)
        let labelsPath = CGMutablePath()
        let labelInner = r * 0.60
        for (text, angle) in [("AUF", aufAngle), ("AB", abAngle)] {
            let lx = cx + cos(angle) * labelInner
            let ly = cy + sin(angle) * labelInner
            if let glyphs = textPath(string: text, font: labelFont) {
                let bounds = glyphs.boundingBox
                let tx = lx - bounds.midX
                let ty = ly - bounds.midY
                let t = CGAffineTransform(translationX: tx, y: ty)
                labelsPath.addPath(glyphs, transform: t)
            }
        }
        powerReserveLabelsLayer.frame = CGRect(origin: .zero, size: canvas)
        powerReserveLabelsLayer.path = labelsPath

        // Indicator hand — slim lance with counterweight tail; no hub disc
        // (pivot is hidden behind the bezel edge in the reference).
        let tailFrac = Self.handTailFraction
        let anchorY = tailFrac / (1 + tailFrac)
        let handLength = r * 0.82
        let handWidth = r * 0.14
        let prHandPath = goldHandPath(width: handWidth, length: handLength, taper: true)
        powerReserveIndicatorHand.bounds = CGRect(
            x: 0, y: 0, width: handWidth, height: handLength * (1 + tailFrac)
        )
        powerReserveIndicatorHand.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        powerReserveIndicatorHand.position = a.powerReserveCenter
        powerReserveIndicatorHand.path = prHandPath
        powerReserveIndicatorHand.shadowPath = prHandPath
    }

    private func updatePowerReserveHand(fraction: Double) {
        // Interpolate between AB (fraction=0) and AUF (fraction=1).
        let f = CGFloat(max(0.0, min(1.0, fraction)))
        // The hand's default orientation (no rotation) points UP (toward 12).
        // We want fraction=1 → hand points along AUF angle (upper-left of pivot).
        // The hand's pivot is at powerReservePivot. We need to rotate it to
        // match the target angle on the arc.
        //
        // Target angle on arc (interpolated): aufAngle (when f=1) → abAngle (when f=0).
        let targetAngle = powerReserveABAngle + f * (powerReserveAUFAngle - powerReserveABAngle)
        // The hand "up" direction is +y (angle π/2). We need to rotate it to
        // point along `targetAngle`. Rotation needed = targetAngle - π/2.
        // But `CGAffineTransform.rotationAngle` is CCW-positive in y-up coords.
        // To rotate the hand from "up" to `targetAngle`, the CCW rotation is
        // `targetAngle - π/2`. Positive = CCW.
        let rotation = targetAngle - .pi / 2
        powerReserveIndicatorHand.setAffineTransform(CGAffineTransform(rotationAngle: rotation))
    }

    // MARK: Helpers

    /// Returns a serif `NSFont`, falling back gracefully if a specific family
    /// isn't available. Uses the system-provided "Times New Roman" family
    /// which ships with macOS.
    private func serifFont(size: CGFloat, bold: Bool) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        // Prefer the system serif design (NSFont.systemFont with a serif descriptor)
        if let descriptor = NSFont.systemFont(ofSize: size, weight: weight)
            .fontDescriptor.withDesign(.serif),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        // Fallback: Times New Roman by name.
        return NSFont(name: bold ? "Times New Roman Bold" : "Times New Roman", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Renders the given string as a single combined `CGPath` of all its
    /// glyph outlines, anchored at the origin. Caller is responsible for
    /// transforming to the desired position.
    ///
    /// Returns `nil` if the string is empty or text-rendering fails.
    private func textPath(string: String, font: NSFont) -> CGPath? {
        guard !string.isEmpty else { return nil }
        let attrString = NSAttributedString(
            string: string,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let path = CGMutablePath()
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let runAttrs = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = runAttrs[kCTFontAttributeName as String] else { continue }
            let ctFont = runFont as! CTFont
            for i in 0..<count {
                if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) {
                    let t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                    path.addPath(glyphPath, transform: t)
                }
            }
        }
        return path.isEmpty ? nil : path
    }

    /// Lange-1 lance hand path. SOLID gold blade with a symmetric lozenge
    /// near the tip. `width` is the diamond's peak width, `length` is
    /// forward-from-pivot reach. Includes a counterweight tail of
    /// `tailFraction × length` extending behind the pivot, and optionally a
    /// circular pivot eye (minute-hand signature; renders as a hole with
    /// `.evenOdd` fill rule on the host layer).
    private func goldHandPath(
        width: CGFloat,
        length: CGFloat,
        taper: Bool,
        withHole: Bool = false
    ) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        if taper {
            let tailL = length * Self.handTailFraction
            let shaftW = width * 0.18            // slim shaft
            let tailW = width * 0.55             // small lozenge at the tail end
            let diamondW = width                 // peak blade width = input width
            // Symmetric blade (lozenge from 42% to 92% of forward length,
            // peak at 66%) per the design spec.
            let diamondStartY = tailL + length * 0.42
            let diamondPeakY = tailL + length * 0.66
            let tipNarrowY = tailL + length * 0.92
            let tipY = tailL + length

            path.move(to: CGPoint(x: cx, y: 0))
            path.addLine(to: CGPoint(x: cx + tailW / 2, y: tailL * 0.55))
            path.addLine(to: CGPoint(x: cx + shaftW / 2, y: tailL))
            path.addLine(to: CGPoint(x: cx + shaftW / 2, y: diamondStartY))
            path.addLine(to: CGPoint(x: cx + diamondW / 2, y: diamondPeakY))
            path.addLine(to: CGPoint(x: cx + shaftW / 3, y: tipNarrowY))
            path.addLine(to: CGPoint(x: cx, y: tipY))
            path.addLine(to: CGPoint(x: cx - shaftW / 3, y: tipNarrowY))
            path.addLine(to: CGPoint(x: cx - diamondW / 2, y: diamondPeakY))
            path.addLine(to: CGPoint(x: cx - shaftW / 2, y: diamondStartY))
            path.addLine(to: CGPoint(x: cx - shaftW / 2, y: tailL))
            path.addLine(to: CGPoint(x: cx - tailW / 2, y: tailL * 0.55))
            path.closeSubpath()

            if withHole {
                // Circular eye near the pivot — minute-hand signature.
                // With .evenOdd fill rule on the layer, this renders as a hole.
                let holeR = shaftW * 1.6
                let holeY = tailL + holeR * 1.4
                path.addEllipse(in: CGRect(
                    x: cx - holeR, y: holeY - holeR,
                    width: holeR * 2, height: holeR * 2
                ))
            }
        } else {
            // Slim gold needle, no counterweight tail (sub-seconds hand) per
            // design-spec vertex coords.
            let baseHalf = width * 0.45
            path.move(to: CGPoint(x: cx - baseHalf, y: 0))
            path.addLine(to: CGPoint(x: cx + baseHalf, y: 0))
            path.addLine(to: CGPoint(x: cx + baseHalf * 0.40, y: length * 0.88))
            path.addLine(to: CGPoint(x: cx, y: length))
            path.addLine(to: CGPoint(x: cx - baseHalf * 0.40, y: length * 0.88))
            path.closeSubpath()
        }
        return path
    }

    /// Fraction of forward length that the counterweight tail extends behind
    /// the pivot for tapered (Lange-style) hands. Tail is small but visible.
    private static let handTailFraction: CGFloat = 0.20
}
