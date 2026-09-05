#!/usr/bin/env bash
set -euo pipefail

target="${!#}"
if [[ -n "${JOTPIN_TEST_RENAME_RACE_TARGET:-}" &&
      "$target" == "$JOTPIN_TEST_RENAME_RACE_TARGET" ]]; then
  /usr/bin/cp -- "$JOTPIN_TEST_RACE_FIXTURE" "$target"
fi

exec /usr/bin/mv "$@"
