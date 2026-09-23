# Default image format settings

## Findings

The screenshot shows the first 15 formats selected, with DDS and the three
following formats unset. The old batch loop stopped on its first thrown error.

A read-only system query confirmed that `.dds` resolves to `com.microsoft.dds`;
the configured `com.microsoft.directdraw-surface` is not a registered UTType.
The exact Launch Services status from the user's macOS 27 installation was not
captured, so its error code is not assumed.

The app's `LSItemContentTypes` list also omitted selectable formats AVIF, TGA,
DDS, OpenEXR, Radiance HDR, and JPEG XL, and used `public.ico` instead of the
settings list's `com.microsoft.ico`.

Constructing `NSAlert(error:)` with the existing description-only error puts the
details in `messageText` and leaves `informativeText` empty. Overwriting that
message with a generic title hid the format and error code, matching the screenshot.

## Changes

- Correct DDS's content type and align the bundled declarations with all selectable types.
- Skip formats already using PicSee; attempt every other selected format even if
  one fails, and report successes and failures separately.
- Refresh checkboxes from system state after applying.
- Explicitly place format names and error descriptions in the alert body.
- Record failing content types and status codes in the `DefaultImageApp` log category.

## Validation

The registration tests failed before the fix: the DDS identifier differed from
the system's value, it could not resolve to a UTType, and seven selectable types
were absent from the declaration list.

`swift test --filter DefaultImage` passed four XCTest tests and five Swift Testing
tests, including continuation after DDS fails, skipping existing defaults,
successful batches, and preserving error details in an actual NSAlert instance.
Tests use fake handlers and do not change this machine's default applications.

`PICSEE_SKIP_LOCAL_INSTALL=1 bash Scripts/build-app.sh` built the arm64/x86_64
test app with ad-hoc signing. The generated Info.plist contains all 19 selectable
content types; strict code signature verification and `git diff --check` passed.
The installed app and system default handlers were not changed.

The real batch operation still needs verification on the user's macOS 27 machine.
If the system rejects any remaining format, the corrected alert and log now expose
which format failed and its error code.
