import Foundation

/// Creates and retains the service graph at the application's composition root.
///
/// Monitoring and the pull-only HTTP listener run independently of panel visibility.
/// Concrete dependencies are assembled here; monitoring never imports the API schema.
@MainActor
final class ApplicationRuntime {
    let monitor: PlaybackMonitor
    let diagnostics: DiagnosticsModel
    private let server: BridgeHTTPServer

    init() {
        let monitor = PlaybackMonitor()
        let diagnostics = DiagnosticsModel(monitor: monitor)
        let mapper = EncoreSnapshotMapper()
        let server = BridgeHTTPServer { mapper.map(monitor.snapshot) }
        server.onStatusChange = { [weak diagnostics] in diagnostics?.recordServerStatus($0) }
        self.monitor = monitor
        self.diagnostics = diagnostics
        self.server = server
    }

    /// Starts source monitoring, then starts the HTTP listener.
    func start() {
        monitor.start()
        server.start()
    }

    /// Stops the HTTP listener before stopping the source monitors at app termination.
    func stop() {
        server.stop()
        monitor.stop()
    }
}
