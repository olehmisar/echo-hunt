import Foundation

/// Player-facing options, persisted across launches.
///
/// In a duel the *host's* choice governs the match — it's sent over on connect
/// so both machines agree — but this is where the host reads its own preference
/// and where solo always reads from.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let movingTarget = "movingTarget"
    }

    /// Whether the target drifts during a round. On by default — it's the
    /// livelier game — but a checkbox turns it off for the classic still hunt.
    var movingTarget: Bool {
        didSet { defaults.set(movingTarget, forKey: Key.movingTarget) }
    }

    private init() {
        // Absent key → default on. `object(forKey:)` distinguishes "unset" from
        // "set to false", which `bool(forKey:)` cannot.
        if defaults.object(forKey: Key.movingTarget) == nil {
            movingTarget = true
        } else {
            movingTarget = defaults.bool(forKey: Key.movingTarget)
        }
    }
}
