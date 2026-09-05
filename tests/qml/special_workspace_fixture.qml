import QtQuick
import Quickshell

ShellRoot {
  FloatingWindow {
    visible: true
    title: Quickshell.env("JOTPIN_TEST_SPECIAL_TITLE") ||
      "JotPin special-workspace fixture"
    color: "#20202a"
    implicitWidth: 360
    implicitHeight: 240
  }
}
