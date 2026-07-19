import Foundation

/// Everything the two machines say to each other.
///
/// Note what is *absent*: there is no per-frame traffic. Coordinates cross the
/// wire once per round, at planting time, and from then on each machine
/// computes its own sonar locally. Network latency therefore cannot reach the
/// haptics — a laggy connection delays the start of a round, never the feel of
/// it.
enum Message: Codable {
    /// Version handshake. Mismatched builds refuse each other rather than
    /// desyncing in some subtler way later.
    case hello(protocolVersion: Int, playerName: String)

    /// "My target is buried, here it is." Sent once per round. The receiver
    /// hunts this point.
    case planted(x: Double, y: Double)

    /// Where my finger is, while seeking. Purely cosmetic: it lets each
    /// player watch the other grope around the target they buried. Throttled,
    /// and never in the haptic path — if these arrive late or not at all, the
    /// game still plays identically.
    case probe(x: Double, y: Double)

    /// Guest claiming a find. The host arbitrates.
    case foundIt

    /// "I've burned both my digs." The host folds this into its ruling.
    case outOfDigs

    /// "I just jammed you." The receiver's sonar goes to noise for a few
    /// seconds. Carries no timing — the jammed machine runs its own clock, so
    /// a laggy link can't lengthen or shorten the effect.
    case jam

    /// Host's ruling on the round, plus the authoritative running score.
    ///
    /// Deliberately carries no coordinates. Each machine already holds the
    /// target it was hunting, and they are *different* targets — shipping one
    /// across only invites the receiver to reveal the wrong point.
    case roundResult(winner: RoundWinner, hostScore: Int, guestScore: Int)

    /// Host starting the next round; both sides return to planting.
    case nextRound(round: Int)

    /// Guest asking for a rematch. Only the host can actually start one, so
    /// this is a request rather than an action.
    case rematchRequest

    /// Host wiping the score and starting over. Keeps the connection, so
    /// nobody has to trade a lobby code again.
    case restartMatch(round: Int)

    case bye

    /// Injected by the relay, never by a player: the other side arrived, or
    /// vanished. The Bonjour link derives the same facts from its connection
    /// state, so game code sees one story either way.
    case peerJoined
    case peerLeft

    static let currentVersion = 1
}

/// Length-prefixed JSON framing. TCP is a byte stream, so without an explicit
/// length a single read can deliver half a message or three at once.
enum Framing {
    static func encode(_ message: Message) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }

    /// Pulls as many whole messages as `buffer` currently holds, leaving any
    /// partial tail in place.
    static func drain(_ buffer: inout Data) -> [Message] {
        var messages: [Message] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            let payload = buffer.subdata(in: 4..<total)
            buffer.removeSubrange(0..<total)
            if let message = try? JSONDecoder().decode(Message.self, from: payload) {
                messages.append(message)
            }
            // A frame that fails to decode is dropped rather than killing the
            // connection: a newer peer may send something we don't know yet.
        }
        return messages
    }
}

/// Short, unambiguous lobby codes. No O/0, I/1, or similar — these get read
/// aloud and retyped.
enum LobbyCode {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 5

    static func generate() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Accepts sloppy input: lowercase, spaces, dashes.
    static func normalize(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    static func isComplete(_ code: String) -> Bool {
        code.count == length
    }
}
