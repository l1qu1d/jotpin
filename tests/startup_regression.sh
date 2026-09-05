#!/usr/bin/env bash
set -euo pipefail
readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-startup.XXXXXX)"
trap 'rm -rf -- "$TEST_TMP_DIR"' EXIT
for command in quickshell timeout rg; do command -v "$command" >/dev/null; done
mkdir -p "$TEST_TMP_DIR"/{config/jotpin,home,state,cache,data,runtime}
chmod 700 "$TEST_TMP_DIR/runtime"
ln -s /usr/share/omarchy/shell/Commons "$TEST_TMP_DIR/config/Commons"
ln -s /usr/share/omarchy/shell/Ui "$TEST_TMP_DIR/config/Ui"
cp "$ROOT_DIR/"{JotPin.qml,JotPinButton.qml,HostIntegration.qml,NativeMarkdownDisplay.qml,EditorModel.js,HtmlEntities.js,SpellcheckModel.js,SyntaxHighlight.js} "$TEST_TMP_DIR/config/jotpin/"
cp -r "$ROOT_DIR/markdown" "$ROOT_DIR/spellcheck" "$ROOT_DIR/syntax" "$TEST_TMP_DIR/config/jotpin/"
cp "$ROOT_DIR/tests/isolated/startup.qml" "$TEST_TMP_DIR/config/shell.qml"
cat > "$TEST_TMP_DIR/image.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="160" height="80"><rect width="160" height="80" fill="#3080c0"/></svg>
SVG
cat > "$TEST_TMP_DIR/note.md" <<'MD'
# Cold startup

![Local image](image.svg)

```javascript
const answer = 42;
console.log(answer);
```
MD
printf '# Plain note\n\nReady to edit.\n' > "$TEST_TMP_DIR/plain.md"
for mode in normal recovery plain; do
  note_path="$TEST_TMP_DIR/note.md"
  if [[ "$mode" == plain ]]; then note_path="$TEST_TMP_DIR/plain.md"; fi
if ! env -u DISPLAY -u WAYLAND_DISPLAY -u QT_QPA_PLATFORMTHEME \
  HOME="$TEST_TMP_DIR/home" XDG_CONFIG_HOME="$TEST_TMP_DIR/config" \
  XDG_STATE_HOME="$TEST_TMP_DIR/state" XDG_CACHE_HOME="$TEST_TMP_DIR/cache" \
  XDG_DATA_HOME="$TEST_TMP_DIR/data" XDG_RUNTIME_DIR="$TEST_TMP_DIR/runtime" \
  JOTPIN_STARTUP_MODE="$mode" QT_QPA_PLATFORM=offscreen JOTPIN_TEST_NOTE="$note_path" \
  timeout --kill-after=1s 8s quickshell --no-duplicate --path "$TEST_TMP_DIR/config/shell.qml" > "$TEST_TMP_DIR/output.log" 2>&1; then
  cat "$TEST_TMP_DIR/output.log" >&2
  exit 1
fi
if rg -q 'STARTUP_FAIL:|TypeError:|ReferenceError:|Binding loop detected|QQmlApplicationEngine' "$TEST_TMP_DIR/output.log" || ! rg -q 'STARTUP_RESULT: passed' "$TEST_TMP_DIR/output.log"; then
  cat "$TEST_TMP_DIR/output.log" >&2
  exit 1
fi
rg 'STARTUP_(PASS|RESULT):' "$TEST_TMP_DIR/output.log"
done
