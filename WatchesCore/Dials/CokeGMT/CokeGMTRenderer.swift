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
    private let bezelCeramicSheen = CAShapeLayer()
    private let bezelInnerGroove = CAShapeLayer()
    private let bezelNumeralsLayer = CAShapeLayer()
    private let bezelTicksLayer = CAShapeLayer()
    private let bezelPipLayer = CAShapeLayer()

    // MARK: Dial layers

    private let dialFaceLayer = CAShapeLayer()
    private let dialVignetteLayer = CAGradientLayer()
    private let dialGrainLayer = CALayer()

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

        bezelCeramicSheen.fillColor = nil
        bezelCeramicSheen.strokeColor = CokeGMTPalette.ceramicSheenWhite
        bezelCeramicSheen.lineCap = .round
        canvasBackground.addSublayer(bezelCeramicSheen)

        bezelInnerGroove.fillColor = nil
        bezelInnerGroove.strokeColor = NSColor(white: 0.0, alpha: 0.60).cgColor
        canvasBackground.addSublayer(bezelInnerGroove)

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

        // Polished chamfer ring + outer bezel rim + glints.
        chamferRingLayer.fillColor = nil
        chamferRingLayer.strokeColor = CokeGMTPalette.caseSteelHighlight
        canvasBackground.addSublayer(chamferRingLayer)

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

        let caseDiameter = min(canvas.width, canvas.height) * 0.85
        let caseRadius = caseDiameter / 2
        let caseCenter = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let dialRadius = caseRadius * 0.80
        let bezelInnerR = caseRadius * 0.88
        let bezelOuterR = caseRadius * 0.99

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

        // Brushed overlay clipped to the chamfer ring (annulus between
        // dialRadius and bezelInnerR).
        caseBrushLayer.frame = caseRect
        let brushMask = CAShapeLayer()
        brushMask.frame = caseBrushLayer.bounds
        let brushPath = CGMutablePath()
        // Annulus = outer minus inner (even-odd)
        brushPath.addEllipse(in: CGRect(
            x: caseRadius - bezelInnerR + 0, y: caseRadius - bezelInnerR + 0,
            width: bezelInnerR * 2, height: bezelInnerR * 2
        ))
        brushPath.addEllipse(in: CGRect(
            x: caseRadius - dialRadius, y: caseRadius - dialRadius,
            width: dialRadius * 2, height: dialRadius * 2
        ))
        brushMask.path = brushPath
        brushMask.fillRule = .evenOdd
        brushMask.fillColor = NSColor.white.cgColor
        caseBrushLayer.mask = brushMask

        // Bezel halves — paths in canvas coords. Gradient layers cover the
        // full canvas and use the half-shapes as masks.
        let blackHalfPath = bezelHalfPath(
            center: caseCenter, outerR: bezelOuterR, innerR: bezelInnerR,
            startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false
        )
        bezelBlackGradient.frame = CGRect(origin: .zero, size: canvas)
        bezelBlackHalf.frame = bezelBlackGradient.bounds
        bezelBlackHalf.path = blackHalfPath

        let redHalfPath = bezelHalfPath(
            center: caseCenter, outerR: bezelOuterR, innerR: bezelInnerR,
            startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false
        )
        bezelRedGradient.frame = CGRect(origin: .zero, size: canvas)
        bezelRedHalf.frame = bezelRedGradient.bounds
        bezelRedHalf.path = redHalfPath

        // Ceramic sheen — broad arc highlight at top-left of bezel.
        bezelCeramicSheen.frame = CGRect(origin: .zero, size: canvas)
        let sheenPath = CGMutablePath()
        let sheenR = bezelOuterR - caseRadius * 0.005
        sheenPath.addArc(
            center: caseCenter, radius: sheenR,
            startAngle: .pi / 3, endAngle: .pi * 0.95,
            clockwise: false
        )
        bezelCeramicSheen.path = sheenPath
        bezelCeramicSheen.lineWidth = max(1.0, caseRadius * 0.014)

        // Bezel inner groove at bezelInnerR.
        bezelInnerGroove.frame = CGRect(origin: .zero, size: canvas)
        bezelInnerGroove.path = CGPath(ellipseIn: CGRect(
            x: caseCenter.x - bezelInnerR, y: caseCenter.y - bezelInnerR,
            width: bezelInnerR * 2, height: bezelInnerR * 2
        ), transform: nil)
        bezelInnerGroove.lineWidth = max(0.4, caseRadius * 0.003)

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

        // 24h numerals at even hours, upright in the wearer's frame.
        let numFont = bezelFont(size: caseRadius * 0.060)
        let numeralsPath = CGMutablePath()
        for h in stride(from: 2, through: 22, by: 2) {
            let angle = .pi / 2 - CGFloat(h) / 24.0 * 2 * .pi
            let nx = caseCenter.x + cos(angle) * numeralR
            let ny = caseCenter.y + sin(angle) * numeralR
            if let glyphs = textPath(string: "\(h)", font: numFont) {
                let bounds = glyphs.boundingBox
                let tx = nx - bounds.midX
                let ty = ny - bounds.midY
                let t = CGAffineTransform(translationX: tx, y: ty)
                numeralsPath.addPath(glyphs, transform: t)
            }
        }
        bezelNumeralsLayer.frame = CGRect(origin: .zero, size: canvas)
        bezelNumeralsLayer.path = numeralsPath

        // Triangle pip at 24/00 (top, angle π/2).
        let pipTipR = bezelInnerR + caseRadius * 0.008
        let pipBaseR = bezelInnerR + caseRadius * 0.038
        let pipHalfW = caseRadius * 0.022
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

        // Chamfer ring (radii 0.80–0.82 — drawn as stroke at 0.81).
        chamferRingLayer.frame = CGRect(origin: .zero, size: canvas)
        chamferRingLayer.path = CGPath(ellipseIn: CGRect(
            x: caseCenter.x - caseRadius * 0.81, y: caseCenter.y - caseRadius * 0.81,
            width: caseRadius * 1.62, height: caseRadius * 1.62
        ), transform: nil)
        chamferRingLayer.lineWidth = max(1.0, caseRadius * 0.015)

        // Polished outer rim.
        polishedRimLayer.frame = CGRect(origin: .zero, size: canvas)
        polishedRimLayer.path = CGPath(ellipseIn: CGRect(
            x: caseCenter.x - caseRadius * 0.995, y: caseCenter.y - caseRadius * 0.995,
            width: caseRadius * 1.99, height: caseRadius * 1.99
        ), transform: nil)
        polishedRimLayer.lineWidth = max(1.0, caseRadius * 0.012)

        // Glints — upper-left arcs (CCW from a low angle to a higher angle).
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

        let chamferGlintR = caseRadius * 0.815
        let chamferGlintPath = CGMutablePath()
        chamferGlintPath.addArc(
            center: caseCenter, radius: chamferGlintR,
            startAngle: 5 * .pi / 12, endAngle: 3 * .pi / 4,
            clockwise: false
        )
        chamferGlint.frame = CGRect(origin: .zero, size: canvas)
        chamferGlint.path = chamferGlintPath
        chamferGlint.lineWidth = max(0.8, caseRadius * 0.010)

        // Inner edge stroke at dialRadius.
        innerEdgeStroke.frame = CGRect(origin: .zero, size: canvas)
        innerEdgeStroke.path = CGPath(ellipseIn: dialRect, transform: nil)
        innerEdgeStroke.lineWidth = max(0.4, caseRadius * 0.004)

        // Dial face fill.
        dialFaceLayer.frame = CGRect(origin: .zero, size: canvas)
        dialFaceLayer.path = CGPath(ellipseIn: dialRect, transform: nil)

        // Dial vignette gradient masked to dial.
        dialVignetteLayer.frame = dialRect
        let vMask = CAShapeLayer()
        vMask.frame = dialVignetteLayer.bounds
        vMask.path = CGPath(ellipseIn: CGRect(origin: .zero, size: dialRect.size), transform: nil)
        vMask.fillColor = NSColor.white.cgColor
        dialVignetteLayer.mask = vMask

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
        let barOuterR = dialRadius * 0.86
        let barInnerR = dialRadius * 0.66
        let barWidth = dialRadius * 0.045
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

        dateBoxFont = sansBoldFont(size: dateBoxH * 0.65)
        dateDigitLayer.frame = CGRect(origin: .zero, size: canvas)
        // Initial digit — overwritten on first tick.
        updateDateDigit(day: 0)

        // Hands.
        let hourLength = dialRadius * 0.48
        let hourWidth = dialRadius * 0.16
        let hourPath = snowflakeHandPath(width: hourWidth, length: hourLength, isMinute: false)
        let hourBounds = CGRect(x: 0, y: 0, width: hourWidth, height: hourLength)
        hourHandLayer.bounds = hourBounds
        hourHandLayer.position = caseCenter
        hourHandLayer.path = hourPath
        hourHandLayer.shadowPath = hourPath

        let minuteLength = dialRadius * 0.88
        let minuteWidth = dialRadius * 0.115
        let minutePath = snowflakeHandPath(width: minuteWidth, length: minuteLength, isMinute: true)
        let minuteBounds = CGRect(x: 0, y: 0, width: minuteWidth, height: minuteLength)
        minuteHandLayer.bounds = minuteBounds
        minuteHandLayer.position = caseCenter
        minuteHandLayer.path = minutePath
        minuteHandLayer.shadowPath = minutePath

        let gmtLength = dialRadius * 0.94
        let gmtWidth = dialRadius * 0.022
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
    private func snowflakeHandPath(width: CGFloat, length: CGFloat, isMinute: Bool) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let shaftWidth: CGFloat = isMinute ? width * 0.14 : width * 0.18
        let lozengeStartY: CGFloat = isMinute ? length * 0.62 : length * 0.45
        let lozengeEndY: CGFloat = isMinute ? length * 0.86 : length * 0.85
        let lozengeHalfWidth = width * 0.50
        let lozengeChamfer = width * 0.10
        let tipBaseY: CGFloat = isMinute ? length * 0.90 : length * 0.88
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

    /// GMT hand path — shaft + plain triangle arrowhead (v1; chevron-notch
    /// refinement deferred per spec).
    private func gmtHandPath(width: CGFloat, length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let cx = width / 2
        let arrowBaseY = length * 0.84
        let arrowMidY = length * 0.92
        let arrowHalfWidth = width * 2.4
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
