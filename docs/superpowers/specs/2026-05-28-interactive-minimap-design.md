# Interactive Minimap Design

## Goal

When a zoomed image cannot be fully displayed, PicSee shows a small thumbnail in the bottom-right corner. The thumbnail includes a viewport rectangle and supports clicking or dragging to navigate the enlarged image.

## Behavior

- Show the minimap only when the displayed image is larger than the viewport in at least one axis.
- Hide the minimap when the image fully fits in the viewport.
- Draw the complete image inside the minimap, preserving aspect ratio.
- Draw a semi-transparent white viewport rectangle showing the portion of the image currently visible in the main canvas.
- Clicking or dragging inside the minimap recenters the main image around the clicked image point.
- Reuse the existing pan constraints so minimap navigation cannot move beyond valid pan bounds.

## Architecture

The core mapping math lives in `ImageDisplayGeometry` so it can be unit-tested without AppKit event setup. `CanvasNSView` owns a lightweight minimap `NSView`, lays it out in the bottom-right corner, updates it whenever image geometry changes, and forwards minimap gestures back into the existing `panOffset` state.

## Testing

Unit tests cover visibility, minimap aspect fitting, visible-rect mapping, and click-to-pan conversion. Existing Swift tests remain the regression suite for zoom and pan behavior.
