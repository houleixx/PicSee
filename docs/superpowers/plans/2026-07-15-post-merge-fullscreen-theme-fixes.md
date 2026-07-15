# Post-merge Fullscreen and Theme Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复原生全屏退出与失败恢复、主题菜单重复添加问题，补齐回归测试，并安装验证后的 PicSee。

**Architecture:** 将窗口 frame 恢复计算和全屏失败回滚提取为可直接测试的 `ViewerWindow` 行为；`WindowManager` 负责在切换 style mask 前采集标题栏高度并转交纯计算。主题菜单使用稳定 identifier 保证幂等，主题偏好使用独立 UserDefaults suite 测试。

**Tech Stack:** Swift 6、AppKit、SwiftUI、XCTest、Swift Package Manager、现有 `Scripts/build-app.sh`。

## Global Constraints

- 保持 macOS 14 最低版本，不增加第三方依赖。
- 正常退出全屏时采用用户当前标题栏偏好；进入失败时恢复进入前的 style mask。
- 使用测试先行，每个生产代码改动前必须看到对应测试按预期失败。
- 安装目标为 `~/Applications/PicSee.app`。

---

### Task 1: Fullscreen frame restoration and failure rollback

**Files:**
- Modify: `Sources/PicSee/App/WindowManager.swift:6-33,182-204,301-319,350-385`
- Test: `Tests/PicSeeTests/ViewerWindowTests.swift`

**Interfaces:**
- Produces: `ViewerWindow.frameRestoringHiddenTitleBar(from:titleBarHeight:) -> NSRect`
- Produces: `ViewerWindow.prepareStyleMaskForNativeFullScreen()`
- Produces: `ViewerWindow.restoreStyleMaskAfterFailedFullScreenEntry()`
- Consumes: `ViewerTitleBarPreference.styleMask(titleBarVisible:)`

- [ ] **Step 1: Write failing frame restoration tests**

Add to `ViewerWindowTests`:

```swift
func testHiddenTitleBarFullScreenRestoreRemovesTitledChromeHeight() {
    let frame = NSRect(x: 100, y: 80, width: 800, height: 628)

    XCTAssertEqual(
        ViewerWindow.frameRestoringHiddenTitleBar(from: frame, titleBarHeight: 28),
        NSRect(x: 100, y: 108, width: 800, height: 600)
    )
}

func testHiddenTitleBarFullScreenRestoreClampsInvalidChromeHeight() {
    let frame = NSRect(x: 100, y: 80, width: 800, height: 600)

    XCTAssertEqual(
        ViewerWindow.frameRestoringHiddenTitleBar(from: frame, titleBarHeight: 900),
        frame
    )
}
```

- [ ] **Step 2: Run tests and verify RED**

Run: `swift test --filter ViewerWindowTests`

Expected: compilation fails because `frameRestoringHiddenTitleBar` does not exist.

- [ ] **Step 3: Implement minimal frame helper and use pre-mask geometry**

Add to `ViewerWindow`:

```swift
static func frameRestoringHiddenTitleBar(from frame: NSRect, titleBarHeight: CGFloat) -> NSRect {
    guard titleBarHeight > 0, titleBarHeight < frame.height else { return frame }
    return NSRect(
        x: frame.minX,
        y: frame.minY + titleBarHeight,
        width: frame.width,
        height: frame.height - titleBarHeight
    )
}
```

In `restoreStyleMaskAfterFullScreen`, compute the titled content rect and `titleBarHeight` before changing `window.styleMask`, then call the helper after changing to the preferred style mask.

- [ ] **Step 4: Run frame tests and verify GREEN**

Run: `swift test --filter ViewerWindowTests`

Expected: all `ViewerWindowTests` pass.

- [ ] **Step 5: Write failing full-screen failure rollback test**

Add to `ViewerWindowTests`:

