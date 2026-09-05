#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-isolated-render.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly SCALE_VALUES=(1 1.25 1.6 2 3 4)
declare -a SCALE_RESULTS=()
declare -a VIEWPORT_SCALE_RESULTS=()
CURRENT_OUTPUT_PATH=""

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -n "$CURRENT_OUTPUT_PATH" && -f "$CURRENT_OUTPUT_PATH" ]]; then
    cat "$CURRENT_OUTPUT_PATH" >&2
  fi
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell timeout rg mktemp cp ln mkdir; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -m 700 -p -- "$CONFIG_DIR/jotpin"

# Quickshell resolves the shell's `qs.Commons` and `qs.Ui` imports relative to
# its config directory. Keep the test config disposable while reusing the
# packaged, read-only Omarchy modules.
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"
cp -- "$ROOT_DIR/tests/isolated/markdown_display.qml" "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/tests/isolated/performance.qml" "$CONFIG_DIR/viewport.qml"
cp -- "$ROOT_DIR/MarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/HtmlEntities.js" "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/jotpin/"
mkdir -m 700 -p -- "$CONFIG_DIR/jotpin/syntax"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/jotpin/syntax/"

# Run the complete renderer matrix at every scale exposed by Omarchy's monitor
# panel. This includes both fractional stops and the 3x/4x extremes. Each run
# has its own private Quickshell runtime and never connects to Wayland.
for scale in "${SCALE_VALUES[@]}"; do
  scale_key="${scale//./_}"
  runtime_dir="$TEST_TMP_DIR/runtime-scale-$scale_key"
  output_path="$TEST_TMP_DIR/quickshell-scale-$scale_key.log"
  CURRENT_OUTPUT_PATH="$output_path"
  mkdir -m 700 -p -- "$runtime_dir"

  capture_args=()
  if [[ "$scale" != "1" ]]; then
    # Do not overwrite an explicitly requested scale-1 visual artifact set;
    # the other scale runs validate geometry numerically.
    capture_args=(-u JOTPIN_CAPTURE_DIR)
  fi

  if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
      "${capture_args[@]}" \
      JOTPIN_TEST_IMAGE_DIR="$ROOT_DIR/tests/fixtures" \
      XDG_RUNTIME_DIR="$runtime_dir" \
      QT_QPA_PLATFORM=offscreen \
      QT_SCALE_FACTOR="$scale" \
      timeout --kill-after=1s 15s \
      quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
      >"$output_path" 2>&1; then
    fail "scale-$scale isolated Quickshell renderer test failed"
  fi

  if rg -q 'ISOLATED_FAIL:|ERROR qml:|ReferenceError:|TypeError:|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine' \
      "$output_path"; then
    fail "scale-$scale isolated renderer emitted a failure"
  fi
  if rg -q 'Unknown color name' "$output_path"; then
    fail "scale-$scale renderer emitted an unsupported rich-text color"
  fi

  pass_count="$(rg -c 'ISOLATED_PASS:' "$output_path" || true)"
  [[ "$pass_count" -eq 76 ]] || \
    fail "scale-$scale renderer reported $pass_count cases; expected 76"
  rg -q 'ISOLATED_RESULT: .*"failures":\[\]' "$output_path" || \
    fail "scale-$scale renderer did not report an empty failure list"
  rg -q 'ISOLATED_RESULT: .*"caseCount":76' "$output_path" || \
    fail "scale-$scale renderer did not execute the complete edge-case matrix"

  lookup_line="$(rg -o 'ISOLATED_SELECTION_LOOKUP_MS: [0-9]+' "$output_path")"
  lookup_ms="${lookup_line##* }"
  [[ "$lookup_ms" =~ ^[0-9]+$ && "$lookup_ms" -lt 1000 ]] || \
    fail "scale-$scale selection lookup benchmark was not below 1000ms: $lookup_ms"
  column_lookup_line="$(rg -o \
    'ISOLATED_SOURCE_COLUMN_LOOKUP_MS: [0-9]+' "$output_path")"
  column_lookup_ms="${column_lookup_line##* }"
  [[ "$column_lookup_ms" =~ ^[0-9]+$ && "$column_lookup_ms" -lt 1000 ]] || \
    fail "scale-$scale source-column benchmark was not below 1000ms: $column_lookup_ms"
  SCALE_RESULTS+=("$scale=${lookup_ms}/${column_lookup_ms}ms")

  viewport_runtime_dir="$TEST_TMP_DIR/viewport-runtime-scale-$scale_key"
  viewport_output_path="$TEST_TMP_DIR/viewport-scale-$scale_key.log"
  CURRENT_OUTPUT_PATH="$viewport_output_path"
  mkdir -m 700 -p -- "$viewport_runtime_dir"
  if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
      -u JOTPIN_CAPTURE_DIR \
      JOTPIN_TEST_IMAGE_DIR="$ROOT_DIR/tests/fixtures" \
      XDG_RUNTIME_DIR="$viewport_runtime_dir" \
      QT_QPA_PLATFORM=offscreen \
      QT_SCALE_FACTOR="$scale" \
      timeout --kill-after=1s 15s \
      quickshell --no-duplicate --path "$CONFIG_DIR/viewport.qml" \
      >"$viewport_output_path" 2>&1; then
    fail "scale-$scale viewport renderer test failed"
  fi
  if rg -q 'PERF_FAIL:|ERROR qml:|ReferenceError:|TypeError:|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine' \
      "$viewport_output_path"; then
    fail "scale-$scale viewport renderer emitted a failure"
  fi
  viewport_pass_count="$(rg -c 'PERF_VIEWPORT_PASS:' \
    "$viewport_output_path" || true)"
  [[ "$viewport_pass_count" -eq 3 ]] || \
    fail "scale-$scale viewport renderer reported $viewport_pass_count workloads; expected 3"
  rg -q 'PERF_QML_RESULT: .*"failures":\[\]' "$viewport_output_path" || \
    fail "scale-$scale viewport renderer did not report an empty failure list"
  VIEWPORT_SCALE_RESULTS+=("$scale=$viewport_pass_count/3")
done

CURRENT_OUTPUT_PATH=""
printf 'PASS: offscreen Quickshell renderer checks passed without desktop input\n'
printf 'PASS: complete renderer matrix passed at Omarchy scales %s\n' \
  "${SCALE_VALUES[*]}"
printf 'PASS: 240 long-note/long-row pointer lookups by scale: %s\n' \
  "${SCALE_RESULTS[*]}"
printf 'PASS: viewport top/middle/bottom/edit workloads by scale: %s\n' \
  "${VIEWPORT_SCALE_RESULTS[*]}"
printf 'PASS: isolated renderer artifact log was disposable and cleaned up\n'
