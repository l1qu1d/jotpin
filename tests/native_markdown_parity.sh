#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-native-markdown-parity.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly RUNTIME_DIR="$TEST_TMP_DIR/runtime"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "$OUTPUT_PATH" ]]; then
    sed -n '1,320p' "$OUTPUT_PATH" >&2
  fi
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell timeout rg mktemp mkdir cp ln sed node; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

[[ -s "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" ]] || \
  fail "native Markdown parity fixture is missing"
[[ -s "$ROOT_DIR/NativeMarkdownDisplay.qml" ]] || \
  fail "NativeMarkdownDisplay.qml is missing"
[[ -s "$ROOT_DIR/markdown/MarkdownParserWorker.js" ]] || \
  fail "Markdown parser worker is missing"
[[ -s "$ROOT_DIR/SyntaxHighlight.js" ]] || \
  fail "SyntaxHighlight.js is missing"
[[ -s "$ROOT_DIR/syntax/HighlightWorker.js" ]] || \
  fail "syntax highlight worker is missing"
[[ -s "$ROOT_DIR/tests/fixtures/markdown-image.svg" ]] || \
  fail "Markdown image fixture is missing"

mkdir -m 700 -p -- "$CONFIG_DIR/markdown" "$CONFIG_DIR/syntax" \
  "$RUNTIME_DIR" "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/cache" \
  "$TEST_TMP_DIR/data"
cp -- "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/NativeMarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/markdown/MarkdownParserWorker.js"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" \
  "$CONFIG_DIR/syntax/HighlightWorker.js"
cp -- "$ROOT_DIR/tests/fixtures/markdown-image.svg" \
  "$CONFIG_DIR/markdown-image.svg"
# Some packaged Quickshell builds resolve TextEdit image URLs relative to the
# offscreen shell's URL rather than the copied config directory.
cp -- "$ROOT_DIR/tests/fixtures/markdown-image.svg" \
  "$TEST_TMP_DIR/markdown-image.svg"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"

set +e
env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    XDG_CONFIG_HOME="$CONFIG_DIR" XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" QT_QPA_PLATFORM=offscreen \
    QT_SCALE_FACTOR=1 \
    QT_LOGGING_RULES='qt.qml.usedbeforedeclared=false;qt.core.qobject.connect=false' \
    timeout --kill-after=1s 120s \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1
process_status=$?
set -e

if rg -q 'ERROR qml:|WARNING qml:|WARN qt\\.qml|WARN qt\\.core|WARN scene:|WARNING scene:|ERROR scene:|ReferenceError:|TypeError:|SyntaxError:|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine|file error|Failed to load' \
    "$OUTPUT_PATH"; then
  fail "native Markdown parity emitted a QML/runtime warning or error"
fi

result_count="$(rg -c 'NATIVE_PARITY_CASE: ' "$OUTPUT_PATH" || true)"
node "$ROOT_DIR/tests/check_native_reports.cjs" parity "$OUTPUT_PATH" || \
  fail "per-case parity contract failed"
expected_count="$(sed -n 's/.*"expectedCaseCount":\([0-9][0-9]*\).*/\1/p' \
  "$OUTPUT_PATH" | tail -1)"
[[ -n "$expected_count" ]] || fail "parity summary was not emitted"
[[ "$result_count" -eq "$expected_count" ]] || \
  fail "parity ran $result_count cases; expected $expected_count"
rg -q 'NATIVE_PARITY_SUMMARY: .*"missingCases":\[\]' "$OUTPUT_PATH" || \
  fail "parity did not run every expected fixture"

if [[ "$process_status" -eq 0 ]] && \
    rg -q 'NATIVE_PARITY_SUMMARY: .*"failures":\[\]' "$OUTPUT_PATH"; then
  printf 'PASS: native Markdown parity ran all %s cases\n' \
    "$expected_count"
  printf 'PASS: parser/runtime diagnostics were clean\n'
  printf 'NATIVE_PARITY_SUMMARY: %s\n' \
    "$(rg 'NATIVE_PARITY_SUMMARY: ' "$OUTPUT_PATH" | sed 's/.*NATIVE_PARITY_SUMMARY: //')"
  exit 0
fi

printf 'NATIVE_PARITY_SUMMARY: %s\n' \
  "$(rg 'NATIVE_PARITY_SUMMARY: ' "$OUTPUT_PATH" | sed 's/.*NATIVE_PARITY_SUMMARY: //')"
if [[ "$process_status" -ne 0 ]]; then
  fail "native Markdown parity reported fixture failures (quickshell status $process_status)"
fi
fail "native Markdown parity did not report a clean summary"
