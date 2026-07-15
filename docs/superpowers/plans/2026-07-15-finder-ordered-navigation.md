# Finder-Ordered Image Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Navigate sibling images using a stable snapshot of the matching Finder window's current order while pruning files deleted during browsing.

**Architecture:** A Finder adapter returns an optional ordered URL snapshot through Apple Events. `FolderImageNavigator` remains the testable ordering boundary and becomes a retained, mutable session navigator that removes missing neighbors; `ImageViewerViewModel` performs retry-on-deletion navigation without changing corrupt-file behavior.

**Tech Stack:** Swift 6, Foundation, AppKit `NSAppleScript`, XCTest, macOS 14+, hardened runtime

## Global Constraints

- Finder ordering is best-effort and always falls back to localized natural filename order.
- Finder is queried once per viewer session, not once per image switch.
- Snapshot order never changes during the session; only missing URLs are removed.
- New files, renamed files, and Finder sorting changes take effect only in a new viewer session.
- No third-party dependencies.

---

### Task 1: Preferred Order and Mutable Snapshot Navigation

**Files:**
- Modify: `Sources/PicSee/Navigation/FolderImageNavigator.swift`
- Modify: `Tests/PicSeeTests/FolderImageNavigatorTests.swift`

**Interfaces:**
- `FolderImageNavigator.init(currentImageURL:fileManager:preferredOrder:)`
- `FolderImageNavigator.previousURL()` and `nextURL()` mutate the retained snapshot by pruning missing candidates.
- `FolderImageNavigator.move(to:)` advances the current index without rebuilding the snapshot.
- `FolderImageNavigator.removeFromSnapshot(_:)` removes a URL that disappeared during decode.

- [x] Add failing tests proving preferred order overrides filename order, unsupported/duplicate URLs are discarded, the current index matches Finder order, and omitted current URLs fall back to filename order.
- [x] Run `swift test --filter FolderImageNavigatorTests` and verify failures are caused by the missing preferred-order API.
- [x] Implement preferred-order normalization and fallback with this decision: use preferred order only when it contains the standardized current URL; otherwise use the existing folder scan.
- [x] Add failing tests where deleted files immediately before and after the current image are pruned and lookup continues to the nearest surviving URL.
- [x] Implement mutable previous/next scanning plus `move(to:)` and `removeFromSnapshot(_:)`.
- [x] Run `swift test --filter FolderImageNavigatorTests`; expect zero failures.

### Task 2: Finder Ordering Adapter and Signed-App Permission

**Files:**
- Create: `Sources/PicSee/Navigation/FinderFolderOrderProvider.swift`
- Create: `Tests/PicSeeTests/FinderFolderOrderProviderTests.swift`
- Create: `Resources/PicSee.entitlements`
- Modify: `Scripts/build-app.sh`
- Modify: `Tests/PicSeeTests/MinimumSystemVersionTests.swift`

**Interfaces:**
- `protocol FinderFolderOrderProviding { func orderedURLs(for folderURL: URL) -> [URL]? }`
- `struct FinderFolderOrderProvider` implements the protocol with `NSAppleScript`.
- `FinderFolderOrderProvider.scriptSource(folderURL:)` is internal for deterministic script coverage tests.

- [x] Add failing script-source tests requiring matching target URL, list sort columns, reverse direction, icon arrangement, manual position ordering, column-name order, and nil-on-error parsing.
- [x] Implement a read-only Finder script that returns URL strings separated by line feed. Escape the folder URL as an AppleScript string literal before interpolation.
- [x] Add failing build-script tests requiring `NSAppleEventsUsageDescription`, `com.apple.security.automation.apple-events`, and `codesign --entitlements`.
- [x] Add `Resources/PicSee.entitlements`, embed the Chinese Finder-access explanation in Info.plist, and pass the entitlement to `codesign`.
- [x] Run `swift test --filter FinderFolderOrderProviderTests` and `swift test --filter MinimumSystemVersionTests`; expect zero failures.

### Task 3: Viewer Session Integration and Deletion Retry

**Files:**
- Modify: `Sources/PicSee/Viewer/ImageViewerViewModel.swift`
- Modify: `Tests/PicSeeTests/ImageViewerViewModelTests.swift`

**Interfaces:**
- `ImageViewerViewModel.init(imageURL:finderOrderProvider:fileManager:)` supports test injection with production defaults.
- Initial load constructs one navigator using `finderOrderProvider.orderedURLs(for:)`.
- Navigation calls `navigator.move(to:)` after successful decode and calls `removeFromSnapshot(_:)` before retrying a candidate that no longer exists.

- [x] Add failing tests proving Finder is queried once, its order drives navigation, later Finder changes do not reorder the session, and a candidate deleted between lookup and load is removed and skipped.
- [x] Implement retained-navigator setup and retry-on-missing navigation while preserving the existing error state for present but invalid images.
- [x] Run `swift test --filter ImageViewerViewModelTests`; expect zero failures.

### Task 4: Verification

**Files:**
- Review all files changed by Tasks 1–3.

- [x] Run `swift test`; expect all tests to pass with zero failures.
- [x] Run `swift build`; expect exit code 0.
- [x] Run `PICSEE_SKIP_LOCAL_INSTALL=1 Scripts/build-app.sh`; expect a signed universal app bundle.
- [x] Verify `codesign -d --entitlements :- build/PicSee.app` contains `com.apple.security.automation.apple-events` and the built Info.plist contains `NSAppleEventsUsageDescription`.
- [x] Run `git diff --check` and inspect the full diff for unrelated changes, placeholders, and requirement gaps.
