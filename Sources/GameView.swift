import AppKit

final class GameView: NSView {
    private static let trailLifetime: TimeInterval = 0.7
    private static let rippleLifetime: TimeInterval = 0.5

    private let game = Game()

    // Input state
    private var finger: Point?
    private var fingerCount = 0
    /// Every contact, not just the averaged probe point.
    private var contacts: [Point] = []
    /// Recent probe positions, drawn as a fading trail.
    private var trail: [(point: Point, at: Date)] = []

    // Sonar scheduling
    private var pingArmed = true
    private var nextPulseAt: Date = .distantFuture
    private var lastTickAt = Date()
    private var revealUntil: Date?
    /// Time left on the reveal when a menu interrupted it.
    private var revealRemaining: TimeInterval?
    private var flashMessage: String?
    private var flashUntil: Date?
    private var flashWarning = true

    /// Expanding rings that acknowledge every click, so pressing always
    /// produces *something* even when it doesn't dig.
    private struct Ripple {
        let point: Point
        let at: Date
        let hard: Bool
    }
    private var ripples: [Ripple] = []

    /// A soft click is also the first stage of a force click, so the "press
    /// harder" nudge waits a moment to see whether a dig follows.
    private var nudgeAt: Date?

    // Menus
    private var screen: Screen? = .main
    private var selection = 0
    /// Item hit boxes, rebuilt each draw so the mouse can click them.
    private var itemRects: [NSRect] = []

    /// True while actually playing — the pointer should be captured.
    var wantsPointerCaptured: Bool { screen == nil }

