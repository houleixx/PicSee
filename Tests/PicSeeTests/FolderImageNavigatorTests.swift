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
        XCTAssertFalse(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/notes.txt")))
        XCTAssertFalse(FolderImageNavigator.isSupportedImage(URL(fileURLWithPath: "/tmp/no-extension")))
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
