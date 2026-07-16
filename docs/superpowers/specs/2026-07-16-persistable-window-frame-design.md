# Safe Window Frame Persistence Design

## Problem

PR #5 attempts to prevent native full-screen dimensions from replacing the saved normal or fixed window frame. It was based on code from before PR #4 and references the removed `preFullScreenFrame`, so the merged `master` no longer compiles. Checking only `.fullScreen` also leaves a transition window where AppKit may resize the window before or after that style bit changes.

## Goal

Preserve the last valid normal-window frame across native full-screen transitions and closing the viewer, including when the window closes while full screen is active. Restore compilation without reintroducing the old duplicated full-screen state.

## Design

`ViewerWindow` remains the owner of `NativeFullScreenSnapshot`. It exposes a read-only `persistableFrame` value with one rule:

1. If a native full-screen snapshot exists, return the snapshot frame.
2. If no snapshot exists and the window is currently full screen, return `nil`.
3. Otherwise, return the current window frame.

The snapshot takes priority over `.fullScreen` so resize notifications during entry and exit transitions cannot persist a transient full-screen frame.

`WindowManager` adds one private persistence helper. Both `onFrameChanged` and `onClose` call this helper, eliminating duplicated save logic. The helper does nothing when `persistableFrame` is `nil`; otherwise it updates the normal saved frame and, when fixed-window mode is enabled, the fixed frame.

## State Flow

- Normal window resize or close: persist the current frame.
- Native full-screen entry or transition: persist the captured pre-full-screen frame.
- Native full-screen close: persist the captured pre-full-screen frame.
- Full-screen state without a valid snapshot: persist nothing.
- Successful or failed full-screen completion: existing snapshot cleanup remains responsible for returning persistence to the normal current frame.

## Testing

Add focused `ViewerWindowTests` that prove:

- A normal window exposes its current frame for persistence.
- Preparing native full screen keeps exposing the original frame after AppKit-style frame changes.
- A full-screen window without a snapshot exposes no persistable frame.
- Failed entry restores the original frame and clears the snapshot-backed persistence state.
- Successful exit restores the original frame and clears the snapshot-backed persistence state.

Then run the focused tests, the full Swift test suite, and a release build.

## Scope

This change only repairs native full-screen frame persistence and the PR #5 compilation failure. It does not change temporary desktop-fill behavior, window placement policy, Finder ordering, or release configuration.
