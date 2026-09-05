#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FIXTURE_PATH="$ROOT_DIR/tests/fixtures/source-preservation.md"
readonly COMMONMARK_FIXTURE_PATH="$ROOT_DIR/tests/fixtures/markdown-commonmark.md"
readonly GFM_FIXTURE_PATH="$ROOT_DIR/tests/fixtures/markdown-gfm.md"
readonly NAVIGATION_FIXTURE_PATH="$ROOT_DIR/tests/fixtures/list-navigation.md"
readonly SINGLE_LINE_CARET_FIXTURE_PATH="$ROOT_DIR/tests/fixtures/list-caret-single-line.md"
readonly PARAGRAPH_CARET_FIXTURE_PATH="$ROOT_DIR/tests/fixtures/paragraph-caret-soft-breaks.md"
readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-test-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-live-smoke.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/source-preservation.md"
readonly COMMONMARK_NOTE_PATH="$TEST_TMP_DIR/markdown-commonmark.md"
readonly GFM_NOTE_PATH="$TEST_TMP_DIR/markdown-gfm.md"
readonly NAVIGATION_NOTE_PATH="$TEST_TMP_DIR/list-navigation.md"
readonly SINGLE_LINE_CARET_NOTE_PATH="$TEST_TMP_DIR/list-caret-single-line.md"
readonly PARAGRAPH_CARET_NOTE_PATH="$TEST_TMP_DIR/paragraph-caret-soft-breaks.md"
readonly LIST_ENTRY_NOTE_PATH="$TEST_TMP_DIR/list-entry.md"
readonly SAVE_AS_NOTE_PATH="$TEST_TMP_DIR/renamed-note.md"
readonly RENAME_SOURCE_PATH="$TEST_TMP_DIR/rename-source.md"
readonly RENAME_TARGET_PATH="$TEST_TMP_DIR/renamed-inline.md"
QUICK_NEW_PATH=""
declare -a OVERFLOW_NOTE_PATHS=()

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v omarchy-shell >/dev/null 2>&1 || fail 'omarchy-shell is missing'
command -v grim >/dev/null 2>&1 || fail 'grim is missing'
command -v wtype >/dev/null 2>&1 || fail 'wtype is missing'

mkdir -p -- "$ARTIFACT_DIR"
cp -- "$FIXTURE_PATH" "$TEST_NOTE_PATH"
cp -- "$COMMONMARK_FIXTURE_PATH" "$COMMONMARK_NOTE_PATH"
cp -- "$GFM_FIXTURE_PATH" "$GFM_NOTE_PATH"
cp -- "$NAVIGATION_FIXTURE_PATH" "$NAVIGATION_NOTE_PATH"
cp -- "$SINGLE_LINE_CARET_FIXTURE_PATH" "$SINGLE_LINE_CARET_NOTE_PATH"
cp -- "$PARAGRAPH_CARET_FIXTURE_PATH" "$PARAGRAPH_CARET_NOTE_PATH"
cp -- "$FIXTURE_PATH" "$LIST_ENTRY_NOTE_PATH"
cp -- "$FIXTURE_PATH" "$RENAME_SOURCE_PATH"
for tab_index in $(seq 1 8); do
  overflow_path="$TEST_TMP_DIR/tab-${tab_index}-with-a-long-name-for-scroll.md"
  cp -- "$GFM_FIXTURE_PATH" "$overflow_path"
  OVERFLOW_NOTE_PATHS+=("$overflow_path")
done
readonly FIXTURE_HASH="$(sha256sum "$TEST_NOTE_PATH" | awk '{print $1}')"
readonly COMMONMARK_HASH="$(sha256sum "$COMMONMARK_NOTE_PATH" | awk '{print $1}')"
readonly GFM_HASH="$(sha256sum "$GFM_NOTE_PATH" | awk '{print $1}')"
readonly NAVIGATION_HASH="$(sha256sum "$NAVIGATION_NOTE_PATH" | awk '{print $1}')"
readonly SINGLE_LINE_CARET_HASH="$(sha256sum "$SINGLE_LINE_CARET_NOTE_PATH" | awk '{print $1}')"

close_plugin() {
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
}

move_right() {
  local count="$1"
  local step
  for step in $(seq 1 "$count"); do
    wtype -k Right
    sleep 0.02
  done
}

select_right() {
  local count="$1"
  local step
  for step in $(seq 1 "$count"); do
    wtype -M shift -k Right -m shift
    sleep 0.02
  done
}

