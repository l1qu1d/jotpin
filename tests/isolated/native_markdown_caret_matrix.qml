import QtQuick
import Quickshell

// Offscreen matrix for the failure class where an edit advances the source
// caret before the projected rich document. Every case inspects each rapid
// insertion and deletion before allowing the worker parse to settle.
ShellRoot {
  id: shell

  property var cases: [
    {name: "paragraph", prefix: "Plain text", suffix: "\n"},
    {name: "heading", prefix: "# Heading", suffix: "\n"},
    {name: "bullet", prefix: "- Bullet", suffix: "\n"},
    {name: "multiline-bullet", prefix: "- First line\n  continuation", suffix: "\n"},
    {name: "ordered-list", prefix: "1. Ordered", suffix: "\n"},
    {name: "task", prefix: "- [ ] Task", suffix: "\n"},
    {name: "quote", prefix: "> Quote", suffix: "\n"},
    {name: "emphasis", prefix: "**Bold", suffix: "**\n"},
    {name: "inline-code", prefix: "Before `code", suffix: "` after\n"},
    {name: "link-label", prefix: "[Label", suffix: "](https://example.com)\n"},
    {name: "fence-language", prefix: "```", suffix: "\nbody\n```\n"},
    {name: "fence-body", prefix: "```js\nbody", suffix: "\n```\n"},
    {name: "table-cell", prefix: "| left | cell", suffix: " |\n| --- | --- |\n"}
  ]
  property int caseIndex: -1
  property string currentSource: ""
  property int currentCursor: 0
  property string phase: ""
  property int burstLength: 0
  property real expectedY: -1
  property int checkedEdits: 0
  property var beforeEditState: ({})
  property var failures: []

  NativeMarkdownDisplay {
    id: display
    width: 720
    height: 280
    sourceText: shell.currentSource
    cursorPosition: shell.currentCursor
    foreground: Qt.rgba(1, 0.79, 0.64, 1)
    background: Qt.rgba(1, 0.79, 0.64, 0.035)
    surfaceBackground: Qt.rgba(0.02, 0.03, 0.08, 1)
    accent: "#b5a3ff"
  }

  function fail(message) {
    failures.push(String(message))
    console.error("CARET_MATRIX_FAIL: " + String(message))
  }

  function validRectangle(rectangle) {
    return rectangle && isFinite(Number(rectangle.x)) &&
      isFinite(Number(rectangle.y)) && Number(rectangle.height) > 0
  }

  function startCase(index) {
    caseIndex = index
    if (caseIndex >= cases.length) {
      console.log("CARET_MATRIX_RESULT: " + JSON.stringify({
        caseCount: cases.length,
        rapidEditsPerCase: 24,
        checkedEdits: checkedEdits,
        failures: failures
      }))
      Qt.exit(failures.length === 0 ? 0 : 1)
      return
    }
    var item = cases[caseIndex]
    currentSource = String(item.prefix) + String(item.suffix)
    currentCursor = String(item.prefix).length
    burstLength = 0
    expectedY = -1
    phase = "initial"
    settleTimer.attempts = 0
    settleTimer.start()
  }

  function currentRevisionReady() {
    return display.layoutReady && display.layoutMatchesCurrentInput() &&
      display.layoutSourceText === currentSource &&
      display.documentSourceText === currentSource &&
      Number(display.layoutCursorPosition) === currentCursor &&
      !display.parseInFlight && !display.parsePending &&
      Number(display.pendingStyledReconcileRequestId) < 0 &&
      Number(display.codeHighlightPendingCount) === 0
  }

  function checkImmediate(label) {
    var rectangle = display.cursorRectangleForSource(currentCursor)
    if (!display.layoutReady || !display.layoutMatchesCurrentInput() ||
        display.layoutSourceText !== currentSource ||
        display.documentSourceText !== currentSource ||
        Number(display.layoutCursorPosition) !== currentCursor ||
        !validRectangle(rectangle) || expectedY < 0 ||
        Math.abs(Number(rectangle.y) - expectedY) > 1) {
      fail(cases[caseIndex].name + " " + label + ": " + JSON.stringify({
        cursor: currentCursor,
        layoutReady: display.layoutReady,
        layoutMatches: display.layoutMatchesCurrentInput(),
        layoutSourceMatches: display.layoutSourceText === currentSource,
        documentSourceMatches: display.documentSourceText === currentSource,
        parseRequestId: display.parseRequestId,
        settledRequestId: display.settledRequestId,
        documentSourceLength: String(display.documentSourceText).length,
        layoutSourceLength: String(display.layoutSourceText).length,
        optimisticEditCount: display.optimisticEditCount,
        beforeEditState: beforeEditState,
        mappedCursor: display.sourceToDocument[currentCursor],
        mappedAfterCursor: display.sourceToDocument[currentCursor + 1],
        documentPlainLength: String(display.documentPlainText).length,
        layoutCursor: display.layoutCursorPosition,
        rectangle: rectangle,
        expectedY: expectedY
      }))
    }
    checkedEdits++
  }

  Component.onCompleted: startCase(0)

  Timer {
    id: settleTimer
    property int attempts: 0
    interval: 2
    repeat: true
    onTriggered: {
      attempts++
      if (shell.currentRevisionReady()) {
        stop()
        var rectangle = display.cursorRectangleForSource(shell.currentCursor)
        if (!shell.validRectangle(rectangle)) {
          shell.fail(shell.cases[shell.caseIndex].name +
            " has no settled caret rectangle")
          shell.startCase(shell.caseIndex + 1)
          return
        }
        if (shell.phase === "initial") {
          shell.expectedY = Number(rectangle.y)
          shell.phase = "insert"
          burstTimer.start()
        } else if (shell.phase === "settle-insert") {
          if (Math.abs(Number(rectangle.y) - shell.expectedY) > 1)
            shell.fail(shell.cases[shell.caseIndex].name +
              " moved after authoritative insertion reconciliation")
          shell.phase = "delete"
          burstTimer.start()
        } else if (shell.phase === "settle-delete") {
          if (Math.abs(Number(rectangle.y) - shell.expectedY) > 1)
            shell.fail(shell.cases[shell.caseIndex].name +
              " moved after authoritative deletion reconciliation")
          shell.startCase(shell.caseIndex + 1)
        }
      } else if (attempts >= 4000) {
        stop()
        shell.fail(shell.cases[shell.caseIndex].name +
          " did not settle during " + shell.phase)
        shell.startCase(shell.caseIndex + 1)
      }
    }
  }

  Timer {
    id: burstTimer
    interval: 6
    repeat: true
    onTriggered: {
      var item = shell.cases[shell.caseIndex]
      if (shell.phase === "insert") {
        shell.burstLength++
      } else if (shell.phase === "delete") {
        shell.burstLength--
      }
      var repeated = new Array(shell.burstLength + 1).join("x")
      shell.beforeEditState = {
        parseRequestId: display.parseRequestId,
        settledRequestId: display.settledRequestId,
        layoutReady: display.layoutReady,
        layoutSource: String(display.layoutSourceText),
        documentSource: String(display.documentSourceText),
        documentPlainLength: String(display.documentPlainText).length,
        optimisticEditCount: display.optimisticEditCount
      }
      shell.currentCursor = String(item.prefix).length + repeated.length
      shell.currentSource = String(item.prefix) + repeated + String(item.suffix)
      shell.checkImmediate(shell.phase + "-" + shell.burstLength)

      if (shell.phase === "insert" && shell.burstLength >= 12) {
        stop()
        shell.phase = "settle-insert"
        settleTimer.attempts = 0
        settleTimer.start()
      } else if (shell.phase === "delete" && shell.burstLength <= 0) {
        stop()
        shell.phase = "settle-delete"
        settleTimer.attempts = 0
        settleTimer.start()
      }
    }
  }
}
