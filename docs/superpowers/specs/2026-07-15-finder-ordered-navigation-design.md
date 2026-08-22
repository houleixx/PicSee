# Finder-Ordered Image Navigation Design

## Goal

PicSee should navigate sibling images in the order currently displayed by the Finder window for that folder. If the current image is third in Finder, Next opens the fourth image and Previous opens the second.

## Finder Order Snapshot

When the viewer first opens, PicSee uses macOS Accessibility APIs to locate a Finder window whose target is the image's parent folder. It reads candidate item orders from Finder's navigation-order, children, and contents accessibility branches. Exact document URL matches are preferred; if Finder does not expose document URLs, all same-title window candidates are checked.

Each candidate is filtered to supported image extensions, standardized, and deduplicated. PicSee accepts a candidate only when it contains every supported regular image currently in the directory exactly once. A partial accessibility result is never used because that could make images disappear from navigation. Candidate traversal has messaging, elapsed-time, and node-count limits so an unresponsive Finder cannot block image opening indefinitely.

The accepted list is a session snapshot: Finder window closure, Finder sort changes, and newly added files do not reorder the active viewer. If no complete candidate is available, PicSee falls back to localized natural filename order.

## Deleted Files

The snapshot order is stable, but its membership is pruned lazily:

- Previous and next lookup scan outward from the current index.
- A missing candidate is removed from the in-memory snapshot and scanning continues in the same direction.
- Buttons reflect the nearest surviving candidate. When no candidate survives, that direction is hidden.
- If the currently displayed file is deleted, its already-loaded pixels remain visible. After navigating away, it cannot be revisited.
- Renames are treated as deletion of the old URL plus an unobserved new file. New and renamed files appear only in a new viewer session.
- If a candidate disappears between lookup and decode, navigation removes it and continues to the next surviving candidate. Existing but undecodable files keep the existing error behavior rather than being silently skipped.

## Permissions and Fallback

Reading Finder's displayed order requires Accessibility permission. PicSee requests the system prompt at most once, provides a shortcut to the Accessibility privacy pane in settings, and shows whether access is enabled. The app does not request Apple Events automation permission.

Finder access is best-effort. If the user denies access, no matching Finder window exists, traversal reaches its budget, or every returned order is incomplete, PicSee falls back to its existing localized natural filename order. Image viewing must never wait on a permission retry loop or fail solely because Finder ordering is unavailable.

## Components

- `FinderFolderOrderProvider` reads Finder's accessibility tree and returns a complete ordered URL snapshot or `nil`.
- `FolderImageNavigator` accepts a preferred ordered URL list, filters it, finds the current index, and mutably prunes missing neighbors.
- `ImageViewerViewModel` asks for Finder order only for the first image in a viewer session, retains one navigator across navigation, and retries past files deleted during navigation.
- `AccessibilityPermissionSettings` owns the one-time prompt preference, status text, and System Settings shortcut.

## Testing

Unit tests cover preferred Finder order, fallback order, current index, duplicate and unsupported entries, complete-candidate selection, permission prompt state, deleted previous/next candidates, deletion of the current file, and deleted-file races during navigation. The full Swift test suite and app build remain required; live Finder accessibility behavior remains an integration check.
