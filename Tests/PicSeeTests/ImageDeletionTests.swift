import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageDeletionTests: XCTestCase {
    private var directory: URL!
    private var trash: TestImageTrash!
    private var defaults: UserDefaults!
    private var defaultsSuite: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PicSeeDeletionTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        trash = TestImageTrash(directory: directory.appendingPathComponent("trash"))
        try FileManager.default.createDirectory(at: trash.directory, withIntermediateDirectories: true)
        defaultsSuite = "PicSeeConfirmationTests-\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    func testConfirmationDefaultsToCancelAndDoesNotDeleteUntilConfirmed() throws {
        let url = try writePNG("确认测试.png")
        let model = ImageViewerViewModel(imageURL: url, imageTrash: trash)
        var completion: ((NSApplication.ModalResponse) -> Void)?
        let confirmation = ImageDeletionConfirmation(defaults: defaults) { alert, _, reply in
            XCTAssertEqual(alert.messageText, "将图片移到废纸篓？")
            XCTAssertEqual(alert.filename, "确认测试.png")
            XCTAssertEqual(alert.buttons.map(\.title), ["取消", "移到废纸篓"])
            XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
            XCTAssertEqual(alert.buttons[1].keyEquivalent, "")
            XCTAssertTrue(alert.defaultButtonCell === alert.buttons[0].cell)
            XCTAssertTrue(alert.initialFirstResponder === alert.buttons[0])
            XCTAssertEqual(alert.suppressionButton.title, "以后不再询问")
            XCTAssertEqual(alert.suppressionButton.state, .off)
            completion = reply
        }
        confirmation.requestDeletion(for: model, in: NSWindow())
        XCTAssertEqual(trash.trashCalls, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try XCTUnwrap(completion)(.alertSecondButtonReturn)
        XCTAssertEqual(trash.trashCalls, 1)
        XCTAssertTrue(model.isFolderEmpty)
        XCTAssertNil(defaults.object(forKey: ImageDeletionConfirmation.asksBeforeDeletingKey))
    }

    func testCancelDoesNotDeleteOrRememberSuppression() throws {
        let url = try writePNG("only.png")
        let model = ImageViewerViewModel(imageURL: url, imageTrash: trash)
        var presentations = 0
        let confirmation = ImageDeletionConfirmation(defaults: defaults) { alert, _, reply in
            presentations += 1
            alert.suppressionButton.state = .on
            reply(.alertFirstButtonReturn)
        }
        confirmation.requestDeletion(for: model, in: NSWindow())
        confirmation.requestDeletion(for: model, in: NSWindow())
        XCTAssertEqual(presentations, 2)
        XCTAssertEqual(trash.trashCalls, 0)
        XCTAssertEqual(model.currentURL, url)
        XCTAssertNil(defaults.object(forKey: ImageDeletionConfirmation.asksBeforeDeletingKey))
    }

    func testSuppressionPersistsForNextConfirmationController() throws {
        let first = try writePNG("1.png")
        _ = try writePNG("2.png")
        let model = ImageViewerViewModel(imageURL: first, imageTrash: trash)
        let confirmation = ImageDeletionConfirmation(defaults: defaults) { alert, _, reply in
            alert.suppressionButton.state = .on
            reply(.alertSecondButtonReturn)
        }
        confirmation.requestDeletion(for: model, in: NSWindow())
        XCTAssertEqual(trash.trashCalls, 1)
        let nextDefaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        XCTAssertEqual(nextDefaults.object(forKey: ImageDeletionConfirmation.asksBeforeDeletingKey) as? Bool, false)
        let nextConfirmation = ImageDeletionConfirmation(defaults: nextDefaults) { _, _, _ in
            XCTFail("Opting out should skip subsequent confirmation")
        }
        nextConfirmation.requestDeletion(for: model, in: NSWindow())
        XCTAssertEqual(trash.trashCalls, 2)
    }

    func testRepeatedRequestDoesNotOpenMultipleConfirmations() throws {
        let url = try writePNG("only.png")
        let model = ImageViewerViewModel(imageURL: url, imageTrash: trash)
        var presentations = 0
        var completion: ((NSApplication.ModalResponse) -> Void)?
        let confirmation = ImageDeletionConfirmation(defaults: defaults) { _, _, reply in
            presentations += 1
            completion = reply
        }
        let window = NSWindow()
        confirmation.requestDeletion(for: model, in: window)
        confirmation.requestDeletion(for: model, in: window)
        XCTAssertEqual(presentations, 1)
        try XCTUnwrap(completion)(.alertFirstButtonReturn)
        confirmation.requestDeletion(for: model, in: window)
        XCTAssertEqual(presentations, 2)
        XCTAssertEqual(trash.trashCalls, 0)
    }

    func testStaleConfirmationCannotDeleteADifferentImage() throws {
        let first = try writePNG("1.png")
        let second = try writePNG("2.png")
        let model = ImageViewerViewModel(imageURL: first, imageTrash: trash)
        var completion: ((NSApplication.ModalResponse) -> Void)?
        let confirmation = ImageDeletionConfirmation(defaults: defaults) { alert, _, reply in
            alert.suppressionButton.state = .on
            completion = reply
        }
        confirmation.requestDeletion(for: model, in: NSWindow())
        model.navigate(to: second)
        try XCTUnwrap(completion)(.alertSecondButtonReturn)
        XCTAssertEqual(trash.trashCalls, 0)
        XCTAssertNil(defaults.object(forKey: ImageDeletionConfirmation.asksBeforeDeletingKey))
    }

    func testConfirmationDoesNotOpenWhileEditing() throws {
        let url = try writePNG("only.png")
        let model = ImageViewerViewModel(imageURL: url, imageTrash: trash)
        model.isScreenshotEditing = true
        let confirmation = ImageDeletionConfirmation(defaults: defaults) { _, _, _ in
            XCTFail("Editing must not open deletion confirmation")
        }
        confirmation.requestDeletion(for: model, in: NSWindow())
        XCTAssertEqual(trash.trashCalls, 0)
    }

    func testDeleteAdvancesThenFallsBackAndUndoRestoresInReverseOrder() throws {
        let first = try writePNG("1.png")
        let second = try writePNG("2.png")
        let third = try writePNG("3.png")
        let model = ImageViewerViewModel(imageURL: second, imageTrash: trash)
        model.zoomScale = 2
        model.rotationDegrees = 90

        model.trashCurrentImage()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(model.currentURL, third)
        XCTAssertEqual(model.zoomScale, 1)
        XCTAssertEqual(model.rotationDegrees, 0)
        XCTAssertEqual(model.previousURL, first)
        model.trashCurrentImage()
        XCTAssertEqual(model.currentURL, first)
        model.undoDeletion()
        XCTAssertEqual(model.currentURL, third)
        XCTAssertEqual(model.previousURL, first)
        model.undoDeletion()
        XCTAssertEqual(model.currentURL, second)
        XCTAssertEqual(model.previousURL, first)
        XCTAssertEqual(model.nextURL, third)
        XCTAssertFalse(model.canUndoDeletion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.path))
    }

    func testLastDeletionShowsEmptyStateAndCanBeUndone() throws {
        let url = try writePNG("only.png")
        let model = ImageViewerViewModel(imageURL: url, imageTrash: trash)
        model.trashCurrentImage()
        XCTAssertTrue(model.isFolderEmpty)
        XCTAssertNil(model.image)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.previousURL)
        XCTAssertNil(model.nextURL)
        XCTAssertFalse(model.canTrashCurrentImage)
        XCTAssertTrue(model.canUndoDeletion)
        XCTAssertTrue(model.titleBarText.contains("此文件夹中没有可浏览的图片"))
        model.trashCurrentImage()
        XCTAssertEqual(trash.trashCalls, 1)
        model.undoDeletion()
        XCTAssertFalse(model.isFolderEmpty)
        XCTAssertNotNil(model.image)
        XCTAssertEqual(model.currentURL, url)
        XCTAssertNil(model.deletionNoticeID)
    }

    func testTrashFailurePreservesImageAndNavigation() throws {
        let first = try writePNG("1.png")
        let second = try writePNG("2.png")
        let model = ImageViewerViewModel(imageURL: first, imageTrash: trash)
        let image = model.image
        trash.shouldFail = true
        model.trashCurrentImage()
        XCTAssertEqual(model.currentURL, first)
        XCTAssertTrue(model.image === image)
        XCTAssertEqual(model.nextURL, second)
        XCTAssertFalse(model.canUndoDeletion)
        XCTAssertNotNil(model.fileOperationError)
        XCTAssertNil(model.deletionNoticeID)
    }

    func testUndoDoesNotOverwriteNewFileAndCanBeRetried() throws {
        let url = try writePNG("only.png")
        let model = ImageViewerViewModel(imageURL: url, imageTrash: trash)
        model.trashCurrentImage()
        let replacement = Data("new file".utf8)
        try replacement.write(to: url)
        model.undoDeletion()
        XCTAssertEqual(try Data(contentsOf: url), replacement)
        XCTAssertTrue(model.canUndoDeletion)
        XCTAssertTrue(model.isFolderEmpty)
        XCTAssertNotNil(model.fileOperationError)
        try FileManager.default.removeItem(at: url)
        model.undoDeletion()
        XCTAssertNotNil(model.image)
        XCTAssertNil(model.fileOperationError)
    }

    func testDeletionSkipsMissingAndUndecodableImages() throws {
        let first = try writePNG("1.png")
        let missing = try writePNG("2.png")
        try Data("invalid".utf8).write(to: directory.appendingPathComponent("3.png"))
        let last = try writePNG("4.png")
        let model = ImageViewerViewModel(imageURL: first, imageTrash: trash)
        try FileManager.default.removeItem(at: missing)
        model.trashCurrentImage()
        XCTAssertEqual(model.currentURL, last)
        XCTAssertNotNil(model.image)
    }

    func testNewImageInFolderPreventsEmptyState() throws {
        let first = try writePNG("1.png")
        let model = ImageViewerViewModel(imageURL: first, imageTrash: trash)
        let added = try writePNG("2.png")
        model.trashCurrentImage()
        XCTAssertEqual(model.currentURL, added)
        XCTAssertFalse(model.isFolderEmpty)
    }

    func testScreenshotEditingDisablesDeletionAndUndo() throws {
        let first = try writePNG("1.png")
        _ = try writePNG("2.png")
        let model = ImageViewerViewModel(imageURL: first, imageTrash: trash)
        model.isScreenshotEditing = true
        model.trashCurrentImage()
        XCTAssertEqual(trash.trashCalls, 0)
        model.isScreenshotEditing = false
        model.trashCurrentImage()
        model.isScreenshotEditing = true
        model.undoDeletion()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(model.canUndoDeletion)
    }

    func testFinderOrderIsPreservedAcrossDeletionAndUndo() async throws {
        let first = try writePNG("1.png")
        let second = try writePNG("2.png")
        let third = try writePNG("3.png")
        let model = ImageViewerViewModel(
            imageURL: first, finderOrderProvider: DeletionOrderProvider(order: [third, first, second]), imageTrash: trash
        )
        XCTAssertFalse(model.canTrashCurrentImage)
        model.trashCurrentImage()
        XCTAssertEqual(trash.trashCalls, 0)
        for _ in 0..<100 where !model.isNavigationOrderReady {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isNavigationOrderReady)
        model.trashCurrentImage()
        XCTAssertEqual(model.currentURL, second)
        XCTAssertEqual(model.previousURL, third)
        model.undoDeletion()
        XCTAssertEqual(model.previousURL, third)
        XCTAssertEqual(model.nextURL, second)
    }

    func testContextMenuRoutesActionsAndValidatesAvailability() {
        let canvas = CanvasNSView(frame: .zero, backend: .vision)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        let trashItems = menu.items.filter { $0.title == "移到废纸篓" }
        XCTAssertEqual(trashItems.count, 1)
        let item = trashItems[0]
        XCTAssertEqual(item.keyEquivalent, "\u{8}")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        menu.update()
        XCTAssertFalse(item.isEnabled)
        var calls = 0
        canvas.onTrashImage = { calls += 1 }
        canvas.trashImageForMenu(nil)
        XCTAssertEqual(calls, 0)
        canvas.canTrashImage = true
        menu.update()
        XCTAssertTrue(item.isEnabled)
        canvas.trashImageForMenu(nil)
        XCTAssertEqual(calls, 1)
    }

    private func writePNG(_ name: String) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = directory.appendingPathComponent(name).standardizedFileURL
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }
}

private final class TestImageTrash: ImageTrashing {
    let directory: URL
    var shouldFail = false
    var trashCalls = 0

    init(directory: URL) { self.directory = directory }

    func trash(_ url: URL) throws -> URL? {
        trashCalls += 1
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        let destination = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    func restore(_ trashedURL: URL, to originalURL: URL) throws {
        try ImageTrash().restore(trashedURL, to: originalURL)
    }
}

private struct DeletionOrderProvider: FinderFolderOrderProviding {
    let order: [URL]
    var isOrderingAvailableImmediately: Bool { false }
    func orderedURLs(for folderURL: URL) async -> [URL]? { order }
}
