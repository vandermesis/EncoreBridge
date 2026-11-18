import Foundation

/// A value copy of monitoring state, independent of UI, HTTP, and any client schema.
///
/// Copy this state on the main actor before passing it to an integration. Freshness
/// limits and the names of JSON fields belong to the integration, not this model.
nonisolated struct PlaybackMonitoringSnapshot: Sendable {
    let isMonitoring: Bool
    let appleMusic: Source
    let roon: Source

    /// The latest observation from one playback source, including its availability.
    struct Source: Sendable {
        let playback: MusicPlaybackSnapshot?
        let audioFormat: AudioFormatSnapshot
        let observedAt: Date?
        let isAvailable: Bool
        var zone: String? = nil
    }
}