cleanup() {
  local test_path
  for test_path in \
      "$TEST_NOTE_PATH" \
      "$COMMONMARK_NOTE_PATH" \
      "$GFM_NOTE_PATH" \
      "$NAVIGATION_NOTE_PATH" \
      "$SINGLE_LINE_CARET_NOTE_PATH" \
      "$PARAGRAPH_CARET_NOTE_PATH" \
      "$LIST_ENTRY_NOTE_PATH" \
      "$SAVE_AS_NOTE_PATH" \
      "$RENAME_SOURCE_PATH" \
      "$RENAME_TARGET_PATH"; do
    omarchy-shell shell call dev.jotpin closeFile "$test_path" \
      >/dev/null 2>&1 || true
  done
  for test_path in "${OVERFLOW_NOTE_PATHS[@]}"; do
    omarchy-shell shell call dev.jotpin closeFile "$test_path" \
      >/dev/null 2>&1 || true
  done
  if [[ -n "$QUICK_NEW_PATH" ]]; then
    omarchy-shell shell call dev.jotpin closeFile "$QUICK_NEW_PATH" \
      >/dev/null 2>&1 || true
  fi
  close_plugin
  if [[ -n "$QUICK_NEW_PATH" &&
        "$QUICK_NEW_PATH" == "$HOME/Documents/Notes"/untitled-*.md ]]; then
    rm -f -- "$QUICK_NEW_PATH"
  fi
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"side\",\"path\":\"$TEST_NOTE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin pluginId '{}' >/dev/null
grim "$ARTIFACT_DIR/jotpin-side.png"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin pluginId '{}' >/dev/null

wtype -M ctrl -k Home -m ctrl
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-caret-start.png"

move_right 2
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-caret-heading-start.png"

wtype -k End
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-caret-heading-end.png"

wtype -M ctrl -k Home -m ctrl
sleep 0.1
move_right 23
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-caret-bullet-start.png"

move_right 2
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-caret-bullet-text.png"

wtype -M ctrl -k Home -m ctrl
sleep 0.1
move_right 36
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-caret-nested-start.png"

grim "$ARTIFACT_DIR/jotpin-center.png"

wtype -M ctrl -k A -m ctrl
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-selection-all.png"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$NAVIGATION_NOTE_PATH\"}" \
  >/dev/null
sleep 1
wtype -M ctrl -k Home -m ctrl
sleep 0.1
move_right 14
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-list-cursor-t2.png"
wtype -M ctrl -k Home -m ctrl
sleep 0.1
select_right 7
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-list-selection-newlines.png"

close_plugin
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$SINGLE_LINE_CARET_NOTE_PATH\"}" \
  >/dev/null
sleep 1
wtype -M ctrl -k End -m ctrl
wtype -k Left
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-list-caret-single-line.png"
wtype x
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-list-caret-single-line-after-edit.png"
wtype -k BackSpace
sleep 0.2
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$SINGLE_LINE_CARET_NOTE_PATH\"}" \
  >/dev/null
sleep 0.5
wtype -M ctrl -k Home -m ctrl
move_right 4
wtype -k Return
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-caret-after-enter.png"
wtype -k BackSpace
sleep 0.2
close_plugin

close_plugin
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$PARAGRAPH_CARET_NOTE_PATH\"}" \
  >/dev/null
sleep 1
wtype -M ctrl -k A -m ctrl
sleep 0.1
wtype -k BackSpace
sleep 0.2
wtype 'test a'
sleep 0.2
wtype -k Return
sleep 0.2
wtype a
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-paragraph-caret-after-a1.png"
wtype -k Return
sleep 0.2
wtype a
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-paragraph-caret-after-a2.png"
wtype -k Return
sleep 0.2
wtype a
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-paragraph-caret-after-a3.png"
wtype -k Return
sleep 0.2
wtype a
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-paragraph-caret-after-a4.png"
wtype -k Return
sleep 0.2
wtype a
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-paragraph-caret-after-a5.png"
sleep 1
grim "$ARTIFACT_DIR/jotpin-save-caret-before.png"
wtype -M ctrl -k S -m ctrl
sleep 0.4
grim "$ARTIFACT_DIR/jotpin-save-caret-after.png"
paragraph_caret_source="$(<"$PARAGRAPH_CARET_NOTE_PATH")"
[[ "$paragraph_caret_source" == $'test a\na\na\na\na\na' ]] || \
  fail 'repeated Enter paragraph test did not preserve source line breaks'
wtype z
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-save-caret-after-z-immediate.png"
sleep 1
grim "$ARTIFACT_DIR/jotpin-save-caret-after-z-settled.png"
paragraph_caret_after_save_source="$(<"$PARAGRAPH_CARET_NOTE_PATH")"
[[ "$paragraph_caret_after_save_source" == $'test a\na\na\na\na\naz' ]] || \
  fail 'saving moved the caret or changed the paragraph source'

close_plugin
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$LIST_ENTRY_NOTE_PATH\"}" \
  >/dev/null
sleep 1
wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
wtype test
wtype -k Return
sleep 0.1
wtype -- -
grim "$ARTIFACT_DIR/jotpin-list-entry-after-marker-immediate.png"
sleep 0.3
grim "$ARTIFACT_DIR/jotpin-list-entry-after-marker.png"
wtype t
sleep 1
grim "$ARTIFACT_DIR/jotpin-list-entry-autocomplete.png"
close_plugin
list_entry_source="$(<"$LIST_ENTRY_NOTE_PATH")"
[[ "$list_entry_source" == $'test\n- t' ]] || \
  fail 'typing a bullet marker did not preserve a Markdown list source'

close_plugin
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$RENAME_SOURCE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin beginRenameFile "$RENAME_SOURCE_PATH" >/dev/null
sleep 0.2
grim "$ARTIFACT_DIR/jotpin-file-tab-rename.png"
omarchy-shell shell call dev.jotpin commitRenameFile "renamed-inline.md" >/dev/null
sleep 1
[[ -f "$RENAME_TARGET_PATH" ]] || fail 'inline rename did not create the renamed file'
[[ ! -e "$RENAME_SOURCE_PATH" ]] || fail 'inline rename left the old file in place'
rename_hash="$(sha256sum "$RENAME_TARGET_PATH" | awk '{print $1}')"
[[ "$rename_hash" == "$FIXTURE_HASH" ]] || \
  fail 'inline rename changed the Markdown source'

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$COMMONMARK_NOTE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin pluginId '{}' >/dev/null
grim "$ARTIFACT_DIR/jotpin-commonmark.png"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$GFM_NOTE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin pluginId '{}' >/dev/null
grim "$ARTIFACT_DIR/jotpin-gfm.png"
grim "$ARTIFACT_DIR/jotpin-file-tabs.png"
wtype -M ctrl -k A -m ctrl
sleep 0.1
grim "$ARTIFACT_DIR/jotpin-gfm-selection-all.png"

for overflow_path in "${OVERFLOW_NOTE_PATHS[@]}"; do
  omarchy-shell shell summon dev.jotpin \
    "{\"mode\":\"center\",\"path\":\"$overflow_path\"}" \
    >/dev/null
done
sleep 1
grim "$ARTIFACT_DIR/jotpin-file-tabs-overflow.png"

close_plugin
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin saveAsSelected "$SAVE_AS_NOTE_PATH" >/dev/null
sleep 1
save_as_hash="$(sha256sum "$SAVE_AS_NOTE_PATH" | awk '{print $1}')"
[[ "$save_as_hash" == "$FIXTURE_HASH" ]] || \
  fail 'Save As did not preserve the disposable Markdown source'
omarchy-shell shell call dev.jotpin closeFile "$SAVE_AS_NOTE_PATH" >/dev/null
sleep 0.5
[[ -f "$SAVE_AS_NOTE_PATH" ]] || fail 'closing a file tab removed the file from disk'

close_plugin
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" \
  >/dev/null
sleep 1
omarchy-shell shell call dev.jotpin openNewFile '{}' >/dev/null
sleep 1
QUICK_NEW_PATH="$(omarchy-shell shell call dev.jotpin currentNotePath '{}' | tr -d '\"')"
[[ "$QUICK_NEW_PATH" == "$HOME/Documents/Notes"/untitled-*.md ]] || \
  fail "New created the file outside the default notes folder: $QUICK_NEW_PATH"
[[ -f "$QUICK_NEW_PATH" ]] || fail 'New did not create a Markdown file'
[[ ! -s "$QUICK_NEW_PATH" ]] || fail 'New did not create a blank Markdown file'
grim "$ARTIFACT_DIR/jotpin-new-note.png"

close_plugin
actual_hash="$(sha256sum "$TEST_NOTE_PATH" | awk '{print $1}')"
if [[ "$actual_hash" != "$FIXTURE_HASH" ]]; then
  printf '%s\n' '--- disposable fixture diff ---' >&2
  diff -u "$FIXTURE_PATH" "$TEST_NOTE_PATH" >&2 || true
  fail 'visual smoke test changed the source-preservation fixture'
fi
commonmark_hash_after="$(sha256sum "$COMMONMARK_NOTE_PATH" | awk '{print $1}')"
[[ "$commonmark_hash_after" == "$COMMONMARK_HASH" ]] || \
  fail 'visual smoke test changed the CommonMark fixture'
gfm_hash_after="$(sha256sum "$GFM_NOTE_PATH" | awk '{print $1}')"
[[ "$gfm_hash_after" == "$GFM_HASH" ]] || \
  fail 'visual smoke test changed the GFM fixture'
navigation_hash_after="$(sha256sum "$NAVIGATION_NOTE_PATH" | awk '{print $1}')"
[[ "$navigation_hash_after" == "$NAVIGATION_HASH" ]] || \
  fail 'visual smoke test changed the list-navigation fixture'
single_line_caret_hash_after="$(sha256sum "$SINGLE_LINE_CARET_NOTE_PATH" | awk '{print $1}')"
[[ "$single_line_caret_hash_after" == "$SINGLE_LINE_CARET_HASH" ]] || \
  fail 'visual smoke test changed the two-item caret fixture'
printf 'PASS: live side, caret, center, CommonMark, GFM, selection, file-tab, and overflow-tab screenshots captured in %s\n' "$ARTIFACT_DIR"
printf 'PASS: list caret navigation, single-line caret, paragraph Enter caret, and newline selection screenshots captured; Save As preserved source; inline rename preserved contents; New created a blank file in ~/Documents/Notes\n'
printf 'PASS: visual smoke test preserved every fixture source\n'
