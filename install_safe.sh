#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly user_home="${HOME:?HOME is required}"
readonly INSTALL_DIR="$user_home/.config/omarchy/plugins/dev.jotpin"
readonly backup_root="$user_home/.local/state/jotpin/deploy-backups"
readonly hypr_config_dir="$user_home/.config/hypr"
readonly hypr_main_config="$hypr_config_dir/hyprland.lua"
readonly hypr_rule_path="$hypr_config_dir/jotpin.lua"
readonly hypr_bindings_path="$hypr_config_dir/bindings.lua"
readonly hypr_binding_module_path="$hypr_config_dir/jotpin_binding.lua"
readonly hypr_require='require("hypr.jotpin")'
readonly hypr_binding_require='require("hypr.jotpin_binding")'
readonly menu_config_dir="$user_home/.config/omarchy/extensions"
readonly menu_config_path="$menu_config_dir/omarchy-menu.jsonc"
readonly menu_template_path="$ROOT_DIR/omarchy-menu.jsonc"
readonly applications_dir="$user_home/.local/share/applications"
readonly desktop_entry_path="$applications_dir/dev.jotpin.desktop"
readonly desktop_entry_template="$ROOT_DIR/desktop/dev.jotpin.desktop"
readonly user_icon_dir="$user_home/.local/share/icons/hicolor/256x256/apps"
readonly user_icon_path="$user_icon_dir/dev.jotpin.png"
readonly default_notes_dir="$user_home/Documents/Notes"
readonly default_note_path="$default_notes_dir/welcome.md"
readonly welcome_note_template="$ROOT_DIR/welcome.md"
readonly allow_config_changes="${JOTPIN_ALLOW_CONFIG_CHANGES:-0}"
if [[ -f "$INSTALL_DIR/manifest.json" ]]; then
  readonly first_install=0
else
  readonly first_install=1
fi

fail() {
  printf 'Refusing JotPin deployment: %s\n' "$*" >&2
  exit 2
}

install_welcome_note() {
  local staged_note

  mkdir -m 700 -p -- "$default_notes_dir"
  staged_note="$(mktemp "$default_notes_dir/.welcome.md.jotpin.XXXXXX")"
  cp -- "$welcome_note_template" "$staged_note"
  chmod 0600 -- "$staged_note"

  if ln -T -- "$staged_note" "$default_note_path" 2>/dev/null; then
    printf '%s\n' "Created the first-run welcome note at $default_note_path."
  elif [[ -e "$default_note_path" || -L "$default_note_path" ]]; then
    printf '%s\n' "Kept the existing note unchanged at $default_note_path."
  else
    rm -f -- "$staged_note"
    fail "the first-run welcome note could not be created: $default_note_path"
  fi
  rm -f -- "$staged_note"
}

install_menu_entry() {
  local staged_menu

  mkdir -m 700 -p -- "$menu_config_dir"
  staged_menu="$(mktemp "$menu_config_dir/.omarchy-menu.jsonc.jotpin.XXXXXX")"
  if ! perl "$ROOT_DIR/scripts/merge_menu_jsonc.pl" \
      "$menu_config_path" "$menu_template_path" "$staged_menu"; then
    rm -f -- "$staged_menu"
    fail "the existing Omarchy menu extension could not be updated: $menu_config_path"
  fi

  if [[ -f "$menu_config_path" ]]; then
    chmod --reference="$menu_config_path" -- "$staged_menu"
  else
    chmod 0644 -- "$staged_menu"
  fi

  if cmp -s -- "$staged_menu" "$menu_config_path" 2>/dev/null; then
    rm -f -- "$staged_menu"
    printf '%s\n' 'The JotPin menu entry is already present.'
  else
    mv -- "$staged_menu" "$menu_config_path"
    printf '%s\n' \
      "Added JotPin to $menu_config_path (Personal > JotPin)."
  fi
}

install_desktop_entry() {
  install -d -m 0755 -- "$applications_dir" "$user_icon_dir"
  install -m 0644 -- "$desktop_entry_template" "$desktop_entry_path"
  install -m 0644 -- "$ROOT_DIR/assets/jotpin-icon.png" "$user_icon_path"
  printf '%s\n' 'Installed the JotPin desktop application and icon.'
}

