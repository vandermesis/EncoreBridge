import Foundation
import Observation

/// Combines Music playback observations with source format reports for the current track.
///
/// Polling and selected log messages refresh the track. A matching local file
/// takes precedence over a format from Music's quality panel or diagnostic logs.
@MainActor
@Observable
final class MusicLogMonitor {
    enum Status: Equatable {
        case stopped
        case starting
        case monitoring
        case failed(String)
    }

    private(set) var status: Status = .stopped
    private(set) var audioFormat = AudioFormatSnapshot()
    private(set) var currentPlayback: MusicPlaybackSnapshot?
    private(set) var lastPlaybackUpdate: Date?
    private(set) var diagnosticMessages: [String] = []
    var onDiagnosticMessage: ((String) -> Void)?

    private let parser: AudioFormatParser
    private let logService = AppleMusicLogService()
    private let localTrackService: LocalMusicTrackService
    private var localTrackTask: Task<Void, Never>?
    private var localAudioFormat: AudioFormatSnapshot?
    private var trackReports: [AudioFormatSnapshot] = []
    private let qualityService = MusicQualityService()
    private var qualityTask: Task<Void, Never>?
    private var confirmedStreamFormat: AudioFormatSnapshot?
    private var qualityAttempts = 0
    private var lastQualityAttempt = Date.distantPast

    init(parser: AudioFormatParser? = nil, localTrackService: LocalMusicTrackService? = nil) {
        self.parser = parser ?? AudioFormatParser()
        self.localTrackService = localTrackService ?? LocalMusicTrackService()
    }

