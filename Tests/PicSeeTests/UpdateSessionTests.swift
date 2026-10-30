import AppKit
import XCTest
import SwiftUI
@testable import PicSee

@MainActor
final class UpdateSessionTests: XCTestCase {
    func testSessionIsOneShotAndNormalLaunchDoesNotRestore() throws {
        let state = UpdateSession(viewer: .init(url: URL(fileURLWithPath: "/tmp/image with spaces.png"),
            frame: CGRect(x: 100, y: 80, width: 640, height: 480), zoom: 2.5,
            pan: CGSize(width: 30, height: -12), rotation: 90,
            fullScreen: true, desktopFullScreen: false, minimized: false),
            settingsPage: "about", settingsFrame: CGRect(x: 20, y: 30, width: 724, height: 580),
            settingsInFront: true)
        let url = try state.write()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(UpdateSession.consume(arguments: ["PicSee"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let arguments = ["PicSee", "--picsee-update-session", url.path]
        XCTAssertEqual(UpdateSession.consume(arguments: arguments), state)
        XCTAssertNil(UpdateSession.consume(arguments: arguments))
    }

    func testClosingLastWindowDuringDownloadKeepsProcessUntilInstall() async throws {
        _ = NSApplication.shared
        let suite = "PicSee.UpdateSessionTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let version = try XCTUnwrap(AppVersion("0.2.13"))
        let release = GitHubRelease(tagName: "v0.2.13", version: version, dmgURL: GitHubReleaseClient.dmgDownloadURL(for: version))
        let started = expectation(description: "Download started")
        var continuation: CheckedContinuation<Void, any Error>?
        var installed = false
        let checker = UpdateChecker(currentVersion: try XCTUnwrap(AppVersion("0.2.11")), defaults: defaults,
            fetchLatestRelease: { release }, downloadAndOpen: { _, progress in
                progress(1) // 100% still needs validation and preparation.
                try await withCheckedThrowingContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }, prepareInstall: { installed = true })
        let manager = WindowManager(updateChecker: checker, loadingMode: .immediate)
        let delegate = AppDelegate(windowManager: manager)
        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        await checker.checkForUpdates()
        let download = Task { await checker.downloadAvailableUpdate() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        manager.openViewer(for: URL(fileURLWithPath: "/tmp/picsee-update-missing.png"))
        let hosting = try XCTUnwrap(manager.currentWindow?.contentViewController as? NSHostingController<ImageViewerView>)
        hosting.rootView.onCloseViewer()
        XCTAssertNil(manager.currentWindow)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        XCTAssertEqual(delegate.captureUpdateSession(), UpdateSession())
        XCTAssertFalse(installed)
        continuation?.resume()
        await download.value
        XCTAssertTrue(installed)
        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    func testViewerRestoresImageAndTransformsAndClosedViewerIsNotCaptured() async throws {
        try await verifyViewerRestoration(loadingMode: .immediate)
    }

    func testViewerRestoresAfterBackgroundImageLoading() async throws {
        try await verifyViewerRestoration(loadingMode: .background)
    }

    private func verifyViewerRestoration(loadingMode: ImageLoadingMode) async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("picsee-restore-\(UUID()).png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = WindowManager(updateChecker: nil, loadingMode: loadingMode)
        let state = UpdateSession.Viewer(url: url.standardizedFileURL,
            frame: CGRect(x: 100, y: 100, width: 640, height: 480), zoom: 2,
            pan: CGSize(width: 10, height: 20), rotation: 90,
            fullScreen: false, desktopFullScreen: false, minimized: false)
        let restored = expectation(description: "Viewer restored")
        manager.restoreUpdateViewer(state) { restored.fulfill() }
        defer { manager.currentWindow?.close() }
        await fulfillment(of: [restored], timeout: 3)
        XCTAssertEqual(manager.captureUpdateViewer(), state)
        manager.currentWindow?.close()
        XCTAssertNil(manager.captureUpdateViewer())
    }

    func testMixedSessionCompletesAfterImageLoadAndKeepsSettingsInFront() async throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        defer { NSApp.setActivationPolicy(previousPolicy) }
        NSApp.activate(ignoringOtherApps: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("picsee-mixed-\(UUID()).png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let manager = WindowManager(updateChecker: nil, loadingMode: .background)
        let settings = SettingsWindowController(updateChecker: nil,
            defaultAppHandler: ReadOnlyDefaultAppHandler(), captureFixedWindowFrame: {})
        let delegate = AppDelegate(settingsWindowController: settings, windowManager: manager)
        defer { manager.currentWindow?.close(); settings.window?.close() }
        let viewer = UpdateSession.Viewer(url: url.standardizedFileURL,
            frame: CGRect(x: 100, y: 100, width: 640, height: 480), zoom: 2,
            pan: .zero, rotation: 90, fullScreen: false, desktopFullScreen: false, minimized: false)
        let restored = expectation(description: "Both windows and image ready for tip")
        delegate.restoreUpdateSession(UpdateSession(viewer: viewer, settingsPage: "about", settingsInFront: true)) {
            XCTAssertNotNil(manager.currentViewModel?.image)
            XCTAssertEqual(manager.currentViewModel?.isImageLoading, false)
            XCTAssertEqual(settings.navigation.page, .about)
            XCTAssertTrue(settings.window?.isVisible == true)
            // Settings window should be ordered to the front. In test environments the app may
            // not activate, so check window ordering rather than key-window status.
            let orderedVisible = NSApp.orderedWindows.filter { $0.isVisible }
            XCTAssertTrue(orderedVisible.first === settings.window,
                "active=\(NSApp.isActive) key=\(NSApp.keyWindow?.title ?? "nil") canKey=\(settings.window?.canBecomeKey == true) order=\(NSApp.orderedWindows.map(\.title))")
            restored.fulfill()
        }
        await fulfillment(of: [restored], timeout: 3)
        let settled = expectation(description: "Queued activation cannot steal focus")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        let orderedVisible = NSApp.orderedWindows.filter { $0.isVisible }
        XCTAssertTrue(orderedVisible.first === settings.window,
            "active=\(NSApp.isActive) key=\(NSApp.keyWindow?.title ?? "nil") canKey=\(settings.window?.canBecomeKey == true) order=\(NSApp.orderedWindows.map(\.title))")
    }

    private struct ReadOnlyDefaultAppHandler: DefaultImageAppHandling {
        func isDefaultViewer(for format: DefaultImageFormat) -> Bool { false }
        func setDefaultViewer(for format: DefaultImageFormat) throws { XCTFail("Must not change associations") }
    }

    func testEmptySessionDoesNotOpenSettingsAndSettingsSessionRestoresPage() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate(windowManager: WindowManager(updateChecker: nil))
        delegate.restoreUpdateSession(UpdateSession())
        XCTAssertEqual(delegate.captureUpdateSession(), UpdateSession())
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        delegate.restoreUpdateSession(UpdateSession(settingsPage: "about"))
        XCTAssertEqual(delegate.captureUpdateSession().settingsPage, "about")
        for window in NSApp.windows where !existingWindows.contains(ObjectIdentifier(window)) { window.close() }
        XCTAssertNil(delegate.captureUpdateSession().settingsPage)
    }
}
