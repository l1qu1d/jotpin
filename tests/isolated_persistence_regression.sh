#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-persistence.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly RUNTIME_DIR="$TEST_TMP_DIR/runtime"
readonly TEST_HOME="$TEST_TMP_DIR/home"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/note.md"
readonly TEST_OPEN_NOTE="$TEST_TMP_DIR/open-target.md"
readonly TEST_POLICY_NOTE_PATH="$TEST_TMP_DIR/policy-note.md"
readonly TEST_POLICY_NON_MD_PATH="$TEST_TMP_DIR/policy-blocked.txt"
readonly TEST_POLICY_RENAME_PATH="$TEST_TMP_DIR/policy-renamed.md"
readonly TEST_SAVE_AS_PATH="$TEST_TMP_DIR/save-as-target.md"
readonly TEST_SAVE_AS_OVERWRITE_PATH="$TEST_TMP_DIR/save-as-existing.md"
readonly TEST_SAVE_AS_RACE_PATH="$TEST_TMP_DIR/save-as-race.md"
readonly TEST_RENAME_RACE_SOURCE="$TEST_TMP_DIR/rename-race-source.md"
readonly TEST_RENAME_RACE_TARGET="$TEST_TMP_DIR/rename-race-target.md"
readonly TEST_RACE_FIXTURE="$TEST_TMP_DIR/late-created.md"
readonly TEST_BIN_DIR="$TEST_TMP_DIR/bin"
readonly TEST_BLANK_UNTITLED_PATH="$TEST_TMP_DIR/home/Documents/Notes/untitled-ABC123.md"
readonly TEST_DEFAULT_FIRST_PATH="$TEST_TMP_DIR/home/Documents/Notes/default-first.md"
readonly TEST_DEFAULT_SECOND_PATH="$TEST_TMP_DIR/home/Documents/Notes/default-second.md"
readonly TEST_DEFAULT_IGNORE_PATH="$TEST_TMP_DIR/home/Documents/Notes/default-ignore.txt"
readonly TEST_SETTINGS_DIR="$TEST_TMP_DIR/custom-notes"
readonly TEST_READONLY_DIR="$TEST_TMP_DIR/read-only"
readonly TEST_READONLY_NOTE="$TEST_READONLY_DIR/note.md"
readonly TEST_MISSING_NOTE="$TEST_TMP_DIR/missing-note.md"
readonly TEST_UNREADABLE_NOTE="$TEST_TMP_DIR/unreadable-note.md"
readonly TEST_TAB_STATE_FIRST="$TEST_TMP_DIR/tab-state-first.md"
readonly TEST_TAB_STATE_SECOND="$TEST_TMP_DIR/tab-state-second.md"
readonly TEST_TASK_TOGGLE_PATH="$TEST_TMP_DIR/task-toggle-scroll.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  chmod 700 "$TEST_READONLY_DIR" 2>/dev/null || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell timeout rg jq mktemp cp ln mkdir find cmp tail mv touch chmod stat; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -m 700 -p -- "$CONFIG_DIR/jotpin" "$RUNTIME_DIR" "$TEST_HOME/state" \
  "$TEST_BIN_DIR"
mkdir -p -- "$TEST_HOME/Documents/Notes"
mkdir -p -- "$TEST_READONLY_DIR"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"
cp -- "$ROOT_DIR/JotPin.qml" "$ROOT_DIR/JotPinButton.qml" \
  "$ROOT_DIR/HostIntegration.qml" \
  "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  "$ROOT_DIR/EditorModel.js" "$ROOT_DIR/HtmlEntities.js" \
  "$ROOT_DIR/SpellcheckModel.js" "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/jotpin/"
mkdir -m 700 -p -- "$CONFIG_DIR/jotpin/markdown" \
  "$CONFIG_DIR/jotpin/spellcheck" "$CONFIG_DIR/jotpin/syntax"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/jotpin/markdown/"
