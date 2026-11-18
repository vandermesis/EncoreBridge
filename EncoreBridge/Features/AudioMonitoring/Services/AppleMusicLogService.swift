import Foundation

@MainActor
final class AppleMusicLogService {
    private var process: Process?
    private var readingTask: Task<Void, Never>?

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

        let process = Process()
        let output = Pipe()
        let errors = Pipe()

        process.executableURL = URL(filePath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "ndjson",
            "--level", "debug",
            "--predicate",
            #"process == "Music""#
        ]
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        self.process = process

        readingTask = Task { [weak self] in
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    guard !Task.isCancelled else {
                        return
                    }
                    onMessage(Self.decodedMessage(from: line) ?? line)
                }

                guard !Task.isCancelled else {
                    return
                }

                let errorData = try errors.fileHandleForReading.readToEnd() ?? Data()
                let errorMessage = String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                self?.process = nil
                onFailure(
                    errorMessage.isEmpty
                        ? "Proces log zakończył działanie (kod \(process.terminationStatus))."
                        : errorMessage
                )
            } catch is CancellationError {
                return
            } catch {
                self?.process = nil
                onFailure(error.localizedDescription)
            }
        }
    }

    func stop() {
        readingTask?.cancel()
        readingTask = nil
        process?.terminate()
        process = nil
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
