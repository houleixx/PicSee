import XCTest
@testable import PicSee

final class FolderImageNavigatorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicSeeNavigatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testSupportedExtensionsAreCaseInsensitive() {
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.JPG")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.heic")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.WEBP")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.AVIF")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.SVG")))
        XCTAssertFalse(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/document.PDF")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/texture.EXR")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/design.psd")))
        XCTAssertFalse(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/notes.txt")))
        XCTAssertFalse(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/no-extension")))
    }

    func testCameraRawExtensionsAreSupportedCaseInsensitively() {
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.DNG")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.cr3")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.NEF")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.arw")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.RAF")))
        XCTAssertTrue(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/photo.rw2")))
    }

    func testScansOnlySupportedImagesInLocalizedFilenameOrder() throws {
        let b = try createFile(named: "b.png")
        let a = try createFile(named: "a.jpg")
        _ = try createFile(named: "notes.txt")
        let c = try createFile(named: "c.HEIC")

        let navigator = try FolderImageNavigator(currentImageURL: b)

        XCTAssertEqual(navigator.images, [a, b, c])
        XCTAssertEqual(navigator.currentIndex, 1)
    }

    func testPreviousAndNextRespectBoundaries() throws {
        let first = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let third = try createFile(named: "003.jpg")

        let middleNavigator = try FolderImageNavigator(currentImageURL: second)
        XCTAssertEqual(middleNavigator.previousURL(), first)
        XCTAssertEqual(middleNavigator.nextURL(), third)

        let firstNavigator = try FolderImageNavigator(currentImageURL: first)
        XCTAssertNil(firstNavigator.previousURL())
        XCTAssertEqual(firstNavigator.nextURL(), second)

        let lastNavigator = try FolderImageNavigator(currentImageURL: third)
        XCTAssertEqual(lastNavigator.previousURL(), second)
        XCTAssertNil(lastNavigator.nextURL())
    }

    func testPreferredOrderDeterminesCurrentPreviousAndNextPositions() throws {
        let first = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let third = try createFile(named: "003.jpg")

        let navigator = try FolderImageNavigator(
            currentImageURL: second,
            preferredOrder: [third, second, first]
        )

        XCTAssertEqual(navigator.images, [third, second, first])
        XCTAssertEqual(navigator.currentIndex, 1)
        XCTAssertEqual(navigator.previousURL(), third)
        XCTAssertEqual(navigator.nextURL(), first)
    }

    func testPreferredOrderFiltersDuplicatesUnsupportedFilesAndOtherFolders() throws {
        let first = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let notes = try createFile(named: "notes.txt")
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside.jpg")

        let navigator = try FolderImageNavigator(
            currentImageURL: second,
            preferredOrder: [second, notes, outside, first, second]
        )

        XCTAssertEqual(navigator.images, [second, first])
        XCTAssertEqual(navigator.currentIndex, 0)
    }

    func testImageNamedDirectoriesAreExcludedFromScannedAndPreferredOrders() throws {
        let current = try createFile(named: "001.jpg")
        let imageNamedDirectory = temporaryDirectory.appendingPathComponent("002.png", isDirectory: true)
        try FileManager.default.createDirectory(at: imageNamedDirectory, withIntermediateDirectories: false)

        let scannedNavigator = try FolderImageNavigator(currentImageURL: current)
        let preferredNavigator = try FolderImageNavigator(
            currentImageURL: current,
            preferredOrder: [current, imageNamedDirectory]
        )

        XCTAssertEqual(scannedNavigator.images, [current])
        XCTAssertEqual(preferredNavigator.images, [current])
    }

    func testPreferredOrderWithoutCurrentImageFallsBackToFilenameOrder() throws {
        let first = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let third = try createFile(named: "003.jpg")

        let navigator = try FolderImageNavigator(
            currentImageURL: second,
            preferredOrder: [third, first]
        )

        XCTAssertEqual(navigator.images, [first, second, third])
        XCTAssertEqual(navigator.currentIndex, 1)
    }

    func testNextPrunesDeletedCandidatesAndContinuesForward() throws {
        let first = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let deleted = try createFile(named: "003.jpg")
        let fourth = try createFile(named: "004.jpg")
        let navigator = try FolderImageNavigator(
            currentImageURL: second,
            preferredOrder: [first, second, deleted, fourth]
        )
        try FileManager.default.removeItem(at: deleted)

        XCTAssertEqual(navigator.nextURL(), fourth)
        XCTAssertEqual(navigator.images, [first, second, fourth])
        XCTAssertEqual(navigator.currentIndex, 1)
    }

    func testPreviousPrunesDeletedCandidatesAndUpdatesCurrentIndex() throws {
        let deleted = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let third = try createFile(named: "003.jpg")
        let navigator = try FolderImageNavigator(
            currentImageURL: second,
            preferredOrder: [deleted, second, third]
        )
        try FileManager.default.removeItem(at: deleted)

        XCTAssertNil(navigator.previousURL())
        XCTAssertEqual(navigator.images, [second, third])
        XCTAssertEqual(navigator.currentIndex, 0)
    }

    func testDeletedCurrentImageRemainsAnchorUntilNavigationMovesAway() throws {
        let first = try createFile(named: "001.jpg")
        let current = try createFile(named: "002.jpg")
        let third = try createFile(named: "003.jpg")
        let navigator = try FolderImageNavigator(
            currentImageURL: current,
            preferredOrder: [first, current, third]
        )
        try FileManager.default.removeItem(at: current)

        XCTAssertEqual(navigator.previousURL(), first)
        XCTAssertEqual(navigator.nextURL(), third)

        navigator.move(to: third)

        XCTAssertEqual(navigator.currentIndex, 1)
        XCTAssertEqual(navigator.images, [first, third])
        XCTAssertEqual(navigator.previousURL(), first)
    }

    func testRemoveFromSnapshotKeepsCurrentIndexAligned() throws {
        let first = try createFile(named: "001.jpg")
        let second = try createFile(named: "002.jpg")
        let third = try createFile(named: "003.jpg")
        let navigator = try FolderImageNavigator(
            currentImageURL: second,
            preferredOrder: [first, second, third]
        )

        navigator.removeFromSnapshot(first)

        XCTAssertEqual(navigator.images, [second, third])
        XCTAssertEqual(navigator.currentIndex, 0)
    }

    func testMissingCurrentImageStillReturnsSingleImageNavigator() throws {
        let missing = temporaryDirectory.appendingPathComponent("missing.jpg")

        let navigator = try FolderImageNavigator(currentImageURL: missing)

        XCTAssertEqual(navigator.images, [missing])
        XCTAssertEqual(navigator.currentIndex, 0)
        XCTAssertNil(navigator.previousURL())
        XCTAssertNil(navigator.nextURL())
    }

    private func createFile(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: url)
        return url.standardizedFileURL
    }
}
