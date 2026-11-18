nonisolated struct PlaybackSourceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let playback: MusicPlaybackSnapshot
    let audioFormat: AudioFormatSnapshot
}
