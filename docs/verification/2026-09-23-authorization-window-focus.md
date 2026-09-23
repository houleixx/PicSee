# Restore the viewer after interactive Finder authorization

## Report and implementation gap

The user reports that clicking Allow dismisses the system authorization dialog
and leaves the viewer behind another application's window. It was reported on
macOS 27 and subsequently another macOS version. The native transition has not
been reproduced on the development machine.

The launch code brought the viewer forward only while opening it. The asynchronous
Finder authorization returned permission without informing the window manager
that the interactive dialog had finished. A callback-driven regression test
reproduced that missing handoff: both Allow and Don't Allow completed without
requesting any viewer activation.

## Change

- First check authorization without prompting. Existing permission decisions and
  unavailable Finder results do not initiate any focus recovery.
- Only `errAEEventWouldRequireUserConsent` starts the interactive request. Record
  a weak reference to the currently visible viewer before requesting consent.
- After an Allow or Don't Allow response, restore that viewer on the main actor.
  Clear the pending reference so a completed dialog cannot repeatedly raise it.
- Skip restoration for cancellation, a closed/hidden or minimized viewer, an
  inactive Space, or a hidden application. Check eligibility again before the
  existing next-main-loop activation retry.
- Keep permission waits on the dispatch worker and Finder queries bounded by
  their existing timeout. No window-level changes or persistent always-on-top mode.
- Log authorization checks under `FinderOrder` and focus handoffs under
  `AuthorizationFocus`; no image paths or filenames are logged.

## Automated validation

`swift test --filter 'AuthorizationFocusRecoveryTests|FinderAuthorizationTests|FinderFolderOrderProviderTests|WindowActivationTests|ImageViewerViewModelTests'`

The new regression first failed because the interactive completion did not call
the focus handler. With the handoff connected, it passes for Allow and Don't
Allow, verifies that pre-decided permissions do not change focus, and covers
closed/minimized/off-Space viewers and cancellation while waiting for consent.
Existing consent timeout, directory ordering, and viewer tests also pass.

Tests inject system authorization responses and window availability. They verify
the application's recovery request, not the OS's final stacking order.

## Manual validation on the affected system

1. Quit PicSee. Reset only its automation decision with
   `tccutil reset AppleEvents local.picsee.viewer`.
2. Open an image in front of another application window. Wait several seconds in
   the authorization prompt, then click Allow. The viewer should regain the front.
3. Reopen another image with permission already granted; ordinary permission
   checks must not trigger an additional focus recovery.
4. Repeat from an undecided permission with Don't Allow. Filename navigation and
   the visible viewer should remain usable.

The user tested the locally installed Developer ID-signed build
`0.2.57 (2026092302)` and confirmed that the window now behaves normally after
authorization. The confirmation did not separately identify every OS version
tested, so it is not a claim of verification across all reported systems.
