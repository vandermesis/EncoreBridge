import Foundation

/// Public LAN contract. Contains no local paths, library identifiers or diagnostics.
nonisolated struct BridgePlaybackSnapshot: Encodable, Sendable {
    let schemaVersion = 1
    let ttlMs = 3000
    let generatedAt: Date
    let monitoring: Bool
    let sources: [String: Source]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ttlMs = "ttl_ms"
        case generatedAt = "generated_at"
        case monitoring, sources
    }

    struct Source: Encodable, Sendable {
        let name: String
        let application: String
        let zone: String?
        let playing: Bool
        let observedAt: Date?
        let artist: String?
        let title: String?
        let codec: String?
        let bits: Int?
        let fsHz: Int?

        enum CodingKeys: String, CodingKey {
            case name, application, zone, playing, artist, title, codec, bits
            case observedAt = "observed_at"
            case fsHz = "fs_hz"
        }

        init(name: String, application: String, zone: String? = nil,
             playback: MusicPlaybackSnapshot?, format: AudioFormatSnapshot,
             observedAt: Date?, active: Bool, maxAge: TimeInterval, now: Date) {
            self.name = name
            self.application = application
            self.zone = zone
            self.observedAt = observedAt
            let age = observedAt.map { now.timeIntervalSince($0) }
            playing = active && playback?.isPlaying == true && age.map { (-1...maxAge).contains($0) } == true
            artist = playing ? playback?.artist.nilIfEmpty : nil
            title = playing ? playback?.title.nilIfEmpty : nil
            codec = playing ? format.fileFormat?.nilIfEmpty : nil
            let depth = format.bitDepth.flatMap { Int($0.replacingOccurrences(of: "-bit", with: "")) }
            bits = playing ? depth.flatMap { [8, 16, 20, 24, 32, 64].contains($0) ? $0 : nil } : nil
            let rate = format.sampleRate.flatMap { value -> Double? in
                guard value.hasSuffix(" kHz") else { return nil }
                return Double(value.dropLast(4).replacingOccurrences(of: ",", with: "."))
            }
            fsHz = playing ? rate.flatMap { $0.isFinite && (8...768).contains($0) ? Int(($0 * 1000).rounded()) : nil } : nil
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
