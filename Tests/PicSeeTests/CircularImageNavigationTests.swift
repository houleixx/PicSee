import AppKit
import Testing
@testable import PicSee

struct CircularImageNavigationTests {
    @Test(arguments: [false, true])
    func wrappingSkipsDeletedImages(forward: Bool) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try (0..<4).map { index in
            let url = directory.appendingPathComponent("\(index).png")
            try Data("fixture".utf8).write(to: url)
            return url
        }
        // Use an order different from filenames to exercise Finder ordering too.
        let order = [urls[2], urls[0], urls[3], urls[1]]
        let current = forward ? order[3] : order[0]
        let remaining = forward ? order[2] : order[1]
        let navigator = try FolderImageNavigator(currentImageURL: current, preferredOrder: order)
        for url in order where url != current && url != remaining {
            try FileManager.default.removeItem(at: url)
        }

        #expect((forward ? navigator.nextURL() : navigator.previousURL()) == remaining)
        #expect(navigator.images[navigator.currentIndex] == current)
        navigator.move(to: remaining)
        #expect(navigator.previousURL() == current)
        #expect(navigator.nextURL() == current)

        try FileManager.default.removeItem(at: current)
        #expect(navigator.previousURL() == nil)
        #expect(navigator.nextURL() == nil)
        #expect(navigator.images == [remaining])
    }

    @Test(arguments: [false, true])
    func singleOrEmptyListHasNoNavigation(empty: Bool) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("single.png")
        try Data("fixture".utf8).write(to: url)
        let navigator = try FolderImageNavigator(currentImageURL: url)
        if empty { navigator.removeFromSnapshot(url) }

        #expect(navigator.previousURL() == nil)
        #expect(navigator.nextURL() == nil)
    }

    @Test @MainActor
    func viewerLoadsImagesAcrossBothBoundaries() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let urls = try (0..<3).map { index in
            let url = directory.appendingPathComponent("\(index).png")
            try data.write(to: url)
            return url
        }
        let model = ImageViewerViewModel(imageURL: urls[2])

        #expect(model.nextURL == urls[0])
        model.navigateToNext()
        #expect(model.currentURL == urls[0])
        #expect(model.navigationDirection == 1)
        #expect(model.image != nil)
        #expect(model.errorMessage == nil)

        #expect(model.previousURL == urls[2])
        model.navigateToPrevious()
        #expect(model.currentURL == urls[2])
        #expect(model.navigationDirection == -1)
        #expect(model.image != nil)
        #expect(model.errorMessage == nil)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicSeeCircularTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
