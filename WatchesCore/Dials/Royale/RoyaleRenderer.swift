import AppKit
import QuartzCore

/// Royale — digital LCD dial homage of the Casio AE-1200WH.
///
/// Story 1.5's purpose is the `DialRenderer` protocol stress test: Royale is
/// the first dial that breaks the analog paradigm. If the protocol survives
/// Royale without amendment, the analog dials in Epics 1.6 / 2.x are
/// execution rather than architecture. See `notes.md` for design decisions.
public final class RoyaleRenderer: DialRenderer {

    // MARK: DialRenderer static metadata

    public static let identity = DialIdentity(
        id: "royale",
        displayName: "Royale",
        homageCredit: "Inspired by the Casio AE-1200WH",
        previewAssetName: "royale-preview"
    )

    public static let visibility: DialVisibility = .hidden

    // MARK: State

    private weak var rootLayer: CALayer?
    private var canvas: CGSize = .zero
    private var timeSource: TimeSource?

    /// Locale-respecting per D5; resolved once at attach time.
    private let calendar: Calendar = .autoupdatingCurrent

    /// Watch-case proportions: slightly taller than wide. The AE-1200WH is
    /// roughly 42.1 × 45 mm (W × H), aspect ≈ 0.94.
    private static let caseAspect: CGFloat = 0.94  // width / height

    /// Case stack (outside the LCD).
    private let caseBackgroundLayer = CALayer()

    /// Soft radial vignette on the canvas — slightly lighter at center,
    /// pure black at corners. Reads as the watch sitting under ambient
    /// light rather than floating in a void.
    private let vignetteLayer = CAGradientLayer()

    /// Bezel: CAGradientLayer (vertical light→dark) masked to the chamfered
    /// case shape. Skeuomorphic "polished metal under top light" effect.
    private let bezelLayer = CAGradientLayer()
    private let bezelMaskShape = CAShapeLayer()

    /// Per-edge bevel strokes — bright on top edges, dark on bottom edges.
    /// Makes the chamfered corners feel properly faceted under top light.
    private let bezelTopHighlight = CAShapeLayer()
    private let bezelBottomShadow = CAShapeLayer()

    /// Rim light — thin bright stroke at the chamfered outer edge. Helps
    /// the bezel pop against the dark canvas.
    private let bezelRimLight = CAShapeLayer()

    /// Thin dark groove at the boundary where bezel meets faceplate — sells
    /// the physical step-down from raised bezel level to recessed faceplate
    /// level.
    private let bezelFaceplateGroove = CAShapeLayer()

    /// Brushed-metal striations on the bezel — thin horizontal lines at
    /// very low alpha, hinting at the AE-1200WH's brushed finish.
    private let bezelBrushedTexture = CAShapeLayer()
    private let bezelBrushedMask = CAShapeLayer()
    /// Faceplate: CAGradientLayer (vertical, subtle) masked to the chamfered
    /// outer shape MINUS the four cutouts (even-odd fill on the mask).
    private let faceplateLayer = CAGradientLayer()
    private let faceplateMaskShape = CAShapeLayer()
    private var screwLayers: [CALayer] = []
    private var pusherLayers: [CALayer] = []

    /// LCD container — replaces the old "panel layer." The LCD inset sits
    /// inside the faceplate, rectangular, and holds all glyph content.
    private let lcdLayer = CALayer()

    /// Skeuomorphic detail: thin bevel stroke along each faceplate cutout
    /// edge, suggesting the cutouts have depth into the plastic.
    private let cutoutBevelLayer = CAShapeLayer()

    /// Inner-shadow stroke just INSIDE each cutout (on the LCD side), so the
    /// cutouts read as recessed rather than printed-on.
    private let cutoutInnerShadowLayer = CAShapeLayer()

    /// LCD crystal sheen — faint diagonal highlight on the LCD suggesting a
    /// glass/plastic cover over the display.
    private let lcdSheenLayer = CAGradientLayer()

    /// Mask shape that clips the rectangular LCD layer to the chamfered
    /// face-octagon, so the LCD's corners don't bleed past the faceplate
    /// chamfer cuts and onto the bezel.
    private let lcdMaskShape = CAShapeLayer()

    /// LCD content sublayers (BEHIND the faceplate, visible only through
    /// the faceplate's cutouts).
    private let subdialHubLayer = CAShapeLayer()   // sits on LCD, visible through subdial cutout

    /// Functional analog mini-clock inside the subdial cutout (Story 1.5.2).
    /// Hour + minute hands are CAShapeLayers whose `affineTransform` rotates
    /// per tick. The seconds tick is a single short radial line that jumps
    /// to one of 60 angular positions on each second boundary (NOT a smooth
    /// sweeping hand). Quadrant accent lines are the four short radial
    /// strokes at the 12/3/6/9 positions.
    private let subdialQuadrants = CAShapeLayer()
    private let subdialHourHand = CAShapeLayer()
    private let subdialMinuteHand = CAShapeLayer()
    private let subdialSecondTick = CAShapeLayer()
    /// Last second index rendered for the seconds tick. Used by
    /// `tick(reduceMotion:)` to freeze the tick when reduce-motion is on
    /// (we still advance it once when transitioning from non-reduced).
    private var lastRenderedSecondTickIndex: Int?

    private let mapLayer = CALayer()                // sits on LCD, visible through middle-right cutout
    private let mapContinentsLayer = CAShapeLayer()
    private let timeContainer = CALayer()           // sits on LCD, visible through bottom cutout
    private let secondaryContainer = CALayer()      // sits on LCD, visible through bottom cutout

    /// Faceplate decoration sublayers (PRINTED ON the dark plastic).
    private let subdialFrameLayer = CAShapeLayer()  // ring + tick marks around subdial cutout
    private var subdialNumberLayers: [CATextLayer] = []  // 12 numerals around subdial cutout
    private var subdialRivetLayers: [CAShapeLayer] = []  // 4 black rivets around subdial cutout

    /// Cutout positions expressed in face-local coordinates. Computed once
    /// per layout pass and reused for faceplate path generation, LCD content
    /// positioning, and decoration placement.
    private struct CutoutGeometry {
        let faceRect: CGRect            // faceplate frame, canvas-coordinates
        let subdialCenter: CGPoint      // canvas-coordinates
        let subdialRadius: CGFloat
        let topRight: CGRect            // canvas-coordinates
        let middleRight: CGRect         // canvas-coordinates
        let bottom: CGRect              // canvas-coordinates
        let cornerRadius: CGFloat       // rounded-rect radius for rectangular cutouts
    }
    private var cutoutGeometry: CutoutGeometry?

    /// Glyph slots — built in `layoutLayers(for:)` so they can size to canvas.
    private var timeDigitSlots: [DigitSlot] = []   // [h1, h2, m1, m2, s1, s2]
    private var colonSlots: [ColonSlot] = []        // 2 colons (HH:MM, MM:SS)
    /// `AM`/`PM` indicator to the left of the time (2 letter slots: "A"|"P", "M").
    private var meridiemLetterSlots: [LetterSlot] = []
    private var dateDigitSlots: [DigitSlot] = []   // [mo1, mo2, d1, d2]
    private var dateSeparatorSlot: SeparatorSlot?  // dash between MM and DD
    private var dayLetterSlots: [LetterSlot] = []  // 3 letter slots

    /// Thin border rects around the two secondary data fields (day + date).
    private var secondaryBoxLayers: [CAShapeLayer] = []

    /// Last integer-second rendered. Used for both reduce-motion dedup and
    /// 1 Hz colon blink parity.
    private var lastRenderedSecond: Int?

    // MARK: Init

    public init() {
        // No setup here — host calls attach() with everything we need.
    }

    // MARK: DialRenderer

    public func attach(rootLayer: CALayer, canvas: CGSize, timeSource: TimeSource) {
        self.rootLayer = rootLayer
        self.canvas = canvas
        self.timeSource = timeSource

        installLayers()
        layoutLayers(for: canvas)

        // First-frame correctness: produce a correct visible frame at attach
        // time so the host's reveal doesn't fade in a stale state. Story 1.4
        // pattern. `reduceMotion: false` for parity with ProofOfHost.
        _ = tick(reduceMotion: false)

        Logging.renderer.info(
            "RoyaleRenderer attached: canvas=\(Int(canvas.width), privacy: .public)×\(Int(canvas.height), privacy: .public)"
        )
    }

