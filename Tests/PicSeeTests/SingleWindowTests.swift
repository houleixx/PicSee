import AppKit
import Testing
@testable import PicSee

@Suite(.serialized)
@MainActor
struct SingleWindowTests {
    @Test func routesOnlyFirstImageWithoutSpawning() {
        let urls = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        for hasViewer in [true, false] {
            let route = ImageOpenRouting.route(urls: urls, hasOpenViewer: hasViewer, singleWindowEnabled: true)
            #expect(route.currentProcessURL == urls[0])
            #expect(route.spawnedProcessURLs.isEmpty)
        }
        let empty = ImageOpenRouting.route(urls: [], hasOpenViewer: true, singleWindowEnabled: true)
        #expect(empty.currentProcessURL == nil)
        #expect(empty.spawnedProcessURLs.isEmpty)
    }

    @Test func receiverHonorsChoiceAndRecoversFromExitOrPIDReuse() {
        let first = SingleWindowRouter.Instance(pid: 10, launchedAt: 100)
        let second = SingleWindowRouter.Instance(pid: 20, launchedAt: 200)
        #expect(SingleWindowRouter.receiver(in: [second, first], preferredIdentity: nil) == first)
        #expect(SingleWindowRouter.receiver(in: [first, second], preferredIdentity: second.identity) == second)
        #expect(SingleWindowRouter.receiver(in: [first], preferredIdentity: second.identity) == first)
        let reused = SingleWindowRouter.Instance(pid: second.pid, launchedAt: 300)
        #expect(SingleWindowRouter.receiver(in: [reused, first], preferredIdentity: second.identity) == first)
        #expect(SingleWindowRouter.receiver(in: [], preferredIdentity: second.identity) == nil)
    }

    @Test func preferenceAndContextMenuSharePersistentState() throws {
        let suite = "PicSee.SingleWindowTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        #expect(!preferences.snapshot.singleWindowEnabled)
        preferences.set(\.singleWindowEnabled, to: true)
        #expect(ViewerPreferences(defaults: defaults).snapshot.singleWindowEnabled)
        let canvas = CanvasNSView(frame: .zero, backend: .vision, defaults: defaults)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        #expect(menu.items.filter { $0.title == "单窗口看图" }.count == 1)
        #expect(menu.items.first { $0.title == "单窗口看图" }?.state == .on)
        canvas.toggleSingleWindowForMenu(nil)
        preferences.reload()
        #expect(!preferences.snapshot.singleWindowEnabled)
    }

    @Test func replacementResetsSessionAndNavigatesNewFolder() async throws {
        let fixture = try Images()
        defer { fixture.remove() }
        let model = ImageViewerViewModel(imageURL: fixture.a)
        model.zoomScale = 4
        model.panOffset = CGSize(width: 80, height: 20)
        model.rotateLeft()
        model.zoomIn()
        model.isScreenshotEditing = true
        model.startSlideshow()
        let session = model.sessionID
        #expect(model.openImage(fixture.b))
        #expect(model.sessionID != session)
        #expect(model.zoomScale == 1)
        #expect(model.panOffset == .zero)
        #expect(model.rotationDegrees == 0)
        #expect(model.zoomRequest == nil)
        #expect(!model.isScreenshotEditing)
        #expect(model.slideshow.state == .stopped)
        try await ready(model)
        #expect(model.nextURL == fixture.c)
        model.navigateToNext()
        #expect(model.currentURL == fixture.c)
        model.navigateToPrevious()
        #expect(model.currentURL == fixture.b)
    }

    @Test func sameImagePreservesTransformsAndFailedOpenPreservesSession() async throws {
        let fixture = try Images()
        defer { fixture.remove() }
        let model = ImageViewerViewModel(imageURL: fixture.b)
        try await ready(model)
        model.zoomScale = 3
        model.panOffset = CGSize(width: 8, height: 12)
        model.rotationDegrees = 90
        model.isScreenshotEditing = true
        let session = model.sessionID
        let image = model.image
        #expect(model.openImage(fixture.b))
        #expect(!model.openImage(fixture.root.appendingPathComponent("missing.png")))
        #expect(model.currentURL == fixture.b)
        #expect(model.image === image)
        #expect(model.sessionID == session)
        #expect(model.zoomScale == 3)
        #expect(model.panOffset == CGSize(width: 8, height: 12))
        #expect(model.rotationDegrees == 90)
        #expect(model.isScreenshotEditing)
        #expect(model.nextURL == fixture.c)
        #expect(model.fileOperationError != nil)
    }

    @Test func sameFolderRefreshesNewFilesAndStopsPlayback() async throws {
        let fixture = try Images()
        defer { fixture.remove() }
        let model = ImageViewerViewModel(imageURL: fixture.b)
        try await ready(model)
        let added = fixture.c.deletingLastPathComponent().appendingPathComponent("03.png")
        try FileManager.default.copyItem(at: fixture.c, to: added)
        model.startSlideshow()
        #expect(model.slideshow.isActive)
        #expect(model.openImage(fixture.c))
        try await ready(model)
        #expect(model.slideshow.state == .stopped)
        #expect(model.nextURL == added)
    }

    @Test func lateOldFolderOrderCannotOverrideNewSession() async throws {
        let fixture = try Images()
        defer { fixture.remove() }
        let model = ImageViewerViewModel(imageURL: fixture.a, finderOrderProvider: DelayedOrder())
        model.navigateToNext() // queued in the old session
        #expect(model.openImage(fixture.b))
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.currentURL == fixture.b)
        #expect(model.nextURL == fixture.c)
    }

    @Test func reusesWindowAndKeepsFrame() async throws {
        _ = NSApplication.shared
        let fixture = try Images()
        defer { fixture.remove() }
        let manager = WindowManager(finderOrderProvider: FilenameFolderOrderProvider())
        manager.openInExistingViewer(for: fixture.a)
        let window = try #require(manager.currentWindow)
        defer { window.close() }
        let model = try #require(manager.currentViewModel)
        let frame = window.frame
        model.zoomScale = 4
        manager.openInExistingViewer(for: fixture.b)
        #expect(manager.currentWindow === window)
        #expect(manager.currentViewModel === model)
        #expect(window.frame == frame)
        #expect(model.zoomScale == 1)
        #expect(model.currentURL == fixture.b)
        try await ready(model)
        #expect(model.nextURL == fixture.c)
    }

    private func ready(_ model: ImageViewerViewModel) async throws {
        for _ in 0..<100 {
            if model.isNavigationOrderReady { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Directory order did not become ready")
    }

    private struct DelayedOrder: FinderFolderOrderProviding {
        func orderedURLs(for folderURL: URL) async -> [URL]? {
            // Intentionally returns after cancellation, like an external Finder request.
            try? await Task.sleep(for: .milliseconds(150))
            return try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
        }
    }

    private struct Images {
        let root: URL
        let a: URL
        let b: URL
        let c: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("PicSeeSingle-\(UUID())")
                .standardizedFileURL
            let old = root.appendingPathComponent("old")
            let new = root.appendingPathComponent("new")
            try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
            a = old.appendingPathComponent("01.png")
            b = new.appendingPathComponent("01.png")
            c = new.appendingPathComponent("02.png")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 10,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let data = bitmap.representation(using: .png, properties: [:])!
            for url in [a, b, c] { try data.write(to: url) }
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
