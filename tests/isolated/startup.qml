import QtQuick
import QtTest
import Quickshell
import "./jotpin" as JotPin

ShellRoot {
  id: test
  property bool recoveryMode: Quickshell.env("JOTPIN_STARTUP_MODE") === "recovery"
  property bool completed: false
  property int phase: 0
  property double started: Date.now()
  property double phaseStarted: Date.now()
  property real revealedHeight: 0
  property string revealedImageRects: ""
  property var renderer: null
  property var viewport: null
  function fail(message) {
    if (completed) return
    completed = true
    console.log("STARTUP_FAIL: " + message)
    Qt.exit(1)
  }
  function next(value) { phase = value; phaseStarted = Date.now() }
  function pass(message) { console.log("STARTUP_PASS: " + message) }
  QtObject {
    id: fakeShell
    property var barConfig: ({position: "top"})
    property var bar: null
    function firstPartyServiceFor(pluginId) { return null }
    function hide(pluginId) {}
  }
  TestCase { id: finder; name: "StartupLookup"; when: false }
  Loader {
    id: loader
    sourceComponent: Component {
      JotPin.JotPin { shell: fakeShell; manifest: ({id: "dev.jotpin"}) }
    }
    onLoaded: {
      if (item.startupContentRevealed) test.fail("cold component was already revealed")
      item.open(JSON.stringify({mode: "center", path: Quickshell.env("JOTPIN_TEST_NOTE")}))
    }
  }
  Connections {
    target: loader.item
    function onStartupContentRevealedChanged() {
      var pad = loader.item
      if (pad.startupContentRevealed && !pad.startupContentReady)
        test.fail("reveal occurred before readiness")
    }
  }
  Timer {
    interval: 10
    repeat: true
    running: !test.completed
    onTriggered: {
      var pad = loader.item
      if (!pad) return
      if (!test.renderer) test.renderer = finder.findChild(pad, "startupRenderer")
      if (!test.viewport) test.viewport = finder.findChild(pad, "startupEditorViewport")
      var r = test.renderer, v = test.viewport
      if (!r || !v) return
      var elapsed = Date.now() - test.phaseStarted
      if (!pad.startupContentRevealed && v.opacity !== 0)
        return test.fail("unready editor viewport is visible")
      if (!pad.startupContentRevealed && v.enabled)
        return test.fail("unready editor accepts invisible input")
      if (test.phase === 0 && pad.startupContentRevealed) {
        if (Quickshell.env("JOTPIN_STARTUP_MODE") === "plain") {
          if (!r.initialLayoutReady || !r.imagesReady || r.images.length !== 0 || r.codeBlocks.length !== 0)
            return test.fail("plain note revealed before layout readiness")
          test.pass("plain cold reveal ready after " + (Date.now() - test.started) + "ms")
          test.completed = true
          console.log("STARTUP_RESULT: passed")
          Qt.exit(0)
          return
        }
        if (!r.initialLayoutReady || !r.imagesReady || r.images.length !== 1 ||
            r.imageLoadStateAt(0) !== "ready" || r.codeBlocks.length !== 1 ||
            r.codeHighlightPendingCount !== 0 || r.codeHighlightDispatchPending ||
            r.codePaintState !== "highlighted")
          return test.fail("cold reveal lacked complete image/layout/highlight: " + r.codePaintState)
        test.revealedHeight = r.implicitHeight
        test.revealedImageRects = JSON.stringify(r.imageRects)
        if (r.imageRects.length !== 1)
          return test.fail("image geometry missing at reveal")
        test.pass("cold image and code reveal ready after " + (Date.now() - test.started) + "ms")
        if (test.recoveryMode) {
          pad.loadingFromFile = true
          r.parseInFlight = true
          pad.loadingFromFile = false
          test.next(10)
        } else test.next(1)
      } else if (test.phase === 10) {
        if (pad.startupContentRevealed) return test.fail("stalled parser revealed incomplete preview")
        if (elapsed < 100 && pad.startupMessageVisible)
          return test.fail("loading message appeared without its delay")
        if (elapsed > 300 && !pad.startupMessageVisible)
          return test.fail("loading message did not appear")
        if (elapsed < 2800 && pad.startupRecoveryVisible)
          return test.fail("source recovery appeared before timeout")
        if (!pad.startupRecoveryVisible) return
        var button = finder.findChild(pad, "startupSourceRecovery")
        if (!button || !button.visible) return test.fail("source recovery action unavailable")
        button.clicked()
        test.next(11)
      } else if (test.phase === 11 && pad.startupContentRevealed) {
        if (!pad.rawMode || elapsed > 500) return test.fail("source recovery did not reveal Raw")
        test.pass("stalled parser stays hidden with delayed loading and working source recovery")
        test.completed = true
        console.log("STARTUP_RESULT: passed")
        Qt.exit(0)
      } else if (test.phase === 1 && elapsed >= 100) {
        if (r.implicitHeight !== test.revealedHeight ||
            JSON.stringify(r.imageRects) !== test.revealedImageRects)
          return test.fail("layout shifted after reveal")
        pad.loadingFromFile = true
        r.imageLoadStates = ["loading"]
        pad.loadingFromFile = false
        test.next(2)
      } else if (test.phase === 2) {
        if (elapsed < 500 && pad.startupContentRevealed)
          return test.fail("stalled image bypassed grace period")
        if (!pad.startupContentRevealed) return
        if (elapsed > 1500 || !pad.startupImageWaitExpired)
          return test.fail("image wait was not bounded")
        test.pass("stalled image reveals after bounded grace: " + elapsed + "ms")
        pad.loadingFromFile = true
        r.imageLoadStates = ["error"]
        pad.loadingFromFile = false
        test.next(3)
      } else if (test.phase === 3 && pad.startupContentRevealed) {
        if (!r.imagesReady || pad.startupImageWaitExpired || elapsed > 500)
          return test.fail("image error did not settle without grace")
        test.pass("image errors are terminal")
        pad.setEditorText(String(pad.markdownSource) + "\nAn edit.")
        if (!pad.startupContentRevealed) return test.fail("edit hid revealed content")
        test.next(4)
      } else if (test.phase === 4) {
        if (!pad.startupContentRevealed) return test.fail("edit reparsing hid content")
        if (elapsed < 100 || !r.initialLayoutReady) return
        r.dispatchParse()
        r.dispatchParse()
        if (!r.parseInFlight || !r.parsePending)
          return test.fail("redundant in-flight parse was not exercised")
        test.next(45)
      } else if (test.phase === 45) {
        if (!r.initialLayoutReady) return
        test.pass("current parser reply clears redundant pending work")
        pad.loadingFromFile = true
        r.imageLoadStates = ["loading"]
        pad.rawMode = true
        pad.loadingFromFile = false
        test.next(5)
      } else if (test.phase === 5 && pad.startupContentRevealed) {
        if (pad.startupImageWaitExpired || elapsed > 500)
          return test.fail("Raw unnecessarily waited for image readiness")
        test.pass("edits keep content revealed and Raw bypasses image wait")
        test.completed = true
        console.log("STARTUP_RESULT: passed")
        Qt.exit(0)
      }
    }
  }
  Timer {
    interval: 5000
    running: !test.completed
    onTriggered: test.fail("deadline in phase " + test.phase + "; renderer=" + !!test.renderer + "; viewport=" + !!test.viewport)
  }
}
