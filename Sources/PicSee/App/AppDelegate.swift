import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where FolderImageNavigator.isSupportedImage(url) {
            windowManager.openViewer(for: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
