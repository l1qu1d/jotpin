#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly FIXTURE_DIR="$ROOT_DIR/tests/fixtures"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-test-suite.XXXXXX)"

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local description="$3"

  rg -Fq -- "$needle" "$file" || fail "$description (missing: $needle)"
  pass "$description"
}

assert_block_contains() {
  local block="$1"
  local needle="$2"
  local description="$3"

  rg -Fq -- "$needle" <<<"$block" || fail "$description (missing: $needle)"
  pass "$description"
}

assert_absent() {
  local file="$1"
  local needle="$2"
  local description="$3"

  if rg -Fq -- "$needle" "$file"; then
    fail "$description (found: $needle)"
  fi
  pass "$description"
}

assert_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local description="$4"
  local first_line
  local second_line

  first_line="$(rg -n -m1 -F -- "$first" "$file" | cut -d: -f1 || true)"
  second_line="$(rg -n -m1 -F -- "$second" "$file" | cut -d: -f1 || true)"
  [[ -n "$first_line" && -n "$second_line" &&
      "$first_line" -lt "$second_line" ]] || \
    fail "$description (expected '$first' before '$second')"
  pass "$description"
}

require_command omarchy
require_command md2html
require_command rg
require_command node
require_command luac
require_command lua
require_command perl

printf '%s\n' '== plugin validation =='
omarchy plugin validate "$ROOT_DIR"
pass 'manifest and plugin structure validate'
assert_contains "$ROOT_DIR/manifest.json" \
  '"id": "dev.jotpin"' \
  'the manifest uses the JotPin plugin id'
assert_contains "$ROOT_DIR/manifest.json" \
  '"name": "JotPin"' \
  'the manifest exposes the JotPin display name'
assert_contains "$ROOT_DIR/manifest.json" \
  '"panel": "JotPin.qml"' \
  'the manifest loads the renamed QML entry point'
[[ -f "$ROOT_DIR/preview.png" ]] || \
  fail 'the marketplace preview image is missing'
pass 'the marketplace preview image is present'
assert_contains "$ROOT_DIR/README.md" \
  '![JotPin preview](preview.png)' \
  'the README displays the marketplace preview'
[[ -f "$ROOT_DIR/assets/jotpin-icon.png" ]] || \
  fail 'the JotPin icon asset is missing'
pass 'the JotPin icon asset is present'
[[ -f "$ROOT_DIR/desktop/dev.jotpin.desktop" ]] || \
  fail 'the JotPin desktop entry is missing'
pass 'the JotPin desktop entry is present'
assert_contains "$ROOT_DIR/desktop/dev.jotpin.desktop" \
  'Icon=dev.jotpin' \
  'the desktop entry requests the installed JotPin application icon'
assert_contains "$ROOT_DIR/desktop/dev.jotpin.desktop" \
  'Exec=omarchy-shell shell summon dev.jotpin' \
  'the desktop entry summons JotPin through the shell'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'source: Qt.resolvedUrl("assets/jotpin-icon.png")' \
  'the header loads the JotPin icon beside its title'
assert_contains "$ROOT_DIR/LICENSE" \
  'GNU GENERAL PUBLIC LICENSE' \
  'the repository includes the GNU GPL license text'
assert_contains "$ROOT_DIR/LICENSE" \
  'Version 3, 29 June 2007' \
  'the repository includes GPL version 3'
assert_contains "$ROOT_DIR/README.md" \
  'GPL-3.0-only' \
  'the repository explicitly selects GPL version 3 only'
assert_contains "$ROOT_DIR/THIRD_PARTY_NOTICES.md" \
  'html.entities.html5' \
  'the generated entity table documents its external provenance'
assert_contains "$ROOT_DIR/README.md" \
  '## Requirements' \
  'the README documents runtime dependencies for submission'
assert_contains "$ROOT_DIR/README.md" \
  '## Update and remove' \
  'the README documents public installation and removal'
assert_contains "$ROOT_DIR/README.md" \
  'suggested global shortcut; it is added only when available.' \
  'the README recommends the collision-safe default JotPin shortcut'
assert_contains "$ROOT_DIR/README.md" \
  'The guarded installer preserves unrelated menu entries and refuses to take' \
  'the README promises not to replace an occupied shortcut'
assert_contains "$ROOT_DIR/README.md" \
  'press `SUPER + A`, search for `JotPin`' \
  'the README explains how to open JotPin from Apps'
assert_contains "$ROOT_DIR/README.md" \
  '## Platform support' \
  'the README documents the conditional future-shell roadmap'
assert_contains "$ROOT_DIR/README.md" \
  'Support for additional hosts will be documented as tested integrations become' \
  'the portability roadmap requires tested integrations before claiming support'
assert_contains "$ROOT_DIR/PORTING.md" \
  'Omarchy is the only supported host today.' \
  'the porting guide states the current support boundary'
assert_contains "$ROOT_DIR/PORTING.md" \
  '`hostIntegration` object' \
  'the porting guide documents the injectable host contract'
for portable_core in EditorModel.js SpellcheckModel.js NativeMarkdownDisplay.qml; do
  assert_absent "$ROOT_DIR/$portable_core" \
    'import qs.' \
    "$portable_core remains independent of Omarchy QML modules"
  assert_absent "$ROOT_DIR/$portable_core" \
    'import Quickshell' \
    "$portable_core remains independent of Quickshell host modules"
  assert_absent "$ROOT_DIR/$portable_core" \
    'Hyprland' \
    "$portable_core remains independent of Hyprland integration"
done

printf '%s\n' '== isolated editor model checks =='
node "$ROOT_DIR/tests/editor_model.test.cjs"
node "$ROOT_DIR/tests/spellcheck_model.test.cjs"

printf '%s\n' '== test harness safety checks =='
assert_contains "$ROOT_DIR/tests/run.sh" \
  'mode="${1:-headless}"' \
  'the default test runner is headless'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'JOTPIN_ALLOW_LIVE_TESTS' \
  'live runs require explicit opt-in'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'markdown_parser_regression.sh' \
  'the safe runner validates established Markdown parsing and HTML output'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'native_markdown_display_regression.sh' \
  'the safe runner validates the production RichText display'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'native_markdown_mouse_regression.sh' \
  'the safe runner validates clicks and selection below fenced code'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'jotpin_list_return_regression.sh' \
  'the safe runner recovers a native newline at a wrapped list-item end'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'native_markdown_parity.sh' \
  'the safe runner requires the complete legacy renderer behavior corpus'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'native_markdown_performance.sh' \
  'the safe runner validates production parse layout and geometry performance'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'isolated_installer_regression.sh' \
  'the safe runner includes isolated deployment checks'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'JOTPIN_ALLOW_DEPLOY' \
  'plugin deployment requires explicit opt-in'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'JOTPIN_ALLOW_CONFIG_CHANGES' \
  'user configuration changes require separate explicit consent'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'User configuration was left unchanged.' \
  'unconsented deployment reports that user configuration was preserved'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'omarchy-shell shell ping' \
  'plugin deployment checks the live shell before writing'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'pgrep -x quickshell' \
  'plugin deployment refuses any running Quickshell process'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'No shell rescan or restart was run.' \
  'plugin deployment never triggers a live shell reload'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'ln -T -- "$staged_note" "$default_note_path"' \
  'the welcome note is created without overwriting an existing note'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'if (( first_install )); then' \
  'upgrades do not recreate a deleted welcome note'
assert_contains "$ROOT_DIR/welcome.md" \
  '# Welcome to JotPin' \
  'the first-run welcome note introduces JotPin'
assert_contains "$ROOT_DIR/welcome.md" \
  '| `Ctrl+P` | Toggle Preview / Raw Markdown |' \
  'the first-run welcome note includes concise shortcut help'
assert_contains "$ROOT_DIR/welcome.md" \
  '## Try it right here' \
  'the welcome note invites hands-on Markdown exploration'
assert_contains "$ROOT_DIR/welcome.md" \
  '- [ ] Click a checkbox in Preview' \
  'the welcome note demonstrates interactive tasks'
assert_contains "$ROOT_DIR/welcome.md" \
  '## Tips' \
  'the welcome note provides practical workflow tips'
luac -p "$ROOT_DIR/hypr/jotpin.lua"
pass 'the JotPin Hyprland integration is valid Lua'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'class = "^org\\.quickshell$"' \
  'the floating rule is restricted to Quickshell windows'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'title = "^JotPin Window — .+$"' \
  'the centered floating rule is restricted to its JotPin title'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'float = true' \
  'window mode opens outside the tiled layout'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'center = true' \
  'window mode opens centered like the former overlay'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'title = "^JotPin Side (top|bottom|left|right) (left|right) — .+$"' \
  'side mode has bar-position- and edge-aware map-time rules'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'border_size = 0' \
  'side mode suppresses the compositor border'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'no_shadow = true' \
  'side mode suppresses floating-window shadow chrome'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'move = { "monitor_w-window_w", "monitor_h-window_h" }' \
  'a top bar places a right-mounted Side below its reserved work-area edge'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'move = { "0", "monitor_h-window_h" }' \
  'a top bar places a left-mounted Side below its reserved work-area edge'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'move = { "monitor_w-window_w", "0" }' \
  'non-top bars keep a right-mounted Side at the monitor top edge'
