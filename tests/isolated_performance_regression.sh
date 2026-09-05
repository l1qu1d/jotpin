#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-p.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly RUNTIME_DIR="$TEST_TMP_DIR/runtime"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"
readonly MODEL_OUTPUT_PATH="$TEST_TMP_DIR/model.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ ! -f "$OUTPUT_PATH" ]] || cat "$OUTPUT_PATH" >&2
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in node quickshell timeout rg mktemp cp ln mkdir; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

if ! node "$ROOT_DIR/tests/editor_performance.test.cjs" \
    >"$MODEL_OUTPUT_PATH" 2>&1; then
  cat "$MODEL_OUTPUT_PATH" >&2
  fail "editor-model performance baseline failed"
fi
rg -q 'PERF_MODEL_RESULT:' "$MODEL_OUTPUT_PATH" || \
  fail "editor-model performance baseline did not report a result"

mkdir -m 700 -p -- "$CONFIG_DIR/jotpin" "$RUNTIME_DIR"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"
cp -- "$ROOT_DIR/tests/isolated/performance.qml" "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/MarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/HtmlEntities.js" "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/jotpin/"
mkdir -m 700 -p -- "$CONFIG_DIR/jotpin/syntax"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/jotpin/syntax/"

if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    JOTPIN_TEST_IMAGE_DIR="$ROOT_DIR/tests/fixtures" \
    QT_QPA_PLATFORM=offscreen \
    QT_SCALE_FACTOR=1 \
    timeout --kill-after=1s 45s \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1; then
  fail "isolated performance baseline failed"
fi

if rg -q 'PERF_FAIL:|ERROR qml:|ReferenceError:|TypeError:|Binding loop detected|QQmlApplicationEngine' \
    "$OUTPUT_PATH"; then
  fail "isolated performance baseline emitted a failure"
fi

rg -q 'PERF_QML_RESULT: .*"failures":\[\]' "$OUTPUT_PATH" || \
  fail "isolated performance baseline did not report a clean result"

model_result="$(rg 'PERF_MODEL_RESULT:' "$MODEL_OUTPUT_PATH")"
qml_result="$(rg 'PERF_QML_RESULT:' "$OUTPUT_PATH")"
printf '%s\n' "$model_result" "$qml_result"
printf 'PASS: isolated parser, layout, caret, pointer, selection, find, and edit-transaction budgets passed\n'
printf 'PASS: performance artifacts were disposable and cleaned up\n'
