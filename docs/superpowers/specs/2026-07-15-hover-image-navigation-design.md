# Hover Image Navigation Design

## Goal

Add mouse-accessible previous and next controls without turning PicSee's image canvas into a permanently visible toolbar.

## Interaction

- Navigation controls are hidden by default after the initial discovery hint.
- When the pointer enters the leftmost 20% of the viewer, show only the previous-image control.
- When the pointer enters the rightmost 20% of the viewer, show only the next-image control.
- Keep both controls hidden while the pointer is in the middle 60% or outside the viewer.
- When a viewer first opens with neighboring images, briefly show every available direction for 1.2 seconds, then return to pointer-driven visibility.
- Hide a direction entirely when no image exists in that direction.
- Keep a visible control interactive while the pointer moves onto it.
- Fade controls in and out over 0.18 seconds.

## Visual Design

Each control is a 40-point circular dark translucent button with a white chevron, a subtle white border, and the same shadow language as PicSee's existing HUD controls. Its hit target is at least 44 by 44 points. Controls sit 14 points from the corresponding window edge and remain vertically centered.

## Integration Constraints

- Reuse `ImageViewerViewModel.navigateToPrevious()` and `navigateToNext()`.
- Derive direction availability from `previousURL` and `nextURL`.
- The controls must remain SwiftUI overlays so their clicks do not reach `CanvasNSView` and trigger OCR selection, image panning, window dragging, or double-click reset.
- Keep the edge-zone calculation in a small pure policy type so boundary behavior is unit-testable without AppKit event synthesis.
- Preserve keyboard navigation and every existing canvas gesture unchanged.

## Testing

Unit tests cover the left, middle, and right zones; exact 20% boundaries; initial reveal; missing neighbors; invalid widths; and pointers outside the viewer. The full Swift test suite and debug build verify integration.
