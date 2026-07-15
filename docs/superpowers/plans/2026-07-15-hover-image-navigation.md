# Hover Image Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add previous and next image buttons that briefly introduce themselves, then appear only in the corresponding outer 20% hover zone.

**Architecture:** Put pointer-to-visibility decisions in a pure `ImageNavigationVisibilityPolicy`, then render the resulting controls as SwiftUI overlays in `ImageViewerView`. The existing view model remains the source of navigation availability and actions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, macOS 14+

## Global Constraints

- Preserve keyboard navigation, OCR selection, image panning, window dragging, zooming, and double-click reset.
- Use an outer-edge fraction of exactly `0.20`.
- Use a discovery reveal duration of `1.2` seconds and a fade duration of `0.18` seconds.
- Do not add dependencies.

---

### Task 1: Testable Visibility Policy

**Files:**
- Create: `Sources/PicSee/Viewer/ImageNavigationVisibilityPolicy.swift`
- Create: `Tests/PicSeeTests/ImageNavigationVisibilityPolicyTests.swift`

**Interfaces:**
- Consumes: pointer x-coordinate, viewer width, neighbor availability, and initial-reveal state.
- Produces: `ImageNavigationVisibility(previous: Bool, next: Bool)` through `ImageNavigationVisibilityPolicy.visibility(pointerX:viewerWidth:hasPrevious:hasNext:revealsAvailableDirections:)`.

- [x] **Step 1: Write failing tests** for left, middle, right, boundary, unavailable-neighbor, outside-pointer, invalid-width, and initial-reveal behavior.
- [x] **Step 2: Verify the tests fail** with `swift test --filter ImageNavigationVisibilityPolicyTests`; expected failure is that the policy types are missing.
- [x] **Step 3: Implement the minimal pure policy** with `edgeFraction = 0.20`, inclusive outer boundaries, and availability filtering.
- [x] **Step 4: Verify the policy tests pass** with `swift test --filter ImageNavigationVisibilityPolicyTests`; expected result is zero failures.

### Task 2: Viewer Overlay Integration

**Files:**
- Modify: `Sources/PicSee/Viewer/ImageViewerView.swift`

**Interfaces:**
- Consumes: `viewModel.previousURL`, `viewModel.nextURL`, `viewModel.navigateToPrevious()`, `viewModel.navigateToNext()`, and the Task 1 policy.
- Produces: a pointer-tracked overlay with accessible previous and next buttons.

- [x] **Step 1: Add hover and discovery state** to `ImageViewerView` and update the pointer x-coordinate with `onContinuousHover`.
- [x] **Step 2: Add the navigation overlay** using `GeometryReader`, availability-filtered buttons, 44-point hit targets, 40-point circles, 14-point edge padding, and vertical centering.
- [x] **Step 3: Add the discovery timer** that reveals available directions for 1.2 seconds once per viewer, then animates to the current hover state over 0.18 seconds.
- [x] **Step 4: Verify focused tests and compilation** with `swift test --filter ImageNavigationVisibilityPolicyTests` and `swift build`; expected result is zero failures and successful build.

### Task 3: Regression Verification

**Files:**
- Review: all files changed by Tasks 1 and 2.

**Interfaces:**
- Consumes: completed feature.
- Produces: verification evidence and a clean, scoped diff.

- [x] **Step 1: Run the complete suite** with `swift test`; expected result is zero failures.
- [x] **Step 2: Run a fresh build** with `swift build`; expected result is exit code 0.
- [x] **Step 3: Inspect `git diff --check` and `git diff`** to confirm no whitespace errors, unrelated edits, placeholders, or requirement gaps.
