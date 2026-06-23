#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/project/Scripts" "$WORK_DIR/bin"
cp "$SOURCE_ROOT/Scripts/build-dmg.sh" "$WORK_DIR/project/Scripts/build-dmg.sh"
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

cat > "$WORK_DIR/bin/hdiutil" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

output="${@: -1}"
mkdir -p "$(dirname "$output")"
printf 'fake dmg\n' > "$output"
SCRIPT
chmod +x "$WORK_DIR/bin/hdiutil"

(
  cd "$WORK_DIR/project"
  PATH="$WORK_DIR/bin:$PATH" \
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
