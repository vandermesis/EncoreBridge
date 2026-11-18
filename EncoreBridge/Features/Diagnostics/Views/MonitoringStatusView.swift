import SwiftUI

struct MonitoringStatusView: View {
    let status: MusicLogMonitor.Status
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(style)
        }
    }

    private var symbol: String {
        switch status {
        case .stopped:
            "pause.circle"
        case .starting:
            "clock"
        case .monitoring:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var style: AnyShapeStyle {
        switch status {
        case .monitoring:
            AnyShapeStyle(.green)
        case .failed:
            AnyShapeStyle(.red)
        case .starting:
            AnyShapeStyle(.orange)
        case .stopped:
            AnyShapeStyle(.secondary)
        }
    }
}

#Preview("Monitoring States") {
    VStack(alignment: .leading) {
        MonitoringStatusView(status: .starting, text: "Uruchamianie monitoringu")
        MonitoringStatusView(status: .monitoring, text: "Nasłuchiwanie Apple Music")
        MonitoringStatusView(status: .stopped, text: "Monitoring zatrzymany")
        MonitoringStatusView(status: .failed("Błąd monitoringu"), text: "Błąd monitoringu")
    }
    .font(.caption)
    .padding()
}
