#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bash tests/run.sh [model|performance|render|headless|legacy-render|legacy-performance|window|live|all]

  model     Run pure editor transition tests only.
  performance
            Run the production Markdown parser/display latency smoke.
  render    Run the production parser and RichText display checks only.
  headless  Run all non-interactive plugin, Markdown, and renderer checks (default).
  legacy-render
            Run the retired pure-QML renderer oracle (not production acceptance).
  legacy-performance
            Run the retired pure-QML renderer benchmark (not production acceptance).
  window    Run the opt-in native-window fullscreen/resize regression.
  live      Run the opt-in visual smoke test; it requires
            JOTPIN_ALLOW_LIVE_TESTS=1 and controls the active desktop.
  all       Run headless checks, then live smoke only when explicitly opted in.
EOF
}

mode="${1:-headless}"

run_headless() (
  # Enforce isolation at the suite boundary as well as inside each harness.
  # Future child tests inherit disposable state and no desktop connection.
  suite_tmp_dir="$(mktemp -d /tmp/jotpin-headless.XXXXXX)"
  trap 'rm -rf -- "$suite_tmp_dir"' EXIT
  mkdir -p "$suite_tmp_dir"/{home,config,state,cache,data,runtime}
  chmod 700 "$suite_tmp_dir/runtime"
  unset DISPLAY WAYLAND_DISPLAY QT_QPA_PLATFORMTHEME
  export HOME="$suite_tmp_dir/home" XDG_CONFIG_HOME="$suite_tmp_dir/config" \
    XDG_STATE_HOME="$suite_tmp_dir/state" XDG_CACHE_HOME="$suite_tmp_dir/cache" \
    XDG_DATA_HOME="$suite_tmp_dir/data" XDG_RUNTIME_DIR="$suite_tmp_dir/runtime"
  node "$ROOT_DIR/tests/qt_contract_gate.test.cjs"
  node "$ROOT_DIR/tests/native_report_gate.test.cjs"
  bash "$ROOT_DIR/tests/test_plugin.sh"
  node "$ROOT_DIR/tests/editor_performance.test.cjs"
  bash "$ROOT_DIR/tests/isolated_installer_regression.sh"
  bash "$ROOT_DIR/tests/isolated_vendor_regression.sh"
  bash "$ROOT_DIR/tests/markdown_parser_regression.sh"
  bash "$ROOT_DIR/tests/native_markdown_display_regression.sh"
  bash "$ROOT_DIR/tests/native_markdown_caret_matrix.sh"
  bash "$ROOT_DIR/tests/native_markdown_mouse_regression.sh"
  bash "$ROOT_DIR/tests/jotpin_link_keys_regression.sh"
  node "$ROOT_DIR/tests/link_mutation_regression.cjs"
  bash "$ROOT_DIR/tests/jotpin_list_return_regression.sh"
  bash "$ROOT_DIR/tests/native_markdown_parity.sh"
  bash "$ROOT_DIR/tests/native_markdown_performance.sh"
  bash "$ROOT_DIR/tests/startup_regression.sh"
  bash "$ROOT_DIR/tests/isolated_persistence_regression.sh"
  printf '%s\n' 'PASS: complete production headless suite (including coverage and mutation gates)'
)

case "$mode" in
  model)
    exec node "$ROOT_DIR/tests/editor_model.test.cjs"
    ;;
  performance|perf)
    exec bash "$ROOT_DIR/tests/native_markdown_performance.sh"
    ;;
  headless|fast)
    run_headless
    ;;
  render|isolated)
    bash "$ROOT_DIR/tests/markdown_parser_regression.sh"
    bash "$ROOT_DIR/tests/native_markdown_display_regression.sh"
    bash "$ROOT_DIR/tests/native_markdown_caret_matrix.sh"
    bash "$ROOT_DIR/tests/native_markdown_mouse_regression.sh"
    exec bash "$ROOT_DIR/tests/native_markdown_parity.sh"
    ;;
  legacy-render)
    exec bash "$ROOT_DIR/tests/isolated_render_regression.sh"
    ;;
  legacy-performance)
    exec bash "$ROOT_DIR/tests/isolated_performance_regression.sh"
    ;;
  window)
    exec bash "$ROOT_DIR/tests/live_window_management_regression.sh"
    ;;
  live|visual)
    exec bash "$ROOT_DIR/tests/live_visual_smoke.sh"
    ;;
  all)
    run_headless
    if [[ ${JOTPIN_ALLOW_LIVE_TESTS:-0} != 1 ]]; then
      printf '%s\n' \
        'Headless checks passed.' \
        'Live checks were skipped because they control the active desktop.' \
        'To run them intentionally: JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/run.sh all' >&2
      exit 0
    fi
    bash "$ROOT_DIR/tests/live_window_management_regression.sh"
    exec bash "$ROOT_DIR/tests/live_visual_smoke.sh"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
