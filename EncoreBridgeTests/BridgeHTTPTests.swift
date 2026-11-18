import Foundation
import Testing
@testable import EncoreBridge

struct BridgeHTTPTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func exportsBothSourcesInEncoreUnitsWithoutPrivatePaths() throws {
        let data = try encoded(snapshot())
        let root = try object(data)
        #expect(root["schema_version"] as? Int == 1)
        #expect(root["ttl_ms"] as? Int == 3000)
        let sources = try #require(root["sources"] as? [String: [String: Any]])
        #expect(sources.count == 2)
        #expect(sources["apple_music"]?["artist"] as? String == "Sigur Rós")
        #expect(sources["apple_music"]?["codec"] as? String == "ALAC")
        #expect(sources["apple_music"]?["bits"] as? Int == 24)
        #expect(sources["apple_music"]?["fs_hz"] as? Int == 96000)
        #expect(sources["roon"]?["title"] as? String == "Rehab")
        #expect(sources["roon"]?["bits"] as? Int == 16)
        #expect(sources["roon"]?["fs_hz"] as? Int == 44100)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("/private/"))
        #expect(!text.contains("fileURL"))
        #expect(!text.contains("secret"))
    }

    @Test(arguments: ["paused", "stopped", "stale", "future"])
    func inactiveSourceNeverLeaksRetainedTrackOrFormat(_ reason: String) throws {
        var playback = track()
        playback.isPlaying = reason != "paused"
        let age: TimeInterval = reason == "stale" ? 4 : reason == "future" ? -10 : 0
        let source = BridgePlaybackSnapshot.Source(name: "Mac", application: "Apple Music",
            playback: playback, format: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"),
            observedAt: now.addingTimeInterval(-age), active: reason != "stopped", maxAge: 3, now: now)
        let result = try object(encoded(source))
        #expect(result["playing"] as? Bool == false)
        for key in ["artist", "title", "codec", "bits", "fs_hz"] { #expect(result[key] == nil) }
    }

    @Test func unknownSourceValuesAreOmittedInsteadOfInvented() throws {
        let source = BridgePlaybackSnapshot.Source(name: "Roon", application: "Roon", playback: track(),
            format: AudioFormatSnapshot(fileFormat: "MP3", sampleRate: "44.1 kHz"),
            observedAt: now, active: true, maxAge: 20, now: now)
        let result = try object(encoded(source))
        #expect(result["playing"] as? Bool == true)
        #expect(result["codec"] as? String == "MP3")
        #expect(result["fs_hz"] as? Int == 44100)
        #expect(result["bits"] == nil)
    }

    @Test func unicodeResponseUsesByteLengthAndHeadKeepsHeadersOnly() throws {
        let get = try BridgeHTTPResponse.make(request: Data("GET /v1/now-playing HTTP/1.0\r\n\r\n".utf8), snapshot: snapshot())
        #expect(get.status == 200)
        #expect(try object(get.body)["sources"] != nil)
        let separator = try #require(get.data.range(of: Data("\r\n\r\n".utf8)))
        #expect(get.data[separator.upperBound...].count == get.body.count)
        let head = try BridgeHTTPResponse.make(request: Data("HEAD /v1/now-playing HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8), snapshot: snapshot())
        #expect(String(decoding: head.data, as: UTF8.self).contains("Content-Length: \(get.body.count)\r\n"))
        #expect(head.data.suffix(4) == Data("\r\n\r\n".utf8))
    }

    @Test(arguments: ["POST", "PUT", "DELETE"])
    func networkInterfaceRejectsControlMethods(_ method: String) throws {
        let response = try BridgeHTTPResponse.make(request: Data("\(method) /v1/now-playing HTTP/1.1\r\n\r\n".utf8), snapshot: snapshot())
        #expect(response.status == 405)
        #expect(String(decoding: response.data, as: UTF8.self).contains("Allow: GET, HEAD\r\n"))
    }

    @Test func malformedAndUnrelatedRequestsDoNotReturnPlayback() throws {
        let bad = try BridgeHTTPResponse.make(request: Data("garbage\r\n\r\n".utf8), snapshot: snapshot())
        #expect(bad.status == 400)
        let absent = try BridgeHTTPResponse.make(request: Data("GET /logs HTTP/1.1\r\n\r\n".utf8), snapshot: snapshot())
        #expect(absent.status == 404)
        #expect(!String(decoding: absent.body, as: UTF8.self).contains("artist"))
    }

    @MainActor @Test func realListenerHandlesConcurrentClientsAndStoppedSnapshot() async throws {
        let activeSnapshot = snapshot()
        let stoppedSnapshot = BridgePlaybackSnapshot(generatedAt: now, monitoring: false, sources: [:])
        var currentSnapshot = activeSnapshot
        let server = BridgeHTTPServer(port: 0) { currentSnapshot }
        server.start()
        defer { server.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while server.boundPort == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/v1/now-playing"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 3
                    let (data, response) = try await session.data(for: request)
                    #expect((response as? HTTPURLResponse)?.statusCode == 200)
                    return data
                }
            }
            for try await data in group {
                let root = try object(data)
                #expect(root["monitoring"] as? Bool == true)
                #expect((root["sources"] as? [String: Any])?.count == 2)
            }
        }
        currentSnapshot = stoppedSnapshot
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, _) = try await session.data(for: request)
        #expect(try object(data)["monitoring"] as? Bool == false)
    }

    private func snapshot() -> BridgePlaybackSnapshot {
        BridgePlaybackSnapshot(generatedAt: now, monitoring: true, sources: [
            "apple_music": .init(name: "Mac", application: "Apple Music", playback: track(),
                format: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"),
                observedAt: now, active: true, maxAge: 3, now: now),
            "roon": .init(name: "Roon", application: "Roon", zone: "SHD ROON",
                playback: MusicPlaybackSnapshot(id: "private-id", title: "Rehab", artist: "Amy Winehouse", album: "", sampleRate: "44.1 kHz", fileURL: nil),
                format: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "44.1 kHz", bitDepth: "16-bit"),
                observedAt: now, active: true, maxAge: 20, now: now)
        ])
    }

    private func track() -> MusicPlaybackSnapshot {
        MusicPlaybackSnapshot(id: "/private/secret.m4a", title: "[Njósnavélin]", artist: "Sigur Rós", album: "", sampleRate: "96 kHz", fileURL: URL(filePath: "/private/secret.m4a"))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
