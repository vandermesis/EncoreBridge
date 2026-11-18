import Testing
import AVFoundation
@testable import EncoreBridge

struct EncoreBridgeTests {
    private let parser = AudioFormatParser()

    @Test(arguments: ["Hi-Res Lossless 24-bit 96 kHz ALAC", "Hi-Res Lossless 96kHz ALAC", "24-bit 96,0 kHz ALAC"])
    func parsesDisplayedMusicQuality(_ label: String) throws {
        let format = try #require(parser.parseQualityLabel(label))
        #expect(format.sampleRate == "96 kHz")
        #expect(format.fileFormat == "ALAC")
    }

    @Test func qualityLabelDoesNotInventDetails() throws {
        #expect(parser.parseQualityLabel("Hi-Res Lossless") == nil)
        #expect(parser.parseQualityLabel("96 kHz") == nil)
        let format = try #require(parser.parseQualityLabel("96kHz ALAC"))
        #expect(format.bitDepth == nil)
    }

    @MainActor @Test func partialReportKeepsPreviouslyReadBitDepth() {
        let playback = MusicPlaybackSnapshot(id: "current", title: "Track", artist: "Artist", album: "Album", sampleRate: "96 kHz", fileURL: nil)
        let monitor = MusicLogMonitor(localTrackService: LocalMusicTrackService(playbackProvider: { playback }))
        monitor.refreshLocalTrack()
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz")
        for _ in 0..<25 {
            monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, asbdSampleRate = 96.0 kHz")
        }
        #expect(monitor.audioFormat.bitDepth == "24-bit")
    }

    @MainActor @Test func logDepthSupplementsMusicQualityBeforeAndAfterConfirmation() {
        let playback = MusicPlaybackSnapshot(id: "current", title: "Track", artist: "Artist", album: "Album", sampleRate: "96 kHz", fileURL: nil)
        let monitor = MusicLogMonitor(localTrackService: LocalMusicTrackService(playbackProvider: { playback }))
        monitor.refreshLocalTrack()
        monitor.confirmStreamFormat(AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz"))
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz")
        #expect(monitor.audioFormat.bitDepth == "24-bit")
        monitor.confirmStreamFormat(AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz"))
        #expect(monitor.audioFormat.bitDepth == "24-bit")
        monitor.confirmStreamFormat(AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "16-bit"))
        #expect(monitor.audioFormat.bitDepth == "16-bit")
    }

    @MainActor @Test func conflictingCodecOrRateDoesNotSupplyDepth() {
        let playback = MusicPlaybackSnapshot(id: "current", title: "Track", artist: "Artist", album: "Album", sampleRate: "48 kHz", fileURL: nil)
        let monitor = MusicLogMonitor(localTrackService: LocalMusicTrackService(playbackProvider: { playback }))
        monitor.refreshLocalTrack()
        monitor.confirmStreamFormat(AudioFormatSnapshot(fileFormat: "AAC", sampleRate: "48 kHz"))
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 48.0 kHz")
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = aac, sdBitDepth = 16 bit, asbdSampleRate = 44.1 kHz")
        #expect(monitor.audioFormat == AudioFormatSnapshot(fileFormat: "AAC", sampleRate: "48 kHz"))
    }

    @Test func readsExplicitDepthWithoutVariantDescriptor() throws {
        let message = #"item-audio-format-metadata "active-format" = { bd = 24; codec = 1634492771; sr = 96000; };"#
        #expect(parser.parseActiveAudioFormat(message) == AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"))
    }

    @Test func explicitDepthIgnoresUnavailableAndDecoderDepth() throws {
        let message = #"item-audio-format-metadata "active-format" = { bd = 0; codec = 1633772320; sr = 44100; }; "available-format" = { bd = 24; };"#
        #expect(try #require(parser.parseActiveAudioFormat(message)).bitDepth == nil)
        #expect(try #require(parser.parsePlaybackFormat("play> cm>> mediaFormatinfo sdFormatID = aac, asbdBitDepth = 32 bit, asbdSampleRate = 44.1 kHz")).bitDepth == nil)
    }

    @Test func variantSuppliesDepthWhenMetadataOmitsIt() throws {
        let message = #"item-audio-format-metadata "active-format" = { codec = 1634492771; sr = 96000; grp = "audio-alac-stereo-96000-24"; };"#
        #expect(try #require(parser.parseActiveAudioFormat(message)).bitDepth == "24-bit")
        let explicit = "activeFormat: groupID: current; codec: alac; bitDepth: 24-bit; sampleRate: 96khz"
        #expect(parser.parseActiveAudioFormat(explicit) == AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"))
    }

    @MainActor @Test func reportArrivingBeforeCurrentRateIsPreservedForSameIdentity() {
        var playback = MusicPlaybackSnapshot(id: "track", title: "Track", artist: "Artist", album: "Album", sampleRate: nil, fileURL: nil)
        let monitor = MusicLogMonitor(localTrackService: LocalMusicTrackService(playbackProvider: { playback }))
        monitor.refreshLocalTrack()
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz")
        playback = MusicPlaybackSnapshot(id: "track", title: "Track", artist: "Artist", album: "Album", sampleRate: "96 kHz", fileURL: nil)
        monitor.refreshLocalTrack()
        #expect(monitor.audioFormat.bitDepth == "24-bit")
        #expect(monitor.audioFormat.fileFormat == "ALAC")
    }


    @MainActor @Test func currentLocalFileWinsOverPrefetchedStreamAndClearsOnExit() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var currentURL: URL? = directory.appending(path: "track.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            let output = try AVAudioFile(forWriting: currentURL!, settings: settings)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 32))
            buffer.frameLength = 32
            try output.write(from: buffer)
        }
        let service = LocalMusicTrackService(trackURLProvider: { currentURL })
        let monitor = MusicLogMonitor(localTrackService: service)
        monitor.refreshLocalTrack()
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 192.0 kHz")
        #expect(monitor.audioFormat == AudioFormatSnapshot(fileFormat: "WAV", sampleRate: "44.1 kHz", bitDepth: "16-bit"))
        currentURL = nil
        monitor.refreshLocalTrack()
        #expect(!monitor.audioFormat.hasValues)
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz")
        #expect(!monitor.audioFormat.hasValues)
    }

