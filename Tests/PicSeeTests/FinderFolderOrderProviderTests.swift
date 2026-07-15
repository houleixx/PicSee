import AppKit
import XCTest
@testable import PicSee

final class FinderFolderOrderProviderTests: XCTestCase {
    func testScriptMatchesTheRequestedFolderAndEscapesAppleScriptText() {
        let folderURL = URL(fileURLWithPath: "/tmp/a \"quoted\" folder", isDirectory: true)

        let source = FinderFolderOrderProvider.scriptSource(folderURL: folderURL)

        XCTAssertTrue(source.contains("URL of target of finderWindow"))
        XCTAssertTrue(source.contains("set finderWindowCount to count of Finder windows"))
        XCTAssertTrue(source.contains("set finderWindow to Finder window finderWindowIndex"))
        XCTAssertFalse(source.contains("repeat with finderWindow in Finder windows"))
        XCTAssertTrue(source.contains("SCRIPT_ERROR"))
        XCTAssertTrue(source.contains("file:///tmp/a%20%22quoted%22%20folder/"))
        XCTAssertFalse(source.contains("set requestedFolderURL to \"file:///tmp/a%20\"quoted\""))
    }

    func testScriptCoversFinderListSortColumnsAndDirection() {
        let source = FinderFolderOrderProvider.scriptSource(
            folderURL: URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        )

        for token in [
            "sort column of list view options",
            "name column",
            "modification date column",
            "creation date column",
            "size column",
            "kind column",
            "label column",
            "version column",
            "comment column",
            "sort direction of activeColumn",
            "reversed"
        ] {
            XCTAssertTrue(source.contains(token), "Missing Finder list sorting token: \(token)")
        }
    }

    func testScriptCoversIconPositionAndColumnViewOrdering() {
        let source = FinderFolderOrderProvider.scriptSource(
            folderURL: URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        )

        for token in [
            "arrangement of icon view options",
            "not arranged",
            "snap to grid",
            "position of folderItem",
            "current view of finderWindow is column view",
            "sort folderItems by name"
        ] {
            XCTAssertTrue(source.contains(token), "Missing Finder view token: \(token)")
        }
    }

    func testColumnViewReadsFinderDateAddedArrangement() {
        let source = FinderFolderOrderProvider.scriptSource(
            folderURL: URL(fileURLWithPath: "/Users/holly/Downloads", isDirectory: true)
        )

        XCTAssertTrue(source.contains("defaults read com.apple.finder FK_ArrangeBy"))
        XCTAssertTrue(source.contains("Date Added"))
        XCTAssertTrue(source.contains("DATE_ADDED_DESCENDING"))
    }

    func testParsesOrderedURLResult() {
        let result = FinderFolderOrderProvider.parseOutput(
            "ORDERED\nfile:///tmp/three.jpg\nfile:///tmp/one.jpg\nfile:///tmp/two.jpg"
        )

        XCTAssertEqual(
            result,
            ["three.jpg", "one.jpg", "two.jpg"].map {
                URL(fileURLWithPath: "/tmp/\($0)").standardizedFileURL
            }
        )
    }

    func testPositionResultSortsTopToBottomThenLeftToRight() {
        let result = FinderFolderOrderProvider.parseOutput(
            "POSITION\nfile:///tmp/lower.jpg\t10\t200\nfile:///tmp/right.jpg\t200\t10\nfile:///tmp/left.jpg\t10\t10"
        )

        XCTAssertEqual(
            result,
            ["left.jpg", "right.jpg", "lower.jpg"].map {
                URL(fileURLWithPath: "/tmp/\($0)").standardizedFileURL
            }
        )
    }

    func testDateAddedResultSortsNewestFirstLikeGroupedFinderColumnView() {
        let older = URL(fileURLWithPath: "/tmp/older.png").standardizedFileURL
        let newer = URL(fileURLWithPath: "/tmp/newer.png").standardizedFileURL
        let dates = [
            older: Date(timeIntervalSince1970: 100),
            newer: Date(timeIntervalSince1970: 200)
        ]

        let result = FinderFolderOrderProvider.parseOutput(
            "DATE_ADDED_DESCENDING\n\(older.absoluteString)\n\(newer.absoluteString)",
            dateAdded: { dates[$0] }
        )

        XCTAssertEqual(result, [newer, older])
    }

    func testDateAddedDescriptorEnumeratesTheFolderWithoutFinderReturningEveryItem() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicSeeFinderDescriptor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.png")
        let second = folder.appendingPathComponent("second.png")
        try Data().write(to: first)
        try Data().write(to: second)
        let provider = FinderFolderOrderProvider { _ in "DATE_ADDED_DESCENDING" }

        let result = await provider.orderedURLs(for: folder)

        XCTAssertEqual(Set(result ?? []), Set([first.standardizedFileURL, second.standardizedFileURL]))
    }

    func testMalformedOrEmptyResultsReturnNil() {
        XCTAssertNil(FinderFolderOrderProvider.parseOutput(""))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("ORDERED"))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("POSITION\nnot-a-row"))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("ERROR\nfile:///tmp/image.jpg"))
    }

    func testProviderReturnsNilWhenScriptExecutionFails() async {
        let provider = FinderFolderOrderProvider { _ in nil }

        let result = await provider.orderedURLs(
            for: URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        )

        XCTAssertNil(result)
    }

    func testGeneratedFinderScriptCompiles() throws {
        let source = FinderFolderOrderProvider.scriptSource(
            folderURL: URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        )
        let script = try XCTUnwrap(NSAppleScript(source: source))
        var error: NSDictionary?

        XCTAssertTrue(script.compileAndReturnError(&error), "AppleScript compile error: \(String(describing: error))")
    }
}
