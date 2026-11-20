import AppKit
import ApplicationServices

/// Reads the source quality displayed by Music using Accessibility.
///
/// Requires an existing Accessibility grant. The service can press Music's
/// quality badge and attempt to close the popover it observes afterward.
@MainActor
final class MusicQualityService {
    var hasReadAccess: Bool { AXIsProcessTrusted() }

    /// Looks for the quality badge under visible metadata matching the track's title.
    ///
    /// Each sleep allows the UI to update between reads. The caller verifies
    /// the current track again after this asynchronous operation.
    func audioFormat(for track: MusicPlaybackSnapshot) async -> AudioFormatSnapshot? {
        guard hasReadAccess,
              let music = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else { return nil }
        let application = AXUIElementCreateApplication(music.processIdentifier)
        guard let metadata = find(in: application, matching: {
            string($0, kAXIdentifierAttribute) == "Music.miniPlayer.metadataRegion[state=populated]"
        }), find(in: metadata, matching: { element in
            text(element).contains { $0.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) == track.title }
        }) != nil,
              let badge = find(in: metadata, matching: {
                  string($0, kAXIdentifierAttribute) == "Music.miniPlayer.audioBadge"
              }) else { return nil }

        let existingPopover = find(in: application, matching: { string($0, kAXRoleAttribute) == "AXPopover" })
        if existingPopover == nil {
            guard AXUIElementPerformAction(badge, kAXPressAction as CFString) == .success else { return nil }
        }
        var openedPopover: AXUIElement?
        defer {
            if existingPopover == nil, let openedPopover {
                AXUIElementPerformAction(openedPopover, kAXCancelAction as CFString)
            }
        }
        for _ in 0..<20 {
            guard !Task.isCancelled else { return nil }
            if let popover = find(in: application, matching: { string($0, kAXRoleAttribute) == "AXPopover" }) {
                openedPopover = popover
                if let label = find(in: popover, matching: { element in
                    text(element).contains { AudioFormatParser().parseQualityLabel($0) != nil }
                }) {
                    return text(label).compactMap { AudioFormatParser().parseQualityLabel($0) }.first
                }
            }
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return nil }
        }
        return nil
    }

    private func find(in root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var pending = [root]
        var visited = 0
        while let element = pending.popLast(), visited < 500 {
            visited += 1
            if predicate(element) { return element }
            // Music's library tables are large and unrelated to Now Playing.
            let role = string(element, kAXRoleAttribute)
            if role == "AXTable" || role == "AXOutline" || role == "AXMenuBar" { continue }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] {
                pending.append(contentsOf: children.reversed())
            }
        }
        return nil
    }

    private func text(_ element: AXUIElement) -> [String] {
        [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].compactMap { string(element, $0) }
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
