// DialSnapshot — Story 1.5 AC17
//
// Command-line tool that renders any registered dial to a PNG. Mirrors what
// the screensaver host does (attach + tick) but writes the result to disk
// instead of presenting it onscreen. Purpose: skeuomorphic-iteration
// velocity — produce a PNG, look at it, adjust the renderer, repeat. Without
// this loop, every iteration requires rebuilding the .saver, installing into
// ~/Library/Screen Savers, killing legacyScreenSaver, and activating.
//
// Dial-agnostic by design: any dial registered in `DialRegistry` can be
// snapshotted via `--dial <id>`. Story 1.5 ships with `royale` as the
// default; Story 1.6 (`asymmetricMoonphase`) and beyond reuse this tool.

import AppKit
import QuartzCore
import Foundation
import WatchesCore

// MARK: Arguments

struct Args {
    var dialID: String = "royale"
    var outputPath: String = "snapshot.png"
    var width: Int = 1200
    var height: Int = 1200
    var scale: CGFloat = 2.0
    var iso8601: String?
}

func parseArgs() -> Args {
    var args = Args()
    let raw = CommandLine.arguments
    var i = 1
    func next() -> String? { i += 1; return i < raw.count ? raw[i] : nil }
    while i < raw.count {
        switch raw[i] {
        case "--dial",   "-d": if let v = next() { args.dialID = v }
        case "--output", "-o": if let v = next() { args.outputPath = v }
        case "--width",  "-w": if let v = next(), let n = Int(v) { args.width  = n }
        case "--height", "-h": if let v = next(), let n = Int(v) { args.height = n }
        case "--scale":        if let v = next(), let d = Double(v) { args.scale = CGFloat(d) }
        case "--date":         if let v = next() { args.iso8601 = v }
        case "--list":
            for type in DialRegistry.all {
                print("\(type.identity.id)\t\(type.identity.displayName)")
            }
            exit(0)
        case "--generate-royale-map":
            // Story 1.5.1: one-shot generator for WatchesCore/Dials/Royale/RoyaleMap.png.
            // PNG is committed once; this flag lets us regenerate later.
            let outPath = next() ?? "WatchesCore/Dials/Royale/RoyaleMap.png"
            generateRoyaleMap(outputPath: outPath)
            exit(0)
        case "--help":
            print("""
            Usage: DialSnapshot [options]
              --dial,   -d  ID    Dial ID from DialRegistry (default: royale)
              --output, -o  PATH  Output PNG path (default: snapshot.png)
              --width,  -w  N     Canvas width in points (default: 1200)
              --height, -h  N     Canvas height in points (default: 1200)
              --scale       N     Backing scale factor (default: 2.0 for retina)
              --date        ISO   Fixed render time (default: now)
              --list              List all registered dials and exit
              --generate-royale-map PATH
                                  Regenerate the bundled RoyaleMap.png (Story 1.5.1).
                                  Default path: WatchesCore/Dials/Royale/RoyaleMap.png
            """)
            exit(0)
        default: break
        }
        i += 1
    }
    return args
}

// MARK: Render

func renderSnapshot(args: Args) {
    let canvas = CGSize(width: args.width, height: args.height)
    let pxW = Int(canvas.width * args.scale)
    let pxH = Int(canvas.height * args.scale)

    // Root layer mirroring what the screensaver host installs.
    let rootLayer = CALayer()
    rootLayer.frame = CGRect(origin: .zero, size: canvas)
    rootLayer.contentsScale = args.scale
    rootLayer.backgroundColor = NSColor.black.cgColor

    // Time source: optionally pinned via --date.
    let date: Date
    if let iso = args.iso8601, let parsed = ISO8601DateFormatter().date(from: iso) {
        date = parsed
    } else {
        date = Date()
    }
    let timeSource = FixedTimeSource(now: date)

    // Look up the requested dial in the registry.
    guard let dialType = DialRegistry.byID(args.dialID) else {
        FileHandle.standardError.write(
            Data("[error] DialRegistry has no '\(args.dialID)' entry. Try --list.\n".utf8)
        )
        exit(2)
    }
    let renderer = dialType.init()

    // Same lifecycle as the host: attach + first tick.
    renderer.attach(rootLayer: rootLayer, canvas: canvas, timeSource: timeSource)
    _ = renderer.tick(reduceMotion: false)

    // Render the layer tree to an offscreen bitmap.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil, width: pxW, height: pxH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: bitmapInfo
    ) else {
        FileHandle.standardError.write(Data("[error] Failed to create CGContext\n".utf8))
        exit(3)
    }
    context.scaleBy(x: args.scale, y: args.scale)
    rootLayer.render(in: context)

    guard let cgImage = context.makeImage() else {
        FileHandle.standardError.write(Data("[error] Failed to make CGImage\n".utf8))
        exit(4)
    }

    let outputURL = URL(fileURLWithPath: args.outputPath)
    guard let dest = CGImageDestinationCreateWithURL(
        outputURL as CFURL, "public.png" as CFString, 1, nil
    ) else {
        FileHandle.standardError.write(Data("[error] Failed to open output: \(args.outputPath)\n".utf8))
        exit(5)
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write(Data("[error] Failed to write PNG\n".utf8))
        exit(6)
    }

    print("Wrote \(args.outputPath) (\(pxW)×\(pxH); dial=\(args.dialID))")

    renderer.detach()
}

