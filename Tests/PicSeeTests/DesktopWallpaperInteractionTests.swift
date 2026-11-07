import AppKit
import XCTest
@testable import PicSee

@MainActor
final class DesktopWallpaperInteractionTests: XCTestCase {
    func testFullScreenMenuActionWaitsForDesktopAndKeepsRequestedImage() async throws {
        let window = WallpaperTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                         styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CanvasNSView(frame: window.contentView!.bounds, backend: .vision)
        window.contentView = canvas
        defer { window.close() }
        let original = NSImage(size: NSSize(width: 12, height: 8))
        canvas.image = original
        window.simulatedFullScreen = true
        var applied: [NSImage] = []
        canvas.applyDesktopWallpaper = { image, _ in applied.append(image) }

        canvas.setDesktopWallpaperForMenu(nil)
        canvas.setDesktopWallpaperForMenu(nil)
        XCTAssertEqual(window.exitRequests, 1)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(applied.isEmpty, "Must not call the wallpaper API in the full-screen Space")

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(applied.isEmpty, "A Space notification before full-screen exit must not apply")

        canvas.image = NSImage(size: NSSize(width: 20, height: 10))
        window.simulatedFullScreen = false
        window.simulatedActiveSpace = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(applied.isEmpty, "The exit notification alone does not guarantee an active desktop")

        window.simulatedActiveSpace = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(applied.count, 1)
        XCTAssertTrue(applied.first === original)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(applied.count, 1)
    }

    func testWindowedMenuActionAppliesWithoutFullScreenTransition() async {
        let window = makeWindow()
        let canvas = CanvasNSView(frame: window.contentView!.bounds, backend: .vision)
        window.contentView = canvas
        defer { window.close() }
        canvas.image = NSImage(size: NSSize(width: 12, height: 8))
        let applied = expectation(description: "Wallpaper requested")
        canvas.applyDesktopWallpaper = { _, _ in applied.fulfill() }
        canvas.setDesktopWallpaperForMenu(nil)
        await fulfillment(of: [applied], timeout: 2)
        XCTAssertEqual(window.exitRequests, 0)
    }

    func testDesktopAlreadyActiveWhenExitCompletesAppliesImmediately() {
        let window = makeWindow()
        defer { window.close() }
        window.simulatedFullScreen = true
        let request = DesktopWallpaperRequest()
        var applications = 0
        request.perform(in: window, apply: { applications += 1 }, cancel: { _ in XCTFail("Unexpected cancellation") })
        window.simulatedFullScreen = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertEqual(applications, 1)
    }

    func testClosingWindowCancelsPendingMenuRequest() async {
        let window = makeWindow()
        let canvas = CanvasNSView(frame: window.contentView!.bounds, backend: .vision)
        window.contentView = canvas
        canvas.image = NSImage(size: NSSize(width: 12, height: 8))
        window.simulatedFullScreen = true
        var applications = 0
        canvas.applyDesktopWallpaper = { _, _ in applications += 1 }
        canvas.setDesktopWallpaperForMenu(nil)
        window.close()
        window.simulatedFullScreen = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(applications, 0)
    }

    func testFailedFullScreenExitCancelsAndAllowsRetry() {
        let window = makeWindow()
        defer { window.close() }
        window.simulatedFullScreen = true
        let request = DesktopWallpaperRequest()
        var applications = 0
        var failures: [Bool] = []
        request.perform(in: window, apply: { applications += 1 }, cancel: { failures.append($0) })
        NotificationCenter.default.post(name: ViewerWindow.didFailToExitFullScreenNotification, object: window)
        XCTAssertEqual(failures, [true])
        XCTAssertEqual(applications, 0)
        request.perform(in: window, apply: { applications += 1 }, cancel: { _ in XCTFail("Unexpected cancellation") })
        XCTAssertEqual(window.exitRequests, 2)
        window.simulatedFullScreen = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertEqual(applications, 1)
    }

    private func makeWindow() -> WallpaperTestWindow {
        let window = WallpaperTestWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                         styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}

@MainActor
private final class WallpaperTestWindow: NSWindow {
    var simulatedFullScreen = false
    var simulatedActiveSpace = true
    var exitRequests = 0
    override var styleMask: NSWindow.StyleMask {
        get { simulatedFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask }
        set { super.styleMask = newValue }
    }
    override var isOnActiveSpace: Bool { simulatedActiveSpace }
    override func toggleFullScreen(_ sender: Any?) { exitRequests += 1 }
}
