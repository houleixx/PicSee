import AppKit
import SwiftUI
import XCTest
@testable import PicSee

@MainActor
final class UpdateSessionTests: XCTestCase {
    func testTallUpdateCardStaysAboveWindowBottomWhenBesideToolbar() async throws {
        _ = NSApplication.shared
        let measured = expectation(description: "Update card layout")
        let width: CGFloat = 900
        let height: CGFloat = 360
        let inset: CGFloat = 12
        let host = NSHostingView(rootView: ViewerBottomControlsLayout(inset: inset) {
            Color.clear.frame(width: 240, height: 140)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named("viewer"))
                } action: { frame in
                    guard frame.height == 140 else { return }
                    XCTAssertEqual(frame.maxY, height - inset, accuracy: 1)
                    measured.fulfill()
                }
            Color.clear.frame(width: 250, height: 32)
        }
        .frame(width: width, height: height)
        .coordinateSpace(name: "viewer"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        await fulfillment(of: [measured], timeout: 2)
    }

    func testUpdateErrorDetailsScrollAtViewerAndSettingsWidths() async throws {
        _ = NSApplication.shared
        let longMessage = (1...36).map { "第 \($0) 行，更新校验失败。Update verification failed." }
            .joined(separator: "\n")

        for width: CGFloat in [216, 420] {
            let host = NSHostingView(rootView: UpdateErrorDetails(message: longMessage)
                .font(.system(size: 12))
                .frame(width: width))
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline {
                if let scrollView = findScrollView(in: host),
                   let document = scrollView.documentView,
                   document.bounds.height > scrollView.contentView.bounds.height {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
                host.layoutSubtreeIfNeeded()
            }

            XCTAssertEqual(host.frame.height, 96, accuracy: 1)
            let scrollView = try XCTUnwrap(findScrollView(in: host))
            let document = try XCTUnwrap(scrollView.documentView)
            XCTAssertGreaterThan(document.bounds.height, scrollView.contentView.bounds.height)

            let clip = scrollView.contentView
            let bottom = document.isFlipped ? document.bounds.maxY - clip.bounds.height : document.bounds.minY
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: bottom))
            scrollView.reflectScrolledClipView(clip)
            let visible = scrollView.documentVisibleRect
            let distanceFromEnd = document.isFlipped
                ? document.bounds.maxY - visible.maxY
                : visible.minY - document.bounds.minY
            XCTAssertEqual(distanceFromEnd, 0, accuracy: 1)
        }
    }

    func testCompactUpdateCardMovesAboveToolbarAsViewerNarrows() async {
        _ = NSApplication.shared
        let besideToolbar = expectation(description: "Card beside toolbar")
        let aboveToolbar = expectation(description: "Card above toolbar")
        let height: CGFloat = 360
        let inset: CGFloat = 12
        let toolbarHeight: CGFloat = 32
        let wide = NSSize(width: 900, height: height)
        let narrow = NSSize(width: 650, height: height)
        let host = NSHostingView(rootView: ViewerBottomControlsLayout(inset: inset) {
            Color.clear.frame(width: 192, height: 72)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named("viewer"))
                } action: { frame in
                    guard frame.width == 192 else { return }
                    if abs(frame.maxY - (height - inset)) < 1 {
                        besideToolbar.fulfill()
                    } else if abs(frame.maxY - (height - toolbarHeight - 2 * inset)) < 1 {
                        aboveToolbar.fulfill()
                    }
                }
            Color.clear.frame(width: 250, height: toolbarHeight)
        }
        .coordinateSpace(name: "viewer"))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: wide),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        await fulfillment(of: [besideToolbar], timeout: 2)
        window.setContentSize(narrow)
        await fulfillment(of: [aboveToolbar], timeout: 2)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) { return scrollView }
        }
        return nil
    }

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
        let defaults = UserDefaults.standard
        let preferences: [String: Any] = [
            AutomaticWindowSizePreference.defaultsKey: true,
            AutomaticWindowResizeAnimationPreference.defaultsKey: false,
            "PicSee.FixedWindowFrameEnabled": false,
            ImageDisplayPreference.defaultsKey: ImageDisplayMode.fitWindow.rawValue
        ]
        let savedPreferences = (Array(preferences.keys) + [WindowFramePreference.defaultsKey])
            .map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in savedPreferences { defaults.set(value, forKey: key) }
            ViewerPreferences.shared.reload()
        }
        for (key, value) in preferences { defaults.set(value, forKey: key) }
        ViewerPreferences.shared.reload()

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("picsee-restore-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func writePNG(_ name: String, width: Int, height: Int) throws -> URL {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let url = folder.appendingPathComponent(name).standardizedFileURL
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            return url
        }
        let first = try writePNG("01.png", width: 100, height: 100)
        let second = try writePNG("02.png", width: 1600, height: 1000)
        let manager = WindowManager(updateChecker: nil, finderOrderProvider: FilenameFolderOrderProvider(),
            loadingMode: loadingMode, screenGeometryOverride: (CGRect(x: 0, y: 0, width: 1440, height: 900), 2))
        let state = UpdateSession.Viewer(url: first,
            frame: CGRect(x: 100, y: 100, width: 640, height: 480), zoom: 2,
            pan: CGSize(width: 10, height: 20), rotation: 90,
            fullScreen: false, desktopFullScreen: false, minimized: false)
        let restored = expectation(description: "Viewer restored")
        manager.restoreUpdateViewer(state) { DispatchQueue.main.async { restored.fulfill() } }
        defer { manager.currentWindow?.close() }
        await fulfillment(of: [restored], timeout: 3)
        XCTAssertEqual(manager.captureUpdateViewer(), state)
        let window = try XCTUnwrap(manager.currentWindow)
        let model = try XCTUnwrap(manager.currentViewModel)
        model.navigate(to: second)
        for _ in 0..<100 where window.frame.width != 800 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.currentURL, second)
        XCTAssertEqual(window.frame.width, 800, accuracy: 0.5)
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
