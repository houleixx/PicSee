#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Tests requiring WindowServer, actual presentation layers, OCR hardware or
# pasteboard services are an explicit separate group, never silently skipped.
UI_TESTS='AppMenuTests|AuthorizationFocusRecoveryTests|ImageCanvasAnimationTests|ImageCanvasCursorZoomTests|ImageCanvasFileDragTests|ImageCanvasOCRTests|ScreenshotCaretLayoutTests|ScreenshotNavigationInteractionTests|ScreenshotShortcutTests|ScreenshotSizeFieldLayoutTests|SettingsMenuRoutingTests|SettingsWindowTests|SingleWindowTests|TransparencyBackgroundTests|ViewerTitleBarPreferenceTests|ViewerWindowTests|WindowActivationTests|WindowPinningTests|testSavedPNGUsesChosenDimensionsAndIncludesAnnotations|testScreenSamplingPreservesOffsetCropAndRotationAtNativeScale|testScreenSizeExportUsesLinearSamplingForFineStrokesAtElevenPercent|testGeneratedFinderScriptCompiles|reattachingViewerDuringFullScreenDoesNotStopPlayback|testPreferenceWrittenByAnotherProcessRefreshesOpenSettings|DefaultImageFormatRegistrationTests'
MODE="${1:-logic}"
if [ "$#" -gt 0 ]; then shift; fi
case "$MODE" in
  logic) swift test --skip "$UI_TESTS" "$@" ;;
  ui)
    swift test --disable-swift-testing --filter "$UI_TESTS" "$@"
    # Swift Testing serializes within each suite, but separate suites can still
    # race on process-wide activation/focus. Give desktop suites their own process.
    for group in DefaultImageFormatRegistrationTests AuthorizationFocusRecoveryTests ScreenshotShortcutTests TransparencyBackgroundTests SingleWindowTests WindowPinningTests ImageCanvasCursorZoomTests reattachingViewerDuringFullScreenDoesNotStopPlayback; do
      swift test --skip-build --disable-xctest --filter "$group" "$@"
    done
    ;;
  all) bash Scripts/test-swift.sh logic "$@"; bash Scripts/test-swift.sh ui "$@" ;;
  *) echo "Usage: bash Scripts/test-swift.sh [logic|ui|all] [SwiftPM options]" >&2; exit 2 ;;
esac
