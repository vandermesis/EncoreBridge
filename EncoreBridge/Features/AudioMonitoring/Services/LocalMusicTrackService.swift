import AppKit
import AudioToolbox
import AVFoundation

@MainActor
final class LocalMusicTrackService {
    private let trackURLProvider: (() -> URL?)?
    private var cachedURL: URL?
    private var cachedFormat: AudioFormatSnapshot?
    private let playbackProvider: (() -> MusicPlaybackSnapshot?)?

    // Execution compiles the script on first use. Keep the compiled object for later polls.
    private lazy var playbackScript = NSAppleScript(source: """
        tell application "Music"
            if not running then return {}
            try
                set t to current track
                set trackID to persistent ID of t
                set trackName to name of t
                set trackArtist to artist of t
                set trackAlbum to album of t
                set trackRate to sample rate of t
                set trackPlaying to (player state is playing)
                set trackPath to ""
                try
                    set trackPath to POSIX path of (location of t as alias)
                end try
                if trackID is not (persistent ID of current track) then return {}
                return {trackID, trackName, trackArtist, trackAlbum, trackRate, trackPath, trackPlaying}
            on error
                return {}
            end try
        end tell
        """)

    init(trackURLProvider: (() -> URL?)? = nil, playbackProvider: (() -> MusicPlaybackSnapshot?)? = nil) {
        self.trackURLProvider = trackURLProvider
        self.playbackProvider = playbackProvider
    }

    func currentPlayback() -> MusicPlaybackSnapshot? {
        if let playbackProvider { return playbackProvider() }
        if let trackURLProvider {
            guard let url = trackURLProvider() else { return nil }
            return MusicPlaybackSnapshot(id: url.path, title: url.deletingPathExtension().lastPathComponent,
                                         artist: "", album: "", sampleRate: nil, fileURL: url)
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return nil
        }

        var error: NSDictionary?
        let result = playbackScript?.executeAndReturnError(&error)
        guard error == nil, let result, result.numberOfItems == 7,
              let id = result.atIndex(1)?.stringValue, !id.isEmpty,
              let title = result.atIndex(2)?.stringValue else { return nil }
        let rate = result.atIndex(5)?.int32Value ?? 0
        let path = result.atIndex(6)?.stringValue ?? ""
        return MusicPlaybackSnapshot(id: id, title: title,
                                     artist: result.atIndex(3)?.stringValue ?? "",
                                     album: result.atIndex(4)?.stringValue ?? "",
                                     sampleRate: rate > 0 ? formattedSampleRate(Double(rate)) : nil,
                                     fileURL: path.isEmpty ? nil : URL(filePath: path),
                                     isPlaying: result.atIndex(7)?.booleanValue ?? false)
    }

    func formatForCurrentFile(_ url: URL) -> AudioFormatSnapshot? {
        if url == cachedURL, let cachedFormat { return cachedFormat }
        cachedURL = url
        cachedFormat = try? audioFormat(at: url)
        return cachedFormat
    }

