#!/usr/bin/env bash

# Live tests inject keys into the focused Wayland surface and can change the
# active JotPin panel. Refuse by default so the normal test command is safe to
# run while the desktop is being used.

if [[ ${JOTPIN_ALLOW_LIVE_TESTS:-0} != 1 ]]; then
  printf '%s\n' \
    'Refusing to run an JotPin live test because it controls the active desktop.' \
    'Run the isolated suite instead: bash tests/run.sh' \
    'For an intentional visual check, opt in explicitly with:' \
    '  JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/live_visual_smoke.sh' >&2
  exit 2
fi

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  printf '%s\n' \
    'JotPin live tests require an active Wayland display.' \
    'Use the isolated suite when no desktop session is available.' >&2
  exit 2
fi
