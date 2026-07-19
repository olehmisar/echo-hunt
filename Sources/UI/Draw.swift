import AppKit

/// Shared drawing primitives, so solo and duel screens look like one game.
enum Draw {
    enum Palette {
        static let background = NSColor(calibratedWhite: 0.07, alpha: 1)
        static let arena = NSColor(calibratedWhite: 0.12, alpha: 1)
        static let arenaEdge = NSColor(calibratedWhite: 0.22, alpha: 1)
        static let bright = NSColor(calibratedWhite: 0.96, alpha: 1)
        static let dim = NSColor(calibratedWhite: 0.55, alpha: 1)
        static let faint = NSColor(calibratedWhite: 0.35, alpha: 1)
        static let finger = NSColor(calibratedRed: 0.55, green: 0.85, blue: 1, alpha: 1)
        static let good = NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.5, alpha: 1)
        static let bad = NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 1)
        static let warn = NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.4, alpha: 1)
    }

    static func text(
        _ string: String, at point: NSPoint, size: CGFloat, color: NSColor,
        centered: Bool = false, tracking: CGFloat = 0, monospaced: Bool = true
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: monospaced
                ? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                : NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        let attributed = NSAttributedString(string: string, attributes: attributes)
        var origin = point
        if centered { origin.x -= attributed.size().width / 2 }
        attributed.draw(at: origin)
    }

    /// Maps a normalized pad coordinate into the on-screen arena.
    static func point(_ point: Point, in arena: NSRect) -> NSPoint {
        NSPoint(
            x: arena.minX + CGFloat(point.x) * arena.width,
            y: arena.minY + CGFloat(point.y) * arena.height)
    }

    /// The legal planting region, drawn in arena coordinates.
    static func plantingAreaPath(in arena: NSRect) -> NSBezierPath {
        let origin = point(Point(x: PlantingArea.minX, y: PlantingArea.minY), in: arena)
        let far = point(Point(x: PlantingArea.maxX, y: PlantingArea.maxY), in: arena)
        let rect = NSRect(
            x: origin.x, y: origin.y,
            width: far.x - origin.x, height: far.y - origin.y)
        return NSBezierPath(
            roundedRect: rect,
            xRadius: CGFloat(PlantingArea.cornerRadiusX) * arena.width,
            yRadius: CGFloat(PlantingArea.cornerRadiusY) * arena.height)
    }
}
