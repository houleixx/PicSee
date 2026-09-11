# Screenshot editor controls

The width/height digits moved upward by 1 pt when the plain SwiftUI TextField
entered editing: its static native text frame was 18 pt high, while the AppKit
field editor was 19 pt high and started at y = -1. Font and outer field bounds
did not change. The regression reproduced this for both 516 and 252.

ScreenshotDimensionInput now uses a native NSTextField with a consistent
monospaced-digit font and vertical frame in both states. Focus callbacks run on
actual focus, rather than waiting for the first text edit. Binding updates avoid
rewriting unchanged strings, preserving the insertion point during typing.

The lower settings row now uses consistent label typography, 24 pt control
heights, wider preset targets with 6 pt corners, and explicit spacing within and
between color, stroke-width and font-size groups. The normal-width toolbar keeps
its two-row layout; narrow windows retain the existing stacked fallback.

Validation:

- `swift test --filter 'ScreenshotSizeFieldLayoutTests|ScreenshotDocumentTests|ScreenshotExportSizeTests'`: 45 tests passed.
- The new regression compares rendered digit bounds before focus, during focus
  and after blur, including anti-aliased edges rather than only opaque pixels.
- Continuous input produces 420 without moving the insertion point; Return
  commits it and a single undo restores 516.
- Native render checks covered crop, arrow, text and mosaic settings, dark/light
  appearance and narrow windows.
- Temporary preview images and test logs were removed after verification during workspace cleanup.

The focus/blur rendering regression protects against future divergence between
the static label and native editing geometry.
