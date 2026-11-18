import Foundation
import Testing
@testable import EncoreBridge

struct EncoreSnapshotMapperTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func appliesDifferentFreshnessWindowsWithoutChangingObservations() {
        let input = snapshot(age: 4)
        let result = EncoreSnapshotMapper().map(input, at: now)
        #expect(result.sources["apple_music"]?.playing == false)
        #expect(result.sources["apple_music"]?.title == nil)
        #expect(result.sources["roon"]?.playing == true)
        #expect(result.sources["roon"]?.title == "Track")
        #expect(result.sources["roon"]?.zone == "SHD ROON")
        #expect(input.appleMusic.playback?.title == "Track")
        #expect(input.appleMusic.observedAt == now.addingTimeInterval(-4))
    }

    @Test(arguments: [false, true])
    func stoppedOrUnavailableMonitoringDoesNotPublishRetainedMetadata(stopped: Bool) {
        let result = EncoreSnapshotMapper().map(
            snapshot(monitoring: !stopped, available: stopped), at: now)
        #expect(result.monitoring == !stopped)
        #expect(result.sources.count == 2)
        for source in result.sources.values {
            #expect(!source.playing)
            #expect(source.title == nil)
            #expect(source.bits == nil)
        }
    }

    private func snapshot(age: TimeInterval = 0, monitoring: Bool = true,
                          available: Bool = true) -> PlaybackMonitoringSnapshot {
        let source = PlaybackMonitoringSnapshot.Source(
            playback: MusicPlaybackSnapshot(id: "private", title: "Track", artist: "Artist",
                album: "", sampleRate: "96 kHz", fileURL: nil),
            audioFormat: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"),
            observedAt: now.addingTimeInterval(-age), isAvailable: available, zone: "SHD ROON")
        return PlaybackMonitoringSnapshot(isMonitoring: monitoring, appleMusic: source, roon: source)
    }
}
