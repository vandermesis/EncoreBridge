import Foundation

/// Adapts neutral monitoring state to the existing, pull-only M6 API contract.
nonisolated struct EncoreSnapshotMapper {
    /// Maps both sources using one clock value so freshness decisions are consistent.
    ///
    /// - Parameters:
    ///   - snapshot: The current monitoring observations, including stopped sources.
    ///   - now: The response time. Inject a fixed value when testing expiration.
    /// - Returns: Version 1 of the API payload, with private and inactive data omitted.
    func map(_ snapshot: PlaybackMonitoringSnapshot, at now: Date = .now) -> BridgePlaybackSnapshot {
        BridgePlaybackSnapshot(generatedAt: now, monitoring: snapshot.isMonitoring, sources: [
            "apple_music": .init(name: "Mac", application: "Apple Music",
                playback: snapshot.appleMusic.playback, format: snapshot.appleMusic.audioFormat,
                observedAt: snapshot.appleMusic.observedAt,
                active: snapshot.isMonitoring && snapshot.appleMusic.isAvailable, maxAge: 3, now: now),
            "roon": .init(name: "Roon", application: "Roon", zone: snapshot.roon.zone,
                playback: snapshot.roon.playback, format: snapshot.roon.audioFormat,
                observedAt: snapshot.roon.observedAt,
                active: snapshot.isMonitoring && snapshot.roon.isAvailable, maxAge: 20, now: now)
        ])
    }
}
