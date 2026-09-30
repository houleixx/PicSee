import AppKit
import SwiftUI
import Testing
@testable import PicSee

@MainActor
struct ScreenshotShortcutTests {
    @Test func repeatedRotationShortcutsReachModelWithToolbarHidden() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/ocr-test.png")
        let model = ImageViewerViewModel(loadingMode: .immediate, imageURL: url)
        let host = NSHostingView(rootView: ImageViewerView(viewModel: model, updateChecker: nil,
            onTitleBarVisibilityChanged: { _ in }, onFixedWindowChanged: { _ in }, onRequestDeletion: {}))
        let window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func findCanvas(_ parent: NSView) -> CanvasNSView? {
            if let canvas = parent as? CanvasNSView { return canvas }
            return parent.subviews.lazy.compactMap { findCanvas($0) }.first
        }
        let canvas = try #require(findCanvas(host))
        canvas.toolbarVisible = false
        func press(_ keyCode: UInt16) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
            canvas.keyDown(with: event)
        }
        let originalURL = model.currentURL
        for expected in [270, 180, 90, 0] {
            try press(124)
            #expect(model.rotationDegrees == expected)
        }
        for expected in [90, 180, 270, 0] {
            try press(123)
            #expect(model.rotationDegrees == expected)
        }
        #expect(model.currentURL == originalURL)
    }

    @Test func screenshotRequiresCommandShiftAWithoutRepeat() {
        #expect(KeyboardNavigation.action(for: 0, modifiers: [.command, .shift]) == .screenshot)
        #expect(KeyboardNavigation.action(for: 0, modifiers: [.command, .shift], isRepeat: true) == .none)
        #expect(KeyboardNavigation.action(for: 0, modifiers: .command) == .none)
        #expect(KeyboardNavigation.action(for: 0, modifiers: .shift) == .none)
        #expect(KeyboardNavigation.action(for: 0, modifiers: [.command, .shift, .option]) == .none)
    }

    @Test func shortcutOpensEditorWithToolbarHiddenAndPreservesExistingSelection() throws {
        let defaults = UserDefaults.standard
        let key = ViewerOverlayPreference.toolbarVisibleDefaultsKey
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/ocr-test.png")
        let model = ImageViewerViewModel(loadingMode: .immediate, imageURL: url)
        let host = NSHostingView(rootView: ImageViewerView(viewModel: model, updateChecker: nil,
            onTitleBarVisibilityChanged: { _ in }, onFixedWindowChanged: { _ in }, onRequestDeletion: {}))
        let window = ViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        func find<T: NSView>(_ parent: NSView) -> T? {
            if let found = parent as? T { return found }
            return parent.subviews.lazy.compactMap { find($0) as T? }.first
        }
        let canvas: CanvasNSView = try #require(find(host))
        #expect(!canvas.debugToolbarVisible)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "A",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        canvas.keyDown(with: event)
        let deadline = Date().addingTimeInterval(1)
        while (find(host) as ScreenshotCanvasNSView?) == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        let editor: ScreenshotCanvasNSView = try #require(find(host))
        #expect(model.isScreenshotEditing)
        let document = editor.document
        canvas.keyDown(with: event)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let sameEditor: ScreenshotCanvasNSView = try #require(find(host))
        #expect(sameEditor.document === document)
    }
}
