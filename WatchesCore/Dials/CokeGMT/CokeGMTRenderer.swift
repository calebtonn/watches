import AppKit
import CoreText
import QuartzCore

/// Coke GMT — homage of the Tudor Black Bay GMT (bicolor red/black bezel).
///
/// Story 2.1's stress test is **parameter passing**: the four hands derive
/// from TWO different time sources (local time + UTC) without any change to
/// the `DialRenderer` protocol contract.
///
/// - Hour, minute, second hands → LOCAL time (via injected `Calendar`).
/// - GMT (24h scale) hand → UTC (via `CokeGMTMath.utcCalendar`).
///
/// See `notes.md` and `design-spec.md` for design decisions and exact
/// element specifications. Spec is the source of truth.
public final class CokeGMTRenderer: DialRenderer {

    // MARK: DialRenderer static metadata

    public static let identity = DialIdentity(
        id: "cokeGMT",
        displayName: "Coke GMT",
        homageCredit: "Inspired by the Tudor Black Bay GMT",
        previewAssetName: "coke-gmt-preview"
    )

    public static let visibility: DialVisibility = .default

    // MARK: State

    private weak var rootLayer: CALayer?
    private var canvas: CGSize = .zero
    private var timeSource: TimeSource?
    private let localCalendar: Calendar = .autoupdatingCurrent

    /// Last rendered integer second — reduce-motion dedup.
    private var lastRenderedSecond: Int?
    /// Last rendered day-of-month — only repaint the date digit when the day changes.
    private var lastRenderedDay: Int?

    // MARK: Cached procedural textures

    private var dialGrainImage: CGImage?
    private var brushedSteelImage: CGImage?

    // MARK: Case + bezel layers

    private let canvasBackground = CALayer()
    private let caseTopGradient = CAGradientLayer()
    private let caseTopMask = CAShapeLayer()
    private let caseBrushLayer = CALayer()
    private let chamferRingLayer = CAShapeLayer()
    private let polishedRimLayer = CAShapeLayer()
    private let outerRimGlint = CAShapeLayer()
    private let chamferGlint = CAShapeLayer()
    private let innerEdgeStroke = CAShapeLayer()

    private let bezelBlackHalf = CAShapeLayer()
    private let bezelBlackGradient = CAGradientLayer()
    private let bezelRedHalf = CAShapeLayer()
    private let bezelRedGradient = CAGradientLayer()
    private let bezelKnurlingLayer = CAShapeLayer()   // Pass-3: outer-edge teeth
    private let bezelInnerGroove = CAShapeLayer()
    private let bezelNumeralsLayer = CAShapeLayer()
    private let bezelTicksLayer = CAShapeLayer()
    private let bezelPipLayer = CAShapeLayer()

    // MARK: Dial layers

    private let dialFaceLayer = CAShapeLayer()
    private let dialVignetteLayer = CAGradientLayer()
    private let dialGrainLayer = CALayer()
    private let crystalGlassLayer = CAGradientLayer()    // Pass-3: sapphire crystal annulus

    private let minuteTrackMinorTicks = CAShapeLayer()
    private let minuteTrackMajorTicks = CAShapeLayer()

    private let markerDotsLayer = CAShapeLayer()
    private let markerBarsLayer = CAShapeLayer()
    private let markerTriangle12Layer = CAShapeLayer()

    // MARK: Date window layers

    private let dateFrameLayer = CAShapeLayer()
    private let dateBoxLayer = CAShapeLayer()
    private let dateDigitLayer = CAShapeLayer()
    private var dateBoxRect: CGRect = .zero
    private var dateBoxFont: NSFont?

    // MARK: Hand layers

    private let hourHandLayer = CAShapeLayer()
    private let minuteHandLayer = CAShapeLayer()
    private let gmtHandLayer = CAShapeLayer()
    private let secondsHandLayer = CAShapeLayer()
    private let secondsPommelLayer = CAShapeLayer()
    private let secondsTipLumeDot = CAShapeLayer()    // Pass-2: mandatory tip dot
    private let centerHubLayer = CAShapeLayer()

    // MARK: Anchors

    private struct LayoutAnchors {
        let caseCenter: CGPoint
        let caseRadius: CGFloat
        let dialRadius: CGFloat
        let bezelInnerR: CGFloat
        let bezelOuterR: CGFloat
    }
    private var anchors: LayoutAnchors?

    public init() {}

    // MARK: DialRenderer

    public func attach(rootLayer: CALayer, canvas: CGSize, timeSource: TimeSource) {
        self.rootLayer = rootLayer
        self.canvas = canvas
        self.timeSource = timeSource

        installLayers()
        layoutLayers(for: canvas)

        // Pass-2 fix: seed lastRenderedDay from a one-time `Date()` read so
        // the date window shows today's date on the very first frame
        // (rather than the "1" placeholder that clamps from `day = 0`).
        // This is install-time only and NOT a P4 violation — the per-frame
        // loop is still purely time-driven via tick(reduceMotion:); we
        // just want the initial visible state to match what the first
        // tick would produce anyway.
        let initialDay = localCalendar.component(.day, from: Date())
        updateDateDigit(day: initialDay)
        lastRenderedDay = initialDay

        _ = tick(reduceMotion: false)

        Logging.renderer.info(
            "CokeGMTRenderer attached: canvas=\(Int(canvas.width), privacy: .public)×\(Int(canvas.height), privacy: .public)"
        )
    }

