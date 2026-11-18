import Foundation

/// A bounded, read-only HTTP/1.0 and HTTP/1.1 interface for the Encore client.
nonisolated struct BridgeHTTPResponse: Sendable {
    let status: Int
    let reason: String
    let body: Data
    var headOnly = false

    var data: Data {
        var headers = ["HTTP/1.1 \(status) \(reason)",
                       "Content-Type: application/json; charset=utf-8",
                       "Content-Length: \(body.count)",
                       "Cache-Control: no-store", "Connection: close"]
        if status == 405 { headers.append("Allow: GET, HEAD") }
        var result = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        if !headOnly { result.append(body) }
        return result
    }

    static func make(request: Data, snapshot: BridgePlaybackSnapshot) throws -> Self {
        guard let text = String(data: request, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else {
            return error(400, "Bad Request", "bad_request")
        }
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(parts[2]),
              parts[1].hasPrefix("/") else { return error(400, "Bad Request", "bad_request") }
        let head = parts[0] == "HEAD"
        guard parts[0] == "GET" || head else { return error(405, "Method Not Allowed", "read_only") }
        let path = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        switch path {
        case "/v1/now-playing":
            return Self(status: 200, reason: "OK", body: try encoder.encode(snapshot), headOnly: head)
        case "/health":
            return Self(status: 200, reason: "OK", body: Data(#"{"service":"EncoreBridge","schema_version":1,"status":"ok"}"#.utf8), headOnly: head)
        default:
            var response = error(404, "Not Found", "not_found")
            response.headOnly = head
            return response
        }
    }

    static func error(_ status: Int, _ reason: String, _ code: String) -> Self {
        Self(status: status, reason: reason, body: Data("{\"error\":\"\(code)\"}".utf8))
    }
}