cp -- "$ROOT_DIR/spellcheck/SpellcheckWorker.js" "$CONFIG_DIR/jotpin/spellcheck/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/jotpin/syntax/"
cp -- "$ROOT_DIR/tests/isolated/persistence.qml" "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_NOTE_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_OPEN_NOTE"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_TAB_STATE_FIRST"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_TAB_STATE_SECOND"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_TASK_TOGGLE_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_READONLY_NOTE"
ln -s /proc/1/mem "$TEST_UNREADABLE_NOTE"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_SAVE_AS_OVERWRITE_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_RENAME_RACE_SOURCE"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_POLICY_NOTE_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_POLICY_NON_MD_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_DEFAULT_FIRST_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_DEFAULT_SECOND_PATH"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_DEFAULT_IGNORE_PATH"
touch -- "$TEST_BLANK_UNTITLED_PATH"
printf '%s' 'late-created-destination' >"$TEST_RACE_FIXTURE"
cp -- "$ROOT_DIR/tests/helpers/race_ln.sh" "$TEST_BIN_DIR/ln"
cp -- "$ROOT_DIR/tests/helpers/race_mv.sh" "$TEST_BIN_DIR/mv"
chmod 700 "$TEST_BIN_DIR/ln" "$TEST_BIN_DIR/mv"
chmod 500 "$TEST_READONLY_DIR"

run_stage() {
  local mode="$1"
  local session_path="${2:-}"
  local note_path="${3:-$TEST_NOTE_PATH}"
  local scale_factor="${4:-1}"
  local output_path="$TEST_TMP_DIR/$mode.log"
  if [[ "$scale_factor" != "1" ]]; then
    output_path="$TEST_TMP_DIR/$mode-scale-$scale_factor.log"
  fi

  if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
      HOME="$TEST_HOME" \
      XDG_STATE_HOME="$TEST_HOME/state" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      QT_QPA_PLATFORM=offscreen \
      QT_SCALE_FACTOR="$scale_factor" \
      JOTPIN_PERSIST_MODE="$mode" \
      JOTPIN_TEST_NOTE="$note_path" \
      JOTPIN_TEST_OPEN_NOTE="$TEST_OPEN_NOTE" \
      JOTPIN_TEST_MISSING_RECENT="$TEST_MISSING_NOTE" \
      JOTPIN_TEST_UNREADABLE_RECENT="$TEST_UNREADABLE_NOTE" \
      JOTPIN_TEST_SESSION_PATH="$session_path" \
      JOTPIN_TEST_NON_MD="$TEST_POLICY_NON_MD_PATH" \
      JOTPIN_TEST_RENAME_TARGET="$TEST_POLICY_RENAME_PATH" \
      JOTPIN_TEST_SAVE_AS_TARGET="$TEST_SAVE_AS_PATH" \
      JOTPIN_TEST_SAVE_AS_OVERWRITE="$TEST_SAVE_AS_OVERWRITE_PATH" \
      JOTPIN_TEST_SAVE_AS_RACE_TARGET="$TEST_SAVE_AS_RACE_PATH" \
      JOTPIN_TEST_RENAME_RACE_SOURCE="$TEST_RENAME_RACE_SOURCE" \
      JOTPIN_TEST_RENAME_RACE_TARGET="$TEST_RENAME_RACE_TARGET" \
      JOTPIN_TEST_RACE_FIXTURE="$TEST_RACE_FIXTURE" \
      JOTPIN_TEST_BLANK_UNTITLED="$TEST_BLANK_UNTITLED_PATH" \
      JOTPIN_TEST_DEFAULT_FIRST="$TEST_DEFAULT_FIRST_PATH" \
      JOTPIN_TEST_DEFAULT_SECOND="$TEST_DEFAULT_SECOND_PATH" \
      JOTPIN_TEST_SETTINGS_DIR="$TEST_SETTINGS_DIR" \
      JOTPIN_TEST_TAB_STATE_SECOND="$TEST_TAB_STATE_SECOND" \
      PATH="$TEST_BIN_DIR:$PATH" \
      timeout --kill-after=1s 8s \
      quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
      >"$output_path" 2>&1; then
    sed -n '1,220p' "$output_path" >&2
    fail "offscreen persistence stage $mode failed"
  fi

  if rg -q 'PERSIST_FAIL:|TypeError:|ReferenceError:|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine' \
      "$output_path"; then
    sed -n '1,220p' "$output_path" >&2
    fail "offscreen persistence stage $mode emitted a runtime failure"
  fi
  rg -q "PERSIST_RESULT: $mode" "$output_path" || {
    sed -n '1,220p' "$output_path" >&2
    fail "offscreen persistence stage $mode did not finish"
  }
  rg 'PERSIST_(PASS|RECOVERY_PATH):' "$output_path"
}

