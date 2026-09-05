import QtQuick
import Quickshell

// Optional offscreen visual artifact for comparing the production renderer
// with the established JotPin treatment. The shell runner supplies a private
// environment and an output path under /tmp unless explicitly overridden.
ShellRoot {
  id: shell

  property string capturePath: Quickshell.env("JOTPIN_NATIVE_CAPTURE_PATH")
  property string source: "# Heading\n\n" +
    "Body with **bold**, *italic*, `inline code`, and a [link](https://example.com).\n\n" +
    "> Markdown is a lightweight markup language with plain-text-formatting " +
      "syntax, created in 2004 by John Gruber with Aaron Swartz.\n>\n" +
    ">> Markdown is often used to format readme files, for writing messages " +
      "in online discussion forums, and to create rich text using a plain " +
      "text editor.\n\n---\n\n" +
    "- parent\n  - child\n\n" +
    "- [x] finished\n- [ ] remaining\n\n" +
    "```dart\nvoid main() {\n  print('hello');\n}\n```\n\n" +
    "| Col | Value |\n| :--- | ---: |\n| A | B |\n"
    + "\n## Images\n\n" +
    "![This is an alt text.](/image/Markdown-mark.svg " +
      "\"This is a sample image.\")\n"
  property int attempts: 0
  property var display: displayLoader.item

  Timer {
    id: cleanExitTimer
    interval: 250
    repeat: false
    onTriggered: Qt.quit()
  }

  Timer {
    id: captureTimer
    interval: 50
    repeat: false
    onTriggered: captureSurface.grabToImage(function(result) {
      if (!result.saveToFile(shell.capturePath)) {
        console.error("NATIVE_VISUAL_FAIL: could not save " +
          shell.capturePath)
        Qt.exit(1)
        return
      }
      console.log("NATIVE_VISUAL_RESULT: " + shell.capturePath)
      displayLoader.active = false
      testWindow.visible = false
      cleanExitTimer.start()
    })
  }

  Window {
    id: testWindow
    width: 760
    height: Math.min(900, Math.max(1,
      shell.display ? shell.display.implicitHeight : 1))
    visible: true
    color: "#101322"

    Item {
      id: captureSurface
      anchors.fill: parent

      Loader {
        id: displayLoader
        anchors.fill: parent
        active: true
        sourceComponent: Component {
          NativeMarkdownDisplay {
            foreground: "#f0d0b0"
            background: "#101322"
            surfaceBackground: "#101322"
            accent: "#b5a3ff"
            fontFamily: "monospace"
            bodyPixelSize: 16
            bodyCaretHeight: 16
            sourceText: shell.source
          }
        }
      }
    }
  }

  Timer {
    interval: 4
    repeat: true
    running: true
    onTriggered: {
      shell.attempts++
      if (shell.display && shell.display.layoutReady &&
          shell.display.layoutSourceText === shell.source &&
          shell.display.codeHighlightPendingCount === 0 &&
          shell.display.taskCheckboxRects.length === 2 &&
          shell.display.imageLoadStates.length === 1 &&
          shell.display.imageLoadStates[0] === "error") {
        stop()
        captureTimer.start()
      } else if (shell.attempts >= 500) {
        stop()
        console.error("NATIVE_VISUAL_FAIL: renderer did not settle")
        Qt.exit(1)
      }
    }
  }
}
