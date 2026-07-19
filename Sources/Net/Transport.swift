import Foundation
import Network

/// Peer-to-peer link between the two players. No server exists anywhere: the
/// host advertises a Bonjour service whose *instance name is the lobby code*,
/// and the guest browses for exactly that name. Discovery and connection both
/// happen on the local network, or over direct peer-to-peer Wi-Fi.
final class Transport {
    enum Status: Equatable {
        case idle
        case hosting(code: String)
        case searching(code: String)
        case connected
        case failed(String)
    }

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    var onStatusChange: ((Status) -> Void)?
    var onMessage: ((Message) -> Void)?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var inbound = Data()

    private static let serviceType = "_echohunt._tcp"

    private static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        let parameters = NWParameters(tls: nil, tcp: tcp)
        // Lets two Macs talk over direct peer-to-peer Wi-Fi with no shared
        // router — useful on a café network that blocks client isolation.
        parameters.includePeerToPeer = true
        return parameters
    }

    // MARK: - Hosting

    func host(code: String) {
        stop()
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = NWListener.Service(name: code, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                // First peer wins; stop advertising so a third machine can't
                // wander into the match.
                if self.connection != nil {
                    connection.cancel()
                    return
                }
                self.listener?.cancel()
                self.listener = nil
                self.adopt(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    if case .failed(let error) = state {
                        self?.status = .failed("Could not host: \(error.localizedDescription)")
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            status = .hosting(code: code)
        } catch {
            status = .failed("Could not host: \(error.localizedDescription)")
        }
    }

    // MARK: - Joining

    func join(code: String) {
        stop()
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: Self.parameters())

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.connection == nil else { return }
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint else { continue }
                guard name.caseInsensitiveCompare(code) == .orderedSame else { continue }
                self.browser?.cancel()
                self.browser = nil
                self.adopt(NWConnection(to: result.endpoint, using: Self.parameters()))
                return
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                if case .failed(let error) = state {
                    self?.status = .failed("Search failed: \(error.localizedDescription)")
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        status = .searching(code: code)

        // Bonjour never reports "that name doesn't exist" — it just keeps
        // looking. Without this, a typo'd code hangs on the search screen
        // forever with no explanation.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.searchTimeout) { [weak self] in
            guard let self, case .searching(let searching) = self.status, searching == code
            else { return }
            self.stop()
            self.status = .failed("No lobby found with code \(code)")
        }
    }

    private static let searchTimeout: TimeInterval = 20

    // MARK: - Connection

    private func adopt(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.status = .connected
                self.receive()
            case .failed(let error):
                self.status = .failed(error.localizedDescription)
                self.teardownConnection()
            case .cancelled:
                self.teardownConnection()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.inbound.append(data)
                for message in Framing.drain(&self.inbound) {
                    self.onMessage?(message)
                }
            }
            if isComplete || error != nil {
                self.status = .failed("Opponent disconnected")
                self.teardownConnection()
                return
            }
            self.receive()
        }
    }

    func send(_ message: Message) {
        guard let connection, let frame = try? Framing.encode(message) else { return }
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func teardownConnection() {
        connection?.cancel()
        connection = nil
        inbound.removeAll()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        teardownConnection()
        status = .idle
    }
}
