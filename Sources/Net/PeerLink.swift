import Foundation

enum LinkStatus: Equatable {
    case idle
    /// Advertising or waiting on a relay; the code is shown to the player.
    case waitingForPeer(code: String)
    case searching(code: String)
    /// Both players are present.
    case connected
    case failed(String)
}

/// How the two machines reach each other. Deliberately narrow, so game code
/// never knows whether the opponent is across the room on Bonjour or across
/// the world through a relay.
protocol PeerLink: AnyObject {
    var status: LinkStatus { get }
    var onStatusChange: ((LinkStatus) -> Void)? { get set }
    var onMessage: ((Message) -> Void)? { get set }

    func host(code: String)
    func join(code: String)
    func send(_ message: Message)
    func stop()
}
