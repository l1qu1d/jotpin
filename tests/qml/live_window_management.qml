import QtQuick
import Quickshell
import qs.Commons
import "./jotpin" as JotPin

ShellRoot {
  readonly property string requestedMode:
    Quickshell.env("JOTPIN_TEST_MODE") || "window"
  readonly property int requestedMaximizeToggles:
    Math.max(0, Number(Quickshell.env("JOTPIN_TEST_TOGGLE_MAXIMIZED")) || 0)

  QtObject {
    id: fakeShell
    property var barConfig: ({ position: "top" })
    property var bar: null
    function firstPartyServiceFor(pluginId) { return null }
    function hide(pluginId) {}
  }

  Component {
    id: padComponent

    JotPin.JotPin {
      shell: fakeShell
      manifest: ({ id: "dev.jotpin" })
    }
  }

  Loader {
    id: padLoader
    active: false
    sourceComponent: padComponent
    onLoaded: {
      item.open(JSON.stringify({
        mode: requestedMode,
        path: Quickshell.env("JOTPIN_TEST_NOTE")
      }))
      if (requestedMaximizeToggles > 0) maximizeTimer.restart()
    }
  }

  Timer {
    id: maximizeTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (!padLoader.item) return
      for (var index = 0; index < requestedMaximizeToggles; index++) {
        padLoader.item.toggleMaximized()
      }
    }
  }

  Timer {
    id: maximizeStateProbe
    interval: 100
    repeat: true
    running: padLoader.item !== null
    property string lastState: ""
    onTriggered: {
      if (!padLoader.item) return
      var state = JSON.stringify({
        active: padLoader.item.activeWindowMaximized,
        pending: padLoader.item.maximizeStatePending,
        requested: padLoader.item.maximizeStateRequested,
        observed: padLoader.item.maximizeStateObserved,
        icon: padLoader.item.fullScreenIconText,
        mode: padLoader.item.activeHyprlandFullscreenMode(),
        ipc: padLoader.item.jotpinHyprlandToplevel()
          ? padLoader.item.jotpinHyprlandToplevel().lastIpcObject : null
      })
      if (state === lastState) return
      lastState = state
      console.log("JOTPIN_MAXIMIZE_PROBE: " + state)
    }
  }

  Timer {
    interval: 250
    running: true
    repeat: false
    onTriggered: {
      // Keep this disposable harness deterministic and exercise the same
      // 10px theme scale as the user's current Omarchy configuration.
      Style.fontBaseSize = 10
      Style.spacingScale = 1
      Style.spacingScaleWithFont = true
      padLoader.active = true
    }
  }
}
