import Foundation

struct AudioFormatParser: Sendable {
    private let standardSampleRates: Set<Int> = [
        8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000,
        44_100, 48_000, 64_000, 88_200, 96_000, 176_400,
        192_000, 352_800, 384_000, 705_600, 768_000
    ]

    func parseQualityLabel(_ label: String) -> AudioFormatSnapshot? {
        guard let rate = captures(in: label, pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*kHz"#)?.first,
              let kilohertz = Double(rate.replacingOccurrences(of: ",", with: ".")),
              kilohertz.isFinite, kilohertz >= 8, kilohertz <= 768,
              standardSampleRates.contains(Int((kilohertz * 1000).rounded())),
              let codec = captures(in: label, pattern: #"\b(ALAC|AAC|MP3|FLAC)\b"#)?.first else { return nil }
        let depth = captures(in: label, pattern: #"\b(8|16|20|24|32|64)-bit\b"#)?.first
        return AudioFormatSnapshot(fileFormat: codec.uppercased(),
                                   sampleRate: formattedSampleRate(Int((kilohertz * 1000).rounded())),
                                   bitDepth: depth.map { "\($0)-bit" })
    }

    func parseEvent(_ message: String) -> AudioFormatEvent? {
        guard
            message.localizedStandardContains("item-audio-format-metadata"),
            let queueItemID = queueItemID(in: message),
            let audioFormat = parseActiveAudioFormat(message)
        else {
            return nil
        }

        return AudioFormatEvent(queueItemID: queueItemID, audioFormat: audioFormat)
    }

    func queueItemID(in message: String) -> Int? {
        guard let value = captures(
            in: message,
            pattern: #""?queue-item-id"?\s*=\s*(\d+)"#
        )?.first else {
            return nil
        }
        return Int(value)
    }

    func queueSectionID(in message: String) -> String? {
        captures(
            in: message,
            pattern: #""?queue-section-id"?\s*=\s*"?([0-9+]+)"?"#
        )?.first
    }

    func parseActiveAudioFormat(_ message: String) -> AudioFormatSnapshot? {
        if let format = parsePlaybackFormat(message) {
            return format
        }
        let isCompleteMetadata = message.localizedStandardContains("item-audio-format-metadata")
            && message.range(
                of: #""active-format"\s*=\s*\{"#,
                options: .regularExpression
            ) != nil
        let isActiveFormatReport = message.localizedStandardContains("activeFormat:")
            && message.localizedStandardContains("groupID:")
        let isStartedVariant = message.localizedStandardContains("fpfs_StartTrackPlaying:")
            && message.localizedStandardContains("desiredRate is 1.000000")
            && message.localizedStandardContains("track 1")
            && message.localizedStandardContains("Variant [")

        guard isCompleteMetadata || isActiveFormatReport || isStartedVariant else {
            return nil
        }

        var explicitMetadata: AudioFormatSnapshot?
        if isCompleteMetadata,
           let block = captures(in: message, pattern: #""active-format"\s*=\s*\{([^}]+)\}"#)?.first,
           let codecValue = captures(in: block, pattern: #"\bcodec\s*=\s*(\d+)\s*;"#)?.first,
           let codec = ["1634492771": "ALAC", "1633772320": "AAC", "1718378851": "FLAC"][codecValue] {
            let rate = captures(in: block, pattern: #"\bsr\s*=\s*(\d+)\s*;"#)?.first.flatMap(Int.init)
            let depth = captures(in: block, pattern: #"\bbd\s*=\s*(8|16|20|24|32|64)\s*;"#)?.first
            explicitMetadata = AudioFormatSnapshot(
                fileFormat: codec,
                sampleRate: rate.flatMap { standardSampleRates.contains($0) ? formattedSampleRate($0) : nil },
                bitDepth: depth.map { "\($0)-bit" }
            )
        }

        if isActiveFormatReport, let format = parseQualityLabel(message) {
            return format
        }

        if
            let values = captures(
                in: message,
                pattern: #"audio-([a-zA-Z0-9]+)-[a-zA-Z0-9]+-(\d+)-(8|16|20|24|32|64)"#
            ),
            values.count == 3,
            let sampleRate = Int(values[1]),
            standardSampleRates.contains(sampleRate)
        {
            let descriptor = AudioFormatSnapshot(
                fileFormat: values[0].uppercased(),
                sampleRate: formattedSampleRate(sampleRate),
                bitDepth: "\(values[2])-bit"
            )
            return explicitMetadata?.fillingMissingValues(from: descriptor) ?? descriptor
        }

        if let explicitMetadata { return explicitMetadata }

        // Apple Music reports AAC variants with zero sample rate and bit depth.
        // The codec identifier is still authoritative, so preserve only that known value.
        if
            isCompleteMetadata,
            message.range(of: #"codec\s*=\s*1633772320\s*;"#, options: .regularExpression) != nil
        {
            return AudioFormatSnapshot(fileFormat: "AAC")
        }

        return nil
    }

    // Music's playback report distinguishes the source format (sd) from the
    // decoder's internal format (asbd), e.g. ALAC decoded as qlac.
    func parsePlaybackFormat(_ message: String) -> AudioFormatSnapshot? {
        guard message.contains("play> cm>> mediaFormatinfo"),
              let codec = captures(in: message, pattern: #"\bsdFormatID\s*=\s*([a-zA-Z0-9]+)"#)?.first,
              let rate = captures(in: message, pattern: #"\basbdSampleRate\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*kHz"#)?.first,
              let kilohertz = Double(rate),
              standardSampleRates.contains(Int((kilohertz * 1000).rounded())) else {
            return nil
        }
        let depth = captures(in: message, pattern: #"\bsdBitDepth\s*=\s*(8|16|20|24|32|64)(?:\.0+)?\s*bits?\b"#)?.first
        return AudioFormatSnapshot(
            fileFormat: codec.uppercased(),
            sampleRate: formattedSampleRate(Int((kilohertz * 1000).rounded())),
            bitDepth: depth.map { "\($0)-bit" }
        )
    }

    private func captures(in text: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let searchRange = NSRange(text.startIndex..., in: text)
        guard let result = expression.firstMatch(in: text, range: searchRange) else {
            return nil
        }

        let values = (1..<result.numberOfRanges).compactMap { index -> String? in
            guard let range = Range(result.range(at: index), in: text) else {
                return nil
            }
            return String(text[range])
        }
        return values.count == result.numberOfRanges - 1 ? values : nil
    }

    private func formattedSampleRate(_ hertz: Int) -> String {
        let wholeKilohertz = hertz / 1_000
        let remainder = hertz % 1_000

        guard remainder != 0 else {
            return "\(wholeKilohertz) kHz"
        }

        var fraction = String(String(remainder + 1_000).dropFirst())
        while fraction.last == "0" {
            fraction.removeLast()
        }
        return "\(wholeKilohertz).\(fraction) kHz"
    }
}
