struct AudioFormatEvent: Equatable, Sendable {
    let queueItemID: Int
    let audioFormat: AudioFormatSnapshot
}
