import AppKit
import ImageIO
import Testing
@testable import PicSee

@MainActor
struct ImagePrefetchTests {
    @Test func openingAloneDoesNotPrefetchAndPagingOnlyFetchesOneNeighbor() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads()
        let model = ImageViewerViewModel(imageURL: fixture.urls[0],
            readImage: { await reads.read($0) },
            prefetchImage: { url, _ in await reads.prefetch(url) })
        try await eventually { model.image != nil && model.isNavigationOrderReady }
        #expect(await reads.prefetched.isEmpty)
        let original = model.image
        model.navigateToNext()
        try await eventually { model.currentURL == fixture.urls[1] && !model.isImageLoading }
        try await eventually { await reads.prefetched == [fixture.urls[2]] }
        // It does not walk the rest of the folder after the speculative read.
        try await Task.sleep(for: .milliseconds(40))
        #expect(await reads.prefetched == [fixture.urls[2]])
        model.navigateToNext()
        try await eventually { model.currentURL == fixture.urls[2] && !model.isImageLoading }
        #expect(await reads.foreground == [fixture.urls[0], fixture.urls[1]])
        model.navigateToPrevious()
        try await eventually { model.currentURL == fixture.urls[1] && !model.isImageLoading }
        #expect(await reads.foreground == [fixture.urls[0], fixture.urls[1]])
        #expect(original != nil)
    }

    @Test func reversingAfterFirstPageReusesOriginalAndPrefetchesPreviousDirection() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads()
        let model = ImageViewerViewModel(imageURL: fixture.urls[1],
            readImage: { await reads.read($0) },
            prefetchImage: { url, _ in await reads.prefetch(url) })
        try await eventually { model.image != nil && model.isNavigationOrderReady }
        let original = model.image
        model.navigateToNext()
        try await eventually { model.currentURL == fixture.urls[2] && !model.isImageLoading }
        model.navigateToPrevious()
        try await eventually { model.currentURL == fixture.urls[1] && !model.isImageLoading }
        #expect(model.image === original)
        try await eventually { await reads.prefetched.contains(fixture.urls[0]) }
        #expect(await reads.foreground == [fixture.urls[1], fixture.urls[2]])
    }

    @Test func pagingIntoUnfinishedPrefetchDoesNotDecodeTwice() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads(heldURL: fixture.urls[2])
        let model = ImageViewerViewModel(imageURL: fixture.urls[0],
            readImage: { await reads.read($0) },
            prefetchImage: { url, _ in await reads.prefetch(url) })
        try await eventually { model.image != nil && model.isNavigationOrderReady }
        model.navigateToNext()
        try await eventually { await reads.isHeld }
        model.navigateToNext()
        #expect(model.isImageLoading)
        await reads.finish()
        try await eventually { model.currentURL == fixture.urls[2] && !model.isImageLoading }
        #expect(await reads.foreground == [fixture.urls[0], fixture.urls[1]])
        #expect(await reads.prefetched.filter { $0 == fixture.urls[2] }.count == 1)
    }

    @Test func unrelatedPrefetchDoesNotBlockReversePageAndExternalOpenStopsPrefetch() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads(heldURL: fixture.urls[2])
        let model = ImageViewerViewModel(imageURL: fixture.urls[0],
            readImage: { await reads.read($0) },
            prefetchImage: { url, _ in await reads.prefetch(url) })
        try await eventually { model.image != nil && model.isNavigationOrderReady }
        model.navigateToNext()
        try await eventually { await reads.isHeld }
        model.navigateToPrevious()
        try await eventually { model.currentURL == fixture.urls[0] && !model.isImageLoading }
        model.openImage(fixture.urls[3])
        try await eventually { model.currentURL == fixture.urls[3] && !model.isImageLoading }
        await reads.finish()
        await Task.yield()
        #expect(model.currentURL == fixture.urls[3])
        #expect(await reads.foreground == [fixture.urls[0], fixture.urls[1], fixture.urls[3]])
    }

    @Test func changedOrDeletedFilesCannotHitCache() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads()
        let cache = ImagePrefetchCache()
        let first = try #require(LoadedImage.read(fixture.urls[0]))
        let second = try #require(LoadedImage.read(fixture.urls[1]))
        cache.didDisplay(fixture.urls[0], image: first, retainingPrevious: false)
        cache.didDisplay(fixture.urls[1], image: second, retainingPrevious: true)
        try Data("changed".utf8).write(to: fixture.urls[0])
        #expect(await cache.load(fixture.urls[0], reader: { await reads.read($0) }) == nil)
        cache.didDisplay(fixture.urls[1], image: second, retainingPrevious: false)
        cache.didDisplay(fixture.urls[2], image: first, retainingPrevious: true)
        try FileManager.default.removeItem(at: fixture.urls[1])
        #expect(await cache.load(fixture.urls[1], reader: { await reads.read($0) }) == nil)
        #expect(await reads.foreground == [fixture.urls[0], fixture.urls[1]])
    }

    @Test func cacheEvictsOldEntriesAndRejectsImagesOverBudget() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads()
        let loaded = try #require(LoadedImage.read(fixture.urls[0]))
        let cache = ImagePrefetchCache(byteLimit: 4096)
        for url in fixture.urls { cache.didDisplay(url, image: loaded, retainingPrevious: true) }
        _ = await cache.load(fixture.urls[0], reader: { await reads.read($0) })
        _ = await cache.load(fixture.urls[1], reader: { await reads.read($0) })
        _ = await cache.load(fixture.urls[2], reader: { await reads.read($0) })
        #expect(await reads.foreground == [fixture.urls[0]])
        let tiny = ImagePrefetchCache(byteLimit: 1)
        tiny.didDisplay(fixture.urls[0], image: loaded, retainingPrevious: false)
        tiny.didDisplay(fixture.urls[1], image: loaded, retainingPrevious: true)
        _ = await tiny.load(fixture.urls[0], reader: { await reads.read($0) })
        #expect(await reads.foreground == [fixture.urls[0], fixture.urls[0]])
    }

    @Test func productionPrefetchSkipsImagesBeyondBudget() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        #expect(await ImageLoadWorker.prefetch(fixture.urls[0], byteLimit: 1) == nil)
        #expect(await ImageLoadWorker.prefetch(fixture.urls[0], byteLimit: 4096) != nil)
    }

    @Test func aggregateBudgetEvictsPreviousImage() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads()
        let loaded = try #require(LoadedImage.read(fixture.urls[0]))
        let cost = 8 * 8 * 8 + Int(loaded.byteCount ?? 0)
        let cache = ImagePrefetchCache(byteLimit: cost)
        for url in fixture.urls.prefix(3) { cache.didDisplay(url, image: loaded, retainingPrevious: true) }
        _ = await cache.load(fixture.urls[0], reader: { await reads.read($0) })
        _ = await cache.load(fixture.urls[1], reader: { await reads.read($0) })
        #expect(await reads.foreground == [fixture.urls[0]])
    }

    @Test func cancelledPrefetchCannotRepopulateClearedCache() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let reads = PrefetchReads(heldURL: fixture.urls[1])
        let cache = ImagePrefetchCache(prefetchReader: { url, _ in await reads.prefetch(url) })
        cache.prefetch(fixture.urls[1])
        try await eventually { await reads.isHeld }
        cache.clear()
        await reads.finish()
        // Drain the cancelled task's completion before attempting a cache hit.
        try await Task.sleep(for: .milliseconds(20))
        _ = await cache.load(fixture.urls[1], reader: { await reads.read($0) })
        #expect(await reads.foreground == [fixture.urls[1]])
    }

    @Test func animatedImagesAreExcludedFromSpeculativeDecodeAndCache() async throws {
        let fixture = try PrefetchFixture()
        defer { fixture.remove() }
        let loaded = try #require(LoadedImage.read(fixture.urls[0]))
        let cgImage = try #require(loaded.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let gif = fixture.directory.appendingPathComponent("animated.gif")
        let destination = try #require(CGImageDestinationCreateWithURL(gif as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(await ImageLoadWorker.prefetch(gif, byteLimit: 4096) == nil)
        let animation = try #require(LoadedImage.read(gif))
        let reads = PrefetchReads()
        let cache = ImagePrefetchCache()
        cache.didDisplay(gif, image: animation, retainingPrevious: false)
        cache.didDisplay(fixture.urls[0], image: loaded, retainingPrevious: true)
        _ = await cache.load(gif, reader: { await reads.read($0) })
        #expect(await reads.foreground == [gif])
    }

    private func eventually(_ predicate: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw PrefetchTimeout() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct PrefetchTimeout: Error {}

private struct PrefetchFixture {
    let directory: URL
    let urls: [URL]
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PicSee-Prefetch-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder = directory
        urls = try (1...4).map {
            let url = folder.appendingPathComponent("00\($0).png").standardizedFileURL
            try data.write(to: url)
            return url
        }
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private actor PrefetchReads {
    private(set) var foreground: [URL] = []
    private(set) var prefetched: [URL] = []
    private let heldURL: URL?
    private var continuation: CheckedContinuation<Void, Never>?
    var isHeld: Bool { continuation != nil }
    init(heldURL: URL? = nil) { self.heldURL = heldURL }
    func read(_ url: URL) -> LoadedImage? {
        foreground.append(url)
        return LoadedImage.read(url)
    }
    func prefetch(_ url: URL) async -> LoadedImage? {
        prefetched.append(url)
        if url == heldURL { await withCheckedContinuation { continuation = $0 } }
        return LoadedImage.read(url)
    }
    func finish() { continuation?.resume(); continuation = nil }
}
