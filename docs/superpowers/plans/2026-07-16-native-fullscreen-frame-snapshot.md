# Native Fullscreen Frame Snapshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完善 PR #4，并用稳定的单元测试证明三种标题栏切换场景退出原生全屏后都会恢复原始窗口 frame。

**Architecture:** `ViewerWindow` 用一个私有快照同时保存进入全屏前的 `styleMask` 和 `frame`。正常退出通过单一方法应用当前标题栏偏好的样式并恢复原始 frame；进入失败恢复快照中的原始样式和 frame。`WindowManager` 只负责选择目标样式及执行公共外观收尾。

**Tech Stack:** Swift 6、AppKit、XCTest、Swift Package Manager。

## Global Constraints

- 不增加第三方依赖。
- 不增加依赖真实 macOS 全屏动画的 UI 自动化测试。
- 不改变临时桌面全屏行为。
- 正常退出使用用户退出时的标题栏偏好；进入失败使用进入前的原始样式。
- 所有生产代码调整都必须由先失败的回归测试驱动。

---

### Task 1: Fullscreen snapshot restoration

**Files:**
- Modify: `Tests/PicSeeTests/ViewerWindowTests.swift`
- Modify: `Sources/PicSee/App/WindowManager.swift:5-55,320-350`

**Interfaces:**
- Produces: `ViewerWindow.completeNativeFullScreenExit(restoring: NSWindow.StyleMask) -> Bool`
- Consumes: `ViewerWindow.prepareStyleMaskForNativeFullScreen()`
- Consumes: `ViewerTitleBarPreference.styleMask(titleBarVisible:) -> NSWindow.StyleMask`

- [ ] **Step 1: Write the three failing title-bar transition tests**

Add a shared assertion helper and three explicitly named tests to `ViewerWindowTests`:

```swift
func testHiddenTitleBarExitRestoresOriginalFrame() {
    assertNativeFullScreenExit(
        entryMask: [.borderless, .resizable, .fullSizeContentView],
        exitMask: [.borderless, .resizable, .fullSizeContentView]
    )
}

func testChangingFromHiddenToVisibleTitleBarInFullScreenRestoresOriginalFrame() {
    assertNativeFullScreenExit(
        entryMask: [.borderless, .resizable, .fullSizeContentView],
        exitMask: [.titled, .closable, .miniaturizable, .resizable]
    )
}

func testChangingFromVisibleToHiddenTitleBarInFullScreenRestoresOriginalFrame() {
    assertNativeFullScreenExit(
        entryMask: [.titled, .closable, .miniaturizable, .resizable],
        exitMask: [.borderless, .resizable, .fullSizeContentView]
    )
}

private func assertNativeFullScreenExit(
    entryMask: NSWindow.StyleMask,
    exitMask: NSWindow.StyleMask,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let window = ViewerWindow(
        contentRect: NSRect(x: 100, y: 80, width: 800, height: 600),
        styleMask: entryMask,
        backing: .buffered,
        defer: false
    )
    let originalFrame = window.frame

    window.prepareStyleMaskForNativeFullScreen()
    window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)

    XCTAssertTrue(window.completeNativeFullScreenExit(restoring: exitMask), file: file, line: line)
    XCTAssertEqual(window.frame, originalFrame, file: file, line: line)
    XCTAssertEqual(window.styleMask, exitMask, file: file, line: line)

    let frameAfterExit = window.frame
    XCTAssertFalse(window.completeNativeFullScreenExit(restoring: entryMask), file: file, line: line)
    XCTAssertEqual(window.frame, frameAfterExit, file: file, line: line)
}
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
swift test --filter 'ViewerWindowTests/(testHiddenTitleBarExitRestoresOriginalFrame|testChangingFromHiddenToVisibleTitleBarInFullScreenRestoresOriginalFrame|testChangingFromVisibleToHiddenTitleBarInFullScreenRestoresOriginalFrame)'
```

Expected: compilation fails because `completeNativeFullScreenExit(restoring:)` does not exist. This proves the tests require the new atomic restore behavior rather than passing against the PR implementation unchanged.

- [ ] **Step 3: Replace the two loose fields with one private snapshot**

In `ViewerWindow`, replace `fullScreenPreMask` and `preFullScreenFrame` with:

```swift
private struct NativeFullScreenSnapshot {
    let styleMask: NSWindow.StyleMask
    let frame: NSRect
}

private var nativeFullScreenSnapshot: NativeFullScreenSnapshot?
```

Update the guard in `toggleFullScreen(_:)` and snapshot capture:

```swift
guard nativeFullScreenSnapshot == nil else { return }

func prepareStyleMaskForNativeFullScreen() {
    guard nativeFullScreenSnapshot == nil else { return }
    nativeFullScreenSnapshot = NativeFullScreenSnapshot(styleMask: styleMask, frame: frame)
    styleMask = [.titled, .closable, .miniaturizable, .resizable]
}
```

