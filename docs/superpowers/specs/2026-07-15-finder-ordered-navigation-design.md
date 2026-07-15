# Finder-Ordered Image Navigation Design

## Goal

PicSee should navigate sibling images in the order currently displayed by the Finder window for that folder. If the current image is third in Finder, Next opens the fourth image and Previous opens the second.

## Finder Order Snapshot

When the viewer first opens, PicSee asks Finder for the frontmost open Finder window whose target is the image's parent folder. It reads that window's current view and ordering:

- List view: active sort column and normal or reversed direction.
- Icon view: arrangement property. For `not arranged` and `snap to grid`, order items by icon position from top to bottom and then left to right.
- Column view: name order, because Finder column view does not expose a separate sort choice.
- Gallery/group view or an unsupported Finder response: fall back to PicSee's localized natural filename order.

Finder supplies the sorted item URLs. PicSee filters that ordered list to supported image extensions, standardizes the URLs, removes duplicates, and records the current image index. The resulting list is a session snapshot: Finder window closure, Finder sort changes, and newly added files do not reorder the active viewer.

## Deleted Files

The snapshot order is stable, but its membership is pruned lazily:

- Previous and next lookup scan outward from the current index.
- A missing candidate is removed from the in-memory snapshot and scanning continues in the same direction.
- Buttons reflect the nearest surviving candidate. When no candidate survives, that direction is hidden.
- If the currently displayed file is deleted, its already-loaded pixels remain visible. After navigating away, it cannot be revisited.
- Renames are treated as deletion of the old URL plus an unobserved new file. New and renamed files appear only in a new viewer session.
- If a candidate disappears between lookup and decode, navigation removes it and continues to the next surviving candidate. Existing but undecodable files keep the existing error behavior rather than being silently skipped.

## Permissions and Fallback

Reading Finder state uses Apple Events. The app bundle declares `NSAppleEventsUsageDescription` and the hardened-runtime entitlement `com.apple.security.automation.apple-events`.

Finder access is best-effort. If the user denies access, no matching Finder window exists, the script fails, or the returned order omits the current image, PicSee falls back to its existing localized natural filename order. Image viewing must never wait on a permission retry loop or fail solely because Finder ordering is unavailable.

## Components

- `FinderFolderOrderProvider` owns the read-only Finder AppleScript and returns an ordered URL snapshot or `nil`.
- `FolderImageNavigator` accepts a preferred ordered URL list, filters it, finds the current index, and mutably prunes missing neighbors.
- `ImageViewerViewModel` asks for Finder order only for the first image in a viewer session, retains one navigator across navigation, and retries past files deleted during navigation.
- `Scripts/build-app.sh` embeds the usage description and signs with the Apple Events entitlement.

## Testing

Unit tests cover preferred Finder order, fallback order, current index, duplicate and unsupported entries, deleted previous/next candidates, deletion of the current file, and deleted-file races during navigation. Script-source tests cover every Finder view/sort mode without requiring live Finder automation. Build-script tests cover the usage description and entitlement. The full Swift test suite and app build remain required.
