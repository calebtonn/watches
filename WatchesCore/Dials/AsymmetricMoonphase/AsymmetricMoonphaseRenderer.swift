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
    private let mainTimeOuterRing = CAShapeLayer()
    private let mainTimeNumeralsLayer = CAShapeLayer()
    private let mainTimeTicksLayer = CAShapeLayer()
    private let mainTimeHourHand = CAShapeLayer()
    private let mainTimeMinuteHand = CAShapeLayer()
    private let mainTimeCenterHub = CAShapeLayer()

    // MARK: Moonphase aperture layers

    private let moonphaseClipShape = CAShapeLayer()  // mask for the aperture
    private let moonphaseSkyLayer = CAShapeLayer()    // navy background
    private let moonphaseDiscLayer = CAShapeLayer()   // gold moon (stationary)
    private let moonphaseOcculterLayer = CAShapeLayer()  // navy disc that translates over the moon for phase
    private let moonphaseStarsLayer = CAShapeLayer()  // decorative stars
    private let moonphaseFrameLayer = CAShapeLayer()  // gold rim around the aperture
    /// Container that holds the moon + occulter; we apply translation to the
    /// occulter inside this container to fake lunar phases.
    private let moonphaseDiscContainer = CALayer()

    // MARK: Big date window layers

    private let bigDateGoldFrame1 = CAShapeLayer()
    private let bigDateGoldFrame2 = CAShapeLayer()
    private let bigDateBox1 = CAShapeLayer()
    private let bigDateBox2 = CAShapeLayer()
    private let bigDateDigit1Layer = CAShapeLayer()
    private let bigDateDigit2Layer = CAShapeLayer()
    private let bigDateSeparator = CAShapeLayer()
    private var bigDateBox1Rect: CGRect = .zero
    private var bigDateBox2Rect: CGRect = .zero
    private var bigDateNumeralFont: NSFont?

    // MARK: Sub-seconds dial layers

    private let subSecondsFaceLayer = CAShapeLayer()
    private let subSecondsRecessShade = CAGradientLayer()
    private let subSecondsNumeralsLayer = CAShapeLayer()
    private let subSecondsTicksLayer = CAShapeLayer()
    private let subSecondsHand = CAShapeLayer()
    private let subSecondsHub = CAShapeLayer()

    // MARK: Power reserve indicator layers

    private let powerReserveArcLayer = CAShapeLayer()
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

        // Gold bezel — vertical gradient with subtle diagonal tilt.
        bezelLayer.name = "asymmetric.bezel"
        bezelLayer.colors = [
            AsymmetricMoonphasePalette.caseGoldHighlight,
            AsymmetricMoonphasePalette.caseGold,
            AsymmetricMoonphasePalette.caseGoldShadow,
        ]
        bezelLayer.locations = [0.0, 0.55, 1.0]
        bezelLayer.startPoint = CGPoint(x: 0.25, y: 1.0)
        bezelLayer.endPoint = CGPoint(x: 0.75, y: 0.0)
        bezelMaskShape.fillColor = NSColor.white.cgColor
        bezelLayer.mask = bezelMaskShape
        caseBackgroundLayer.addSublayer(bezelLayer)

        // Outer rim light (thin bright stroke).
        bezelRimLight.name = "asymmetric.bezel.rim"
        bezelRimLight.fillColor = nil
        bezelRimLight.strokeColor = AsymmetricMoonphasePalette.caseRim
        caseBackgroundLayer.addSublayer(bezelRimLight)

        // Inner shadow stroke at the bezel/dial boundary.
        bezelInnerShadow.name = "asymmetric.bezel.innerShadow"
        bezelInnerShadow.fillColor = nil
        bezelInnerShadow.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
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

        // Recess shade — subtle dark-at-top / light-at-bottom overlay clipped
        // to the sub-dial face. Sells the "this dial is sunken into the plate"
        // skeuomorphic effect without any gold rim.
        mainTimeRecessShade.startPoint = CGPoint(x: 0.5, y: 1.0)
        mainTimeRecessShade.endPoint = CGPoint(x: 0.5, y: 0.0)
        mainTimeRecessShade.colors = [
            NSColor(white: 0.0, alpha: 0.32).cgColor,
            NSColor(white: 0.0, alpha: 0.06).cgColor,
            NSColor(white: 1.0, alpha: 0.18).cgColor,
        ]
        mainTimeRecessShade.locations = [0.0, 0.55, 1.0]
        caseBackgroundLayer.addSublayer(mainTimeRecessShade)

        // Inner-boundary shadow ring (replaces gold ring) — dark thin stroke
        // just inside the face perimeter to define the recessed edge.
        mainTimeOuterRing.fillColor = nil
        mainTimeOuterRing.strokeColor = AsymmetricMoonphasePalette.subDialShadow
        caseBackgroundLayer.addSublayer(mainTimeOuterRing)

        mainTimeTicksLayer.fillColor = nil
        mainTimeTicksLayer.strokeColor = AsymmetricMoonphasePalette.numeralBlack
        caseBackgroundLayer.addSublayer(mainTimeTicksLayer)

        mainTimeNumeralsLayer.fillColor = AsymmetricMoonphasePalette.numeralBlack
        mainTimeNumeralsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(mainTimeNumeralsLayer)

        // Moonphase — z-order: sky → stars → disc → clip-mask (applied as
        // layer.mask on a container).
        moonphaseClipShape.fillColor = NSColor.white.cgColor
        moonphaseSkyLayer.fillColor = AsymmetricMoonphasePalette.moonSky
        moonphaseSkyLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(moonphaseSkyLayer)

        moonphaseStarsLayer.fillColor = AsymmetricMoonphasePalette.starGold
        moonphaseStarsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(moonphaseStarsLayer)

        moonphaseDiscContainer.addSublayer(moonphaseDiscLayer)
        moonphaseDiscLayer.fillColor = AsymmetricMoonphasePalette.moonGold
        moonphaseDiscLayer.strokeColor = nil
        // Occulter rides INSIDE the disc container, on top of the moon disc.
        // We translate this layer left/right based on the current lunar phase.
        moonphaseDiscContainer.addSublayer(moonphaseOcculterLayer)
        moonphaseOcculterLayer.fillColor = AsymmetricMoonphasePalette.moonSky
        moonphaseOcculterLayer.strokeColor = nil
        moonphaseOcculterLayer.actions = ["transform": NSNull(), "position": NSNull()]
        caseBackgroundLayer.addSublayer(moonphaseDiscContainer)

        // Thin gold frame around the aperture perimeter.
        moonphaseFrameLayer.fillColor = nil
        moonphaseFrameLayer.strokeColor = AsymmetricMoonphasePalette.handGold
        caseBackgroundLayer.addSublayer(moonphaseFrameLayer)

        // Hands — anchor at bottom-center, rotation pivots at sub-dial center.
        mainTimeHourHand.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeHourHand.strokeColor = nil
        mainTimeHourHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        mainTimeHourHand.actions = ["transform": NSNull(), "position": NSNull()]
        caseBackgroundLayer.addSublayer(mainTimeHourHand)

        mainTimeMinuteHand.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeMinuteHand.strokeColor = nil
        mainTimeMinuteHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        mainTimeMinuteHand.actions = ["transform": NSNull(), "position": NSNull()]
        caseBackgroundLayer.addSublayer(mainTimeMinuteHand)

        mainTimeCenterHub.fillColor = AsymmetricMoonphasePalette.handGold
        mainTimeCenterHub.strokeColor = nil
        caseBackgroundLayer.addSublayer(mainTimeCenterHub)

        // Big date — gold frame BEHIND, then white inner box, then digits.
        bigDateGoldFrame1.fillColor = AsymmetricMoonphasePalette.handGold
        bigDateGoldFrame1.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        caseBackgroundLayer.addSublayer(bigDateGoldFrame1)

        bigDateGoldFrame2.fillColor = AsymmetricMoonphasePalette.handGold
        bigDateGoldFrame2.strokeColor = AsymmetricMoonphasePalette.caseGoldShadow
        caseBackgroundLayer.addSublayer(bigDateGoldFrame2)

        bigDateBox1.fillColor = AsymmetricMoonphasePalette.dateBackground
        bigDateBox1.strokeColor = nil
        caseBackgroundLayer.addSublayer(bigDateBox1)

        bigDateBox2.fillColor = AsymmetricMoonphasePalette.dateBackground
        bigDateBox2.strokeColor = nil
        caseBackgroundLayer.addSublayer(bigDateBox2)

        bigDateSeparator.fillColor = AsymmetricMoonphasePalette.dateSeparator
        bigDateSeparator.strokeColor = nil
        caseBackgroundLayer.addSublayer(bigDateSeparator)

        // Drop shadow on the digits so they sit physically on the white plate.
        bigDateDigit1Layer.fillColor = AsymmetricMoonphasePalette.dateNumeral
        bigDateDigit1Layer.strokeColor = nil
        bigDateDigit1Layer.shadowColor = NSColor.black.cgColor
        bigDateDigit1Layer.shadowOpacity = 0.35
        bigDateDigit1Layer.shadowOffset = CGSize(width: 0.6, height: -1.0)
        bigDateDigit1Layer.shadowRadius = 1.2
        caseBackgroundLayer.addSublayer(bigDateDigit1Layer)

        bigDateDigit2Layer.fillColor = AsymmetricMoonphasePalette.dateNumeral
        bigDateDigit2Layer.strokeColor = nil
        bigDateDigit2Layer.shadowColor = NSColor.black.cgColor
        bigDateDigit2Layer.shadowOpacity = 0.35
        bigDateDigit2Layer.shadowOffset = CGSize(width: 0.6, height: -1.0)
        bigDateDigit2Layer.shadowRadius = 1.2
        caseBackgroundLayer.addSublayer(bigDateDigit2Layer)

        // Sub-seconds — same recess treatment as main time.
        subSecondsFaceLayer.fillColor = AsymmetricMoonphasePalette.subDialFace
        subSecondsFaceLayer.strokeColor = AsymmetricMoonphasePalette.subDialShadow
        caseBackgroundLayer.addSublayer(subSecondsFaceLayer)

        subSecondsRecessShade.startPoint = CGPoint(x: 0.5, y: 1.0)
        subSecondsRecessShade.endPoint = CGPoint(x: 0.5, y: 0.0)
        subSecondsRecessShade.colors = [
            NSColor(white: 0.0, alpha: 0.32).cgColor,
            NSColor(white: 0.0, alpha: 0.06).cgColor,
            NSColor(white: 1.0, alpha: 0.18).cgColor,
        ]
        subSecondsRecessShade.locations = [0.0, 0.55, 1.0]
        caseBackgroundLayer.addSublayer(subSecondsRecessShade)

        subSecondsTicksLayer.fillColor = nil
        subSecondsTicksLayer.strokeColor = AsymmetricMoonphasePalette.subDialNumeral
        caseBackgroundLayer.addSublayer(subSecondsTicksLayer)

        subSecondsNumeralsLayer.fillColor = AsymmetricMoonphasePalette.subDialNumeral
        subSecondsNumeralsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(subSecondsNumeralsLayer)

        subSecondsHand.fillColor = AsymmetricMoonphasePalette.handGold
        subSecondsHand.strokeColor = nil
        subSecondsHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        subSecondsHand.actions = ["transform": NSNull(), "position": NSNull()]
        caseBackgroundLayer.addSublayer(subSecondsHand)

        subSecondsHub.fillColor = AsymmetricMoonphasePalette.handGold
        caseBackgroundLayer.addSublayer(subSecondsHub)

        // Power reserve
        powerReserveArcLayer.fillColor = nil
        powerReserveArcLayer.strokeColor = AsymmetricMoonphasePalette.powerReserveTrack
        caseBackgroundLayer.addSublayer(powerReserveArcLayer)

        powerReserveRedTrianglesLayer.fillColor = AsymmetricMoonphasePalette.powerReserveRed
        powerReserveRedTrianglesLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(powerReserveRedTrianglesLayer)

        powerReserveLabelsLayer.fillColor = AsymmetricMoonphasePalette.subDialNumeral
        powerReserveLabelsLayer.strokeColor = nil
        caseBackgroundLayer.addSublayer(powerReserveLabelsLayer)

        powerReserveIndicatorHand.fillColor = AsymmetricMoonphasePalette.handGold
        powerReserveIndicatorHand.strokeColor = nil
        powerReserveIndicatorHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        powerReserveIndicatorHand.actions = ["transform": NSNull(), "position": NSNull()]
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

        // Dial — inner circle at ~88% of case radius (bezel thickness = 12%).
        let dialRadius = caseRadius * 0.88
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

        // Per-readout anchors (canvas-coords). Tuned in the Story 1.6 polish
        // pass: main time bigger, big-date/sub-seconds slid right to clear it,
        // power reserve sized down and pulled inward.
        let mainTimeCenter = CGPoint(
            x: caseCenter.x - dialRadius * 0.22,
            y: caseCenter.y + dialRadius * 0.02
        )
        let mainTimeRadius = dialRadius * 0.48

        // Moonphase aperture inside main time sub-dial. `moonphaseCenter`
        // is the BASELINE-center of the aperture (the flat-with-bites edge);
        // the top of the aperture is a semicircle of radius == halfWidth.
        let moonphaseCenter = CGPoint(
            x: mainTimeCenter.x,
            y: mainTimeCenter.y + mainTimeRadius * 0.30
        )
        let moonphaseHalfWidth = mainTimeRadius * 0.40
        let moonphaseHalfHeight = moonphaseHalfWidth   // semicircular top

        // Big date — top-right
        let bigDateCenter = CGPoint(
            x: caseCenter.x + dialRadius * 0.42,
            y: caseCenter.y + dialRadius * 0.45
        )
        let bigDateHeight = dialRadius * 0.22

        // Sub-seconds — bottom-right
        let subSecondsCenter = CGPoint(
            x: caseCenter.x + dialRadius * 0.38,
            y: caseCenter.y - dialRadius * 0.42
        )
        let subSecondsRadius = dialRadius * 0.20

        // Power reserve — right side, in the negative space between big date
        // and sub-seconds. Smaller arc + sized for tick-mark display.
        let powerReserveCenter = CGPoint(
            x: caseCenter.x + dialRadius * 0.62,
            y: caseCenter.y - dialRadius * 0.02
        )
        let powerReserveRadius = dialRadius * 0.18

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

        // Recess gradient — masked to the face circle, applied in the
        // sub-dial's local coordinate space so the gradient spans only the
        // face (not the whole canvas).
        mainTimeRecessShade.frame = faceRect
        let recessMask = CAShapeLayer()
        recessMask.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: faceRect.size), transform: nil
        )
        recessMask.fillColor = NSColor.white.cgColor
        mainTimeRecessShade.mask = recessMask

        // Inner-boundary shadow stroke (replaces the old gold ring).
        mainTimeOuterRing.frame = CGRect(origin: .zero, size: canvas)
        mainTimeOuterRing.path = CGPath(ellipseIn: faceRect, transform: nil)
        mainTimeOuterRing.lineWidth = max(0.5, r * 0.012)

        // Tick marks — long at 4 cardinals, short at others
        let ticksPath = CGMutablePath()
        let outerTickR = r * 0.93
        let shortTickInner = r * 0.85
        let longTickInner = r * 0.78
        for i in 0..<12 {
            let theta = .pi / 2 - (CGFloat(i) / 12) * 2 * .pi
            let dx = cos(theta)
            let dy = sin(theta)
            let isCardinal = i % 3 == 0  // 12, 3, 6, 9
            let inner = isCardinal ? longTickInner : shortTickInner
            ticksPath.move(to: CGPoint(x: cx + dx * inner, y: cy + dy * inner))
            ticksPath.addLine(to: CGPoint(x: cx + dx * outerTickR, y: cy + dy * outerTickR))
        }
        // Minute ticks (60 small dots near the rim)
        let minuteTickR = r * 0.97
        let minuteTickInner = r * 0.92
        for i in 0..<60 where i % 5 != 0 {
            let theta = .pi / 2 - (CGFloat(i) / 60) * 2 * .pi
            let dx = cos(theta)
            let dy = sin(theta)
            ticksPath.move(to: CGPoint(x: cx + dx * minuteTickInner, y: cy + dy * minuteTickInner))
            ticksPath.addLine(to: CGPoint(x: cx + dx * minuteTickR, y: cy + dy * minuteTickR))
        }
        mainTimeTicksLayer.frame = CGRect(origin: .zero, size: canvas)
        mainTimeTicksLayer.path = ticksPath
        mainTimeTicksLayer.lineWidth = max(0.5, r * 0.020)
        mainTimeTicksLayer.lineCap = .round

        // Roman numerals at 12 / 3 / 6 / 9 — drawn via Core Text glyph paths
        // for crisp serif rendering. (Sub-dial Roman numerals are a Lange 1
        // signature; they're black, serif, slightly larger than the ticks.)
        let romans = ["XII", "III", "VI", "IX"]
        let romanAngles: [CGFloat] = [
            .pi / 2,     // 12 (top)
            0,           // 3 (right)
            -.pi / 2,    // 6 (bottom)
            .pi,         // 9 (left)
        ]
        let romanRadius = r * 0.68
        let romanFontSize = r * 0.20
        let romanFont = serifFont(size: romanFontSize, bold: false)
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

        // Hands
        let hourLength = r * 0.56
        let hourWidth = r * 0.075
        mainTimeHourHand.bounds = CGRect(x: 0, y: 0, width: hourWidth, height: hourLength)
        mainTimeHourHand.position = a.mainTimeCenter
        mainTimeHourHand.path = goldHandPath(width: hourWidth, length: hourLength, taper: true)

        let minuteLength = r * 0.82
        let minuteWidth = r * 0.05
        mainTimeMinuteHand.bounds = CGRect(x: 0, y: 0, width: minuteWidth, height: minuteLength)
        mainTimeMinuteHand.position = a.mainTimeCenter
        mainTimeMinuteHand.path = goldHandPath(width: minuteWidth, length: minuteLength, taper: true)

        // Center hub
        let hubR = r * 0.05
        mainTimeCenterHub.frame = CGRect(
            x: cx - hubR, y: cy - hubR,
            width: hubR * 2, height: hubR * 2
        )
        mainTimeCenterHub.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: mainTimeCenterHub.frame.size),
            transform: nil
        )
    }

    // MARK: Moonphase layout

    private func layoutMoonphase(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.moonphaseCenter.x        // baseline center
        let baseY = a.moonphaseCenter.y
        let hw = a.moonphaseHalfWidth
        // Bounding rect of the aperture: full-width × semicircle-height,
        // rising upward from the baseline.
        let apertureRect = CGRect(x: cx - hw, y: baseY, width: hw * 2, height: hw)
        let aperturePath = buildAperturePath(in: apertureRect)

        // Sky fills the aperture.
        moonphaseSkyLayer.frame = CGRect(origin: .zero, size: canvas)
        moonphaseSkyLayer.path = aperturePath

        // Stars (decorative): a handful inside the upper region of the aperture.
        let starsPath = CGMutablePath()
        let starR = hw * 0.04
        let starPositions: [(CGFloat, CGFloat)] = [
            (-0.55, 0.30),
            (-0.20, 0.65),
            ( 0.10, 0.85),
            ( 0.45, 0.55),
            ( 0.70, 0.25),
        ]
        for (fx, fy) in starPositions {
            let sx = cx + fx * hw
            let sy = baseY + fy * hw
            starsPath.addEllipse(in: CGRect(x: sx - starR, y: sy - starR, width: starR * 2, height: starR * 2))
        }
        moonphaseStarsLayer.frame = CGRect(origin: .zero, size: canvas)
        moonphaseStarsLayer.path = starsPath

        // Moon disc — sits stationary inside the aperture, well clear of the
        // bottom hills. The OCCULTER disc (navy, same size) translates over
        // the moon to fake lunar phases.
        let discR = hw * 0.52
        let moonCenter = CGPoint(x: cx, y: baseY + hw * 0.62)
        moonphaseDiscContainer.frame = CGRect(
            x: moonCenter.x - discR, y: moonCenter.y - discR,
            width: discR * 2, height: discR * 2
        )
        let discBounds = CGRect(origin: .zero, size: moonphaseDiscContainer.bounds.size)
        moonphaseDiscLayer.frame = discBounds
        moonphaseDiscLayer.path = CGPath(ellipseIn: discBounds, transform: nil)

        moonphaseOcculterLayer.frame = discBounds
        moonphaseOcculterLayer.path = CGPath(ellipseIn: discBounds, transform: nil)

        // Gold frame around the aperture perimeter.
        moonphaseFrameLayer.frame = CGRect(origin: .zero, size: canvas)
        moonphaseFrameLayer.path = aperturePath
        moonphaseFrameLayer.lineWidth = max(0.5, hw * 0.05)

        // Clip the sky, stars, and disc container to the aperture shape.
        applyMoonphaseClip(aperturePath: aperturePath, apertureRect: apertureRect, canvasSize: canvas)
    }

    /// Build the aperture path: top semicircle + scalloped bottom with two
    /// flat upward "rolling hills" cutting into the aperture from the
    /// baseline. The hills use quadratic Beziers so width and height are
    /// independent — this is what gives the moonphase aperture its Lange-1
    /// "moon over rolling hills" silhouette without becoming heart-shaped.
    private func buildAperturePath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let cx = rect.midX
        let baseY = rect.minY
        let leftX = rect.minX
        let rightX = rect.maxX
        let hw = rect.width / 2
        let topRadius = hw

        // Hill parameters: wide-and-flat, well clear of the moon disc above.
        let hillHalfWidth = hw * 0.32     // each hill spans 0.64*hw horizontally
        let hillGap = hw * 0.06           // tiny valley between the two hills
        let hillHeight = hw * 0.10        // subtle peak height — moon must clear

        let rightHillLeft = cx + hillGap
        let rightHillRight = rightHillLeft + hillHalfWidth * 2
        let leftHillRight = cx - hillGap
        let leftHillLeft = leftHillRight - hillHalfWidth * 2

        // Quadratic Bezier peaks at (baseY + controlY)/2, so for an apex of
        // `hillHeight` above the baseline we set control y = baseY + 2*hillHeight.
        let controlYOffset = hillHeight * 2

        path.move(to: CGPoint(x: leftX, y: baseY))
        // Top semicircle from left base CCW (in y-up) up and over to right base.
        path.addArc(
            center: CGPoint(x: cx, y: baseY),
            radius: topRadius,
            startAngle: .pi,
            endAngle: 0,
            clockwise: false
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
        // Each clipped layer needs its own mask CAShapeLayer. The disc
        // container has a non-origin frame, so its mask path must be in the
        // container's LOCAL coordinate space.
        for layer in [moonphaseSkyLayer, moonphaseStarsLayer] {
            let mask = CAShapeLayer()
            mask.frame = CGRect(origin: .zero, size: canvasSize)
            mask.path = aperturePath
            mask.fillColor = NSColor.white.cgColor
            layer.mask = mask
        }
        // Disc container: rebuild the aperture path in local coords.
        let containerOrigin = moonphaseDiscContainer.frame.origin
        let localRect = apertureRect.offsetBy(dx: -containerOrigin.x, dy: -containerOrigin.y)
        let localPath = buildAperturePath(in: localRect)
        let discMask = CAShapeLayer()
        discMask.frame = moonphaseDiscContainer.bounds
        discMask.path = localPath
        discMask.fillColor = NSColor.white.cgColor
        moonphaseDiscContainer.mask = discMask
    }

    private func updateMoonphaseTransform(fraction: Double) {
        // Two-disc technique: a stationary gold moon + a navy occulter that
        // slides over it. The occulter's horizontal offset is piecewise-linear
        // in phase fraction so the visible-moon area matches actual lunar
        // appearance (northern hemisphere orientation — waxing crescent is
        // bright on the RIGHT, waning is bright on the LEFT).
        guard anchors != nil else { return }
        let discR = moonphaseDiscLayer.bounds.width / 2
        let dx: CGFloat
        if fraction <= 0.5 {
            // Waxing 0 → 0.5: occulter slides from center to far-left.
            dx = -CGFloat(4.0) * discR * CGFloat(fraction)
        } else {
            // Waning 0.5 → 1.0: occulter slides from far-right back to center.
            dx = CGFloat(4.0) * discR * CGFloat(1.0 - fraction)
        }
        moonphaseOcculterLayer.setAffineTransform(CGAffineTransform(translationX: dx, y: 0))
    }

    // MARK: Big date layout

    private func layoutBigDate(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.bigDateCenter.x
        let cy = a.bigDateCenter.y
        let h = a.bigDateHeight
        // Two side-by-side rectangles. Each ~0.75h wide, with a thin gap.
        let boxW = h * 0.78
        let gap = h * 0.06
        let totalW = boxW * 2 + gap
        let cornerR = h * 0.10
        let frameInset = h * 0.05

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

        // Gold frame — a slightly larger rounded rect behind each box,
        // creating a visible gold border when the inner white box sits on top.
        let frame1Rect = box1Rect.insetBy(dx: -frameInset, dy: -frameInset)
        let frame2Rect = box2Rect.insetBy(dx: -frameInset, dy: -frameInset)
        let frameCornerR = cornerR + frameInset

        bigDateGoldFrame1.frame = CGRect(origin: .zero, size: canvas)
        bigDateGoldFrame1.path = CGPath(
            roundedRect: frame1Rect,
            cornerWidth: frameCornerR, cornerHeight: frameCornerR,
            transform: nil
        )
        bigDateGoldFrame1.lineWidth = max(0.5, h * 0.012)

        bigDateGoldFrame2.frame = CGRect(origin: .zero, size: canvas)
        bigDateGoldFrame2.path = CGPath(
            roundedRect: frame2Rect,
            cornerWidth: frameCornerR, cornerHeight: frameCornerR,
            transform: nil
        )
        bigDateGoldFrame2.lineWidth = max(0.5, h * 0.012)

        bigDateBox1.frame = CGRect(origin: .zero, size: canvas)
        bigDateBox1.path = CGPath(roundedRect: box1Rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

        bigDateBox2.frame = CGRect(origin: .zero, size: canvas)
        bigDateBox2.path = CGPath(roundedRect: box2Rect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)

        // Thin vertical separator between the two boxes (decorative line in
        // the gap area).
        let sepPath = CGMutablePath()
        let sepX = cx
        sepPath.addRect(CGRect(
            x: sepX - h * 0.005, y: cy - h * 0.20,
            width: h * 0.010, height: h * 0.40
        ))
        bigDateSeparator.frame = CGRect(origin: .zero, size: canvas)
        bigDateSeparator.path = sepPath

        // Numeral font for the big date — Didot or Bodoni gives the
        // high-contrast Lange-1-like serif. Falls back to system serif bold.
        bigDateNumeralFont = bigDateFont(size: h * 0.80)
        bigDateDigit1Layer.frame = CGRect(origin: .zero, size: canvas)
        bigDateDigit2Layer.frame = CGRect(origin: .zero, size: canvas)

        // Initial digits — will be overwritten by first tick
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
        subSecondsFaceLayer.frame = CGRect(origin: .zero, size: canvas)
        subSecondsFaceLayer.path = CGPath(ellipseIn: faceRect, transform: nil)
        subSecondsFaceLayer.lineWidth = max(0.5, r * 0.020)

        subSecondsRecessShade.frame = faceRect
        let recessMask = CAShapeLayer()
        recessMask.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: faceRect.size), transform: nil
        )
        recessMask.fillColor = NSColor.white.cgColor
        subSecondsRecessShade.mask = recessMask

        // Tick marks
        let ticksPath = CGMutablePath()
        let outer = r * 0.92
        let inner = r * 0.82
        let innerShort = r * 0.86
        for i in 0..<60 {
            let theta = .pi / 2 - (CGFloat(i) / 60) * 2 * .pi
            let dx = cos(theta), dy = sin(theta)
            let isFive = i % 5 == 0
            let innerR = isFive ? inner : innerShort
            ticksPath.move(to: CGPoint(x: cx + dx * innerR, y: cy + dy * innerR))
            ticksPath.addLine(to: CGPoint(x: cx + dx * outer, y: cy + dy * outer))
        }
        subSecondsTicksLayer.frame = CGRect(origin: .zero, size: canvas)
        subSecondsTicksLayer.path = ticksPath
        subSecondsTicksLayer.lineWidth = max(0.5, r * 0.025)

        // Numerals at 10 / 20 / 30 / 40 / 50 / 60 (Arabic)
        let numerals = ["60", "10", "20", "30", "40", "50"]
        let numeralRadius = r * 0.70
        let numeralFontSize = r * 0.22
        let numeralFont = serifFont(size: numeralFontSize, bold: false)
        let numeralsPath = CGMutablePath()
        for (i, str) in numerals.enumerated() {
            // i=0 → 60 at top (theta = π/2); i=1 → 10 at 60° clockwise; etc.
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

        // Hand
        let handLength = r * 0.78
        let handWidth = r * 0.07
        subSecondsHand.bounds = CGRect(x: 0, y: 0, width: handWidth, height: handLength)
        subSecondsHand.position = a.subSecondsCenter
        subSecondsHand.path = goldHandPath(width: handWidth, length: handLength, taper: false)

        // Hub
        let hubR = r * 0.07
        subSecondsHub.frame = CGRect(
            x: cx - hubR, y: cy - hubR,
            width: hubR * 2, height: hubR * 2
        )
        subSecondsHub.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: subSecondsHub.frame.size),
            transform: nil
        )
    }

    // MARK: Power reserve layout

    private func layoutPowerReserve(canvas: CGSize, anchors a: LayoutAnchors) {
        let cx = a.powerReserveCenter.x
        let cy = a.powerReserveCenter.y
        let r = a.powerReserveRadius

        // Power reserve arc on the RIGHT side of the dial, opening LEFT
        // (toward the dial center). The arc spans 90° centered on the +x
        // axis. AUF (full) at the upper end (π/4), AB (empty) at the lower
        // end (-π/4). Arc sweeps clockwise through 0 (rightmost point).
        //
        // y-up Core Animation angles: 0=right, π/2=up, π=left, -π/2=down.
        let arcSpan: CGFloat = .pi / 2  // 90° total arc
        let aufAngle: CGFloat = arcSpan / 2     // +π/4 (upper-right)
        let abAngle: CGFloat = -arcSpan / 2     // -π/4 (lower-right)
        powerReserveAUFAngle = aufAngle
        powerReserveABAngle = abAngle
        powerReservePivot = CGPoint(x: cx, y: cy)

        // Tick marks along the arc path — no continuous arc. Major ticks at
        // AUF, midpoint, AB; minor ticks evenly between. (Matches the real
        // Lange 1's discrete graduation, not a printed arc.)
        let ticksPath = CGMutablePath()
        let tickCount = 12
        let tickOuter = r
        let minorInner = r * 0.90
        let majorInner = r * 0.82
        for i in 0...tickCount {
            let t = CGFloat(i) / CGFloat(tickCount)
            let angle = aufAngle - t * (aufAngle - abAngle)
            let isMajor = (i == 0) || (i == tickCount / 2) || (i == tickCount)
            let innerR = isMajor ? majorInner : minorInner
            let dx = cos(angle), dy = sin(angle)
            ticksPath.move(to: CGPoint(x: cx + dx * innerR, y: cy + dy * innerR))
            ticksPath.addLine(to: CGPoint(x: cx + dx * tickOuter, y: cy + dy * tickOuter))
        }
        powerReserveArcLayer.frame = CGRect(origin: .zero, size: canvas)
        powerReserveArcLayer.path = ticksPath
        powerReserveArcLayer.lineWidth = max(0.5, r * 0.05)
        powerReserveArcLayer.lineCap = .round
        powerReserveArcLayer.strokeColor = AsymmetricMoonphasePalette.numeralBlack

        // Red triangles at AUF + AB ends
        let triR = r * 0.10
        let trianglesPath = CGMutablePath()
        for (angle, pointInward) in [(aufAngle, false), (abAngle, false)] {
            let _ = pointInward
            let baseCx = cx + cos(angle) * r
            let baseCy = cy + sin(angle) * r
            // Triangle points outward (away from pivot)
            let tipX = cx + cos(angle) * (r + triR * 0.9)
            let tipY = cy + sin(angle) * (r + triR * 0.9)
            // Two base corners perpendicular to angle direction
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

        // Labels: AUF (top), AB (bottom). Tiny serif text positioned just
        // beyond the red triangles, on the inside of the arc (toward the dial).
        let labelFontSize = r * 0.22
        let labelFont = serifFont(size: labelFontSize, bold: false)
        let labelsPath = CGMutablePath()
        let labelInner = r * 0.65
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

        // Indicator hand — anchored at the pivot. Slim lance, reaches the
        // inner tick line.
        let handLength = r * 0.78
        let handWidth = r * 0.14
        powerReserveIndicatorHand.bounds = CGRect(x: 0, y: 0, width: handWidth, height: handLength)
        powerReserveIndicatorHand.position = a.powerReserveCenter
        powerReserveIndicatorHand.path = goldHandPath(width: handWidth, length: handLength, taper: true)
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

    /// Lance / spear-tip hand path. `width` × `length` with anchor at bottom-center.
    /// If `taper`, produces an elongated arrowhead: wide tail, narrow shaft,
    /// widening spear-blade near the tip, sharp point (Lange 1 hour/minute hand).
    /// If not, produces a slim leaf-shape (sub-seconds hand).
    private func goldHandPath(width: CGFloat, length: CGFloat, taper: Bool) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        if taper {
            let tailHalf = width * 0.50      // wide rounded tail behind pivot
            let shaftHalf = width * 0.18     // slim shaft
            let bladeHalf = width * 0.50     // spear shoulder near tip
            let shaftTopY = length * 0.62    // shaft transitions into blade here
            let bladeMaxY = length * 0.78    // widest point of blade
            // Clockwise from bottom-left tail
            path.move(to: CGPoint(x: cx - tailHalf, y: length * 0.02))
            path.addLine(to: CGPoint(x: cx - tailHalf, y: length * 0.08))
            path.addLine(to: CGPoint(x: cx - shaftHalf, y: length * 0.16))
            path.addLine(to: CGPoint(x: cx - shaftHalf, y: shaftTopY))
            path.addLine(to: CGPoint(x: cx - bladeHalf, y: bladeMaxY))
            path.addLine(to: CGPoint(x: cx, y: length))
            path.addLine(to: CGPoint(x: cx + bladeHalf, y: bladeMaxY))
            path.addLine(to: CGPoint(x: cx + shaftHalf, y: shaftTopY))
            path.addLine(to: CGPoint(x: cx + shaftHalf, y: length * 0.16))
            path.addLine(to: CGPoint(x: cx + tailHalf, y: length * 0.08))
            path.addLine(to: CGPoint(x: cx + tailHalf, y: length * 0.02))
            path.closeSubpath()
        } else {
            // Slim leaf-shape with a pointed tip — for the sub-seconds hand
            let baseHalf = width * 0.40
            path.move(to: CGPoint(x: cx - baseHalf, y: 0))
            path.addLine(to: CGPoint(x: cx + baseHalf, y: 0))
            path.addLine(to: CGPoint(x: cx + baseHalf * 0.55, y: length * 0.90))
            path.addLine(to: CGPoint(x: cx, y: length))
            path.addLine(to: CGPoint(x: cx - baseHalf * 0.55, y: length * 0.90))
            path.closeSubpath()
        }
        return path
    }
}
