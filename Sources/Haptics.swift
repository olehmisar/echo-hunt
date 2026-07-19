import AppKit

/// Discrete taps are the only thing the trackpad can actually do — there is no
/// continuous vibration mode. Everything expressive in this game comes from
/// *rhythm* (how fast taps repeat) and *timing* (how long after a ping the
/// echo lands), not from amplitude.
enum Tap {
    /// Faint tick — used for distant sonar returns.
    case weak
    /// Solid thump — used for close returns, echoes, and confirmations.
    case strong

    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .weak: return .alignment
        case .strong: return .levelChange
        }
    }
}

enum Haptics {
    static func tap(_ tap: Tap = .strong) {
        NSHapticFeedbackManager.defaultPerformer.perform(
            tap.pattern, performanceTime: .now)
    }

    /// A burst of taps `interval` apart, read as a single texture.
    static func burst(count: Int, interval: TimeInterval, tap style: Tap = .strong) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                tap(style)
            }
        }
    }

    /// A named haptic phrase, so meaning-carrying feedback reads the same
    /// everywhere and can be tuned in one place.
    static func play(_ cue: Cue) {
        switch cue {
        case .plant:
            // A deliberate, weighty double-thunk — this press commits a target.
            tap(.strong)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) { tap(.strong) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { tap(.strong) }
        case .found:
            // A quick rising flurry: you got it.
            burst(count: 6, interval: 0.05, tap: .strong)
        case .win:
            // Celebratory, spaced so it reads as an arrival, not a stutter.
            for delay in [0.0, 0.09, 0.20, 0.36] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { tap(.strong) }
            }
        case .lose:
            // Three heavy, slowing thuds — a sink, not a celebration. This is
            // the "they beat you to it" jolt, distinct from your own miss.
            for delay in [0.0, 0.16, 0.40] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { tap(.strong) }
            }
        case .countdown:
            tap(.weak)
        case .go:
            tap(.strong)
        }
    }

    enum Cue {
        case plant       // target buried
        case found       // you dug the target
        case win         // you took the round
        case lose        // the opponent took it
        case countdown   // one lead-in second elapsed
        case go          // lead-in over, seek is live
    }
}
