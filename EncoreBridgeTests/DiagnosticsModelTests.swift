import Testing
@testable import EncoreBridge

struct DiagnosticsModelTests {
    @MainActor @Test func combinesDiagnosticsAndBoundsRetainedHistoryWithoutStartingMonitoring() {
        let monitor = PlaybackMonitor()
        let diagnostics = DiagnosticsModel(monitor: monitor)
        monitor.music.onDiagnosticMessage?("Music event")
        monitor.roon.onDiagnosticMessage?("Roon event")
        #expect(diagnostics.messages.count == 2)
        #expect(diagnostics.text.contains("Music event"))
        #expect(diagnostics.text.contains("Roon event"))
        for index in 0..<60 { diagnostics.recordServerStatus("HTTP status \(index)") }
        #expect(diagnostics.messages.count == 50)
        #expect(diagnostics.serverStatus == "HTTP status 59")
        #expect(diagnostics.text.contains("HTTP_SERVER HTTP status 59"))
        #expect(!monitor.snapshot.isMonitoring)
    }
}
