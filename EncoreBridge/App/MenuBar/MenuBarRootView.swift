import SwiftUI

struct MenuBarRootView: View {
    let monitor: PlaybackMonitor
    let diagnostics: DiagnosticsModel

    var body: some View {
        VStack(spacing: 0) {
            MenuBarContentView(monitor: monitor)
            Divider()
            MenuBarOptionsView(monitor: monitor, diagnostics: diagnostics)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
