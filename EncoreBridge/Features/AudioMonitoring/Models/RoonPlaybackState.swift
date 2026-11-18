import Foundation

/// Source metadata for one Roon zone. Output and DSP formats never enter this state.
nonisolated struct RoonPlaybackState: Sendable {
    let zone: String
    private(set) var playback: MusicPlaybackSnapshot?
    private(set) var audioFormat = AudioFormatSnapshot()
    private(set) var isPlaying = false
    private(set) var lastPlayingReport: Date?
    private var fileID: String?
    private var queuedFileID: String?
    private var stream: RoonLogParser.Stream?
    private var pendingTrackLabel: String?

    mutating func consume(_ event: RoonLogParser.Event) {
        guard event.zone == zone else { return }
        switch event.payload {
        case .queuedFile(let path):
            queuedFileID = path
        case .advance:
            // OnToNext explicitly confirms a gapless transition. Queueing on
            // its own never changes the display. The continuous stream may be
            // reused, but its precision still has to match the new source summary.
            fileID = queuedFileID
            queuedFileID = nil
            playback = nil
            audioFormat = .init()
            isPlaying = false
            lastPlayingReport = nil
            pendingTrackLabel = nil
        case .file(let path):
            if fileID != path {
                stream = nil
                audioFormat = .init()
                playback = nil
                isPlaying = false
                lastPlayingReport = nil
            }
            fileID = path
        case .stream(let value):
            stream = value
        case .summary(let summary):
            let label = summary.trackLabel
            if summary.state != "PLAYING" {
                reset()
                pendingTrackLabel = summary.state == "LOADING" ? label : nil
                return
            }
            // If we missed a transition, metadata from the previous stream is
            // unsafe even when the next track has the same sample rate.
            if pendingTrackLabel != nil && pendingTrackLabel != label {
                fileID = nil
                stream = nil
            } else if pendingTrackLabel == nil, let playback,
                      label != "\(playback.title) - \(playback.artist)" {
                fileID = nil
                stream = nil
            }
            pendingTrackLabel = nil
            guard let separator = label.range(of: " - ", options: .backwards) else {
                reset()
                return
            }
            let title = String(label[..<separator.lowerBound])
            let artist = String(label[separator.upperBound...])
            guard !title.isEmpty, !artist.isEmpty else { reset(); return }
            let format = summary.sourceFormat(matching: stream)
            playback = MusicPlaybackSnapshot(id: "roon:\(zone):\(fileID ?? label)", title: title,
                                             artist: artist, album: "", sampleRate: format.sampleRate,
                                             fileURL: nil)
            audioFormat = format
            isPlaying = true
            lastPlayingReport = event.date
        }
    }

    mutating func expire(at date: Date) {
        guard let lastPlayingReport, date.timeIntervalSince(lastPlayingReport) > 20
                || lastPlayingReport.timeIntervalSince(date) > 5 else { return }
        reset()
    }

    mutating func reset() {
        playback = nil
        audioFormat = .init()
        isPlaying = false
        lastPlayingReport = nil
        fileID = nil
        queuedFileID = nil
        stream = nil
        pendingTrackLabel = nil
    }
}
