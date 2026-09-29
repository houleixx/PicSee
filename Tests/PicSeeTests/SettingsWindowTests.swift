import AppKit
import XCTest
@testable import PicSee

@MainActor
final class SettingsWindowTests: XCTestCase {
    private struct ReadOnlyDefaultAppHandler: DefaultImageAppHandling {
        func isDefaultViewer(for format: DefaultImageFormat) -> Bool { format.label == "PNG" }
        func setDefaultViewer(for format: DefaultImageFormat) throws {
            XCTFail("Opening settings must not change file associations")
        }
    }

    // Native UI integration uses XCTest's serial lifecycle because application language
    // is a process-wide preference shared by existing windows and menus.
    func testLiveLanguageSwitchUpdatesNativeControlsAndPreservesEditingState() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: AppLanguage.defaultsKey)
        defer {
            if let original { defaults.set(original, forKey: AppLanguage.defaultsKey) }
            else { defaults.removeObject(forKey: AppLanguage.defaultsKey) }
            LanguageSettings.shared.reload()
        }
        defaults.set("zh-Hans", forKey: AppLanguage.defaultsKey)
        LanguageSettings.shared.reload()
        let controller = SettingsWindowController(updateChecker: nil,
            defaultAppHandler: ReadOnlyDefaultAppHandler(), captureFixedWindowFrame: {})
        let window = try XCTUnwrap(controller.window)
        let dialog = ImageDeletionDialog(filename: "照片.jpg")
        dialog.suppressionButton.state = .on
        let accessory = ScreenshotExportAccessoryView(sourceSize: CGSize(width: 100, height: 80), displayScale: 0.5)
        accessory.selectedMode = .imageScale
        let exportOptions = accessory.exportOptions
        let canvas = CanvasNSView(frame: .zero, backend: .liveText)
        let menu = NSMenu()
        canvas.debugAppendPicSeeContextMenuItems(to: menu)
        let associationController = DefaultImageAppSettingsViewController(handler: ReadOnlyDefaultAppHandler())
        func allButtons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(allButtons)
        }
        let buttons = allButtons(associationController.view)
        let png = try XCTUnwrap(buttons.first { $0.title.hasPrefix("PNG") })
        png.state = .off
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("language-\(UUID()).png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = ImageViewerViewModel(imageURL: url)
        model.zoomScale = 2.5
        model.panOffset = CGSize(width: 10, height: 20)
        model.rotationDegrees = 90
        let session = model.sessionID
        let document = try ScreenshotDocument(image: XCTUnwrap(model.image), rotationDegrees: 0)
        document.state.selection = CGRect(x: 2, y: 3, width: 20, height: 20)
        document.tool = .pen
        let selection = document.state.selection

        LanguageSettings.shared.set(.english)
        XCTAssertEqual(window.title, "PicSee Settings")
        XCTAssertEqual(dialog.messageText, "Move Image to Trash?")
        XCTAssertEqual(dialog.buttons.map(\.title), ["Cancel", "Move to Trash"])
        XCTAssertEqual(dialog.filename, "照片.jpg")
        XCTAssertEqual(dialog.suppressionButton.state, .on)
        XCTAssertTrue(menu.displayOptionsItems.contains { $0.title == "Show Title Bar" })
        XCTAssertTrue(menu.items.contains { $0.title == "Display Options" })
        XCTAssertEqual(png.state, .off)
        XCTAssertTrue(buttons.contains { $0.title == "Set as Default" })
        XCTAssertEqual(accessory.exportOptions.pixelSize, exportOptions.pixelSize)
        XCTAssertEqual(accessory.selectedMode, .imageScale)
        XCTAssertNil(model.fileSizeText?.range(of: "\\p{Han}", options: .regularExpression))
        XCTAssertEqual(model.sessionID, session)
        XCTAssertEqual(model.currentURL, url)
        XCTAssertEqual(model.zoomScale, 2.5)
        XCTAssertEqual(model.panOffset, CGSize(width: 10, height: 20))
        XCTAssertEqual(model.rotationDegrees, 90)
        XCTAssertEqual(document.state.selection, selection)
        XCTAssertEqual(document.tool, .pen)

        LanguageSettings.shared.set(.simplifiedChinese)
        XCTAssertEqual(window.title, "PicSee 设置")
        XCTAssertEqual(dialog.buttons.map(\.title), ["取消", "移到废纸篓"])
        XCTAssertTrue(menu.displayOptionsItems.contains { $0.title == "显示标题栏" })
        XCTAssertEqual(png.state, .off)
        window.close()
    }

    func testDefaultAppCardBorderResolvesUsingSelectedTheme() throws {
        _ = NSApplication.shared
        let controller = DefaultImageAppSettingsViewController(handler: ReadOnlyDefaultAppHandler())
        func cardLayers(in view: NSView) -> [CALayer] {
            let own = view.layer.map { $0.borderWidth == 0.5 ? [$0] : [] } ?? []
            return own + view.subviews.flatMap { cardLayers(in: $0) }
        }
        let layers = cardLayers(in: controller.view)
        XCTAssertEqual(layers.count, 1)
        for theme in [ViewerTheme.light, .dark, .light] {
            let opposite = try XCTUnwrap(NSAppearance(named: theme == .light ? .darkAqua : .aqua))
            opposite.performAsCurrentDrawingAppearance { controller.applyTheme(theme) }
            let color = try XCTUnwrap(layers.first?.borderColor)
            let rgb = try XCTUnwrap(NSColor(cgColor: color)?.usingColorSpace(.sRGB))
            let expected: CGFloat = theme == .light ? 0 : 1
            XCTAssertEqual(rgb.redComponent, expected, accuracy: 0.01)
            XCTAssertEqual(rgb.greenComponent, expected, accuracy: 0.01)
            XCTAssertEqual(rgb.blueComponent, expected, accuracy: 0.01)
            XCTAssertEqual(rgb.alphaComponent, 0.10, accuracy: 0.001)
        }
    }

    func testEveryInitialPageStaysCenteredAfterDisplayAndLayout() async throws {
        _ = NSApplication.shared
        let suite = "PicSee.SettingsCenterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for page in SettingsPage.allCases {
            let controller = SettingsWindowController(
                preferences: ViewerPreferences(defaults: defaults), updateChecker: nil,
                defaultAppHandler: ReadOnlyDefaultAppHandler(), captureFixedWindowFrame: {}
            )
            let window = try XCTUnwrap(controller.window)
            controller.show(page: page)
            let screen = try XCTUnwrap(window.screen)
            try await Task.sleep(for: .milliseconds(250))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.midX, screen.visibleFrame.midX, accuracy: 1, "\(page) after layout")
            XCTAssertEqual(window.frame.midY, screen.visibleFrame.midY, accuracy: 1, "\(page) after layout")
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.minY + 12))
            window.orderOut(nil)
            controller.show()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(window.frame.midX, screen.visibleFrame.midX, accuracy: 1, "\(page) reopened")
            XCTAssertEqual(window.frame.midY, screen.visibleFrame.midY, accuracy: 1, "\(page) reopened")
            window.orderOut(nil)
        }
    }

    func testSettingsWindowReusesNavigationAndFollowsTheme() async throws {
        _ = NSApplication.shared
        let suite = "PicSee.SettingsWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ViewerPreferences(defaults: defaults)
        let checker = UpdateChecker(
            currentVersion: AppVersion("0.2.58")!, defaults: defaults,
            fetchLatestRelease: {
                try await Task.sleep(for: .milliseconds(500))
                throw URLError(.notConnectedToInternet)
            },
            downloadAndOpen: { _, _ in }
        )
        let controller = SettingsWindowController(
            preferences: preferences, updateChecker: checker,
            defaultAppHandler: ReadOnlyDefaultAppHandler(), captureFixedWindowFrame: {}
        )
        let window = try XCTUnwrap(controller.window)
        defer { window.orderOut(nil) }
        controller.show(page: .defaultApps)
        XCTAssertEqual(controller.navigation.page, .defaultApps)
        let screen = try XCTUnwrap(window.screen)
        XCTAssertEqual(window.frame.midX, screen.visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(window.frame.midY, screen.visibleFrame.midY, accuracy: 1)
        window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.minY + 12))
        controller.show()
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(controller.navigation.page, .defaultApps)
        XCTAssertEqual(window.frame.midX, screen.visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(window.frame.midY, screen.visibleFrame.midY, accuracy: 1)

        preferences.setTheme(.dark)
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        preferences.setTheme(.system)
        XCTAssertNil(window.appearance)

        // Optional visual artifacts from the real AppKit/SwiftUI window.
        if let output = ProcessInfo.processInfo.environment["PICSEE_SETTINGS_SNAPSHOTS"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            func snapshot(_ name: String) throws {
                let content = try XCTUnwrap(window.contentView)
                content.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
            }
            for theme in [ViewerTheme.light, .dark] {
                preferences.setTheme(theme)
                for page in SettingsPage.allCases {
                    controller.show(page: page)
                    try await Task.sleep(for: .milliseconds(150))
                    try snapshot("\(theme.rawValue)-\(page)")
                }
            }
            // Capture changing status text to verify the check button stays put.
            let check = Task { await checker.checkForUpdatesManually() }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(checker.status, .checking)
            try snapshot("2-about-checking")
            _ = await check.value
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertNotNil(checker.checkError)
            try snapshot("2-about-error")
        }
    }
}
