import Foundation

enum Language: String, CaseIterable {
    case en
    case uk

    /// Shown in the language selector, each in its own script.
    var displayName: String {
        switch self {
        case .en: return "English"
        case .uk: return "Українська"
        }
    }

    /// Flag emoji, so the selector reads at a glance without knowing the words.
    var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .uk: return "🇺🇦"
        }
    }

    /// Flag + name, as shown on the main-menu selector.
    var label: String { "\(flag)  \(displayName)" }

    var next: Language {
        let all = Language.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Tiny translation layer. English strings are the keys, so any string not yet
/// translated simply renders in English — nothing ever comes back blank.
///
///   Loc.t("Two Players")     // "Два гравці" when Ukrainian is selected
enum Loc {
    static func t(_ english: String) -> String {
        guard Settings.shared.language == .uk else { return english }
        return uk[english] ?? english
    }

    private static let uk: [String: String] = [
        // Screen titles (ECHO HUNT is the wordmark and stays as-is).
        "HOW TO PLAY": "ЯК ГРАТИ",
        "PAUSED": "ПАУЗА",
        "TIME": "РЕЗУЛЬТАТ",
        "TWO PLAYERS": "ДВА ГРАВЦІ",
        "SETTINGS": "НАЛАШТУВАННЯ",
        "LOBBY": "ЛОБІ",
        "JOIN A GAME": "ПРИЄДНАТИСЯ",
        "DISCONNECTED": "З'ЄДНАННЯ ВТРАЧЕНО",

        // Main + navigation
        "Solo": "Одиночна гра",
        "Two Players": "Два гравці",
        "Settings": "Налаштування",
        "How to Play": "Як грати",
        "Quit": "Вихід",
        "Back": "Назад",
        "Resume": "Продовжити",
        "Restart": "Заново",
        "Restart Match": "Почати заново",
        "Leave Match": "Вийти з матчу",
        "Play Again": "Грати знову",
        "Main Menu": "Головне меню",
        "Host Online": "Створити онлайн",
        "Join Online": "Приєднатися онлайн",
        "Host on Local Wi-Fi": "Створити у Wi-Fi",
        "Join on Local Wi-Fi": "Приєднатися у Wi-Fi",

        // Settings
        "Moving Target": "Рухома ціль",
        "Language": "Мова",
        "ON": "УВІМК",
        "OFF": "ВИМК",
        "When on, the target drifts during a round, so a dig":
            "Коли увімкнено, ціль рухається під час раунду,",
        "has to be timed rather than just aimed.":
            "тож копати треба вчасно, а не лише влучно.",
        "In a two-player match the host's choice is used for both.":
            "У матчі на двох діє вибір господаря.",

        // Help / solo blurb
        "Something is hidden on your trackpad.": "На тачпаді захована ціль.",
        "The screen will never show you where.": "Екран ніколи не покаже, де вона.",
        "Find it by feel.": "Знайди її на дотик.",
        "ONE FINGER      the pad ticks faster as you close in":
            "ОДИН ПАЛЕЦЬ    стукає частіше, коли ближче",
        "TWO FINGERS     a ping — the delay before the thump is distance":
            "ДВА ПАЛЬЦІ      пінг — затримка до удару це відстань",
        "STUTTER         a double-tick means a decoy":
            "ЗАЇКАННЯ        подвійний стукіт — приманка",
        "FORCE CLICK     dig here          (or press space)":
            "СИЛЬНЕ НАТИСК. копати тут        (або пробіл)",
        "No clock — a round ends when you find it.":
            "Без часу — раунд триває, поки не знайдеш.",
        "Wrong digs stay on the board and cost you points.":
            "Промахи лишаються на полі й коштують очок.",
        "Five rounds. Decoys accumulate as you go.":
            "П'ять раундів. Приманок більшає з часом.",
        "Your finger is drawn on screen. The target never is.":
            "Твій палець видно на екрані. Ціль — ніколи.",

        // Duel blurb
        "Each of you hides a target on your own trackpad.":
            "Кожен ховає ціль на своєму тачпаді.",
        "Then you both race to find the other's — but the":
            "Далі змагаєтесь, хто перший знайде чужу —",
        "targets drift, so a dig must be timed, not just aimed.":
            "але цілі рухаються, тож копати треба вчасно.",
        "Two digs a round. Press J once a match to jam their sonar.":
            "Два копання за раунд. J — раз за матч глушити сонар.",
        "Online plays anywhere. Local Wi-Fi needs no internet,":
            "Онлайн грає будь-де. Wi-Fi не потребує інтернету,",
        "but both Macs must be on the same network.":
            "але обидва Mac мають бути в одній мережі.",

        // Lobby
        "Give this code to your opponent": "Дай цей код супернику",
        "press C to copy": "C — скопіювати",
        "copied to clipboard": "скопійовано",
        "opponent connected": "суперник підключився",
        "waiting for opponent…": "очікування суперника…",
        "esc — back": "esc — назад",
        "Type or paste your opponent's code": "Введи або встав код суперника",
        "press return to connect": "return — підключитися",
        "Enter all": "Введи всі",
        "characters.": "символів.",
        "Searching for": "Пошук",
        "Version mismatch — both players need the same build.":
            "Різні версії — потрібна однакова збірка в обох.",
        "⌘V paste      delete      esc — back": "⌘V вставити   delete   esc — назад",

        // Planting / seeking
        "HIDE YOUR TARGET": "СХОВАЙ СВОЮ ЦІЛЬ",
        "force click inside the area to bury it": "сильно натисни в зоні, щоб заховати",
        "too close to the edge — move inside the area":
            "надто близько до краю — ближче до центру",
        "TARGET BURIED": "ЦІЛЬ СХОВАНО",
        "waiting for your opponent to hide theirs…":
            "чекаємо, поки суперник сховає свою…",
        "yours": "твоя",
        "them": "суперник",
        "LIFT YOUR FINGER": "ПРИБЕРИ ПАЛЕЦЬ",
        "they can see where your finger is — you're pointing at your own target":
            "суперник бачить палець — ти вказуєш на свою ціль",
        "good — they can't see you now": "добре — тепер тебе не видно",
        "LIFT YOUR FINGER — you're still pointing at your target":
            "ПРИБЕРИ ПАЛЕЦЬ — ти досі вказуєш на ціль",
        "FOUND IT — waiting for the verdict…": "ЗНАЙШОВ — чекаємо вердикт…",
        "OUT OF DIGS — the round is theirs unless they miss twice too":
            "КОПАННЯ ВИЧЕРПАНО — раунд їхній, якщо й вони не промахнуться",
        "FIND THEIRS FIRST": "ЗНАЙДИ ЇХНЮ ПЕРШИМ",

        // Round / match results
        "NOBODY FOUND IT": "НІХТО НЕ ЗНАЙШОВ",
        "ROUND WON": "РАУНД ВИГРАНО",
        "ROUND LOST": "РАУНД ПРОГРАНО",
        "YOU WIN THE MATCH": "ТИ ВИГРАВ МАТЧ",
        "YOU LOSE THE MATCH": "ТИ ПРОГРАВ МАТЧ",
        "you both ran out of digs — nobody scores":
            "обидва вичерпали копання — нічия",
        "they were hunting yours all along": "вони весь час шукали твою",
        "that's where they buried it": "ось де вони її сховали",
        "buried here": "сховано тут",
        "you found it": "ти знайшов",
        "it was here": "вона була тут",
        "press return for the next round": "return — наступний раунд",
        "waiting for the host to start the next round…":
            "чекаємо, поки господар почне раунд…",
        "esc — back to the menu": "esc — до меню",
        "return — rematch          esc — leave":
            "return — реванш          esc — вийти",
        "return — ask for a rematch          esc — leave":
            "return — просити реванш      esc — вийти",
        "asked for a rematch — waiting for the host…":
            "запит на реванш — чекаємо господаря…",

        // HUD tokens
        "HOST": "ГОСПОДАР",
        "GUEST": "ГІСТЬ",
        "ROUND": "РАУНД",
        "YOU": "ТИ",
        "THEM": "СУП.",
        "FIRST TO": "ДО",
        "DIGS": "КОПАННЯ",
        "SCORE": "РАХУНОК",
        "FOUND": "ЗНАЙДЕНО",
        "wasted": "змарновано",
        "JAM READY": "ГЛУШНЯ ГОТОВА",
        "JAM SPENT": "ГЛУШНЯ ВИКОРИСТАНА",
        "SONAR JAMMED": "СОНАР ЗАГЛУШЕНО",

        // Flashes / hints
        "MISS": "ПРОМАХ",
        "DECOY": "ПРИМАНКА",
        "dig left": "копання лишилось",
        "digs left": "копань лишилось",
        "OUT OF DIGS": "КОПАННЯ ВИЧЕРПАНО",
        "GET READY…": "ПРИГОТУЙСЯ…",
        "PRESS HARDER TO DIG": "НАТИСНИ СИЛЬНІШЕ",
        "TOO CLOSE TO THE EDGE": "НАДТО БЛИЗЬКО ДО КРАЮ",
        "JAMMED THEM — 3s": "ЗАГЛУШИВ ЇХ — 3с",
        "JAM ALREADY USED": "ГЛУШНЯ ВЖЕ ВИКОРИСТАНА",
        "touch the trackpad": "торкнись тачпада",
        "Score": "Рахунок",
        "↑ ↓ select      return confirm": "↑ ↓ вибір      return підтвердити",
        "      esc resume": "      esc продовжити",
        "BURY": "ЗАХОВАТИ",
        "DIG": "КОПАТИ",
        "FORCE CLICK OR SPACE —": "СИЛЬНЕ НАТИСК. АБО ПРОБІЛ —",
        "J — JAM": "J — ГЛУШНЯ",
        "ESC — MENU": "ESC — МЕНЮ",
    ]
}
