import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageLoadingTests: XCTestCase {
    private var directory: URL!
    private var images: [URL] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PicSee-LoadingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        images = try (1...3).map { number in
            let url = directory.appendingPathComponent("00\(number).png")
            try data.write(to: url)
            return url.standardizedFileURL
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testInitialLoadDoesNotBlockMainActorAndQueuesNavigation() async throws {
        let gate = ImageReadGate()
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: images[0],
            readImage: { await gate.read($0) })
        XCTAssertTrue(model.isImageLoading)
        XCTAssertNil(model.image)
        model.navigateToNext()
        try await waitUntil { model.isNavigationOrderReady }
        try await waitUntil { await gate.hasRequest(self.images[0]) }
        await gate.finish(images[0], result: LoadedImage.read(images[0]))
        try await waitUntil { await gate.hasRequest(self.images[1]) }
        await gate.finish(images[1], result: LoadedImage.read(images[1]))
        try await waitUntil { !model.isImageLoading }
        XCTAssertEqual(model.currentURL, images[1])
        XCTAssertNotNil(model.image)
    }

    func testLateLoadCannotReplaceNewestNavigationRequest() async throws {
        let gate = ImageReadGate()
        let first = try XCTUnwrap(LoadedImage.read(images[0]))
        let firstURL = images[0]
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: firstURL,
            readImage: { url in url == firstURL ? first : await gate.read(url) })
        try await waitUntil { model.image != nil && model.isNavigationOrderReady }
        model.navigateToNext()
        try await waitUntil { await gate.hasRequest(self.images[1]) }
        model.navigateToNext()
        try await waitUntil { await gate.hasRequest(self.images[2]) }
        await gate.finish(images[2], result: LoadedImage.read(images[2]))
        try await waitUntil { !model.isImageLoading }
        await gate.finish(images[1], result: LoadedImage.read(images[1]))
        await Task.yield()
        XCTAssertEqual(model.currentURL, images[2])
        XCTAssertFalse(model.isImageLoading)
    }

    func testReopeningDisplayedImageCancelsPendingReplacementWithoutResettingSession() async throws {
        let gate = ImageReadGate()
        let first = try XCTUnwrap(LoadedImage.read(images[0]))
        let firstURL = images[0]
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: firstURL,
            readImage: { url in url == firstURL ? first : await gate.read(url) })
        try await waitUntil { model.image != nil && model.isNavigationOrderReady }
        let session = model.sessionID
        model.zoomScale = 3
        model.openImage(images[1])
        try await waitUntil { await gate.hasRequest(self.images[1]) }
        model.openImage(images[0])
        XCTAssertFalse(model.isImageLoading)
        await gate.finish(images[1], result: LoadedImage.read(images[1]))
        await Task.yield()
        XCTAssertEqual(model.currentURL, images[0])
        XCTAssertEqual(model.sessionID, session)
        XCTAssertEqual(model.zoomScale, 3)
    }

    func testFailedExternalOpenPreservesImageTransformAndSession() async throws {
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: images[0])
        try await waitUntil { model.image != nil && model.isNavigationOrderReady }
        let session = model.sessionID
        let original = model.image
        model.zoomScale = 3
        model.rotationDegrees = 90
        let bad = directory.appendingPathComponent("broken.png")
        try Data("broken".utf8).write(to: bad)
        model.openImage(bad)
        try await waitUntil { !model.isImageLoading }
        XCTAssertEqual(model.currentURL, images[0])
        XCTAssertTrue(model.image === original)
        XCTAssertEqual(model.zoomScale, 3)
        XCTAssertEqual(model.rotationDegrees, 90)
        XCTAssertEqual(model.sessionID, session)
        XCTAssertNotNil(model.fileOperationError)
    }

    func testMetadataRemainsAvailableWithoutRepeatedFileReads() async throws {
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: images[0])
        try await waitUntil { model.image != nil }
        let metadata = model.imageParametersText
        let size = model.fileSizeText
        XCTAssertNotNil(metadata)
        XCTAssertNotNil(size)
        try FileManager.default.removeItem(at: images[0])
        model.zoomScale = 2
        XCTAssertEqual(model.imageParametersText, metadata)
        XCTAssertEqual(model.fileSizeText, size)
    }

    func testSuccessfulExternalOpenResetsSessionAfterLoad() async throws {
        let gate = ImageReadGate()
        let first = try XCTUnwrap(LoadedImage.read(images[0]))
        let firstURL = images[0]
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: firstURL,
            readImage: { url in url == firstURL ? first : await gate.read(url) })
        try await waitUntil { model.image != nil && model.isNavigationOrderReady }
        let session = model.sessionID
        model.zoomScale = 3
        model.openImage(images[2])
        XCTAssertEqual(model.sessionID, session)
        XCTAssertEqual(model.zoomScale, 3)
        XCTAssertFalse(model.canTrashCurrentImage)
        try await waitUntil { await gate.hasRequest(self.images[2]) }
        await gate.finish(images[2], result: LoadedImage.read(images[2]))
        try await waitUntil { !model.isImageLoading && model.isNavigationOrderReady }
        XCTAssertNotEqual(model.sessionID, session)
        XCTAssertEqual(model.currentURL, images[2])
        XCTAssertEqual(model.zoomScale, 1)
    }

    func testSlideshowStartsNextIntervalOnlyAfterImageLoads() async throws {
        let gate = ImageReadGate()
        let first = try XCTUnwrap(LoadedImage.read(images[0]))
        let firstURL = images[0]
        var intervals = 0
        let slideshow = SlideshowController(sleep: { _ in
            intervals += 1
            try await Task.sleep(for: .seconds(60))
        })
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: firstURL, slideshow: slideshow,
            readImage: { url in url == firstURL ? first : await gate.read(url) })
        try await waitUntil { model.image != nil && model.isNavigationOrderReady }
        model.startSlideshow()
        try await waitUntil { intervals == 1 }
        model.navigateToNext()
        try await waitUntil { await gate.hasRequest(self.images[1]) }
        XCTAssertEqual(intervals, 1)
        XCTAssertEqual(slideshow.state, .playing)
        await gate.finish(images[1], result: LoadedImage.read(images[1]))
        try await waitUntil { intervals == 2 }
        XCTAssertEqual(model.currentURL, images[1])
        slideshow.stop()
    }

    func testBackgroundDeletionAndUndoRetainNavigationOrder() async throws {
        let trash = TemporaryImageTrash(directory: directory)
        let model = ImageViewerViewModel(loadingMode: .background, imageURL: images[0], imageTrash: trash)
        try await waitUntil { model.image != nil && model.isNavigationOrderReady }
        model.trashCurrentImage()
        try await waitUntil { !model.isImageLoading }
        XCTAssertEqual(model.currentURL, images[1])
        XCTAssertEqual(model.nextURL, images[2])
        XCTAssertTrue(model.canUndoDeletion)
        model.undoDeletion()
        try await waitUntil { !model.isImageLoading }
        XCTAssertEqual(model.currentURL, images[0])
        XCTAssertEqual(model.nextURL, images[1])
        XCTAssertFalse(model.canUndoDeletion)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "ImageLoadingTests.Timeout", code: 1)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor ImageReadGate {
    private var pending: [URL: CheckedContinuation<LoadedImage?, Never>] = [:]
    func read(_ url: URL) async -> LoadedImage? {
        await withCheckedContinuation { pending[url] = $0 }
    }
    func hasRequest(_ url: URL) -> Bool { pending[url] != nil }
    func finish(_ url: URL, result: LoadedImage?) { pending.removeValue(forKey: url)?.resume(returning: result) }
}

private struct TemporaryImageTrash: ImageTrashing {
    let directory: URL
    func trash(_ url: URL) throws -> URL? {
        let destination = directory.appendingPathComponent("deleted-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
    func restore(_ trashedURL: URL, to originalURL: URL) throws {
        try FileManager.default.moveItem(at: trashedURL, to: originalURL)
    }
}
