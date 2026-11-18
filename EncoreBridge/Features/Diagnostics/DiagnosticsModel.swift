import AppKit
import Observation

/// Collects source diagnostics and exports them for the UI and the clipboard.
///
/// This model owns the sources' diagnostic callbacks. It must be retained for the
/// application lifetime, rather than created whenever the logs window appears.
@MainActor
@Observable
final class DiagnosticsModel {
    let monitor: PlaybackMonitor
    private(set) var messages: [String] = []
    private(set) var serverStatus = "Nie uruchomiono"

    init(monitor: PlaybackMonitor) {
        self.monitor = monitor
        monitor.music.onDiagnosticMessage = { [weak self] in self?.append($0) }
        monitor.roon.onDiagnosticMessage = { [weak self] in
            self?.append("\(Date.now.formatted(date: .omitted, time: .standard))  \($0)")
        }
    }

    /// Local diagnostics may contain paths; this text is never part of the LAN API.
    var text: String {
        let music = monitor.music
        let roon = monitor.roon
        let musicPlayback = (try? JSONEncoder().encode(music.currentPlayback)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        let roonPlayback = (try? JSONEncoder().encode(roon.state.playback)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return "ACTIVE_SOURCES \(monitor.playingSources.map(\.title).joined(separator: ", "))"
            + "\nAPPLE_MUSIC_PLAYBACK \(musicPlayback)\nAPPLE_MUSIC_AUDIO_FORMAT \(music.audioFormat)"
            + "\nROON_PLAYBACK \(roonPlayback)\nROON_PLAYING \(roon.state.isPlaying)\nROON_AUDIO_FORMAT \(roon.state.audioFormat)"
            + "\nSTATUS \(monitor.statusText)\nHTTP_SERVER \(serverStatus)\nROON_ZONE \(roon.state.zone)\nROON_LOG \(roon.logURL.path)"
            + "\nROON_ERROR \(roon.readError ?? "none")\n\n"
            + messages.reversed().joined(separator: "\n\n---\n\n")
            + "\n\n--- APPLE MUSIC ---\n" + music.diagnosticLogText
    }

    func recordServerStatus(_ status: String) {
        serverStatus = status
        append("\(Date.now.formatted(date: .omitted, time: .standard))  \(status)")
    }

    func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func append(_ message: String) {
        messages.append(message)
        messages = Array(messages.suffix(50))
    }
}
