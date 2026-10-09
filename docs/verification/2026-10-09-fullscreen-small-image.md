# Full-screen small-image display verification

## Behavior

- Settings → Display → Image browsing offers Original size (100%), Always fit screen, and Smart enlargement.
- Default mode is Original size. Smart enlargement defaults to 2×, with 1.5×, 2×, 3×, and 4× limits.
- Preferences affect automatic full-screen fitting only. Large images remain fully visible, preserving aspect ratio; normal-window fitting is unchanged.
- Scaling uses source pixels and the window backing scale, independent of image DPI.
- Automatic enlargement remains the default zoom baseline. Double-click exits full screen from that baseline; after manual zoom or pan, the first double-click restores the baseline and the next exits.
- Manual zoom can exceed the automatic enlargement limit. The actual-size action also works for very small images with large automatic fit factors.

## Validation

- `bash Scripts/test-swift.sh all` passed. Log: `build/verification/fullscreen-small-image-all-tests-final.log`.
- Ten native canvas tests cover DPI, 1×/2× backing scales, all modes and limits, full-screen entry/exit, double-click reset, preference persistence, and actual-size zoom for tiny images.
- Bilingual localization coverage and `git diff --check` passed.
- Installed UI tested with a 400×300 PNG carrying 350 DPI metadata on a 3840×2160 Retina display (1920×1080 logical points, 2× backing scale): normal window 100%; full-screen Smart 2× = 200%; Always fit = 720%; Original = 100%.
- Confirmed the conditional maximum-scale control and all four choices. Restored Original size before handing off for user testing.

## Local installation

- Installed local test version 0.2.74 (build 74) at `/Applications/PicSee.app`.
- Universal arm64/x86_64 binary signed with `Developer ID Application: Baixing Co. ,Ltd. (3989F32QL4)`, hardened runtime and secure timestamp.
- Strict signature verification and installed/build binary comparison passed.
- Previous installed app preserved at `/private/tmp/picsee-small-image-install.yXoePm/PicSee.previous.app`.
- This local test build has not been notarized or published as a release.