    @MainActor @Test func downloadedDRMPackageSelectsStoredVariantAndRejectsAmbiguity() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".movpkg")
        try FileManager.default.createDirectory(at: directory.appending(path: "Data"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let boot = directory.appending(path: "boot.xml")
        try "<HLSMoviePackage><Streams><Stream UniqueTag=\"stored\"><Complete>YES</Complete></Stream></Streams></HLSMoviePackage>".write(to: boot, atomically: true, encoding: .utf8)
        try """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="cd",SAMPLE-RATE=44100,BIT-DEPTH=16
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="hires",SAMPLE-RATE=192000,BIT-DEPTH=24
        #EXT-X-STREAM-INF:CODECS="alac",STABLE-VARIANT-ID="available",AUDIO="hires"
        unused.m3u8
        #EXT-X-STREAM-INF:CODECS="alac",STABLE-VARIANT-ID="stored",AUDIO="cd"
        stored.m3u8
        """.write(to: directory.appending(path: "Data/master.m3u8"), atomically: true, encoding: .utf8)
        let service = LocalMusicTrackService()
        #expect(try service.audioFormat(at: directory) == AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "44.1 kHz", bitDepth: "16-bit"))
        try "<HLSMoviePackage><Streams><Stream UniqueTag=\"stored\"><Complete>YES</Complete></Stream><Stream UniqueTag=\"available\"><Complete>YES</Complete></Stream></Streams></HLSMoviePackage>".write(to: boot, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try service.audioFormat(at: directory) }
    }

    @Test func parsesMusicPlaybackSourceInsteadOfDecoderFormat() throws {
        let format = try #require(parser.parsePlaybackFormat(
            "play> cm>> mediaFormatinfo '<private>', asbdFormatID = qlac, sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz"
        ))
        #expect(format.fileFormat == "ALAC")
        #expect(format.sampleRate == "96 kHz")
        #expect(format.bitDepth == "24-bit")
    }

    @Test func playbackReportDoesNotInventMissingDepthOrCodec() throws {
        let format = try #require(parser.parsePlaybackFormat(
            "play> cm>> mediaFormatinfo '<private>', sdFormatID = aac, asbdSampleRate = 44.1 kHz"
        ))
        #expect(format.sampleRate == "44.1 kHz")
        #expect(format.bitDepth == nil)
        #expect(parser.parsePlaybackFormat(
            "play> cm>> mediaFormatinfo '<private>', asbdFormatID = qlac, asbdSampleRate = 96.0 kHz"
        ) == nil)
    }

    @Test func parsesAppleMusicAudioFormatMetadata() throws {
        let message = """
        event.id=3F95621C-6DCC-4F9C-B851-13E02F5E3D8A payload={
            "item-audio-format-metadata" = {
                "active-format" = {
                    bd = 16;
                    br = 0;
                    chlayd = Stereo;
                    codec = 1634492771;
                    grp = "audio-alac-stereo-44100-16";
                    sr = 44100;
                };
            };
            "queue-item-id" = 104861;
            "queue-section-id" = 104751;
        }
        """

        let event = try #require(parser.parseEvent(message))

        #expect(event.queueItemID == 104861)
        #expect(event.audioFormat.fileFormat == "ALAC")
        #expect(event.audioFormat.sampleRate == "44.1 kHz")
        #expect(event.audioFormat.bitDepth == "16-bit")
    }

    @Test func ignoresOtherAppleMusicLogs() {
        let message = "AudioQueue scheduling rationale at 44100 Hz, ALAC, 16-bit"

        #expect(parser.parseEvent(message) == nil)
    }

    @Test func incompleteMetadataStillIdentifiesChangedTrack() {
        let message = """
        item-audio-format-metadata
        active-format-justification = 100;
        "queue-item-id" = 112424;
        """

        #expect(parser.queueItemID(in: message) == 112424)
        #expect(parser.parseEvent(message) == nil)
    }

    @Test func parsesHiResDescriptorFromSeparateLogEntry() throws {
        let format = try #require(
            parser.parseActiveAudioFormat(
                "fpfs_StartTrackPlaying: desiredRate is 1.000000 rate 0.000000 track 1 Variant [AudioGroup audio-alac-stereo-192000-24]"
            )
        )

        #expect(format.fileFormat == "ALAC")
        #expect(format.sampleRate == "192 kHz")
        #expect(format.bitDepth == "24-bit")
    }

    @Test func ignoresAvailableAndPendingVariants() {
        let availableVariants = """
        HLS-FASB AudioGroup audio-alac-stereo-48000-24
        AudioGroup audio-alac-stereo-96000-24
        """
        let pendingSwitch = """
        fpfs_ReportVariantSwitchStart: starting switch up to
        AudioGroup audio-alac-stereo-96000-24
        """

        #expect(parser.parseActiveAudioFormat(availableVariants) == nil)
        #expect(parser.parseActiveAudioFormat(pendingSwitch) == nil)
    }

    @Test func ignoresPreparedVariantWithZeroDesiredRate() {
        let message = """
        fpfs_StartTrackPlaying: desiredRate is 0.000000 rate 0.000000 track 1
        Variant [AudioGroup audio-alac-stereo-96000-24]
        """

        #expect(parser.parseActiveAudioFormat(message) == nil)
    }

    @Test func parsesExplicitActiveFormatReport() throws {
        let message = """
        activeFormat: tier: HighResolutionLossless;
        groupID: audio-alac-stereo-88200-24;
        bitDepth: 24-bit; sampleRate: 88.2khz
        """

        let format = try #require(parser.parseActiveAudioFormat(message))

        #expect(format.sampleRate == "88.2 kHz")
        #expect(format.bitDepth == "24-bit")
    }

    @Test func rejectsMetadataWithInvalidSampleRate() {
        let message = """
        item-audio-format-metadata active-format
        bd = 16; grp = "audio-alac-stereo"; sr = 4;
        queue-item-id = 104861;
        """

        #expect(parser.parseEvent(message) == nil)
    }

    @Test func parsesAACMetadataWithoutSampleRateOrBitDepth() throws {
        let message = """
        item-audio-format-metadata
        "active-format" = {
            bd = 0;
            br = 256000;
            codec = 1633772320;
            grp = "audio-stereo-256";
            sr = 0;
        };
        queue-item-id = 117501;
        """

        let event = try #require(parser.parseEvent(message))

        #expect(event.audioFormat.fileFormat == "AAC")
        #expect(event.audioFormat.sampleRate == nil)
        #expect(event.audioFormat.bitDepth == nil)
    }

    @Test func distinguishesTracksByQueueItemIdentifier() throws {
        let first = try #require(parser.parseEvent(metadata(queueItemID: 100)))
        let second = try #require(parser.parseEvent(metadata(queueItemID: 101)))

        #expect(first.queueItemID != second.queueItemID)
        #expect(first.audioFormat == second.audioFormat)
    }

    @MainActor @Test func trackIdentityResetsFormatEvenWhenSampleRateIsUnchanged() {
        var playback = MusicPlaybackSnapshot(id: "first", title: "First", artist: "Artist", album: "Album", sampleRate: "96 kHz", fileURL: nil)
        let service = LocalMusicTrackService(playbackProvider: { playback })
        let monitor = MusicLogMonitor(localTrackService: service)
        monitor.refreshLocalTrack()
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz")
        #expect(monitor.audioFormat.bitDepth == "24-bit")
        playback = MusicPlaybackSnapshot(id: "second", title: "Second", artist: "Other", album: "Album", sampleRate: "96 kHz", fileURL: nil)
        monitor.refreshLocalTrack()
        #expect(monitor.currentPlayback?.title == "Second")
        #expect(monitor.audioFormat.fileFormat == nil)
        #expect(monitor.audioFormat.bitDepth == nil)
        #expect(monitor.audioFormat.sampleRate == "96 kHz")
    }

    @MainActor @Test func rejectsPrefetchedFormatThatDiffersFromCurrentTrackRate() {
        let playback = MusicPlaybackSnapshot(id: "current", title: "Dancing in the Dark", artist: "Diana Krall", album: "The Look of Love", sampleRate: "96 kHz", fileURL: nil)
        let monitor = MusicLogMonitor(localTrackService: LocalMusicTrackService(playbackProvider: { playback }))
        monitor.refreshLocalTrack()
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 96.0 kHz")
        monitor.consume("play> cm>> mediaFormatinfo '<private>', sdFormatID = alac, sdBitDepth = 24 bit, asbdSampleRate = 192.0 kHz")
        #expect(monitor.audioFormat == AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"))
    }

    private func metadata(queueItemID: Int) -> String {
        """
        item-audio-format-metadata
        "active-format" = {
            bd = 24;
            grp = "audio-alac-stereo-96000-24";
            sr = 96000;
        };
        queue-item-id = \(queueItemID);
        """
    }
}
