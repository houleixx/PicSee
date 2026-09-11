import AppKit
import SwiftUI
import XCTest
@testable import PicSee

@MainActor
final class ScreenshotNavigationInteractionTests: XCTestCase {
    func testSelectionReceivesMouseDragImmediatelyAfterNavigation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = (0..<3).map { directory.appendingPathComponent("\($0).png") }
        for (index, url) in urls.enumerated() {
            let source = index == 1 ? "xiaohongshu-picsee-crop-annotate.png" : "Tests/Fixtures/ocr-test.png"
            try FileManager.default.copyItem(at: root.appendingPathComponent(source), to: url)
        }
        for repeatCount in [0, 1, 3] {
            for delay in [0.0, 0.01, 0.05, 0.18, 0.3] {
                let model = ImageViewerViewModel(imageURL: urls[0], finderOrderProvider: ScreenshotTestOrder(urls: urls))
                let host = NSHostingView(rootView: ImageViewerView(viewModel: model, updateChecker: nil,
                    onTitleBarVisibilityChanged: { _ in }, onFixedWindowChanged: { _ in }, onRequestDeletion: {}))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.orderFront(nil)
                defer { window.orderOut(nil) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let canvas: CanvasNSView = try XCTUnwrap(find(in: host))
                canvas.motionPreference = { false }
                for index in 0..<repeatCount {
                    if index == 2 { model.navigateToPrevious() } else { model.navigateToNext() }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                if delay > 0 { RunLoop.current.run(until: Date().addingTimeInterval(delay)) }
                let button = CGPoint(x: host.bounds.midX + ViewerToolbarMetrics.viewerWidth / 2
                    - ViewerToolbarMetrics.horizontalPadding - ViewerToolbarMetrics.buttonSize / 2, y: 40)
                try send([(.leftMouseDown, button), (.leftMouseUp, button)], to: window)
                let deadline = Date().addingTimeInterval(0.5)
                while (find(in: host) as ScreenshotCanvasNSView?) == nil && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.001))
                }
                let editor: ScreenshotCanvasNSView = try XCTUnwrap(find(in: host), "repeat=\(repeatCount), delay=\(delay)")
                XCTAssertTrue(model.isScreenshotEditing)
                let rect = try XCTUnwrap(editor.displayImageRect)
                let start = editor.convert(CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.65), to: nil)
                let end = editor.convert(CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.4), to: nil)
                try send([(.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)], to: window)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                XCTAssertTrue(editor.document.canExport,
                    "Screenshot must receive the first selection drag: repeat=\(repeatCount), delay=\(delay)")
                // Finish closing the previous session, then switch and reopen immediately.
                let previousDocument = editor.document
                editor.onCancel?()
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                model.navigate(to: model.currentURL == urls[0] ? urls[1] : urls[0])
                model.zoomScale = 0.25
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                try send([(.leftMouseDown, button), (.leftMouseUp, button)], to: window)
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                let reopened: ScreenshotCanvasNSView = try XCTUnwrap(find(in: host))
                XCTAssertTrue(model.isScreenshotEditing)
                XCTAssertFalse(reopened.document === previousDocument, "Reopening must bind the new image document")
                let reopenedRect = try XCTUnwrap(reopened.displayImageRect)
                // Reproduce the small-image case: start in the surrounding blank
                // space and drag into the image through the real window event path.
                let reopenedStart = reopened.convert(CGPoint(x: reopenedRect.minX - 24, y: reopenedRect.maxY + 24), to: nil)
                let reopenedEnd = reopened.convert(CGPoint(x: reopenedRect.midX, y: reopenedRect.midY), to: nil)
                try send([(.leftMouseDown, reopenedStart), (.leftMouseDragged, reopenedEnd), (.leftMouseUp, reopenedEnd)], to: window)
                XCTAssertTrue(reopened.document.canExport)
                let crop = try XCTUnwrap(reopened.document.state.selection)
                XCTAssertEqual(crop.minX, 0, accuracy: 0.01)
                XCTAssertEqual(crop.maxY, reopened.document.pixelSize.height, accuracy: 0.01)
            }
        }
    }

    private func find<T: NSView>(in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.find(in: $0) as T? }.first
    }

    private func send(_ samples: [(NSEvent.EventType, CGPoint)], to window: NSWindow) throws {
        // Queue the release before dispatching mouseDown: native controls can run
        // their own tracking loop and consume the remaining gesture synchronously.
        for (type, point) in samples.reversed() {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
            NSApp.postEvent(event, atStart: true)
        }
        while let event = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }

}

private struct ScreenshotTestOrder: FinderFolderOrderProviding {
    let urls: [URL]
    func orderedURLs(for folderURL: URL) async -> [URL]? { urls }
}
