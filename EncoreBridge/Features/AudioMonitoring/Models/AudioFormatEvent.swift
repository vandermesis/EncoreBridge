/// A format report tagged with the queue-item ID from a Music log entry.
struct AudioFormatEvent: Equatable, Sendable {
    let queueItemID: Int
    let audioFormat: AudioFormatSnapshot
}
