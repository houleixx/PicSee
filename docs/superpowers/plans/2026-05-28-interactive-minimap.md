# Interactive Minimap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive bottom-right minimap when a zoomed image cannot fit in the viewer.

**Architecture:** Keep minimap geometry in `ImageDisplayGeometry` for testability. Add an AppKit `MinimapView` inside `CanvasNSView` that draws the thumbnail, draws the viewport rectangle, and converts clicks/drags into existing `panOffset` updates.

**Tech Stack:** Swift, AppKit, SwiftUI wrapper, XCTest.

---

### Task 1: Geometry

**Files:**
- Modify: `Sources/PicSee/Viewer/ImageDisplayGeometry.swift`
- Test: `Tests/PicSeeTests/ImageDisplayGeometryTests.swift`

- [x] Add tests for minimap visibility, aspect-fit size, visible image rect mapping, and minimap click-to-pan conversion.
- [x] Run the geometry test file and confirm the new tests fail because minimap APIs do not exist.
- [x] Implement `MinimapGeometry` and helper methods on `ImageDisplayGeometry`.
- [x] Run the geometry test file and confirm it passes.

### Task 2: AppKit Minimap View

**Files:**
- Modify: `Sources/PicSee/Viewer/ImageCanvasView.swift`

- [x] Add a private `MinimapView` subclass that draws the thumbnail and viewport rectangle.
- [x] Add the minimap as a subview of `CanvasNSView`.
- [x] Update layout to position the minimap bottom-right only when geometry says it is needed.
- [x] Handle mouse down and drag in the minimap by converting the event location into a constrained `panOffset`.

### Task 3: Verification

**Files:**
- Verify: Swift test suite

- [x] Run `swift test`.
- [x] If tests fail, fix the failing behavior and rerun.
