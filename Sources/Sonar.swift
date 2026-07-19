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

    /// Two-finger ping: the echo returns after a delay proportional to distance.
    static func echoDelay(distance: Double) -> TimeInterval {
        0.12 + distance * 1.5
    }
}