if [[ "${1:-}" == "table-helper" ]]; then
  run_stage table-helper
  run_stage table-helper "" "$TEST_NOTE_PATH" 2
  exit 0
fi

if [[ "${1:-}" == "load-stall" ]]; then
  run_stage load-stall
  exit 0
fi

run_spellcheck_hydration() {
  local settings_path="$TEST_HOME/.local/state/jotpin/settings.json"
  mkdir -m 700 -p -- "$(dirname -- "$settings_path")"
  printf '%s\n' \
    '{"version":10,"spellcheck":{"enabled":false,"language":"en-US"}}' \
    >"$settings_path"
  run_stage spellcheck-hydration
  [[ "$(jq -r '.spellcheck.enabled' "$settings_path")" == "true" ]] || \
    fail "the final pre-hydration spellcheck click was not persisted"
  printf '%s\n' \
    'PASS: pre-hydration spellcheck toggle persisted its final enabled state'
}

if [[ "${1:-}" == "spellcheck-hydration" ]]; then
  run_spellcheck_hydration
  exit 0
fi

if [[ "${1:-}" == "host-integration" ]]; then
  run_stage host-integration
  exit 0
fi

run_spellcheck_hydration
run_stage host-integration
run_stage alignment
run_stage load-stall
run_stage editor-undo
run_stage task-toggle-scroll "" "$TEST_TASK_TOGGLE_PATH"
run_stage table-helper
run_stage table-helper "" "$TEST_NOTE_PATH" 2
run_stage editor-commands
run_stage editor-indent
run_stage editor-context
run_stage spellcheck
personal_dictionary_path="$TEST_HOME/.local/state/jotpin/personal-dictionary.json"
[[ "$(jq -r '.words | index("mispelled")' "$personal_dictionary_path")" != "null" ]] || \
  fail "spellcheck did not persist its personal dictionary word"
printf '%s\n' 'PASS: bundled spellcheck persisted a personal word without dirtying the note'
run_stage file-menu-save
[[ "$(<"$TEST_NOTE_PATH")" == "file-menu-save" ]] || \
  fail "File-menu Save did not persist the current source"
printf '%s\n' 'PASS: File-menu Save persisted the current source and closed its menu'
run_stage save-as-inflight
[[ "$(<"$TEST_SAVE_AS_PATH")" == "save-as-newer" ]] || \
  fail "Save As did not persist the edit made while its first write was in flight"
printf '%s\n' 'PASS: Save As preserved and persisted an edit made during its write'
run_stage save-as-overwrite
[[ "$(<"$TEST_SAVE_AS_OVERWRITE_PATH")" == "save-as-overwrite" ]] || \
  fail "confirmed Save As overwrite did not replace the destination"
printf '%s\n' 'PASS: Save As required confirmation before replacing an existing file'
run_stage save-as-race
[[ "$(<"$TEST_SAVE_AS_RACE_PATH")" == "late-created-destination" ]] || \
  fail "Save As overwrote a destination created after its existence check"
printf '%s\n' 'PASS: Save As did not clobber a destination created during the race window'
run_stage rename-race "" "$TEST_RENAME_RACE_SOURCE"
[[ "$(<"$TEST_RENAME_RACE_TARGET")" == "late-created-destination" ]] || \
  fail "rename overwrote a destination created after its existence check"
[[ "$(<"$TEST_RENAME_RACE_SOURCE")" == "base" ]] || \
  fail "failed no-clobber rename changed or removed its source"
printf '%s\n' 'PASS: rename preserved both files when a destination appeared during the race window'
run_stage save-failure-switch "" "$TEST_READONLY_NOTE"
[[ "$(<"$TEST_READONLY_NOTE")" == "base" ]] || \
  fail "failed save changed the read-only source file"
printf '%s\n' 'PASS: a failed save kept the original tab and source context'
run_stage save-failure-close "" "$TEST_READONLY_NOTE"
printf '%s\n' 'PASS: a failed close kept the unsaved tab open'
run_stage missing-load "" "$TEST_MISSING_NOTE"
[[ ! -e "$TEST_MISSING_NOTE" ]] || \
  fail "loading a missing session note recreated it without confirmation"
run_stage unreadable-load "" "$TEST_UNREADABLE_NOTE"
[[ -e "$TEST_UNREADABLE_NOTE" ]] || \
  fail "loading an unreadable note removed it"
