# PicSee Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build PicSee, a native macOS image viewer that opens Finder-selected images, zooms with the mouse wheel, pans by drag, navigates sibling images with arrow keys, and quits when the final window closes.

**Architecture:** Use a Swift Package for source organization and tests, with an AppKit application entry point hosting SwiftUI views inside `NSWindow`. Keep pure file-navigation logic testable in a small `FolderImageNavigator`; keep desktop integration in `AppDelegate` and `WindowManager`; keep image interaction state in `ImageViewerViewModel` and event handling in an `NSViewRepresentable` canvas.

**Tech Stack:** Swift 6.2, Swift Package Manager, AppKit, SwiftUI, XCTest, shell script for assembling `PicSee.app`.

---

## File Structure

- Create `Package.swift`: Swift Package definition for executable target `PicSee` and test target `PicSeeTests`.
- Create `.gitignore`: ignores Swift build output, generated app bundle, and local brainstorm artifacts.
- Create `Sources/PicSee/main.swift`: AppKit process entry point.
- Create `Sources/PicSee/App/AppDelegate.swift`: handles lifecycle and Finder file-open events.
- Create `Sources/PicSee/App/WindowManager.swift`: creates viewer windows and tracks open windows.
- Create `Sources/PicSee/Navigation/FolderImageNavigator.swift`: scans folders, filters supported image files, sorts them, and provides neighbor lookup.
- Create `Sources/PicSee/Viewer/ImageViewerViewModel.swift`: loads images, owns current URL, navigator state, zoom, pan, and navigation commands.
- Create `Sources/PicSee/Viewer/ImageViewerView.swift`: SwiftUI shell for the viewer surface and error state.
- Create `Sources/PicSee/Viewer/ImageCanvasView.swift`: AppKit-backed image canvas for drawing, wheel zoom, drag pan, double-click reset, and arrow keys.
- Create `Scripts/build-app.sh`: builds release binary and assembles `build/PicSee.app` with an `Info.plist` containing image document types.
- Create `Tests/PicSeeTests/FolderImageNavigatorTests.swift`: tests extension filtering, localized sorting, index detection, and boundary navigation.
- Create `Tests/PicSeeTests/ImageViewerViewModelTests.swift`: tests load failure behavior and navigation reset behavior using temporary image fixtures.

## Task 1: Swift Package Scaffold

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/PicSee/main.swift`
- Test command: `swift test`

- [ ] **Step 1: Create the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicSee",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PicSee", targets: ["PicSee"])
    ],
    targets: [
        .executableTarget(
            name: "PicSee",
            path: "Sources/PicSee"
        ),
        .testTarget(
            name: "PicSeeTests",
            dependencies: ["PicSee"],
            path: "Tests/PicSeeTests"
        )
    ]
)
```

- [ ] **Step 2: Create ignore rules**

Create `.gitignore`:

```gitignore
.build/
.swiftpm/
build/
DerivedData/
*.xcuserdata/
.DS_Store
.superpowers/
```

- [ ] **Step 3: Create a temporary executable entry**

Create `Sources/PicSee/main.swift`:

```swift
import AppKit

print("PicSee scaffold is ready.")
```

- [ ] **Step 4: Verify the package builds and tests**

Run: `swift test`

Expected: command exits with code `0`. SwiftPM may report that there are no tests yet.

- [ ] **Step 5: Commit**

```bash
git add Package.swift .gitignore Sources/PicSee/main.swift
git commit -m "chore: scaffold PicSee Swift package"
```

## Task 2: Folder Image Navigation

**Files:**
- Create: `Sources/PicSee/Navigation/FolderImageNavigator.swift`
- Create: `Tests/PicSeeTests/FolderImageNavigatorTests.swift`
- Test command: `swift test --filter FolderImageNavigatorTests`

- [ ] **Step 1: Write failing navigator tests**

Create `Tests/PicSeeTests/FolderImageNavigatorTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FolderImageNavigatorTests`

Expected: FAIL because `FolderImageNavigator` does not exist.

