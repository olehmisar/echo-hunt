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
    case miss(remaining: Int)
    /// That was the last dig — this player is out for the round.
    case eliminated
}

/// A round can end without a find: if both players burn their digs, nobody
/// takes it.
enum RoundWinner: String, Codable {
    case host
    case guest
    case draw
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
    /// nil while the round is undecided *or* when it was drawn — check
    /// `lastRoundWasDraw` to tell those apart.
    private(set) var lastRoundWonByMe: Bool?
    private(set) var lastRoundWasDraw = false

    /// Digs are scarce: miss twice and you've lost the round.
    private(set) var digsUsed = 0
    /// Set when the opponent reports they've burned theirs.
    private(set) var opponentOut = false
    /// Revealed once the round is decided.
    private(set) var revealedTarget: Point?

    /// True once I've found it and am waiting on the host's ruling.
    private(set) var awaitingRuling = false

    /// One jam per whole match, not per round. Scrambles the opponent's sonar.
    private(set) var myJamUsed = false

    static let winsNeeded = 3
    static let digsPerRound = 2

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
        lastRoundWasDraw = false
        digsUsed = 0
        opponentOut = false
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

    var digsRemaining: Int { max(0, Self.digsPerRound - digsUsed) }
    /// Out of digs: still watching, but can no longer win the round.
    var isOut: Bool { digsRemaining == 0 }

    func dig(at point: Point) -> DuelDig? {
        guard canSeek, let opponentTarget, !awaitingRuling, !isOut else { return nil }
        if point.distance(to: opponentTarget) <= Sonar.digRadius {
            awaitingRuling = true
            return .found
        }
        misses.append(point)
        digsUsed += 1
        return isOut ? .eliminated : .miss(remaining: digsRemaining)
    }

    func markOpponentOut() {
        opponentOut = true
    }

    /// Both targets drift during a round; the view feeds their live positions
    /// here each frame so digging, sonar, and the reveal all read the current
    /// spot without any of them knowing about motion.
    func moveTargets(mine: Point?, theirs: Point?) {
        guard phase == .seeking else { return }
        if let mine { myTarget = mine }
        if let theirs { opponentTarget = theirs }
    }

    /// Spend the match's single jam. Returns false if already used or not in a
    /// live round.
    func useJam() -> Bool {
        guard phase == .seeking, !myJamUsed else { return false }
        myJamUsed = true
        return true
    }

    /// Host-side: does running out of digs decide the round yet? Losing your
    /// last dig hands the round to the opponent — unless they're out too, in
    /// which case nobody takes it.
    func eliminationVerdict() -> RoundWinner? {
        guard isHost, phase == .seeking else { return nil }
        switch (isOut, opponentOut) {
        case (true, true): return .draw
        case (true, false): return .guest
        case (false, true): return .host
        case (false, false): return nil
        }
    }

    // MARK: - Resolution
    //
    // Both players race in real time, so two finds can be moments apart. The
    // host is the single arbiter: whichever claim it processes first wins, and
    // it publishes the score both sides then display. Without one authority the
    // two machines could each believe they'd won.

    /// Host-side ruling. Returns the scores to broadcast.
    func hostResolve(winner: RoundWinner) -> (hostScore: Int, guestScore: Int) {
        guard isHost else { return (myScore, opponentScore) }
        switch winner {
        case .host: myScore += 1
        case .guest: opponentScore += 1
        case .draw: break          // a drawn round is worth nothing to anyone
        }
        applyOutcome(winner == .draw ? nil : winner == .host, drawn: winner == .draw)
        return (myScore, opponentScore)
    }

    /// Guest-side: adopt the host's ruling verbatim.
    ///
    /// Note it does *not* take a target. The reveal always shows the target
    /// this player was hunting, which is already held locally — the two
    /// players are hunting different points, so accepting one over the wire
    /// showed the loser their own hiding place instead of the one they missed.
    func applyRuling(winner: RoundWinner, hostScore: Int, guestScore: Int) {
        myScore = isHost ? hostScore : guestScore
        opponentScore = isHost ? guestScore : hostScore
        let iWon: Bool? = winner == .draw ? nil : ((winner == .host) == isHost)
        applyOutcome(iWon, drawn: winner == .draw)
    }

    private func applyOutcome(_ iWon: Bool?, drawn: Bool) {
        lastRoundWonByMe = iWon
        lastRoundWasDraw = drawn
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
        myJamUsed = false          // jam refreshes with a new match, not a round
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