printf '%s\n' 'PASS: missing and unreadable notes remain distinct and non-destructive'
run_stage external-change
[[ "$(<"$TEST_NOTE_PATH")" == "external-to-reload" ]] || \
  fail "external conflict Reload did not preserve the disk version"
printf '%s\n' 'PASS: external changes reload clean notes and conflict with dirty notes'
run_stage session-prepare
session_path="$(sed -n 's/.*PERSIST_SESSION_PATH: //p' \
  "$TEST_TMP_DIR/session-prepare.log" | tail -n 1)"
[[ -n "$session_path" ]] || fail "New did not report its generated note path"
[[ "$session_path" == "$TEST_HOME/Documents/Notes/untitled-"* ]] || \
  fail "New generated a note outside the private notes directory: $session_path"
[[ -f "$session_path" ]] || fail "New's generated note was not left on disk"
session_settings_path="$TEST_HOME/.local/state/jotpin/settings.json"
[[ -f "$session_settings_path" ]] || \
  fail "New did not create the persisted JotPin session settings"
[[ "$(jq -r '.notePath' "$session_settings_path")" == "$session_path" ]] || \
  fail "persisted settings did not keep the generated file active"
jq -e --arg session_path "$session_path" \
  '.openFiles | index($session_path) != null' \
  "$session_settings_path" >/dev/null || \
  fail "persisted settings did not keep the generated file tab"
jq -e --arg session_path "$session_path" \
  '.generatedUntitledPaths | index($session_path) != null' \
  "$session_settings_path" >/dev/null || \
  fail "persisted settings did not keep generated-note provenance"
jq --arg blocked_path "$TEST_POLICY_NON_MD_PATH" \
  '.openFiles += [$blocked_path]' "$session_settings_path" \
  >"$session_settings_path.tmp"
mv -- "$session_settings_path.tmp" "$session_settings_path"
printf '%s\n' 'PASS: session state persisted the generated active file and tab'
run_stage session-restore "$session_path"
run_stage open
[[ "$(<"$TEST_OPEN_NOTE")" == "base" ]] || \
  fail "Open stage changed the existing target file"
run_stage open-list
run_stage untitled-close
[[ -e "$TEST_BLANK_UNTITLED_PATH" ]] || \
  fail "closing a user-created untitled-like note deleted it"
printf '%s\n' 'PASS: user-created untitled-like filenames are never auto-deleted'
run_stage generated-close
generated_close_path="$(sed -n 's/.*PERSIST_GENERATED_CLOSE_PATH: //p' \
  "$TEST_TMP_DIR/generated-close.log" | tail -n 1)"
[[ -n "$generated_close_path" ]] || fail "generated close did not report its path"
[[ ! -e "$generated_close_path" ]] || \
  fail "closing a blank JotPin-generated note left it on disk"
printf '%s\n' 'PASS: blank notes created by JotPin are removed on close'
run_stage last-close
last_close_new_path="$(sed -n 's/.*PERSIST_LAST_CLOSE_NEW_PATH: //p' \
  "$TEST_TMP_DIR/last-close.log" | tail -n 1)"
[[ -n "$last_close_new_path" ]] || \
  fail 'closing the last tab did not report its replacement note'
[[ -f "$last_close_new_path" && ! -s "$last_close_new_path" ]] || \
  fail 'the last-tab replacement is missing or not blank'
[[ "$(<"$TEST_NOTE_PATH")" == 'saved-before-last-close' ]] || \
  fail 'closing the dirty last tab did not preserve its saved source'
printf '%s\n' 'PASS: closing the last tab saves it and opens a blank replacement note'
run_stage policy "" "$TEST_POLICY_NOTE_PATH"
[[ -f "$TEST_POLICY_NON_MD_PATH" ]] || \
  fail "Markdown policy stage removed the non-Markdown file"
[[ "$(<"$TEST_POLICY_NON_MD_PATH")" == "base" ]] || \
  fail "Markdown policy stage changed the non-Markdown file"
[[ -f "$TEST_POLICY_RENAME_PATH" ]] || \
  fail "Markdown policy stage did not create the renamed Markdown file"
[[ "$(<"$TEST_POLICY_RENAME_PATH")" == "dirty-rename-source" ]] || \
  fail "Markdown policy stage did not preserve the renamed Markdown source"