- [ ] **Step 3: Implement folder navigation**

Create `Sources/PicSee/Navigation/FolderImageNavigator.swift`:

```swift
import Foundation

struct FolderImageNavigator {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "tif", "tiff", "bmp", "webp"
    ]

    let images: [URL]
    let currentIndex: Int

    init(currentImageURL: URL, fileManager: FileManager = .default) throws {
        let standardizedCurrent = currentImageURL.standardizedFileURL
        let folderURL = standardizedCurrent.deletingLastPathComponent()
        let folderContents: [URL]

        do {
            folderContents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            self.images = [standardizedCurrent]
            self.currentIndex = 0
            return
        }

        let sortedImages = folderContents
            .map { $0.standardizedFileURL }
            .filter(Self.isSupportedImage)
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        if let index = sortedImages.firstIndex(of: standardizedCurrent) {
            self.images = sortedImages
            self.currentIndex = index
        } else {
            self.images = [standardizedCurrent]
            self.currentIndex = 0
        }
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return !pathExtension.isEmpty && supportedExtensions.contains(pathExtension)
    }

    func previousURL() -> URL? {
        guard currentIndex > 0 else { return nil }
        return images[currentIndex - 1]
    }

    func nextURL() -> URL? {
        guard currentIndex + 1 < images.count else { return nil }
        return images[currentIndex + 1]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FolderImageNavigatorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PicSee/Navigation/FolderImageNavigator.swift Tests/PicSeeTests/FolderImageNavigatorTests.swift
git commit -m "feat: add folder image navigation"
```

## Task 3: Viewer View Model

**Files:**
- Create: `Sources/PicSee/Viewer/ImageViewerViewModel.swift`
- Create: `Tests/PicSeeTests/ImageViewerViewModelTests.swift`
- Test command: `swift test --filter ImageViewerViewModelTests`

- [ ] **Step 1: Write failing view model tests**

Create `Tests/PicSeeTests/ImageViewerViewModelTests.swift`:

```swift
import AppKit
import XCTest
@testable import PicSee

@MainActor
final class ImageViewerViewModelTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PicSeeViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testLoadsValidImageAndBuildsNavigator() throws {
        let first = try writePNG(named: "001.png", color: .red)
        let second = try writePNG(named: "002.png", color: .blue)

        let viewModel = ImageViewerViewModel(imageURL: first)

        XCTAssertEqual(viewModel.currentURL, first.standardizedFileURL)
        XCTAssertNotNil(viewModel.image)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.currentFilename, "001.png")
        XCTAssertEqual(viewModel.nextURL, second.standardizedFileURL)
    }

    func testInvalidImageShowsErrorState() throws {
        let invalid = temporaryDirectory.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: invalid)

        let viewModel = ImageViewerViewModel(imageURL: invalid)

        XCTAssertNil(viewModel.image)
        XCTAssertEqual(viewModel.currentURL, invalid.standardizedFileURL)
        XCTAssertEqual(viewModel.currentFilename, "broken.jpg")
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testNavigateNextResetsZoomAndPan() throws {
        let first = try writePNG(named: "001.png", color: .red)
        let second = try writePNG(named: "002.png", color: .blue)

        let viewModel = ImageViewerViewModel(imageURL: first)
        viewModel.zoomScale = 3
        viewModel.panOffset = CGSize(width: 40, height: 50)

        viewModel.navigate(to: second)

        XCTAssertEqual(viewModel.currentURL, second.standardizedFileURL)
        XCTAssertEqual(viewModel.zoomScale, 1)
        XCTAssertEqual(viewModel.panOffset, .zero)
        XCTAssertNotNil(viewModel.image)
    }

    private func writePNG(named name: String, color: NSColor) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to create PNG fixture")
            return url
        }

        try data.write(to: url)
        return url.standardizedFileURL
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageViewerViewModelTests`

Expected: FAIL because `ImageViewerViewModel` does not exist.

- [ ] **Step 3: Implement the view model**