    @discardableResult
    public func tick(reduceMotion: Bool) -> [CGRect] {
        guard let timeSource else { return [] }
        let now = timeSource.now
        let integerSecond = Int(now.timeIntervalSince1970)

        // Reduce-motion contract: integer-second dedup. Skip redundant writes
        // when the displayed second hasn't advanced.
        if reduceMotion, integerSecond == lastRenderedSecond {
            return []
        }
        lastRenderedSecond = integerSecond

        let time = RoyaleMath.timeDigits(from: now, calendar: calendar)
        let dateD = RoyaleMath.dateDigits(from: now, calendar: calendar)
        let day = RoyaleMath.dayOfWeekLabel(for: now, calendar: calendar)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Convert 24-hour digits to 12-hour display per AE-1200WH convention:
        //   00 → 12 AM, 01-11 → 1-11 AM, 12 → 12 PM, 13-23 → 1-11 PM.
        // Leading hour digit is blanked (set to -1 → empty segments) when
        // the displayed hour is single-digit (1-9), so "9" reads as " 9".
        let hour24 = time.h1 * 10 + time.h2
        let isPM = hour24 >= 12
        let hour12Raw = hour24 % 12
        let hour12 = hour12Raw == 0 ? 12 : hour12Raw
        let displayH1: Int = hour12 < 10 ? -1 : 1
        let displayH2: Int = hour12 % 10

        // Time digits
        if timeDigitSlots.count == 6 {
            timeDigitSlots[0].set(digit: displayH1)
            timeDigitSlots[1].set(digit: displayH2)
            timeDigitSlots[2].set(digit: time.m1)
            timeDigitSlots[3].set(digit: time.m2)
            timeDigitSlots[4].set(digit: time.s1)
            timeDigitSlots[5].set(digit: time.s2)
        }

        // Meridiem indicator: "AM" or "PM" rendered via the pixel-block
        // letter slots, positioned to the left of the time digits.
        if meridiemLetterSlots.count == 2 {
            meridiemLetterSlots[0].set(letter: isPM ? "P" : "A")
            meridiemLetterSlots[1].set(letter: "M")
        }

        // Colons: 1 Hz blink (even seconds ON), frozen ON in reduce-motion
        let colonsOn = reduceMotion ? true : (integerSecond % 2 == 0)
        for slot in colonSlots {
            slot.set(on: colonsOn)
        }

        // Date digits — suppress leading zero on the MONTH (AE-1200WH
        // convention: May shows as "5-13" not "05-13"). Day keeps its
        // leading zero so single-digit days render as "5-03" not "5-3".
        let month = dateD.mo1 * 10 + dateD.mo2
        let displayMo1: Int = month < 10 ? -1 : dateD.mo1
        if dateDigitSlots.count == 4 {
            dateDigitSlots[0].set(digit: displayMo1)
            dateDigitSlots[1].set(digit: dateD.mo2)
            dateDigitSlots[2].set(digit: dateD.d1)
            dateDigitSlots[3].set(digit: dateD.d2)
        }

        // Day-of-week letters (pad to 3 with blanks if locale-abbrev is shorter)
        let chars: [Character] = Array(day.prefix(3))
        for i in 0..<dayLetterSlots.count {
            let c: Character = i < chars.count ? chars[i] : " "
            dayLetterSlots[i].set(letter: c)
        }

        // Subdial analog mini-clock (Story 1.5.2). RoyaleMath returns angles
        // measured CLOCKWISE from 12-o'clock; CGAffineTransform's positive
        // rotation is COUNTER-clockwise on macOS's y-up coords, so we negate.
        let hourAngle = RoyaleMath.subdialHourAngle(from: now, calendar: calendar)
        let minuteAngle = RoyaleMath.subdialMinuteAngle(from: now, calendar: calendar)
        subdialHourHand.setAffineTransform(CGAffineTransform(rotationAngle: -hourAngle))
        subdialMinuteHand.setAffineTransform(CGAffineTransform(rotationAngle: -minuteAngle))

        // Seconds tick — only advances when reduce-motion is off. When on, the
        // tick freezes at whatever index was current last; per AC7 the seconds
        // readout is functionally silenced in reduce-motion mode.
        if !reduceMotion {
            let secondIndex = RoyaleMath.subdialSecondTickIndex(from: now, calendar: calendar)
            if secondIndex != lastRenderedSecondTickIndex {
                let secondAngle = CGFloat(secondIndex) * (2 * .pi / 60.0)
                subdialSecondTick.setAffineTransform(
                    CGAffineTransform(rotationAngle: -secondAngle)
                )
                lastRenderedSecondTickIndex = secondIndex
            }
        }

        return [
            timeContainer.frame,
            secondaryContainer.frame,
            subdialHourHand.frame,
            subdialMinuteHand.frame,
            subdialSecondTick.frame,
        ]
    }

    public func canvasDidChange(to canvas: CGSize) {
        self.canvas = canvas
        layoutLayers(for: canvas)
    }

    public func detach() {
        // Removing the case background detaches the entire layer subtree.
        caseBackgroundLayer.removeFromSuperlayer()
        screwLayers.removeAll()
        pusherLayers.removeAll()
        secondaryBoxLayers.removeAll()
        subdialNumberLayers.removeAll()
        subdialRivetLayers.removeAll()
        cutoutGeometry = nil
        timeDigitSlots.removeAll()
        colonSlots.removeAll()
        dateDigitSlots.removeAll()
        dateSeparatorSlot = nil
        dayLetterSlots.removeAll()
        rootLayer = nil
        timeSource = nil
    }

    // MARK: Layer construction

