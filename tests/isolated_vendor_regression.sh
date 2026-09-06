#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-isolated-vendor.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly RUNTIME_DIR="$TEST_TMP_DIR/runtime"
readonly OUTPUT_PATH="$TEST_TMP_DIR/vendor.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ -f "$OUTPUT_PATH" ]] && tail -n 120 "$OUTPUT_PATH" >&2
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

node "$ROOT_DIR/tests/dictionary_bundle.mjs"

for command in quickshell timeout rg mktemp cp mkdir; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -m 700 -p -- "$CONFIG_DIR/spellcheck" "$CONFIG_DIR/syntax" "$RUNTIME_DIR"
cp -- "$ROOT_DIR/tests/isolated/vendor_smoke.qml" "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/spellcheck/SpellcheckWorker.mjs" "$ROOT_DIR/spellcheck/DictionaryPart1.mjs" "$ROOT_DIR/spellcheck/DictionaryPart2.mjs" "$CONFIG_DIR/spellcheck/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/syntax/"

if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" QT_QPA_PLATFORM=offscreen \
    timeout --kill-after=1s 20s \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1; then
  fail 'offline language-bundle smoke test failed'
fi

if rg -q 'VENDOR_FAIL:|ERROR qml:|ReferenceError:|TypeError:|usedbeforedeclared|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine' \
    "$OUTPUT_PATH"; then
  fail 'offline language-bundle smoke test emitted a runtime failure'
fi
rg -q 'VENDOR_PASS: offline language bundles initialized' "$OUTPUT_PATH" || \
  fail 'offline language bundles did not report successful initialization'
rg 'VENDOR_SPELLCHECK_PERF:' "$OUTPUT_PATH" || \
  fail 'offline spellcheck worker did not emit its performance measurement'
rg 'VENDOR_SPELLCHECK_INCREMENTAL:' "$OUTPUT_PATH" || \
  fail 'offline spellcheck worker did not prove incremental cache reuse'

printf '%s\n' 'PASS: bundled nspell and Highlight.js engines run in isolated QML workers'