assert_contains "$ROOT_DIR/hypr/jotpin.lua" \
  'move = { "0", "0" }' \
  'non-top bars keep a left-mounted Side at the monitor top edge'
assert_absent "$ROOT_DIR/hypr/jotpin.lua" \
  'size = { 900, 700 }' \
  'Hyprland does not override the theme-scaled centered size'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'readonly hypr_rule_path="$hypr_config_dir/jotpin.lua"' \
  'guarded deployment installs the user-owned window rule'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'readonly hypr_require=' \
  'guarded deployment loads the JotPin Hyprland module'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'cp -p -- "$hypr_main_config" "$backup_dir/hyprland.lua"' \
  'guarded deployment backs up the Hyprland entrypoint'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'omarchy menu keybindings --print' \
  'guarded deployment checks the effective binding before claiming SUPER + N'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'install_menu_entry' \
  'guarded deployment installs the Omarchy menu entry'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'install_desktop_entry' \
  'guarded deployment installs the desktop application and icon'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'hypr_binding_require' \
  'guarded deployment installs the optional binding module require'
assert_contains "$ROOT_DIR/install_safe.sh" \
  'SUPER + N is already taken' \
  'guarded deployment leaves an occupied SUPER + N unchanged'
assert_absent "$ROOT_DIR/omarchy-menu.jsonc" \
  '"apps.jotpin"' \
  'the menu template leaves Apps to the icon-aware desktop entry'
assert_contains "$ROOT_DIR/omarchy-menu.jsonc" \
  '"personal.jotpin"' \
  'the menu template declares the JotPin row'
assert_contains "$ROOT_DIR/omarchy-menu.jsonc" \
  'omarchy-shell shell summon dev.jotpin' \
  'the menu template summons JotPin'
assert_contains "$ROOT_DIR/scripts/merge_menu_jsonc.pl" \
  '"apps\.jotpin"' \
  'the menu merge retires the legacy glyph-only Apps row'
luac -p "$ROOT_DIR/hypr/jotpin_binding.lua"
pass 'the optional JotPin default binding module is valid Lua'
lua "$ROOT_DIR/tests/jotpin_binding.test.lua" \
  "$ROOT_DIR/hypr/jotpin_binding.lua"
pass 'the JotPin binding waits for cross-workspace relocation before focus'
perl -c "$ROOT_DIR/scripts/merge_menu_jsonc.pl" >/dev/null
pass 'the Omarchy menu merge helper is valid Perl'
assert_absent "$ROOT_DIR/manifest.json" \
  '"keepLoaded": true' \
  'JotPin is not persistently loaded by the shell'
assert_contains "$ROOT_DIR/tests/lib/live_guard.sh" \
  'controls the active desktop' \
  'the live guard explains its interruption boundary'
for live_script in "$ROOT_DIR"/tests/live_*.sh; do
  assert_contains "$live_script" \
    'lib/live_guard.sh' \
    "$(basename "$live_script") is protected by the live guard"
done

printf '%s\n' '== presentation geometry checks =='
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property var hostIntegration: null' \
  'JotPin exposes an injectable host boundary'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.hostIntegration || builtinHostIntegration' \
  'Omarchy remains the default host integration'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'readonly property string barPosition: root.shell && root.shell.barConfig' \
  'the host adapter reads the configured Omarchy bar position'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'readonly property int liveBarSize: root.shell && root.shell.bar' \
  'the host adapter reads the live visible bar size'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'Math.max(0, Number(root.shell.bar.barSize) || 0)' \
  'the host adapter clamps the live bar size before using it'
assert_contains "$ROOT_DIR/tests/isolated_persistence_regression.sh" \
  'run_stage host-integration' \
  'offscreen persistence harness exercises the injectable host contract'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'shell.firstPartyServiceFor' \
  'editor code does not query Omarchy services directly'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'shell.hide(' \
  'editor code does not dismiss itself through an Omarchy API directly'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property int barClearance: root.liveBarSize' \
  'side mode uses only the live bar strip for outer clearance'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'sideEdgePadding' \
  'side mode does not add a separate screen-edge padding inset'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property int sideTopMargin: root.barPosition === "top"' \
  'a top bar clears the drawer top edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property int sideRightMargin: root.barPosition === "right"' \
  'a right bar clears the drawer right edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property int sideBottomMargin: root.barPosition === "bottom"' \
  'a bottom bar clears the drawer bottom edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property int sideLeftMargin: root.barPosition === "left"' \
  'a left bar clears the drawer left edge'
side_margin_block="$(sed -n \
  '/^[[:space:]]*readonly property int sideTopMargin:/,/^[[:space:]]*readonly property string home:/p' \
  "$ROOT_DIR/JotPin.qml")"
assert_block_contains "$side_margin_block" \
  ': 0' \
  'non-bar-facing drawer edges stay flush against the screen'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property bool screensaverActive:' \
  'the windows derive secure-surface visibility from the host contract'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'root.idleService.idledThisCycle' \
  'idle-cycle state hides the panel before the screensaver process starts'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'root.idleService.screensaverStartedThisCycle' \
  'screensaver launch state hides the panel before the saver window maps'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'Number(root.idleService.screensaverWindowCount) > 0' \
  'screensaver window state keeps the panel hidden while it is present'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'Boolean(root.lockService && root.lockService.locked)' \
  'lock state also keeps the overlay hidden'
assert_contains "$ROOT_DIR/HostIntegration.qml" \
  'Boolean(root.lockService && root.lockService.lockRequested)' \
  'pending lock state also keeps the overlay hidden'

card_geometry_block="$(sed -n \
  '/^[[:space:]]*id: card[[:space:]]*$/,/^[[:space:]]*id: content[[:space:]]*$/p' \
  "$ROOT_DIR/JotPin.qml")"
assert_block_contains "$card_geometry_block" \
  '(root.sideExpanded ? 0 : root.sideOuterMargin)' \
  'normal side width reserves the bar-facing edge while fullscreen fills its window'
assert_block_contains "$card_geometry_block" \
  'height: Math.max(0, parent.height - edgeGuard * 2)' \
  'the drawer preserves a neutral buffer edge during native resizing'
assert_block_contains "$card_geometry_block" \
  'anchors.topMargin: edgeGuard' \
  'the drawer does not rely on a transparent strip underneath the top bar'
assert_block_contains "$card_geometry_block" \
  'anchors.leftMargin: root.sideLeftMode && !root.sideExpanded' \
  'left-mounted Side reserves a left bar clearance'
assert_block_contains "$card_geometry_block" \
  'anchors.rightMargin: root.sideRightMode && !root.sideExpanded' \
  'right-mounted Side reserves a right bar clearance'
assert_block_contains "$card_geometry_block" \
  'padding: Style.spacing.panelPadding' \
  'the card uses shared theme panel padding'
assert_block_contains "$card_geometry_block" \
  ': Math.max(0, parent.width - edgeGuard * 2)' \
  'window mode follows the compositor-managed window width'
assert_block_contains "$card_geometry_block" \
  'height: Math.max(0, parent.height - edgeGuard * 2)' \
  'window mode follows the compositor-managed window height'