    private func installLayers() {
        guard let rootLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Case background — fills the canvas behind the watch.
        caseBackgroundLayer.name = "royale.caseBackground"
        caseBackgroundLayer.backgroundColor = RoyalePalette.caseBackground
        rootLayer.addSublayer(caseBackgroundLayer)

        // Radial vignette ON the case background — slightly lighter at
        // center, pure black at corners. Subtle atmosphere.
        vignetteLayer.name = "royale.canvas.vignette"
        vignetteLayer.type = .radial
        vignetteLayer.colors = [
            NSColor(white: 0.09, alpha: 1.0).cgColor,
            NSColor(white: 0.02, alpha: 1.0).cgColor,
            NSColor(white: 0.0,  alpha: 1.0).cgColor,
        ]
        vignetteLayer.locations = [0.0, 0.55, 1.0]
        vignetteLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignetteLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        caseBackgroundLayer.addSublayer(vignetteLayer)

        // Bezel — silver chamfered-rectangle frame, vertical gradient
        // light→dark suggesting top-front lighting on polished metal.
        bezelLayer.name = "royale.bezel"
        bezelLayer.colors = [
            RoyalePalette.bezelHighlight,
            RoyalePalette.bezel,
            RoyalePalette.bezelEdgeShadow,
        ]
        bezelLayer.locations = [0.0, 0.55, 1.0]
        // CAGradientLayer uses bottom-left-origin normalized coords on
        // macOS layers without geometryFlipped. Tilting the gradient
        // slightly from upper-left → lower-right suggests a single light
        // source above and to the left rather than direct overhead light.
        bezelLayer.startPoint = CGPoint(x: 0.25, y: 1.0)
        bezelLayer.endPoint = CGPoint(x: 0.75, y: 0.0)
        bezelMaskShape.fillColor = NSColor.white.cgColor
        bezelLayer.mask = bezelMaskShape
        caseBackgroundLayer.addSublayer(bezelLayer)

        // Brushed-metal texture on the bezel — many thin horizontal lines
        // at low alpha, masked to the bezel shape.
        bezelBrushedTexture.name = "royale.bezel.brushed"
        bezelBrushedTexture.fillColor = nil
        bezelBrushedTexture.strokeColor = NSColor.white.withAlphaComponent(0.06).cgColor
        bezelBrushedMask.fillColor = NSColor.white.cgColor
        bezelBrushedTexture.mask = bezelBrushedMask
        caseBackgroundLayer.addSublayer(bezelBrushedTexture)

        // Per-edge bevels: bright stroke on top edges, dark on bottom edges.
        bezelTopHighlight.name = "royale.bezel.topHighlight"
        bezelTopHighlight.fillColor = nil
        bezelTopHighlight.strokeColor = NSColor.white.withAlphaComponent(0.70).cgColor
        bezelTopHighlight.lineCap = .round
        caseBackgroundLayer.addSublayer(bezelTopHighlight)

        bezelBottomShadow.name = "royale.bezel.bottomShadow"
        bezelBottomShadow.fillColor = nil
        bezelBottomShadow.strokeColor = NSColor.black.withAlphaComponent(0.55).cgColor
        bezelBottomShadow.lineCap = .round
        caseBackgroundLayer.addSublayer(bezelBottomShadow)

        // Rim light — thin bright stroke right at the outer chamfered edge
        // of the bezel, making the case silhouette pop against the canvas.
        bezelRimLight.name = "royale.bezel.rim"
        bezelRimLight.fillColor = nil
        bezelRimLight.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        caseBackgroundLayer.addSublayer(bezelRimLight)

        // Four screw heads at the bezel corners — built in layoutLayers.
        // (Frames depend on canvas geometry.)

        // LCD — full panel filling the bezel interior. The user sees the
        // LCD only through the cutouts in the faceplate above. Clipped to
        // the chamfered face-octagon so the rectangular LCD corners don't
        // bleed past the faceplate chamfer onto the bezel.
        lcdLayer.name = "royale.lcd"
        lcdLayer.backgroundColor = RoyalePalette.background
        lcdMaskShape.fillColor = NSColor.white.cgColor
        lcdLayer.mask = lcdMaskShape
        caseBackgroundLayer.addSublayer(lcdLayer)

        // LCD crystal sheen — subtle white-to-clear diagonal gradient
        // suggesting a glass cover above the LCD. Lives ON the LCD so
        // it's clipped to the LCD's bounds.
        lcdSheenLayer.name = "royale.lcd.sheen"
        lcdSheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.10).cgColor,
            NSColor.white.withAlphaComponent(0.02).cgColor,
            NSColor.white.withAlphaComponent(0.00).cgColor,
        ]
        lcdSheenLayer.locations = [0.0, 0.35, 0.75]
        // From top-left to bottom-right.
        lcdSheenLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        lcdSheenLayer.endPoint = CGPoint(x: 0.85, y: 0.15)
        lcdLayer.addSublayer(lcdSheenLayer)

        // LCD content (sublayers of lcdLayer). These are positioned in
        // layoutLCDContent so they line up with the faceplate cutouts.

        // Subdial hub — small dark dot at the center of the subdial cutout.
        subdialHubLayer.name = "royale.subdial.hub"
        subdialHubLayer.fillColor = RoyalePalette.litSegment
        subdialHubLayer.strokeColor = nil
        lcdLayer.addSublayer(subdialHubLayer)

        // Functional analog mini-clock (Story 1.5.2). Z-order matters:
        // quadrants → hour hand → minute hand → seconds tick (top so it's
        // always visible against the hands). All sit on lcdLayer, visible
        // through the subdial cutout in the faceplate above.
        subdialQuadrants.name = "royale.subdial.quadrants"
        subdialQuadrants.fillColor = nil
        subdialQuadrants.strokeColor = RoyalePalette.litSegment
        subdialQuadrants.lineCap = .butt
        lcdLayer.addSublayer(subdialQuadrants)

        subdialHourHand.name = "royale.subdial.hourHand"
        subdialHourHand.fillColor = RoyalePalette.litSegment
        subdialHourHand.strokeColor = nil
        // Anchor at the BASE of the hand (its bottom-center) so rotation
        // pivots around the subdial center, not the hand's own midpoint.
        subdialHourHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        // Suppress implicit animations on transform changes.
        subdialHourHand.actions = ["transform": NSNull(), "position": NSNull()]
        lcdLayer.addSublayer(subdialHourHand)

        subdialMinuteHand.name = "royale.subdial.minuteHand"
        subdialMinuteHand.fillColor = RoyalePalette.litSegment
        subdialMinuteHand.strokeColor = nil
        subdialMinuteHand.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        subdialMinuteHand.actions = ["transform": NSNull(), "position": NSNull()]
        lcdLayer.addSublayer(subdialMinuteHand)

        subdialSecondTick.name = "royale.subdial.secondTick"
        subdialSecondTick.fillColor = RoyalePalette.litSegment
        subdialSecondTick.strokeColor = nil
        subdialSecondTick.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        subdialSecondTick.actions = ["transform": NSNull(), "position": NSNull()]
        lcdLayer.addSublayer(subdialSecondTick)

        // World map (rendered through the middle-right cutout).
        mapLayer.name = "royale.map"
        mapLayer.backgroundColor = nil  // LCD background shows through
        lcdLayer.addSublayer(mapLayer)

        mapContinentsLayer.name = "royale.map.continents"
        mapContinentsLayer.fillColor = RoyalePalette.mapDot
        mapContinentsLayer.strokeColor = nil
        mapLayer.addSublayer(mapContinentsLayer)

        // Time + secondary containers (rendered through the bottom cutout).
        timeContainer.name = "royale.time"
        lcdLayer.addSublayer(timeContainer)

        secondaryContainer.name = "royale.secondary"
        lcdLayer.addSublayer(secondaryContainer)

        // Faceplate — matte-black plastic with cutout windows. Sits ON TOP
        // of the LCD; LCD visible only through cutouts. Subtle vertical
        // gradient suggests molded plastic catching a hint of top light.
        // The mask uses even-odd fill so the chamfered outer shape minus
        // the four cutout sub-paths is what the gradient fills.
        faceplateLayer.name = "royale.faceplate"
        faceplateLayer.colors = [
            RoyalePalette.faceplateHighlight,
            RoyalePalette.faceplate,
            RoyalePalette.faceplateEdgeShadow,
        ]
        faceplateLayer.locations = [0.0, 0.5, 1.0]
        faceplateLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        faceplateLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        faceplateMaskShape.fillColor = NSColor.white.cgColor
        faceplateMaskShape.fillRule = .evenOdd
        faceplateLayer.mask = faceplateMaskShape
        caseBackgroundLayer.addSublayer(faceplateLayer)

        // Bezel-faceplate boundary groove — thin dark stroke right at the
        // edge of the faceplate, suggesting the bezel sits above the
        // faceplate as a physical step.
        bezelFaceplateGroove.name = "royale.bezel.faceplateGroove"
        bezelFaceplateGroove.fillColor = nil
        bezelFaceplateGroove.strokeColor = NSColor.black.withAlphaComponent(0.40).cgColor
        caseBackgroundLayer.addSublayer(bezelFaceplateGroove)

        // Cutout bevel — a thin lighter stroke around each cutout edge,
        // suggesting the cutouts have depth.
        cutoutBevelLayer.name = "royale.faceplate.cutoutBevel"
        cutoutBevelLayer.fillColor = nil
        cutoutBevelLayer.strokeColor = RoyalePalette.faceplateCutoutBevel
        caseBackgroundLayer.addSublayer(cutoutBevelLayer)

        // Cutout inner shadow — dark stroke just inside each cutout edge,
        // drawn at LCD level so it reads as a recess shadow inside the
        // cutout (visible through the faceplate's cutouts).
        cutoutInnerShadowLayer.name = "royale.lcd.cutoutInnerShadow"
        cutoutInnerShadowLayer.fillColor = nil
        cutoutInnerShadowLayer.strokeColor = NSColor.black.withAlphaComponent(0.45).cgColor
        // Inserted at lcdLayer level so it's clipped to LCD bounds and
        // drawn between LCD background and LCD content.
        lcdLayer.addSublayer(cutoutInnerShadowLayer)

        // Subdial frame (outer ring + 60 tick marks) — PRINTED ON the
        // faceplate around the circular cutout.
        subdialFrameLayer.name = "royale.subdial.frame"
        subdialFrameLayer.fillColor = nil
        subdialFrameLayer.strokeColor = RoyalePalette.faceplatePrint
        caseBackgroundLayer.addSublayer(subdialFrameLayer)
    }

    private func layoutLayers(for canvas: CGSize) {
        // Skip layout for degenerate sizes — canvasDidChange will retry.
        guard canvas.width > 0, canvas.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        caseBackgroundLayer.frame = CGRect(origin: .zero, size: canvas)
        vignetteLayer.frame = caseBackgroundLayer.bounds

        // 1. Fit the watch case in the canvas, aspect-preserving.
        // Margin leaves the dark canvas background visible around the watch.
        let aspect = Self.caseAspect
        let canvasAspect = canvas.width / canvas.height
        let margin: CGFloat = 0.85
        let caseSize: CGSize
        if canvasAspect > aspect {
            let h = canvas.height * margin
            caseSize = CGSize(width: h * aspect, height: h)
        } else {
            let w = canvas.width * margin
            caseSize = CGSize(width: w, height: w / aspect)
        }
        let caseRect = CGRect(
            x: (canvas.width - caseSize.width) / 2,
            y: (canvas.height - caseSize.height) / 2,
            width: caseSize.width,
            height: caseSize.height
        )

        // 2. Bezel — silver chamfered rectangle filling the case. The
        // CAGradientLayer fills the full canvas; its mask shape is the
        // chamfered path so the gradient only shows inside the case.
        // The AE-1200WH chamfer is ~13% of the case's smaller dimension.
        let chamfer = min(caseSize.width, caseSize.height) * 0.13
        bezelLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelMaskShape.frame = bezelLayer.bounds
        bezelMaskShape.path = Self.chamferedRectPath(caseRect, chamfer: chamfer)

        // 3. Per-edge bevels — top edges bright, bottom edges dark.
        let edgeLineWidth = max(1, chamfer * 0.10)
        bezelTopHighlight.frame = CGRect(origin: .zero, size: canvas)
        bezelTopHighlight.path = Self.chamferedTopEdgePath(rect: caseRect, chamfer: chamfer)
        bezelTopHighlight.lineWidth = edgeLineWidth

        bezelBottomShadow.frame = CGRect(origin: .zero, size: canvas)
        bezelBottomShadow.path = Self.chamferedBottomEdgePath(rect: caseRect, chamfer: chamfer)
        bezelBottomShadow.lineWidth = edgeLineWidth

        // 3c. Rim light — thin stroke around the entire chamfered outline.
        bezelRimLight.frame = CGRect(origin: .zero, size: canvas)
        bezelRimLight.path = Self.chamferedRectPath(caseRect, chamfer: chamfer)
        bezelRimLight.lineWidth = max(0.5, chamfer * 0.04)

        // 3b. Brushed-metal striations — many thin horizontal lines clipped
        // to the bezel shape.
        bezelBrushedTexture.frame = CGRect(origin: .zero, size: canvas)
        bezelBrushedTexture.path = Self.brushedStriationPath(
            in: caseRect,
            stride: max(2, caseSize.height * 0.005)
        )
        bezelBrushedTexture.lineWidth = max(0.4, caseSize.height * 0.0008)
        bezelBrushedMask.frame = CGRect(origin: .zero, size: canvas)
        bezelBrushedMask.path = Self.chamferedRectPath(caseRect, chamfer: chamfer)

        // 4. Faceplate area — dark plastic with cutout windows. Inset
        // asymmetrically from the bezel (more vertical, since the side
        // bands are mostly hidden by pushers).
        let faceInsetH = caseSize.width * 0.05
        let faceInsetV = caseSize.height * 0.09
        let faceRect = caseRect.insetBy(dx: faceInsetH, dy: faceInsetV)
        let faceChamfer = max(0, chamfer - min(faceInsetH, faceInsetV))

        // 5. LCD — sits BEHIND the faceplate, sized to the faceplate's
        // interior. Only visible through the cutouts in the faceplate
        // above. The lcdMaskShape clips it to the chamfered face octagon
        // so its rectangular corners don't show past the bezel chamfer.
        lcdLayer.frame = faceRect
        lcdMaskShape.frame = lcdLayer.bounds
        lcdMaskShape.path = Self.chamferedRectPath(
            CGRect(origin: .zero, size: faceRect.size),
            chamfer: faceChamfer
        )

        // 6. Cutout geometry — computed once, reused for faceplate path,
        // bevels, LCD content positioning, and faceplate decorations.
        let cutouts = Self.computeCutouts(faceRect: faceRect)
        cutoutGeometry = cutouts

        // 7. Faceplate: gradient fills the canvas; mask shape uses even-odd
        // path (chamfered outer + 4 cutout sub-paths) so the cutouts
        // produce transparent holes in the mask, revealing the LCD beneath.
        faceplateLayer.frame = CGRect(origin: .zero, size: canvas)
        faceplateMaskShape.frame = faceplateLayer.bounds
        faceplateMaskShape.path = Self.faceplatePath(
            faceRect: faceRect,
            chamfer: faceChamfer,
            cutouts: cutouts
        )

        // 7b. Bezel-faceplate groove — thin dark stroke right at the
        // faceplate's chamfered outline (the bezel/faceplate junction).
        bezelFaceplateGroove.frame = CGRect(origin: .zero, size: canvas)
        bezelFaceplateGroove.path = Self.chamferedRectPath(faceRect, chamfer: faceChamfer)
        bezelFaceplateGroove.lineWidth = max(1, min(caseSize.width, caseSize.height) * 0.002)

        // 8. Cutout bevel — thin lighter stroke around each cutout edge,
        // suggesting depth into the plastic.
        let bevelLineWidth: CGFloat = max(0.5, min(caseSize.width, caseSize.height) * 0.0025)
        cutoutBevelLayer.frame = CGRect(origin: .zero, size: canvas)
        cutoutBevelLayer.path = Self.cutoutBevelPath(cutouts: cutouts)
        cutoutBevelLayer.lineWidth = bevelLineWidth

        // 8b. Cutout inner shadow — drawn at LCD level; path is in LCD-local
        // coords (cutouts are in canvas coords, so subtract lcdLayer origin).
        cutoutInnerShadowLayer.frame = lcdLayer.bounds
        cutoutInnerShadowLayer.path = Self.cutoutBevelPath(
            cutouts: cutouts,
            offsetBy: CGPoint(x: -faceRect.minX, y: -faceRect.minY)
        )
        cutoutInnerShadowLayer.lineWidth = max(1, min(caseSize.width, caseSize.height) * 0.006)

        // 8c. LCD crystal sheen — fills LCD bounds with subtle diagonal alpha.
        lcdSheenLayer.frame = lcdLayer.bounds

        // 9. Screws on top/bottom bezel strips + pushers at sides + LCD
        // content + faceplate decorations.
        rebuildScrews(
            caseRect: caseRect,
            chamfer: chamfer,
            bezelStripHeight: faceInsetV,
            screwSize: faceInsetV * 0.55
        )
        rebuildPushers(caseRect: caseRect)

        // Subdial frame (ring + 60 ticks) printed on the faceplate.
        subdialFrameLayer.frame = CGRect(origin: .zero, size: canvas)
        subdialFrameLayer.path = Self.subdialFramePathAround(cutouts: cutouts)
        subdialFrameLayer.lineWidth = max(0.5, cutouts.subdialRadius * 0.035)

        rebuildSubdialNumbers(cutouts: cutouts)
        rebuildSubdialRivets(cutouts: cutouts)

        layoutLCDContent(cutouts: cutouts)

        rebuildTimeSlots()
        rebuildSecondarySlots()
    }

    /// Computes faceplate cutout positions in canvas coordinates.
    /// Proportions are tuned by eye against the AE-1200WH faceplate reference.
    private static func computeCutouts(faceRect: CGRect) -> CutoutGeometry {
        let fW = faceRect.width
        let fH = faceRect.height

        // Subdial circular cutout — upper-left quadrant. Pushed slightly
        // higher (y=0.68 instead of 0.65) so the printed numerals around
        // the cutout clear the bottom rectangular cutout below.
        let subdialCenter = CGPoint(
            x: faceRect.minX + fW * 0.27,
            y: faceRect.minY + fH * 0.68
        )
        let subdialRadius = min(fW, fH) * 0.135

        // Three rectangular cutouts (face-local fractional layout).
        // Bottom cutout shrunk from 0.36→0.33 face-height so more faceplate
        // material is visible below the subdial numerals.
        let topRight = CGRect(
            x: faceRect.minX + fW * 0.53,
            y: faceRect.minY + fH * 0.74,
            width: fW * 0.40,
            height: fH * 0.11
        )
        let middleRight = CGRect(
            x: faceRect.minX + fW * 0.53,
            y: faceRect.minY + fH * 0.52,
            width: fW * 0.40,
            height: fH * 0.17
        )
        let bottom = CGRect(
            x: faceRect.minX + fW * 0.14,
            y: faceRect.minY + fH * 0.08,
            width: fW * 0.79,
            height: fH * 0.33
        )

        return CutoutGeometry(
            faceRect: faceRect,
            subdialCenter: subdialCenter,
            subdialRadius: subdialRadius,
            topRight: topRight,
            middleRight: middleRight,
            bottom: bottom,
            cornerRadius: min(fW, fH) * 0.018
        )
    }

    /// Builds the even-odd-fill faceplate path: outer chamfered rect minus
    /// the 4 cutout sub-paths.
    private static func faceplatePath(
        faceRect: CGRect,
        chamfer: CGFloat,
        cutouts: CutoutGeometry
    ) -> CGPath {
        let path = CGMutablePath()

        // Outer chamfered rect (filled)
        path.addPath(chamferedRectPath(faceRect, chamfer: chamfer))

        // Subdial circular cutout
        let subdialRect = CGRect(
            x: cutouts.subdialCenter.x - cutouts.subdialRadius,
            y: cutouts.subdialCenter.y - cutouts.subdialRadius,
            width: cutouts.subdialRadius * 2,
            height: cutouts.subdialRadius * 2
        )
        path.addEllipse(in: subdialRect)

        // Three rounded-rectangular cutouts
        for rect in [cutouts.topRight, cutouts.middleRight, cutouts.bottom] {
            path.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: cutouts.cornerRadius,
                cornerHeight: cutouts.cornerRadius,
                transform: nil
            ))
        }
        return path
    }

    /// A thin bevel-style stroke around each cutout, drawn at the cutout
    /// edges. `offsetBy` translates the entire path (e.g. to convert canvas
    /// coords → LCD-local coords for use in an LCD sublayer).
    private static func cutoutBevelPath(
        cutouts: CutoutGeometry,
        offsetBy translation: CGPoint = .zero
    ) -> CGPath {
        let path = CGMutablePath()
        var t = CGAffineTransform(translationX: translation.x, y: translation.y)
        let subdialRect = CGRect(
            x: cutouts.subdialCenter.x - cutouts.subdialRadius,
            y: cutouts.subdialCenter.y - cutouts.subdialRadius,
            width: cutouts.subdialRadius * 2,
            height: cutouts.subdialRadius * 2
        )
        path.addEllipse(in: subdialRect, transform: t)
        for rect in [cutouts.topRight, cutouts.middleRight, cutouts.bottom] {
            path.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: cutouts.cornerRadius,
                cornerHeight: cutouts.cornerRadius,
                transform: &t
            ))
        }
        return path
    }

    /// Four short radial lines at the cardinal positions (12 / 3 / 6 / 9) of
    /// the subdial — the "quadrant" accent lines. Drawn as a single combined
    /// stroked path in LCD-local coordinates.
    private static func subdialQuadrantsPath(
        center: CGPoint,
        inner: CGFloat,
        outer: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        // y-up cardinal directions: 12=+y, 3=+x, 6=-y, 9=-x
        let dirs: [(dx: CGFloat, dy: CGFloat)] = [
            ( 0,  1),  // 12 o'clock
            ( 1,  0),  //  3 o'clock
            ( 0, -1),  //  6 o'clock
            (-1,  0),  //  9 o'clock
        ]
        for (dx, dy) in dirs {
            path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            path.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        }
        return path
    }

    /// Subdial frame printed on the faceplate around the circular cutout:
    /// outer ring + 60 tick marks (12 long major + 48 short minor). The
    /// ring sits just outside the cutout; ticks span from the cutout edge
    /// out to the ring.
    private static func subdialFramePathAround(cutouts: CutoutGeometry) -> CGPath {
        let path = CGMutablePath()
        let cx = cutouts.subdialCenter.x
        let cy = cutouts.subdialCenter.y
        let cutoutR = cutouts.subdialRadius

        let ringR = cutoutR * 1.50
        path.addEllipse(in: CGRect(
            x: cx - ringR, y: cy - ringR,
            width: ringR * 2, height: ringR * 2
        ))

        let tickOuter = cutoutR * 1.46
        let majorTickInner = cutoutR * 1.18
        let minorTickInner = cutoutR * 1.30
        // CALayer's local y-axis points UP. To position index 0 at the visual
        // TOP and go clockwise, use theta = π/2 - i·step.
        for i in 0..<60 {
            let theta = .pi / 2 - (CGFloat(i) / 60) * 2 * .pi
            let dx = cos(theta)
            let dy = sin(theta)
            let isMajor = i % 5 == 0
            let inner = isMajor ? majorTickInner : minorTickInner
            path.move(to: CGPoint(x: cx + dx * inner, y: cy + dy * inner))
            path.addLine(to: CGPoint(x: cx + dx * tickOuter, y: cy + dy * tickOuter))
        }
        return path
    }

    /// Positions LCD content sublayers so they line up behind the faceplate
    /// cutouts. Coordinates are LCD-local (relative to `lcdLayer.bounds`).
    /// The cutouts arrive in canvas coordinates; subtract `lcdLayer.frame.origin`
    /// to convert.
    private func layoutLCDContent(cutouts: CutoutGeometry) {
        let lcdOrigin = lcdLayer.frame.origin

        func toLCD(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX - lcdOrigin.x,
                y: rect.minY - lcdOrigin.y,
                width: rect.width,
                height: rect.height
            )
        }
        func toLCD(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - lcdOrigin.x, y: point.y - lcdOrigin.y)
        }

        // Subdial hub — small dark dot at the center of the subdial cutout.
        let hubR = cutouts.subdialRadius * 0.12
        let hubCenter = toLCD(cutouts.subdialCenter)
        subdialHubLayer.frame = CGRect(
            x: hubCenter.x - hubR, y: hubCenter.y - hubR,
            width: hubR * 2, height: hubR * 2
        )
        subdialHubLayer.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: subdialHubLayer.frame.size),
            transform: nil
        )

        // Functional analog mini-clock inside the subdial cutout (Story 1.5.2).
        // All four layers share the same anchor strategy:
        //   - bounds = (width, length) with length running from the SUBDIAL
        //     CENTER outward toward 12-o'clock
        //   - anchorPoint = (0.5, 0.0) — bottom-center, which is the base of
        //     the "hand"
        //   - position = subdial center (LCD-local)
        //   - default rotation (0) points the layer UP (12-o'clock visually)
        //   - tick() rotates via `setAffineTransform` per the math angles
        let cutoutR = cutouts.subdialRadius

        // Hour hand — short and thick.
        let hourLength = cutoutR * 0.55
        let hourWidth = cutoutR * 0.11
        subdialHourHand.bounds = CGRect(x: 0, y: 0, width: hourWidth, height: hourLength)
        subdialHourHand.position = hubCenter
        subdialHourHand.path = CGPath(
            rect: CGRect(x: 0, y: 0, width: hourWidth, height: hourLength),
            transform: nil
        )

        // Minute hand — longer and thinner.
        let minuteLength = cutoutR * 0.80
        let minuteWidth = cutoutR * 0.075
        subdialMinuteHand.bounds = CGRect(x: 0, y: 0, width: minuteWidth, height: minuteLength)
        subdialMinuteHand.position = hubCenter
        subdialMinuteHand.path = CGPath(
            rect: CGRect(x: 0, y: 0, width: minuteWidth, height: minuteLength),
            transform: nil
        )

        // Seconds tick — a short rectangle near the outer ring. The layer
        // extends from center to outer ring; only the tip portion is filled
        // (the rest of the bounds is transparent path-less area).
        let secondTickRing = cutoutR * 0.92
        let secondTickLen = cutoutR * 0.14
        let secondTickWidth = cutoutR * 0.07
        subdialSecondTick.bounds = CGRect(x: 0, y: 0, width: secondTickWidth, height: secondTickRing)
        subdialSecondTick.position = hubCenter
        subdialSecondTick.path = CGPath(
            rect: CGRect(
                x: 0, y: secondTickRing - secondTickLen,
                width: secondTickWidth, height: secondTickLen
            ),
            transform: nil
        )

        // Quadrant accent lines — 4 short radial bars at 12/3/6/9 positions.
        // Drawn as a single path on a layer whose frame is the full lcdLayer
        // bounds, so the path's coordinates are LCD-local.
        subdialQuadrants.frame = lcdLayer.bounds
        subdialQuadrants.path = Self.subdialQuadrantsPath(
            center: hubCenter,
            inner: cutoutR * 0.35,
            outer: cutoutR * 0.48
        )
        subdialQuadrants.lineWidth = max(1, cutoutR * 0.05)

        // Reset rotation cache so the next tick re-renders the seconds tick.
        lastRenderedSecondTickIndex = nil

        // Map — fills the middle-right cutout area.
        let mapFrameLCD = toLCD(cutouts.middleRight)
        mapLayer.frame = mapFrameLCD
        mapContinentsLayer.frame = CGRect(origin: .zero, size: mapFrameLCD.size)
        mapContinentsLayer.path = Self.continentsPath(size: mapFrameLCD.size)

        // Bottom cutout vertical bands (LCD-local y-up, fractions of cutout height):
        //   0.00 – 0.04   bottom margin
        //   0.04 – 0.58   time block (54%) — tall enough for Casio-like digit aspect
        //   0.58 – 0.63   gap between time and secondary
        //   0.63 – 0.90   secondary boxes (27%)
        //   0.90 – 1.00   top margin
        let bottomLCD = toLCD(cutouts.bottom)
        let timeH = bottomLCD.height * 0.54
        let timeY = bottomLCD.minY + bottomLCD.height * 0.04
        let secondaryH = bottomLCD.height * 0.27
        let secondaryY = bottomLCD.minY + bottomLCD.height * 0.63

        // Time container narrower than the cutout width so the digit aspect
        // ratio matches the AE-1200WH (tall + narrow Casio digits).
        let timeWidth = bottomLCD.width * 0.82
        timeContainer.frame = CGRect(
            x: bottomLCD.minX + (bottomLCD.width - timeWidth) / 2,
            y: timeY,
            width: timeWidth,
            height: timeH
        )
        secondaryContainer.frame = CGRect(
            x: bottomLCD.minX + bottomLCD.width * 0.06,
            y: secondaryY,
            width: bottomLCD.width * 0.88,
            height: secondaryH
        )
    }

    /// Rebuilds the four button pushers protruding from the bezel sides.
    /// Two on the left, two on the right; positioned at ~30% / ~70% up the
    /// case (matching the AE-1200WH's MODE / ADJUST / LIGHT / SEARCH layout).
    private func rebuildPushers(caseRect: CGRect) {
        for p in pusherLayers { p.removeFromSuperlayer() }
        pusherLayers.removeAll()

        let pusherDepth = caseRect.width * 0.035    // how far they stick out
        let pusherHeight = caseRect.height * 0.075  // vertical extent
        let pusherInsetFromBezel = caseRect.width * 0.005  // slight overlap into bezel

        // Y positions (canvas-relative, y-up):
        // Upper pushers near top of case → high y
        // Lower pushers near bottom of case → low y
        let upperY = caseRect.minY + caseRect.height * 0.71 - pusherHeight / 2
        let lowerY = caseRect.minY + caseRect.height * 0.29 - pusherHeight / 2

        let positions: [(x: CGFloat, y: CGFloat)] = [
            // Left side, upper + lower
            (caseRect.minX - pusherDepth + pusherInsetFromBezel, upperY),
            (caseRect.minX - pusherDepth + pusherInsetFromBezel, lowerY),
            // Right side, upper + lower
            (caseRect.maxX - pusherInsetFromBezel, upperY),
            (caseRect.maxX - pusherInsetFromBezel, lowerY),
        ]

        let cornerRadius = min(pusherDepth, pusherHeight) * 0.30
        for (x, y) in positions {
            let container = CALayer()
            container.frame = CGRect(x: x, y: y, width: pusherDepth, height: pusherHeight)

            // Horizontal gradient: bright center, dark edges. Reads as a
            // chrome cylinder lit from the front.
            let gradient = CAGradientLayer()
            gradient.frame = container.bounds
            gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
            gradient.colors = [
                RoyalePalette.pusherShadow,
                RoyalePalette.pusher,
                RoyalePalette.pusherHighlight,
                RoyalePalette.pusher,
                RoyalePalette.pusherShadow,
            ]
            gradient.locations = [0.0, 0.25, 0.5, 0.75, 1.0]

            // Rounded-rect mask clips the gradient to the pusher's shape.
            let mask = CAShapeLayer()
            mask.frame = container.bounds
            mask.path = CGPath(
                roundedRect: container.bounds,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            mask.fillColor = NSColor.white.cgColor
            gradient.mask = mask
            container.addSublayer(gradient)

            // Insert below the bezel so the bezel's chamfered edge sits on top.
            caseBackgroundLayer.insertSublayer(container, below: bezelLayer)
            pusherLayers.append(container)
        }
    }

    /// Rebuilds the four screw layers — positioned on the top and bottom
    /// bezel strips above and below the faceplate, NOT at the case corners
    /// (where they'd sit on the diagonal chamfer cuts). Aligned horizontally
    /// with the faceplate's chamfered-corner endpoints at the top/bottom
    /// edges, vertically centered on the bezel strip.
    ///
    /// Each screw is a container CALayer holding:
    ///   - a radial CAGradientLayer (clipped to a circular mask) — the
    ///     polished-metal sphere under top-left light
    ///   - a CAShapeLayer with the phillips cross-slot strokes on top
    private func rebuildScrews(
        caseRect: CGRect,
        chamfer: CGFloat,
        bezelStripHeight: CGFloat,
        screwSize: CGFloat
    ) {
        for s in screwLayers { s.removeFromSuperlayer() }
        screwLayers.removeAll()

        // x positions align with where the faceplate's chamfered diagonals
        // meet the top/bottom edges (= caseRect.minX/maxX ± chamfer).
        // y positions are centered on the bezel strip above/below the face.
        let xLeft = caseRect.minX + chamfer
        let xRight = caseRect.maxX - chamfer
        let yTop = caseRect.maxY - bezelStripHeight / 2
        let yBottom = caseRect.minY + bezelStripHeight / 2

        let positions: [CGPoint] = [
            CGPoint(x: xLeft,  y: yTop),
            CGPoint(x: xRight, y: yTop),
            CGPoint(x: xLeft,  y: yBottom),
            CGPoint(x: xRight, y: yBottom),
        ]

        for center in positions {
            let container = CALayer()
            container.frame = CGRect(
                x: center.x - screwSize / 2,
                y: center.y - screwSize / 2,
                width: screwSize,
                height: screwSize
            )

            // Radial gradient — bright at top-left, dark at bottom-right.
            // y-up coords: (0.35, 0.70) is upper-left of the screw bounds.
            let gradient = CAGradientLayer()
            gradient.frame = container.bounds
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.35, y: 0.70)
            gradient.endPoint = CGPoint(x: 0.95, y: 0.05)
            gradient.colors = [
                RoyalePalette.screwHighlight,
                RoyalePalette.screw,
                RoyalePalette.screwShadow,
            ]
            gradient.locations = [0.0, 0.55, 1.0]

            // Circular mask clips the gradient to the screw head shape.
            let mask = CAShapeLayer()
            mask.frame = container.bounds
            mask.path = CGPath(ellipseIn: container.bounds, transform: nil)
            mask.fillColor = NSColor.white.cgColor
            gradient.mask = mask
            container.addSublayer(gradient)

            // Phillips cross-slot on top.
            let slot = CAShapeLayer()
            slot.frame = container.bounds
            slot.path = Self.screwSlotPath(size: container.bounds.size)
            slot.fillColor = nil
            slot.strokeColor = RoyalePalette.screwSlot
            slot.lineWidth = max(0.5, screwSize * 0.10)
            slot.lineCap = .round
            container.addSublayer(slot)

            caseBackgroundLayer.addSublayer(container)
            screwLayers.append(container)
        }
    }

    // MARK: Path helpers

    /// Just the top edges of the chamfered rectangle (top horizontal +
    /// the two top chamfer diagonals). Used to stroke a bright highlight
    /// along the bezel surfaces that face upward into the light.
    private static func chamferedTopEdgePath(rect: CGRect, chamfer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let c = max(0, min(chamfer, min(rect.width, rect.height) / 2))
        // Y-up coords: maxY is the visual top.
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        return path
    }

    /// Just the bottom edges of the chamfered rectangle. Used to stroke
    /// a dark shadow along the bezel surfaces that face downward.
    private static func chamferedBottomEdgePath(rect: CGRect, chamfer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let c = max(0, min(chamfer, min(rect.width, rect.height) / 2))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + c))
        path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        return path
    }

    /// A path of many thin horizontal lines across `rect`, spaced by
    /// `stride` pixels. Stroked at low alpha and masked to the bezel shape,
    /// this gives the fine horizontal grain of brushed metal.
    private static func brushedStriationPath(in rect: CGRect, stride: CGFloat) -> CGPath {
        let path = CGMutablePath()
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += stride
        }
        return path
    }

    /// Octagonal chamfered-rectangle path. The chamfer is the diagonal cut at
    /// each corner — `chamfer` is the leg length along each edge.
    private static func chamferedRectPath(_ rect: CGRect, chamfer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let c = max(0, min(chamfer, min(rect.width, rect.height) / 2))
        let x0 = rect.minX
        let x1 = rect.maxX
        let y0 = rect.minY
        let y1 = rect.maxY
        path.move(to: CGPoint(x: x0 + c, y: y0))
        path.addLine(to: CGPoint(x: x1 - c, y: y0))
        path.addLine(to: CGPoint(x: x1, y: y0 + c))
        path.addLine(to: CGPoint(x: x1, y: y1 - c))
        path.addLine(to: CGPoint(x: x1 - c, y: y1))
        path.addLine(to: CGPoint(x: x0 + c, y: y1))
        path.addLine(to: CGPoint(x: x0, y: y1 - c))
        path.addLine(to: CGPoint(x: x0, y: y0 + c))
        path.closeSubpath()
        return path
    }

    /// Builds 12 CATextLayer instances showing 60, 5, 10, ..., 55 around
    /// the subdial cutout — printed on the dark faceplate in light silver.
    private func rebuildSubdialNumbers(cutouts: CutoutGeometry) {
        for layer in subdialNumberLayers { layer.removeFromSuperlayer() }
        subdialNumberLayers.removeAll()

        let cx = cutouts.subdialCenter.x
        let cy = cutouts.subdialCenter.y
        let cutoutR = cutouts.subdialRadius
        let textRadius = cutoutR * 1.66  // outside the tick ring, inside the rivet ring
        let fontSize = cutoutR * 0.26
        let scale = rootLayer?.contentsScale ?? 2.0

        let labels = ["60", "5", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"]
        for (i, label) in labels.enumerated() {
            // y-up clockwise: theta = π/2 - i·step puts index 0 at top.
            let theta = .pi / 2 - (CGFloat(i) / 12) * 2 * .pi
            let tx = cx + cos(theta) * textRadius
            let ty = cy + sin(theta) * textRadius

            let layer = CATextLayer()
            layer.string = label
            layer.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            layer.fontSize = fontSize
            layer.foregroundColor = RoyalePalette.faceplatePrint
            layer.alignmentMode = .center
            layer.contentsScale = scale
            layer.actions = ["contents": NSNull(), "position": NSNull()]

            let boxW = fontSize * 1.8
            let boxH = fontSize * 1.3
            layer.frame = CGRect(
                x: tx - boxW / 2,
                y: ty - boxH / 2,
                width: boxW,
                height: boxH
            )
            // Above the faceplate (faceplate was added before; sublayers of
            // caseBackgroundLayer stack later == higher z).
            caseBackgroundLayer.addSublayer(layer)
            subdialNumberLayers.append(layer)
        }
    }

    /// Four black rivets at NW/NE/SW/SE corners around the subdial cutout —
    /// the black dots printed on the faceplate that read as "screws" holding
    /// the subdial assembly.
    private func rebuildSubdialRivets(cutouts: CutoutGeometry) {
        for r in subdialRivetLayers { r.removeFromSuperlayer() }
        subdialRivetLayers.removeAll()

        let cx = cutouts.subdialCenter.x
        let cy = cutouts.subdialCenter.y
        let cutoutR = cutouts.subdialRadius
        let rivetR = cutoutR * 0.085
        let rivetDist = cutoutR * 1.90

        let angles: [CGFloat] = [-.pi/4, -3 * .pi/4, .pi/4, 3 * .pi/4]
        for theta in angles {
            let rx = cx + cos(theta) * rivetDist
            let ry = cy + sin(theta) * rivetDist
            let layer = CAShapeLayer()
            layer.frame = CGRect(
                x: rx - rivetR, y: ry - rivetR,
                width: rivetR * 2, height: rivetR * 2
            )
            layer.path = CGPath(
                ellipseIn: CGRect(origin: .zero, size: layer.frame.size),
                transform: nil
            )
            layer.fillColor = RoyalePalette.faceplateRivet
            layer.strokeColor = nil
            caseBackgroundLayer.addSublayer(layer)
            subdialRivetLayers.append(layer)
        }
    }

    /// Dot-matrix world map matching the AE-1200WH's visual style. A coarse
    /// grid where each '#' cell becomes a small filled dot. Atlantic-centered
    /// projection: Americas on the left, Eurasia/Africa center, Pacific
    /// edges wrap. Rough shapes only — true cartographic accuracy is
    /// deferred to Story 1.5.1's real bitmap asset.
    private static func continentsPath(size: CGSize) -> CGPath {
        // 36 cols × 14 rows; '#' = land, '.' = water. Row 0 is north.
        // Atlantic-centered: Americas left, Eurasia/Africa center, Indonesia
        // + Australia right. Recognizable silhouettes only — true cartography
        // is the bitmap asset in Story 1.5.1.
        let map: [String] = [
            "....................................",
            "........##...............##.........",
            "....########......##############....",
            "..##########....################....",
            "..#########.....################....",
            "...########......##############.....",
            "....#######.......############......",
            ".....######........###########..##..",
            "......#####.........##########..###.",
            ".......####..........#########..###.",
            ".......###...........#######....##..",
            "........##...........######.........",
            ".........#............####..........",
            "....................................",
        ]
        let rows = map.count
        let cols = map.first?.count ?? 0
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        let dotR = min(cellW, cellH) * 0.42

        let path = CGMutablePath()
        for (rowIdx, rowStr) in map.enumerated() {
            // Row 0 is north (top) in the array. In y-up CALayer coords,
            // the top has the highest y, so flip the row index.
            let yIdx = rows - 1 - rowIdx
            for (colIdx, char) in rowStr.enumerated() {
                guard char == "#" else { continue }
                let x = (CGFloat(colIdx) + 0.5) * cellW
                let y = (CGFloat(yIdx) + 0.5) * cellH
                path.addEllipse(in: CGRect(
                    x: x - dotR, y: y - dotR,
                    width: dotR * 2, height: dotR * 2
                ))
            }
        }
        return path
    }

    /// Just the phillips cross-slot of the screw (two perpendicular line
    /// segments). The screw's circular shape comes from the radial-gradient
    /// mask, not this path.
    private static func screwSlotPath(size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let r = min(size.width, size.height) / 2
        let cx = size.width / 2
        let cy = size.height / 2
        let slotLen = r * 0.55
        path.move(to: CGPoint(x: cx - slotLen, y: cy))
        path.addLine(to: CGPoint(x: cx + slotLen, y: cy))
        path.move(to: CGPoint(x: cx, y: cy - slotLen))
        path.addLine(to: CGPoint(x: cx, y: cy + slotLen))
        return path
    }

    private func rebuildTimeSlots() {
        for slot in timeDigitSlots { slot.removeFromParent() }
        for slot in colonSlots { slot.removeFromParent() }
        for slot in meridiemLetterSlots { slot.removeFromParent() }
        timeDigitSlots = []
        colonSlots = []
        meridiemLetterSlots = []

        // AE-1200WH layout with AM/PM:
        //   AM/PM letters (2 × 0.55D)    → 1.1 D   (same width as a small digit
        //                                            → near-square pixel cells)
        //   gap before HH                → 0.2 D
        //   big H1 H2 [colon] M1 M2      → 4.3 D
        //   gap before SS                → 0.3 D
        //   small S1 S2 (2 × 0.55D)      → 1.1 D
        //   total                         → 7.0 D
        let totalWidth = timeContainer.bounds.width
        let totalHeight = timeContainer.bounds.height
        let bigD = totalWidth / 7.0
        let bigColonW = bigD * 0.3
        let bigH = totalHeight
        let smallD = bigD * 0.55
        let smallH = totalHeight * 0.55
        // AM/PM hugs the TOP of the row; SS hugs the BOTTOM, matching the
        // AE-1200WH where PM sits high-left and the small seconds sit low-right.
        let meridiemY = totalHeight - smallH
        let secondsY: CGFloat = 0
        let meridiemW = smallD             // matches a small-digit width

        var x: CGFloat = 0

        // AM / PM letter slots (pixel-block letters), top-aligned.
        for _ in 0..<2 {
            let frame = CGRect(x: x, y: meridiemY, width: meridiemW, height: smallH)
            meridiemLetterSlots.append(LetterSlot(parent: timeContainer, frame: frame))
            x += meridiemW
        }
        x += bigD * 0.2  // gap before HH

        // Big H1, H2
        for _ in 0..<2 {
            timeDigitSlots.append(DigitSlot(
                parent: timeContainer,
                frame: CGRect(x: x, y: 0, width: bigD, height: bigH)
            ))
            x += bigD
        }
        // Big colon (blinks at 1 Hz)
        colonSlots.append(ColonSlot(
            parent: timeContainer,
            frame: CGRect(x: x, y: 0, width: bigColonW, height: bigH)
        ))
        x += bigColonW
        // Big M1, M2
        for _ in 0..<2 {
            timeDigitSlots.append(DigitSlot(
                parent: timeContainer,
                frame: CGRect(x: x, y: 0, width: bigD, height: bigH)
            ))
            x += bigD
        }
        // Gap before small SS
        x += bigD * 0.3
        // Small S1, S2 (bottom-aligned with big digits)
        for _ in 0..<2 {
            timeDigitSlots.append(DigitSlot(
                parent: timeContainer,
                frame: CGRect(x: x, y: secondsY, width: smallD, height: smallH)
            ))
            x += smallD
        }
    }

    private func rebuildSecondarySlots() {
        for slot in dayLetterSlots { slot.removeFromParent() }
        for slot in dateDigitSlots { slot.removeFromParent() }
        for box in secondaryBoxLayers { box.removeFromSuperlayer() }
        dateSeparatorSlot?.removeFromParent()
        dayLetterSlots = []
        dateDigitSlots = []
        dateSeparatorSlot = nil
        secondaryBoxLayers = []

        let totalWidth = secondaryContainer.bounds.width
        let height = secondaryContainer.bounds.height

        // Two side-by-side bordered boxes, matching the AE-1200WH's "5.01"
        // (day-of-week) and "6:30" (date) data fields.
        //   left box:  contains 3 day-of-week letters
        //   right box: contains MM-DD digits with dash separator
        let boxGap = totalWidth * 0.04
        let boxWidth = (totalWidth - boxGap) / 2
        let leftBoxRect = CGRect(x: 0, y: 0, width: boxWidth, height: height)
        let rightBoxRect = CGRect(x: boxWidth + boxGap, y: 0, width: boxWidth, height: height)

        // Box border decorations
        for rect in [leftBoxRect, rightBoxRect] {
            let box = CAShapeLayer()
            box.frame = rect
            box.path = CGPath(
                rect: CGRect(origin: .zero, size: rect.size),
                transform: nil
            )
            box.fillColor = nil
            box.strokeColor = RoyalePalette.litSegment
            box.lineWidth = max(0.5, height * 0.05)
            box.opacity = 0.55  // borders are subtle on the real LCD
            secondaryContainer.addSublayer(box)
            secondaryBoxLayers.append(box)
        }

        // Inset content within each box so glyphs don't kiss the borders.
        let inset = height * 0.18

        // --- Left box: 3 day-of-week letters, centered ---
        let leftContent = leftBoxRect.insetBy(dx: inset, dy: inset)
        let letterW = leftContent.width / 3
        for i in 0..<3 {
            let frame = CGRect(
                x: leftContent.minX + CGFloat(i) * letterW,
                y: leftContent.minY,
                width: letterW,
                height: leftContent.height
            )
            dayLetterSlots.append(LetterSlot(parent: secondaryContainer, frame: frame))
        }

        // --- Right box: MM-DD, centered ---
        // Layout inside content: 2D + 0.4D + 2D = 4.4D
        let rightContent = rightBoxRect.insetBy(dx: inset, dy: inset)
        let unitR = rightContent.width / 4.4
        let digitWR = unitR
        let sepWR = unitR * 0.4
        var xr = rightContent.minX
        // Month digits
        for _ in 0..<2 {
            let frame = CGRect(x: xr, y: rightContent.minY, width: digitWR, height: rightContent.height)
            dateDigitSlots.append(DigitSlot(parent: secondaryContainer, frame: frame))
            xr += digitWR
        }
        // Separator dash
        let sepFrame = CGRect(x: xr, y: rightContent.minY, width: sepWR, height: rightContent.height)
        dateSeparatorSlot = SeparatorSlot(parent: secondaryContainer, frame: sepFrame)
        xr += sepWR
        // Day digits
        for _ in 0..<2 {
            let frame = CGRect(x: xr, y: rightContent.minY, width: digitWR, height: rightContent.height)
            dateDigitSlots.append(DigitSlot(parent: secondaryContainer, frame: frame))
            xr += digitWR
        }
    }

}