// MARK: Royale map bitmap generator (Story 1.5.1)

/// Generates `RoyaleMap.png` — the dot-matrix world-map asset bundled with
/// WatchesCore.framework. Produces a 72×28 PNG with transparent background
/// and dark continent dots. Hand-tuned for higher fidelity than the
/// procedural 36×14 grid that shipped in Story 1.5.
///
/// One pixel per `#` in the string grid; `.` is transparent. Atlantic-
/// centered projection: Americas on the left, Eurasia/Africa center,
/// Indonesia + Australia right.
func generateRoyaleMap(outputPath: String) {
    // Generated by 2x replicating the 36×14 grid that shipped with Story 1.5.
    // Each char represents a single pixel. '#' = dot in mapDot color; '.' = transparent.
    let map: [String] = [
        "........................................................................",
        "........................................................................",
        "................####..............................####..................",
        "................####..............................####..................",
        "........################............############################........",
        "........################............############################........",
        "....####################........################################........",
        "....####################........################################........",
        "....##################..........################################........",
        "....##################..........################################........",
        "......################............############################..........",
        "......################............############################..........",
        "........##############..............########################............",
        "........##############..............########################............",
        "..........############................######################....####....",
        "..........############................######################....####....",
        "............##########..................####################....######..",
        "............##########..................####################....######..",
        "..............########....................##################....######..",
        "..............########....................##################....######..",
        "..............######......................##############........####....",
        "..............######......................##############........####....",
        "................####......................############..................",
        "................####......................############..................",
        "..................##........................########....................",
        "..................##........................########....................",
        "........................................................................",
        "........................................................................",
    ]

    let cols = 72
    let rows = 28
    precondition(map.count == rows, "row count must be \(rows) (got \(map.count))")
    for (i, row) in map.enumerated() {
        precondition(row.count == cols, "row \(i) must be \(cols) cols (got \(row.count))")
    }

    // Each grid cell renders at 6×6 pixels with a centered circular dot of
    // diameter 5. This preserves the round-dot character (vs. pixel squares)
    // while giving enough resolution that the dots don't blur when scaled
    // up to the display cutout. Final PNG: 432×168 pixels.
    let cellPx = 6
    let dotPx = CGFloat(cellPx) * 0.85  // diameter
    let pixelW = cols * cellPx
    let pixelH = rows * cellPx

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil, width: pixelW, height: pixelH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: bitmapInfo
    ) else {
        FileHandle.standardError.write(Data("[error] CGContext creation failed\n".utf8))
        exit(3)
    }

    // Transparent background: clear the entire context.
    ctx.clear(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

    // Dot color: matches RoyalePalette.mapDot (positive-LCD dark).
    ctx.setFillColor(red: 0.18, green: 0.19, blue: 0.17, alpha: 1.0)

    // Draw a centered circular dot per '#'. Row 0 in the array is NORTH
    // (top), but CGContext y is up (origin at bottom-left). Flip the row.
    for (rowIdx, rowStr) in map.enumerated() {
        let yCell = rows - 1 - rowIdx
        for (colIdx, char) in rowStr.enumerated() where char == "#" {
            let cx = CGFloat(colIdx * cellPx) + CGFloat(cellPx) / 2
            let cy = CGFloat(yCell * cellPx) + CGFloat(cellPx) / 2
            ctx.fillEllipse(in: CGRect(
                x: cx - dotPx / 2, y: cy - dotPx / 2,
                width: dotPx, height: dotPx
            ))
        }
    }

    guard let cgImage = ctx.makeImage() else {
        FileHandle.standardError.write(Data("[error] makeImage failed\n".utf8))
        exit(4)
    }

    let outURL = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(
        outURL as CFURL, "public.png" as CFString, 1, nil
    ) else {
        FileHandle.standardError.write(Data("[error] cannot open \(outputPath)\n".utf8))
        exit(5)
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write(Data("[error] PNG write failed\n".utf8))
        exit(6)
    }
    print("Wrote \(outputPath) (\(pixelW)×\(pixelH); grid \(cols)×\(rows), \(cellPx)px/cell)")
}

// CALayer operations need to run on the main thread; for a tool target the
// entry point is already on the main thread.
let args = parseArgs()
renderSnapshot(args: args)
