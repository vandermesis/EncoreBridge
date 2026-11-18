import AppKit
import SwiftUI

struct MenuBarContentView: View {
    let monitor: PlaybackMonitor

    var body: some View {
        PlaybackPanelView(sources: monitor.playingSources)
    }
}

private struct PlaybackPanelView: View {
    let sources: [PlaybackSourceSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if sources.isEmpty {
                Text("Brak odtwarzania")
                    .foregroundStyle(.secondary)
            }
            ForEach(sources) { source in
                if source.id != sources.first?.id {
                    Divider()
                }
                PlaybackSourceView(source: source)
            }
        }
        .padding(20)
        .frame(width: panelWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playbackPanel")
    }

    private var panelWidth: CGFloat {
        let titleFont = NSFont.preferredFont(forTextStyle: .headline, options: [:])
        let artistFont = NSFont.preferredFont(forTextStyle: .subheadline, options: [:])
        let widestLine = sources.reduce(CGFloat.zero) { width, source in
            let titleWidth = (source.playback.title as NSString).size(withAttributes: [.font: titleFont]).width
            let artistWidth = (source.playback.artist as NSString).size(withAttributes: [.font: artistFont]).width
            return max(width, titleWidth, artistWidth)
        }
        return min(400, max(300, ceil(widestLine) + 44))
    }
}

private struct PlaybackSourceView: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let source: PlaybackSourceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(informationColor)
                .accessibilityIdentifier("source.\(source.id)")

            VStack(alignment: .leading, spacing: 3) {
                Text(source.playback.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("currentTrack.\(source.id)")

                if !source.playback.artist.isEmpty {
                    Text(source.playback.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("currentArtist.\(source.id)")
                }
            }

            let values = [source.audioFormat.fileFormat,
                          source.audioFormat.bitDepth,
                          source.audioFormat.sampleRate].compactMap { $0 }
            if !values.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        if index > 0 {
                            Text("·")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        Text(value)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(index == 0 && source.audioFormat.fileFormat != nil
                                             ? informationColor : Color.primary)
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playbackSource.\(source.id)")
    }

    private var informationColor: Color {
        // Blend toward the system text color for readable small labels in both appearances.
        // Keep small informational labels maximally legible with Increase Contrast.
        contrast == .increased ? .primary : Color(nsColor: .systemIndigo).mix(with: .primary, by: 0.15)
    }
}

#Preview("Both Sources") {
    PlaybackPanelView(sources: [
        PlaybackSourceSnapshot(id: "appleMusic", title: "Apple Music",
            playback: MusicPlaybackSnapshot(id: "music", title: "Dancing in the Dark", artist: "Diana Krall", album: "", sampleRate: "96 kHz", fileURL: nil),
            audioFormat: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit")),
        PlaybackSourceSnapshot(id: "roon", title: "Roon",
            playback: MusicPlaybackSnapshot(id: "roon", title: "Rehab", artist: "Amy Winehouse", album: "", sampleRate: "44.1 kHz", fileURL: nil),
            audioFormat: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "44.1 kHz", bitDepth: "16-bit"))
    ])
}

#Preview("Unknown Depth") {
    PlaybackPanelView(sources: [
        PlaybackSourceSnapshot(id: "appleMusic", title: "Apple Music",
            playback: MusicPlaybackSnapshot(id: "preview", title: "Everything in Its Right Place", artist: "Radiohead", album: "Kid A", sampleRate: "44.1 kHz", fileURL: nil),
            audioFormat: AudioFormatSnapshot(fileFormat: "AAC", sampleRate: "44.1 kHz"))
    ])
}

#Preview("Long Metadata") {
    PlaybackPanelView(sources: [
        PlaybackSourceSnapshot(id: "roon", title: "Roon",
            playback: MusicPlaybackSnapshot(id: "long", title: "The Great Gig in the Sky (Live at Wembley, London, November 1974)", artist: "Pink Floyd", album: "", sampleRate: "96 kHz", fileURL: nil),
            audioFormat: AudioFormatSnapshot(fileFormat: "ALAC", sampleRate: "96 kHz", bitDepth: "24-bit"))
    ])
}