// MARK: - 7-segment digit slot

/// One LCD digit. Owns 7 `CAShapeLayer`s (one per segment), positioned inside
/// a private `slotLayer` whose frame is set in parent coordinates. `set(digit:)`
/// toggles each segment layer's `opacity`. Paths are built once and never
/// rebuilt.
private final class DigitSlot {
    private let slotLayer = CALayer()
    private var segmentLayers: [RoyaleMath.Segment: CAShapeLayer] = [:]

    init(parent: CALayer, frame: CGRect) {
        slotLayer.frame = frame
        parent.addSublayer(slotLayer)

        let size = frame.size
        for seg in RoyaleMath.Segment.allCases {
            let layer = CAShapeLayer()
            layer.frame = CGRect(origin: .zero, size: size)
            layer.path = Self.path(for: seg, size: size)
            layer.fillColor = RoyalePalette.litSegment
            layer.opacity = 0
            slotLayer.addSublayer(layer)
            segmentLayers[seg] = layer
        }
    }

    func set(digit: Int) {
        let on = RoyaleMath.segments(forDigit: digit)
        for (seg, layer) in segmentLayers {
            layer.opacity = on.contains(seg) ? 1 : 0
        }
    }

    func removeFromParent() {
        slotLayer.removeFromSuperlayer()
    }

