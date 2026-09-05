import QtQuick
import Quickshell
import "./jotpin" as JotPin

ShellRoot {
  id: test

  readonly property string firstItem:
    "- JotPin autosaves after a short pause; use `Ctrl+S` to save immediately."
  readonly property string existingItem:
    "- Use Side, Center, or Full Screen to match the way you are working."
  readonly property string source: firstItem + "\n" + existingItem
  property int phase: 0
  property double phaseStartedAt: Date.now()

  function fail(message) {
    console.log("LIST_RETURN_FAIL: " + message)
    Qt.exit(1)
  }

  function enterPhase(next) {
    test.phase = next
    test.phaseStartedAt = Date.now()
  }

  function timedOut() {
    return Date.now() - test.phaseStartedAt > 4000
  }

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
      presentationMode: "window"
    }
  }

  Loader {
    id: padLoader
    active: true
    sourceComponent: padComponent
    onLoaded: {
      item.opened = true
      item.rawMode = false
      test.enterPhase(1)
    }
  }

  Timer {
    interval: 20
    repeat: true
    running: true
    onTriggered: {
      var pad = padLoader.item
      if (!pad) return
      var editor = pad.editorItemForTests()
      if (test.phase === 1) {
        if (!pad.presentationSettingsLoaded || pad.loadingFromFile) {
          if (test.timedOut())
            test.fail("JotPin did not finish its isolated startup")
          return
        }
        pad.setEditorText(test.source)
        pad.selectEditorRange(test.firstItem.length, test.firstItem.length)
        test.enterPhase(2)
        return
      }
      if (test.phase === 2) {
        var rendered = JSON.parse(pad.renderedDocumentStateForTests())
        if (!rendered.layoutMatches) {
          if (test.timedOut())
            test.fail("Preview layout never settled before Return")
          return
        }
        var beforeState = JSON.parse(pad.editorBehaviorState())
        if (beforeState.text !== test.source) {
          test.fail("precondition source changed before Return: " +
            JSON.stringify(beforeState))
          return
        }
        pad.selectEditorRange(test.firstItem.length, test.firstItem.length)
        if (editor.cursorPosition !== test.firstItem.length) {
          test.fail("could not place the caret at the first item end: " +
            editor.cursorPosition)
          return
        }
        pad.captureHistoryInputState(Qt.Key_Return, Qt.NoModifier)
        editor.cursorSelection.text = "\n"
        test.enterPhase(3)
        return
      }
      if (test.phase === 3) {

      var expected = test.firstItem + "\n- \n" + test.existingItem
      var state = JSON.parse(pad.editorBehaviorState())
      var documentState = JSON.parse(pad.renderedDocumentStateForTests())
      if (state.text !== expected ||
          state.cursorPosition !== test.firstItem.length + 3) {
        test.fail("Return did not create the expected bullet: " +
          JSON.stringify(state))
        return
      }
      if (!documentState.layoutMatches) {
        if (test.timedOut())
          test.fail("Preview never settled after list Return")
        return
      }
      var caret = JSON.parse(pad.caretState())
      if (caret.cursorPosition !== test.firstItem.length + 3 ||
          caret.sourceLine !== 1 || caret.renderedCursorY < 0) {
        test.fail("Preview caret geometry did not remain on the new bullet: " +
          JSON.stringify(caret))
        return
      }
      pad.setEditorText(test.firstItem + "\n\n\n\n" + test.existingItem)
      pad.selectEditorRange(test.firstItem.length + 1,
        test.firstItem.length + 1)
      test.enterPhase(4)
      return
      }
      if (test.phase === 4) {
      var blankRendered = JSON.parse(pad.renderedDocumentStateForTests())
      if (!blankRendered.layoutMatches) {
        if (test.timedOut())
          test.fail("Preview never settled with the stranded blank lines")
        return
      }
      // The offscreen editor intentionally has no active desktop focus, so it
      // cannot reproduce Qt's live BeforeItem cursor offset. The pure model
      // suite covers that offset; this harness verifies the QML list edit from
      // the stranded blank-line source position.
      pad.selectEditorRange(test.firstItem.length + 1,
        test.firstItem.length + 1)
      if (!pad.handleListReturn()) {
        test.fail("Return did not recover the blank line between list items")
        return
      }
      test.enterPhase(5)
      return
    }
      if (test.phase !== 5) return

    var recoveredExpected = test.firstItem + "\n- \n" +
      test.existingItem
    var recoveredState = JSON.parse(pad.editorBehaviorState())
    var recoveredDocument = JSON.parse(pad.renderedDocumentStateForTests())
    if (recoveredState.text !== recoveredExpected ||
        recoveredState.cursorPosition !== test.firstItem.length + 3) {
      test.fail("stranded blank line did not become a bullet: " +
        JSON.stringify(recoveredState))
      return
    }
    if (!recoveredDocument.layoutMatches) {
      if (test.timedOut())
        test.fail("Preview never settled after recovering the blank line")
      return
    }
      pad.setEditorText("- test\n- testas")
      pad.selectEditorRange(15, 15)
      for (var backspaceIndex = 0; backspaceIndex < 8; backspaceIndex++) {
        if (!pad.handleBackspace()) {
          test.fail("held Backspace stopped at step " + backspaceIndex)
          return
        }
      }
      var heldState = JSON.parse(pad.editorBehaviorState())
      if (heldState.text !== "- test" || heldState.cursorPosition !== 6) {
        test.fail("held Backspace left whitespace or extra rows: " +
          JSON.stringify(heldState))
        return
      }
      pad.opened = false
      console.log("LIST_RETURN_RESULT: pass")
      Qt.exit(0)
    }
  }
}
