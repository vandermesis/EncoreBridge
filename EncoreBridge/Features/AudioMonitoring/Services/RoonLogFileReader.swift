import Foundation

/// Reads only Roon's text logs. All file I/O and parsing runs on this actor.
actor RoonLogFileReader {
    struct Record: Sendable {
        let event: RoonLogParser.Event
        let line: String
    }

    struct Batch: Sendable {
        let records: [Record]
        let reset: Bool
        let available: Bool
    }

    private let url: URL
    private let zone: String
    private var identity: UInt64?
    private var offset: UInt64 = 0
    private var pending = Data()
    private let parser = RoonLogParser()
    private let initialLimit = 8 * 1024 * 1024

    init(url: URL, zone: String) {
        self.url = url
        self.zone = zone
    }

    func rewind() {
        identity = nil
        offset = 0
        pending.removeAll()
    }

    func read(relativeTo now: Date = .now) throws -> Batch {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            identity = nil
            offset = 0
            pending.removeAll()
            return Batch(records: [], reset: true, available: false)
        }
        let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let reset = identity == nil || identity != fileID || size < offset
        var records: [Record] = []
        if reset {
            pending.removeAll()
            // A rotation can split Playing/StartStream and the periodic summary.
            // Replaying the preceding file restores that context, then the
            // current file always takes precedence.
            let previous = url.deletingLastPathComponent().appending(path: "RoonServer_log.01.txt")
            if FileManager.default.fileExists(atPath: previous.path) {
                let handle = try FileHandle(forReadingFrom: previous)
                defer { try? handle.close() }
                let previousSize = try handle.seekToEnd()
                let start = previousSize > initialLimit ? previousSize - UInt64(initialLimit) : 0
                try handle.seek(toOffset: start)
                let data = try handle.read(upToCount: initialLimit) ?? Data()
                records += parse(data, droppingFirstLine: start > 0, relativeTo: now)
                pending.removeAll()
            }
            offset = size > initialLimit ? size - UInt64(initialLimit) : 0
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: reset ? initialLimit : 1024 * 1024) ?? Data()
        records += parse(data, droppingFirstLine: reset && offset > 0, relativeTo: now)
        offset += UInt64(data.count)
        identity = fileID
        return Batch(records: records, reset: reset, available: true)
    }

    private func parse(_ data: Data, droppingFirstLine: Bool, relativeTo now: Date) -> [Record] {
        pending.append(data)
        guard let lastNewline = pending.lastIndex(of: 10) else {
            if pending.count > 256 * 1024 { pending.removeAll() }
            return []
        }
        let complete = pending[..<lastNewline]
        pending = Data(pending[pending.index(after: lastNewline)...])
        var lines = String(decoding: complete, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        if droppingFirstLine, !lines.isEmpty { lines.removeFirst() }
        return lines.compactMap { line in
            guard line.contains("[\(zone)]") || line.contains("[zone \(zone)]"),
                  let event = parser.parse(String(line), relativeTo: now) else { return nil }
            return Record(event: event, line: String(line))
        }
    }
}
