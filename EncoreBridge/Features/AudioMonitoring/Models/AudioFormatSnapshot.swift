nonisolated struct AudioFormatSnapshot: Equatable, Sendable {
    var fileFormat: String?
    var sampleRate: String?
    var bitDepth: String?

    var hasValues: Bool {
        fileFormat != nil || sampleRate != nil || bitDepth != nil
    }

    func fillingMissingValues(from other: Self) -> Self {
        guard fileFormat == nil || other.fileFormat == nil || fileFormat == other.fileFormat,
              sampleRate == nil || other.sampleRate == nil || sampleRate == other.sampleRate else {
            return self
        }
        return Self(fileFormat: fileFormat ?? other.fileFormat,
                    sampleRate: sampleRate ?? other.sampleRate,
                    bitDepth: bitDepth ?? other.bitDepth)
    }
}
