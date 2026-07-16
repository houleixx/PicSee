# Safe Window Frame Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore compilation after PR #5 and ensure native full-screen transitions never overwrite the saved normal or fixed window frame.

**Architecture:** `ViewerWindow` remains the sole owner of the native full-screen snapshot and exposes a read-only `persistableFrame`. `WindowManager` routes both resize and close persistence through one helper so every caller uses the same transition-safe policy.

**Tech Stack:** Swift 6, AppKit, XCTest, Swift Package Manager

## Global Constraints

- Preserve the private `NativeFullScreenSnapshot` introduced by PR #4; do not restore duplicated full-screen state.
- A snapshot frame takes priority over the `.fullScreen` style bit during entry and exit transitions.
- A full-screen window without a valid snapshot must not persist a frame.
- Temporary desktop-fill behavior and unrelated window placement logic remain unchanged.

---

### Task 1: Restore a compilable baseline

**Files:**
- Modify: `Sources/PicSee/App/WindowManager.swift:6-60`

**Interfaces:**
- Consumes: `ViewerWindow.nativeFullScreenSnapshot`
- Produces: temporary read-only `ViewerWindow.preFullScreenFrame: NSRect?`, removed in Task 2

- [ ] **Step 1: Confirm the existing compile regression is red**

Run:

```bash
swift test
```

Expected: compilation fails at `WindowManager.swift` because `ViewerWindow` has no member `preFullScreenFrame`.

- [ ] **Step 2: Add the smallest compatibility accessor**

Add inside `ViewerWindow`, immediately after `nativeFullScreenSnapshot`:

```swift
var preFullScreenFrame: NSRect? {
    nativeFullScreenSnapshot?.frame
}
```

This is a temporary green step that reconnects PR #5 to the PR #4 snapshot without adding a second source of state.

- [ ] **Step 3: Verify the baseline is green**

Run:

```bash
swift test
```

Expected: all existing tests pass. Do not commit the temporary accessor separately; Task 2 replaces it with the final API.

---

### Task 2: Define and test the persistence policy

**Files:**
- Modify: `Tests/PicSeeTests/ViewerWindowTests.swift:120-232`
- Modify: `Sources/PicSee/App/WindowManager.swift:6-60`

**Interfaces:**
- Consumes: `ViewerWindow.frame`, `ViewerWindow.styleMask`, and `NativeFullScreenSnapshot.frame`
- Produces: `ViewerWindow.persistableFrame: NSRect?`

- [ ] **Step 1: Write failing policy tests**

Add to `ViewerWindowTests`:

```swift
func testNormalWindowUsesCurrentFrameForPersistence() {
    let window = ViewerWindow(
        contentRect: NSRect(x: 100, y: 80, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    XCTAssertEqual(window.persistableFrame, window.frame)
}

func testNativeFullScreenTransitionUsesCapturedFrameForPersistence() {
    let window = ViewerWindow(
        contentRect: NSRect(x: 100, y: 80, width: 800, height: 600),
        styleMask: [.borderless, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    let originalFrame = window.frame

    window.prepareStyleMaskForNativeFullScreen()
    window.setFrame(NSRect(x: 0, y: 0, width: 1440, height: 900), display: false)

    XCTAssertEqual(window.persistableFrame, originalFrame)
}

func testFullScreenWithoutSnapshotHasNoPersistableFrame() {
    XCTAssertNil(ViewerWindow.persistableFrame(
        currentFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        capturedFrame: nil,
        isFullScreen: true
    ))
}
```

Also extend the existing failure and success cleanup tests. After
`restoreStyleMaskAfterFailedFullScreenEntry()` and after
`completeNativeFullScreenExit(restoring:)`, move the window to a distinct normal
frame and assert that `persistableFrame` follows that new frame:

```swift
let normalFrameAfterCleanup = NSRect(x: 180, y: 140, width: 720, height: 480)
window.setFrame(normalFrameAfterCleanup, display: false)
XCTAssertEqual(window.persistableFrame, normalFrameAfterCleanup)
```

These assertions prove both cleanup paths clear the snapshot-backed persistence
state instead of continuing to return the entry frame.

- [ ] **Step 2: Run focused tests and verify red**

Run:

```bash
swift test --filter ViewerWindowTests
```

Expected: compilation fails because `persistableFrame` and the static policy function do not exist.

- [ ] **Step 3: Replace the temporary accessor with the final policy**

Remove the temporary `preFullScreenFrame` accessor from Task 1 and add:

```swift
var persistableFrame: NSRect? {
    Self.persistableFrame(
        currentFrame: frame,
        capturedFrame: nativeFullScreenSnapshot?.frame,
        isFullScreen: styleMask.contains(.fullScreen)
    )
}

static func persistableFrame(
    currentFrame: NSRect,
    capturedFrame: NSRect?,
    isFullScreen: Bool
) -> NSRect? {
    if let capturedFrame {
        return capturedFrame
    }
    return isFullScreen ? nil : currentFrame
}
```

- [ ] **Step 4: Run focused tests and verify green**

Run:

```bash
swift test --filter ViewerWindowTests
```

Expected: all `ViewerWindowTests` pass.

---

### Task 3: Route resize and close persistence through one helper

**Files:**
- Modify: `Sources/PicSee/App/WindowManager.swift:207-235`
- Modify: `Sources/PicSee/App/WindowManager.swift:329-345`

**Interfaces:**
- Consumes: `ViewerWindow.persistableFrame: NSRect?`
- Produces: `WindowManager.saveWindowFrame(_ window: ViewerWindow)`

- [ ] **Step 1: Replace both closure implementations**

Use the shared helper from both callbacks:

```swift
onFrameChanged: { [weak self, weak window] in
    guard let self, let window else { return }
    self.saveWindowFrame(window)
},
onClose: { [weak self, weak window] in
    if let self, let window {
        self.saveWindowFrame(window)
    }
    self?.titleObserver = nil
    if let monitor = self?.keyEventMonitor {
        NSEvent.removeMonitor(monitor)
        self?.keyEventMonitor = nil
    }
    self?.currentWindow = nil
},
```

Add this private helper near the other `WindowManager` frame helpers:

```swift
private func saveWindowFrame(_ window: ViewerWindow) {
    guard let frame = window.persistableFrame else { return }
    WindowFramePreference.save(frame)
    if WindowFramePreference.isFixedEnabled() {
        WindowFramePreference.saveFixedFrame(frame)
    }
}
```

- [ ] **Step 2: Re-run focused tests**

Run:

```bash
swift test --filter ViewerWindowTests
```

Expected: all focused tests pass and no `preFullScreenFrame` reference remains.

- [ ] **Step 3: Run the full test suite**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 4: Run release verification**

Run:

```bash
swift build -c release
git diff --check
```

Expected: release build succeeds and `git diff --check` produces no output.

- [ ] **Step 5: Commit the verified fix**

```bash
git add Sources/PicSee/App/WindowManager.swift Tests/PicSeeTests/ViewerWindowTests.swift docs/superpowers/plans/2026-07-16-safe-window-frame-persistence.md
git commit -m "fix: preserve window frame during fullscreen transitions"
```