```swift
func testFailedNativeFullScreenEntryRestoresOriginalStyleMaskOnce() {
    let originalMask: NSWindow.StyleMask = [.borderless, .resizable, .fullSizeContentView]
    let window = ViewerWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
        styleMask: originalMask,
        backing: .buffered,
        defer: false
    )

    window.prepareStyleMaskForNativeFullScreen()
    XCTAssertTrue(window.styleMask.contains(.titled))

    window.restoreStyleMaskAfterFailedFullScreenEntry()
    XCTAssertEqual(window.styleMask, originalMask)

    window.styleMask = [.titled, .resizable]
    window.restoreStyleMaskAfterFailedFullScreenEntry()
    XCTAssertEqual(window.styleMask, [.titled, .resizable])
}
```

- [ ] **Step 6: Run rollback test and verify RED**

Run: `swift test --filter ViewerWindowTests/testFailedNativeFullScreenEntryRestoresOriginalStyleMaskOnce`

Expected: compilation fails because the prepare and restore methods do not exist.

- [ ] **Step 7: Implement rollback and delegate failure handling**

Move the existing pre-fullscreen mask change into:

```swift
func prepareStyleMaskForNativeFullScreen() {
    fullScreenPreMask = styleMask
    styleMask = [.titled, .closable, .miniaturizable, .resizable]
}

func restoreStyleMaskAfterFailedFullScreenEntry() {
    guard let fullScreenPreMask else { return }
    styleMask = fullScreenPreMask
    self.fullScreenPreMask = nil
}
```

Call `prepareStyleMaskForNativeFullScreen()` from `toggleFullScreen`. Extend `WindowDelegate` with an `onFailToEnterFullScreen` closure and implement:

```swift
func windowDidFailToEnterFullScreen(_ window: NSWindow) {
    onFailToEnterFullScreen()
}
```

Wire the closure to `ViewerWindow.restoreStyleMaskAfterFailedFullScreenEntry()`. Clear `fullScreenPreMask` after normal exit restoration.

- [ ] **Step 8: Run ViewerWindow tests and commit**

Run: `swift test --filter ViewerWindowTests`

Expected: all tests pass.

```bash
git add Sources/PicSee/App/WindowManager.swift Tests/PicSeeTests/ViewerWindowTests.swift
git commit -m "fix: restore viewer window after fullscreen"
```

### Task 2: Theme menu idempotency and theme preferences

**Files:**
- Modify: `Sources/PicSee/Viewer/ImageCanvasView.swift:1046-1058,1126-1138`
- Modify: `Tests/PicSeeTests/AppMenuTests.swift`
- Create: `Tests/PicSeeTests/ViewerThemeTests.swift`

**Interfaces:**
- Produces: `CanvasNSView.themeMenuIdentifier: NSUserInterfaceItemIdentifier`
- Consumes: `ViewerTheme.current(in:)` and `ViewerTheme.set(_:in:)`

- [ ] **Step 1: Write failing menu idempotency test**

Add to `AppMenuTests`:

```swift
func testAppendingPicSeeItemsTwiceAddsOnlyOneThemeMenu() {
    let view = CanvasNSView(frame: .zero, backend: .liveText)
    let menu = NSMenu(title: "Live Text")

    view.debugAppendPicSeeContextMenuItems(to: menu)
    view.debugAppendPicSeeContextMenuItems(to: menu)

    XCTAssertEqual(menu.items.filter { $0.title == "主题" }.count, 1)
}
```

- [ ] **Step 2: Run idempotency test and verify RED**

Run: `swift test --filter AppMenuTests/testAppendingPicSeeItemsTwiceAddsOnlyOneThemeMenu`

Expected: assertion fails with theme menu count `2` instead of `1`.

- [ ] **Step 3: Implement stable theme menu identifier**

Add to `CanvasNSView`:

```swift
static let themeMenuIdentifier = NSUserInterfaceItemIdentifier("PicSee.ThemeMenu")
```

Replace the action-based top-level check with:

```swift
if menu.items.first(where: { $0.identifier == Self.themeMenuIdentifier }) == nil {
    let themeItem = NSMenuItem(title: "主题", action: nil, keyEquivalent: "")
    themeItem.identifier = Self.themeMenuIdentifier
    // existing submenu construction
}
```

