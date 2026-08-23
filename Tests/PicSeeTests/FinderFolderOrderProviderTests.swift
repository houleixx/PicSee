import AppKit
import XCTest
@testable import PicSee

final class FinderFolderOrderProviderTests: XCTestCase {
    func testScriptMatchesRequestedFolderAndEscapesAppleScriptText() {
        let folderURL = URL(fileURLWithPath: "/tmp/a \"quoted\" folder", isDirectory: true)

        let source = FinderFolderOrderProvider.scriptSource(folderURL: folderURL)

        XCTAssertTrue(source.contains("URL of target of finderWindow"))
        XCTAssertTrue(source.contains("set finderWindowCount to count of Finder windows"))
        XCTAssertTrue(source.contains("file:///tmp/a%20%22quoted%22%20folder/"))
        XCTAssertTrue(source.contains("SCRIPT_ERROR"))
        XCTAssertFalse(source.contains("set requestedFolderURL to \"file:///tmp/a%20\"quoted\""))
    }

    func testScriptUsesExactFinderOrderForListView() {
        let source = scriptSource()

        for token in [
            "sort column of list view options",
            "name column",
            "modification date column",
            "creation date column",
            "size column",
            "kind column",
            "sort direction of activeColumn",
            "return my encodeOrdered(orderedItems)"
        ] {
            XCTAssertTrue(source.contains(token), "Missing list-view token: \(token)")
        }
    }

    func testScriptUsesExactPositionsForManualIconView() {
        let source = scriptSource()

        XCTAssertTrue(source.contains("arrangement of icon view options"))
        XCTAssertTrue(source.contains("not arranged"))
        XCTAssertTrue(source.contains("snap to grid"))
        XCTAssertTrue(source.contains("position of folderItem"))
        XCTAssertFalse(source.contains("iconArrangement is arranged by name"))
        XCTAssertFalse(source.contains("iconArrangement is arranged by size"))
    }

    func testColumnAndGroupedViewsUseDefaultFallbackWithoutChangingFinderSelection() {
        let source = scriptSource()

        XCTAssertTrue(source.contains("else if viewMode is column view or viewMode is group view then"))
        XCTAssertTrue(source.contains("return \"\""))
        XCTAssertFalse(source.contains("set savedSelection to selection"))
        XCTAssertFalse(source.contains("set selection to folderItems"))
        XCTAssertFalse(source.contains("\"None\" & tab & \"Name\""))
        XCTAssertFalse(source.contains("defaults read com.apple.finder"))
        XCTAssertFalse(source.contains("FXPreferredGroupBy"))
        XCTAssertFalse(source.contains("FXArrangeGroupViewBy"))
        XCTAssertFalse(source.contains("FK_ArrangeBy"))
        XCTAssertFalse(source.contains("DATE_ADDED_DESCENDING"))
    }

    func testParsesExactURLAndPositionResults() {
        XCTAssertEqual(
            FinderFolderOrderProvider.parseOutput(
                "ORDERED\nfile:///tmp/three.jpg\nfile:///tmp/one.jpg\nfile:///tmp/two.jpg"
            ),
            ["three.jpg", "one.jpg", "two.jpg"].map {
                URL(fileURLWithPath: "/tmp/\($0)").standardizedFileURL
            }
        )

        XCTAssertEqual(
            FinderFolderOrderProvider.parseOutput(
                "POSITION\nfile:///tmp/lower.jpg\t10\t200\nfile:///tmp/right.jpg\t200\t10\nfile:///tmp/left.jpg\t10\t10"
            ),
            ["left.jpg", "right.jpg", "lower.jpg"].map {
                URL(fileURLWithPath: "/tmp/\($0)").standardizedFileURL
            }
        )
    }

    func testMalformedOrUnavailableSystemResultsReturnNil() {
        XCTAssertNil(FinderFolderOrderProvider.parseOutput(""))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("ORDERED"))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("POSITION\nnot-a-row"))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("SCRIPT_ERROR\t-1\tfailure"))
        XCTAssertNil(FinderFolderOrderProvider.parseOutput("NO_MATCHING_WINDOW"))
    }

    func testUnavailableSystemOrderUsesImmediateFallbackWithoutReadingDirectory() async {
        let directoryWasRead = ThreadSafeFlag()
        let provider = FinderFolderOrderProvider(
            { _ in nil },
            directoryReader: { _ in
                directoryWasRead.set()
                return []
            }
        )

        XCTAssertTrue(provider.isOrderingAvailableImmediately)
        let result = await provider.orderedURLs(
            for: URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        )
        XCTAssertNil(result)
        XCTAssertFalse(directoryWasRead.value)
    }

    func testProviderAcceptsOnlyCompleteExactImageOrder() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let one = imageURL(folder: folder, name: "1.png")
        let two = imageURL(folder: folder, name: "2.png")

        let complete = FinderFolderOrderProvider(
            { _ in
                "ORDERED\nfile:///tmp/photos/readme.txt\n\(two.absoluteString)\n\(one.absoluteString)"
            },
            directoryReader: { _ in [one, two] }
        )
        let partial = FinderFolderOrderProvider(
            { _ in "ORDERED\n\(one.absoluteString)" },
            directoryReader: { _ in [one, two] }
        )
        let duplicate = FinderFolderOrderProvider(
            { _ in "ORDERED\n\(one.absoluteString)\n\(one.absoluteString)\n\(two.absoluteString)" },
            directoryReader: { _ in [one, two] }
        )

        let completeResult = await complete.orderedURLs(for: folder)
        let partialResult = await partial.orderedURLs(for: folder)
        let duplicateResult = await duplicate.orderedURLs(for: folder)
        XCTAssertEqual(completeResult, [two, one])
        XCTAssertNil(partialResult)
        XCTAssertNil(duplicateResult)
    }

    func testProviderReturnsNilForUnavailableSystemResultOrMissingDirectory() async {
        let folder = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        let item = imageURL(folder: folder, name: "1.png")
        let noSystemResult = FinderFolderOrderProvider(
            { _ in nil },
            directoryReader: { _ in [item] }
        )
        let noDirectory = FinderFolderOrderProvider(
            { _ in "ORDERED\n\(item.absoluteString)" },
            directoryReader: { _ in nil }
        )

        let noSystemResultValue = await noSystemResult.orderedURLs(for: folder)
        let noDirectoryValue = await noDirectory.orderedURLs(for: folder)
        XCTAssertNil(noSystemResultValue)
        XCTAssertNil(noDirectoryValue)
    }

    func testGeneratedFinderScriptCompiles() throws {
        let script = try XCTUnwrap(NSAppleScript(source: scriptSource()))
        var error: NSDictionary?

        XCTAssertTrue(script.compileAndReturnError(&error), "AppleScript compile error: \(String(describing: error))")
    }

    private func scriptSource() -> String {
        FinderFolderOrderProvider.scriptSource(
            folderURL: URL(fileURLWithPath: "/tmp/photos", isDirectory: true)
        )
    }

    private func imageURL(folder: URL, name: String) -> URL {
        folder.appendingPathComponent(name).standardizedFileURL
    }
}

private final class ThreadSafeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func set() {
        lock.withLock { storedValue = true }
    }
}
