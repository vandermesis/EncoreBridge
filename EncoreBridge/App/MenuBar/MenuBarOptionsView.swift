import AppKit
import SwiftUI

/// Routes menu commands to the existing monitors, diagnostics model and app lifecycle.
///
/// Start and Stop affect the monitors. The HTTP listener belongs to the app runtime.
struct MenuBarOptionsView: View {
    @Environment(\.openWindow) private var openWindow
    let monitor: PlaybackMonitor
    let diagnostics: DiagnosticsModel

    var body: some View {
        Menu {
            Button("Show Logs") {
                openWindow(id: "diagnostics")
                NSApp.activate()
            }
            Button("Copy Logs") { diagnostics.copyLogs() }
            Divider()
            Button(monitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                if monitor.isMonitoring { monitor.stop() }
                else { monitor.start() }
            }
            Divider()
            Button("Close") { NSApp.terminate(nil) }
        } label: {
            Label("Opcje", systemImage: "ellipsis.circle")
        }
        .fixedSize()
        .accessibilityIdentifier("optionsMenu")
    }
}
