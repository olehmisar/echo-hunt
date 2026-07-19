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
}
