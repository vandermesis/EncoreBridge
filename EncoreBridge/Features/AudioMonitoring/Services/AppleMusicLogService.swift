import Darwin
import Foundation

@MainActor
final class AppleMusicLogService {
    private let makeProcess: @MainActor () -> Process
    private var process: Process?
    private var readingTask: Task<Void, Never>?

    init(makeProcess: (@MainActor () -> Process)? = nil) {
        self.makeProcess = makeProcess ?? Self.makeLogProcess
    }

    var isRunning: Bool {
        process != nil
    }

    func start(
        onMessage: @escaping (String) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard process == nil else {
            return
        }

        let process = makeProcess()
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let (exits, exit) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { process in
            exit.yield(process.terminationStatus)
            exit.finish()
        }
        do {
            try process.run()
        } catch {
            exit.finish()
            throw error
        }
        self.process = process

        let stdout = LogPipe(handle: output.fileHandleForReading)
        let stderr = LogPipe(handle: errors.fileHandleForReading)
        readingTask = Task { [weak self] in
            do {
                let result = try await withThrowingTaskGroup(of: Completion.self) { group in
                    group.addTask { @MainActor [weak self] in
                        for try await line in stdout.lines {
                            guard !Task.isCancelled, self?.process === process else { break }
                            onMessage(Self.decodedMessage(from: line) ?? line)
                        }
                        return .outputDrained
                    }
                    group.addTask {
                        .diagnostics(try await Self.readDiagnostics(stderr))
                    }
                    group.addTask {
                        var iterator = exits.makeAsyncIterator()
                        return .exitStatus(await iterator.next())
                    }

                    var status: Int32?
                    var diagnostics = ""
                    do {
                        for try await completion in group {
                            switch completion {
                            case .outputDrained: break
                            case .diagnostics(let text): diagnostics = text
                            case .exitStatus(let code): status = code
                            }
                        }
                    } catch {
                        // Terminate the writer before the group waits for its other readers.
                        if process.isRunning { process.terminate() }
                        throw error
                    }
                    return (status, diagnostics)
                }

                guard !Task.isCancelled, let self, self.process === process,
                      let status = result.0 else { return }
                self.process = nil
                readingTask = nil
                let message = "Proces log zakończył działanie (kod \(status))."
                onFailure(result.1.isEmpty ? message : message + "\n" + result.1)
            } catch {
                guard !Task.isCancelled, let self, self.process === process else { return }
                stop()
                onFailure(error.localizedDescription)
            }
        }
    }

    func stop() {
        let stoppedProcess = process
        process = nil
        readingTask?.cancel()
        readingTask = nil
        if let stoppedProcess, stoppedProcess.isRunning { stoppedProcess.terminate() }
    }

    private enum Completion: Sendable {
        case outputDrained
        case diagnostics(String)
        case exitStatus(Int32?)
    }

    @concurrent
    private static func readDiagnostics(_ pipe: LogPipe) async throws -> String {
        let limit = 8 * 1024
        var prefix = Data()
        var truncated = false
        // Keep draining even after reaching the limit so the child can keep writing.
        while let chunk = try await pipe.readChunk() {
            let remaining = limit - prefix.count
            prefix.append(contentsOf: chunk.prefix(remaining))
            truncated = truncated || chunk.count > remaining
        }
        let text = String(decoding: prefix, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated ? text + "\n[diagnostyka skrócona]" : text
    }

    private static func makeLogProcess() -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "ndjson",
            "--level", "debug",
            "--predicate",
            #"process == "Music""#
        ]
        return process
    }

    private static func decodedMessage(from line: String) -> String? {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["eventMessage"] as? String
            ?? object["message"] as? String
    }
}

/// Gives each pipe its own blocking I/O queue and reads on demand.
/// Swift tasks suspend at the continuation while the queue waits for data.
nonisolated private struct LogPipe: AsyncSequence, Sendable {
    let handle: FileHandle
    private let queue = DispatchQueue(label: "EncoreBridge.log.pipe")

    func readChunk() async throws -> Data? {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try readAvailableChunk() })
            }
        }
    }

    private func readAvailableChunk() throws -> Data? {
        var chunk = Data(count: 8 * 1024)
        let count = try chunk.withUnsafeMutableBytes { buffer in
            while true {
                let count = Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
                if count >= 0 { return count }
                let error = errno
                if error != EINTR {
                    throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
                }
            }
        }
        guard count > 0 else { return nil }
        chunk.count = count
        return chunk
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(pipe: self)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let pipe: LogPipe
        private var chunk = Data()
        private var offset = 0

        init(pipe: LogPipe) {
            self.pipe = pipe
        }

        mutating func next() async throws -> UInt8? {
            if offset == chunk.count {
                guard let next = try await pipe.readChunk(), !next.isEmpty else { return nil }
                chunk = next
                offset = 0
            }
            defer { offset += 1 }
            return chunk[offset]
        }
    }
}