install_default_binding_if_free() {
  local binding_output
  local staged_bindings
  local staged_module=""

  if ! command -v omarchy >/dev/null 2>&1; then
    printf '%s\n' \
      'SUPER + N was not changed: the effective Omarchy bindings could not be checked.'
    return 0
  fi

  if ! binding_output="$(omarchy menu keybindings --print 2>/dev/null)" || \
      [[ -z "$binding_output" ]]; then
    printf '%s\n' \
      'SUPER + N was not changed: the effective Omarchy bindings could not be checked.'
    return 0
  fi

  if rg -q -- '^SUPER \+ N([[:space:]]|/)' <<<"$binding_output"; then
    printf '%s\n' \
      'SUPER + N is already taken; leaving the existing binding unchanged.'
    return 0
  fi

  if [[ ! -f "$hypr_bindings_path" ]]; then
    printf '%s\n' \
      "SUPER + N was free, but $hypr_bindings_path does not exist; no binding was added."
    return 0
  fi

  if [[ -e "$hypr_binding_module_path" ]] && \
      ! cmp -s -- "$ROOT_DIR/hypr/jotpin_binding.lua" "$hypr_binding_module_path"; then
    printf '%s\n' \
      "SUPER + N was free, but $hypr_binding_module_path already contains different content; no binding was added."
    return 0
  fi

  if [[ ! -e "$hypr_binding_module_path" ]]; then
    staged_module="$(mktemp "$hypr_config_dir/.jotpin_binding.lua.jotpin.XXXXXX")"
    cp -- "$ROOT_DIR/hypr/jotpin_binding.lua" "$staged_module"
    chmod --reference="$hypr_bindings_path" -- "$staged_module"
  fi

  if ! rg -q -- '^[[:space:]]*require\("hypr\.jotpin_binding"\)' \
      "$hypr_bindings_path"; then
    staged_bindings="$(mktemp "$hypr_config_dir/.bindings.lua.jotpin.XXXXXX")"
    cp -p -- "$hypr_bindings_path" "$staged_bindings"
    perl -0pi -e \
      's/\z/\n\n-- JotPin default Markdown scratchpad binding.\nrequire("hypr.jotpin_binding")\n/' \
      "$staged_bindings"
    if ! luac -p "$staged_bindings"; then
      rm -f -- "$staged_bindings" "$staged_module"
      fail 'adding the default JotPin binding would make bindings.lua invalid'
    fi
    mv -- "$staged_bindings" "$hypr_bindings_path"
  fi

  if [[ -n "$staged_module" ]]; then
    mv -- "$staged_module" "$hypr_binding_module_path"
  fi

  printf '%s\n' 'Installed the default SUPER + N Markdown scratchpad binding.'
}

if [[ ${JOTPIN_ALLOW_DEPLOY:-0} != 1 ]]; then
  fail 'set JOTPIN_ALLOW_DEPLOY=1 only when you intentionally want to update the installed plugin'
fi

command -v omarchy-shell >/dev/null 2>&1 || \
  fail 'omarchy-shell is unavailable, so the live shell state cannot be checked'
command -v pgrep >/dev/null 2>&1 || \
  fail 'pgrep is unavailable, so the live shell state cannot be checked'

# A local plugin write is itself a hot-reload request. Never write the
# installed directory while the long-running Omarchy shell or any Quickshell
# process exists. The check fails closed if the shell state cannot be proved.
if omarchy-shell shell ping >/dev/null 2>&1; then
  fail 'omarchy-shell is running; deploy only while the shell is stopped'
fi
if pgrep -x quickshell >/dev/null 2>&1 || pgrep -x omarchy-shell >/dev/null 2>&1; then
  fail 'a Quickshell process is running; deploy only while Quickshell is stopped'
fi

for file in manifest.json EditorModel.js HtmlEntities.js SpellcheckModel.js \
    SyntaxHighlight.js JotPin.qml JotPinButton.qml HostIntegration.qml \
    NativeMarkdownDisplay.qml README.md PORTING.md LICENSE \
    THIRD_PARTY_NOTICES.md welcome.md assets/jotpin-icon.png \
    markdown/MarkdownParserWorker.js spellcheck/SpellcheckWorker.js \
    syntax/HighlightWorker.js \
    vendor/VERSIONS.json vendor/licenses/nspell-MIT.txt \
    vendor/licenses/is-buffer-MIT.txt \
    vendor/licenses/dictionary-en-MIT-BSD.txt \
    vendor/licenses/highlight.js-BSD-3-Clause.txt \
    vendor/licenses/highlightjs-gdscript-MIT.txt \
    vendor/licenses/micromark-mdast-MIT.txt; do
  [[ -f "$ROOT_DIR/$file" ]] || fail "source file is missing: $file"
done

if [[ "$allow_config_changes" == 1 ]]; then
  command -v rg >/dev/null 2>&1 || fail 'rg is required for optional configuration integration'
  command -v perl >/dev/null 2>&1 || fail 'perl is required for optional configuration integration'
  command -v luac >/dev/null 2>&1 || fail 'luac is required for optional configuration integration'
  for file in omarchy-menu.jsonc desktop/dev.jotpin.desktop \
      hypr/jotpin.lua hypr/jotpin_binding.lua \
      scripts/merge_menu_jsonc.pl; do
    [[ -f "$ROOT_DIR/$file" ]] || fail "source file is missing: $file"
  done
  [[ -f "$hypr_main_config" ]] || \
    fail "Hyprland user config is missing: $hypr_main_config"
  luac -p "$ROOT_DIR/hypr/jotpin.lua" || fail 'JotPin Hyprland rule is invalid Lua'
  luac -p "$ROOT_DIR/hypr/jotpin_binding.lua" || \
    fail 'JotPin default binding module is invalid Lua'
  perl -c "$ROOT_DIR/scripts/merge_menu_jsonc.pl" >/dev/null || \
    fail 'JotPin menu merge helper is invalid Perl'
