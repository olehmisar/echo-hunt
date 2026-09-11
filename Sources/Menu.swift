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
    case cycleLanguage
}

extension Screen {
    /// ECHO HUNT is the wordmark and stays; everything else is localized.
    var title: String {
        switch self {
        case .main: return "ECHO HUNT"
        case .help: return Loc.t("HOW TO PLAY")
        case .pause: return Loc.t("PAUSED")
        case .over: return Loc.t("TIME")
        case .duel: return Loc.t("TWO PLAYERS")
        case .duelPause: return Loc.t("PAUSED")
        case .settings: return Loc.t("SETTINGS")
        }
    }

    var items: [MenuItem] {
        switch self {
        case .main:
            return [
                MenuItem(title: Loc.t("Solo"), action: .play),
                MenuItem(title: Loc.t("Two Players"), action: .duel),
                MenuItem(title: Loc.t("Settings"), action: .settings),
                MenuItem(title: Loc.t("How to Play"), action: .help),
                // The selector shows the current language as flag + name, and
                // cycles on activation.
                MenuItem(title: Settings.shared.language.label, action: .cycleLanguage),
                MenuItem(title: Loc.t("Quit"), action: .quit),
            ]
        case .help:
            return [MenuItem(title: Loc.t("Back"), action: .back)]
        case .settings:
            // Titles reflect live state, so the rows read as controls.
            let on = Settings.shared.movingTarget
            return [
                MenuItem(title: "\(Loc.t("Moving Target")):  \(Loc.t(on ? "ON" : "OFF"))",
                         action: .toggleMovingTarget),
                MenuItem(title: Loc.t("Back"), action: .back),
            ]
        case .duel:
            return [
                MenuItem(title: Loc.t("Host Online"), action: .hostOnline),
                MenuItem(title: Loc.t("Join Online"), action: .joinOnline),
                MenuItem(title: Loc.t("Host on Local Wi-Fi"), action: .hostGame),
                MenuItem(title: Loc.t("Join on Local Wi-Fi"), action: .joinGame),
                MenuItem(title: Loc.t("Back"), action: .back),
            ]
        case .duelPause:
            return [
                MenuItem(title: Loc.t("Resume"), action: .resume),
                MenuItem(title: Loc.t("Restart Match"), action: .restartMatch),
                MenuItem(title: Loc.t("Leave Match"), action: .leaveMatch),
            ]
        // Quit lives only on the main menu — leaving the game shouldn't be one
        // stray keystroke away mid-round.
        case .pause:
            return [
                MenuItem(title: Loc.t("Resume"), action: .resume),
                MenuItem(title: Loc.t("Restart"), action: .restart),
                MenuItem(title: Loc.t("Main Menu"), action: .mainMenu),
            ]
        case .over:
            return [
                MenuItem(title: Loc.t("Play Again"), action: .restart),
                MenuItem(title: Loc.t("Main Menu"), action: .mainMenu),
            ]
        }
    }

    /// Lines shown above the items.
    var blurb: [String] {
        let keys: [String]
        switch self {
        case .main:
            keys = [
                "Something is hidden on your trackpad.",
                "The screen will never show you where.",
                "Find it by feel.",
            ]
        case .help:
            keys = [
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
            keys = [
                "Each of you hides a target on your own trackpad.",
                "Then you both race to find the other's — but the",
                "targets drift, so a dig must be timed, not just aimed.",
                "Two digs a round. Press J once a match to jam their sonar.",
                "",
                "Online plays anywhere. Local Wi-Fi needs no internet,",
                "but both Macs must be on the same network.",
            ]
        case .settings:
            keys = [
                "When on, the target drifts during a round, so a dig",
                "has to be timed rather than just aimed.",
                "",
                "In a two-player match the host's choice is used for both.",
            ]
        case .pause, .over, .duelPause:
            keys = []
        }
        // Blank lines stay blank; everything else is translated.
        return keys.map { $0.isEmpty ? $0 : Loc.t($0) }
    }
}