[[ ! -e "$TEST_POLICY_NOTE_PATH" ]] || \
  fail "Markdown policy stage left the old Markdown path in place"
run_stage prepare
[[ "$(<"$TEST_NOTE_PATH")" == "coalesced-save" ]] || \
  fail "save stage did not leave the latest coalesced bytes on disk"

recovery_path="$(sed -n 's/.*PERSIST_RECOVERY_PATH: //p' \
  "$TEST_TMP_DIR/prepare.log" | tail -n 1)"
[[ -n "$recovery_path" ]] || fail "continuous editing did not create a recovery file"
[[ "$recovery_path" == "$TEST_TMP_DIR"/* ]] || \
  fail "offscreen recovery escaped the private test directory: $recovery_path"
[[ -f "$recovery_path" ]] || fail "continuous editing did not create a recovery file"
expected_recovery="$(jq -r '.source' "$recovery_path")"
[[ "$expected_recovery" == crash-recovery-* ]] || \
  fail "recovery file did not contain the continuously edited source"
printf '%s\n' 'PASS: continuous edits left the saved note unchanged and created recovery bytes'

run_stage recover
[[ "$(<"$TEST_NOTE_PATH")" == "$expected_recovery" ]] || \
  fail "Recover did not persist the recovery source"
[[ ! -f "$recovery_path" ]] || \
  fail "Recover did not remove the recovery file"
printf '%s\n' 'PASS: Recover persisted the snapshot and removed its recovery file'

saved_before_discard="$(<"$TEST_NOTE_PATH")"
run_stage discard-prepare
recovery_path="$(sed -n 's/.*PERSIST_RECOVERY_PATH: //p' \
  "$TEST_TMP_DIR/discard-prepare.log" | tail -n 1)"
[[ -n "$recovery_path" ]] || fail "discard setup did not create a recovery file"
[[ "$recovery_path" == "$TEST_TMP_DIR"/* ]] || \
  fail "discard recovery escaped the private test directory: $recovery_path"
[[ -f "$recovery_path" ]] || fail "discard setup did not create a recovery file"
[[ "$(jq -r '.source' "$recovery_path")" == discard-recovery-* ]] || \
  fail "discard setup recovery file contained the wrong source"

run_stage discard
[[ "$(<"$TEST_NOTE_PATH")" == "$saved_before_discard" ]] || \
  fail "Discard changed the saved note"
[[ ! -f "$recovery_path" ]] || \
  fail "Discard did not remove the recovery file"
printf '%s\n' 'PASS: Discard preserved the note and removed its recovery file'
jq '.version = 6 | .shortcuts.maximize = "F11" | .spellcheck.enabled = false' \
  "$session_settings_path" >"$session_settings_path.tmp"
mv -- "$session_settings_path.tmp" "$session_settings_path"
run_stage shortcut-migrate
[[ "$(jq -r '.version' "$session_settings_path")" == "10" ]] || \
  fail "settings migration did not persist schema version 10"
[[ "$(jq -r '.shortcuts.maximize' "$session_settings_path")" == "Ctrl+F" ]] || \
  fail "shortcut migration did not persist Ctrl+F for Expand/Restore"
[[ "$(jq -r '.spellcheck.enabled' "$session_settings_path")" == "true" ]] || \
  fail "settings migration did not automatically enable spellcheck"
printf '%s\n' 'PASS: legacy settings migrated shortcuts and enabled spellcheck'
run_stage settings
[[ -d "$TEST_SETTINGS_DIR" ]] || \
  fail "settings did not create the configured default notes folder"
[[ "$(jq -r '.notesDirectory' "$session_settings_path")" == "$TEST_SETTINGS_DIR" ]] || \
  fail "settings did not persist the configured default notes folder"
[[ "$(jq -r '.sidePlacement' "$session_settings_path")" == "left" ]] || \
  fail "settings did not persist the left Side edge"
[[ "$(jq -r '.shortcuts.save' "$session_settings_path")" == "Alt+S" ]] || \
  fail "settings did not persist the custom Save shortcut"
[[ "$(jq -r '.shortcuts.find' "$session_settings_path")" == "Alt+Shift+F" ]] || \
  fail "settings did not persist the custom Find shortcut"
[[ "$(jq -r '.shortcuts.openRecent' "$session_settings_path")" == "Alt+R" ]] || \
  fail "settings did not persist the Open Most Recent shortcut"
[[ "$(jq -r '.shortcuts.clearRecent' "$session_settings_path")" == "Alt+Shift+R" ]] || \
  fail "settings did not persist the Clear Recent Files shortcut"
[[ "$(jq -r '.shortcuts.replace' "$session_settings_path")" == "Ctrl+H" ]] || \
  fail "settings did not persist the Replace shortcut"
[[ "$(jq -r '.shortcuts.goToLine' "$session_settings_path")" == "Ctrl+G" ]] || \
  fail "settings did not persist the Go to Line shortcut"
[[ "$(jq -r '.shortcuts.contextMenu' "$session_settings_path")" == "Shift+F10" ]] || \
  fail "settings did not persist the editor context-menu shortcut"
[[ "$(jq -r '.fileTabRows' "$session_settings_path")" == "4" ]] || \
  fail "settings did not persist the file-tab row count"
[[ "$(jq -r '.spellcheck.enabled' "$session_settings_path")" == "true" ]] || \
  fail "settings did not persist enabled bundled spellcheck"
[[ "$(jq -r '.spellcheck.language' "$session_settings_path")" == "en-US" ]] || \
  fail "settings did not persist the included spellcheck language"
printf '%s\n' 'PASS: settings persisted the folder, Side edge, shortcut, and file-tab rows'
run_stage settings-restore
run_stage recent-prepare
[[ "$(jq -r '.recentFiles | length' "$session_settings_path")" == "2" ]] || \
  fail "Recent Files did not persist two validated entries"
[[ "$(jq -r '.recentFiles[0]' "$session_settings_path")" == "$TEST_OPEN_NOTE" ]] || \
  fail "Recent Files did not persist MRU ordering"
[[ "$(jq -r --arg missing "$TEST_MISSING_NOTE" \
    '.recentFiles | index($missing)' "$session_settings_path")" == "null" ]] || \
  fail "Recent Files persisted a missing path"
printf '%s\n' 'PASS: Recent Files persisted MRU order without missing entries'
run_stage recent-restore
[[ "$(jq -r '.recentFiles | length' "$session_settings_path")" == "0" ]] || \
  fail "Clear Recent Files did not persist an empty history"
run_stage recent-clear-restore
printf '%s\n' 'PASS: Recent Files opening, clearing, and restart persistence completed'
run_stage tab-state-prepare "" "$TEST_TAB_STATE_FIRST"
editor_states_path="$TEST_HOME/.local/state/jotpin/editor-states.json"
[[ -f "$editor_states_path" ]] || \
  fail "per-tab editor state did not create its atomic state file"
jq -e --arg first "$TEST_TAB_STATE_FIRST" --arg second "$TEST_TAB_STATE_SECOND" \
  '(.version == 1) and
   ([.files[].path] | index($first) != null) and
   ([.files[].path] | index($second) != null) and
   ([.files[] | select(.path == $first) | .past | length][0] > 0) and
   ([.files[] | select(.path == $second) | .past | length][0] > 0)' \
  "$editor_states_path" >/dev/null || \
  fail "per-tab editor state did not persist both bounded undo histories"
[[ "$(<"$TEST_TAB_STATE_FIRST")" == A\ editor-state\ line\ 0* ]] || \
  fail "first tab did not save its final source"
[[ "$(<"$TEST_TAB_STATE_SECOND")" == B\ editor-state\ line\ 0* ]] || \
  fail "second tab did not save its final source"
printf '%s\n' 'PASS: per-tab editor state persisted both notes without mixing bytes'
run_stage tab-state-restore "" "$TEST_TAB_STATE_FIRST"
jq --arg first "$TEST_TAB_STATE_FIRST" \
  '(.files[] | select(.path == $first) | .past[-1].inserted) = "stale"' \
  "$editor_states_path" >"$editor_states_path.tmp"
mv -- "$editor_states_path.tmp" "$editor_states_path"
first_before_stale_check="$(<"$TEST_TAB_STATE_FIRST")"
run_stage tab-state-stale "" "$TEST_TAB_STATE_FIRST"
[[ "$(<"$TEST_TAB_STATE_FIRST")" == "$first_before_stale_check" ]] || \
  fail "rejecting stale undo history changed the note"
printf '%s\n' 'PASS: stale persisted undo history cannot overwrite changed note bytes'
printf '%s\n' 'PASS: complete offscreen save and recovery lifecycle'
