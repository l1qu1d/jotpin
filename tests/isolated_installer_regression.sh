#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-installer.XXXXXX)"
readonly TEST_BIN="$TEST_TMP_DIR/bin"

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -m 700 -p -- "$TEST_BIN"

for command in omarchy-shell pgrep; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$TEST_BIN/$command"
  chmod +x "$TEST_BIN/$command"
done

cat > "$TEST_BIN/omarchy" <<'OMARCHY'
#!/usr/bin/env bash

if [[ "$1" == "menu" && "$2" == "keybindings" && "$3" == "--print" ]]; then
  case "${JOTPIN_TEST_BINDING_STATE:-free}" in
    free)
      printf '%s\n' 'SUPER + RETURN                     → Terminal'
      exit 0
      ;;
    taken)
      printf '%s\n' 'SUPER + N                          → Existing user binding'
      exit 0
      ;;
    unknown)
      exit 1
      ;;
  esac
fi

exit 2
OMARCHY
chmod +x "$TEST_BIN/omarchy"

prepare_home() {
  local test_home="$1"
  local menu_shape="${2:-parent}"

  mkdir -m 700 -p \
    "$test_home/.config/hypr" \
    "$test_home/.config/omarchy/extensions"
  printf '%s\n' '-- isolated Hyprland entrypoint' > \
    "$test_home/.config/hypr/hyprland.lua"
  printf '%s\n' '-- isolated Hyprland bindings' > \
    "$test_home/.config/hypr/bindings.lua"

  case "$menu_shape" in
    parent)
      printf '%s\n' \
        '{' \
        '  // keep this comment' \
        '  "personal": {"icon":"x","label":"My Personal"}' \
        '}' > "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"
      ;;
    legacy)
      printf '%s\n' \
        '{' \
        '  // keep this comment' \
        '  "apps.jotpin": {"icon":"x","label":"JotPin","action":"omarchy-shell shell summon dev.jotpin"},' \
        '  "personal": {"icon":"x","label":"My Personal"},' \
        '  "personal.jotpin": {"icon":"x","label":"Existing JotPin","action":"custom-action"}' \
        '}' > "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"
      ;;
    empty)
      printf '%s\n' \
        '{' \
        '  // keep this comment' \
        '}' > "$test_home/.config/omarchy/extensions/omarchy-menu.jsonc"
      ;;
    *)
      fail "unknown menu fixture: $menu_shape"
      ;;
  esac
}

run_installer() {
  local test_home="$1"
  local binding_state="$2"
  local config_consent="${3:-0}"

  HOME="$test_home" \
    PATH="$TEST_BIN:$PATH" \
    JOTPIN_ALLOW_DEPLOY=1 \
    JOTPIN_ALLOW_CONFIG_CHANGES="$config_consent" \
    JOTPIN_TEST_BINDING_STATE="$binding_state" \
    bash "$ROOT_DIR/install_safe.sh" >/dev/null
}

readonly FREE_HOME="$TEST_TMP_DIR/free-home"
prepare_home "$FREE_HOME" parent
run_installer "$FREE_HOME" free

readonly FREE_INSTALL_DIR="$FREE_HOME/.config/omarchy/plugins/dev.jotpin"
for file in manifest.json EditorModel.js HtmlEntities.js SpellcheckModel.js \
    SyntaxHighlight.js JotPin.qml JotPinButton.qml HostIntegration.qml \
    NativeMarkdownDisplay.qml README.md PORTING.md LICENSE \
    THIRD_PARTY_NOTICES.md welcome.md; do
  cmp -s "$ROOT_DIR/$file" "$FREE_INSTALL_DIR/$file" || \
    fail "installed plugin file differs: $file"
done
for file in markdown/MarkdownParserWorker.js spellcheck/SpellcheckWorker.js \
    syntax/HighlightWorker.js \
    vendor/VERSIONS.json vendor/licenses/nspell-MIT.txt \
    vendor/licenses/is-buffer-MIT.txt \
    vendor/licenses/dictionary-en-MIT-BSD.txt \
    vendor/licenses/highlight.js-BSD-3-Clause.txt \
    vendor/licenses/highlightjs-gdscript-MIT.txt \
    vendor/licenses/micromark-mdast-MIT.txt; do
  cmp -s "$ROOT_DIR/$file" "$FREE_INSTALL_DIR/$file" || \
    fail "installed bundled language asset differs: $file"
done
cmp -s "$ROOT_DIR/assets/jotpin-icon.png" \
  "$FREE_INSTALL_DIR/assets/jotpin-icon.png" || \
  fail 'installed plugin icon differs'
