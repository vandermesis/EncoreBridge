import Foundation
import Network

@MainActor
final class BridgeHTTPServer {
    nonisolated static let defaultPort: UInt16 = 8765
    private(set) var boundPort: UInt16?
    var onStatusChange: ((String) -> Void)?
    private let port: NWEndpoint.Port
    private let snapshot: @MainActor () -> BridgePlaybackSnapshot
    private var task: Task<Void, Never>?
    private var runID: UUID?
    private var activeRequests = 0

    init(port: UInt16 = defaultPort, snapshot: @escaping @MainActor () -> BridgePlaybackSnapshot) {
        self.port = NWEndpoint.Port(rawValue: port) ?? .any
        self.snapshot = snapshot
    }

    func start() {
        guard task == nil else { return }
        let id = UUID()
        runID = id
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let listener = try NetworkListener(using: .parameters { TCP() }.localPort(port).localOnly(true))
                listener.onStateUpdate { [weak self] listener, state in
                    guard let self, runID == id else { return }
                    switch state {
                    case .ready:
                        boundPort = listener.port?.rawValue
                        onStatusChange?("HTTP: http://\(ProcessInfo.processInfo.hostName):\(boundPort ?? port.rawValue)/v1/now-playing")
                    case .waiting(let error):
                        boundPort = nil
                        onStatusChange?("HTTP: oczekiwanie — \(error)")
                    default: break
                    }
                }
                try await listener.run { [weak self] connection in
                    guard let self else { return }
                    guard activeRequests < 16 else { return }
                    activeRequests += 1
                    defer { activeRequests -= 1 }
                    // A client failure must never terminate the listener or
                    // leave an incomplete request occupying a connection forever.
                    do { try await serve(connection) }
                    catch { }
                }
            } catch {
                if !Task.isCancelled, runID == id {
                    onStatusChange?("HTTP: błąd — \(error.localizedDescription)")
                }
            }
            if runID == id {
                boundPort = nil
                task = nil
                runID = nil
            }
        }
    }

    func stop() {
        runID = nil
        task?.cancel()
        task = nil
        boundPort = nil
        onStatusChange?("HTTP: zatrzymano")
    }

    private func serve(_ connection: NetworkConnection<TCP>) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [self] in
                var request = Data()
                let terminator = Data("\r\n\r\n".utf8)
                while request.range(of: terminator) == nil {
                    guard request.count < 8192 else {
                        try await connection.send(BridgeHTTPResponse.error(431, "Request Header Fields Too Large", "headers_too_large").data, endOfStream: true)
                        return
                    }
                    let chunk = try await connection.receive(atLeast: 1, atMost: min(4096, 8192 - request.count)).content
                    guard !chunk.isEmpty else { return }
                    request.append(chunk)
                }
                let response = try BridgeHTTPResponse.make(request: request, snapshot: snapshot())
                try await connection.send(response.data, endOfStream: true)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw RequestTimeout()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private struct RequestTimeout: Error { }
}