elif [[ "$allow_config_changes" != 0 ]]; then
  fail 'JOTPIN_ALLOW_CONFIG_CHANGES must be 1 to grant consent or 0 to keep user configuration unchanged'
fi

mkdir -m 700 -p -- "$backup_root"
readonly backup_dir="$(mktemp -d \
  "$backup_root/$(date +%Y%m%d-%H%M%S).XXXXXX")"
if [[ -d "$INSTALL_DIR" ]]; then
  cp -a -- "$INSTALL_DIR" "$backup_dir/plugin"
fi
if [[ "$allow_config_changes" == 1 ]]; then
  cp -p -- "$hypr_main_config" "$backup_dir/hyprland.lua"
  if [[ -f "$hypr_rule_path" ]]; then
    cp -p -- "$hypr_rule_path" "$backup_dir/jotpin.lua"
  fi
  if [[ -f "$hypr_bindings_path" ]]; then
    cp -p -- "$hypr_bindings_path" "$backup_dir/bindings.lua"
  fi
  if [[ -f "$hypr_binding_module_path" ]]; then
    cp -p -- "$hypr_binding_module_path" "$backup_dir/jotpin_binding.lua"
  fi
  if [[ -f "$menu_config_path" ]]; then
    cp -p -- "$menu_config_path" "$backup_dir/omarchy-menu.jsonc"
  fi
  if [[ -f "$desktop_entry_path" ]]; then
    cp -p -- "$desktop_entry_path" "$backup_dir/dev.jotpin.desktop"
  fi
  if [[ -f "$user_icon_path" ]]; then
    cp -p -- "$user_icon_path" "$backup_dir/dev.jotpin.png"
  fi

  install_menu_entry
  install_desktop_entry
  install_default_binding_if_free

  mkdir -m 700 -p -- "$hypr_config_dir"
  cp -- "$ROOT_DIR/hypr/jotpin.lua" "$hypr_rule_path"
  if ! rg -Fq -- "$hypr_require" "$hypr_main_config"; then
    staged_hypr_config="$(mktemp "$hypr_config_dir/.hyprland.lua.jotpin.XXXXXX")"
    cp -p -- "$hypr_main_config" "$staged_hypr_config"
    perl -0pi -e \
      's/\z/\n-- JotPin native floating-window integration.\nrequire("hypr.jotpin")\n/' \
      "$staged_hypr_config"
    if ! luac -p "$staged_hypr_config"; then
      rm -f -- "$staged_hypr_config"
      fail 'installing the JotPin require would make hyprland.lua invalid'
    fi
    mv -- "$staged_hypr_config" "$hypr_main_config"
  fi
fi

mkdir -m 700 -p -- "$INSTALL_DIR"
mkdir -m 700 -p -- "$INSTALL_DIR/assets"
mkdir -m 700 -p -- "$INSTALL_DIR/markdown"
mkdir -m 700 -p -- "$INSTALL_DIR/spellcheck"
mkdir -m 700 -p -- "$INSTALL_DIR/syntax"
mkdir -m 700 -p -- "$INSTALL_DIR/vendor/licenses"
cp -- \
  "$ROOT_DIR/manifest.json" \
  "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/HtmlEntities.js" \
  "$ROOT_DIR/SpellcheckModel.js" \
  "$ROOT_DIR/SyntaxHighlight.js" \
  "$ROOT_DIR/JotPin.qml" \
  "$ROOT_DIR/JotPinButton.qml" \
  "$ROOT_DIR/HostIntegration.qml" \
  "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  "$ROOT_DIR/README.md" \
  "$ROOT_DIR/PORTING.md" \
  "$ROOT_DIR/LICENSE" \
  "$ROOT_DIR/THIRD_PARTY_NOTICES.md" \
  "$ROOT_DIR/welcome.md" \
  "$INSTALL_DIR/"
cp -- "$ROOT_DIR/assets/jotpin-icon.png" "$INSTALL_DIR/assets/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" "$INSTALL_DIR/markdown/"
cp -- "$ROOT_DIR/spellcheck/SpellcheckWorker.js" "$INSTALL_DIR/spellcheck/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$INSTALL_DIR/syntax/"
cp -- "$ROOT_DIR/vendor/VERSIONS.json" "$INSTALL_DIR/vendor/"
cp -- "$ROOT_DIR/vendor/licenses/"*.txt "$INSTALL_DIR/vendor/licenses/"

if (( first_install )); then
  install_welcome_note
fi

printf '%s\n' "Installed JotPin into $INSTALL_DIR."
if [[ "$allow_config_changes" == 1 ]]; then
  printf '%s\n' \
    "Installed the explicitly authorized floating-window rule into $hypr_rule_path." \
    "Installed the explicitly authorized menu integration into $menu_config_path." \
    "Installed the explicitly authorized desktop entry into $desktop_entry_path."
else
  printf '%s\n' \
    'User configuration was left unchanged.' \
    'Optional desktop app, menu, Hyprland rule, and keybinding integration requires JOTPIN_ALLOW_CONFIG_CHANGES=1.'
fi
printf '%s\n' \
  "Deployment backup: $backup_dir" \
  'No shell rescan or restart was run.' \
  'The installed manifest is on-demand and is not kept loaded persistently.'