- [ ] **Step 4: Run idempotency test and verify GREEN**

Run: `swift test --filter AppMenuTests/testAppendingPicSeeItemsTwiceAddsOnlyOneThemeMenu`

Expected: test passes.

- [ ] **Step 5: Write ViewerTheme tests**

Create `ViewerThemeTests.swift` with isolated defaults:

```swift
import AppKit
import XCTest
@testable import PicSee

final class ViewerThemeTests: XCTestCase {
    func testDefaultsToSystemAndFallsBackFromInvalidValue() {
        withDefaults { defaults in
            XCTAssertEqual(ViewerTheme.current(in: defaults), .system)
            defaults.set(999, forKey: ViewerTheme.defaultsKey)
            XCTAssertEqual(ViewerTheme.current(in: defaults), .system)
        }
    }

    func testPersistsEveryThemeAndMapsAppearance() {
        withDefaults { defaults in
            for theme in ViewerTheme.allCases {
                ViewerTheme.set(theme, in: defaults)
                XCTAssertEqual(ViewerTheme.current(in: defaults), theme)
            }
            XCTAssertNil(ViewerTheme.system.appearance)
            XCTAssertEqual(ViewerTheme.light.appearance?.name, .aqua)
            XCTAssertEqual(ViewerTheme.dark.appearance?.name, .darkAqua)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "PicSee.ViewerThemeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
```

- [ ] **Step 6: Run theme tests and commit**

Run: `swift test --filter 'AppMenuTests|ViewerThemeTests'`

Expected: all selected tests pass.

```bash
git add Sources/PicSee/Viewer/ImageCanvasView.swift Tests/PicSeeTests/AppMenuTests.swift Tests/PicSeeTests/ViewerThemeTests.swift
git commit -m "fix: make viewer theme menu idempotent"
```

### Task 3: Remove unused toolbar state and verify the repository

**Files:**
- Modify: `Sources/PicSee/Viewer/ImageViewerView.swift:307-309`

**Interfaces:**
- Consumes: existing `toolbarEffectivelyVisible` logic; produces no new interface.

- [ ] **Step 1: Remove unused property**

Delete:

```swift
private var toolbarHoverEdgeFraction: CGFloat {
    isFullScreen ? toolbarEdgeFraction : 1.0
}
```

- [ ] **Step 2: Run complete verification**

Run: `git diff --check`

Expected: no output and exit code 0.

Run: `swift test`

Expected: all tests pass with 0 failures.

Run: `swift build -c release`

Expected: build completes with exit code 0.

- [ ] **Step 3: Commit cleanup**

```bash
git add Sources/PicSee/Viewer/ImageViewerView.swift
git commit -m "refactor: remove unused toolbar state"
```

### Task 4: Build and install locally

**Files:**
- Generated: `build/PicSee.app`
- Installed: `~/Applications/PicSee.app`

**Interfaces:**
- Consumes: `Scripts/build-app.sh`
- Produces: locally installed universal PicSee application.

- [ ] **Step 1: Stop the currently running local app**

Run: `pgrep -fl PicSee`

If PicSee is running, terminate only those PicSee process IDs with `kill <pid>` and verify `pgrep -fl PicSee` returns no PicSee process.

- [ ] **Step 2: Build and install**

Run: `PICSEE_VERSION=0.2.35 PICSEE_BUILD_NUMBER=36 Scripts/build-app.sh`

Expected: arm64 and x86_64 Release builds complete, signing succeeds, and the app is copied to `~/Applications/PicSee.app`.

- [ ] **Step 3: Verify installation**

Run: `file build/PicSee.app/Contents/MacOS/PicSee`

Expected: Mach-O universal binary containing `x86_64` and `arm64`.

Run: `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' ~/Applications/PicSee.app/Contents/Info.plist`

Expected: `0.2.35`.

Run: `/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' ~/Applications/PicSee.app/Contents/Info.plist`

Expected: `36`.

Run: `git status --short --branch`

Expected: clean `master` branch except committed implementation history.
