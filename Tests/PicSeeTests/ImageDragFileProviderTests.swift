import AppKit
import XCTest
@testable import PicSee

final class ImageDragFileProviderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PicSee-drag-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testLocalFilesKeepURLNameExtensionAndBytesWithoutCreatingCache() throws {
        let cache = directory.appendingPathComponent("cache")
        let provider = ImageDragFileProvider(root: cache, temporaryResourceRoots: [])
        for name in ["照片 sample.jpg", "sample.PNG", "sample.webp", "animated.gif"] {
            let source = directory.appendingPathComponent(name)
            let bytes = Data("original bytes for \(name)".utf8)
            try bytes.write(to: source)
            let result = try provider.fileURL(sourceURL: source, image: NSImage())
            XCTAssertEqual(result, source.resolvingSymlinksInPath().standardizedFileURL)
            XCTAssertEqual(try Data(contentsOf: result), bytes)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testTemporarySourceIsCopiedWithoutReencodingAndRepeatedDragsNeverOverwrite() throws {
        let provider = ImageDragFileProvider(root: directory.appendingPathComponent("cache"), temporaryResourceRoots: [directory])
        let source = directory.appendingPathComponent("动画.gif")
        let bytes = Data("GIF89a-original-frames".utf8)
        try bytes.write(to: source)
        let first = try provider.fileURL(sourceURL: source, image: NSImage())
        let second = try provider.fileURL(sourceURL: source, image: NSImage())
        XCTAssertNotEqual(first, source)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: second), bytes)
    }

    func testSymbolicLinkExportsRealGIFWithoutReencoding() throws {
        let target = directory.appendingPathComponent("original.gif")
        let link = directory.appendingPathComponent("shortcut.gif")
        let bytes = Data("GIF89a-original-frames".utf8)
        try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        for temporaryRoots in [[], [directory]] as [[URL]] {
            let provider = ImageDragFileProvider(root: directory.appendingPathComponent("cache"),
                                                temporaryResourceRoots: temporaryRoots)
            let result = try provider.fileURL(sourceURL: link, image: NSImage())
            XCTAssertEqual(result.lastPathComponent, "original.gif")
            XCTAssertEqual(try Data(contentsOf: result), bytes)
            XCTAssertEqual(try result.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, false)
            if temporaryRoots.isEmpty {
                XCTAssertEqual(result, target.resolvingSymlinksInPath().standardizedFileURL)
            } else {
                XCTAssertNotEqual(result, target.resolvingSymlinksInPath().standardizedFileURL)
            }
        }
    }

    @MainActor
    func testMemoryAndRemoteURLFallbackProduceActualPNGWithCorrectName() throws {
        let provider = ImageDragFileProvider(root: directory.appendingPathComponent("cache"))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = NSImage(size: NSSize(width: 32, height: 16))
        image.addRepresentation(bitmap)
        for source in [nil, URL(string: "https://example.invalid/photos/cat.webp?token=unused")] as [URL?] {
            let result = try provider.fileURL(sourceURL: source, image: image)
            XCTAssertEqual(result.pathExtension, "png")
            XCTAssertEqual(result.lastPathComponent, source == nil ? "PicSee-image.png" : "cat.png")
            XCTAssertEqual(try Data(contentsOf: result).prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
            XCTAssertEqual(ImageExporter.pixelSize(of: try XCTUnwrap(NSImage(contentsOf: result))), CGSize(width: 32, height: 16))
        }
    }

    func testFailedRenderRemovesPartialExportDirectory() throws {
        let cache = directory.appendingPathComponent("cache")
        let provider = ImageDragFileProvider(root: cache)
        XCTAssertThrowsError(try provider.fileURL(sourceURL: nil, image: NSImage()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path), [])
    }

    func testCleanupOnlyRemovesExpiredInactiveExportDirectories() throws {
        let provider = ImageDragFileProvider(root: directory)
        let now = Date()
        let old = now.addingTimeInterval(-ImageDragFileProvider.retentionInterval - 1)
        let candidates = [("export-111-expired", old), ("export-222-active", old),
                          ("export-333-recent", now), ("unrelated", old)]
        for (name, date) in candidates {
            let url = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        provider.cleanupExpiredFiles(now: now, processIsRunning: { $0 == 222 })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)),
                       Set(["export-222-active", "export-333-recent", "unrelated"]))
    }
}