    @discardableResult
    public func tick(reduceMotion: Bool) -> [CGRect] {
        guard let timeSource else { return [] }
        let now = timeSource.now
        let integerSecond = Int(now.timeIntervalSince1970)
        if reduceMotion, integerSecond == lastRenderedSecond {
            return []
        }
        lastRenderedSecond = integerSecond

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Hour, minute, GMT hands always update (per-minute/per-hour
        // movement is so slow that the `setDisableActions` wrap suppresses
        // any visible animation).
        let hourAngle = CokeGMTMath.hourAngle(from: now, calendar: localCalendar)
        let minuteAngle = CokeGMTMath.minuteAngle(from: now, calendar: localCalendar)
        let gmtAngle = CokeGMTMath.gmtAngle(from: now)

        hourHandLayer.setAffineTransform(CGAffineTransform(rotationAngle: -hourAngle))
        minuteHandLayer.setAffineTransform(CGAffineTransform(rotationAngle: -minuteAngle))
        gmtHandLayer.setAffineTransform(CGAffineTransform(rotationAngle: -gmtAngle))

        // Seconds hand: per-second tick. Frozen under reduce-motion.
        if !reduceMotion {
            let secondAngle = CokeGMTMath.secondAngle(from: now, calendar: localCalendar)
            secondsHandLayer.setAffineTransform(CGAffineTransform(rotationAngle: -secondAngle))
        }

        // Date digit: update only on day rollover.
        let day = CokeGMTMath.dayOfMonth(from: now, calendar: localCalendar)
        if day != lastRenderedDay {
            updateDateDigit(day: day)
            lastRenderedDay = day
        }

        return [
            hourHandLayer.frame,
            minuteHandLayer.frame,
            gmtHandLayer.frame,
            secondsHandLayer.frame,
            dateBoxRect,
        ]
    }

    public func canvasDidChange(to canvas: CGSize) {
        self.canvas = canvas
        layoutLayers(for: canvas)
    }

    public func detach() {
        canvasBackground.removeFromSuperlayer()
        rootLayer = nil
        timeSource = nil
        anchors = nil
        lastRenderedSecond = nil
        lastRenderedDay = nil
    }

    // MARK: Install

    private func installLayers() {
        guard let rootLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Procedural textures generated once.
        if dialGrainImage == nil { dialGrainImage = makeDialGrainImage() }
        if brushedSteelImage == nil { brushedSteelImage = makeBrushedSteelImage() }

        // Canvas background.
        canvasBackground.backgroundColor = NSColor.black.cgColor
        rootLayer.addSublayer(canvasBackground)

        // Case top gradient with steel colors (masked to the full case disc).
        caseTopGradient.colors = [
            CokeGMTPalette.caseSteelHighlight,
            CokeGMTPalette.caseSteel,
            CokeGMTPalette.caseSteelShadow,
        ]
        caseTopGradient.locations = [0.0, 0.45, 1.0]
        caseTopGradient.startPoint = CGPoint(x: 0.30, y: 1.0)
        caseTopGradient.endPoint = CGPoint(x: 0.70, y: 0.0)
        caseTopMask.fillColor = NSColor.white.cgColor
        caseTopGradient.mask = caseTopMask
        canvasBackground.addSublayer(caseTopGradient)

        // Brushed steel overlay on the chamfer ring.
        caseBrushLayer.contents = brushedSteelImage
        caseBrushLayer.contentsGravity = .resize
        caseBrushLayer.opacity = 0.08
        canvasBackground.addSublayer(caseBrushLayer)

        // Bezel halves — each is a CAShapeLayer mask for a gradient layer.
        bezelBlackGradient.colors = [
            CokeGMTPalette.bezelBlackHighlight,
            CokeGMTPalette.bezelBlack,
            CokeGMTPalette.bezelBlackShadow,
        ]
        bezelBlackGradient.locations = [0.0, 0.40, 1.0]
        bezelBlackGradient.startPoint = CGPoint(x: 0.30, y: 1.0)
        bezelBlackGradient.endPoint = CGPoint(x: 0.70, y: 0.0)
        bezelBlackHalf.fillColor = NSColor.white.cgColor
        bezelBlackGradient.mask = bezelBlackHalf
        canvasBackground.addSublayer(bezelBlackGradient)

        bezelRedGradient.colors = [
            CokeGMTPalette.bezelRedHighlight,
            CokeGMTPalette.bezelRed,
            CokeGMTPalette.bezelRedShadow,
        ]
        bezelRedGradient.locations = [0.0, 0.45, 1.0]
        bezelRedGradient.startPoint = CGPoint(x: 0.30, y: 1.0)
        bezelRedGradient.endPoint = CGPoint(x: 0.70, y: 0.0)
        bezelRedHalf.fillColor = NSColor.white.cgColor
        bezelRedGradient.mask = bezelRedHalf
        canvasBackground.addSublayer(bezelRedGradient)

        bezelInnerGroove.fillColor = nil
        bezelInnerGroove.strokeColor = NSColor(white: 0.0, alpha: 0.60).cgColor
        canvasBackground.addSublayer(bezelInnerGroove)

        // Pass-3: knurled outer-edge teeth around the bezel rim. Cream-gold
        // to read as polished metal rim, not as ticks.
        bezelKnurlingLayer.fillColor = nil
        bezelKnurlingLayer.strokeColor = NSColor(white: 0.0, alpha: 0.55).cgColor
        bezelKnurlingLayer.lineCap = .butt
        canvasBackground.addSublayer(bezelKnurlingLayer)

        bezelTicksLayer.fillColor = CokeGMTPalette.bezelNumeralCream
        bezelTicksLayer.strokeColor = nil
        canvasBackground.addSublayer(bezelTicksLayer)

        bezelNumeralsLayer.fillColor = CokeGMTPalette.bezelNumeralCream
        bezelNumeralsLayer.strokeColor = NSColor(srgbRed: 0.78, green: 0.65, blue: 0.40, alpha: 0.4).cgColor
        bezelNumeralsLayer.lineWidth = 0.4
        canvasBackground.addSublayer(bezelNumeralsLayer)

        bezelPipLayer.fillColor = CokeGMTPalette.lumeCream
        bezelPipLayer.strokeColor = CokeGMTPalette.lumeCreamOutline
        bezelPipLayer.shadowColor = NSColor.black.cgColor
        bezelPipLayer.shadowOpacity = 0.45
        bezelPipLayer.shadowOffset = CGSize(width: 0.6, height: -0.6)
        bezelPipLayer.shadowRadius = 1.0
        canvasBackground.addSublayer(bezelPipLayer)

        // Pass-3: chamferRingLayer is REPURPOSED as a very subtle dark
        // engraved-channel stroke at the dial boundary (lower-contrast
        // than the Pass-2 "polished steel" appearance) so the sapphire
        // crystal effect above can dominate.
        chamferRingLayer.fillColor = nil
        chamferRingLayer.strokeColor = NSColor(white: 0.0, alpha: 0.45).cgColor
        canvasBackground.addSublayer(chamferRingLayer)

        // Pass 3.2: crystalGlassLayer is configured here but ADDED LATER
        // (after dialFaceLayer + grain) so it renders ABOVE the dial-black
        // background — the translucent gradient reads as "glass-over-dial"
        // rather than "silver ring against canvas". See the "// crystal
        // install (post-dial)" block below.
        crystalGlassLayer.type = .axial
        crystalGlassLayer.startPoint = CGPoint(x: 0.20, y: 1.00)
        crystalGlassLayer.endPoint = CGPoint(x: 0.85, y: 0.05)
        crystalGlassLayer.colors = [
            NSColor(white: 1.0, alpha: 0.38).cgColor,    // boosted from 0.28
            NSColor(white: 1.0, alpha: 0.14).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor,
            NSColor(white: 0.6, alpha: 0.10).cgColor,
        ]
        crystalGlassLayer.locations = [0.0, 0.35, 0.65, 1.0]

        polishedRimLayer.fillColor = nil
        polishedRimLayer.strokeColor = CokeGMTPalette.caseSteelHighlight
        canvasBackground.addSublayer(polishedRimLayer)

        outerRimGlint.fillColor = nil
        outerRimGlint.strokeColor = NSColor(white: 1.0, alpha: 0.85).cgColor
        outerRimGlint.lineCap = .round
        canvasBackground.addSublayer(outerRimGlint)

        chamferGlint.fillColor = nil
        chamferGlint.strokeColor = NSColor(white: 1.0, alpha: 0.65).cgColor
        chamferGlint.lineCap = .round
        canvasBackground.addSublayer(chamferGlint)

        innerEdgeStroke.fillColor = nil
        innerEdgeStroke.strokeColor = CokeGMTPalette.chamferShadow
        canvasBackground.addSublayer(innerEdgeStroke)

        // Dial face + vignette + grain.
        dialFaceLayer.fillColor = CokeGMTPalette.dialBlack
        dialFaceLayer.strokeColor = nil
        canvasBackground.addSublayer(dialFaceLayer)

        dialVignetteLayer.type = .radial
        dialVignetteLayer.startPoint = CGPoint(x: 0.45, y: 0.55)
        dialVignetteLayer.endPoint = CGPoint(x: 1.05, y: 1.05)
        dialVignetteLayer.colors = [
            NSColor(white: 1.0, alpha: 0.04).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor,
            NSColor(white: 0.0, alpha: 0.22).cgColor,
        ]
        dialVignetteLayer.locations = [0.0, 0.70, 1.0]
        canvasBackground.addSublayer(dialVignetteLayer)

        dialGrainLayer.contents = dialGrainImage
        dialGrainLayer.contentsGravity = .resize
        dialGrainLayer.opacity = 0.04
        canvasBackground.addSublayer(dialGrainLayer)

        // crystal install (post-dial). Sapphire crystal annulus is added
        // AFTER the dial face so it overlays the dial-black background —
        // reads as transparent glass showing the dial through, not silver
        // chamfer.
        canvasBackground.addSublayer(crystalGlassLayer)

        // Minute track.
        minuteTrackMinorTicks.fillColor = nil
        minuteTrackMinorTicks.strokeColor = CokeGMTPalette.bezelNumeralCream
        minuteTrackMinorTicks.lineCap = .butt
        canvasBackground.addSublayer(minuteTrackMinorTicks)

        minuteTrackMajorTicks.fillColor = nil
        minuteTrackMajorTicks.strokeColor = CokeGMTPalette.bezelNumeralCream
        minuteTrackMajorTicks.lineCap = .butt
        canvasBackground.addSublayer(minuteTrackMajorTicks)

        // Hour markers — dots, bars, triangle.
        markerDotsLayer.fillColor = CokeGMTPalette.lumeCream
        markerDotsLayer.strokeColor = CokeGMTPalette.lumeCreamOutline
        markerDotsLayer.shadowColor = NSColor.black.cgColor
        markerDotsLayer.shadowOpacity = 0.55
        markerDotsLayer.shadowOffset = CGSize(width: 0.5, height: -0.6)
        markerDotsLayer.shadowRadius = 1.2
        canvasBackground.addSublayer(markerDotsLayer)

        markerBarsLayer.fillColor = CokeGMTPalette.lumeCream
        markerBarsLayer.strokeColor = CokeGMTPalette.lumeCreamOutline
        markerBarsLayer.shadowColor = NSColor.black.cgColor
        markerBarsLayer.shadowOpacity = 0.55
        markerBarsLayer.shadowOffset = CGSize(width: 0.5, height: -0.6)
        markerBarsLayer.shadowRadius = 1.2
        canvasBackground.addSublayer(markerBarsLayer)

        markerTriangle12Layer.fillColor = CokeGMTPalette.lumeCream
        markerTriangle12Layer.strokeColor = CokeGMTPalette.lumeCreamOutline
        markerTriangle12Layer.shadowColor = NSColor.black.cgColor
        markerTriangle12Layer.shadowOpacity = 0.55
        markerTriangle12Layer.shadowOffset = CGSize(width: 0.6, height: -0.8)
        markerTriangle12Layer.shadowRadius = 1.4
        canvasBackground.addSublayer(markerTriangle12Layer)

        // Date window.
        dateFrameLayer.fillColor = CokeGMTPalette.dateFrameGold
        dateFrameLayer.strokeColor = CokeGMTPalette.goldOutline
        dateFrameLayer.shadowColor = NSColor.black.cgColor
        dateFrameLayer.shadowOpacity = 0.45
        dateFrameLayer.shadowOffset = CGSize(width: 0.6, height: -0.8)
        dateFrameLayer.shadowRadius = 1.2
        canvasBackground.addSublayer(dateFrameLayer)

        dateBoxLayer.fillColor = CokeGMTPalette.dateBoxWhite
        dateBoxLayer.strokeColor = NSColor(white: 0.0, alpha: 0.20).cgColor
        dateBoxLayer.lineWidth = 0.4
        canvasBackground.addSublayer(dateBoxLayer)

        dateDigitLayer.fillColor = CokeGMTPalette.dateNumeralBlack
        dateDigitLayer.strokeColor = nil
        dateDigitLayer.shadowColor = NSColor.black.cgColor
        dateDigitLayer.shadowOpacity = 0.25
        dateDigitLayer.shadowOffset = CGSize(width: 0.3, height: -0.5)
        dateDigitLayer.shadowRadius = 0.6
        canvasBackground.addSublayer(dateDigitLayer)

        // Hands — anchor at pivot, rotate via setAffineTransform.
        hourHandLayer.fillColor = CokeGMTPalette.lumeCream
        hourHandLayer.strokeColor = CokeGMTPalette.lumeCreamOutline
        hourHandLayer.lineWidth = 0.4
        hourHandLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        hourHandLayer.actions = ["transform": NSNull(), "position": NSNull()]
        hourHandLayer.shadowColor = NSColor.black.cgColor
        hourHandLayer.shadowOpacity = 0.55
        hourHandLayer.shadowOffset = CGSize(width: 1.2, height: -1.8)
        hourHandLayer.shadowRadius = 2.5
        canvasBackground.addSublayer(hourHandLayer)

        minuteHandLayer.fillColor = CokeGMTPalette.lumeCream
        minuteHandLayer.strokeColor = CokeGMTPalette.lumeCreamOutline
        minuteHandLayer.lineWidth = 0.4
        minuteHandLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        minuteHandLayer.actions = ["transform": NSNull(), "position": NSNull()]
        minuteHandLayer.shadowColor = NSColor.black.cgColor
        minuteHandLayer.shadowOpacity = 0.55
        minuteHandLayer.shadowOffset = CGSize(width: 1.2, height: -1.8)
        minuteHandLayer.shadowRadius = 2.5
        canvasBackground.addSublayer(minuteHandLayer)

        gmtHandLayer.fillColor = CokeGMTPalette.gmtHandGold
        gmtHandLayer.strokeColor = CokeGMTPalette.goldOutline
        gmtHandLayer.lineWidth = 0.3
        gmtHandLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
        gmtHandLayer.actions = ["transform": NSNull(), "position": NSNull()]
        gmtHandLayer.shadowColor = NSColor.black.cgColor
        gmtHandLayer.shadowOpacity = 0.45
        gmtHandLayer.shadowOffset = CGSize(width: 0.8, height: -1.2)
        gmtHandLayer.shadowRadius = 1.6
        canvasBackground.addSublayer(gmtHandLayer)

        secondsPommelLayer.fillColor = CokeGMTPalette.secondHandCream
        secondsPommelLayer.strokeColor = CokeGMTPalette.goldOutline
        secondsPommelLayer.lineWidth = 0.3
        canvasBackground.addSublayer(secondsPommelLayer)

        secondsHandLayer.fillColor = CokeGMTPalette.secondHandCream
        secondsHandLayer.strokeColor = CokeGMTPalette.goldOutline
        secondsHandLayer.lineWidth = 0.25
        secondsHandLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)  // pommel-relative pivot
        secondsHandLayer.actions = ["transform": NSNull(), "position": NSNull()]
        secondsHandLayer.shadowColor = NSColor.black.cgColor
        secondsHandLayer.shadowOpacity = 0.45
        secondsHandLayer.shadowOffset = CGSize(width: 0.8, height: -1.2)
        secondsHandLayer.shadowRadius = 1.6
        canvasBackground.addSublayer(secondsHandLayer)

        // Pass-2: seconds tip lume dot — child of the seconds hand so it
        // rotates with the needle. Promoted from optional to mandatory.
        secondsTipLumeDot.fillColor = CokeGMTPalette.lumeCream
        secondsTipLumeDot.strokeColor = CokeGMTPalette.lumeCreamOutline
        secondsHandLayer.addSublayer(secondsTipLumeDot)

        centerHubLayer.fillColor = CokeGMTPalette.gmtHandGold
        centerHubLayer.strokeColor = CokeGMTPalette.goldOutline
        centerHubLayer.lineWidth = 0.4
        centerHubLayer.shadowColor = NSColor.black.cgColor
        centerHubLayer.shadowOpacity = 0.50
        centerHubLayer.shadowOffset = CGSize(width: 0.5, height: -0.6)
        centerHubLayer.shadowRadius = 1.0
        canvasBackground.addSublayer(centerHubLayer)
    }