    /// Builds the path for a single segment in slot-local y-up coordinates.
    /// Segment thickness scales with the smaller of width/height; gaps at
    /// segment ends + small side inset give the LCD its characteristic
    /// discrete-segment look and prevent adjacent digit slots from kissing
    /// at their shared boundary.
    static func path(for segment: RoyaleMath.Segment, size: CGSize) -> CGPath {
        let w = size.width
        let h = size.height
        let t = min(w, h) * 0.14  // segment thickness
        let p = CGMutablePath()
        let gap = t * 0.45             // gap at the ends of horizontal segments
        let sideInset = t * 0.35       // inset of vertical segments from the slot edge

        switch segment {
        case .top:
            p.addRect(CGRect(x: gap + sideInset, y: h - t,
                             width: w - 2 * (gap + sideInset), height: t))
        case .bottom:
            p.addRect(CGRect(x: gap + sideInset, y: 0,
                             width: w - 2 * (gap + sideInset), height: t))
        case .middle:
            p.addRect(CGRect(x: gap + sideInset, y: h * 0.5 - t * 0.5,
                             width: w - 2 * (gap + sideInset), height: t))
        case .topLeft:
            p.addRect(CGRect(x: sideInset, y: h * 0.5 + gap,
                             width: t, height: h * 0.5 - t - gap))
        case .topRight:
            p.addRect(CGRect(x: w - t - sideInset, y: h * 0.5 + gap,
                             width: t, height: h * 0.5 - t - gap))
        case .bottomLeft:
            p.addRect(CGRect(x: sideInset, y: gap,
                             width: t, height: h * 0.5 - t - gap))
        case .bottomRight:
            p.addRect(CGRect(x: w - t - sideInset, y: gap,
                             width: t, height: h * 0.5 - t - gap))
        }

        return p
    }
}