    private var clock: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Indirect touches = the trackpad surface itself, reported as absolute
        // normalized coordinates. This is what makes the pad a map rather than
        // a pointing device.
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
        let clock = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self))
    }

    // MARK: - Loop

    private func step() {
        let now = Date()

        // An open menu *is* the pause: no clock, no sonar.
        guard screen == nil else {
            lastTickAt = now
            needsDisplay = true
            return
        }

        lastTickAt = now

        if let until = revealUntil, now >= until {
            revealUntil = nil
            game.nextRound()
            if game.phase == .over {
                show(.over)
                needsDisplay = true
                return
            }
        }

        trail.removeAll { now.timeIntervalSince($0.at) > Self.trailLifetime }
        ripples.removeAll { now.timeIntervalSince($0.at) > Self.rippleLifetime }

        // No dig followed the click, so the press really was too soft.
        if let due = nudgeAt, now >= due {
            nudgeAt = nil
            flash("PRESS HARDER TO DIG", warning: false)
        }

        if game.phase == .hunting, let finger, fingerCount == 1, now >= nextPulseAt {
            emitSonar(at: finger)
            nextPulseAt = now.addingTimeInterval(game.pulseInterval(at: finger))
        }

        needsDisplay = true
    }

    /// One sonar return. Near a decoy the single tick becomes a stutter — a
    /// texture you learn to distrust.
    private func emitSonar(at point: Point) {
        if game.decoy(near: point) != nil {
            Haptics.burst(count: 2, interval: 0.045, tap: .weak)
        } else {
            Haptics.tap(game.pulseStrength(at: point))
        }
    }

    /// Two fingers down: fire a ping, then a single thump whose *delay* encodes
    /// the distance. Counting that gap is how you get a precise fix.
    private func fireEcho(at point: Point) {
        Haptics.tap(.weak)
        let delay = game.echoDelay(at: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.screen == nil else { return }   // don't echo into a pause
            Haptics.tap(.strong)
        }
    }

    // MARK: - Screens

    private func show(_ screen: Screen) {
        // Freeze the reveal countdown so pausing mid-reveal doesn't skip a round.
        if let until = revealUntil {
            revealRemaining = max(0, until.timeIntervalSinceNow)
            revealUntil = nil
        }
        self.screen = screen
        selection = 0
        nextPulseAt = .distantFuture
        // Menus mean a usable pointer — that's what makes the items clickable.
        PointerCapture.shared.release()
        needsDisplay = true
    }

    private func resumePlay() {
        screen = nil
        lastTickAt = Date()
        if let remaining = revealRemaining {
            revealUntil = Date().addingTimeInterval(remaining)
            revealRemaining = nil
        }
        PointerCapture.shared.capture()
        needsDisplay = true
    }

    private func startNewGame() {
        game.start()
        trail.removeAll()
        ripples.removeAll()
        contacts = []
        finger = nil
        revealUntil = nil
        revealRemaining = nil
        flashUntil = nil
        nudgeAt = nil
        resumePlay()
    }

    private func activate(_ action: MenuAction) {
        switch action {
        case .play, .restart: startNewGame()
        case .resume: resumePlay()
        case .mainMenu: show(.main)
        case .help: show(.help)
        case .back: show(.main)
        case .quit: NSApp.terminate(nil)
        }
    }

    // MARK: - Touch input

    private func updateTouches(_ event: NSEvent) {
        let touches = event.touches(matching: .touching, in: self)
        fingerCount = touches.count
        guard !touches.isEmpty else {
            finger = nil
            contacts = []
            nextPulseAt = .distantFuture
            pingArmed = true
            return
        }

        contacts = touches.map {
            Point(x: Double($0.normalizedPosition.x), y: Double($0.normalizedPosition.y))
        }

        // Average the contacts so a two-finger ping probes the midpoint.
        let sum = contacts.reduce(into: (x: 0.0, y: 0.0)) {
            $0.x += $1.x
            $0.y += $1.y
        }
        let count = Double(contacts.count)
        let point = Point(x: sum.x / count, y: sum.y / count)
        finger = point
        trail.append((point, Date()))

        guard screen == nil, game.phase == .hunting else { return }

        if touches.count >= 2 {
            if pingArmed {
                pingArmed = false
                fireEcho(at: point)
            }
            nextPulseAt = .distantFuture   // silence the geiger during a ping
        } else {
            pingArmed = true
            if nextPulseAt == .distantFuture { nextPulseAt = Date() }
        }
    }

    override func touchesBegan(with event: NSEvent) { updateTouches(event) }
    override func touchesMoved(with event: NSEvent) { updateTouches(event) }
    override func touchesEnded(with event: NSEvent) { updateTouches(event) }
    override func touchesCancelled(with event: NSEvent) { updateTouches(event) }

    // MARK: - Keyboard & mouse

    override func keyDown(with event: NSEvent) {
        if let screen {
            let items = screen.items
            switch event.keyCode {
            case 126: selection = (selection - 1 + items.count) % items.count   // up
            case 125: selection = (selection + 1) % items.count                 // down
            case 36, 76: activate(items[selection].action)                      // return
            case 53:                                                            // esc
                switch screen {
                case .pause: resumePlay()
                case .help: show(.main)
                case .main, .over: break
                }
            default: break
            }
            needsDisplay = true
            return
        }

        switch event.keyCode {
        case 53: show(.pause)
        case 49: dig()                       // space
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard screen != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let index = itemRects.firstIndex(where: { $0.contains(point) }), index != selection {
            selection = index
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let screen else {
            softClick()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let index = itemRects.firstIndex(where: { $0.contains(point) }) {
            activate(screen.items[index].action)
        }
    }

    /// A normal click can't dig — but it must never feel like nothing happened.
    private func softClick() {
        guard game.phase == .hunting, let finger else { return }
        ripples.append(Ripple(point: finger, at: Date(), hard: false))
        Haptics.tap(.weak)
        nudgeAt = Date().addingTimeInterval(0.4)
        needsDisplay = true
    }

    /// Force click digs at the current finger position.
    override func pressureChange(with event: NSEvent) {
        guard screen == nil else { return }
        if event.stage >= 2 { dig() }
    }

    private func dig() {
        guard screen == nil, game.phase == .hunting, let finger else { return }

        // A dig arrived, so the pending "press harder" nudge is wrong.
        nudgeAt = nil
        ripples.append(Ripple(point: finger, at: Date(), hard: true))

        switch game.dig(at: finger) {
        case .found:
            nextPulseAt = .distantFuture
            Haptics.burst(count: 6, interval: 0.05, tap: .strong)
            revealUntil = Date().addingTimeInterval(2.0)
        case .decoy:
            // A sour triple — you dug the thing that was lying to you.
            Haptics.burst(count: 3, interval: 0.11, tap: .strong)
            flash("DECOY  −\(Game.decoyCost)")
        case .miss:
            Haptics.burst(count: 2, interval: 0.13, tap: .weak)
            flash("MISS  −\(Game.missCost)")
        case nil:
            break
        }
        needsDisplay = true
    }

    private func flash(_ message: String, warning: Bool = true) {
        flashMessage = message
        flashWarning = warning
        flashUntil = Date().addingTimeInterval(warning ? 1.1 : 1.6)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
        bounds.fill()

        let arena = arenaRect()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        let path = NSBezierPath(roundedRect: arena, xRadius: 14, yRadius: 14)
        path.fill()
        NSColor(calibratedWhite: 0.22, alpha: 1).setStroke()
        path.lineWidth = 1
        path.stroke()

        if game.phase == .reveal { drawReveal(in: arena) }
        if screen == nil {
            // Ripples go underneath: they're transient, the misses are lasting
            // information and must never be painted over.
            drawRipples(in: arena)
            drawMisses(in: arena)
            drawContacts(in: arena)
            drawFlash(in: arena)
            drawHUD()
            drawMenuHint()
        } else {
            drawMenu(in: arena)
        }
    }

    private func arenaRect() -> NSRect {
        // Match the trackpad's aspect so the mapping feels honest.
        var rect = bounds.insetBy(dx: 24, dy: 24)
        rect.size.height -= 34
        let aspect: CGFloat = 1.6
        if rect.width / rect.height > aspect {
            let width = rect.height * aspect
            rect.origin.x += (rect.width - width) / 2
            rect.size.width = width
        } else {
            let height = rect.width / aspect
            rect.origin.y += (rect.height - height) / 2
            rect.size.height = height
        }
        return rect
    }

    private func screenPoint(_ point: Point, in arena: NSRect) -> NSPoint {
        NSPoint(
            x: arena.minX + CGFloat(point.x) * arena.width,
            y: arena.minY + CGFloat(point.y) * arena.height)
    }

    // MARK: Menu drawing

    private func drawMenu(in arena: NSRect) {
        guard let screen else { return }

        // Dim whatever is behind, so a paused game stays faintly visible.
        NSColor(calibratedWhite: 0.05, alpha: 0.88).setFill()
        arena.fill()

        let blurb = screen.blurb
        let items = screen.items
        let itemHeight: CGFloat = 44
        let blockHeight = CGFloat(blurb.count) * 22 + CGFloat(items.count) * itemHeight + 90
        var y = arena.midY + blockHeight / 2

        draw(screen.title, at: NSPoint(x: arena.midX, y: y), size: 34,
             color: NSColor(calibratedWhite: 0.96, alpha: 1), centered: true, tracking: 8)
        y -= 54

        if screen == .over {
            draw("Score \(game.score)", at: NSPoint(x: arena.midX, y: y), size: 17,
                 color: NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.6, alpha: 1),
                 centered: true)
            y -= 40
        }

        for line in blurb {
            draw(line, at: NSPoint(x: arena.midX, y: y), size: 13,
                 color: NSColor(calibratedWhite: 0.55, alpha: 1),
                 centered: true, monospaced: screen == .help)
            y -= 22
        }
        y -= 28

        itemRects = []
        for (index, item) in items.enumerated() {
            let selected = index == selection
            let rect = NSRect(x: arena.midX - 150, y: y - 12, width: 300, height: itemHeight - 8)
            itemRects.append(rect)

            if selected {
                NSColor(calibratedRed: 0.35, green: 0.7, blue: 0.95, alpha: 0.14).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
                NSColor(calibratedRed: 0.5, green: 0.82, blue: 1, alpha: 0.55).setStroke()
                let outline = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
                outline.lineWidth = 1
                outline.stroke()
            }

            draw(item.title, at: NSPoint(x: arena.midX, y: y),
                 size: 16,
                 color: selected
                     ? NSColor(calibratedRed: 0.65, green: 0.9, blue: 1, alpha: 1)
                     : NSColor(calibratedWhite: 0.62, alpha: 1),
                 centered: true)
            y -= itemHeight
        }

        draw("↑ ↓ select      return confirm" + (screen == .pause ? "      esc resume" : ""),
             at: NSPoint(x: arena.midX, y: arena.minY + 26), size: 11,
             color: NSColor(calibratedWhite: 0.35, alpha: 1), centered: true)
    }

    /// Persistent in-game affordance — you should never have to guess the way out.
    private func drawMenuHint() {
        draw("FORCE CLICK OR SPACE — DIG          ESC — MENU",
             at: NSPoint(x: bounds.midX, y: 38), size: 11,
             color: NSColor(calibratedWhite: 0.38, alpha: 1), centered: true, tracking: 2)
    }

    // MARK: Play drawing

    /// Where your fingers are on the pad. Note this shows *you*, never the
    /// target — the hunt is still blind, you just aren't lost anymore.
    /// Wrong digs stay on the board for the rest of the round — they're places
    /// you've ruled out, and you paid for that knowledge.
    private func drawMisses(in arena: NSRect) {
        for miss in game.misses {
            let point = screenPoint(miss, in: arena)
            NSColor(calibratedRed: 0.92, green: 0.38, blue: 0.36, alpha: 0.85).setStroke()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: point.x - 6, y: point.y - 6))
            cross.line(to: NSPoint(x: point.x + 6, y: point.y + 6))
            cross.move(to: NSPoint(x: point.x - 6, y: point.y + 6))
            cross.line(to: NSPoint(x: point.x + 6, y: point.y - 6))
            cross.lineWidth = 2
            cross.stroke()
        }
    }

    /// Both click ripples are neutral white — a dig is an action, not a result,
    /// so it must not compete with the red misses or the green/red reveal for
    /// meaning. The hard one is only slightly larger and brighter.
    private func drawRipples(in arena: NSRect) {
        let now = Date()
        for ripple in ripples {
            let age = now.timeIntervalSince(ripple.at) / Self.rippleLifetime
            guard age <= 1 else { continue }
            let center = screenPoint(ripple.point, in: arena)
            let eased = 1 - pow(1 - age, 2)          // fast out, slow settle
            let alpha = (1 - age) * (ripple.hard ? 0.45 : 0.25)
            let radius = ripple.hard ? 12 + eased * 38 : 8 + eased * 22

            NSColor(calibratedWhite: 0.85, alpha: alpha).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))
            ring.lineWidth = ripple.hard ? 1.5 : 1
            ring.stroke()
        }
    }

    private func drawFlash(in arena: NSRect) {
        guard let flashMessage, let flashUntil else { return }
        let remaining = flashUntil.timeIntervalSinceNow
        guard remaining > 0 else { return }
        let alpha = min(1, remaining / 0.5)
        let color = flashWarning
            ? NSColor(calibratedRed: 0.9, green: 0.45, blue: 0.4, alpha: alpha)
            : NSColor(calibratedRed: 0.95, green: 0.8, blue: 0.4, alpha: alpha)
        draw(flashMessage, at: NSPoint(x: arena.midX, y: arena.maxY - 34), size: 15,
             color: color, centered: true, tracking: 1.5)
    }

    private func drawContacts(in arena: NSRect) {
        let now = Date()

        for entry in trail {
            let age = now.timeIntervalSince(entry.at) / Self.trailLifetime
            guard age <= 1 else { continue }
            let point = screenPoint(entry.point, in: arena)
            let alpha = (1 - age) * 0.22
            let radius = 3 + (1 - age) * 2
            NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.95, alpha: alpha).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: point.x - radius, y: point.y - radius,
                width: radius * 2, height: radius * 2)).fill()
        }

        let multi = contacts.count > 1
        for contact in contacts {
            let center = screenPoint(contact, in: arena)

            NSColor(calibratedRed: 0.45, green: 0.78, blue: 1, alpha: 0.16).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: center.x - 20, y: center.y - 20, width: 40, height: 40)).fill()

            NSColor(calibratedRed: 0.55, green: 0.85, blue: 1, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11)).fill()

            // Two fingers down = a ping is armed; ring them to show the mode.
            if multi {
                NSColor(calibratedRed: 0.55, green: 0.85, blue: 1, alpha: 0.5).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(
                    x: center.x - 15, y: center.y - 15, width: 30, height: 30))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }

        if contacts.isEmpty && game.phase == .hunting {
            draw("touch the trackpad", at: NSPoint(x: arena.midX, y: arena.midY),
                 size: 12.5, color: NSColor(calibratedWhite: 0.3, alpha: 1), centered: true)
        }
    }

    private func drawReveal(in arena: NSRect) {
        let found = game.lastResult.hasPrefix("FOUND")

        for decoy in game.decoys {
            let center = screenPoint(decoy, in: arena)
            NSColor(calibratedRed: 0.6, green: 0.5, blue: 0.15, alpha: 0.5).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - 13, y: center.y - 13, width: 26, height: 26))
            ring.lineWidth = 1.5
            ring.stroke()
        }

        let target = screenPoint(game.target, in: arena)
        let color = found
            ? NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.5, alpha: 1)
            : NSColor(calibratedRed: 0.9, green: 0.35, blue: 0.35, alpha: 1)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: target.x - 9, y: target.y - 9, width: 18, height: 18)).fill()

        if let dig = game.lastDig {
            let point = screenPoint(dig, in: arena)
            NSColor(calibratedWhite: 0.8, alpha: 0.9).setStroke()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: point.x - 7, y: point.y - 7))
            cross.line(to: NSPoint(x: point.x + 7, y: point.y + 7))
            cross.move(to: NSPoint(x: point.x - 7, y: point.y + 7))
            cross.line(to: NSPoint(x: point.x + 7, y: point.y - 7))
            cross.lineWidth = 2
            cross.stroke()

            let line = NSBezierPath()
            line.move(to: point)
            line.line(to: target)
            line.lineWidth = 1
            color.withAlphaComponent(0.4).setStroke()
            line.stroke()
        }

        draw(game.lastResult, at: NSPoint(x: arena.midX, y: arena.maxY - 34),
             size: 15, color: color, centered: true)
    }

    private func drawHUD() {
        var hud = "ROUND \(min(game.round, Game.roundCount))/\(Game.roundCount)"
            + "     SCORE \(game.score)"
        if game.roundPenalty > 0 { hud += "     ROUND −\(game.roundPenalty)" }
        draw(hud, at: NSPoint(x: bounds.midX, y: 62), size: 11,
             color: NSColor(calibratedWhite: 0.45, alpha: 1), centered: true)
    }

    private func draw(
        _ text: String, at point: NSPoint, size: CGFloat, color: NSColor,
        centered: Bool, tracking: CGFloat = 0, monospaced: Bool = true
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: monospaced
                ? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                : NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        let string = NSAttributedString(string: text, attributes: attributes)
        var origin = point
        if centered { origin.x -= string.size().width / 2 }
        string.draw(at: origin)
    }
}
