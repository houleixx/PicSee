# GitHub Update Check Design

## Goal

PicSee checks GitHub Releases for newer versions, shows a compact update prompt in the lower-left corner of the image viewer, downloads the matching DMG when requested, and remembers ignored versions so the same release is not shown again.

## Release Source

The app requests the latest release metadata from:

`https://api.github.com/repos/houleixx/PicSee/releases/latest`

The release tag uses the existing convention `v0.2.11`. The DMG download URL is built from the release version:

`https://github.com/houleixx/PicSee/releases/download/v0.2.11/PicSee-0.2.11.dmg`

The app can still use the API response for discovery, but the downloadable asset must match this release URL pattern.

## Version Comparison

PicSee compares versions by normalizing an optional leading `v`, splitting on `.`, parsing numeric components, and comparing each component from left to right. Missing components are treated as zero.

Examples:

- `0.2.12` is newer than `0.2.11`
- `0.3.0` is newer than `0.2.99`
- `1.0` is equal to `1.0.0`
- `0.10.0` is newer than `0.9.9`

This supports cross-version updates because the app does not require the latest release to be exactly one patch version ahead.

## User Experience

After a viewer window opens, PicSee starts the update check asynchronously. If a newer version exists and it has not been ignored, the image viewer shows a small lower-left prompt with:

- The latest version number
- An update button
- An ignore button

Clicking update downloads the DMG to the user's caches directory and opens it with the system. Clicking ignore saves the latest version string in `UserDefaults`.

## Error Handling

Update checks are best-effort. Network errors, invalid JSON, invalid versions, or download failures should not block image viewing. Failed checks simply do not show the prompt; failed downloads keep the prompt visible so the user can retry.

## Tests

Unit tests cover:

- Numeric version comparison, including cross-version examples
- GitHub release decoding and DMG URL construction
- Ignoring a specific latest version
- Showing no prompt for same, older, or ignored versions