    // MARK: Layout

    private func layoutLayers(for canvas: CGSize) {
        guard canvas.width > 0, canvas.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        canvasBackground.frame = CGRect(origin: .zero, size: canvas)

        // Pass-3: bezel widened significantly. Outer pushed to the case
        // edge (was 0.99 → 1.00); inner pulled inward (was 0.88 → 0.82)
        // for a much chunkier bezel that matches the reference's
        // sport-watch proportions. The dial shrinks to 0.78 with a thin
        // sapphire-crystal annulus from 0.78 → 0.82.
        let caseDiameter = min(canvas.width, canvas.height) * 0.85
        let caseRadius = caseDiameter / 2
        let caseCenter = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let dialRadius = caseRadius * 0.78
        let bezelInnerR = caseRadius * 0.82
        let bezelOuterR = caseRadius * 1.00

        anchors = LayoutAnchors(
            caseCenter: caseCenter,
            caseRadius: caseRadius,
            dialRadius: dialRadius,
            bezelInnerR: bezelInnerR,
            bezelOuterR: bezelOuterR
        )

        let caseRect = CGRect(
            x: caseCenter.x - caseRadius,
            y: caseCenter.y - caseRadius,
            width: caseDiameter, height: caseDiameter
        )
        let dialRect = CGRect(
            x: caseCenter.x - dialRadius,
            y: caseCenter.y - dialRadius,
            width: dialRadius * 2, height: dialRadius * 2
        )

        // Case top gradient masked to the full case disc.
        caseTopGradient.frame = CGRect(origin: .zero, size: canvas)
        caseTopMask.frame = caseTopGradient.bounds
        caseTopMask.path = CGPath(ellipseIn: caseRect, transform: nil)

        // Pass-3: the brushed-steel chamfer no longer has visible real
        // estate (the bezel now extends to the case edge, and the area
        // between the bezel inner and the dial is the sapphire crystal).
        // Hide the layer rather than removing it so the install code
        // stays simple.
        caseBrushLayer.opacity = 0.0

        // Bezel halves — Pass-2 corrected angle convention.
        // Black covers the UPPER semicircle (over the top), red covers the
        // LOWER semicircle. CA y-up: +π/2 = 12 o'clock, 0 = 3 o'clock,
        // π = 9 o'clock, -π/2 = 6 o'clock. Black goes CCW from 3 → 12 →
        // 9; red goes CW from 3 → 6 → 9. Same start/end angles, just
        // different `clockwise`.
        let blackHalfPath = bezelHalfPath(
            center: caseCenter, outerR: bezelOuterR, innerR: bezelInnerR,
            startAngle: 0, endAngle: .pi, clockwise: false
        )
        bezelBlackGradient.frame = CGRect(origin: .zero, size: canvas)
        bezelBlackHalf.frame = bezelBlackGradient.bounds
        bezelBlackHalf.path = blackHalfPath

        let redHalfPath = bezelHalfPath(
            center: caseCenter, outerR: bezelOuterR, innerR: bezelInnerR,
            startAngle: 0, endAngle: .pi, clockwise: true
        )
        bezelRedGradient.frame = CGRect(origin: .zero, size: canvas)
        bezelRedHalf.frame = bezelRedGradient.bounds
        bezelRedHalf.path = redHalfPath

        // Bezel inner groove at bezelInnerR.
        bezelInnerGroove.frame = CGRect(origin: .zero, size: canvas)
        bezelInnerGroove.path = CGPath(ellipseIn: CGRect(
            x: caseCenter.x - bezelInnerR, y: caseCenter.y - bezelInnerR,
            width: bezelInnerR * 2, height: bezelInnerR * 2
        ), transform: nil)
        bezelInnerGroove.lineWidth = max(0.4, caseRadius * 0.003)

        // Pass-3: knurling — 120 small radial teeth around the outer
        // bezel edge. Inner radius caseRadius * 0.985, outer 1.00.
        // Drawn as short lines with butt cap so each tooth reads as a
        // discrete grip serration.
        let knurlingPath = CGMutablePath()
        let teethCount = 120
        let knurlInner = caseRadius * 0.985
        let knurlOuter = caseRadius * 1.000
        for i in 0..<teethCount {
            let angle = CGFloat(i) / CGFloat(teethCount) * 2 * .pi
            let dx = cos(angle), dy = sin(angle)
            knurlingPath.move(to: CGPoint(x: caseCenter.x + dx * knurlInner,
                                          y: caseCenter.y + dy * knurlInner))
            knurlingPath.addLine(to: CGPoint(x: caseCenter.x + dx * knurlOuter,
                                             y: caseCenter.y + dy * knurlOuter))
        }
        bezelKnurlingLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelKnurlingLayer.path = knurlingPath
        bezelKnurlingLayer.lineWidth = max(0.5, caseRadius * 0.005)

        // 24h tick marks at odd hours (1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23).
        let numeralR = (bezelOuterR + bezelInnerR) / 2
        let tickLength = caseRadius * 0.022
        let tickWidth = caseRadius * 0.005
        let ticksPath = CGMutablePath()
        for h in stride(from: 1, through: 23, by: 2) {
            let angle = .pi / 2 - CGFloat(h) / 24.0 * 2 * .pi
            let ux = cos(angle), uy = sin(angle)
            let px = -uy, py = ux
            let cx = caseCenter.x + ux * numeralR
            let cy = caseCenter.y + uy * numeralR
            let halfL = tickLength / 2
            let halfW = tickWidth / 2
            let p1 = CGPoint(x: cx + ux * halfL + px * halfW, y: cy + uy * halfL + py * halfW)
            let p2 = CGPoint(x: cx + ux * halfL - px * halfW, y: cy + uy * halfL - py * halfW)
            let p3 = CGPoint(x: cx - ux * halfL - px * halfW, y: cy - uy * halfL - py * halfW)
            let p4 = CGPoint(x: cx - ux * halfL + px * halfW, y: cy - uy * halfL + py * halfW)
            ticksPath.move(to: p1)
            ticksPath.addLine(to: p2)
            ticksPath.addLine(to: p3)
            ticksPath.addLine(to: p4)
            ticksPath.closeSubpath()
        }
        bezelTicksLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelTicksLayer.path = ticksPath

        // Pass-3: 24h numerals are now BIGGER (0.060 → 0.080) and
        // RADIALLY ORIENTED — each glyph rotates so its +y axis points
        // outward from the dial center. At "24" (top) the digit reads
        // upright; at "12" (bottom) it reads inverted; at "6" (right)
        // it reads sideways. Matches the Tudor reference.
        let numFont = bezelFont(size: caseRadius * 0.100)
        let numeralsPath = CGMutablePath()
        for h in stride(from: 2, through: 22, by: 2) {
            let angle = .pi / 2 - CGFloat(h) / 24.0 * 2 * .pi
            let nx = caseCenter.x + cos(angle) * numeralR
            let ny = caseCenter.y + sin(angle) * numeralR
            if let glyphs = textPath(string: "\(h)", font: numFont) {
                let bounds = glyphs.boundingBox
                // Compose: center glyph at origin → rotate to point
                // radially outward → translate to numeral position.
                let transform = CGAffineTransform.identity
                    .translatedBy(x: nx, y: ny)
                    .rotated(by: angle - .pi / 2)
                    .translatedBy(x: -bounds.midX, y: -bounds.midY)
                numeralsPath.addPath(glyphs, transform: transform)
            }
        }
        bezelNumeralsLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelNumeralsLayer.path = numeralsPath

        // Triangle pip at 24/00 (top, angle π/2). Pass-3.3: larger again.
        let pipTipR = bezelInnerR + caseRadius * 0.012
        let pipBaseR = bezelInnerR + caseRadius * 0.075
        let pipHalfW = caseRadius * 0.045
        let pipPath = CGMutablePath()
        let pipTip = CGPoint(x: caseCenter.x, y: caseCenter.y + pipTipR)
        let pipR = CGPoint(x: caseCenter.x + pipHalfW, y: caseCenter.y + pipBaseR)
        let pipL = CGPoint(x: caseCenter.x - pipHalfW, y: caseCenter.y + pipBaseR)
        pipPath.move(to: pipTip)
        pipPath.addLine(to: pipR)
        pipPath.addLine(to: pipL)
        pipPath.closeSubpath()
        bezelPipLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelPipLayer.path = pipPath
        bezelPipLayer.shadowPath = pipPath
        bezelPipLayer.lineWidth = max(0.6, caseRadius * 0.0035)

        // Pass-3: chamfer ring repurposed as a subtle dark engraved-channel
        // stroke at the dial boundary (the "where the dial meets the
        // sapphire" edge). Quiet so the crystal effect dominates.
        chamferRingLayer.frame = CGRect(origin: .zero, size: canvas)
        chamferRingLayer.path = CGPath(ellipseIn: dialRect, transform: nil)
        chamferRingLayer.lineWidth = max(0.5, caseRadius * 0.005)

        // Polished outer rim — now sits at the very edge of the case
        // (bezel goes to 1.00 in Pass-3).
        polishedRimLayer.frame = CGRect(origin: .zero, size: canvas)
        polishedRimLayer.path = CGPath(ellipseIn: CGRect(
            x: caseCenter.x - caseRadius, y: caseCenter.y - caseRadius,
            width: caseDiameter, height: caseDiameter
        ), transform: nil)
        polishedRimLayer.lineWidth = max(0.5, caseRadius * 0.006)

        // Outer rim glint — bright arc on the upper-left of the bezel edge.
        let outerGlintR = caseRadius * 0.997
        let outerGlintPath = CGMutablePath()
        outerGlintPath.addArc(
            center: caseCenter, radius: outerGlintR,
            startAngle: .pi / 3, endAngle: 2 * .pi / 3,
            clockwise: false
        )
        outerRimGlint.frame = CGRect(origin: .zero, size: canvas)
        outerRimGlint.path = outerGlintPath
        outerRimGlint.lineWidth = max(1.2, caseRadius * 0.014)

        // Pass-3: chamferGlint hidden — the crystal glass gradient is the
        // only sapphire effect now (rim highlight removed in Pass 3.3).
        chamferGlint.path = nil

        // Pass-3: sapphire crystal annulus gradient. The gradient is
        // axial (upper-left bright → lower-right transparent) and masked
        // to the annulus between dialRadius and bezelInnerR. Sells the
        // "translucent glass dome over the dial" effect.
        let crystalRect = CGRect(
            x: caseCenter.x - bezelInnerR,
            y: caseCenter.y - bezelInnerR,
            width: bezelInnerR * 2, height: bezelInnerR * 2
        )
        crystalGlassLayer.frame = crystalRect
        let crystalMask = CAShapeLayer()
        crystalMask.frame = CGRect(origin: .zero, size: crystalRect.size)
        let crystalMaskPath = CGMutablePath()
        crystalMaskPath.addEllipse(in: CGRect(
            origin: .zero, size: crystalRect.size
        ))
        let dialInsetInCrystal = (crystalRect.width - dialRadius * 2) / 2
        crystalMaskPath.addEllipse(in: CGRect(
            x: dialInsetInCrystal, y: dialInsetInCrystal,
            width: dialRadius * 2, height: dialRadius * 2
        ))
        crystalMask.path = crystalMaskPath
        crystalMask.fillRule = .evenOdd
        crystalMask.fillColor = NSColor.white.cgColor
        crystalGlassLayer.mask = crystalMask

        // Inner edge stroke at dialRadius — kept but subtler than Pass-2
        // (the crystal layer above provides the "edge" feel).
        innerEdgeStroke.frame = CGRect(origin: .zero, size: canvas)
        innerEdgeStroke.path = CGPath(ellipseIn: dialRect, transform: nil)
        innerEdgeStroke.lineWidth = max(0.4, caseRadius * 0.003)

        // Pass 3.2: the dial face NOW EXTENDS to bezelInnerR (not the
        // smaller dialRadius). This means the chamfer annulus where the
        // sapphire crystal lives is filled with dial-black underneath,
        // so the crystal's translucent gradient overlay reads as
        // "glass-over-dial" rather than "silver-grey ring" (which is
        // what happened when the crystal painted against the canvas
        // background). Markers/hands stay positioned via `dialRadius`
        // (0.78) so the dial composition isn't disturbed.
        let dialFaceR = bezelInnerR
        let dialFaceRect = CGRect(
            x: caseCenter.x - dialFaceR, y: caseCenter.y - dialFaceR,
            width: dialFaceR * 2, height: dialFaceR * 2
        )
        dialFaceLayer.frame = CGRect(origin: .zero, size: canvas)
        dialFaceLayer.path = CGPath(ellipseIn: dialFaceRect, transform: nil)

        // Dial vignette extends to the new dial-face size too.
        dialVignetteLayer.frame = dialFaceRect
        let vMask = CAShapeLayer()
        vMask.frame = dialVignetteLayer.bounds
        vMask.path = CGPath(ellipseIn: CGRect(origin: .zero, size: dialFaceRect.size), transform: nil)
        vMask.fillColor = NSColor.white.cgColor
        dialVignetteLayer.mask = vMask

        // Grain stays at dialRadius (the textural matte black is only
        // on the main dial area where markers live, not in the crystal
        // annulus).
        dialGrainLayer.frame = dialRect
        let gMask = CAShapeLayer()
        gMask.frame = dialGrainLayer.bounds
        gMask.path = CGPath(ellipseIn: CGRect(origin: .zero, size: dialRect.size), transform: nil)
        gMask.fillColor = NSColor.white.cgColor
        dialGrainLayer.mask = gMask

        // Minute track.
        let minorTicks = CGMutablePath()
        let majorTicks = CGMutablePath()
        let tickOuter = dialRadius * 0.95
        let minorInner = dialRadius * 0.93
        let majorInner = dialRadius * 0.90
        for i in 0..<60 {
            let angle = .pi / 2 - CGFloat(i) / 60.0 * 2 * .pi
            let isMajor = i % 5 == 0
            let inner = isMajor ? majorInner : minorInner
            let dx = cos(angle), dy = sin(angle)
            let p1 = CGPoint(x: caseCenter.x + dx * inner, y: caseCenter.y + dy * inner)
            let p2 = CGPoint(x: caseCenter.x + dx * tickOuter, y: caseCenter.y + dy * tickOuter)
            if isMajor {
                majorTicks.move(to: p1)
                majorTicks.addLine(to: p2)
            } else {
                minorTicks.move(to: p1)
                minorTicks.addLine(to: p2)
            }
        }
        minuteTrackMinorTicks.frame = CGRect(origin: .zero, size: canvas)
        minuteTrackMinorTicks.path = minorTicks
        minuteTrackMinorTicks.lineWidth = max(0.3, dialRadius * 0.005)

        minuteTrackMajorTicks.frame = CGRect(origin: .zero, size: canvas)
        minuteTrackMajorTicks.path = majorTicks
        minuteTrackMajorTicks.lineWidth = max(0.5, dialRadius * 0.010)

        // Hour markers — dots, bars, triangle.
        let dotR = dialRadius * 0.034
        let markerR = dialRadius * 0.78
        let dotsPath = CGMutablePath()
        let dotHours = [1, 2, 4, 5, 7, 8, 10, 11]
        for h in dotHours {
            let angle = .pi / 2 - CGFloat(h) / 12.0 * 2 * .pi
            let mx = caseCenter.x + cos(angle) * markerR
            let my = caseCenter.y + sin(angle) * markerR
            dotsPath.addEllipse(in: CGRect(
                x: mx - dotR, y: my - dotR, width: dotR * 2, height: dotR * 2
            ))
        }
        markerDotsLayer.frame = CGRect(origin: .zero, size: canvas)
        markerDotsLayer.path = dotsPath
        markerDotsLayer.shadowPath = dotsPath
        markerDotsLayer.lineWidth = max(0.5, dialRadius * 0.003)

        // Bars at 6 and 9 — rounded rectangles radially aligned.
        // Pass-2: width 0.045 → 0.055 for more presence against the dots.
        let barOuterR = dialRadius * 0.86
        let barInnerR = dialRadius * 0.66
        let barWidth = dialRadius * 0.055
        let barsPath = CGMutablePath()
        for h in [6, 9] {
            let angle = .pi / 2 - CGFloat(h) / 12.0 * 2 * .pi
            let ux = cos(angle), uy = sin(angle)
            let px = -uy, py = ux
            let inner = CGPoint(
                x: caseCenter.x + ux * barInnerR, y: caseCenter.y + uy * barInnerR
            )
            let outer = CGPoint(
                x: caseCenter.x + ux * barOuterR, y: caseCenter.y + uy * barOuterR
            )
            let halfW = barWidth / 2
            // Bar corners (clockwise from inner-right)
            let iR = CGPoint(x: inner.x + px * halfW, y: inner.y + py * halfW)
            let oR = CGPoint(x: outer.x + px * halfW, y: outer.y + py * halfW)
            let oL = CGPoint(x: outer.x - px * halfW, y: outer.y - py * halfW)
            let iL = CGPoint(x: inner.x - px * halfW, y: inner.y - py * halfW)
            barsPath.move(to: iR)
            barsPath.addLine(to: oR)
            barsPath.addLine(to: oL)
            barsPath.addLine(to: iL)
            barsPath.closeSubpath()
        }
        markerBarsLayer.frame = CGRect(origin: .zero, size: canvas)
        markerBarsLayer.path = barsPath
        markerBarsLayer.shadowPath = barsPath
        markerBarsLayer.lineWidth = max(0.5, dialRadius * 0.003)

        // Triangle at 12.
        let tri12Path = CGMutablePath()
        let tri12Tip = CGPoint(x: caseCenter.x, y: caseCenter.y + dialRadius * 0.62)
        let tri12BaseR = CGPoint(
            x: caseCenter.x + dialRadius * 0.055, y: caseCenter.y + dialRadius * 0.84
        )
        let tri12BaseL = CGPoint(
            x: caseCenter.x - dialRadius * 0.055, y: caseCenter.y + dialRadius * 0.84
        )
        tri12Path.move(to: tri12Tip)
        tri12Path.addLine(to: tri12BaseR)
        tri12Path.addLine(to: tri12BaseL)
        tri12Path.closeSubpath()
        markerTriangle12Layer.frame = CGRect(origin: .zero, size: canvas)
        markerTriangle12Layer.path = tri12Path
        markerTriangle12Layer.shadowPath = tri12Path
        markerTriangle12Layer.lineWidth = max(0.6, dialRadius * 0.004)

        // Date window at 3 o'clock.
        let dateBoxH = dialRadius * 0.12
        let dateBoxW = dateBoxH * 1.10
        let dateCenter = CGPoint(x: caseCenter.x + dialRadius * 0.70, y: caseCenter.y)
        dateBoxRect = CGRect(
            x: dateCenter.x - dateBoxW / 2,
            y: dateCenter.y - dateBoxH / 2,
            width: dateBoxW, height: dateBoxH
        )
        let frameInset = dialRadius * 0.008
        let frameRect = dateBoxRect.insetBy(dx: -frameInset, dy: -frameInset)
        let frameCornerR = dateBoxH * 0.05 + frameInset
        let framePath = CGPath(
            roundedRect: frameRect,
            cornerWidth: frameCornerR, cornerHeight: frameCornerR,
            transform: nil
        )
        dateFrameLayer.frame = CGRect(origin: .zero, size: canvas)
        dateFrameLayer.path = framePath
        dateFrameLayer.shadowPath = framePath
        dateFrameLayer.lineWidth = max(0.3, dialRadius * 0.002)

        dateBoxLayer.frame = CGRect(origin: .zero, size: canvas)
        dateBoxLayer.path = CGPath(
            roundedRect: dateBoxRect,
            cornerWidth: dateBoxH * 0.05, cornerHeight: dateBoxH * 0.05,
            transform: nil
        )

        dateBoxFont = sansBoldFont(size: dateBoxH * 0.75)
        dateDigitLayer.frame = CGRect(origin: .zero, size: canvas)
        // Initial digit — overwritten on first tick.
        updateDateDigit(day: 0)

        // Hands. Pass-3: hour hand is now a clean 4-vertex diamond
        // (no chamfering — matches the GMT hand's geometric simplicity);
        // minute hand is a SWORD style (straight tapered, no lozenge).
        let hourLength = dialRadius * 0.50
        let hourWidth = dialRadius * 0.16
        let hourPath = diamondHandPath(width: hourWidth, length: hourLength)
        let hourBounds = CGRect(x: 0, y: 0, width: hourWidth, height: hourLength)
        hourHandLayer.bounds = hourBounds
        hourHandLayer.position = caseCenter
        hourHandLayer.path = hourPath
        hourHandLayer.shadowPath = hourPath

        let minuteLength = dialRadius * 0.90
        let minuteWidth = dialRadius * 0.060   // slimmer than the chunky snowflake
        let minutePath = swordHandPath(width: minuteWidth, length: minuteLength)
        let minuteBounds = CGRect(x: 0, y: 0, width: minuteWidth, height: minuteLength)
        minuteHandLayer.bounds = minuteBounds
        minuteHandLayer.position = caseCenter
        minuteHandLayer.path = minutePath
        minuteHandLayer.shadowPath = minutePath

        let gmtLength = dialRadius * 0.94
        let gmtWidth = dialRadius * 0.028   // Pass-2: 0.022 → 0.028 (~27% wider shaft for readability)
        let gmtPath = gmtHandPath(width: gmtWidth, length: gmtLength)
        let gmtBounds = CGRect(x: 0, y: 0, width: gmtWidth, height: gmtLength)
        gmtHandLayer.bounds = gmtBounds
        gmtHandLayer.position = caseCenter
        gmtHandLayer.path = gmtPath
        gmtHandLayer.shadowPath = gmtPath

        // Seconds hand: pivot at center; layer has length on both sides
        // (tail + needle), anchorPoint at the pivot.
        let secondsFwd = dialRadius * 0.92
        let secondsTail = secondsFwd * 0.12
        let secondsTotal = secondsFwd + secondsTail
        let secondsWidth = dialRadius * 0.012
        let secondsBounds = CGRect(x: 0, y: 0, width: secondsWidth, height: secondsTotal)
        secondsHandLayer.bounds = secondsBounds
        secondsHandLayer.anchorPoint = CGPoint(x: 0.5, y: secondsTail / secondsTotal)
        secondsHandLayer.position = caseCenter
        let secondsPath = secondsNeedlePath(width: secondsWidth, forwardLength: secondsFwd, tailLength: secondsTail)
        secondsHandLayer.path = secondsPath
        secondsHandLayer.shadowPath = secondsPath

        // Pommel as a separate layer at the pivot (so it doesn't rotate
        // with the needle's transform; it sits at the pivot).
        let pommelR = dialRadius * 0.030
        let pommelPath = CGPath(
            ellipseIn: CGRect(x: 0, y: 0, width: pommelR * 2, height: pommelR * 2),
            transform: nil
        )
        secondsPommelLayer.frame = CGRect(
            x: caseCenter.x - pommelR, y: caseCenter.y - pommelR,
            width: pommelR * 2, height: pommelR * 2
        )
        secondsPommelLayer.path = pommelPath

        // Pass-2: seconds tip lume dot — positioned in seconds-hand-local
        // coords at 78% along the forward needle (measured from pivot).
        let secondsDotR = dialRadius * 0.014
        let dotCenterYLocal = secondsTail + secondsFwd * 0.78
        secondsTipLumeDot.frame = CGRect(
            x: secondsBounds.midX - secondsDotR,
            y: dotCenterYLocal - secondsDotR,
            width: secondsDotR * 2, height: secondsDotR * 2
        )
        secondsTipLumeDot.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: secondsTipLumeDot.bounds.size),
            transform: nil
        )
        secondsTipLumeDot.lineWidth = max(0.3, dialRadius * 0.002)

        // Center hub.
        let hubR = dialRadius * 0.030
        let hubPath = CGPath(
            ellipseIn: CGRect(x: 0, y: 0, width: hubR * 2, height: hubR * 2),
            transform: nil
        )
        centerHubLayer.frame = CGRect(
            x: caseCenter.x - hubR, y: caseCenter.y - hubR,
            width: hubR * 2, height: hubR * 2
        )
        centerHubLayer.path = hubPath
        centerHubLayer.shadowPath = hubPath

        // Pass-2: wire specular highlights once paths are set.
        applyAllSpecularHighlights()
    }

    private func updateDateDigit(day: Int) {
        guard let font = dateBoxFont else { return }
        let s = "\(max(1, min(31, day)))"
        guard let glyphs = textPath(string: s, font: font) else { return }
        let bounds = glyphs.boundingBox
        let tx = dateBoxRect.midX - bounds.midX
        let ty = dateBoxRect.midY - bounds.midY
        var transform = CGAffineTransform(translationX: tx, y: ty)
        if let p = glyphs.copy(using: &transform) {
            dateDigitLayer.path = p
            dateDigitLayer.shadowPath = p
        }
    }

    // MARK: - Hand path constructors

    /// Snowflake hour/minute hand path — 16 vertices per design spec.
    /// `isMinute = true` uses the elongated/slimmer proportions.
    /// Pass-2: lozenge moved outward (hour 0.60-0.90, minute 0.74-0.93),
    /// tip cap shortened to 7%/5% of length.
    private func snowflakeHandPath(width: CGFloat, length: CGFloat, isMinute: Bool) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let shaftWidth: CGFloat = isMinute ? width * 0.14 : width * 0.18
        let lozengeStartY: CGFloat = isMinute ? length * 0.74 : length * 0.60
        let lozengeEndY: CGFloat = isMinute ? length * 0.93 : length * 0.90
        let lozengeHalfWidth = width * 0.50
        let lozengeChamfer = width * 0.10
        let tipBaseY: CGFloat = isMinute ? length * 0.95 : length * 0.93
        let tipBaseHalfWidth: CGFloat = isMinute ? width * 0.16 : width * 0.18
        let tipY = length

        path.move(to: CGPoint(x: cx + shaftWidth / 2, y: 0))                                              // 1
        path.addLine(to: CGPoint(x: cx + shaftWidth / 2, y: lozengeStartY))                               // 2
        path.addLine(to: CGPoint(x: cx + lozengeHalfWidth - lozengeChamfer, y: lozengeStartY))            // 3
        path.addLine(to: CGPoint(x: cx + lozengeHalfWidth, y: lozengeStartY + lozengeChamfer))            // 4
        path.addLine(to: CGPoint(x: cx + lozengeHalfWidth, y: lozengeEndY - lozengeChamfer))              // 5
        path.addLine(to: CGPoint(x: cx + lozengeHalfWidth - lozengeChamfer, y: lozengeEndY))              // 6
        path.addLine(to: CGPoint(x: cx + tipBaseHalfWidth, y: tipBaseY))                                  // 7
        path.addLine(to: CGPoint(x: cx, y: tipY))                                                          // 8
        path.addLine(to: CGPoint(x: cx - tipBaseHalfWidth, y: tipBaseY))                                  // 9
        path.addLine(to: CGPoint(x: cx - lozengeHalfWidth + lozengeChamfer, y: lozengeEndY))              // 10
        path.addLine(to: CGPoint(x: cx - lozengeHalfWidth, y: lozengeEndY - lozengeChamfer))              // 11
        path.addLine(to: CGPoint(x: cx - lozengeHalfWidth, y: lozengeStartY + lozengeChamfer))            // 12
        path.addLine(to: CGPoint(x: cx - lozengeHalfWidth + lozengeChamfer, y: lozengeStartY))            // 13
        path.addLine(to: CGPoint(x: cx - shaftWidth / 2, y: lozengeStartY))                               // 14
        path.addLine(to: CGPoint(x: cx - shaftWidth / 2, y: 0))                                            // 15
        path.closeSubpath()
        return path
    }

    /// Pass-3.1: 90°-cornered diamond hour hand — a square rotated 45°
    /// at the tip of a slim shaft. For 90° corners the diamond's
    /// vertical half-span MUST equal its horizontal half-span (proof:
    /// dot product of the two sides meeting at any vertex is zero
    /// iff the half-widths are equal). The lozenge is therefore a
    /// `width × width` rhombus oriented point-up.
    private func diamondHandPath(width: CGFloat, length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let shaftWidth = width * 0.20
        let diamondHalfWidth = width * 0.50
        // Square-turned-45°: half-height equals half-width.
        let diamondHalfHeight = diamondHalfWidth
        let tipY = length
        let diamondMidY = tipY - diamondHalfHeight
        let diamondStartY = diamondMidY - diamondHalfHeight

        // CCW from pivot right.
        path.move(to: CGPoint(x: cx + shaftWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: cx + shaftWidth / 2, y: diamondStartY))
        path.addLine(to: CGPoint(x: cx + diamondHalfWidth, y: diamondMidY))
        path.addLine(to: CGPoint(x: cx, y: tipY))
        path.addLine(to: CGPoint(x: cx - diamondHalfWidth, y: diamondMidY))
        path.addLine(to: CGPoint(x: cx - shaftWidth / 2, y: diamondStartY))
        path.addLine(to: CGPoint(x: cx - shaftWidth / 2, y: 0))
        path.closeSubpath()
        return path
    }

    /// Pass-3: sword minute hand. Straight parallel-sided shaft tapering
    /// to a sharp point at the tip. No lozenge. Tudor minute hands on
    /// many Black Bay variants are sword-style; the snowflake belongs
    /// to the hour hand only.
    private func swordHandPath(width: CGFloat, length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let half = width / 2
        let taperStartY = length * 0.82
        let tipY = length

        // CCW from pivot right.
        path.move(to: CGPoint(x: cx + half, y: 0))
        path.addLine(to: CGPoint(x: cx + half, y: taperStartY))
        path.addLine(to: CGPoint(x: cx, y: tipY))
        path.addLine(to: CGPoint(x: cx - half, y: taperStartY))
        path.addLine(to: CGPoint(x: cx - half, y: 0))
        path.closeSubpath()
        return path
    }

    /// GMT hand path — shaft + plain triangle arrowhead (v1; chevron-notch
    /// refinement deferred per spec).
    /// Pass-2: arrowhead multiplier 2.4 → 3.0 for readability against the
    /// busy dial. Width parameter is also wider (0.022 → 0.028 at call site).
    private func gmtHandPath(width: CGFloat, length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let arrowBaseY = length * 0.84
        let arrowMidY = length * 0.92
        let arrowHalfWidth = width * 3.0
        let tipY = length

        path.move(to: CGPoint(x: cx + width / 2, y: 0))
        path.addLine(to: CGPoint(x: cx + width / 2, y: arrowBaseY))
        path.addLine(to: CGPoint(x: cx + arrowHalfWidth, y: arrowMidY))
        path.addLine(to: CGPoint(x: cx, y: tipY))
        path.addLine(to: CGPoint(x: cx - arrowHalfWidth, y: arrowMidY))
        path.addLine(to: CGPoint(x: cx - width / 2, y: arrowBaseY))
        path.addLine(to: CGPoint(x: cx - width / 2, y: 0))
        path.closeSubpath()
        return path
    }

    /// Seconds hand needle path with tail. Anchor at pivot in the MIDDLE of
    /// the layer (pommel side has negative y, needle side has positive y).
    /// In layer bounds the path runs from y=0 (tail tip) to y=total (needle tip).
    private func secondsNeedlePath(width: CGFloat, forwardLength: CGFloat, tailLength: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let total = forwardLength + tailLength
        let tipY = total
        // Tail (lower portion)
        path.move(to: CGPoint(x: cx - width * 0.30, y: 0))
        path.addLine(to: CGPoint(x: cx + width * 0.30, y: 0))
        path.addLine(to: CGPoint(x: cx + width * 0.30, y: tailLength))
        // Needle shaft (upper portion)
        path.addLine(to: CGPoint(x: cx + width / 2, y: tailLength))
        path.addLine(to: CGPoint(x: cx + width / 2, y: tipY * 0.95))
        path.addLine(to: CGPoint(x: cx + width * 0.15, y: tipY * 0.99))
        path.addLine(to: CGPoint(x: cx, y: tipY))
        path.addLine(to: CGPoint(x: cx - width * 0.15, y: tipY * 0.99))
        path.addLine(to: CGPoint(x: cx - width / 2, y: tipY * 0.95))
        path.addLine(to: CGPoint(x: cx - width / 2, y: tailLength))
        path.addLine(to: CGPoint(x: cx - width * 0.30, y: tailLength))
        path.closeSubpath()
        return path
    }

    // MARK: - Geometry helpers

    /// Builds an annular half-ring path: outer arc CCW from startAngle to
    /// endAngle, line inward, inner arc CW back, line outward, close.
    private func bezelHalfPath(
        center: CGPoint,
        outerR: CGFloat,
        innerR: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        clockwise: Bool
    ) -> CGPath {
        let path = CGMutablePath()
        let startOuter = CGPoint(
            x: center.x + cos(startAngle) * outerR,
            y: center.y + sin(startAngle) * outerR
        )
        path.move(to: startOuter)
        path.addArc(center: center, radius: outerR,
                    startAngle: startAngle, endAngle: endAngle,
                    clockwise: clockwise)
        let endInner = CGPoint(
            x: center.x + cos(endAngle) * innerR,
            y: center.y + sin(endAngle) * innerR
        )
        path.addLine(to: endInner)
        path.addArc(center: center, radius: innerR,
                    startAngle: endAngle, endAngle: startAngle,
                    clockwise: !clockwise)
        path.closeSubpath()
        return path
    }

    // MARK: - Specular highlights (Pass-2 — REQUIRED per spec Elements 19, 20)

    /// Adds (or refreshes) a `CAGradientLayer` providing a diagonal gold
    /// specular sweep across the host element. Carry-over of the helper
    /// pattern from Asymmetric Moonphase's renderer. Idempotent — removes
    /// any prior specular sublayer before re-adding so it survives
    /// repeated `layoutLayers` calls.
    ///
    /// `useLocalPath: true` for layers whose path is in layer-local coords
    /// (rotating hands, hub layers with offset frames). `false` for layers
    /// whose path is in canvas coords (markers, date frame).
    private func applyGoldSpecular(to host: CAShapeLayer, useLocalPath: Bool) {
        applySpecularHighlight(
            to: host,
            useLocalPath: useLocalPath,
            stops: [
                CokeGMTPalette.goldSpecularHi,
                CokeGMTPalette.goldSpecularMid,
                NSColor(white: 1.0, alpha: 0.0).cgColor,
                CokeGMTPalette.goldSpecularLo,
            ],
            locations: [0.00, 0.30, 0.55, 1.00]
        )
    }

    /// Cream-lume specular variant — softer/less saturated than gold.
    private func applyLumeSpecular(to host: CAShapeLayer, useLocalPath: Bool) {
        applySpecularHighlight(
            to: host,
            useLocalPath: useLocalPath,
            stops: [
                CokeGMTPalette.lumeSpecularHi,
                CokeGMTPalette.lumeSpecularMid,
                NSColor(white: 1.0, alpha: 0.0).cgColor,
                CokeGMTPalette.lumeSpecularLo,
            ],
            locations: [0.00, 0.40, 0.65, 1.00]
        )
    }

    private func applySpecularHighlight(
        to host: CAShapeLayer,
        useLocalPath: Bool,
        stops: [CGColor],
        locations: [NSNumber]
    ) {
        host.sublayers?.removeAll(where: { $0.name == "cokeGMT.specular" })
        guard let basePath = host.path else { return }
        let bounds = basePath.boundingBox
        let gradient = CAGradientLayer()
        gradient.name = "cokeGMT.specular"
        gradient.frame = useLocalPath ? host.bounds : bounds
        gradient.type = .axial
        gradient.startPoint = CGPoint(x: 0.0, y: 1.0)
        gradient.endPoint = CGPoint(x: 1.0, y: 0.0)
        gradient.colors = stops
        gradient.locations = locations
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: gradient.bounds.size)
        mask.fillColor = NSColor.white.cgColor
        if useLocalPath {
            mask.path = basePath
        } else {
            var t = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            mask.path = basePath.copy(using: &t)
        }
        gradient.mask = mask
        host.addSublayer(gradient)
    }

    /// Apply specular gradients to every required element per Pass-2 spec.
    /// Called at the end of `layoutLayers` so every host has its path set.
    private func applyAllSpecularHighlights() {
        // Lume family — softer cream highlight (Element 20).
        applyLumeSpecular(to: hourHandLayer, useLocalPath: true)
        applyLumeSpecular(to: minuteHandLayer, useLocalPath: true)
        applyLumeSpecular(to: markerDotsLayer, useLocalPath: false)
        applyLumeSpecular(to: markerBarsLayer, useLocalPath: false)
        applyLumeSpecular(to: markerTriangle12Layer, useLocalPath: false)
        applyLumeSpecular(to: bezelPipLayer, useLocalPath: false)
        // Gold family — saturated yellow-gold highlight (Element 19).
        applyGoldSpecular(to: gmtHandLayer, useLocalPath: true)
        applyGoldSpecular(to: secondsHandLayer, useLocalPath: true)
        applyGoldSpecular(to: centerHubLayer, useLocalPath: true)
        applyGoldSpecular(to: dateFrameLayer, useLocalPath: false)
    }

    // MARK: - Procedural textures

    private func makeDialGrainImage() -> CGImage? {
        return makeStippleImage(size: 512, dotCount: 4000, dotSize: CGSize(width: 1, height: 1))
    }

    private func makeBrushedSteelImage() -> CGImage? {
        return makeStippleImage(size: 256, dotCount: 2000, dotSize: CGSize(width: 6, height: 1))
    }

    private func makeStippleImage(size: Int, dotCount: Int, dotSize: CGSize) -> CGImage? {
        let bytesPerRow = size * 4
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        for _ in 0..<dotCount {
            let x = Int(arc4random_uniform(UInt32(size)))
            let y = Int(arc4random_uniform(UInt32(size)))
            let gray = CGFloat(arc4random_uniform(255)) / 255.0
            ctx.setFillColor(gray: gray, alpha: 1.0)
            ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: dotSize.width, height: dotSize.height))
        }
        return ctx.makeImage()
    }

    // MARK: - Fonts + text

    private func bezelFont(size: CGFloat) -> NSFont {
        let candidates = ["HelveticaNeue-CondensedBold", "HelveticaNeue-Bold"]
        for name in candidates {
            if let f = NSFont(name: name, size: size) { return f }
        }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    private func sansBoldFont(size: CGFloat) -> NSFont {
        if let f = NSFont(name: "HelveticaNeue-Bold", size: size) { return f }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    private func textPath(string: String, font: NSFont) -> CGPath? {
        guard !string.isEmpty else { return nil }
        let attr = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
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
}