// MARK: - 5×7 pixel-block letter slot

/// One letter glyph slot. Owns 35 `CAShapeLayer`s (5×7 pixel grid).
/// `set(letter:)` toggles each pixel's `opacity` from `RoyaleMath.pixels(forLetter:)`.
/// The pixel grid is y-up in slot-local coordinates; row 0 of the math
/// representation = top of the letter, so row r renders at y = (6 - r) * cellH.
private final class LetterSlot {
    private let slotLayer = CALayer()
    private var pixelLayers: [RoyaleMath.PixelCell: CAShapeLayer] = [:]

    init(parent: CALayer, frame: CGRect) {
        slotLayer.frame = frame
        parent.addSublayer(slotLayer)

        let cellW = frame.width / 5
        let cellH = frame.height / 7
        // Inset gives the pixels visible separation — the LCD pixel grid look.
        let inset: CGFloat = max(0.5, min(cellW, cellH) * 0.08)

        for r in 0..<7 {
            for c in 0..<5 {
                let cell = RoyaleMath.PixelCell(row: r, col: c)
                let yUp = CGFloat(6 - r) * cellH
                let rect = CGRect(
                    x: CGFloat(c) * cellW + inset,
                    y: yUp + inset,
                    width: cellW - inset * 2,
                    height: cellH - inset * 2
                )
                let layer = CAShapeLayer()
                layer.frame = rect
                layer.path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
                layer.fillColor = RoyalePalette.litSegment
                layer.opacity = 0
                slotLayer.addSublayer(layer)
                pixelLayers[cell] = layer
            }
        }
    }