    func requestAuthorization() {
        let source = #"tell application "Music" to get name"#
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    func currentAudioFormat() -> AudioFormatSnapshot? {
        let currentURL: URL?
        if let trackURLProvider { currentURL = trackURLProvider() }
        else { currentURL = currentTrackURL() }
        guard let url = currentURL else {
            cachedURL = nil
            cachedFormat = nil
            return nil
        }
        if url == cachedURL, let cachedFormat { return cachedFormat }
        cachedURL = url
        cachedFormat = try? audioFormat(at: url)
        return cachedFormat
    }

    func audioFormat(at url: URL) throws -> AudioFormatSnapshot {
        if url.pathExtension.lowercased() == "movpkg" {
            return try downloadedPackageFormat(at: url)
        }
        let file = try AVAudioFile(forReading: url)
        let description = file.fileFormat.streamDescription.pointee

        return AudioFormatSnapshot(
            fileFormat: fileFormat(
                formatID: description.mFormatID,
                fileExtension: url.pathExtension
            ),
            sampleRate: formattedSampleRate(description.mSampleRate),
            bitDepth: bitDepth(
                formatID: description.mFormatID,
                formatFlags: description.mFormatFlags,
                bitsPerChannel: description.mBitsPerChannel
            )
        )
    }

    private func downloadedPackageFormat(at url: URL) throws -> AudioFormatSnapshot {
        let manifest = DownloadedMusicManifest()
        let xml = try Data(contentsOf: url.appending(path: "boot.xml"))
        let parser = XMLParser(data: xml)
        parser.delegate = manifest
        guard parser.parse(), manifest.completeVariantIDs.count == 1,
              let variantID = manifest.completeVariantIDs.first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let dataURL = url.appending(path: "Data")
        for playlist in try FileManager.default.contentsOfDirectory(at: dataURL, includingPropertiesForKeys: nil)
            where playlist.pathExtension == "m3u8" {
            let lines = try String(contentsOf: playlist, encoding: .utf8).components(separatedBy: .newlines)
            guard let variant = lines.first(where: {
                $0.hasPrefix("#EXT-X-STREAM-INF:") && attribute("STABLE-VARIANT-ID", in: $0) == variantID
            }), let group = attribute("AUDIO", in: variant),
                  let codec = attribute("CODECS", in: variant) else { continue }
            let media = lines.first { $0.hasPrefix("#EXT-X-MEDIA:") && attribute("GROUP-ID", in: $0) == group }
            let format: String
            if codec == "alac" { format = "ALAC" }
            else if codec.hasPrefix("mp4a.") { format = "AAC" }
            else { continue }
            let rate = media.flatMap { attribute("SAMPLE-RATE", in: $0) }.flatMap(Double.init)
            let depth = media.flatMap { attribute("BIT-DEPTH", in: $0) }.flatMap(Int.init)
            return AudioFormatSnapshot(
                fileFormat: format,
                sampleRate: rate.flatMap { $0.isFinite && $0 > 0 && $0 <= 768_000 ? formattedSampleRate($0) : nil },
                bitDepth: format == "ALAC" ? depth.flatMap { [16, 20, 24, 32].contains($0) ? "\($0)-bit" : nil } : nil
            )
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private func attribute(_ name: String, in line: String) -> String? {
        let pattern = #"(?:[:,])"# + NSRegularExpression.escapedPattern(for: name) + #"=(?:"([^"]*)"|([^,]*))"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        for index in [1, 2] {
            if let range = Range(match.range(at: index), in: line) { return String(line[range]) }
        }
        return nil
    }

    private func currentTrackURL() -> URL? {
        let source = #"tell application "Music" to POSIX path of (location of current track as alias)"#
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)

        guard error == nil, let path = result?.stringValue, !path.isEmpty else {
            return nil
        }

        return URL(filePath: path)
    }

    private func fileFormat(formatID: AudioFormatID, fileExtension: String) -> String {
        switch formatID {
        case kAudioFormatAppleLossless:
            "ALAC"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2:
            "AAC"
        case kAudioFormatMPEGLayer3:
            "MP3"
        case kAudioFormatFLAC:
            "FLAC"
        case kAudioFormatLinearPCM:
            fileExtension.uppercased()
        default:
            fileExtension.isEmpty ? "Audio" : fileExtension.uppercased()
        }
    }

    private func bitDepth(
        formatID: AudioFormatID,
        formatFlags: AudioFormatFlags,
        bitsPerChannel: UInt32
    ) -> String? {
        if formatID == kAudioFormatAppleLossless {
            // For ALAC, format flags 1...4 identify the original PCM source depth.
            let bits: UInt32? = switch formatFlags {
            case 1:
                16
            case 2:
                20
            case 3:
                24
            case 4:
                32
            default:
                nil
            }

            return bits.map { "\($0)-bit" }
        }

        return bitsPerChannel == 0 ? nil : "\(bitsPerChannel)-bit"
    }

    private func formattedSampleRate(_ hertz: Double) -> String {
        let roundedHertz = Int(hertz.rounded())
        let wholeKilohertz = roundedHertz / 1_000
        let remainder = roundedHertz % 1_000

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

private final class DownloadedMusicManifest: NSObject, XMLParserDelegate {
    var completeVariantIDs: Set<String> = []
    private var streamID: String?
    private var readingComplete = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "Stream" { streamID = attributes["UniqueTag"] }
        readingComplete = elementName == "Complete"
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingComplete { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "Complete", text.trimmingCharacters(in: .whitespacesAndNewlines) == "YES", let streamID {
            completeVariantIDs.insert(streamID)
        }
        readingComplete = false
        if elementName == "Stream" { streamID = nil }
    }
}
