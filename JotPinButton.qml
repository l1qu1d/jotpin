import QtQuick
import qs.Ui as Ui

// JotPin keeps the shell button's keyboard focus path, but a completed button
// activation must not leave its focus treatment painted until the next click.
Ui.Button {
  id: control

  Connections {
    target: control

    function onClicked() {
      Qt.callLater(function() {
        if (control.activeFocus) control.focus = false
      })
    }
  }
}
