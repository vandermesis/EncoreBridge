import Foundation

/// A source's observation of the selected track and its playing state.
///
/// The track can remain selected while paused. A missing file URL leaves the
/// observation usable for streamed playback. Each source defines its own track ID.
nonisolated struct MusicPlaybackSnapshot: Equatable, Sendable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let sampleRate: String?
    let fileURL: URL?
    var isPlaying = true
}
