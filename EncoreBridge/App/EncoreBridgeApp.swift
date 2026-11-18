import SwiftUI

@main
struct EncoreBridgeApp: App {
    @NSApplicationDelegateAdaptor(EncoreBridgeAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(monitor: appDelegate.runtime.monitor,
                            diagnostics: appDelegate.runtime.diagnostics)
        } label: {
            Image(systemName: "waveform")
                .accessibilityLabel("EncoreBridge")
                .accessibilityIdentifier("EncoreBridgeStatusItem")
        }
        .menuBarExtraStyle(.window)

        Window("EncoreBridge — Logs", id: "diagnostics") {
            LogSummaryView(diagnostics: appDelegate.runtime.diagnostics)
        }
        .defaultSize(width: 680, height: 480)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