readonly FREE_WELCOME_NOTE="$FREE_HOME/Documents/Notes/welcome.md"
cmp -s "$ROOT_DIR/welcome.md" "$FREE_WELCOME_NOTE" || \
  fail 'a first install did not create the welcome note exactly'
[[ "$(stat -c '%a' "$FREE_WELCOME_NOTE")" == 600 ]] || \
  fail 'the welcome note does not use private file permissions'
[[ ! -e "$FREE_HOME/Documents/Notes/scratchpad.md" ]] || \
  fail 'a first install still created a separate scratchpad'
[[ "$(cat "$FREE_HOME/.config/hypr/hyprland.lua")" == \
    '-- isolated Hyprland entrypoint' ]] || \
  fail 'deployment without config consent changed hyprland.lua'
[[ "$(cat "$FREE_HOME/.config/hypr/bindings.lua")" == \
    '-- isolated Hyprland bindings' ]] || \
  fail 'deployment without config consent changed bindings.lua'
[[ ! -e "$FREE_HOME/.config/hypr/jotpin.lua" ]] || \
  fail 'deployment without config consent installed a Hyprland rule'
[[ ! -e "$FREE_HOME/.config/hypr/jotpin_binding.lua" ]] || \
  fail 'deployment without config consent installed a binding module'
[[ ! -e "$FREE_HOME/.local/share/applications/dev.jotpin.desktop" ]] || \
  fail 'deployment without config consent installed a desktop entry'
[[ ! -e "$FREE_HOME/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png" ]] || \
  fail 'deployment without config consent installed an application icon'
if rg -q -- 'jotpin' "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  fail 'deployment without config consent changed the user menu'
fi

readonly DIRECTORY_HOME="$TEST_TMP_DIR/directory-home"
prepare_home "$DIRECTORY_HOME" empty
mkdir -m 700 -p -- "$DIRECTORY_HOME/Documents/Notes/welcome.md"
run_installer "$DIRECTORY_HOME" free
[[ -d "$DIRECTORY_HOME/Documents/Notes/welcome.md" ]] || \
  fail 'an existing welcome-note directory was replaced'
[[ -z "$(find "$DIRECTORY_HOME/Documents/Notes/welcome.md" -mindepth 1 -print -quit)" ]] || \
  fail 'the welcome-note installer wrote inside an existing directory'

run_installer "$FREE_HOME" free 1
cmp -s "$ROOT_DIR/hypr/jotpin.lua" "$FREE_HOME/.config/hypr/jotpin.lua" || \
  fail 'installed Hyprland rule differs from the checkout'
cmp -s "$ROOT_DIR/hypr/jotpin_binding.lua" \
  "$FREE_HOME/.config/hypr/jotpin_binding.lua" || \
  fail 'installed default binding module differs from the checkout'
cmp -s "$ROOT_DIR/desktop/dev.jotpin.desktop" \
  "$FREE_HOME/.local/share/applications/dev.jotpin.desktop" || \
  fail 'installed JotPin desktop entry differs from the checkout'
cmp -s "$ROOT_DIR/assets/jotpin-icon.png" \
  "$FREE_HOME/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png" || \
  fail 'installed Apps icon differs from the JotPin icon asset'
[[ "$(rg -Fc 'require("hypr.jotpin")' \
    "$FREE_HOME/.config/hypr/hyprland.lua")" == 1 ]] || \
  fail 'Hyprland module require was not installed exactly once'
[[ "$(rg -Fc 'require("hypr.jotpin_binding")' \
    "$FREE_HOME/.config/hypr/bindings.lua")" == 1 ]] || \
  fail 'default binding module require was not installed exactly once'
