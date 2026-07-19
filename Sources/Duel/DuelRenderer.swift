import AppKit

/// Duel-specific overlays. Finger marks, ripples and trails stay in GameView
/// so both modes share exactly one implementation of "where your hand is".
enum DuelRenderer {

    // MARK: - Lobby

    static func drawHostLobby(code: String, connected: Bool, in arena: NSRect, copied: Bool) {
        var y = arena.midY + 110
        Draw.text("LOBBY", at: NSPoint(x: arena.midX, y: y), size: 26,
                  color: Draw.Palette.bright, centered: true, tracking: 7)
        y -= 56
        Draw.text("Give this code to your opponent",
                  at: NSPoint(x: arena.midX, y: y), size: 13,
                  color: Draw.Palette.dim, centered: true)
        y -= 62

        // The code is the whole point of this screen — make it huge.
        Draw.text(code, at: NSPoint(x: arena.midX, y: y), size: 54,
                  color: Draw.Palette.finger, centered: true, tracking: 14)
        y -= 54

        Draw.text(copied ? "copied to clipboard" : "press C to copy",
                  at: NSPoint(x: arena.midX, y: y), size: 12,
                  color: copied ? Draw.Palette.good : Draw.Palette.faint, centered: true)
        y -= 44

        Draw.text(connected ? "opponent connected" : "waiting for opponent…",
                  at: NSPoint(x: arena.midX, y: y), size: 14,
                  color: connected ? Draw.Palette.good : Draw.Palette.dim, centered: true)

        Draw.text("esc — back", at: NSPoint(x: arena.midX, y: arena.minY + 26),
                  size: 11, color: Draw.Palette.faint, centered: true)
    }

    static func drawJoinEntry(typed: String, status: String?, in arena: NSRect) {
        var y = arena.midY + 90
        Draw.text("JOIN A GAME", at: NSPoint(x: arena.midX, y: y), size: 26,
                  color: Draw.Palette.bright, centered: true, tracking: 7)
        y -= 56
        Draw.text("Type or paste your opponent's code",
                  at: NSPoint(x: arena.midX, y: y), size: 13,
                  color: Draw.Palette.dim, centered: true)
        y -= 70

        // Fixed slots, so it's obvious how many characters are expected.
        let slotWidth: CGFloat = 46
        let totalWidth = slotWidth * CGFloat(LobbyCode.length)
        let characters = Array(typed)
        for index in 0..<LobbyCode.length {
            let x = arena.midX - totalWidth / 2 + slotWidth * CGFloat(index) + slotWidth / 2
            let filled = index < characters.count
            let box = NSRect(x: x - 18, y: y - 8, width: 36, height: 46)
            NSColor(calibratedWhite: filled ? 0.2 : 0.15, alpha: 1).setFill()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
            if filled {
                Draw.text(String(characters[index]), at: NSPoint(x: x, y: y + 4),
                          size: 28, color: Draw.Palette.finger, centered: true)
            }
        }
        y -= 60

        if let status {
            Draw.text(status, at: NSPoint(x: arena.midX, y: y), size: 13,
                      color: Draw.Palette.warn, centered: true)
        } else if LobbyCode.isComplete(typed) {
            Draw.text("press return to connect", at: NSPoint(x: arena.midX, y: y),
                      size: 13, color: Draw.Palette.good, centered: true)
        }

        Draw.text("⌘V paste      delete      esc — back",
                  at: NSPoint(x: arena.midX, y: arena.minY + 26),
                  size: 11, color: Draw.Palette.faint, centered: true)
    }

    // MARK: - Match

    /// Planting: the only screen where the legal region is shown, because it's
    /// the only screen where it constrains you.
    static func drawPlanting(match: DuelMatch, finger: Point?, in arena: NSRect) {
        let path = Draw.plantingAreaPath(in: arena)
        NSColor(calibratedRed: 0.35, green: 0.65, blue: 0.9, alpha: 0.07).setFill()
        path.fill()
        NSColor(calibratedRed: 0.45, green: 0.75, blue: 1, alpha: 0.4).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([5, 5], count: 2, phase: 0)
        path.stroke()

        let legal = finger.map(PlantingArea.contains) ?? true
        Draw.text("HIDE YOUR TARGET", at: NSPoint(x: arena.midX, y: arena.maxY - 44),
                  size: 17, color: Draw.Palette.bright, centered: true, tracking: 4)
        Draw.text(legal
                    ? "force click inside the area to bury it"
                    : "too close to the edge — move inside the area",
                  at: NSPoint(x: arena.midX, y: arena.maxY - 72),
                  size: 13, color: legal ? Draw.Palette.dim : Draw.Palette.warn,
                  centered: true)
    }

