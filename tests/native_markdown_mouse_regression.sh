#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-native-mouse.XXXXXX)"
readonly TEST_DIR="$TEST_TMP_DIR/tests"
readonly OUTPUT_PATH="$TEST_TMP_DIR/qmltest.log"

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ ! -f "$OUTPUT_PATH" ]] || sed -n '1,260p' "$OUTPUT_PATH" >&2
  exit 1
}

for command in timeout mktemp mkdir cp rg node; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done
[[ -x /usr/lib/qt6/bin/qmltestrunner ]] || fail "qmltestrunner is missing"

mkdir -m 700 -p -- "$TEST_DIR/markdown" "$TEST_DIR/syntax" \
  "$TEST_TMP_DIR/runtime" "$TEST_TMP_DIR/cache" "$TEST_TMP_DIR/home" \
  "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/data" "$TEST_TMP_DIR/config"
cp -- "$ROOT_DIR/tests/isolated/tst_native_markdown_mouse.qml" "$TEST_DIR/"
cp -- "$ROOT_DIR/tests/isolated/tst_native_link_contract.qml" "$TEST_DIR/"
cp -- "$ROOT_DIR/NativeMarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/SyntaxHighlight.js" \
  "$TEST_DIR/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$TEST_DIR/markdown/MarkdownParserWorker.js"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" \
  "$TEST_DIR/syntax/HighlightWorker.js"
cp -- "$ROOT_DIR/tests/fixtures/markdown-image.svg" \
  "$TEST_DIR/markdown-image.svg"

set +e
env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    HOME="$TEST_TMP_DIR/home" XDG_CONFIG_HOME="$TEST_TMP_DIR/config" \
    XDG_STATE_HOME="$TEST_TMP_DIR/state" XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$TEST_TMP_DIR/runtime" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
    timeout --kill-after=1s 30s /usr/lib/qt6/bin/qmltestrunner \
      -input "$TEST_DIR" -import "$TEST_DIR" \
      >"$OUTPUT_PATH" 2>&1
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  fail "rendered mouse regression failed (qmltestrunner status $status)"
fi
if rg -q 'FAIL!|QFATAL|ReferenceError:|TypeError:|SyntaxError:|Binding loop' \
    "$OUTPUT_PATH"; then
  fail "rendered mouse regression reported a failure or runtime error"
fi
rg -q 'Totals: .* passed, 0 failed' "$OUTPUT_PATH" || \
  fail "rendered mouse regression did not report a clean summary"

node "$ROOT_DIR/tests/check_qt_contracts.cjs" "$OUTPUT_PATH" \
  "$ROOT_DIR/tests/qt_contracts.json" || fail "required pointer coverage is incomplete"

printf '%s\n' \
  'PASS: scratchpad-shaped tes/test fence keeps label and code clicks distinct' \
  'PASS: a code language remains drag-selectable after immediate styled rendering' \
  'PASS: an unlabeled fence exposes a clickable language placeholder' \
  'PASS: a hovered link keeps an in-app target marker during Ctrl+click' \
  'PASS: blank space around links shows no marker and cannot activate a target' \
  'PASS: links activate once only for a stationary Ctrl+click' \
  'PASS: Ctrl-dragging away from a link does not activate its target' \
  'PASS: a rendered task checkbox uses its enlarged pointer target' \
  'PASS: left-button selection does not drag-scroll the editor viewport' \
  'PASS: standalone images expose and drag a four-corner resize frame'
