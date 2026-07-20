import AppKit

/// Which overlay is up. `nil` means we're actually playing.
enum Screen {
    case main
    case help
    case pause
    case over
    /// Host or join.
    case duel
    /// Pause during a duel — no "restart", since a round belongs to both players.
    case duelPause
    case settings
}

struct MenuItem {
    let title: String
    let action: MenuAction
}

enum MenuAction {
    case play
    case resume
    case restart
    case mainMenu
    case help
    case back
    case quit
    case duel
    case hostGame
    case joinGame
    case hostOnline
    case joinOnline
    case restartMatch
    case leaveMatch
    case settings
    case toggleMovingTarget
}

extension Screen {
    var title: String {
        switch self {
        case .main: return "ECHO HUNT"
        case .help: return "HOW TO PLAY"
        case .pause: return "PAUSED"
        case .over: return "TIME"
        case .duel: return "TWO PLAYERS"
        case .duelPause: return "PAUSED"
        case .settings: return "SETTINGS"
        }
    }

    var items: [MenuItem] {
        switch self {
        case .main:
            return [
                MenuItem(title: "Solo", action: .play),
                MenuItem(title: "Two Players", action: .duel),
                MenuItem(title: "Settings", action: .settings),
                MenuItem(title: "How to Play", action: .help),
                MenuItem(title: "Quit", action: .quit),
            ]
        case .help:
            return [MenuItem(title: "Back", action: .back)]
        case .settings:
            // Title reflects live state, so the row reads as a checkbox.
            let on = Settings.shared.movingTarget
            return [
                MenuItem(title: "Moving Target:  \(on ? "ON" : "OFF")",
                         action: .toggleMovingTarget),
                MenuItem(title: "Back", action: .back),
            ]
        case .duel:
            return [
                MenuItem(title: "Host Online", action: .hostOnline),
                MenuItem(title: "Join Online", action: .joinOnline),
                MenuItem(title: "Host on Local Wi-Fi", action: .hostGame),
                MenuItem(title: "Join on Local Wi-Fi", action: .joinGame),
                MenuItem(title: "Back", action: .back),
            ]
        case .duelPause:
            return [
                MenuItem(title: "Resume", action: .resume),
                MenuItem(title: "Restart Match", action: .restartMatch),
                MenuItem(title: "Leave Match", action: .leaveMatch),
            ]
        // Quit lives only on the main menu — leaving the game shouldn't be one
        // stray keystroke away mid-round.
        case .pause:
            return [
                MenuItem(title: "Resume", action: .resume),
                MenuItem(title: "Restart", action: .restart),
                MenuItem(title: "Main Menu", action: .mainMenu),
            ]
        case .over:
            return [
                MenuItem(title: "Play Again", action: .restart),
                MenuItem(title: "Main Menu", action: .mainMenu),
            ]
        }
    }

    /// Lines shown above the items.
    var blurb: [String] {
        switch self {
        case .main:
            return [
                "Something is hidden on your trackpad.",
                "The screen will never show you where.",
                "Find it by feel.",
            ]
        case .help:
            return [
                "ONE FINGER      the pad ticks faster as you close in",
                "TWO FINGERS     a ping — the delay before the thump is distance",
                "STUTTER         a double-tick means a decoy",
                "",
                "FORCE CLICK     dig here          (or press space)",
                "",
                "Your finger is drawn on screen. The target never is.",
                "No clock — a round ends when you find it.",
                "Wrong digs stay on the board and cost you points.",
                "Five rounds. Decoys accumulate as you go.",
            ]
        case .duel:
            return [
                "Each of you hides a target on your own trackpad.",
                "Then you both race to find the other's — but the",
                "targets drift, so a dig must be timed, not just aimed.",
                "Two digs a round. Press J once a match to jam their sonar.",
                "",
                "Online plays anywhere. Local Wi-Fi needs no internet,",
                "but both Macs must be on the same network.",
            ]
        case .settings:
            return [
                "When on, the target drifts during a round, so a dig",
                "has to be timed rather than just aimed.",
                "",
                "In a two-player match the host's choice is used for both.",
            ]
        case .pause, .over, .duelPause:
            return []
        }
    }
}