Create `Sources/PicSee/Viewer/ImageViewerViewModel.swift`:

```swift
import AppKit
import Foundation
import SwiftUI

@MainActor
final class ImageViewerViewModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var image: NSImage?
    @Published private(set) var errorMessage: String?
    @Published var zoomScale: CGFloat = 1
    @Published var panOffset: CGSize = .zero

    private var navigator: FolderImageNavigator?

    init(imageURL: URL) {
        self.currentURL = imageURL.standardizedFileURL
        load(imageURL: imageURL)
    }

    var currentFilename: String {
        currentURL.lastPathComponent
    }

    var previousURL: URL? {
        navigator?.previousURL()
    }

    var nextURL: URL? {
        navigator?.nextURL()
    }

    func navigateToPrevious() {
        guard let previousURL else { return }
        navigate(to: previousURL)
    }

    func navigateToNext() {
        guard let nextURL else { return }
        navigate(to: nextURL)
    }

    func navigate(to url: URL) {
        load(imageURL: url)
    }

    func resetViewTransform() {
        zoomScale = 1
        panOffset = .zero
    }

    private func load(imageURL: URL) {
        let standardizedURL = imageURL.standardizedFileURL
        currentURL = standardizedURL
        resetViewTransform()

        do {
            navigator = try FolderImageNavigator(currentImageURL: standardizedURL)
        } catch {
            navigator = nil
        }

        guard let loadedImage = NSImage(contentsOf: standardizedURL), loadedImage.isValid else {
            image = nil
            errorMessage = "PicSee could not open this image."
            return
        }

        image = loadedImage
        errorMessage = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ImageViewerViewModelTests`

Expected: PASS.

- [ ] **Step 5: Run all tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/PicSee/Viewer/ImageViewerViewModel.swift Tests/PicSeeTests/ImageViewerViewModelTests.swift
git commit -m "feat: add image viewer state model"
```

## Task 4: AppKit Lifecycle and Window Management

**Files:**
- Modify: `Sources/PicSee/main.swift`
- Create: `Sources/PicSee/App/AppDelegate.swift`
- Create: `Sources/PicSee/App/WindowManager.swift`
- Test command: `swift test`

- [ ] **Step 1: Replace the temporary executable entry**

Replace `Sources/PicSee/main.swift`:

```swift
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()

