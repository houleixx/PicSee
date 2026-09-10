#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:?Usage: bash Tests/verify-dmg.sh path/to/PicSee.dmg}"
WORK_DIR="$(mktemp -d)"
MOUNT_POINT="$WORK_DIR/volume"
MOUNTED=0

cleanup() {
  if [ "$MOUNTED" = 1 ]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null || return 1
  fi
  rmdir "$MOUNT_POINT" 2>/dev/null || true
  rmdir "$WORK_DIR"
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
MOUNTED=1
codesign --verify --deep --strict "$MOUNT_POINT/PicSee.app"
diff -qr "$SOURCE_ROOT/build/PicSee.app" "$MOUNT_POINT/PicSee.app"
test "$(readlink "$MOUNT_POINT/Applications")" = /Applications
test -s "$MOUNT_POINT/.background.tiff"

"$SOURCE_ROOT/build/dmg-tools/bin/python" - "$MOUNT_POINT" <<'PY'
import pathlib
import sys
from ds_store import DSStore

root = pathlib.Path(sys.argv[1])
assert {p.name for p in root.iterdir() if not p.name.startswith('.')} == {'PicSee.app', 'Applications'}
with DSStore.open(str(root / '.DS_Store'), 'r') as store:
    assert store['.']['icvp']['backgroundType'] == 2
    assert store['.']['icvp']['backgroundImageAlias']
    assert store['.']['icvl'] == (b'type', b'icnv')
    app = store['PicSee.app']['Iloc']
    destination = store['Applications']['Iloc']
    assert app[0] < destination[0] and app[1] == destination[1]
print('PASS: unchanged signed app, Applications link, background, and drag-to-install layout')
PY
