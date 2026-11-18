import Foundation
import Testing
@testable import EncoreBridge

@MainActor
struct AppleMusicLogServiceTests {
    @Test func deliversFragmentedOutputAfterDrainingLargeStderr() async throws {
        let process = shell("""
            printf '{"event'
            printf 'diagnostic prefix\n' >&2
            printf '%01048576d' 0 >&2
            printf 'Message":"complete line"}\n'
            exit 7
            """)
        let service = AppleMusicLogService { process }
        defer { service.stop() }
        var messages: [String] = []
        var failures: [String] = []
        try service.start(onMessage: { messages.append($0) }, onFailure: { failures.append($0) })

        try await waitFor("process completion") { !failures.isEmpty }
        #expect(messages == ["complete line"])
        let failure = try #require(failures.first)
        #expect(failures.count == 1)
        #expect(failure.contains("kod 7"))
        #expect(failure.contains("diagnostic prefix"))
        #expect(failure.contains("[diagnostyka skrócona]"))
        #expect(failure.utf8.count < 8_400)
        #expect(!service.isRunning)
    }

    @Test(arguments: [false, true])
    func pipeEOFAllowsMainActorToRunAndWaitsForRealExit(closeStderr: Bool) async throws {
        let release = temporaryFile()
        defer { try? FileManager.default.removeItem(at: release) }
        let process = shell("""
            printf '{"eventMessage":"ready"}\n'
            exec 1>&-
            if [ "$2" = close ]; then exec 2>&-; fi
            \(waitForRelease)
            if [ "$2" = keep ]; then printf 'final diagnostic\n' >&2; fi
            exit 23
            """, arguments: [release.path, closeStderr ? "close" : "keep"])
        let service = AppleMusicLogService { process }
        defer { service.stop() }
        var messages: [String] = []
        var failures: [String] = []
        try service.start(onMessage: { messages.append($0) }, onFailure: { failures.append($0) })

        try await waitFor("first message") { messages == ["ready"] }
        // Let the stream reach EOF before giving the still-running child permission to exit.
        try await Task.sleep(for: .milliseconds(50))
        #expect(process.isRunning)
        #expect(service.isRunning)
        #expect(failures.isEmpty)
        try Data().write(to: release)
        try await waitFor("real exit callback") { !failures.isEmpty }
        let failure = try #require(failures.first)
        #expect(failures.count == 1)
        #expect(failure.contains("kod 23"))
        #expect(failure.contains("final diagnostic") == !closeStderr)
        #expect(!service.isRunning)
    }

    @Test func stopThenStartIgnoresLateOutputAndExitFromOlderProcess() async throws {
        let releaseOld = temporaryFile()
        let releaseNew = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: releaseOld)
            try? FileManager.default.removeItem(at: releaseNew)
        }
        let old = shell("""
            trap '' TERM
            printf '{"eventMessage":"old ready"}\n'
            \(waitForRelease)
            printf '{"eventMessage":"old late"}\n'
            exit 41
            """, arguments: [releaseOld.path])
        let new = shell("""
            printf '{"eventMessage":"new ready"}\n'
            \(waitForRelease)
            printf '{"eventMessage":"new final"}\n'
            exit 42
            """, arguments: [releaseNew.path])
        var processes = [old, new]
        let service = AppleMusicLogService { processes.removeFirst() }
        defer { service.stop() }
        var messages: [String] = []
        var failures: [String] = []
        try service.start(onMessage: { messages.append($0) }, onFailure: { failures.append($0) })
        try await waitFor("old process started") { messages == ["old ready"] }

        service.stop()
        #expect(!service.isRunning)
        try service.start(onMessage: { messages.append($0) }, onFailure: { failures.append($0) })
        try await waitFor("new process started") { messages.contains("new ready") }
        try Data().write(to: releaseOld)
        try await waitFor("old process exited") { !old.isRunning }
        #expect(service.isRunning)
        #expect(failures.isEmpty)

        try Data().write(to: releaseNew)
        try await waitFor("new process completed") { !failures.isEmpty }
        #expect(messages == ["old ready", "new ready", "new final"])
        #expect(failures.count == 1)
        #expect(failures.first?.contains("kod 42") == true)
        #expect(!service.isRunning)
    }

    private let waitForRelease = """
        attempts=0
        while [ ! -e "$1" ]; do
            [ "$attempts" -lt 150 ] || exit 88
            attempts=$((attempts + 1))
            /bin/sleep 0.02
        done
        """

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func shell(_ script: String, arguments: [String] = []) -> Process {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script, "fixture"] + arguments
        return process
    }

    private func waitFor(_ description: String, until condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "Timed out waiting for \(description)")
    }
}
