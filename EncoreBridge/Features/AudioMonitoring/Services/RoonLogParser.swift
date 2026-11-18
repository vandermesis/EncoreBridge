import Foundation

nonisolated struct RoonLogParser: Sendable {
    struct Stream: Sendable {
        let sampleRate: Int
        let bits: Int
        let id: String
    }

    struct Summary: Sendable {
        let state: String
        let trackLabel: String
        let descriptor: String

        func sourceFormat(matching stream: Stream?) -> AudioFormatSnapshot {
            // The left side describes the source; the right side is Roon's output.
            let source = descriptor.components(separatedBy: "=>")[0]
            guard let fields = RoonLogParser.captures(source,
                #",\s*(\d+|\?)/([\d.]+|\?)\s+([A-Za-z0-9]+)\s*$"#) else { return .init() }
            let codec = fields[2].uppercased()
            guard ["ALAC", "FLAC", "WAV", "AIFF", "PCM", "AAC", "MP3", "OGG", "OPUS"].contains(codec) else { return .init() }
            // Lossy codecs have no original PCM bit depth. Roon can report the
            // decoder's 24-bit container here, which must not be shown as source depth.
            let lossless = ["ALAC", "FLAC", "WAV", "AIFF", "PCM"].contains(codec)
            let bits = Int(fields[0]).flatMap { [8, 16, 20, 24, 32, 64].contains($0) ? $0 : nil }
            var hertz: Int?
            if let rate = Double(fields[1]), rate.isFinite, rate >= 8, rate <= 768 {
                if fields[1].contains(".") {
                    hertz = Int((rate * 1000).rounded())
                } else if let stream, Int(rate) == stream.sampleRate / 1000,
                          !lossless || bits == nil || bits == stream.bits {
                    hertz = stream.sampleRate
                }
            }
            let rate = hertz.map { "\(Double($0) / 1000)" }
                .map { $0.hasSuffix(".0") ? String($0.dropLast(2)) : $0 }
                .map { "\($0) kHz" }
            return AudioFormatSnapshot(fileFormat: codec, sampleRate: rate,
                                       bitDepth: lossless ? bits.map { "\($0)-bit" } : nil)
        }
    }

    enum Payload: Sendable {
        case file(String)
        case queuedFile(String)
        case advance
        case stream(Stream)
        case summary(Summary)
    }

    struct Event: Sendable {
        let date: Date
        let zone: String
        let payload: Payload
    }

    func parse(_ line: String, relativeTo now: Date = .now) -> Event? {
        guard let header = Self.captures(line,
            #"^(\d{2}/\d{2} \d{2}:\d{2}:\d{2})\s+(?:Trace|Info|Debug):\s+\[([^\]]+)\]\s+(.*)$"#),
              let date = Self.date(header[0], relativeTo: now) else { return nil }
        var zone = header[1]
        let body = header[2]
        let payload: Payload
        if body.hasPrefix("[zoneplayer] Playing: ") {
            payload = .file(String(body.dropFirst("[zoneplayer] Playing: ".count)))
        } else if body.hasPrefix("[zoneplayer] Queueing: ") {
            payload = .queuedFile(String(body.dropFirst("[zoneplayer] Queueing: ".count)))
        } else if zone.hasPrefix("zone "), body == "OnPlayFeedback OnToNext" {
            zone = String(zone.dropFirst("zone ".count))
            payload = .advance
        } else if body.hasPrefix("[zoneplayer/raat] StartStream "),
                  let source = body.components(separatedBy: " => ").first,
                  let rateText = Self.captures(source, #"(?i)\bsamplerate\s*=\s*(\d+)"#)?.first,
                  let bitsText = Self.captures(source, #"(?i)\bbitspersample\s*=\s*(\d+)"#)?.first,
                  let streamID = Self.captures(body, #"\bstreamid=(\d+)"#)?.first,
                  let bits = Int(bitsText), let rate = Int(rateText), (8_000...768_000).contains(rate) {
            payload = .stream(Stream(sampleRate: rate, bits: bits, id: streamID))
        } else if let fields = Self.captures(body,
            #"^\[([^\]]+)\]\s+(?:\[[^\]]*buf\]\s+)?\[(PLAYING|LOADING|PAUSED|STOPPED)(?:\s+@[^\]]*)?\]\s*(.*)$"#) {
            payload = .summary(Summary(state: fields[1], trackLabel: fields[2], descriptor: fields[0]))
        } else {
            return nil
        }
        return Event(date: date, zone: zone, payload: payload)
    }

    private static func date(_ text: String, relativeTo now: Date) -> Date? {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        let year = calendar.component(.year, from: now)
        return [year - 1, year, year + 1].compactMap { formatter.date(from: "\($0)/\(text)") }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    fileprivate static func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let values = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        return values.count == match.numberOfRanges - 1 ? values : nil
    }
}
