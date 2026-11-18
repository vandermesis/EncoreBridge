import SwiftUI

/// Declares the menu bar panel and the diagnostics window.
///
/// Both scenes use the same runtime, which the application delegate keeps alive.
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
