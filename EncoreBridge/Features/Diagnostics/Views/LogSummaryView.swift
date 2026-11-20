import SwiftUI

/// Shows the monitoring status and up to ten recent diagnostic entries, newest first.
///
/// Copy Logs exports the report from the shared diagnostics model.
struct LogSummaryView: View {
    let diagnostics: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ostatnie 10 wpisów")
                        .font(.headline)
                    MonitoringStatusView(status: diagnostics.monitor.status, text: diagnostics.monitor.statusText)
                        .font(.caption)
                }
                Spacer()
                Button("Copy Logs", systemImage: "doc.on.doc") {
                    diagnostics.copyLogs()
                }
            }
            .padding(20)

            Divider()

            if diagnostics.messages.isEmpty {
                ContentUnavailableView("Brak wpisów", systemImage: "doc.text",
                                       description: Text("Uruchom odtwarzanie w Apple Music lub Roon."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(diagnostics.messages.suffix(10).reversed().enumerated()), id: \.offset) { _, message in
                            let lines = message.split(separator: "\n", maxSplits: 1)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(lines[0]))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                if lines.count > 1 {
                                    Text(String(lines[1]))
                                        .font(.system(.caption, design: .monospaced))
                                }
                            }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("recentLogs")
            }
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}
