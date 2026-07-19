import Foundation

enum DuelPhase: Equatable {
    /// Choosing host or join, entering a code, waiting for a peer.
    case lobby
    /// Connected. Bury your target — you cannot seek until you have.
    case planting
    /// You've planted; the opponent hasn't yet.
    case waitingForOpponent
    /// Both planted. Race.
    case seeking
    /// Round decided, showing the reveal.
    case roundOver
    case matchOver
    case disconnected(String)
}

enum DuelDig {
    case found
    case miss
}

/// The duel rules, with no networking and no UI so they can be tested directly.
///
/// The anti-stalling rule you asked for is structural rather than policed: a
/// player receives the opponent's target only in exchange for sending their
/// own, so "seek without planting" isn't a move that exists. There is nothing
/// to seek until you've paid your target for it.
final class DuelMatch {
    private(set) var phase: DuelPhase = .lobby
    let isHost: Bool

    /// What I buried, for the opponent to find.
    private(set) var myTarget: Point?
    /// What they buried, for me to find. Absent until they've planted.
    private(set) var opponentTarget: Point?

    private(set) var myScore = 0
    private(set) var opponentScore = 0
    private(set) var round = 0

    /// Wrong digs this round — drawn, but they cost nothing except the time
    /// that lets your opponent win the race.
    private(set) var misses: [Point] = []
    private(set) var lastRoundWonByMe: Bool?
    /// Revealed once the round is decided.
    private(set) var revealedTarget: Point?

    /// True once I've found it and am waiting on the host's ruling.
    private(set) var awaitingRuling = false

    static let winsNeeded = 3

    init(isHost: Bool) {
        self.isHost = isHost
    }

    // MARK: - Round lifecycle

    func beginRound(_ number: Int) {
        round = number
        myTarget = nil
        opponentTarget = nil
        misses = []
        revealedTarget = nil
        lastRoundWonByMe = nil
        awaitingRuling = false
        phase = .planting
    }

    /// Returns false if the spot is outside the legal region.
    func plant(at point: Point) -> Bool {
        guard phase == .planting, PlantingArea.contains(point) else { return false }
        myTarget = point
        phase = opponentTarget == nil ? .waitingForOpponent : .seeking
        return true
    }

    func receiveOpponentTarget(_ point: Point) {
        opponentTarget = point
        // Only start seeking if I've held up my end.
        if myTarget != nil, phase == .waitingForOpponent || phase == .planting {
            phase = .seeking
        }
    }

    /// Guard for every haptic and every dig: no target, no sonar.
    var canSeek: Bool {
        phase == .seeking && myTarget != nil && opponentTarget != nil
    }

    // MARK: - Seeking

    func distance(from point: Point) -> Double? {
        guard canSeek, let opponentTarget else { return nil }
        return point.distance(to: opponentTarget)
    }

    func dig(at point: Point) -> DuelDig? {
        guard canSeek, let opponentTarget, !awaitingRuling else { return nil }
        if point.distance(to: opponentTarget) <= Sonar.digRadius {
            awaitingRuling = true
            return .found
        }
        misses.append(point)
        return .miss
    }

    // MARK: - Resolution
    //
    // Both players race in real time, so two finds can be moments apart. The
    // host is the single arbiter: whichever claim it processes first wins, and
    // it publishes the score both sides then display. Without one authority the
    // two machines could each believe they'd won.

    /// Host-side ruling. Returns the scores to broadcast.
    func hostResolve(winnerIsHost: Bool) -> (hostScore: Int, guestScore: Int) {
        guard isHost else { return (myScore, opponentScore) }
        if winnerIsHost { myScore += 1 } else { opponentScore += 1 }
        applyOutcome(iWon: winnerIsHost)
        return (myScore, opponentScore)
    }

    /// Guest-side: adopt the host's ruling verbatim.
    func applyRuling(winnerIsHost: Bool, hostScore: Int, guestScore: Int, target: Point) {
        myScore = isHost ? hostScore : guestScore
        opponentScore = isHost ? guestScore : hostScore
        opponentTarget = target
        applyOutcome(iWon: isHost == winnerIsHost)
    }

    private func applyOutcome(iWon: Bool) {
        lastRoundWonByMe = iWon
        revealedTarget = opponentTarget
        awaitingRuling = false
        phase = (myScore >= Self.winsNeeded || opponentScore >= Self.winsNeeded)
            ? .matchOver
            : .roundOver
    }

    /// Same opponent, same connection, scores back to nil-nil.
    func restartMatch() {
        myScore = 0
        opponentScore = 0
        round = 0
        lastRoundWonByMe = nil
        revealedTarget = nil
    }

    func disconnect(_ reason: String) {
        phase = .disconnected(reason)
    }

    func resetMatch() {
        myScore = 0
        opponentScore = 0
        round = 0
        phase = .lobby
    }
}
