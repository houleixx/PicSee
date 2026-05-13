# PicSee Design

Date: 2026-05-13

## Summary

PicSee is a lightweight native macOS image viewer. Its primary entry point is Finder: the user double-clicks an image file, PicSee opens that image in a focused viewing window, and closing the last image window quits the app.

The first version is not a gallery manager, import tool, editor, or photo library replacement. It should feel fast, direct, and disposable: open, inspect, zoom, move to nearby images, close.

## Goals

- Open image files from Finder by double-clicking or choosing PicSee as the app.
- Display the selected image centered in a native macOS window.
- Fit the whole image inside the window by default.
- Support mouse wheel zoom in and zoom out.
- Support drag-to-pan when the image is zoomed.
- Support previous and next image navigation within the same folder.
- Quit the application when the final viewer window closes.

## Non-Goals

- No gallery home screen in the first version.
- No image editing, annotation, cropping, or export.
- No persistent library database.
- No cloud sync, tagging, albums, or search.
- No custom file organization or import flow.

## Platform Choice

PicSee will be a native SwiftUI macOS app with targeted AppKit integration.

SwiftUI provides the top-level UI structure and state-driven rendering. AppKit is used where macOS desktop behavior needs finer control: file open events from Finder, window lifecycle, keyboard handling, and scroll-wheel zoom gestures.

## Core User Flow

1. The user double-clicks an image file in Finder.
2. macOS launches PicSee and passes the file URL to the app.
3. PicSee opens a viewer window for that image.
4. PicSee scans the image's parent folder for supported image files and sorts them by filename.
5. The selected image is shown centered and fit-to-window.
6. The user can zoom with the mouse wheel, pan by dragging, and navigate with left/right arrow keys.
7. When the user closes the window, PicSee exits if no other viewer windows remain.

## Supported Image Formats

The first version supports common macOS-readable image formats:

- `jpg`
- `jpeg`
- `png`
- `gif`
- `heic`
- `tif`
- `tiff`
- `bmp`
- `webp`

Image decoding is delegated to `NSImage` and ImageIO-backed platform support. If a file extension is supported but the image cannot be decoded, PicSee shows an error state in the viewer window.

## Application Structure

### PicSeeApp

The application entry point. Responsibilities:

- Configure the macOS app scene.
- Receive file URLs opened by Finder.
- Create or update viewer windows for opened files.
- Ensure closing the last window quits the application.

### ImageViewerWindow

The native viewer window. Responsibilities:

- Own the SwiftUI viewer content.
- Set the window title to the current image filename.
- Forward close events to app lifecycle handling.
- Provide a focused, minimal window with standard macOS controls.

### ImageViewerViewModel

The state model for a viewer. Responsibilities:

- Track the current image URL.
- Load the current image.
- Store the current folder image list and selected index.
- Track zoom scale and pan offset.
- Reset zoom and offset when switching images.
- Expose previous and next navigation commands.
- Expose error state when loading fails.

### ImageCanvasView

The image display surface. Responsibilities:

- Render the current image centered in the available window area.
- Compute fit-to-window scale.
- Apply user zoom on top of fit scale.
- Handle mouse wheel zoom.
- Keep zoom centered near the pointer when practical.
- Handle drag-to-pan for zoomed images.
- Support double-click to reset to fit-to-window.

### FolderImageNavigator

The folder scanner and navigator. Responsibilities:

- Given a file URL, scan its parent directory.
- Filter files to supported image extensions.
- Sort results by localized filename order.
- Find the current image index.
- Return previous and next image URLs when available.

## Interaction Details

### Initial Display

Every image opens in fit-to-window mode. The full image should be visible without cropping, even for very large images.

### Zoom

Mouse wheel scroll zooms the image:

- Scroll up zooms in.
- Scroll down zooms out.
- Zoom is clamped to a practical range, for example `0.1x` to `20x` relative to fit scale.
- Zooming below the fit scale returns to fit-to-window behavior.

### Pan

When zoomed beyond fit-to-window, dragging the image pans it. Panning is constrained enough that the image cannot be lost completely off screen.

### Navigation

Left and right arrow keys navigate among images in the same folder:

- Right arrow moves to the next image.
- Left arrow moves to the previous image.
- At the first or last image, navigation does nothing.
- Switching images resets zoom and pan to fit-to-window.

### Close Behavior

Closing the only viewer window quits PicSee. If multiple windows are supported later, closing one window should only quit once all viewer windows are closed.

## Error Handling

If PicSee cannot load the requested image:

- The viewer window remains open.
- The title still reflects the filename.
- The content area shows a concise error state.
- The user can close the window to exit.

If folder scanning fails because the directory is unavailable or unreadable, PicSee still opens the requested image if possible, but previous and next navigation are disabled.

## Testing Strategy

Automated tests should cover pure logic first:

- Supported image extension filtering.
- Folder image sorting.
- Current index detection.
- Previous and next navigation behavior.
- Boundary behavior at the first and last image.

Manual verification should cover desktop integration:

- Open an image file from Finder with PicSee.
- Open an image file by passing a file URL to the built app.
- Mouse wheel zooms in and out.
- Dragging pans a zoomed image.
- Double-click resets zoom.
- Left/right arrows switch images in the same folder.
- Closing the only window quits the app.

## Open Decisions

No blocking open decisions remain for the first implementation plan.

