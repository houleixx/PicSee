#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/project/Scripts" "$WORK_DIR/bin"
cp "$SOURCE_ROOT/Scripts/build-dmg.sh" "$WORK_DIR/project/Scripts/build-dmg.sh"
cp "$SOURCE_ROOT/Scripts/dmg-settings.py" "$WORK_DIR/project/Scripts/dmg-settings.py"
mkdir -p "$WORK_DIR/project/build/pkg-root/PicSee.app"

cat > "$WORK_DIR/project/Scripts/build-app.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/PicSee.app/Contents"
printf '%s\n' "${PICSEE_VERSION:-}" > "$ROOT_DIR/build/build-app-version.txt"
printf '%s\n' "${PICSEE_BUILD_NUMBER:-}" > "$ROOT_DIR/build/build-app-build-number.txt"
printf '%s\n' "${PICSEE_SKIP_LOCAL_INSTALL:-}" > "$ROOT_DIR/build/build-app-skip-local-install.txt"
SCRIPT
chmod +x "$WORK_DIR/project/Scripts/build-app.sh"

cat > "$WORK_DIR/bin/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${@: -1}"
touch "${@: -1}/background.png" "${@: -1}/background@2x.png"
SCRIPT
chmod +x "$WORK_DIR/bin/swift"

cat > "$WORK_DIR/bin/dmgbuild" <<'SCRIPT'
#!/usr/bin/env python3
import pathlib
import runpy
import sys

args = sys.argv[1:]
defines = dict(args[i + 1].split("=", 1) for i, arg in enumerate(args) if arg == "-D")
settings = runpy.run_path(args[args.index("-s") + 1], init_globals={"defines": defines})
assert pathlib.Path(settings["files"][0], "Contents").is_dir()
assert pathlib.Path(settings["background"]).is_file()
assert settings["symlinks"] == {"Applications": "/Applications"}
assert args[-2] == "PicSee"
pathlib.Path(args[-1]).write_text("fake dmg\n")
SCRIPT
chmod +x "$WORK_DIR/bin/dmgbuild"

(
  cd "$WORK_DIR/project"
  PATH="$WORK_DIR/bin:$PATH" \
    PICSEE_DMGBUILD="$WORK_DIR/bin/dmgbuild" \
    PICSEE_VERSION=9.8.7 \
    PICSEE_BUILD_NUMBER=42 \
    Scripts/build-dmg.sh
)

test "$(cat "$WORK_DIR/project/build/build-app-version.txt")" = "9.8.7"
test "$(cat "$WORK_DIR/project/build/build-app-build-number.txt")" = "42"
test "$(cat "$WORK_DIR/project/build/build-app-skip-local-install.txt")" = "1"
test -f "$WORK_DIR/project/build/dmg/PicSee-9.8.7.dmg"
test ! -e "$WORK_DIR/project/build/dmg-stage"
test ! -e "$WORK_DIR/project/build/pkg-root"
