import Foundation

/// The region a target may be buried in: a rounded rectangle inset from the
/// edges of the pad.
///
/// Two reasons for the shape. Edges and corners are awkward to search — your
/// finger runs out of trackpad before it runs out of sonar — so unrestricted
/// planting rewards hiding somewhere that's tedious rather than clever. And
/// rounding the corners removes the four spots everyone would otherwise pick.
enum PlantingArea {
    /// Inset from each edge, in normalized units.
    static let padding = 0.042

    /// Corner radius along x. The y radius is scaled by the arena's aspect so
    /// the corners read as circular on screen rather than as ellipses.
    static let cornerRadiusX = 0.10
    static let aspect = 1.6

    static var cornerRadiusY: Double { min(cornerRadiusX * aspect, 0.5 - padding) }

    static var minX: Double { padding }
    static var maxX: Double { 1 - padding }
    static var minY: Double { padding }
    static var maxY: Double { 1 - padding }

    /// Standard rounded-rectangle containment: inside the cross, or within the
    /// corner ellipse.
    static func contains(_ point: Point) -> Bool {
        guard point.x >= minX, point.x <= maxX, point.y >= minY, point.y <= maxY else {
            return false
        }

        let rx = cornerRadiusX
        let ry = cornerRadiusY

        // Which corner, if any, is this point in the box of?
        let overhangX: Double
        if point.x < minX + rx {
            overhangX = (minX + rx) - point.x
        } else if point.x > maxX - rx {
            overhangX = point.x - (maxX - rx)
        } else {
            return true          // in the vertical bar of the cross
        }

        let overhangY: Double
        if point.y < minY + ry {
            overhangY = (minY + ry) - point.y
        } else if point.y > maxY - ry {
            overhangY = point.y - (maxY - ry)
        } else {
            return true          // in the horizontal bar of the cross
        }

        // Corner: inside the quarter ellipse?
        let nx = overhangX / rx
        let ny = overhangY / ry
        return nx * nx + ny * ny <= 1
    }

    /// A uniformly random valid spot — rejection sampling, since the region is
    /// most of the rectangle and this converges immediately.
    static func randomPoint() -> Point {
        while true {
            let candidate = Point(
                x: .random(in: minX...maxX),
                y: .random(in: minY...maxY))
            if contains(candidate) { return candidate }
        }
    }
}
