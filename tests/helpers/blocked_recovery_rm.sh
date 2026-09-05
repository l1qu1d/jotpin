#!/usr/bin/env bash
set -euo pipefail

# Hold only this fixture's recovery deletion until the newer edit is queued.
target="${!#}"
if [[ "${JOTPIN_PERSIST_MODE:-}" == recovery-cleanup-* &&
      "$target" == "$HOME/.local/state/jotpin/recovery/"* ]]; then
  for ((attempt = 0; attempt < 500; attempt++)); do
    [[ -f "$JOTPIN_TEST_RECOVERY_RELEASE" ]] && break
    sleep 0.01
  done
  [[ -f "$JOTPIN_TEST_RECOVERY_RELEASE" ]] || exit 1
fi
exec /usr/bin/rm "$@"