    func set(letter: Character) {
        let on = RoyaleMath.pixels(forLetter: letter)
        for (cell, layer) in pixelLayers {
            layer.opacity = on.contains(cell) ? 1 : 0
        }
    }

    func removeFromParent() {
        slotLayer.removeFromSuperlayer()
    }
}

// MARK: - Colon slot (two stacked dots)

private final class ColonSlot {
    private let slotLayer = CALayer()
    private let dotTop = CAShapeLayer()
    private let dotBottom = CAShapeLayer()

    init(parent: CALayer, frame: CGRect) {
        slotLayer.frame = frame
        parent.addSublayer(slotLayer)

        let dot = min(frame.width, frame.height) * 0.35
        let cx = frame.width / 2
        let topY = frame.height * 0.65
        let botY = frame.height * 0.35

        for (layer, y) in [(dotTop, topY), (dotBottom, botY)] {
            layer.frame = CGRect(x: cx - dot / 2, y: y - dot / 2, width: dot, height: dot)
            layer.path = CGPath(
                ellipseIn: CGRect(origin: .zero, size: CGSize(width: dot, height: dot)),
                transform: nil
            )
            layer.fillColor = RoyalePalette.litSegment
            layer.opacity = 1
            slotLayer.addSublayer(layer)
        }
    }

    func set(on: Bool) {
        let v: Float = on ? 1 : 0
        dotTop.opacity = v
        dotBottom.opacity = v
    }

    func removeFromParent() {
        slotLayer.removeFromSuperlayer()
    }
}

// MARK: - Separator dash (date MM-DD)

private final class SeparatorSlot {
    private let slotLayer = CALayer()
    private let bar = CAShapeLayer()

    init(parent: CALayer, frame: CGRect) {
        slotLayer.frame = frame
        parent.addSublayer(slotLayer)

        let dashWidth = frame.width * 0.7
        let dashHeight = min(frame.height * 0.20, frame.width * 0.4)
        let x = (frame.width - dashWidth) / 2
        let y = (frame.height - dashHeight) / 2
        bar.frame = CGRect(x: x, y: y, width: dashWidth, height: dashHeight)
        bar.path = CGPath(rect: CGRect(origin: .zero, size: bar.frame.size), transform: nil)
        bar.fillColor = RoyalePalette.litSegment
        bar.opacity = 1
        slotLayer.addSublayer(bar)
    }

    func removeFromParent() {
        slotLayer.removeFromSuperlayer()
    }
}
