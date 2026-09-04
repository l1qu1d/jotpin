import QtQuick

// Built-in host adapter for the current Omarchy package. JotPin consumes only
// this small contract so a future Quickshell host can inject an equivalent
// object without forking the editor, renderer, or persistence code.
QtObject {
  id: root

  property var shell: null
  property var manifest: null
  property string fallbackPluginId: "dev.jotpin"
  property int fallbackBarSize: 0

  readonly property string pluginId: root.manifest && root.manifest.id
    ? String(root.manifest.id) : root.fallbackPluginId
  readonly property string barPosition: root.shell && root.shell.barConfig
    ? String(root.shell.barConfig.position || "top") : "top"
  readonly property var idleService: root.shell &&
    typeof root.shell.firstPartyServiceFor === "function"
    ? root.shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var lockService: root.shell &&
    typeof root.shell.firstPartyServiceFor === "function"
    ? root.shell.firstPartyServiceFor("omarchy.lock") : null
  readonly property bool screensaverActive:
    Boolean(root.idleService &&
      (root.idleService.idledThisCycle ||
        root.idleService.screensaverStartedThisCycle ||
        Number(root.idleService.screensaverWindowCount) > 0)) ||
    Boolean(root.lockService && root.lockService.locked) ||
    Boolean(root.lockService && root.lockService.lockRequested)
  readonly property int liveBarSize: root.shell && root.shell.bar
    ? (root.shell.bar.barHidden
        ? 0 : Math.max(0, Number(root.shell.bar.barSize) || 0))
    : Math.max(0, Number(root.fallbackBarSize) || 0)

  function hidePanel() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }
}