    var diagnosticLogText: String {
        let snapshot = (try? JSONEncoder().encode(currentPlayback)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        return "CURRENT_PLAYBACK " + snapshot + "\nQUALITY_ACCESS " + String(qualityService.hasReadAccess)
            + "\nSTATUS " + statusText + "\nAUDIO_FORMAT " + String(describing: audioFormat)
            + "\nSYSTEM " + ProcessInfo.processInfo.operatingSystemVersionString
            + "\n\n" + diagnosticMessages.reversed().joined(separator: "\n\n---\n\n")
    }

    var statusText: String {
        switch status {
        case .stopped: "Zatrzymano"
        case .starting: "Uruchamianie…"
        case .monitoring: "Nasłuchiwanie Apple Music"
        case .failed(let message): "Błąd: \(message)"
        }
    }

    /// Starts the log stream and schedules periodic playback observations.
    func start() {
        guard !logService.isRunning else { return }
        status = .starting
        localTrackService.requestAuthorization()
        refreshLocalTrack()
        do {
            try logService.start(
                onMessage: { [weak self] in self?.consume($0) },
                onFailure: { [weak self] in
                    self?.stop()
                    self?.status = .failed($0)
                    self?.appendDiagnostic("Błąd monitorowania: \($0)")
                }
            )
            status = .monitoring
            appendDiagnostic("Monitoring uruchomiony")
            localTrackTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.refreshLocalTrack()
                    do { try await Task.sleep(for: .milliseconds(500)) }
                    catch { return }
                }
            }
        } catch {
            status = .failed(error.localizedDescription)
            appendDiagnostic("Błąd monitorowania: \(error.localizedDescription)")
        }
    }

    /// Stops the stream and cancels polling and quality probes.
    func stop() {
        logService.stop()
        localTrackTask?.cancel()
        localTrackTask = nil
        qualityTask?.cancel()
        qualityTask = nil
        status = .stopped
        appendDiagnostic("Monitoring zatrzymany")
    }

    /// Associates a useful diagnostic message with the current playback observation.
    func consume(_ message: String) {
        // Bind each useful report to Music's current identity, rather than a
        // queue item that may already refer to a prepared, unplayed track.
        let detected = parser.parseActiveAudioFormat(message)
        guard detected != nil || message.contains("mediaFormatinfo")
                || message.contains("item-audio-format-metadata")
                || message.contains("activeFormat:") else { return }
        if status == .monitoring { refreshLocalTrack() }
        let identity = currentPlayback.map { "\($0.id) • \($0.title)" } ?? "Brak utworu"
        appendDiagnostic("[\(identity)]\n\(message)")
        guard let detected, currentPlayback != nil else { return }
        let previous = trackReports.last {
            $0.fileFormat == detected.fileFormat && $0.sampleRate == detected.sampleRate
        }
        trackReports.append(previous.map { detected.fillingMissingValues(from: $0) } ?? detected)
        trackReports = Array(trackReports.suffix(20))
        updateAudioFormat()
    }

    /// Refreshes track identity, clears obsolete reports and schedules quality probes when eligible.
    func refreshLocalTrack() {
        let playback = localTrackService.currentPlayback()
        lastPlaybackUpdate = .now
        let changedTrack = playback?.id != currentPlayback?.id
        let changedRate = playback?.sampleRate != currentPlayback?.sampleRate
        if changedTrack { trackReports.removeAll() }
        if changedTrack || changedRate {
            qualityTask?.cancel()
            qualityTask = nil
            confirmedStreamFormat = nil
            qualityAttempts = 0
            lastQualityAttempt = .distantPast
        }
        currentPlayback = playback
        let format = playback?.fileURL.flatMap { localTrackService.formatForCurrentFile($0) }
        let changedLocalFormat = format != localAudioFormat
        localAudioFormat = format
        if changedTrack || changedRate || changedLocalFormat {
            updateAudioFormat()
            if let playback {
                appendDiagnostic("Bieżący utwór: \(playback.id) • \(playback.title) • \(playback.artist) • \(format != nil ? "plik lokalny" : "stream")")
            }
        }
        if status == .monitoring, let playback, playback.isPlaying, playback.fileURL == nil,
           qualityService.hasReadAccess, confirmedStreamFormat == nil, qualityTask == nil,
           qualityAttempts < 3, Date().timeIntervalSince(lastQualityAttempt) > 3 {
            qualityAttempts += 1
            lastQualityAttempt = Date()
            qualityTask = Task { [weak self] in
                guard let self else { return }
                let result = await qualityService.audioFormat(for: playback)
                guard !Task.isCancelled else { return }
                qualityTask = nil
                guard let result,
                      localTrackService.currentPlayback()?.id == playback.id,
                      currentPlayback?.id == playback.id,
                      currentPlayback?.sampleRate == playback.sampleRate else { return }
                confirmStreamFormat(result)
            }
        }
    }

    func confirmStreamFormat(_ format: AudioFormatSnapshot) {
        confirmedStreamFormat = format
        updateAudioFormat()
        appendDiagnostic("Jakość z panelu Music: \(currentPlayback?.id ?? "—") • \(format)")
    }

    private func updateAudioFormat() {
        guard let currentPlayback else {
            audioFormat = .init()
            return
        }
        var format = localAudioFormat ?? confirmedStreamFormat
            ?? AudioFormatSnapshot(sampleRate: currentPlayback.sampleRate)
        // Only supplement the current source with compatible reports. A later
        // partial report must not erase a known depth, or leak it across codecs.
        if let rate = format.sampleRate {
            let reports = trackReports.filter { $0.sampleRate == rate }
            if localAudioFormat == nil, confirmedStreamFormat == nil,
               let latest = reports.last {
                format = latest
            }
            for report in reports.reversed() {
                format = format.fillingMissingValues(from: report)
            }
        }
        audioFormat = format
    }

    private func appendDiagnostic(_ message: String) {
        let entry = "\(Date.now.formatted(date: .omitted, time: .standard))  \(message)"
        diagnosticMessages.append(entry)
        onDiagnosticMessage?(entry)
        diagnosticMessages = Array(diagnosticMessages.suffix(50))
    }

}
