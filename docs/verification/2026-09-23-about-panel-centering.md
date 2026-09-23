# About panel centering

The About panel uses `NSApp.orderFrontStandardAboutPanel` in
`AppDelegate.showAboutPanel`. `AppMenu.aboutPanelCredits` applies a centered
paragraph style to both complete lines. Link styling changes only link and
underline attributes; it does not alter paragraph alignment or view frames.

`AboutPanelLayoutTests` invokes the real `AppDelegate.showAboutPanel`, finds the
actual credits `NSTextView`, forces layout, and converts both the text view and
each line's glyph bounds into window coordinates. It checks the geometry rather
than relying on a screenshot or the `.center` attribute alone.

Local AppKit measurement (logical points):

| Element | Left | Width | Horizontal center |
| --- | ---: | ---: | ---: |
| Window | 0 | 284 | 142 |
| Credits text view | 8 | 268 | 142 |
| Download address line | 42.5454 | 198.9092 | 142 |
| Thanks line | 44.4795 | 195.0409 | 142 |

Both lines and their container are centered relative to the entire window.
No production layout change is needed. Different line widths and glyph shapes
explain the unequal endpoints in the cropped screenshot. The test derives the
expected center from the actual window width, without hardcoding these measurements.
