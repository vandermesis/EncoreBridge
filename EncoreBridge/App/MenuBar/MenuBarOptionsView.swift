import AppKit
import SwiftUI

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
