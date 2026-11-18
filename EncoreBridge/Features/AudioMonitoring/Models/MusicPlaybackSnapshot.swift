import Foundation

nonisolated struct MusicPlaybackSnapshot: Equatable, Sendable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let sampleRate: String?
    let fileURL: URL?
    var isPlaying = true
}
