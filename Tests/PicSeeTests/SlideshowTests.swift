import AppKit
import SwiftUI
import Testing
@testable import PicSee

// App activation notifications are process-wide; keep these playback sessions isolated.
@Suite(.serialized)
@MainActor
struct SlideshowTests {
    @Test func waitsForFinderThenUsesItsOrder() async throws {
        let fixture = try Fixture(order: [2, 0, 3, 1], deferredOrder: true)
        defer { fixture.cleanUp() }
        fixture.model.startSlideshow()
        #expect(fixture.controller.state == .playing)
        #expect(fixture.clock.pending.isEmpty)
        try await eventually { !fixture.orderClock.pending.isEmpty }
        fixture.orderClock.fireFirst()
        try await eventually { !fixture.clock.pending.isEmpty }
        #expect(fixture.clock.pending[0].duration == .seconds(5))
        #expect(fixture.model.currentURL == fixture.urls[0])
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[3] }
        #expect(fixture.model.nextURL == fixture.urls[1])
    }

    @Test func manualNavigationRestartsFullIntervalAndIgnoresOldDelay() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        fixture.model.navigateToNext()
        #expect(fixture.model.currentURL == fixture.urls[1])
        try await eventually { fixture.clock.pending.count == 2 }
        fixture.clock.fireFirst() // A cancelled sleep completing late must do nothing.
        await drainTasks()
        #expect(fixture.model.currentURL == fixture.urls[1])
        #expect(fixture.clock.pending[0].duration == .seconds(5))
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[2] }
    }

    @Test func pauseAndResumeDoNotCarryOverAnOldDeadline() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        fixture.controller.pause()
        fixture.clock.fireFirst()
        await drainTasks()
        #expect(fixture.model.currentURL == fixture.urls[0])
        #expect(fixture.controller.state == .paused)
        #expect(fixture.clock.pending.isEmpty)
        fixture.controller.togglePause()
        try await eventually { !fixture.clock.pending.isEmpty }
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[1] }
    }

    @Test(arguments: [false, true])
    func lastImageStopsOrWraps(loops: Bool) async throws {
        let fixture = try Fixture(startIndex: 3)
        defer { fixture.cleanUp() }
        fixture.controller.loops = loops
        try await fixture.start()
        fixture.clock.fireFirst()
        try await eventually {
            loops ? fixture.model.currentURL == fixture.urls[0] : fixture.controller.state == .stopped
        }
        #expect(fixture.model.currentURL == fixture.urls[loops ? 0 : 3])
        #expect(fixture.model.image != nil)
    }

    @Test func skipsCorruptAndDeletedFilesWithoutShowingAnError() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        try Data("not an image".utf8).write(to: fixture.urls[1])
        try FileManager.default.removeItem(at: fixture.urls[2])
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[3] }
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.model.image != nil)
    }

    @Test func allRemainingFilesInvalidStopsAndKeepsCurrentImage() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        for url in fixture.urls.dropFirst() { try Data("bad".utf8).write(to: url) }
        fixture.clock.fireFirst()
        try await eventually { fixture.controller.state == .stopped }
        #expect(fixture.model.currentURL == fixture.urls[0])
        #expect(fixture.model.image != nil)
        #expect(fixture.model.errorMessage == nil)
    }

    @Test func singleImageEndsAfterOneInterval() async throws {
        let fixture = try Fixture(count: 1)
        defer { fixture.cleanUp() }
        try await fixture.start()
        fixture.clock.fireFirst()
        try await eventually { fixture.controller.state == .stopped }
        #expect(fixture.model.currentURL == fixture.urls[0])
    }

    @Test(arguments: ["zoom", "rotate", "screenshot", "inactive", "stop", "open"])
    func interruptionsCancelPendingAdvance(action: String) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        switch action {
        case "zoom": fixture.model.zoomIn()
        case "rotate": fixture.model.rotateLeft()
        case "screenshot": fixture.model.isScreenshotEditing = true
        case "inactive": NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
        case "open": fixture.model.navigate(to: fixture.urls[0])
        default: fixture.controller.stop()
        }
        fixture.clock.fireFirst()
        await drainTasks()
        #expect(fixture.model.currentURL == fixture.urls[0])
        #expect(fixture.controller.state == (action == "stop" || action == "open" ? .stopped : .paused))
    }

    @Test func deletionPausesBeforeConfirmationAndCancellationKeepsImage() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        let confirmation = ImageDeletionConfirmation(defaults: fixture.defaults) { _, _, completion in
            #expect(fixture.controller.state == .paused)
            #expect(fixture.model.currentURL == fixture.urls[0])
            completion(.alertFirstButtonReturn)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        confirmation.requestDeletion(for: fixture.model, in: window)
        fixture.clock.fireFirst()
        await drainTasks()
        #expect(fixture.model.currentURL == fixture.urls[0])
        #expect(FileManager.default.fileExists(atPath: fixture.urls[0].path))
        #expect(fixture.controller.state == .paused)
    }

    @Test func windowLosingFocusPausesWithoutResumingAutomatically() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let canvas = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        canvas.slideshow = fixture.controller
        let window = NSWindow(contentRect: canvas.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        try await fixture.start()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        fixture.clock.fireFirst()
        await drainTasks()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        #expect(fixture.controller.state == .paused)
        #expect(fixture.model.currentURL == fixture.urls[0])
    }

    @Test func fullScreenTransitionPreservesPlaybackAndRestartsInterval() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        fixture.controller.beginFullScreenTransition()
        fixture.controller.pauseForWindowDeactivation()
        fixture.clock.fireFirst()
        await drainTasks()
        #expect(fixture.controller.state == .playing)
        #expect(fixture.controller.isFullScreenTransitioning)
        #expect(fixture.model.currentURL == fixture.urls[0])
        #expect(fixture.clock.pending.isEmpty)
        fixture.controller.endFullScreenTransition()
        try await eventually { !fixture.clock.pending.isEmpty }
        #expect(!fixture.controller.isFullScreenTransitioning)
        #expect(fixture.clock.pending[0].duration == .seconds(5))
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[1] }
    }

    @Test func reattachingViewerDuringFullScreenDoesNotStopPlayback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let host = NSHostingView(rootView: ImageViewerView(
            viewModel: fixture.model, updateChecker: nil,
            onTitleBarVisibilityChanged: { _ in }, onFixedWindowChanged: { _ in }, onRequestDeletion: {}
        ))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(50))
        try await fixture.start()
        fixture.controller.beginFullScreenTransition()
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.controller.state == .playing)
        window.contentView = host
        fixture.controller.endFullScreenTransition()
        try await eventually { fixture.clock.pending.count == 2 }
        fixture.clock.fireFirst()
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[1] }
        #expect(fixture.controller.state == .playing)
    }

    @Test(arguments: ["paused", "stopped", "inactive"])
    func finishingFullScreenDoesNotOverrideUserState(interruption: String) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        if interruption == "paused" { fixture.controller.pause() }
        fixture.controller.beginFullScreenTransition()
        if interruption == "stopped" { fixture.controller.stop() }
        if interruption == "inactive" {
            NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: NSApp)
        }
        fixture.controller.endFullScreenTransition()
        fixture.clock.fireFirst()
        await drainTasks()
        #expect(fixture.controller.state == (interruption == "stopped" ? .stopped : .paused))
        #expect(fixture.clock.pending.isEmpty)
        #expect(fixture.model.currentURL == fixture.urls[0])
    }

    @Test func intervalAndLoopPreferencesPersistWithSafeDefaults() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.controller.interval == 5)
        #expect(fixture.controller.loops)
        fixture.controller.setInterval(3)
        fixture.controller.loops = false
        let restored = SlideshowController(defaults: fixture.defaults)
        #expect(restored.interval == 3)
        #expect(!restored.loops)
        restored.setInterval(-1)
        #expect(restored.interval == 3)
        fixture.defaults.set(0, forKey: SlideshowController.intervalKey)
        #expect(SlideshowController(defaults: fixture.defaults).interval == 5)
    }

    @Test func changingIntervalReplacesPendingDelay() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await fixture.start()
        fixture.controller.setInterval(10)
        try await eventually { fixture.clock.pending.count == 2 }
        fixture.clock.fireFirst()
        await drainTasks()
        #expect(fixture.model.currentURL == fixture.urls[0])
        #expect(fixture.clock.pending[0].duration == .seconds(10))
        fixture.clock.fireFirst()
        try await eventually { fixture.model.currentURL == fixture.urls[1] }
    }

    @Test func playbackKeysAreScopedAndDoNotRepeatIntoQuit() {
        #expect(KeyboardNavigation.action(for: 49, slideshowActive: true) == .toggleSlideshowPause)
        #expect(KeyboardNavigation.action(for: 53, slideshowActive: true) == .endSlideshow)
        #expect(KeyboardNavigation.action(for: 49) == .quit)
        #expect(KeyboardNavigation.action(for: 53) == .quit)
        #expect(KeyboardNavigation.action(for: 53, isRepeat: true) == .none)
        #expect(KeyboardNavigation.action(for: 49, isRepeat: true, slideshowActive: true) == .none)
        #expect(KeyboardNavigation.action(for: 49, modifiers: .command, slideshowActive: true) == .none)
    }

    @Test func contextMenuStartsResumesAndEndsPlayback() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try await eventually { fixture.model.isNavigationOrderReady }
        let canvas = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        canvas.slideshow = fixture.controller
        canvas.onStartSlideshow = fixture.model.startSlideshow
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        #expect(canvas.menu(for: event)?.items.contains { $0.title == "播放幻灯片" } == true)
        canvas.toggleSlideshowForMenu(nil)
        #expect(fixture.controller.state == .playing)
        let menu = try #require(canvas.menu(for: event))
        #expect(fixture.controller.state == .paused)
        #expect(menu.items.contains { $0.title == "继续幻灯片" })
        #expect(menu.items.contains { $0.title == "结束幻灯片" })
        canvas.toggleSlideshowForMenu(nil)
        #expect(fixture.controller.state == .playing)
        canvas.endSlideshowForMenu(nil)
        #expect(fixture.controller.state == .stopped)
    }

    private func drainTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw WaitError.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private enum WaitError: Error { case timeout }

    @MainActor
    private final class ManualDelay {
        struct Pending {
            let duration: Duration
            let continuation: CheckedContinuation<Void, Never>
        }
        var pending: [Pending] = []
        func sleep(_ duration: Duration) async {
            await withCheckedContinuation { pending.append(Pending(duration: duration, continuation: $0)) }
        }
        func fireFirst() { pending.removeFirst().continuation.resume() }
        func finish() { while !pending.isEmpty { fireFirst() } }
    }

    private struct OrderProvider: FinderFolderOrderProviding {
        let urls: [URL]
        let clock: ManualDelay?
        func orderedURLs(for folderURL: URL) async -> [URL]? {
            if let clock { await clock.sleep(.seconds(1)) }
            return urls
        }
    }

    @MainActor
    private struct Fixture {
        let directory: URL
        let urls: [URL]
        let suite = "PicSeeSlideshowTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let clock = ManualDelay()
        let orderClock = ManualDelay()
        let controller: SlideshowController
        let model: ImageViewerViewModel

        init(count: Int = 4, startIndex: Int = 0, order: [Int]? = nil, deferredOrder: Bool = false) throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite).standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = directory
            urls = try (0..<count).map { index in
                let url = directory.appendingPathComponent("\(index).png")
                try data.write(to: url)
                return url
            }
            let clock = clock
            controller = SlideshowController(defaults: defaults, sleep: { await clock.sleep($0) })
            let urls = urls
            let provider = OrderProvider(urls: (order ?? Array(0..<count)).map { urls[$0] },
                clock: deferredOrder ? orderClock : nil)
            model = ImageViewerViewModel(imageURL: urls[startIndex], finderOrderProvider: provider, slideshow: controller)
        }

        func start() async throws {
            try await SlideshowTests().eventually { model.isNavigationOrderReady }
            model.startSlideshow()
            try await SlideshowTests().eventually { !clock.pending.isEmpty }
        }

        func cleanUp() {
            controller.stop()
            clock.finish()
            orderClock.finish()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
