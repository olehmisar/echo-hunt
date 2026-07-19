import AppKit

// Renders Resources/AppIcon.icns.
//
// The mark is the game itself: a bright point on a dark pad, with sonar rings
// spreading from it. Rings thin and fade as they travel, which is exactly what
// the haptics do — fast and firm up close, faint and slow far out.
//
//   swift tools/make-icon.swift

let canvas: CGFloat = 1024

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let scale = size / canvas
    let context = NSGraphicsContext.current!.cgContext
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons sit inset inside their canvas rather than filling it.
    let inset: CGFloat = 100 * scale
    let side = (canvas - 200) * scale
    let body = NSRect(x: inset, y: inset, width: side, height: side)
    let radius = 185 * scale
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    context.saveGState()
    bodyPath.addClip()

    // Dark, slightly blue — a trackpad in a dim room.
    let backdrop = NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.14, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 1),
    ])!
    backdrop.draw(in: body, angle: -90)

    let center = NSPoint(x: body.midX, y: body.midY)

    // Sonar returns, weakening as they spread. Below 64px the faint outer
    // rings collapse into grey mush, so small sizes get a simplified mark:
    // fewer rings, carrying more contrast each.
    let rings: [(radius: CGFloat, width: CGFloat, alpha: CGFloat)] =
        size >= 128
        ? [(150, 26, 0.95), (250, 20, 0.55), (350, 15, 0.30), (445, 11, 0.15)]
        : [(170, 40, 1.0), (300, 30, 0.6)]
    for ring in rings {
        let r = ring.radius * scale
        let path = NSBezierPath(ovalIn: NSRect(
            x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        path.lineWidth = max(ring.width * scale, 0.8)
        NSColor(calibratedRed: 0.42, green: 0.78, blue: 1, alpha: ring.alpha).setStroke()
        path.stroke()
    }

    // Glow under the point, so it reads as emitting rather than just sitting.
    let glowRadius = 190 * scale
    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 0.55, green: 0.87, blue: 1, alpha: 0.42),
        NSColor(calibratedRed: 0.55, green: 0.87, blue: 1, alpha: 0),
    ])!
    glow.draw(
        fromCenter: center, radius: 0,
        toCenter: center, radius: glowRadius, options: [])

    // The target itself — proportionally larger when small, or it vanishes.
    let dot = (size >= 128 ? 62 : 90) * scale
    NSColor(calibratedRed: 0.85, green: 0.96, blue: 1, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - dot, y: center.y - dot,
        width: dot * 2, height: dot * 2)).fill()

    context.restoreGState()

    // A hairline lip keeps the icon from dissolving into a dark dock.
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    bodyPath.lineWidth = max(2 * scale, 0.5)
    bodyPath.stroke()

    return image
}

func png(_ image: NSImage, size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

// The exact set iconutil expects.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for variant in variants {
    let data = png(drawIcon(size: variant.size), size: variant.size)
    try! data.write(to: iconset.appendingPathComponent(variant.name))
}

// A standalone preview, handy for eyeballing without opening the bundle.
try! png(drawIcon(size: 512), size: 512)
    .write(to: root.appendingPathComponent("build/icon-preview.png"))

let resources = root.appendingPathComponent("Resources")
try! fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns", iconset.path,
    "-o", resources.appendingPathComponent("AppIcon.icns").path,
]
try! process.run()
process.waitUntilExit()
print(process.terminationStatus == 0
    ? "Wrote Resources/AppIcon.icns"
    : "iconutil failed (\(process.terminationStatus))")
