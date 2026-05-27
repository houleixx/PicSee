# GitHub Update Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Release based update checks, lower-left update UI, DMG download/open behavior, and ignored-version persistence.

**Architecture:** Add focused update files under `Sources/PicSee/App/Updates`. `AppVersion` handles numeric semantic comparison, `GitHubReleaseClient` fetches release metadata and builds the DMG URL, and `UpdateChecker` owns UI-facing state and persistence. `WindowManager` injects one checker into `ImageViewerView`, which renders the prompt as an overlay.

**Tech Stack:** Swift 6, Foundation `URLSession`, SwiftUI, AppKit, XCTest.

---

### Task 1: Version Comparison

**Files:**
- Create: `Sources/PicSee/App/Updates/AppVersion.swift`
- Test: `Tests/PicSeeTests/AppVersionTests.swift`

- [ ] Write failing tests for numeric comparison:
  - `0.2.12 > 0.2.11`
  - `0.3.0 > 0.2.99`
  - `1.0 == 1.0.0`
  - `0.10.0 > 0.9.9`
  - `v0.2.11 == 0.2.11`
- [ ] Run `swift test --filter AppVersionTests` and confirm it fails because `AppVersion` does not exist.
- [ ] Implement `AppVersion` as a `Comparable` value that strips a leading `v`, parses numeric dot-separated components, trims trailing zeroes for equality, and compares missing components as zero.
- [ ] Run `swift test --filter AppVersionTests` and confirm it passes.

### Task 2: Release Metadata

**Files:**
- Create: `Sources/PicSee/App/Updates/GitHubReleaseClient.swift`
- Test: `Tests/PicSeeTests/GitHubReleaseClientTests.swift`

- [ ] Write failing tests for decoding `tag_name: "v0.2.13"` and building `https://github.com/houleixx/PicSee/releases/download/v0.2.13/PicSee-0.2.13.dmg`.
- [ ] Run `swift test --filter GitHubReleaseClientTests` and confirm it fails because the client does not exist.
- [ ] Implement release decoding plus deterministic DMG URL construction from the parsed version.
- [ ] Run `swift test --filter GitHubReleaseClientTests` and confirm it passes.

### Task 3: Update State and Ignore Persistence

**Files:**
- Create: `Sources/PicSee/App/Updates/UpdateChecker.swift`
- Test: `Tests/PicSeeTests/UpdateCheckerTests.swift`

- [ ] Write failing tests for showing updates only when latest is greater than current and not equal to the ignored version.
- [ ] Run `swift test --filter UpdateCheckerTests` and confirm it fails because `UpdateChecker` does not exist.
- [ ] Implement `UpdateChecker` with published state, injectable release fetcher, injectable downloader/opener, and injectable `UserDefaults` suite for tests.
- [ ] Run `swift test --filter UpdateCheckerTests` and confirm it passes.

### Task 4: Viewer Integration

**Files:**
- Modify: `Sources/PicSee/App/WindowManager.swift`
- Modify: `Sources/PicSee/Viewer/ImageViewerView.swift`
- Test: existing test suite

- [ ] Update `WindowManager` to create an `UpdateChecker` using `Bundle.main.infoDictionary`.
- [ ] Update `ImageViewerView` to accept the checker and display a lower-left prompt with update and ignore actions.
- [ ] Ensure errors do not block the viewer and failed downloads leave the prompt available for retry.
- [ ] Run `swift test`.

### Task 5: Build Verification

**Files:**
- No source changes expected.

- [ ] Run `swift test`.
- [ ] Run `PICSEE_SKIP_LOCAL_INSTALL=1 Scripts/build-app.sh`.
- [ ] Summarize the version comparison logic for the user with the concrete examples above.
