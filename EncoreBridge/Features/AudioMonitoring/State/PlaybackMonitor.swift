import Foundation
import Observation

/// Presents each playing source independently, without selecting a preferred source.
@MainActor
@Observable
final class PlaybackMonitor {
    let music: MusicLogMonitor
    let roon: RoonLogMonitor
    private(set) var isMonitoring = false

    init(music: MusicLogMonitor? = nil, roon: RoonLogMonitor? = nil) {
        self.music = music ?? MusicLogMonitor()
        self.roon = roon ?? RoonLogMonitor()
    }

    /// Returns the playback sections whose sources report active playback.
    var playingSources: [PlaybackSourceSnapshot] {
        var sources: [PlaybackSourceSnapshot] = []
        if let playback = music.currentPlayback, playback.isPlaying {
            sources.append(PlaybackSourceSnapshot(id: "appleMusic", title: "Apple Music",
                                                  playback: playback, audioFormat: music.audioFormat))
        }
        if roon.state.isPlaying, let playback = roon.state.playback {
            sources.append(PlaybackSourceSnapshot(id: "roon", title: "Roon",
                                                  playback: playback, audioFormat: roon.state.audioFormat))
        }
        return sources
    }

    var status: MusicLogMonitor.Status {
        guard isMonitoring else { return .stopped }
        return roon.isRunning ? .monitoring : music.status
    }

    var statusText: String {
        guard isMonitoring else { return "Zatrzymano" }
        if case .failed = music.status { return "Roon • \(music.statusText)" }
        return "Nasłuchiwanie Apple Music i Roon"
    }

    /// Captures source state without choosing a transport or applying a client's TTL.
    var snapshot: PlaybackMonitoringSnapshot {
        PlaybackMonitoringSnapshot(isMonitoring: isMonitoring,
            appleMusic: .init(playback: music.currentPlayback, audioFormat: music.audioFormat,
                              observedAt: music.lastPlaybackUpdate, isAvailable: music.status == .monitoring),
            roon: .init(playback: roon.state.playback, audioFormat: roon.state.audioFormat,
                        observedAt: roon.state.lastPlayingReport,
                        isAvailable: roon.isRunning && roon.state.isPlaying, zone: roon.state.zone))
    }

    /// Starts both sources once per monitoring session.
    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        music.start()
        roon.start()
    }

    /// Stops both sources and clears the monitoring flag used by the HTTP snapshot.
    func stop() {
        music.stop()
        roon.stop()
        isMonitoring = false
    }

}
