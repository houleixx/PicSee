# Finder authorization prompt timeout

## Observed failure

On macOS 27, opening an image displays the Finder automation consent prompt,
then dismisses it before the user can respond. The image viewer remains open.
The supplied `PicSee-permission.log` records request `442.14`:

- `16:30:59.029`: `TCCAccessRequestIndirect`, service `kTCCServiceAppleEvents`,
  subject `local.picsee.viewer`, Finder PID 442, `timeout=1`.
- `16:31:00.032`: PicSee resolves the `AppleEvent timed out.` error message.
- `16:31:00.125`: TCC reports `AccessRequestIndirect: prompt timed out after 1 seconds`.
- `16:31:00.128`: the same request returns `timeout=true`, `result=false`.

The sorting script's `with timeout of 1 second` also constrained the consent
prompt on this system. Filtering only `AUTHREQ_` missed the indirect request.

## Change

Before running the sorting script, call `AEDeterminePermissionToAutomateTarget`
for Finder with `askUserIfNeeded=true`. Use a dispatch worker and an async
continuation because this synchronous API can wait arbitrarily long for the user;
it must not block the main thread or Swift's cooperative executor.

Run the sorting script only after authorization succeeds. Its one-second timeout
still bounds Finder event replies. Denial, missing Finder, or another permission
error preserves the existing filename fallback. Cancellation is checked before
authorization and after it returns. Permission status and script error codes are
logged under subsystem `local.picsee.viewer`, category `FinderOrder`, without
image paths or filenames.

## Validation

- The permission-denied regression test failed before connecting the permission
  gate: the script and directory reader both ran without permission.
- `swift test --filter 'FinderAuthorizationTests|FinderFolderOrderProviderTests|ImageViewerViewModelTests'`:
  31 XCTest tests and 3 Swift Testing tests passed. Covers denied access, consent
  pending longer than one second, cancellation while pending, existing sorting,
  immediate filename fallback, and late results after navigation.
- Tests inject the consent response and do not modify this Mac's permissions.
- `swift build -c release` passed; `git diff --check` passed.
- Native consent UI behavior still requires verification on macOS 27; the local
  development machine runs macOS 15.8.

## macOS 27 verification

With a properly signed build and an undecided Finder automation permission,
open an image, wait at least five seconds, and confirm the prompt remains until
answered. Allow it and verify Finder sorting; separately verify denial keeps
filename navigation working. While consent is pending, the viewer should remain
responsive. If the previous timeout left access disabled, enable Finder under
System Settings > Privacy & Security > Automation > PicSee, then reopen the image.
This also provides a workaround for the currently installed version.

The prevention rule is to resolve interactive consent separately from short
timeouts intended to bound background data queries.