    static func drawWaitingForOpponent(myTarget: Point?, in arena: NSRect) {
        let path = Draw.plantingAreaPath(in: arena)
        NSColor(calibratedWhite: 0.3, alpha: 0.25).setStroke()
        path.lineWidth = 1
        path.setLineDash([4, 6], count: 2, phase: 0)
        path.stroke()

        if let myTarget {
            // You may as well see your own hiding place while you wait.
            let center = Draw.point(myTarget, in: arena)
            Draw.Palette.warn.withAlphaComponent(0.8).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - 11, y: center.y - 11, width: 22, height: 22))
            ring.lineWidth = 1.5
            ring.stroke()
            Draw.text("yours", at: NSPoint(x: center.x, y: center.y + 16),
                      size: 10, color: Draw.Palette.warn.withAlphaComponent(0.8),
                      centered: true)
        }

        Draw.text("TARGET BURIED", at: NSPoint(x: arena.midX, y: arena.midY + 14),
                  size: 17, color: Draw.Palette.good, centered: true, tracking: 4)
        Draw.text("waiting for your opponent to hide theirs…",
                  at: NSPoint(x: arena.midX, y: arena.midY - 16),
                  size: 13, color: Draw.Palette.dim, centered: true)
    }

    static func drawSeekingBanner(awaitingRuling: Bool, in arena: NSRect) {
        if awaitingRuling {
            Draw.text("FOUND IT — waiting for the verdict…",
                      at: NSPoint(x: arena.midX, y: arena.maxY - 44),
                      size: 15, color: Draw.Palette.good, centered: true)
        } else {
            Draw.text("FIND THEIRS FIRST", at: NSPoint(x: arena.midX, y: arena.maxY - 40),
                      size: 13, color: Draw.Palette.faint, centered: true, tracking: 3)
        }
    }

    static func drawRoundOver(match: DuelMatch, in arena: NSRect) {
        NSColor(calibratedWhite: 0.05, alpha: 0.8).setFill()
        arena.fill()

        let won = match.lastRoundWonByMe ?? false
        let matchOver = match.phase == .matchOver

        if let target = match.revealedTarget {
            let center = Draw.point(target, in: arena)
            (won ? Draw.Palette.good : Draw.Palette.bad).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: center.x - 9, y: center.y - 9, width: 18, height: 18)).fill()
        }

        var y = arena.midY + 40
        let headline: String
        if matchOver {
            headline = won ? "YOU WIN THE MATCH" : "YOU LOSE THE MATCH"
        } else {
            headline = won ? "ROUND WON" : "ROUND LOST"
        }
        Draw.text(headline, at: NSPoint(x: arena.midX, y: y), size: 26,
                  color: won ? Draw.Palette.good : Draw.Palette.bad,
                  centered: true, tracking: 5)
        y -= 44
        Draw.text("\(match.myScore) — \(match.opponentScore)",
                  at: NSPoint(x: arena.midX, y: y), size: 30,
                  color: Draw.Palette.bright, centered: true, tracking: 4)
        y -= 46
        Draw.text(won ? "they were hunting yours all along"
                      : "that's where they buried it",
                  at: NSPoint(x: arena.midX, y: y), size: 12,
                  color: Draw.Palette.dim, centered: true)
        y -= 40

        if matchOver {
            Draw.text("esc — back to the menu", at: NSPoint(x: arena.midX, y: y),
                      size: 13, color: Draw.Palette.faint, centered: true)
        } else if match.isHost {
            Draw.text("press return for the next round",
                      at: NSPoint(x: arena.midX, y: y), size: 13,
                      color: Draw.Palette.warn, centered: true)
        } else {
            Draw.text("waiting for the host to start the next round…",
                      at: NSPoint(x: arena.midX, y: y), size: 13,
                      color: Draw.Palette.dim, centered: true)
        }
    }

    static func drawDisconnected(reason: String, in arena: NSRect) {
        NSColor(calibratedWhite: 0.05, alpha: 0.85).setFill()
        arena.fill()
        Draw.text("DISCONNECTED", at: NSPoint(x: arena.midX, y: arena.midY + 20),
                  size: 24, color: Draw.Palette.bad, centered: true, tracking: 5)
        Draw.text(reason, at: NSPoint(x: arena.midX, y: arena.midY - 14),
                  size: 13, color: Draw.Palette.dim, centered: true)
        Draw.text("esc — back to the menu",
                  at: NSPoint(x: arena.midX, y: arena.midY - 50),
                  size: 12, color: Draw.Palette.faint, centered: true)
    }

    /// Always-visible match state during play.
    static func drawHUD(match: DuelMatch, in bounds: NSRect) {
        let role = match.isHost ? "HOST" : "GUEST"
        let hud = "ROUND \(match.round)     YOU \(match.myScore) — \(match.opponentScore) THEM"
            + "     FIRST TO \(DuelMatch.winsNeeded)     \(role)"
        Draw.text(hud, at: NSPoint(x: bounds.midX, y: 62), size: 11,
                  color: Draw.Palette.faint, centered: true)
    }
}