- [ ] **Step 4: Implement atomic success and failure restoration**

Replace the old restore/complete methods with:

```swift
func restoreStyleMaskAfterFailedFullScreenEntry() {
    guard let snapshot = nativeFullScreenSnapshot else { return }
    styleMask = snapshot.styleMask
    setFrame(snapshot.frame, display: true)
    nativeFullScreenSnapshot = nil
}

@discardableResult
func completeNativeFullScreenExit(restoring styleMask: NSWindow.StyleMask) -> Bool {
    guard let snapshot = nativeFullScreenSnapshot else { return false }
    self.styleMask = styleMask
    setFrame(snapshot.frame, display: true)
    nativeFullScreenSnapshot = nil
    return true
}
```

- [ ] **Step 5: Make WindowManager use one restore path and one common epilogue**

Replace `restoreStyleMaskAfterFullScreen(to:)` with:

```swift
private func restoreStyleMaskAfterFullScreen(to window: NSWindow) {
    let titleBarVisible = ViewerTitleBarPreference.isVisible()
    let preferredStyleMask = ViewerTitleBarPreference.styleMask(titleBarVisible: titleBarVisible)
    let fallbackFrame = window.frame

    if let viewerWindow = window as? ViewerWindow,
       viewerWindow.completeNativeFullScreenExit(restoring: preferredStyleMask) {
        // The viewer restored the frame captured before entering native full screen.
    } else {
        window.styleMask = preferredStyleMask
        window.setFrame(fallbackFrame, display: true)
    }

    applyWindowShape(to: window, titleBarVisible: titleBarVisible)
    applyFixedWindowState(WindowFramePreference.isFixedEnabled(), to: window)
}
```

- [ ] **Step 6: Run ViewerWindow tests and verify GREEN**

Run: `swift test --filter ViewerWindowTests`

Expected: all `ViewerWindowTests` pass, including all three frame restoration scenarios.

- [ ] **Step 7: Strengthen failure and repeated-prepare tests**

Update the existing failure test to change the frame after prepare and assert both original frame and mask are restored. Update the repeated-prepare test to change the frame between its two prepare calls and assert the first frame is restored:

```swift
let originalFrame = window.frame
window.prepareStyleMaskForNativeFullScreen()
window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)
window.restoreStyleMaskAfterFailedFullScreenEntry()
XCTAssertEqual(window.frame, originalFrame)
XCTAssertEqual(window.styleMask, originalMask)
```

For repeated preparation, save `originalFrame`, call prepare, change the frame, call prepare again, then call `restoreStyleMaskAfterFailedFullScreenEntry()` and assert `window.frame == originalFrame`.

- [ ] **Step 8: Run the strengthened tests and commit**

Run: `swift test --filter ViewerWindowTests`

Expected: all selected tests pass with zero failures.

```bash
git add Sources/PicSee/App/WindowManager.swift Tests/PicSeeTests/ViewerWindowTests.swift
git commit -m "test: cover fullscreen frame restoration"
```

### Task 2: Repository verification and PR landing

**Files:**
- Verify: `Sources/PicSee/App/WindowManager.swift`
- Verify: `Tests/PicSeeTests/ViewerWindowTests.swift`
- Verify: `docs/superpowers/specs/2026-07-16-native-fullscreen-frame-snapshot-design.md`
- Verify: `docs/superpowers/plans/2026-07-16-native-fullscreen-frame-snapshot.md`

**Interfaces:**
- Consumes: all Task 1 window restoration behavior.
- Produces: a verified PR branch ready to merge into `master`.

- [ ] **Step 1: Run repository checks**

Run: `git diff --check origin/master...HEAD`

Expected: no output and exit code 0.

Run: `swift test`

Expected: all tests pass with zero failures.

Run: `swift build -c release`

Expected: Release build completes with exit code 0.

- [ ] **Step 2: Inspect final scope**

Run:

```bash
git status --short
git diff --stat origin/master...HEAD
git log --oneline origin/master..HEAD
```

Expected: clean worktree; changes are limited to the fullscreen implementation, its tests, and the two approved design/plan documents.

- [ ] **Step 3: Push the updated PR branch**

Push the local commits to the PR head branch `codex-fix-fullscreen-frame` using the authenticated GitHub transport. Confirm PR #4 remains mergeable and that required checks are not failing.

- [ ] **Step 4: Merge and verify master**

Merge PR #4 using the repository-supported merge method, delete the remote feature branch, switch to `master`, and fast-forward from `origin/master`.

Run: `swift test`

Expected: the merged `master` passes the complete test suite with zero failures.
