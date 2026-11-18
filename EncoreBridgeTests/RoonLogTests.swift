import Foundation
import Testing
@testable import EncoreBridge

struct RoonLogTests {
    private let parser = RoonLogParser()
    private let zone = "SHD ROON"
    private var now: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 13, minute: 32, second: 40))!
    }

    @Test func readsVerifiedSourceInsteadOfOutputOrDSP() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([
            file("/Music/Rehab.m4a"), stream(rate: 44100, bits: 16, outputRate: 96000),
            summary("Rehab - Amy Winehouse / Chris Elliott / Isobel Griffiths", format: "Enhanced, 16/44 ALAC => 24/96")
        ], into: &state)
        #expect(state.playback?.title == "Rehab")
        #expect(state.playback?.artist == "Amy Winehouse / Chris Elliott / Isobel Griffiths")
        #expect(state.audioFormat == AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "44.1 kHz", bitDepth: "16-bit"))
        #expect(parser.parse("11/16 13:32:36 Trace: [miniDSP SHD Studio] [raatclient] SENT [1]{\"request\":\"setup\",\"format\":{\"sample_rate\":96000,\"bits_per_sample\":24}}", relativeTo: now) == nil)
    }

    @Test func loadingClearsOldFormatAndQueueingDoesNotChangeIdentity() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([file("/Music/old.m4a"), stream(rate: 96000, bits: 24),
                     summary("Old - Artist", format: "Enhanced, 24/96 ALAC => 24/96")], into: &state)
        try consume([summary("New - Artist", format: "Enhanced, 24/96 ALAC => 24/96", status: "LOADING")], into: &state)
        #expect(state.playback == nil)
        #expect(!state.audioFormat.hasValues)
        #expect(!state.isPlaying)
        try consume(["11/16 13:32:36 Info: [SHD ROON] [zoneplayer] Queueing: /Music/next.m4a"], into: &state)
        #expect(state.playback == nil)
        try consume([file("/Music/new.m4a"), summary("New - Artist", format: "Lossless, 16/44 FLAC => 16/44")], into: &state)
        #expect(state.playback?.title == "New")
        #expect(state.audioFormat.bitDepth == "16-bit")
        #expect(state.audioFormat.sampleRate == nil)
    }

    @Test func unexpectedTrackChangeDoesNotInheritExactRate() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([file("/Music/one.m4a"), stream(rate: 44100, bits: 16), summary("One - Artist")], into: &state)
        try consume([summary("Two - Artist")], into: &state)
        #expect(state.playback?.title == "Two")
        #expect(state.audioFormat.sampleRate == nil)
        #expect(state.playback?.id.contains("one.m4a") == false)
    }

    @Test func gaplessAdvancePromotesQueuedFileOnlyWhenPlaybackAdvances() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([file("/Music/one.m4a"), stream(rate: 44100, bits: 16), summary("One - Artist"),
                     "11/16 13:32:36 Info: [SHD ROON] [zoneplayer] Queueing: /Music/two.m4a"], into: &state)
        #expect(state.playback?.title == "One")
        #expect(state.playback?.id.contains("one.m4a") == true)
        try consume(["11/16 13:32:36 Info: [zone SHD ROON] OnPlayFeedback OnToNext",
                     summary("Two - Other")], into: &state)
        #expect(state.playback?.title == "Two")
        #expect(state.playback?.id.contains("two.m4a") == true)
        #expect(state.audioFormat.sampleRate == "44.1 kHz")
    }

    @Test func ignoresOtherZonesEvenWhenFormatMatches() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([file("/Music/one.m4a"), stream(rate: 44100, bits: 16), summary("One - Artist")], into: &state)
        let other = summary("Other - Someone").replacingOccurrences(of: "[SHD ROON]", with: "[Kitchen]")
        try consume([other], into: &state)
        #expect(state.playback?.title == "One")
    }

    @Test func doesNotInventMissingOrIncompatibleSourceValues() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([stream(rate: 48000, bits: 24), summary("Track - Artist", format: "Lossless, 16/44 ALAC => 24/48")], into: &state)
        #expect(state.audioFormat.sampleRate == nil)
        try consume([summary("Track - Artist", format: "Lossless, ?/44.1 ALAC => 24/48")], into: &state)
        #expect(state.audioFormat.bitDepth == nil)
        #expect(state.audioFormat.sampleRate == "44.1 kHz")
        try consume([summary("Track - Artist", format: "Inactive")], into: &state)
        #expect(!state.audioFormat.hasValues)
    }

    @Test func streamParamsSuppliesRateWithoutInventingLossyDepth() throws {
        var state = RoonPlaybackState(zone: zone)
        let params = "11/16 13:32:36 Trace: [SHD ROON] [zoneplayer/raat] StartStream Roon.Endpoint: StreamParams[SampleRate=44100, BitsPerSample=24, Channels=2, Layout=Stereo FrameCount=15248604] => StreamParams[SampleRate=96000, BitsPerSample=24, Channels=2] streamid=21982447"
        try consume([file("/Music/Whisper.mp3"), params,
                     summary("Whisper [Live in Europe] - Evanescence", format: "LowQuality, 24/44 MP3 => 24/96")], into: &state)
        #expect(state.audioFormat == AudioFormatSnapshot(fileFormat: "MP3", sampleRate: "44.1 kHz"))
        #expect(state.playback?.title == "Whisper [Live in Europe]")
    }

    @Test(arguments: ["PAUSED", "STOPPED"])
    func pauseAndStopInvalidatePlayback(_ status: String) throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([summary("Track - Artist"), summary("Track - Artist", format: "Inactive", status: status)], into: &state)
        #expect(state.playback == nil)
        #expect(!state.audioFormat.hasValues)
        #expect(!state.isPlaying)
    }

    @Test func expiresStalePlaybackAndHandlesNewYear() throws {
        var state = RoonPlaybackState(zone: zone)
        try consume([summary("Track - Artist")], into: &state)
        state.expire(at: now.addingTimeInterval(30))
        #expect(!state.isPlaying)
        let newYear = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 1, second: 2))!
        let line = summary("Track - Artist").replacingOccurrences(of: "11/16 13:32:36", with: "12/31 23:59:59")
        let event = try #require(parser.parse(line, relativeTo: newYear))
        #expect(newYear.timeIntervalSince(event.date) == 3)
    }

    @MainActor @Test func readsAppendsAndPreservesPartialUnicodeLines() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "RoonServer_log.txt")
        let reader = RoonLogFileReader(url: url, zone: zone)
        #expect(try await reader.read(relativeTo: now).available == false)
        let bytes = Data((summary("Żółć - Wykonawca") + "\n").utf8)
        let split = try #require(bytes.firstIndex(of: 0xC5)) + 1
        try bytes.prefix(split).write(to: url)
        #expect(try await reader.read(relativeTo: now).records.isEmpty)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes.dropFirst(split))
        try handle.close()
        let batch = try await reader.read(relativeTo: now)
        #expect(batch.records.count == 1)
        var state = RoonPlaybackState(zone: zone)
        state.consume(try #require(batch.records.first).event)
        #expect(state.playback?.title == "Żółć")
        #expect(try await reader.read(relativeTo: now).records.isEmpty)
    }

    @MainActor @Test func rotationRecoversContextAndDeletionClearsDisplayedRoonData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "RoonServer_log.txt")
        try ([file("/Music/one.m4a"), stream(rate: 44100, bits: 16), summary("One - Artist")].joined(separator: "\n") + "\n").write(to: url, atomically: false, encoding: .utf8)
        let monitor = RoonLogMonitor(logURL: url)
        await monitor.refresh(at: now)
        #expect(monitor.state.audioFormat.sampleRate == "44.1 kHz")
        try FileManager.default.moveItem(at: url, to: directory.appending(path: "RoonServer_log.01.txt"))
        try (summary("One - Artist") + "\n").write(to: url, atomically: false, encoding: .utf8)
        await monitor.refresh(at: now)
        #expect(monitor.state.audioFormat.sampleRate == "44.1 kHz")
        try FileManager.default.removeItem(at: url)
        await monitor.refresh(at: now)
        #expect(monitor.state.playback == nil)
        #expect(monitor.readError != nil)
    }

    @MainActor @Test func simultaneousSourcesRemainIndependentWhenEitherPauses() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "RoonServer_log.txt")
        try ([file("/Music/roon.m4a"), stream(rate: 44100, bits: 16), summary("Roon Track - Roon Artist")].joined(separator: "\n") + "\n").write(to: url, atomically: false, encoding: .utf8)
        var musicTrack = MusicPlaybackSnapshot(id: "music", title: "Music Track", artist: "Music Artist", album: "", sampleRate: "96 kHz", fileURL: nil)
        let music = MusicLogMonitor(localTrackService: LocalMusicTrackService(playbackProvider: { musicTrack }))
        music.refreshLocalTrack()
        music.confirmStreamFormat(AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"))
        let roon = RoonLogMonitor(logURL: url)
        let monitor = PlaybackMonitor(music: music, roon: roon)
        let diagnostics = DiagnosticsModel(monitor: monitor)
        await roon.refresh(at: now)
        #expect(monitor.playingSources.map(\.title) == ["Apple Music", "Roon"])
        #expect(monitor.playingSources.map(\.playback.title) == ["Music Track", "Roon Track"])
        #expect(monitor.playingSources.map(\.audioFormat.bitDepth) == ["24-bit", "16-bit"])
        #expect(monitor.playingSources.map(\.audioFormat.sampleRate) == ["96 kHz", "44.1 kHz"])
        #expect(diagnostics.text.contains("ROON_ZONE SHD ROON"))
        musicTrack.isPlaying = false
        music.refreshLocalTrack()
        #expect(monitor.playingSources.map(\.title) == ["Roon"])
        #expect(monitor.playingSources.first?.audioFormat.bitDepth == "16-bit")
        musicTrack.isPlaying = true
        music.refreshLocalTrack()
        #expect(monitor.playingSources.count == 2)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((summary("Roon Track - Roon Artist", format: "Inactive", status: "PAUSED") + "\n").utf8))
        try handle.close()
        await roon.refresh(at: now)
        #expect(monitor.playingSources.map(\.title) == ["Apple Music"])
        #expect(monitor.playingSources.first?.playback.title == "Music Track")
        #expect(monitor.playingSources.first?.audioFormat.sampleRate == "96 kHz")
        #expect(monitor.playingSources.first?.audioFormat.bitDepth == "24-bit")
        musicTrack.isPlaying = false
        music.refreshLocalTrack()
        #expect(monitor.playingSources.isEmpty)
    }

    private func consume(_ lines: [String], into state: inout RoonPlaybackState) throws {
        for line in lines { state.consume(try #require(parser.parse(line, relativeTo: now))) }
    }

    private func summary(_ label: String, format: String = "Enhanced, 16/44 ALAC => 16/44", status: String = "PLAYING") -> String {
        "11/16 13:32:36 Trace: [SHD ROON] [\(format)] [100% buf] [\(status) @ 0:00] \(label)"
    }

    private func file(_ path: String) -> String {
        "11/16 13:32:36 Info: [SHD ROON] [zoneplayer] Playing: \(path)"
    }

    private func stream(rate: Int, bits: Int, outputRate: Int? = nil) -> String {
        "11/16 13:32:36 Trace: [SHD ROON] [zoneplayer/raat] StartStream Roon.Endpoint: StreamFormat(channels=2, bitspersample=\(bits), samplerate=\(rate), isdts=False) => StreamFormat(channels=2, bitspersample=24, samplerate=\(outputRate ?? rate), isdts=False) streamid=21982448"
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
