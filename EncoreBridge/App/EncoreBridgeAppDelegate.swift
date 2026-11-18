import AppKit

/// Connects the application lifetime to services that must outlive every window.
@MainActor
final class EncoreBridgeAppDelegate: NSObject, NSApplicationDelegate {
    let runtime = ApplicationRuntime()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.stop()
    }
}
