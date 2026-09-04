#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-native-markdown-performance.XXXXXX)"
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

for command in quickshell timeout rg mktemp mkdir cp ln node; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

[[ -s "$ROOT_DIR/tests/isolated/native_markdown_performance.qml" ]] || \
  fail "native Markdown performance fixture is missing"
[[ -s "$ROOT_DIR/NativeMarkdownDisplay.qml" ]] || \
  fail "NativeMarkdownDisplay.qml is missing"
[[ -s "$ROOT_DIR/markdown/MarkdownParserWorker.js" ]] || \
  fail "Markdown parser worker is missing"
[[ -s "$ROOT_DIR/SyntaxHighlight.js" ]] || \
  fail "SyntaxHighlight.js is missing"
[[ -s "$ROOT_DIR/syntax/HighlightWorker.js" ]] || \
  fail "syntax highlight worker is missing"

mkdir -m 700 -p -- "$CONFIG_DIR/markdown" "$CONFIG_DIR/syntax" \
  "$RUNTIME_DIR" "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/cache" \
  "$TEST_TMP_DIR/data"
cp -- "$ROOT_DIR/tests/isolated/native_markdown_performance.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/NativeMarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/markdown/MarkdownParserWorker.js"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" \
  "$CONFIG_DIR/syntax/HighlightWorker.js"

# Resolve only the read-only Omarchy QML imports from the packaged shell. All
# writable XDG locations, including runtime metadata, stay inside the temp
# directory and the test is explicitly disconnected from the desktop.
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"

if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    XDG_CONFIG_HOME="$CONFIG_DIR" \
    XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" \
    XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    QT_QPA_PLATFORM=offscreen \
    QT_SCALE_FACTOR=1 \
    QT_LOGGING_RULES='qt.qml.usedbeforedeclared=false;qt.core.qobject.connect=false' \
    timeout --kill-after=1s 120s \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1; then
  fail "native Markdown performance regression failed"
fi

# Keep this stricter than a pass/fail marker: QML warnings and worker/runtime
# diagnostics are regressions even when the fixture happens to finish.
if rg -q 'PERF_NATIVE_FAIL:|ERROR qml:|WARNING qml:|WARN qt\.qml|WARN qt\.core|ReferenceError:|TypeError:|SyntaxError:|usedbeforedeclared|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine|file error|Failed to load' \
    "$OUTPUT_PATH"; then
  fail "native Markdown performance regression emitted a QML/runtime warning or error"
fi

result_count="$(rg -c 'PERF_NATIVE_RESULT: ' "$OUTPUT_PATH" || true)"
node "$ROOT_DIR/tests/check_native_reports.cjs" performance "$OUTPUT_PATH" || \
  fail "per-workload performance contract failed"
[[ "$result_count" -eq 4 ]] || \
  fail "native Markdown performance regression emitted $result_count result records; expected 4"
for workload in 1KiB 10KiB 25KiB 100KiB; do
  rg -q "PERF_NATIVE_RESULT: .*\"name\":\"$workload\"" "$OUTPUT_PATH" || \
    fail "native Markdown performance regression did not report $workload"
done
rg -q 'PERF_NATIVE_RESULT: .*"failures":\[\]' "$OUTPUT_PATH" || \
  fail "native Markdown performance regression did not report an empty failure list"
rg -q 'PERF_NATIVE_SUMMARY: .*"workloadCount":4' "$OUTPUT_PATH" || \
  fail "native Markdown performance regression did not report all workloads"

while IFS= read -r result_line; do
  # Quickshell may prefix console output with a logging category. Expose the
  # stable marker and JSON payload for callers comparing performance runs.
  printf 'PERF_NATIVE_RESULT: %s\n' \
    "${result_line#*PERF_NATIVE_RESULT: }"
done < <(rg 'PERF_NATIVE_RESULT: ' "$OUTPUT_PATH")
printf 'PASS: native Markdown parse/layout and geometry performance regression completed\n'
printf 'PASS: performance artifacts were disposable and cleaned up\n'
