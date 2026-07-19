import Foundation

/// A target that drifts. Burying it fixes a *centre*; from there it wanders on
/// a slow, smooth path, so the hunt becomes a chase and a dig has to be timed,
/// not just aimed.
///
/// The drift is a pure function of the centre, so both machines derive the same
/// path with nothing extra crossing the wire — the planted coordinates already
/// travel, and the phases fall out of them. Motion is measured from each
/// machine's own seek-start, and every find is judged locally against the
/// current position, so no clock sync is needed and latency never enters the
/// haptic loop.
struct MovingTarget {
    let center: Point
    private let phaseX: Double
    private let phaseY: Double

    /// How far it strays from the centre, in normalized pad units. Chosen so
    /// it's catchable within a two-dig budget but never sits still.
    static let amplitude = 0.075
    /// Base angular speed. Slow — a full loop takes several seconds.
    static let speed = 0.5

    init(center: Point) {
        self.center = center
        // Deterministic phases from the centre — same input, same drift, on
        // both machines, with no seed to transmit.
        let a = center.x * 127.1 + center.y * 311.7
        let b = center.x * 269.5 + center.y * 183.3
        phaseX = (a - a.rounded(.down)) * 2 * .pi
        phaseY = (b - b.rounded(.down)) * 2 * .pi
    }

    /// Where the target is `t` seconds into the hunt. Two summed sines per axis
    /// give an organic wander rather than an obvious circle. Each sine is
    /// anchored so it's zero at t=0 — the target starts exactly where it was
    /// buried and drifts away from there — and the result is clamped so the
    /// marker never leaves the pad.
    func position(at t: TimeInterval) -> Point {
        func drift(_ t: Double, _ phase: Double) -> Double {
            Self.amplitude * (
                0.7 * (sin(Self.speed * t + phase) - sin(phase))
                + 0.3 * (sin(Self.speed * 1.7 * t + phase * 2) - sin(phase * 2)))
        }
        return Point(
            x: min(max(center.x + drift(t, phaseX), 0.03), 0.97),
            y: min(max(center.y + drift(t * 0.9, phaseY), 0.03), 0.97))
    }
}