application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
```

- [ ] **Step 2: Add app delegate**

Create `Sources/PicSee/App/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where FolderImageNavigator.isSupportedImage(url) {
            windowManager.openViewer(for: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 3: Add window manager**

Create `Sources/PicSee/App/WindowManager.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class WindowManager {
    private var windows: [ObjectIdentifier: NSWindow] = [:]

    func openViewer(for url: URL) {
        let viewModel = ImageViewerViewModel(imageURL: url)
        let rootView = ImageViewerView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        let identifier = ObjectIdentifier(window)
        windows[identifier] = window

        window.title = viewModel.currentFilename
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = WindowDelegate(onClose: { [weak self] in
            self?.windows.removeValue(forKey: identifier)
        })
        objc_setAssociatedObject(window, &WindowManager.delegateAssociationKey, window.delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        NSApp.activate(ignoringOtherApps: true)
    }

    private static var delegateAssociationKey: UInt8 = 0
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
```

- [ ] **Step 4: Run tests and build**

Run: `swift test`

Expected: PASS.

Run: `swift build`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PicSee/main.swift Sources/PicSee/App/AppDelegate.swift Sources/PicSee/App/WindowManager.swift
git commit -m "feat: add macOS app lifecycle"
```

## Task 5: Viewer UI and Interactive Canvas

**Files:**
- Create: `Sources/PicSee/Viewer/ImageViewerView.swift`
- Create: `Sources/PicSee/Viewer/ImageCanvasView.swift`
- Test command: `swift test`

- [ ] **Step 1: Add SwiftUI viewer shell**

Create `Sources/PicSee/Viewer/ImageViewerView.swift`:

```swift
import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var viewModel: ImageViewerViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = viewModel.image {
                ImageCanvasView(
                    image: image,
                    zoomScale: $viewModel.zoomScale,
                    panOffset: $viewModel.panOffset,
                    onPrevious: viewModel.navigateToPrevious,
                    onNext: viewModel.navigateToNext,
                    onReset: viewModel.resetViewTransform
                )
            } else {
                VStack(spacing: 12) {
                    Text("Cannot Open Image")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(viewModel.errorMessage ?? "PicSee could not open this file.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(viewModel.currentFilename)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(32)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
```

- [ ] **Step 2: Add AppKit image canvas**

Create `Sources/PicSee/Viewer/ImageCanvasView.swift`:

```swift
import AppKit
import SwiftUI

struct ImageCanvasView: NSViewRepresentable {
    let image: NSImage
    @Binding var zoomScale: CGFloat
    @Binding var panOffset: CGSize
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReset: () -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.image = image
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onReset = onReset
        view.onZoomChanged = { zoomScale = $0 }
        view.onPanChanged = { panOffset = $0 }
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.image = image
        nsView.zoomScale = zoomScale
        nsView.panOffset = panOffset
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onReset = onReset
        nsView.needsDisplay = true
    }
}

final class CanvasNSView: NSView {
    var image: NSImage? {
        didSet {
            if oldValue !== image {
                zoomScale = 1
                panOffset = .zero
            }
            needsDisplay = true
        }
    }

    var zoomScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    var panOffset: CGSize = .zero {
        didSet { needsDisplay = true }
    }

    var onZoomChanged: ((CGFloat) -> Void)?
    var onPanChanged: ((CGSize) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onReset: (() -> Void)?

    private var dragStartPoint: NSPoint?
    private var dragStartOffset: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()

        guard let image, image.size.width > 0, image.size.height > 0 else { return }

        let fitScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let displayScale = max(0.01, fitScale * zoomScale)
        let displaySize = NSSize(width: image.size.width * displayScale, height: image.size.height * displayScale)
        let origin = NSPoint(
            x: bounds.midX - displaySize.width / 2 + panOffset.width,
            y: bounds.midY - displaySize.height / 2 + panOffset.height
        )
        let rect = NSRect(origin: origin, size: displaySize)

        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [
            .interpolation: NSImageInterpolation.high.rawValue
        ])
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else { return }

        let multiplier = delta > 0 ? 1.08 : 0.92
        let nextZoom = min(20, max(1, zoomScale * multiplier))
        zoomScale = nextZoom
        onZoomChanged?(nextZoom)

        if nextZoom == 1 {
            panOffset = .zero
            onPanChanged?(.zero)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            zoomScale = 1
            panOffset = .zero
            onZoomChanged?(1)
            onPanChanged?(.zero)
            onReset?()
            return
        }

        dragStartPoint = convert(event.locationInWindow, from: nil)
        dragStartOffset = panOffset
    }

    override func mouseDragged(with event: NSEvent) {
        guard zoomScale > 1, let dragStartPoint else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let nextOffset = CGSize(
            width: dragStartOffset.width + currentPoint.x - dragStartPoint.x,
            height: dragStartOffset.height + currentPoint.y - dragStartPoint.y
        )
        panOffset = constrainedPan(nextOffset)
        onPanChanged?(panOffset)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onPrevious?()
        case 124:
            onNext?()
        case 53:
            window?.close()
        default:
            super.keyDown(with: event)
        }
    }

    private func constrainedPan(_ proposed: CGSize) -> CGSize {
        guard let image else { return .zero }
        let fitScale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let displayWidth = image.size.width * fitScale * zoomScale
        let displayHeight = image.size.height * fitScale * zoomScale
        let maxX = max(0, (displayWidth - bounds.width) / 2 + 80)
        let maxY = max(0, (displayHeight - bounds.height) / 2 + 80)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
```

- [ ] **Step 3: Build and run tests**

Run: `swift test`

Expected: PASS.

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/PicSee/Viewer/ImageViewerView.swift Sources/PicSee/Viewer/ImageCanvasView.swift
git commit -m "feat: add interactive image viewer"
```

## Task 6: Build an Installable App Bundle

**Files:**
- Create: `Scripts/build-app.sh`
- Test command: `Scripts/build-app.sh`

- [ ] **Step 1: Add app bundle build script**

Create `Scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/PicSee.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/PicSee" "$MACOS_DIR/PicSee"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PicSee</string>
    <key>CFBundleIdentifier</key>
    <string>local.picsee.viewer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PicSee</string>
    <key>CFBundleDisplayName</key>
    <string>PicSee</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.jpeg</string>
                <string>public.png</string>
                <string>com.compuserve.gif</string>
                <string>public.heic</string>
                <string>public.tiff</string>
                <string>com.microsoft.bmp</string>
                <string>org.webmproject.webp</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x Scripts/build-app.sh`

Expected: command exits with code `0`.

- [ ] **Step 3: Build the app bundle**

Run: `Scripts/build-app.sh`

Expected: command exits with code `0` and prints `Built /Users/holly/code/Demo/PicSee/build/PicSee.app`.

- [ ] **Step 4: Verify app bundle metadata exists**

Run: `test -f build/PicSee.app/Contents/Info.plist && test -x build/PicSee.app/Contents/MacOS/PicSee`

Expected: command exits with code `0`.

- [ ] **Step 5: Commit**

```bash
git add Scripts/build-app.sh
git commit -m "build: assemble PicSee app bundle"
```

## Task 7: Manual Desktop Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-13-picsee-implementation.md`
- Test command: `Scripts/build-app.sh`

- [ ] **Step 1: Create manual verification fixtures**

Run:

```bash
mkdir -p build/manual-fixtures
sips -s format png /System/Library/Desktop\ Pictures/*.heic --out build/manual-fixtures >/dev/null 2>&1 || true
```

Expected: command exits with code `0`. If no fixtures are created from system wallpapers, use any local image folder for the following steps.

- [ ] **Step 2: Build PicSee**

Run: `Scripts/build-app.sh`

Expected: command exits with code `0`.

- [ ] **Step 3: Launch PicSee with an image URL**

Run: `open -a "$PWD/build/PicSee.app" build/manual-fixtures`

Expected: Finder opens the fixture folder. Double-click or right-click an image and choose PicSee from "Open With". PicSee opens a window with the image.

- [ ] **Step 4: Verify interactions manually**

Confirm these behaviors:

- The image opens centered and fit-to-window.
- Mouse wheel up zooms in.
- Mouse wheel down zooms out.
- Dragging a zoomed image pans it.
- Double-click resets to fit-to-window.
- Right arrow moves to the next image in the same folder.
- Left arrow moves to the previous image in the same folder.
- Closing the PicSee window quits the app.

- [ ] **Step 5: Record verification result in the plan**

Append this section to this plan:

```markdown
## Manual Verification Result

- Date: 2026-05-13
- Build command: `Scripts/build-app.sh`
- Result: PASS
- Notes: Finder open, wheel zoom, drag pan, double-click reset, arrow navigation, and close-to-quit were manually verified.
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-05-13-picsee-implementation.md
git commit -m "test: record PicSee manual verification"
```

## Self-Review

- Spec coverage: Finder file-open handling is covered by Tasks 4 and 6; centered fit-to-window display, wheel zoom, drag pan, double-click reset, and arrow navigation are covered by Task 5; same-folder filtering and navigation are covered by Task 2; load state and transform reset are covered by Task 3; close-to-quit is covered by Task 4; buildable app bundle is covered by Task 6; manual desktop verification is covered by Task 7.
- Placeholder scan: The plan contains no unresolved placeholder markers or unspecified implementation steps.
- Type consistency: `FolderImageNavigator`, `ImageViewerViewModel`, `ImageViewerView`, `ImageCanvasView`, `AppDelegate`, and `WindowManager` names and method signatures are consistent across tasks.
