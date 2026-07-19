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

    // Duel
    /// Which game we're in. Duel and solo never run at once.
    private enum Mode { case solo, duel }
    private var mode: Mode = .solo
    private var match: DuelMatch?
    /// Whichever way we're reaching the opponent this match.
    private var link: PeerLink = LocalLink()
    /// The opponent's finger, as of their last probe. Stale probes are
    /// dropped rather than left frozen on screen.
    private var opponentFinger: Point?
    private var opponentFingerAt: Date?
    private var lastProbeSent: (point: Point, at: Date)?
    /// Guest has asked for a rematch and is waiting on the host.
    private var rematchRequested = false
    /// Seeking is inert until this moment. The player who planted last is
    /// still pressing hard when the round flips, and without a beat they'd
    /// burn a dig on the spot where they buried their own target.
    private var seekArmedAt: Date?
    /// Probes stay locked until the player lifts the finger they planted with.
    /// Otherwise the first thing streamed to the opponent is a marker sitting
    /// exactly on the target you just buried — handing them the round.
    private var probesUnlocked = false
    /// A force click stays at stage 2 for as long as you hold it, and
    /// pressureChange keeps firing — so a single press would spend every dig
    /// you have. Digging is edge-triggered: it fires once when the press
    /// crosses into stage 2, and re-arms only after you let go.
    private var deepClickActive = false
    /// Backstop for any other repeat path (key auto-repeat, trackpad noise).
    private var lastDigAt: Date?

    /// Lobby UI state.
    private enum Lobby { case none, hosting(String), joining }
    private var lobby: Lobby = .none
    private var typedCode = ""
    private var lobbyStatus: String?
    private var codeCopied = false

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

        if mode == .duel {
            stepDuel(now)
            needsDisplay = true
            return
        }

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

    /// Duel sonar. The opponent's target is already on this machine, so this is
    /// computed entirely locally — the network is never in the haptic path.
    private func stepDuel(_ now: Date) {
        guard let match, match.canSeek, seekArmed, fingerCount == 1, let finger,
              now >= nextPulseAt, !match.awaitingRuling, !match.isOut
        else { return }

        guard let distance = match.distance(from: finger) else { return }
        Haptics.tap(Sonar.strength(distance: distance))
        nextPulseAt = now.addingTimeInterval(Sonar.pulseInterval(distance: distance))
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

    /// Returning to a duel resumes the shared round, which never paused on the
    /// opponent's machine — only your own view of it did.
    private func resumeDuel() {
        screen = nil
        lastTickAt = Date()
        PointerCapture.shared.capture()
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
        case .play, .restart:
            leaveDuel()          // solo must never leave a match half-connected
            startNewGame()
        case .resume:
            if mode == .duel { resumeDuel() } else { resumePlay() }
        case .mainMenu: leaveDuel(); show(.main)
        case .help: show(.help)
        case .back:
            if screen == .duel { show(.main) } else { show(.main) }
        case .quit: NSApp.terminate(nil)
        case .duel: show(.duel)
        case .hostGame: startHosting(online: false)
        case .joinGame: startJoining(online: false)
        case .hostOnline: startHosting(online: true)
        case .joinOnline: startJoining(online: true)
        case .restartMatch: requestRematch()
        case .leaveMatch: leaveDuel(); show(.main)
        }
    }

    // MARK: - Duel setup

    private func startHosting(online: Bool) {
        mode = .duel
        link = online ? RelayLink() : LocalLink()
        let code = LobbyCode.generate()
        lobby = .hosting(code)
        codeCopied = false
        lobbyStatus = nil
        match = DuelMatch(isHost: true)
        wireTransport()
        link.host(code: code)
        screen = nil
        PointerCapture.shared.release()   // lobby needs a usable pointer
        needsDisplay = true
    }

    private func startJoining(online: Bool) {
        mode = .duel
        link = online ? RelayLink() : LocalLink()
        lobby = .joining
        typedCode = ""
        lobbyStatus = nil
        match = DuelMatch(isHost: false)
        wireTransport()
        screen = nil
        PointerCapture.shared.release()
        needsDisplay = true
    }

    private func wireTransport() {
        link.onStatusChange = { [weak self] status in
            guard let self else { return }
            switch status {
            case .connected:
                self.lobbyStatus = nil
                self.lobby = .none
                self.link.send(.hello(
                    protocolVersion: Message.currentVersion, playerName: NSUserName()))
                // The host owns round numbering.
                if self.match?.isHost == true {
                    self.match?.beginRound(1)
                    self.link.send(.nextRound(round: 1))
                } else {
                    self.match?.beginRound(1)
                }
                self.enterDuelPlay()
            case .failed(let reason):
                self.lobbyStatus = reason
                self.match?.disconnect(reason)
                PointerCapture.shared.release()
            default:
                break
            }
            self.needsDisplay = true
        }

        link.onMessage = { [weak self] message in
            self?.handle(message)
            self?.needsDisplay = true
        }
    }

    private func handle(_ message: Message) {
        guard let match else { return }
        switch message {
        case .hello(let version, _):
            if version != Message.currentVersion {
                lobbyStatus = "Version mismatch — both players need the same build."
                match.disconnect("Version mismatch")
                link.stop()
            }

        case .planted(let x, let y):
            match.receiveOpponentTarget(Point(x: x, y: y))
            if match.canSeek { beginSeeking() }

        case .foundIt:
            // Only the host arbitrates, and only while the round is open.
            guard match.isHost, match.phase == .seeking else { return }
            hostConclude(.guest)

        case .outOfDigs:
            guard match.isHost, match.phase == .seeking else { return }
            match.markOpponentOut()
            if let verdict = match.eliminationVerdict() { hostConclude(verdict) }

        case .roundResult(let winner, let hostScore, let guestScore):
            guard !match.isHost else { return }
            match.applyRuling(
                winner: winner, hostScore: hostScore, guestScore: guestScore)
            endRoundLocally()

        case .nextRound(let round):
            guard !match.isHost else { return }
            match.beginRound(round)
            enterDuelPlay()

        case .rematchRequest:
            // Only the host can start one; a guest's request is advisory.
            guard match.isHost else { return }
            startRematch()

        case .restartMatch(let round):
            guard !match.isHost else { return }
            match.restartMatch()
            match.beginRound(round)
            rematchRequested = false
            enterDuelPlay()

        case .probe(let x, let y):
            // Drop anything that arrives during the lead-in rather than
            // buffering it: that window is exactly when their finger is still
            // resting on the target they just buried. Suppressing our own
            // sending isn't enough — an older or modified client would still
            // broadcast, so the receiver refuses to look.
            guard seekArmed else { return }
            opponentFinger = Point(x: x, y: y)
            opponentFingerAt = Date()

        case .peerJoined, .peerLeft:
            break        // handled by the link as a status change

        case .bye:
            match.disconnect("Opponent left the match")
            link.stop()
            PointerCapture.shared.release()
        }
    }

    /// Planting and seeking both want the pointer captured and the pad ours.
    private func enterDuelPlay() {
        screen = nil
        opponentFinger = nil
        opponentFingerAt = nil
        lastProbeSent = nil
        rematchRequested = false
        probesUnlocked = false
        trail.removeAll()
        ripples.removeAll()
        nextPulseAt = .distantFuture
        PointerCapture.shared.capture()
    }

    /// Stream my finger to the opponent so they can watch me hunt. Throttled
    /// hard — 12/second, and only when the finger has actually moved — because
    /// every message is a Durable Object request, and this is decoration
    /// rather than gameplay.
    private static let probeInterval: TimeInterval = 1.0 / 12
    private static let probeMinimumMove = 0.008

    private func shareProbe(_ point: Point) {
        // Silence until they've lifted: see `probesUnlocked`.
        guard probesUnlocked else { return }
        let now = Date()
        if let last = lastProbeSent {
            guard now.timeIntervalSince(last.at) >= Self.probeInterval,
                  point.distance(to: last.point) >= Self.probeMinimumMove
            else { return }
        }
        lastProbeSent = (point, now)
        link.send(.probe(x: point.x, y: point.y))
    }

    /// Either player can ask; only the host acts. Works mid-match from the
    /// pause menu as well as after a match ends.
    private func requestRematch() {
        guard let match else { return }
        if match.isHost {
            startRematch()
        } else {
            rematchRequested = true
            link.send(.rematchRequest)
            screen = nil
            PointerCapture.shared.capture()
            needsDisplay = true
        }
    }

    private func startRematch() {
        guard let match, match.isHost else { return }
        match.restartMatch()
        match.beginRound(1)
        rematchRequested = false
        link.send(.restartMatch(round: 1))
        enterDuelPlay()
    }

    private static let roundLeadIn: TimeInterval = 3.0

    private func beginSeeking() {
        let armed = Date().addingTimeInterval(Self.roundLeadIn)
        seekArmedAt = armed
        nextPulseAt = armed          // no sonar during the lead-in either
        needsDisplay = true
    }

    /// True once the lead-in has elapsed.
    private var seekArmed: Bool {
        guard let seekArmedAt else { return false }
        return Date() >= seekArmedAt
    }

    /// Host-only: publish a verdict and end the round on both machines.
    private func hostConclude(_ winner: RoundWinner) {
        guard let match, match.isHost else { return }
        let scores = match.hostResolve(winner: winner)
        link.send(.roundResult(
            winner: winner,
            hostScore: scores.hostScore, guestScore: scores.guestScore))
        endRoundLocally()
    }

    private func endRoundLocally() {
        nextPulseAt = .distantFuture
        Haptics.burst(count: 4, interval: 0.06, tap: .strong)
    }

    private func leaveDuel() {
        if case .connected = link.status { link.send(.bye) }
        link.stop()
        match = nil
        mode = .solo
        lobby = .none
        typedCode = ""
        lobbyStatus = nil
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
            // Hand off the pad: from here it's safe to show them where I am.
            probesUnlocked = true
            deepClickActive = false
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

        guard screen == nil else { return }

        if mode == .duel {
            guard let match, match.canSeek, !match.awaitingRuling else { return }
            shareProbe(point)
            guard seekArmed, !match.isOut else { return }
            if touches.count >= 2 {
                if pingArmed, let distance = match.distance(from: point) {
                    pingArmed = false
                    Haptics.tap(.weak)
                    let delay = Sonar.echoDelay(distance: distance)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard self?.screen == nil else { return }
                        Haptics.tap(.strong)
                    }
                }
                nextPulseAt = .distantFuture
            } else {
                pingArmed = true
                if nextPulseAt == .distantFuture { nextPulseAt = Date() }
            }
            return
        }

        guard game.phase == .hunting else { return }

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
        if mode == .duel, screen == nil, handleDuelKey(event) {
            needsDisplay = true
            return
        }

        if let screen {
            let items = screen.items
            switch event.keyCode {
            case 126: selection = (selection - 1 + items.count) % items.count   // up
            case 125: selection = (selection + 1) % items.count                 // down
            case 36, 76: activate(items[selection].action)                      // return
            case 53:                                                            // esc
                switch screen {
                case .pause: resumePlay()
                case .duelPause: resumeDuel()
                case .help, .duel: show(.main)
                case .main, .over: break
                }
            default: break
            }
            needsDisplay = true
            return
        }

        switch event.keyCode {
        case 53: show(.pause)
        case 49: if !event.isARepeat { dig() }        // space, no auto-repeat
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }

    /// Returns true if the duel consumed the key.
    private func handleDuelKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)

        switch lobby {
        case .hosting(let code):
            if event.keyCode == 53 { leaveDuel(); show(.duel); return true }   // esc
            if event.charactersIgnoringModifiers?.lowercased() == "c" {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                codeCopied = true
                return true
            }
            return true   // swallow everything else while in the lobby

        case .joining:
            if event.keyCode == 53 { leaveDuel(); show(.duel); return true }
            if command, event.charactersIgnoringModifiers?.lowercased() == "v" {
                let pasted = NSPasteboard.general.string(forType: .string) ?? ""
                typedCode = LobbyCode.normalize(pasted)
                return true
            }
            if event.keyCode == 51 {                                          // delete
                if !typedCode.isEmpty { typedCode.removeLast() }
                return true
            }
            if event.keyCode == 36 || event.keyCode == 76 {                   // return
                guard LobbyCode.isComplete(typedCode) else {
                    lobbyStatus = "Enter all \(LobbyCode.length) characters."
                    return true
                }
                lobbyStatus = "Searching for \(typedCode)…"
                link.join(code: typedCode)
                return true
            }
            if let characters = event.charactersIgnoringModifiers, !command {
                let filtered = LobbyCode.normalize(typedCode + characters)
                typedCode = filtered
            }
            return true

        case .none:
            break
        }

        guard let match else { return false }

        switch match.phase {
        case .planting, .waitingForOpponent, .seeking:
            if event.keyCode == 53 { show(.duelPause); return true }
            // isARepeat: holding space would otherwise machine-gun digs.
            if event.keyCode == 49 {
                if !event.isARepeat { duelDig() }
                return true
            }
            return false
        case .roundOver:
            // Only the host advances, so both machines stay on the same round.
            if (event.keyCode == 36 || event.keyCode == 76), match.isHost {
                let next = match.round + 1
                match.beginRound(next)
                link.send(.nextRound(round: next))
                enterDuelPlay()
                return true
            }
            if event.keyCode == 53 { show(.duelPause); return true }
            return true
        case .matchOver:
            if event.keyCode == 36 || event.keyCode == 76 {      // return
                requestRematch()
                return true
            }
            if event.keyCode == 53 {                              // esc
                leaveDuel()
                show(.main)
                return true
            }
            return true
        case .disconnected:
            if event.keyCode == 53 || event.keyCode == 36 {
                leaveDuel()
                show(.main)
                return true
            }
            return true
        case .lobby:
            return false
        }
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

    /// Force click digs at the current finger position — once per press.
    override func pressureChange(with event: NSEvent) {
        guard screen == nil else { return }

        guard event.stage >= 2 else {
            deepClickActive = false     // released: ready for the next dig
            return
        }
        guard !deepClickActive else { return }   // still the same press
        deepClickActive = true

        if mode == .duel { duelDig() } else { dig() }
    }

    /// Two digs can never land closer together than this, whatever the input.
    private static let digCooldown: TimeInterval = 0.45

    private var digCoolingDown: Bool {
        guard let lastDigAt else { return false }
        return Date().timeIntervalSince(lastDigAt) < Self.digCooldown
    }

    /// One control, two meanings: bury during planting, dig during seeking.
    private func duelDig() {
        guard let match, let finger else { return }
        guard !digCoolingDown else { return }
        lastDigAt = Date()

        switch match.phase {
        case .planting:
            guard match.plant(at: finger) else {
                // Outside the legal region — refuse, and say so by feel too.
                Haptics.burst(count: 2, interval: 0.09, tap: .weak)
                flash("TOO CLOSE TO THE EDGE")
                return
            }
            ripples.append(Ripple(point: finger, at: Date(), hard: true))
            Haptics.burst(count: 3, interval: 0.07, tap: .strong)
            link.send(.planted(x: finger.x, y: finger.y))
            if match.canSeek { beginSeeking() }

        case .seeking:
            guard !match.awaitingRuling, !match.isOut else { return }
            // The lead-in exists precisely to absorb this press.
            guard seekArmed else {
                flash("GET READY…")
                return
            }
            ripples.append(Ripple(point: finger, at: Date(), hard: true))
            switch match.dig(at: finger) {
            case .found:
                Haptics.burst(count: 6, interval: 0.05, tap: .strong)
                nextPulseAt = .distantFuture
                if match.isHost {
                    hostConclude(.host)          // I'm the arbiter and I got here first
                } else {
                    link.send(.foundIt)
                }
            case .miss(let remaining):
                Haptics.burst(count: 2, interval: 0.13, tap: .weak)
                flash("MISS — \(remaining) dig\(remaining == 1 ? "" : "s") left")
            case .eliminated:
                // Out of digs: still connected, but the round is no longer
                // winnable for me.
                Haptics.burst(count: 3, interval: 0.12, tap: .strong)
                flash("OUT OF DIGS")
                nextPulseAt = .distantFuture
                if match.isHost {
                    if let verdict = match.eliminationVerdict() { hostConclude(verdict) }
                } else {
                    link.send(.outOfDigs)
                }
            case nil:
                break
            }

        default:
            break
        }
        needsDisplay = true
    }

    private func dig() {
        guard screen == nil, game.phase == .hunting, let finger else { return }
        guard !digCoolingDown else { return }
        lastDigAt = Date()

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

        if mode == .duel, screen == nil {
            drawDuel(in: arena)
            return
        }

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
    private func drawDuel(in arena: NSRect) {
        switch lobby {
        case .hosting(let code):
            var connected = false
            if case .connected = link.status { connected = true }
            DuelRenderer.drawHostLobby(
                code: code, connected: connected, in: arena, copied: codeCopied)
            return
        case .joining:
            DuelRenderer.drawJoinEntry(typed: typedCode, status: lobbyStatus, in: arena)
            return
        case .none:
            break
        }

        guard let match else { return }

        switch match.phase {
        case .planting:
            DuelRenderer.drawPlanting(match: match, finger: finger, in: arena)
            drawRipples(in: arena)
            drawContacts(in: arena)

        case .waitingForOpponent:
            DuelRenderer.drawWaitingForOpponent(myTarget: match.myTarget, in: arena)
            drawContacts(in: arena)

        case .seeking:
            DuelRenderer.drawStandoff(
                myTarget: match.myTarget,
                // Never draw them during the lead-in, whatever arrived.
                opponentFinger: seekArmed ? opponentFinger : nil,
                opponentAge: opponentFingerAt.map { Date().timeIntervalSince($0) },
                in: arena)
            drawRipples(in: arena)
            drawDuelMisses(match: match, in: arena)
            drawContacts(in: arena)
            DuelRenderer.drawSeekingBanner(
                awaitingRuling: match.awaitingRuling,
                isOut: match.isOut,
                leadIn: seekArmedAt.map { $0.timeIntervalSinceNow },
                stillHolding: !probesUnlocked && !contacts.isEmpty,
                in: arena)

        case .roundOver, .matchOver:
            drawDuelMisses(match: match, in: arena)
            DuelRenderer.drawRoundOver(
                match: match, rematchRequested: rematchRequested, in: arena)

        case .disconnected(let reason):
            DuelRenderer.drawDisconnected(reason: reason, in: arena)

        case .lobby:
            break
        }

        DuelRenderer.drawHUD(match: match, in: bounds)
        drawFlash(in: arena)
        if match.phase == .planting || match.phase == .seeking {
            Draw.text("FORCE CLICK OR SPACE — \(match.phase == .planting ? "BURY" : "DIG")"
                      + "          ESC — MENU",
                      at: NSPoint(x: bounds.midX, y: 38), size: 11,
                      color: Draw.Palette.faint, centered: true, tracking: 2)
        }
    }

    private func drawDuelMisses(match: DuelMatch, in arena: NSRect) {
        for miss in match.misses {
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
