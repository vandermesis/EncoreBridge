/// Known source format values. Missing fields represent unavailable information.
nonisolated struct AudioFormatSnapshot: Equatable, Sendable {
    var fileFormat: String?
    var sampleRate: String?
    var bitDepth: String?

    var hasValues: Bool {
        fileFormat != nil || sampleRate != nil || bitDepth != nil
    }

    /// Fills missing fields when known codecs and sample rates agree.
    /// Existing values take precedence.
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
