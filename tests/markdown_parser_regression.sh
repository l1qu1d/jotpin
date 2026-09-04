#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-markdown-parser-regression.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly RUNTIME_DIR="$TEST_TMP_DIR/runtime"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "$OUTPUT_PATH" ]]; then
    sed -n '1,240p' "$OUTPUT_PATH" >&2
  fi
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell timeout rg mktemp mkdir cp; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

[[ -s "$ROOT_DIR/markdown/MarkdownParserWorker.js" ]] || \
  fail "the committed Markdown parser worker bundle is missing"

mkdir -m 700 -p -- "$CONFIG_DIR/markdown" "$RUNTIME_DIR" \
  "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/cache" "$TEST_TMP_DIR/data"
cp -- "$ROOT_DIR/tests/isolated/markdown_parser_regression.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/markdown/MarkdownParserWorker.js"

if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    XDG_CONFIG_HOME="$CONFIG_DIR" \
    XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" \
    XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    QT_QPA_PLATFORM=offscreen \
    timeout --kill-after=1s 15s \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1; then
  fail "Markdown parser WorkerScript regression failed"
fi

if rg -q 'ERROR qml:|ReferenceError:|TypeError:|SyntaxError:|Binding loop detected|QQmlApplicationEngine|MARKDOWN_PARSER_FAIL:' \
    "$OUTPUT_PATH"; then
  fail "Markdown parser regression emitted a QML/runtime error"
fi

result_count="$(rg -c 'MARKDOWN_PARSER_RESULT: ' "$OUTPUT_PATH" || true)"
[[ "$result_count" -eq 1 ]] || \
  fail "Markdown parser regression emitted $result_count results; expected 1"
rg -q 'MARKDOWN_PARSER_RESULT: .*"failures":\[\]' "$OUTPUT_PATH" || \
  fail "Markdown parser regression did not report an empty failure list"

result_line="$(rg 'MARKDOWN_PARSER_RESULT: ' "$OUTPUT_PATH")"
printf 'MARKDOWN_PARSER_RESULT: %s\n' \
  "${result_line#*MARKDOWN_PARSER_RESULT: }"
printf 'PASS: micromark/mdast source offsets survived the QML WorkerScript bundle\n'