[[ "$(rg -Fc '"personal":' \
    "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'the existing Personal menu row was duplicated'
rg -Fq -- '"label":"My Personal"' \
  "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" || \
  fail 'the existing Personal menu row was overwritten'
[[ "$(rg -Fc '"personal.jotpin":' \
    "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'the JotPin menu row was not installed exactly once'
if rg -Fq '"apps.jotpin":' \
    "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  fail 'the glyph-only Apps JotPin row was installed alongside the desktop app'
fi
rg -Fq -- '"action":"omarchy-shell shell summon dev.jotpin"' \
  "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" || \
  fail 'the JotPin menu action is incorrect'

rm -f -- "$FREE_WELCOME_NOTE"
run_installer "$FREE_HOME" free 1
[[ ! -e "$FREE_WELCOME_NOTE" ]] || \
  fail 'a repeated deployment recreated a deleted welcome note'
[[ "$(rg -Fc 'require("hypr.jotpin")' \
    "$FREE_HOME/.config/hypr/hyprland.lua")" == 1 ]] || \
  fail 'a repeated deployment duplicated the Hyprland module require'
[[ "$(rg -Fc 'require("hypr.jotpin_binding")' \
    "$FREE_HOME/.config/hypr/bindings.lua")" == 1 ]] || \
  fail 'a repeated deployment duplicated the default binding require'
[[ "$(rg -Fc '"personal.jotpin":' \
    "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'a repeated deployment duplicated the JotPin menu row'
if rg -Fq '"apps.jotpin":' \
    "$FREE_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  fail 'a repeated deployment restored the retired glyph-only Apps row'
fi
cmp -s "$ROOT_DIR/desktop/dev.jotpin.desktop" \
  "$FREE_HOME/.local/share/applications/dev.jotpin.desktop" || \
  fail 'a repeated deployment changed the desktop entry'
cmp -s "$ROOT_DIR/assets/jotpin-icon.png" \
  "$FREE_HOME/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png" || \
  fail 'a repeated deployment changed the Apps icon'
[[ "$(find "$FREE_HOME/.local/state/jotpin/deploy-backups" \
    -mindepth 1 -maxdepth 1 -type d | wc -l)" == 3 ]] || \
  fail 'each deployment did not create its own backup directory'

readonly LEGACY_HOME="$TEST_TMP_DIR/legacy-home"
prepare_home "$LEGACY_HOME" legacy
run_installer "$LEGACY_HOME" free 1
[[ "$(rg -Fc '"personal.jotpin":' \
    "$LEGACY_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'an existing Personal JotPin row was duplicated during upgrade'
if rg -Fq '"apps.jotpin":' \
    "$LEGACY_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  fail 'the legacy glyph-only Apps row was not retired during upgrade'
fi
rg -Fq -- '"label":"Existing JotPin"' \
  "$LEGACY_HOME/.config/omarchy/extensions/omarchy-menu.jsonc" || \
  fail 'the existing Personal JotPin row was overwritten during upgrade'
cmp -s "$ROOT_DIR/assets/jotpin-icon.png" \
  "$LEGACY_HOME/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png" || \
  fail 'the legacy upgrade did not install the real Apps icon'

readonly TAKEN_HOME="$TEST_TMP_DIR/taken-home"
prepare_home "$TAKEN_HOME" empty
run_installer "$TAKEN_HOME" taken 1
[[ ! -e "$TAKEN_HOME/.config/hypr/jotpin_binding.lua" ]] || \
  fail 'an occupied SUPER + N still installed the default binding module'
if rg -q -- '^[[:space:]]*require\("hypr\.jotpin_binding"\)' \
    "$TAKEN_HOME/.config/hypr/bindings.lua"; then
  fail 'an occupied SUPER + N still installed the binding require'
fi
[[ "$(rg -Fc '"personal":' \
    "$TAKEN_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'the missing Personal menu parent was not installed'
[[ "$(rg -Fc '"personal.jotpin":' \
    "$TAKEN_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'the JotPin menu row was not installed for an occupied binding'
if rg -Fq '"apps.jotpin":' \
    "$TAKEN_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  fail 'an occupied binding installed the retired glyph-only Apps row'
fi
cmp -s "$ROOT_DIR/assets/jotpin-icon.png" \
  "$TAKEN_HOME/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png" || \
  fail 'an occupied binding prevented installation of the real Apps icon'

readonly UNKNOWN_HOME="$TEST_TMP_DIR/unknown-home"
prepare_home "$UNKNOWN_HOME" empty
run_installer "$UNKNOWN_HOME" unknown 1
[[ ! -e "$UNKNOWN_HOME/.config/hypr/jotpin_binding.lua" ]] || \
  fail 'an unverifiable SUPER + N still installed the default binding module'
if rg -q -- '^[[:space:]]*require\("hypr\.jotpin_binding"\)' \
    "$UNKNOWN_HOME/.config/hypr/bindings.lua"; then
  fail 'an unverifiable SUPER + N still installed the binding require'
fi
[[ "$(rg -Fc '"personal.jotpin":' \
    "$UNKNOWN_HOME/.config/omarchy/extensions/omarchy-menu.jsonc")" == 1 ]] || \
  fail 'the menu integration was skipped when binding detection was unavailable'
if rg -Fq '"apps.jotpin":' \
    "$UNKNOWN_HOME/.config/omarchy/extensions/omarchy-menu.jsonc"; then
  fail 'unknown binding state installed the retired glyph-only Apps row'
fi
cmp -s "$ROOT_DIR/assets/jotpin-icon.png" \
  "$UNKNOWN_HOME/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png" || \
  fail 'unknown binding state prevented installation of the real Apps icon'

printf '%s\n' \
  'PASS: guarded installer preserves user config without consent and gates optional integration'
