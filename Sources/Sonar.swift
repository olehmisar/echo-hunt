import Foundation

/// The haptic language, shared by solo and duel modes.
///
/// All positions are **normalized 0...1 on both axes**, which is what makes a
/// planted target portable between machines: trackpads differ in physical size
/// and aspect, but `NSTouch.normalizedPosition` always reports a fraction of
/// the pad. A target buried at (0.3, 0.7) sits three tenths across and seven
/// tenths up on *any* trackpad, so both players hunt the same relative spot.
enum Sonar {
    /// How close you must be, and then dig, to claim the target.
    static let digRadius = 0.06

    /// Sonar repeat interval: rapid when hot, languid when cold.
    static func pulseInterval(distance: Double) -> TimeInterval {
        let normalized = min(distance / 0.55, 1)
        return 0.055 + 0.6 * pow(normalized, 1.35)
    }

    static func strength(distance: Double) -> Tap {
        distance < 0.22 ? .strong : .weak
    }

    /// The *texture* of a single sonar return, not just its rate. Far away it's
    /// a faint tick; closing in it firms to a solid thump; and in the last
    /// stretch — right where the rate differences get too small to feel — it
    /// doubles into a distinct "you're on top of it" buzz. This gives the
    /// endgame its own sensation instead of merely a faster version of the
    /// same one.
    enum Return {
        case faint       // single weak tick
        case solid       // single strong thump
        case hot         // strong double — you're within a whisker
    }

    static func returnTexture(distance: Double) -> Return {
        if distance < 0.09 { return .hot }
        if distance < 0.22 { return .solid }
        return .faint
    }

    /// Two-finger ping: the echo returns after a delay proportional to distance.
    static func echoDelay(distance: Double) -> TimeInterval {
        0.12 + distance * 1.5
    }
}
