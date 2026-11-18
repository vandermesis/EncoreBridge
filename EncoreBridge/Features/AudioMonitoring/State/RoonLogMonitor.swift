import Foundation
import Observation

@MainActor
@Observable
final class RoonLogMonitor {
    private(set) var state: RoonPlaybackState
    private(set) var readError: String?
    private(set) var isRunning = false
    let logURL: URL
    var onDiagnosticMessage: ((String) -> Void)?
    private let reader: RoonLogFileReader
    private var task: Task<Void, Never>?

    init(logURL: URL? = nil, zone: String = "SHD ROON") {
        let url = logURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/RoonServer/Logs/RoonServer_log.txt")
        self.logURL = url
        state = RoonPlaybackState(zone: zone)
        reader = RoonLogFileReader(url: url, zone: zone)
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        onDiagnosticMessage?("Roon: monitoring strefy \(state.zone) • \(logURL.path)")
        task = Task { [weak self] in
            await self?.reader.rewind()
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        state.reset()
        onDiagnosticMessage?("Roon: monitoring zatrzymany")
    }

    func refresh(at now: Date = .now) async {
        do {
            let batch = try await reader.read(relativeTo: now)
            guard !Task.isCancelled else { return }
            if batch.reset { state.reset() }
            setReadError(batch.available ? nil : "Brak pliku logu Roon Server: \(logURL.path)")
            for record in batch.records {
                let before = state.playback
                let beforeFormat = state.audioFormat
                state.consume(record.event)
                // Repeated five-second heartbeats don't crowd out diagnostics.
                if before != state.playback || beforeFormat != state.audioFormat {
                    onDiagnosticMessage?("Roon [\(state.zone)]\n\(record.line)")
                }
            }
            state.expire(at: now)
        } catch {
            guard !Task.isCancelled else { return }
            state.reset()
            setReadError("Błąd odczytu Roon: \(error.localizedDescription)")
        }
    }

    private func setReadError(_ error: String?) {
        guard error != readError else { return }
        readError = error
        onDiagnosticMessage?(error ?? "Roon: odczyt logów dostępny")
    }
}
