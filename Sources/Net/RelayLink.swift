import Foundation

/// Where the Cloudflare relay lives. Override at runtime for local testing:
///   ECHO_HUNT_RELAY=ws://localhost:8787 ./build/EchoHunt.app/Contents/MacOS/EchoHunt
enum RelayConfig {
    /// Replace YOUR-SUBDOMAIN with what `wrangler deploy` prints. Until then
    /// the online options report themselves as unconfigured rather than
    /// failing with a confusing network error.
    static let defaultURL = "wss://echo-hunt-relay.YOUR-SUBDOMAIN.workers.dev"

    static var baseURL: String {
        ProcessInfo.processInfo.environment["ECHO_HUNT_RELAY"] ?? defaultURL
    }

    static var isConfigured: Bool {
        !baseURL.contains("YOUR-SUBDOMAIN")
    }
}

/// Plays over the internet through the Cloudflare relay.
///
/// The relay only shuffles opaque frames between two sockets, so the same
/// messages that cross a Bonjour connection cross this one unchanged — and
/// because the game computes its sonar locally, a slow relay delays the start
/// of a round without ever touching how it feels.
final class RelayLink: NSObject, PeerLink {
    private(set) var status: LinkStatus = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    var onStatusChange: ((LinkStatus) -> Void)?
    var onMessage: ((Message) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var keepAlive: Timer?
    private var code: String?

    func host(code: String) {
        connect(code: code, role: "host")
    }

    func join(code: String) {
        connect(code: code, role: "guest")
        status = .searching(code: code)
    }

    private func connect(code: String, role: String) {
        stop()
        self.code = code

        guard RelayConfig.isConfigured else {
            status = .failed("Relay not configured — deploy the worker first.")
            return
        }
        guard let url = URL(string: "\(RelayConfig.baseURL)/lobby/\(code)?role=\(role)") else {
            status = .failed("Bad relay URL")
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        receive()

        if role == "host" { status = .waitingForPeer(code: code) }

        // Cloudflare drops idle sockets; a round can easily be quiet for
        // longer than that while someone hunts.
        let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in
            self?.task?.sendPing { _ in }
        }
        RunLoop.main.add(timer, forMode: .common)
        keepAlive = timer
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let data: Data?
                switch message {
                case .string(let text): data = text.data(using: .utf8)
                case .data(let raw): data = raw
                @unknown default: data = nil
                }
                if let data, let decoded = try? JSONDecoder().decode(Message.self, from: data) {
                    self.handle(decoded)
                }
                self.receive()
            case .failure(let error):
                // A rejected upgrade (bad code, lobby full) surfaces here.
                self.status = .failed(self.describe(error))
                self.teardown()
            }
        }
    }

    /// Relay-level frames never reach the game; they become status changes.
    private func handle(_ message: Message) {
        switch message {
        case .peerJoined:
            status = .connected
        case .peerLeft:
            status = .failed("Opponent left the match")
            teardown()
        default:
            onMessage?(message)
        }
    }

    private func describe(_ error: Error) -> String {
        // A rejected upgrade arrives as a generic transport error; the useful
        // detail is the HTTP status hanging off the task's response.
        if let response = task?.response as? HTTPURLResponse {
            switch response.statusCode {
            case 404: return "No lobby found with code \(code ?? "")"
            case 409: return "That lobby code is already in use"
            case 426, 400: return "Relay rejected the connection"
            default: break
            }
        }
        return "Connection lost: \((error as NSError).localizedDescription)"
    }

    func send(_ message: Message) {
        guard let task, let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
    }

    private func teardown() {
        keepAlive?.invalidate()
        keepAlive = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func stop() {
        teardown()
        status = .idle
    }
}

extension RelayLink: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?
    ) {
        // Only meaningful if we hadn't already failed for a better reason.
        if case .failed = status { return }
        status = .failed("Disconnected from the relay")
        teardown()
    }
}
