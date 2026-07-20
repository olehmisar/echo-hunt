import AppKit

/// Normalized trackpad coordinates, origin bottom-left, 0...1 on both axes.
struct Point {
    var x: Double
    var y: Double

    func distance(to other: Point) -> Double {
        let dx = x - other.x, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func random(inset: Double) -> Point {
        Point(
            x: .random(in: inset...(1 - inset)),
            y: .random(in: inset...(1 - inset)))
    }
}

struct Contact {
    /// How close you must be, and then dig, to claim it.
    static let digRadius = 0.06
    /// Decoys announce themselves inside this radius.
    static let decoyRadius = 0.10
}

enum Phase {
    case idle
    case hunting
    case reveal
    case over
}

enum DigResult {
    case found(points: Int)
    /// Wrong spot — costs points, but the hunt continues.
    case miss
    case decoy
}

final class Game {
    private(set) var phase: Phase = .idle
    /// The target's current position — which may drift during a round.
    private(set) var target = Point(x: 0.5, y: 0.5)
    /// Where the target was placed. The drift path is anchored here, and it's
    /// what the reveal trajectory starts from.
    private(set) var targetCenter = Point(x: 0.5, y: 0.5)
    private(set) var decoys: [Point] = []
    private(set) var score = 0
    private(set) var round = 0

    /// Wrong digs so far this round: each one costs points and is drawn on the
    /// arena, so a miss is still information you paid for.
    private(set) var misses: [Point] = []
    private(set) var roundPenalty = 0

    /// Revealed only after a round is won — during play the arena is blank.
    private(set) var lastDig: Point?
    private(set) var lastResult: String = ""

    static let roundCount = 5
    static let missCost = 25
    static let decoyCost = 40
    /// However badly a round goes, finding the target is still worth something.
    static let minimumRoundScore = 20

    func start() {
        score = 0
        round = 0
        nextRound()
    }

    func nextRound() {
        guard round < Self.roundCount else {
            phase = .over
            return
        }
        round += 1
        target = .random(inset: 0.12)
        targetCenter = target
        // Decoys sit far enough from the target that their signature can't be
        // mistaken for the real thing.
        decoys = []
        while decoys.count < min(round - 1, 3) {
            let candidate = Point.random(inset: 0.12)
            if candidate.distance(to: target) > 0.3 { decoys.append(candidate) }
        }
        lastDig = nil
        misses = []
        roundPenalty = 0
        phase = .hunting
    }

    /// A round ends only when you find the target. Wrong digs subtract from
    /// what the round is finally worth, which is what keeps the hunt honest
    /// now that there's no clock.
    @discardableResult
    func dig(at point: Point) -> DigResult? {
        guard phase == .hunting else { return nil }
        let distance = point.distance(to: target)

        if distance <= Contact.digRadius {
            lastDig = point
            let precision = 1 - (distance / Contact.digRadius)
            let base = 100 + Int(precision * 100)
            let points = max(Self.minimumRoundScore, base - roundPenalty)
            score += points
            lastResult = roundPenalty > 0
                ? "FOUND  +\(points)   (−\(roundPenalty) wasted)"
                : "FOUND  +\(points)"
            phase = .reveal
            return .found(points: points)
        }

        misses.append(point)
        if decoys.contains(where: { point.distance(to: $0) <= Contact.decoyRadius }) {
            roundPenalty += Self.decoyCost
            return .decoy
        }
        roundPenalty += Self.missCost
        return .miss
    }

    /// Drive the target to a drifted position. Only while hunting, so a found
    /// target stays put for the reveal.
    func moveTarget(to point: Point) {
        guard phase == .hunting else { return }
        target = point
    }

    /// Nearest decoy to a probe point, if one is within range.
    func decoy(near point: Point) -> Point? {
        decoys
            .filter { point.distance(to: $0) <= Contact.decoyRadius }
            .min { point.distance(to: $0) < point.distance(to: $1) }
    }

    /// Sonar repeat interval: rapid when hot, languid when cold.
    func pulseInterval(at point: Point) -> TimeInterval {
        let distance = point.distance(to: target)
        let normalized = min(distance / 0.55, 1)
        return 0.055 + 0.6 * pow(normalized, 1.35)
    }

    func pulseStrength(at point: Point) -> Tap {
        point.distance(to: target) < 0.22 ? .strong : .weak
    }

    /// Two-finger ping: the echo comes back after a delay proportional to
    /// distance. Slow to use, but far more precise than the geiger rhythm.
    func echoDelay(at point: Point) -> TimeInterval {
        0.12 + point.distance(to: target) * 1.5
    }
}