assert_block_contains "$card_geometry_block" \
  'anchors.centerIn: root.sideMode ? undefined : parent' \
  'window content does not inherit the drawer anchors'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'visible: root.opened && root.sideMode && !root.screensaverActive' \
  'the native side window unmaps while the screensaver or lock is active'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'title: "JotPin Side " + root.barPosition + " " + root.sidePlacement + " — " +' \
  'side mode exposes its bar position and drawer edge for map-time placement'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'implicitWidth: Style.space(480) + root.sideOuterMargin' \
  'side mode keeps the former theme-scaled drawer width and bar clearance'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '? Math.max(Style.space(360), screen.height - root.sideTopMargin -' \
  'side mode starts at the bar-reserved work-area height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'maximumSize: Qt.size(' \
  'side mode constrains normal resizing to its horizontal axis'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'visible: root.opened && root.windowMode && !root.screensaverActive' \
  'the centered native window follows JotPin and secure-surface visibility'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'implicitWidth: Style.space(900)' \
  'centered mode restores the former theme-scaled width'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'implicitHeight: Style.space(700)' \
  'centered mode restores the former theme-scaled height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'parent: root.sideMode ? sideWindow.contentItem : centerWindow.contentItem' \
  'one editor is reparented between both native window surfaces'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.sideLeftMode ? Qt.RightEdge : Qt.LeftEdge' \
  'Side exposes native horizontal resize from its outer edge'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'startSystemResize(Qt.TopEdge)' \
  'side mode does not expose a top-edge resize affordance'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'startSystemResize(Qt.BottomEdge)' \
  'side mode does not expose a bottom-edge resize affordance'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'PanelWindow {' \
  'both presentations remain native so compositor fullscreen controls either one'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'sequence: "Super+' \
  'JotPin does not hardcode compositor fullscreen or resize shortcuts'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'focus: root.opened && !root.screensaverActive' \
  'secure-surface state releases the shared focus scope'

content_geometry_block="$(sed -n \
  '/^[[:space:]]*id: content[[:space:]]*$/,/^[[:space:]]*id: header[[:space:]]*$/p' \
  "$ROOT_DIR/JotPin.qml")"
assert_block_contains "$content_geometry_block" \
  'anchors.topMargin: card.contentTopInset' \
  'panel padding reaches the content top through BorderSurface insets'
assert_block_contains "$content_geometry_block" \
  'anchors.rightMargin: card.contentRightInset' \
  'panel padding reaches the content right through BorderSurface insets'
assert_block_contains "$content_geometry_block" \
  'anchors.bottomMargin: card.contentBottomInset' \
  'panel padding reaches the content bottom through BorderSurface insets'
assert_block_contains "$content_geometry_block" \
  'anchors.leftMargin: card.contentLeftInset' \
  'panel padding reaches the content left through BorderSurface insets'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'leftPadding: Style.spacing.panelPadding' \
  'raw editor horizontal padding follows the active theme'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'topPadding: Style.spacing.panelPadding' \
  'raw editor vertical padding follows the active theme'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '? editor.cursorRectangle' \
  'the empty Live caret uses native editor line geometry'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'y: renderedEditor.y + editor.cursorRectangle.y' \
  'the empty editor helper shares the native caret origin'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: "Start writing your note…"' \
  'the empty editor helper explains how to begin a note'

printf '%s\n' '== source-preserving editor checks =='
assert_contains "$ROOT_DIR/JotPin.qml" \
  'import "EditorModel.js" as EditorModel' \
  'QML uses the shared pure editor model'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function horizontalListBoundaryTarget(source, value, direction, rawMode,' \
  'the isolated model owns live horizontal list navigation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.markdownSource = String(editor.text || "")' \
  'editor changes update the Markdown source'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'noteFile.setText(savedSource)' \
  'autosave writes the preserved Markdown source'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'atomicWrites: true' \
  'note and recovery writes use atomic FileView persistence'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property int saveDelayMs: 1500' \
  'normal autosave waits for an idle pause'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'interval: root.saveDelayMs' \
  'the normal save timer uses the configured idle delay'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property int recoveryIntervalMs: 10000' \
  'recovery snapshots have a maximum ten-second interval'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'interval: root.recoveryIntervalMs' \
  'the recovery timer uses the configured interval'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'root.saveTimer' \
  'save code never treats a lexical timer id as a root property'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'root.recoveryTimer' \
  'recovery code never treats a lexical timer id as a root property'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property string recoveryDirectory:' \
  'recovery snapshots stay in the user state directory'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function writeRecoverySnapshot()' \
  'dirty notes periodically write crash-recovery snapshots'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function checkRecoveryCandidate()' \
  'startup checks for an unsaved recovery snapshot'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function recoverSnapshot()' \
  'the recovery prompt can restore a snapshot'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function discardRecovery()' \
  'the recovery prompt can discard a snapshot'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function persistenceState()' \
  'offscreen behavior tests can inspect save completion state'

printf '%s\n' '== presentation mode persistence checks =='
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property string presentationSettingsPath:' \
  'presentation mode uses a dedicated persisted settings path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function loadPresentationSettings(rawValue)' \
  'presentation mode loads from disk when the panel is created'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function writePresentationSettings()' \
  'presentation mode has an explicit disk write path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'presentationSettingsFile.setText(desiredSettingsText)' \
  'presentation mode writes an atomic JSON preference'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function persistedOpenFilePaths()' \
  'the active file and open tabs have a persisted path model'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function restoreFileSession(storedOpenFiles, storedNotePath)' \
  'file tabs restore from the persisted session state'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'openFiles: root.persistedOpenFilePaths()' \
  'settings include the open file tabs'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'notePath: root.notePath' \
  'settings include the active file path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string pendingSessionPath: ""' \
  'explicit summon paths wait for settings hydration when needed'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'else root.pendingSessionPath = nextPath' \
  'explicit summon paths override a stored active file'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (currentSettingsText === desiredSettingsText)' \
  'identical settings do not strand a write in flight'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.setPresentationMode(mode)' \
  'summon payloads use the persisted presentation mode setter'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.setPresentationMode(root.sideMode ? "window" : "side")' \
  'the header toggle persists both presentation modes'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (mode === "center") mode = "window"' \
  'legacy center payloads remain compatible with native window mode'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.ensurePresentationSettingsDirectory()' \
  'presentation mode creates its state directory before writing'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string sidePlacement: "right"' \
  'Side placement defaults to the right edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function normalizedSidePlacement(value)' \
  'Side placement accepts only left or right'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sidePlacement: root.sidePlacement' \
  'settings persist the selected Side edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'else if (storedSidePlacement !== "")' \
  'settings hydrate an explicit Side edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property int fileTabRows: 2' \
  'file tabs default to two rows'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function normalizedFileTabRows(value)' \
  'file tab row settings have a normalization path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'Math.min(root.maximumFileTabRows, Math.round(rows))' \
  'file tab rows are capped at five'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'fileTabRows: root.fileTabRows' \
  'settings persist the selected file tab row count'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string defaultNotesDirectory: builtinNotesDirectory' \
  'the default notes folder is a user-adjustable setting'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function normalizedDirectoryPath(value)' \
  'settings validate the default notes folder path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function applyDefaultNotesDirectory(value)' \
  'settings can apply a new default notes folder'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileTabRowsHeading' \
  'settings expose the file-tab row count'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'model: root.maximumFileTabRows' \
  'settings offer every file-tab row count through five'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.setFileTabRows(index + 1)' \
  'settings apply the selected file-tab row count'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'notesDirectory: root.defaultNotesDirectory' \
  'settings persist the configured default notes folder'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: settingsButton' \
  'the header exposes a settings icon button'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'iconText: "󰒓"' \
  'the settings control uses a gear icon'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: settingsOverlay' \
  'the settings button opens an in-plugin settings surface'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'text: "Presentation"' \
  'settings no longer exposes presentation mode controls'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: settingsScrollView' \
  'settings use a scroll view for the complete settings surface'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property var shortcutSettingEntries:' \
  'settings expose the editable JotPin command shortcut model'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function normalizedShortcut(value)' \
  'shortcut input is normalized before it is applied'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function applyShortcut(id, value)' \
  'settings can apply an individual keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'fixedShortcutValues.indexOf(value) >= 0' \
  'configurable commands cannot replace fixed editor shortcuts'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'defaultShortcutValue(ids[defaultIndex]) === next' \
  'persisted shortcuts cannot displace defaults added by an upgrade'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string shortcutMaximize: "Ctrl+F"' \
  'Expand and Restore share the requested Ctrl+F shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function migratedShortcutSettings(storedVersion, stored)' \
  'legacy F11 settings use a scoped shortcut migration'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'shortcuts: {' \
  'settings persist the editable command shortcut map'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string shortcutFind: "Ctrl+Shift+F"' \
  'Find keeps Ctrl+F reserved for Full Screen'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string shortcutReplace: "Ctrl+H"' \
  'Find and Replace has a configurable default shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string shortcutGoToLine: "Ctrl+G"' \
  'Go to Line has a configurable default shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string shortcutNextFile: "Ctrl+Right"' \
  'Ctrl+Right switches to the next note tab by default'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string shortcutPreviousFile: "Ctrl+Left"' \
  'Ctrl+Left switches to the previous note tab by default'

printf '%s\n' '== Markdown file policy checks =='
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function isMarkdownPath(value)' \
  'all note paths have a Markdown extension policy'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function normalizedMarkdownPath(value, appendMissingExtension)' \
  'file paths can append .md without accepting other extensions'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'return root.normalizedMarkdownPath(value, false)' \
  'internal file switching rejects non-Markdown paths'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function markdownFileNameForInput(value)' \
  'filename inputs normalize to the Markdown suffix'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleHeadingSpace()' \
  'Live heading markers accept their required separator Space'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'EditorModel.headingBackspace(' \
  'Live Backspace does not reinterpret literal heading source edits'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function submitFileChooser(value)' \
  'Open and Save As share filename validation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.statusText = "Markdown files must end in .md"' \
  'summon payloads reject non-Markdown extensions'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.fileChooserMessage = "Markdown files must end in .md"' \
  'file chooser operations reject non-Markdown extensions'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.saveAsName = root.markdownStemForPath(root.notePath)' \
  'Save As edits the filename stem beside a fixed suffix'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.renameValue = root.markdownStemForPath(nextPath)' \
  'inline rename edits only the filename stem'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'id: renameExtension' \
  'inline rename hides the automatic Markdown suffix'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: markdownExtension' \
  'Save As displays a fixed Markdown suffix'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: root.markdownStemForPath(modelData.path)' \
  'file tabs hide the Markdown suffix from their labels'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.markdownStemForPath(modelData.path) +' \
  'file tab close tooltips also use the filename stem'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: "Recover unsaved changes?"' \
  'the recovery prompt is visible to the user'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'enabled: !root.loadingFromFile && !root.recoveryPromptOpen' \
  'the recovery prompt blocks editing until it is resolved'
assert_contains "$ROOT_DIR/tests/isolated/jotpin_link_keys.qml" \
  'test_zzzz_save_keeps_newer_selection' \
  'saving is tested against a newer user selection'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sourceText: editor.text' \
  'live rendering consumes the current editor text'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'baseUrl: root.fileUrlForPath(root.noteDirectory + "/")' \
  'live Markdown images resolve relative to the active note'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function resizeMarkdownImage(sourceStart, sourceEnd, width)' \
  'image corner resizing commits through the source-preserving editor path'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function resizeMarkdownImage(sourceValue, imageStartValue, imageEndValue,' \
  'image resize metadata is a pure tested source transition'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function tableToolbarState(sourceValue, value, rawMode)' \
  'the contextual table helper derives from the active source cell'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function tableStructuralEdit(sourceValue, value, actionValue, rawMode)' \
  'table helper actions are pure atomic source transitions'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: tableHelperBar' \
  'Preview exposes the contextual table helper row'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'parent: editorViewport.contentItem' \
  'the table helper scrolls as part of the editor document'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property real tableGap: 4' \
  'the table helper keeps four pixels above the table'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'x: visible ? Number(tableSlotGeometry.x) : 0' \
  'the table helper aligns to the rendered table slot left edge'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '? 22 : buttonHeight * 2' \
  'the single-row table helper stays vertically compact'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'tableContentStart: context.region.rows[0].spans[0].start' \
  'table helper geometry anchors to rendered header content instead of syntax'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'table.jotpin-table-helper-space' \
  'the native document uses a non-collapsing helper spacer before the table'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'tooltipText: "Insert row above"' \
  'the table helper can insert a row above'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'tooltipText: "Insert row below"' \
  'the table helper can insert a row below'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.performTableAction("columnBefore")' \
  'the table helper can insert a column to the left'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.performTableAction("columnAfter")' \
  'the table helper can insert a column to the right'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.performTableAction("rowDelete")' \
  'the table helper can delete the active body row'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.performTableAction("columnDelete")' \
  'the table helper can delete the active column'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.performTableAction("tableDelete")' \
  'the table helper can delete the complete table'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'contextual table helper follows only a caret inside its table' \
  'the offscreen product harness checks caret-scoped placement and undo'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'NativeMarkdownDisplay {' \
  'live output uses the native Qt Markdown renderer'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'textFormat: TextEdit.RichText' \
  'native Live output delegates rich document layout to Qt'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'source: Qt.resolvedUrl("markdown/MarkdownParserWorker.js")' \
  'native Live source mapping uses the bundled established parser'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function tryApplyOptimisticPlainEdit(nextSourceValue)' \
  'ordinary held-key edits paint before the authoritative parse completes'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function optimisticHeadingFormat(sourceValue, sourcePosition,' \
  'heading characters receive their known title format before first paint'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'optimistic title character immediately inherits heading format' \
  'the renderer tests immediate typing format for all six heading levels'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function scheduleDeferredParse()' \
  'continuous key repeat cannot postpone authoritative parsing indefinitely'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function blankLineSourcePositionForPoint(nativeSourcePositionValue,' \
  'native pointer mapping preserves reachable blank source rows'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'Down enters the paragraph-to-fence blank row' \
  'the renderer checks keyboard and pointer access at a block boundary'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'insertedIsLineBreakRun' \
  'pure repeated line edits paint optimistically before parser reconciliation'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'if (results[pendingIndex] === undefined) return false' \
  'syntax-highlighted code never paints a fallback frame between revisions'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'codeFallbackPaintsDuringTyping' \
  'the native renderer counts intermediate code fallback paints while typing'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (!liveCursorGeometrySettle.running)' \
  'rapid layout updates retain a bounded visible-caret frame deadline'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function sourceRangeTouchesImageResizeMetadata(sourceValue, startValue,' \
  'image width metadata never enters the optimistic visible-text path'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function sourceRangeTouchesImageProjection(startValue, endValue)' \
  'projected image edits wait for authoritative rich layout'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function tryApplyOptimisticFenceLanguageEdit(previousSourceValue,' \
  'fence-language edits have a dedicated styled projection path'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function codeLanguageCursorRectangle(sourcePositionValue)' \
  'fence-language carets remain on their projected header row'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'Number(codeDocumentPosition) - 1' \
  'language mapping cannot match the same prefix in the first code row'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function codeLanguageProjection(value)' \
  'unlabeled fences expose a projected editable language slot'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'type === "blank"' \
  'source-only blank rows participate in native document mapping'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  '.jotpin-inline-code' \
  'inline code retains the established accent treatment'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  '.jotpin-code-block td' \
  'fenced code retains its dedicated card treatment'
assert_contains "$ROOT_DIR/scripts/vendor/markdown-entry.mjs" \
  'padding-top:JOTPIN_QUOTE_GAPpx' \
  'intentional blank quote rows retain compact vertical separation'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'nested quote text is not indented and vertically separated' \
  'the production renderer measures nested quote spacing'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function registerRenderedMousePress(sourcePosition)' \
  'native Live click tracking preserves triple-click row selection'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function linkSourceUrl(value)' \
  'native Live links resolve note-relative and home-relative targets'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function linkTargetForPoint(localX, localY)' \
  'native Live links translate pointer coordinates into document hit tests'
assert_absent "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function linkTargetForSourcePosition' \
  'link activation does not infer painted anchors from raw source positions'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'signal linkActivated(string target)' \
  'native link activation is observable without launching an external app'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onLinkActivated: function(target)' \
  'the product shell handles validated native link activation'
assert_contains "$ROOT_DIR/tests/isolated/tst_native_markdown_mouse.qml" \
  'Ctrl+click emits one link activation' \
  'the pointer harness exercises the complete modified-click behavior'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function rebuildImageRects()' \
  'native Live images expose geometry from their rich-text objects'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function setImageLoadState(indexValue, requestIdValue, urlValue,' \
  'native Live images react to actual asynchronous load outcomes'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'Image cannot be displayed.' \
  'failed native images render an explicit textual fallback'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  '{name: "topLeft", left: true, top: true}' \
  'selected Live images expose a top-left resize box'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  '{name: "bottomRight", left: false, top: false}' \
  'selected Live images expose a bottom-right resize box'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'root.endImageResize(true)' \
  'image resize source changes are committed only on handle release'
assert_contains "$ROOT_DIR/scripts/vendor/markdown-entry.mjs" \
  'jotpin:image[ \t]+width' \
  'the parser recognizes only narrowly scoped portable image width metadata'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'z: 1' \
  'rendered glyphs paint above source selection rectangles'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'checkBlankRowGeometry()' \
  'the production renderer test covers leading, inter-block, and trailing rows'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'checkVisualContract()' \
  'the production renderer test locks the established visual treatment'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'checkImageResizeContract()' \
  'the production renderer test covers all four image resize corners'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'checkFailedImageContract()' \
  'the production renderer test covers actual failed-image fallback behavior'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'image width digits never flash in the native document' \
  'the production renderer test covers repeated image resize metadata edits'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'image alt text waits for styled rendering without a size flash' \
  'the production renderer test covers image alt-text format inheritance'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  'fence-language repeat paints styled text and caret before parsing' \
  'the production renderer tests every in-flight fence-language edit'
assert_contains "$ROOT_DIR/tests/isolated/tst_native_markdown_mouse.qml" \
  'function test_drag_selects_code_language()' \
  'the production pointer test actually drag-selects a fence language'
assert_contains "$ROOT_DIR/tests/isolated/tst_native_markdown_mouse.qml" \
  'function test_drag_selects_code_language_after_styled_edit()' \
  'the production pointer test selects a language after immediate styling'
assert_contains "$ROOT_DIR/tests/isolated/tst_native_markdown_mouse.qml" \
  'function test_clicks_empty_code_language_slot()' \
  'the production pointer test enters an unlabeled fence header'
parity_fixture_count="$(rg -c '^[[:space:]]+makeCase\("' \
  "$ROOT_DIR/tests/isolated/native_markdown_parity.qml")"
[[ "$parity_fixture_count" -eq 88 ]] || \
  fail "the native parity gate has $parity_fixture_count fixtures; expected 88"
pass 'the native parity gate declares all 76 legacy fixtures and twelve focused regressions'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'fenced-code-trailing-space-row' \
  'the native parity gate covers editable fenced-code whitespace rows'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'code-language-mouse-hit' \
  'the native parity gate covers source-mapped language-label clicks'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'new-empty-bullet-caret' \
  'the native parity gate keeps a continued empty-list caret on its own row'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'wrapped-nested-list-item' \
  'the native parity gate checks hanging indentation for nested list wrapping'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'new-empty-bullet-before-existing-item' \
  'the native parity gate keeps an inserted bullet before the next list item'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'stranded-blank-list-return-stability' \
  'the native parity gate prevents a raw marker flash for the escaped list case'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'wrapped-list-end-click-before-existing-item' \
  'the native parity gate maps a wrapped item end before the next list item'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'empty-fence-language-slot' \
  'the native parity gate covers an empty editable fence-language slot'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'empty-code-row-after-language' \
  'the native parity gate keeps an empty code row below its language header'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'blank-lines-before-fenced-code-selection' \
  'the native parity gate keeps both selected blank rows visible before a code card'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'final-line-bottom-padding' \
  'the native parity gate keeps the final rendered row fully above the editor edge'
assert_contains "$ROOT_DIR/tests/live_fence_language_enter_regression.sh" \
  'wtype -k Return' \
  'the focused live fence test routes a physical Enter through Wayland'
assert_contains "$ROOT_DIR/tests/live_fence_language_enter_regression.sh" \
  'renderedCursorY > 0' \
  'the focused live fence test checks visible code-row caret geometry'
assert_contains "$ROOT_DIR/tests/live_fence_language_enter_regression.sh" \
  'Down could not escape to the editable line after the closing fence' \
  'the focused live fence test requires keyboard escape below the code block'
assert_contains "$ROOT_DIR/tests/live_key_repeat_rows_regression.sh" \
  'visible_count < 3' \
  'the focused live repeat test requires visible intermediate row updates'
assert_contains "$ROOT_DIR/tests/live_fence_language_repeat_regression.sh" \
  'observe_held_language_key z language-held-letter' \
  'the focused live fence test holds a physical language character'
assert_contains "$ROOT_DIR/tests/live_fence_language_repeat_regression.sh" \
  'observe_held_language_key BackSpace language-held-backspace' \
  'the focused live fence test holds physical Backspace in the language row'
assert_contains "$ROOT_DIR/tests/live_fence_language_repeat_regression.sh" \
  'visible_count < 3' \
  'the focused live fence test requires intermediate rendered revisions'
assert_contains "$ROOT_DIR/tests/live_fence_language_repeat_regression.sh" \
  '.codeHighlightPendingCount == 0' \
  'the focused live fence test settles fixture layout before key repeat'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_parity.qml" \
  'selection-performance' \
  'the native parity gate covers the legacy large-selection workload'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'native_markdown_display_regression.sh' \
  'the safe runner checks the production native Live renderer'
assert_contains "$ROOT_DIR/tests/run.sh" \
  'native_markdown_caret_matrix.sh' \
  'the safe runner checks rapid caret stability across Markdown contexts'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_caret_matrix.qml" \
  'rapidEditsPerCase: 24' \
  'the caret matrix checks insertion and deletion before parser settling'
assert_contains "$ROOT_DIR/tests/isolated/native_markdown_performance.qml" \
  '100 * 1024' \
  'the production performance gate includes a large-note workload'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onReadyChanged: root.flushSpellcheckInitialization()' \
  'spellcheck initialization waits for the worker to be established'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: spellcheckButton' \
  'the header exposes an icon-only spellcheck toggle'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'iconText: "󰓆"' \
  'the spellcheck toggle keeps one stable icon'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'foreground: root.spellcheckEnabled ? root.foreground' \
  'enabled spellcheck uses the same color as neighboring buttons'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'selected: false' \
  'the spellcheck toggle does not use button highlighting for state'
assert_contains "$ROOT_DIR/JotPinButton.qml" \
  'if (control.activeFocus) control.focus = false' \
  'JotPin buttons release retained focus after activation'
if rg -q '(^|[^[:alnum:]_])Button[[:space:]]*\{' "$ROOT_DIR/JotPin.qml"; then
  fail 'a JotPin button bypasses the non-retaining button component'
fi
pass 'every JotPin button uses the non-retaining focus behavior'
assert_absent "$ROOT_DIR/JotPin.qml" \
  '󰅙' \
  'the spellcheck Off state no longer uses the rejected X icon'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'interval: root.spellcheckDelayMs' \
  'spellcheck waits for the configured idle debounce'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onNotePathChanged: {' \
  'file switches clear spelling marks from the previous note'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.invalidateSpellcheckForSourceChange(' \
  'source edits queue an incremental worker check'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (root.spellingGeometryDeferred && forceValue !== true) return' \
  'typing defers whole-layer spelling geometry publication'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'model: spellingUnderlineVisualModel' \
  'spelling result updates preserve existing underline delegates'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'request.source = String(editor.text || "")' \
  'spellcheck sends source extraction and dictionary work off the UI thread'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'SpellcheckModel.validatedMisspellings(' \
  'worker results must match their extracted candidates before painting'
assert_contains "$ROOT_DIR/scripts/build_vendor_bundles.mjs" \
  "'SpellcheckWorkerRuntime.js'), 'utf8')" \
  'vendor regeneration embeds the incremental spellcheck runtime'
assert_contains "$ROOT_DIR/scripts/SpellcheckWorkerRuntime.js" \
  'jotpinApplyPatch(edits[editIndex], metrics)' \
  'vendor regeneration preserves worker-side incremental patching'
assert_contains "$ROOT_DIR/scripts/SpellcheckWorkerRuntime.js" \
  'var jotpinBundledWords = [' \
  'the spellcheck runtime declares bundled project vocabulary'
assert_contains "$ROOT_DIR/spellcheck/SpellcheckWorker.js" \
  "'Omarchy', 'omarchy'" \
  'the installed spellcheck worker accepts Omarchy'
assert_contains "$ROOT_DIR/spellcheck/SpellcheckWorker.js" \
  "'JotPin', 'jotpin'" \
  'the installed spellcheck worker accepts JotPin'
assert_contains "$ROOT_DIR/spellcheck/SpellcheckWorker.js" \
  'var jotpinCorrectCacheLimit = 4096' \
  'the spelling correctness cache has a fixed memory bound'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (!root.spellcheckEnabled ||' \
  'disabled spellcheck rejects an in-flight worker result'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function selectionRangeRectangles()' \
  'Live selection geometry has a viewport-aware rendering path'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'nativeDocument.select(0, nativeDocument.length)' \
  'Ctrl+A delegates complete rendered selection painting to QTextEdit'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'selectionRenderingEnabled: !root.rawMode' \
  'Raw mode does not build hidden Live selection geometry'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'textFormat: TextEdit.PlainText' \
  'editing uses an unmodified source-text layer'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'cursorRectangleForSource' \
  'live caret maps source positions to rendered positions'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function completeListMarker()' \
  'typing a list marker completes the required Markdown separator'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function completeCodeFence(currentValue, previousValue, value)' \
  'typing a line-start triple backtick completes a Markdown fence'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'var trailingNewline = suffix.indexOf("\r\n") === 0' \
  'auto-completed fences expose a trailing escape line'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'newline + newline + closeText + suffix' \
  'auto-completed fences reserve an empty body row before the closer'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function completeCodePair(currentValue, previousValue, value, pairs)' \
  'typing code delimiters inside a fence adds generated closing pairs'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function codeTagCompletion(sourceValue, context, cursor)' \
  'markup-language fences receive matching closing tags'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function backspaceAutoCodeFence(sourceValue' \
  'Backspace can remove a generated Markdown fence closer'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'remainingMarkerLength' \
  'generated fence Backspace cannot expose a partial opener'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function backspaceAutoCodePair(sourceValue' \
  'Backspace can remove an untouched generated code pair'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function backspaceEmptyCodePair(sourceValue' \
  'Backspace can reconstruct an empty fenced-code pair after tab tracking is lost'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'Backspace removes an empty code pair after tab tracking is lost' \
  'the product harness covers the exact untracked multiline brace regression'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function backspaceOrphanCodeFence(sourceValue' \
  'Backspace can remove an orphaned generated fence after tracking is lost'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'Backspace removes the orphaned bottom fence after tracking is lost' \
  'the product harness covers the exact orphaned bottom-fence regression'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function trackAutoCodeFenceEdit(previousValue' \
  'generated fence tracking follows edits before the closer'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function trackAutoCodePairEdit(previousValue' \
  'generated code pairs track edits before their closers'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function completeCodeFence()' \
  'QML applies Markdown fence completion to live and raw editing'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.autoFenceCloseText = String(result.closeText || "")' \
  'generated fence tracking includes the escape line'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function completeCodePair()' \
  'QML applies code-pair completion to live and raw editing'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (!root.completeCodeFence()) {' \
  'fence completion runs before list-marker completion'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.replaceEditorDocumentText(result.source, result.cursor)' \
  'list-marker completion preserves the cursor position'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'editor.cursorSelection.text = nextSource.slice(prefix, nextEnd)' \
  'custom edits preserve the native TextEdit undo stack'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleListReturn()' \
  'Enter has dedicated Markdown list continuation behavior'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function recoverNativeListReturn(' \
  'a native newline is recovered when Return should continue a list'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function normalizeLiveReturnCursor()' \
  'Return restores the source position represented by the visible caret'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'EditorModel.liveReturnSourcePosition(' \
  'the real Return key path uses the tested live-caret correction'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handlePlainReturn()' \
  'ordinary Enter has an explicit source-preserving path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleFenceHeaderReturn()' \
  'Preview Enter can leave a projected fence-language row'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.handleFenceHeaderReturn() ||' \
  'fence-language Enter is handled before source newline insertion'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function plainReturn(sourceValue' \
  'the editor model owns ordinary newline insertion'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function fenceHeaderReturn(sourceValue' \
  'the editor model owns fence-language row entry'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function fenceBodyBackspace(sourceValue' \
  'the editor model owns empty generated code-row Backspace navigation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleBackspace()' \
  'Backspace has a source-preserving editor transition'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'EditorModel.fenceBodyBackspace(' \
  'Preview Backspace crosses an empty generated code-row boundary safely'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleEditorHistoryKey(event)' \
  'undo and redo have a dedicated focused-editor key route'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'event.key === Qt.Key_Z && !shift' \
  'Ctrl+Z is intercepted before the native TextEdit undo stack'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'event.key === Qt.Key_Y && !shift' \
  'Ctrl+Y invokes the standard redo shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (redoKey) root.redoEditor()' \
  'redo shortcuts invoke the persistent per-tab redo model'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'event.key === Qt.Key_Z && shift' \
  'Ctrl+Shift+Z invokes the standard redo shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (root.handleEditorHistoryKey(event)) {' \
  'the focused TextEdit handles history keys before its native implementation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleEditorFileNavigationKey(event)' \
  'note-tab arrow shortcuts have a dedicated focused-editor key route'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (root.handleEditorFileNavigationKey(event)) {' \
  'the focused TextEdit handles note-tab arrows before native word movement'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'var sourceBefore = String(root.editorPreviousText || "")' \
  'editor changes retain the pre-edit source for no-op detection'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'String(editor.text || "") !== sourceBefore' \
  'selection-only notifications do not schedule a save'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property bool autoFencePending: false' \
  'the editor tracks an untouched generated fence pair'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property var autoCodePairs: []' \
  'the editor tracks generated code-pair closers'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'EditorModel.backspaceAutoCodeFence' \
  'Backspace checks whether the generated fence closer should be removed'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'one Backspace removes the complete generated fence opener' \
  'the product harness rejects partial generated fence openers'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'one Return moves from a fence language into its code row' \
  'the product harness checks single-press fence-language entry'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'held Backspace removes a language and its complete generated fence' \
  'the product harness checks held Backspace through a generated fence'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'EditorModel.backspaceAutoCodePair' \
  'Backspace checks whether an untouched code closer should be removed'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function trackAutoFenceEdit(value)' \
  'QML keeps generated fence metadata aligned with source edits'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'EditorModel.plainBackspace' \
  'ordinary Backspace does not depend on native event propagation'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function indentEdit(sourceValue, selectionStartValue, selectionEndValue,' \
  'the editor model owns Tab and Shift Tab source transitions'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleIndent(direction)' \
  'QML applies source-preserving indentation in Live and Raw modes'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'event.key === Qt.Key_Backtab' \
  'the editor handles the platform Shift Tab key event'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'action: "Indent / outdent source rows"' \
  'shortcut help documents editor indentation'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'collapseEmptyItem === true' \
  'Preview Backspace removes an empty bullet without hidden syntax stops'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'function plainBackspace(sourceValue' \
  'plain Backspace handles code-block boundaries'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'source: source.slice(0, cursor) + list.lineBreak + nextPrefix +' \
  'Enter after a populated item inserts the next list marker using the source newline style'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'source: source.slice(0, list.lineStart) + source.slice(list.lineEnd)' \
  'Enter on an empty item removes its list marker'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'event.key === Qt.Key_Return || event.key === Qt.Key_Enter' \
  'the editor routes Return keys through list continuation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: headerPath' \
  'header exposes the complete current path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'wrapMode: Text.WrapAnywhere' \
  'long paths wrap instead of being elided'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'elide: Text.ElideNone' \
  'header paths do not hide their middle or filename'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'selectionColor: root.rawMode' \
  'Raw mode keeps native source selection highlighting'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'selectionStart: editor.selectionStart' \
  'Live mode receives the source selection start'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'selectionEnd: editor.selectionEnd' \
  'Live mode receives the source selection end'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function onLayoutUpdated()' \
  'live caret resynchronizes after renderer layout updates'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'Native document geometry is already queryable here' \
  'live caret uses current native geometry without a forced blank frame'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'id: renderedCursorSyncTimer' \
  'held key repeat cannot starve caret synchronization through debounce'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'Keep the last valid caret' \
  'live caret remains painted while Markdown geometry reconciles'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'visible: root.rawMode' \
  'native editor caret is disabled in live mode'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'cursorPosition: editor.cursorPosition' \
  'renderer receives the active source cursor position'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onSourceSelectionRequested: function(anchorPosition' \
  'fenced code selections update the native editor range'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'viewportRenderingEnabled: true' \
  'the production Live editor enables viewport-bounded rendering'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onHeightIndexAdjusted: function(delta, blockTop)' \
  'measured blocks above the viewport preserve the scroll anchor'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function horizontalListBoundaryTarget(direction)' \
  'Live horizontal navigation collapses hidden list prefixes'
assert_contains "$ROOT_DIR/EditorModel.js" \
  'list.position < absoluteContentStart' \
  'Left and Right skip the non-editable list marker prefix'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'bodyCaretHeight: editor.cursorRectangle.height' \
  'Live mode uses the native editor font metrics for caret height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property real editorWheelScrollFactor: 2.5' \
  'editor wheel scrolling has an increased movement factor'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'WheelHandler {' \
  'editor wheel input is handled explicitly'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'event.pixelDelta.y' \
  'editor wheel handling supports pixel-based scrolling'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'renderedEditor.cursorRectangleForSource(' \
  'live caret visibility uses rendered Markdown geometry'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'selectByMouse: root.rawMode' \
  'native source mouse placement is restricted to Raw mode'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: liveEditorMouseShield' \
  'Live mode shields the transparent source editor from fallback clicks'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'readonly property int pointerCursorShape: pointerArea.cursorShape' \
  'the pointer harness can observe the renderer cursor shape'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'readonly property bool linkPointerMarkerVisible: controlKeyHeld &&' \
  'Ctrl hover exposes an application-owned link target marker'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'controlKeyHeld: root.controlKeyHeld' \
  'the product forwards Ctrl state to the compositor-independent marker'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: editorCursorArea' \
  'the editor background exposes the default I-beam cursor'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'acceptedButtons: Qt.NoButton' \
  'physical mouse buttons cannot pan or steal rendered-text selection'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'interactive: false' \
  'the editor keeps normal touch and flick scrolling enabled'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'ScrollBar.vertical: ScrollBar {' \
  'the non-dragging editor viewport retains its visible scrollbar'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: editorWheelHandler' \
  'the non-dragging editor viewport retains wheel and touchpad scrolling'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'acceptedButtons: Qt.NoButton' \
  'the default cursor surface does not intercept editor input'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onSourcePositionRequested: function(sourcePosition)' \
  'blank-row taps move the native editor caret'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'Up/Down can enter it instead of skipping over it to the next paragraph' \
  'vertical navigation stops on an adjacent blank source row'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function moveLiveCursorVertically(direction, extendSelection)' \
  'Live Up and Down use rendered visual-row geometry'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function toggleTask(sourcePosition)' \
  'task clicks update the Markdown source'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'path: root.presentationSettingsLoaded ? root.notePath : ""' \
  'the first note load waits for the restored active tab'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function handleNoteLoadWatchdog()' \
  'a dropped note load cannot lock every file tab indefinitely'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function retryNoteLoad()' \
  'a stalled note load exposes an explicit retry path'
assert_contains "$ROOT_DIR/tests/isolated/persistence.qml" \
  'startup load is gated and a dropped load cannot lock every tab' \
  'the offscreen harness exercises startup load deadlock recovery'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function rebuildTaskCheckboxRects()' \
  'Live tasks use dedicated rendered checkbox controls'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'taskCheckboxSize: Style.space(11)' \
  'Live checkbox controls retain the established theme-scaled size'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function taskCheckboxSourceAtPoint(pointX, pointY)' \
  'Live checkbox controls expose source-aware pointer targets'
assert_contains "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  'function sourceRangeTouchesTaskMarker(sourceValue, startValue, endValue)' \
  'task toggles cannot flash their raw source character in Live view'
assert_contains "$ROOT_DIR/tests/isolated/tst_native_markdown_mouse.qml" \
  'function test_clicks_rendered_task_checkbox()' \
  'the pointer harness clicks the rendered checkbox control'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'QtQuick.Dialogs' \
  'Save As avoids the crash-prone native Qt dialog module'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property bool saveAsOpen: false' \
  'Save As uses an in-plugin chooser'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function saveAsSelected(value)' \
  'Save As accepts a selected file path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property string builtinNotesDirectory: home + "/Documents/Notes"' \
  'the default notes folder is Documents/Notes'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property string defaultNotePath: defaultNotesDirectory + "/welcome.md"' \
  'a new installation opens the welcome note from the default folder'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function openNewFile()' \
  'New creates a note immediately'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '"mktemp",' \
  'New creates a unique file without opening the chooser'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '"--tmpdir=" + root.defaultNotesDirectory' \
  'New places files in the default notes folder'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'creatingNewFile' \
  'New no longer relies on the old Save As chooser state'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuButton' \
  'file header exposes a File menu button'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: "File"' \
  'the file menu button is labeled File'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.toggleFileMenu()' \
  'the File button opens and closes its submenu'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuPopup' \
  'the File button owns a popup submenu'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside' \
  'the File submenu closes from Escape or an outside click'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuNewButton' \
  'the File submenu exposes New'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuSaveButton' \
  'the File submenu exposes Save'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.saveFromFileMenu()' \
  'File-menu Save invokes the normal save path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function saveFromFileMenu()' \
  'File-menu Save closes its popup before saving'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuSaveAsButton' \
  'the File submenu exposes Save As'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuOpenButton' \
  'the File submenu exposes Open'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: "Recent Files"' \
  'the File submenu exposes Recent Files'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'model: root.recentFiles' \
  'the File submenu renders persisted recent entries'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.openRecentFile(modelData)' \
  'a recent entry opens through the checked file-open path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuClearRecentButton' \
  'the File submenu exposes Clear Recent Files'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function validateRecentFiles()' \
  'Recent Files validates persisted paths without touching note data'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function tryNextMostRecentFile()' \
  'Open Most Recent falls through unusable entries'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'focusScope.height - Style.space(280)' \
  'the Recent Files viewport is constrained at minimum window height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'recentFiles: root.recentFiles' \
  'Recent Files is persisted in JotPin settings'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutNew' \
  'New uses the configurable keyboard shortcut'
action_block="$(sed -n '/id: actionRow/,/id: headerPath/p' "$ROOT_DIR/JotPin.qml")"
assert_block_contains "$action_block" \
  'anchors.right: parent.right' \
  'top-row actions are aligned to the right'
assert_block_contains "$action_block" \
  'spacing: 0' \
  'top-row buttons have no external gaps between their hit areas'
assert_block_contains "$action_block" \
  'id: fileMenuButton' \
  'the File button is in the top action row'
assert_block_contains "$action_block" \
  'id: presentationButton' \
  'the presentation control is in the top action row'
assert_block_contains "$action_block" \
  'id: previewButton' \
  'the preview control is in the top action row'
assert_block_contains "$action_block" \
  'id: actionSeparator' \
  'file and view actions remain visually separated in the top row'
assert_order "$ROOT_DIR/JotPin.qml" \
  'id: actionRow' \
  'id: headerPath' \
  'top-row actions appear above the file location'
assert_block_contains "$action_block" \
  'id: fullscreenButton' \
  'fullscreen remains in the title row'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fileMenuOpenButton' \
  'the File submenu exposes an Open button'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function openFileChooser()' \
  'Open opens the in-plugin file chooser'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function loadOpenNoteFiles()' \
  'Open loads notes from the configured default folder'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '"-iname", "*.md"' \
  'Open filters its default-folder list to Markdown files'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'model: root.openNoteFiles' \
  'Open renders the Markdown files found in the default folder'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function openFileSelected(value)' \
  'Open accepts a selected file path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'openFileCheckProcess.command = ["test", "-f", nextPath]' \
  'Open validates that the selected path is an existing file'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutOpen' \
  'Open uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutOpenRecent' \
  'Open Most Recent uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutClearRecent' \
  'Clear Recent Files uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: root.sideMode ? "Center" : "Side"' \
  'the window presentation control is labeled Center'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'tooltipText: root.sideMode' \
  'the presentation control explains the centered destination'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'iconText: root.rawMode ? "󰈉" : "󰈈"' \
  'the rendered presentation control uses eye and eye-off icons'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'selected: !root.rawMode' \
  'the preview control does not keep a selected highlight'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function caretRectangleForView(rawView, sourcePosition)' \
  'Raw and Preview share one source-caret alignment path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'Number(caret.y) - root.pendingViewCaretViewportY' \
  'view toggles preserve the caret viewport position'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: viewCaretAlignmentTimer' \
  'Preview waits for rendered caret geometry before aligning its viewport'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'selected: root.activeWindowMaximized' \
  'the expand control does not keep a selected highlight'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'iconText: root.fullScreenIconText' \
  'the expand control uses distinct collapse and expand icons'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'tooltipText: "Full Screen (" + root.shortcutMaximize + ")"' \
  'the header consistently names the action Full Screen'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function observeHyprlandFullscreenEvent(event)' \
  'the Full Screen icon follows compositor fullscreen events'
assert_contains "$ROOT_DIR/JotPin.qml" \
  '? root.maximizeStateRequested : root.maximizeStateObserved' \
  'live icon state does not trust the native window maximized flag'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'function compositorWindowMaximized()' \
  'the superseded compositor maximize helper has been removed'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function toggleMaximized()' \
  'the header exposes a maximize action'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function hyprlandWindowAddress(toplevel)' \
  'Hyprland window selectors have a dedicated address normalizer'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'return "0x" + address' \
  'Hyprland window selectors restore the required hexadecimal prefix'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'var activeToplevel = Hyprland.activeToplevel' \
  'workspace targeting can detect a visible special workspace'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property string pendingWorkspaceName: ""' \
  'opening captures the workspace before the native window maps'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.pendingWorkspaceName = root.hyprlandWorkspaceName(' \
  'opening preserves the captured workspace during relocation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'Hyprland.dispatch("hl.dsp.window.fullscreen({' \
  'the expand action uses the Hyprland fullscreen dispatcher'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.luaString("maximized")' \
  'the expand action requests Hyprland full-width mode'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'target.maximized = nextState' \
  'the expand action retains its offscreen native-window fallback'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: fullscreenButton' \
  'the header exposes a dedicated expand button'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function loadSaveFolders()' \
  'Save As can browse folders in the plugin'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'TextField {' \
  'Save As exposes editable filename and folder fields'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property var openFiles: []' \
  'the plugin keeps a session file tab model'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'flickableDirection: Flickable.HorizontalFlick' \
  'file tabs scroll horizontally'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property int tabRowHeight: Math.max(Style.space(20),' \
  'file tabs use a stable row height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: tabGrid' \
  'file tabs use a multi-row grid'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'rows: fileTabs.visibleTabRows' \
  'the file-tab grid honors the configured row count'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'property int neededTabRows: 1' \
  'file tabs calculate their needed row count'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function updateNeededTabRows()' \
  'file tabs measure rows from available width'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'fileTabRepeater.itemAt(index)' \
  'file tabs measure each tab before wrapping'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'readonly property real occupiedRowsHeight: Math.max(' \
  'file tabs size to the rows that contain tabs'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'tabGrid.childrenRect.height' \
  'file tabs do not reserve unused maximum rows'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'rowSpacing: Style.spacing.controlGap' \
  'file-tab rows have explicit vertical spacing'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'columns: 0' \
  'the file-tab grid lets the configured row count determine its columns'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'height: fileTabs.tabRowHeight' \
  'file-tab delegates share the configured row height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'visible: fileTab.activeTab && root.dirty &&' \
  'the active dirty file exposes an overlay status dot'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'anchors.topMargin: Style.space(3)' \
  'the dirty status dot sits unobtrusively in existing tab padding'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: root.markdownStemForPath(modelData.path)' \
  'the file-tab button label remains stable while dirty state changes'
assert_contains "$ROOT_DIR/JotPin.qml" \
  ': tabButton.implicitWidth' \
  'the dirty status dot adds no measured file-tab width'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'modelData.path === root.notePath && root.dirty ? " •"' \
  'dirty state no longer changes the measured file-tab label'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'dirtyIndicatorSlot' \
  'file tabs do not reserve empty dirty-indicator space'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function switchToFile(path)' \
  'file tabs switch the active Markdown file'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onDoubleClicked: root.beginRenameFile(modelData.path)' \
  'double-clicking a file tab starts inline rename'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function commitRenameFile(value)' \
  'inline rename commits a filename change'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'renameFileProcess.command' \
  'inline rename moves the file on disk'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'verticalAlignment: TextInput.AlignVCenter' \
  'inline rename text is vertically centered'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'verticalPadding: 0' \
  'inline rename text fits the compact tab height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'width: tabName.width + Style.space(2) + closeTabButton.width' \
  'file tabs reserve the close control after the filename'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: tabName' \
  'file tab names have an isolated layout container'
assert_order "$ROOT_DIR/JotPin.qml" \
  'id: tabName' \
  'id: closeTabButton' \
  'file tab close controls remain after the tab name container'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'anchors.fill: tabButton' \
  'rename hit testing no longer distorts the tab Row layout'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function closeFile(path)' \
  'file tabs expose close behavior'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: "✕"' \
  'each file tab has a visible close control'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'fontSize: Style.font.heading' \
  'file tab close controls keep the original glyph sizing'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'width: Style.space(24)' \
  'file tab close controls use a compact button width'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'height: fileMenuButton.implicitHeight' \
  'app close control matches the header button height'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'onClicked: root.closeFile(modelData.path)' \
  'tab close controls remove the selected file'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'enabled: root.openFiles.length > 1' \
  'the only open file tab keeps its close control enabled'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function isGeneratedUntitledPath(path)' \
  'generated untitled notes have a dedicated close policy'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function deleteEmptyUntitledFile(path)' \
  'blank generated untitled notes can be removed on close'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'untitledBlankCheckProcess.command = ["test", "-s", path]' \
  'inactive untitled notes are checked for blank contents before deletion'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'untitledDeleteProcess.command = ["rm", "-f", "--", target]' \
  'blank untitled notes are deleted through a serialized process'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.beginLastFileReplacement(closingPath)' \
  'closing the last file creates a replacement note'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (closingPath !== "") root.closeFile(closingPath)' \
  'the old last tab closes only after its replacement exists'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.replaceLastFilePath = ""' \
  'a failed replacement leaves the original last tab available'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'anchors.bottom: tabScrollRail.top' \
  'the file tab viewport reserves space for its scrollbar'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: tabScrollRail' \
  'the file tab scrollbar has an explicit visual identity'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'height: visible ? Style.space(2) : 0' \
  'the file tab scrollbar has enough height to see'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'visible: contentRange > 0' \
  'the file tab scrollbar hides when tabs fit'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: tabScrollThumb' \
  'the file tab scrollbar has a visible thumb'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function setScrollFromThumb(left)' \
  'the file tab scrollbar can scroll the tab row'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: addFileButton' \
  'the file tab row exposes a dedicated add-note button'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: "+"' \
  'the add-note control uses a plus label'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'anchors.right: addFileButton.left' \
  'the tab viewport leaves the add-note control outside horizontal scrolling'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'tooltipText: "New note (" + root.shortcutNew + ")"' \
  'the add-note control advertises the configurable New shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: actionSeparator' \
  'header file actions have visual separation'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: closeButton' \
  'header close control has a dedicated button'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: shortcutHint' \
  'footer shortcut help has its own layout item'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: shortcutHelpCard' \
  'the footer exposes an expanded keyboard shortcut card'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'model: root.shortcutHelpEntries' \
  'the shortcut card renders the complete shortcut model'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'wrapMode: Text.WrapAtWordBoundaryOrAnywhere' \
  'shortcut help labels wrap inside their assigned columns'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function shortcutHelpLayoutState()' \
  'shortcut help exposes measured label-overflow regression state'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'text: root.shortcutHelpOpen ? "Show less" : "Show more"' \
  'the footer shortcut toggle reports its expanded state'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (root.shortcutHelpOpen) {' \
  'Escape closes shortcut help before closing JotPin'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: footerSideColumn' \
  'shared footer reserves separate status and shortcut rows'
footer_side_block="$(sed -n \
  '/id: footerSideColumn/,/spacing: Style.space(4)/p' \
  "$ROOT_DIR/JotPin.qml")"
rg -Fq -- 'anchors.top: parent.top' <<<"$footer_side_block" || \
  fail 'side-mode footer is not top-anchored'
if rg -Fq -- 'anchors.bottom: parent.bottom' <<<"$footer_side_block"; then
  fail 'side-mode footer reintroduced a parent-height binding loop'
fi
pass 'side-mode footer avoids a parent-height binding loop'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function footerShortcutState()' \
  'center footer visibility is exposed to the offscreen regression'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'footerFontMetrics.height * 2' \
  'both presentations reserve the Side-style two-row shortcut footer'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (!root.opened || root.screensaverActive) return' \
  'native window focus is skipped while closed or behind a secure surface'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'if (root.opened && !root.screensaverActive) editor.forceActiveFocus()' \
  'the shared editor regains focus after either native presentation maps'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutSaveAs' \
  'Save As uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutSave' \
  'Save uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutOpen' \
  'Open uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutNew' \
  'New uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutPreview' \
  'Preview uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutFileMenu' \
  'the File menu uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutPresentation' \
  'Side and Center switching uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutMaximize' \
  'Expand and Restore use a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutSettings' \
  'Settings uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutHelp' \
  'shortcut help uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutNextFile' \
  'next-file navigation uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutPreviousFile' \
  'previous-file navigation uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutCloseFile' \
  'closing the active file uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutRenameFile' \
  'renaming the active file uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutToggleTask' \
  'the task at the caret uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutFind' \
  'Find uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutReplace' \
  'Find and Replace uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutGoToLine' \
  'Go to Line uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutFindNext' \
  'Find Next uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutFindPrevious' \
  'Find Previous uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutContextMenu' \
  'the editor context menu uses a configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'sequence: root.shortcutClose' \
  'Close uses the configurable keyboard shortcut'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: editorCommandBar' \
  'the editor exposes an in-place Find Replace and Go to Line surface'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.updateFindQuery(text)' \
  'Find and Replace highlight matches while the query is typed'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.findInEditor(false, root.findAnchorPosition)' \
  'incremental Find keeps the original caret search anchor'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function findInEditor(backwards, fromOverride)' \
  'Find maps matches into the native source selection'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.findMatchIndex + " of " + root.findMatchCount' \
  'Find displays the current match number and total match count'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function replaceAllMatches()' \
  'Replace All uses the source-preserving editor path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'function goToSourceLine()' \
  'Go to Line targets Markdown source rows'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.ensureEditorCursorVisible(true)' \
  'search results scroll into view without taking command-field focus'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'else if (root.editorCommandOpen)' \
  'Escape closes the editor command bar before JotPin'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: editorContextMenu' \
  'the editor exposes an Undo and clipboard context menu'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'acceptedButtons: Qt.RightButton' \
  'the context-menu mouse layer accepts only right clicks'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'renderedEditor.sourcePositionForPoint(' \
  'Live-mode right clicks map through rendered source geometry'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'editor.positionAt(sourcePoint.x, sourcePoint.y)' \
  'Raw-mode right clicks use native source geometry'
for native_context_action in \
  'editor.cut()' 'editor.copy()' \
  'editor.paste()' 'editor.selectAll()'; do
  assert_contains "$ROOT_DIR/JotPin.qml" "$native_context_action" \
    "the context menu exposes native ${native_context_action#editor.}"
done
assert_contains "$ROOT_DIR/JotPin.qml" \
  'root.applyEditorHistory("undo")' \
  'the context menu shares the persistent per-tab undo path'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'id: editorStatesFile' \
  'per-tab caret selection scroll and history use an atomic state file'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'EditorModel.validateEditTransactionChain(' \
  'persisted undo history is validated against current note bytes'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'function validateEditorHistoryForSource(path, sourceValue)' \
  'the duplicate unused undo-history validator has been removed'
assert_contains "$ROOT_DIR/JotPin.qml" \
  'editorHistoryMaxTextBytes: 131072' \
  'persisted per-tab edit fragments have a strict size bound'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'id: markdownRender' \
  'typing does not launch a second asynchronous Markdown renderer'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'id: cursorLayoutEditor' \
  'typing does not update an unused hidden rich-text editor'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'markdownForDisplay' \
  'no custom Markdown marker-rewriting transform is active'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'editorReparsing' \
  'no destructive per-keystroke reparse path is active'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'console.log(' \
  'the plugin has no development debug logging'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'QtWebEngine' \
  'the shell plugin does not embed the crash-prone WebEngine module'
assert_absent "$ROOT_DIR/JotPin.qml" \
  'WebEngineView' \
  'the shell plugin does not construct a WebEngine view'

printf '%s\n' '== CommonMark fixture =='
commonmark_html="$TEST_TMP_DIR/commonmark.html"
md2html --commonmark "$FIXTURE_DIR/markdown-commonmark.md" > "$commonmark_html"
assert_contains "$commonmark_html" '<h1>Heading 1</h1>' 'renders level-one headings'
assert_contains "$commonmark_html" '<h2>Heading 2</h2>' 'renders level-two headings'
assert_contains "$commonmark_html" '<strong>bold</strong>' 'renders strong emphasis'
assert_contains "$commonmark_html" '<em>italic</em>' 'renders emphasis'
assert_contains "$commonmark_html" '<code>inline code</code>' 'renders inline code'
assert_contains "$commonmark_html" '<a href="https://example.com">a link</a>' 'renders links'
assert_contains "$commonmark_html" '<img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==" alt="alt text">' 'renders images'
assert_contains "$commonmark_html" '<br>' 'renders hard line breaks'
assert_contains "$commonmark_html" '<blockquote>' 'renders block quotes'
assert_contains "$commonmark_html" '<ul>' 'renders unordered lists'
assert_contains "$commonmark_html" '<ol>' 'renders ordered lists'
assert_contains "$commonmark_html" '<hr>' 'renders thematic breaks'
assert_contains "$commonmark_html" '<pre><code class="language-text">' 'renders fenced code blocks'

printf '%s\n' '== GitHub-flavored Markdown fixture =='
gfm_html="$TEST_TMP_DIR/gfm.html"
md2html --github "$FIXTURE_DIR/markdown-gfm.md" > "$gfm_html"
assert_contains "$gfm_html" '<del>strikethrough</del>' 'renders GFM strikethrough'
assert_contains "$gfm_html" 'type="checkbox"' 'renders task-list checkboxes'
assert_contains "$gfm_html" 'checked' 'preserves checked task state'
assert_contains "$gfm_html" '<table>' 'renders GFM tables'
assert_contains "$gfm_html" '<thead>' 'renders table headers'
assert_contains "$gfm_html" '<tbody>' 'renders table body'

printf '%s\n' 'PASS: plugin structure, source invariants, model and Markdown fixture stage'
