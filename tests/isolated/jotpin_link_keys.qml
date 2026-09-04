import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "./jotpin" as JotPin

// This test hosts the real JotPin editor in Quickshell and sends QtTest key
// events through the focused QML item. It deliberately does not call a
// keyboard handler or assign controlKeyHeld: the property must change through
// the same Keys delivery path used by the running plugin.
ShellRoot {
  id: test

  readonly property string linkTarget: "https://example.com/keyboard"
  readonly property string linkLabel: "keyboard link"
  readonly property string source:
    "Open [" + linkLabel + "](" + linkTarget + ") in Live Preview.\n\n" +
    "The space below the link is intentionally empty."

  property var pad: null
  property var editor: null
  property var renderer: null
  property bool testReady: false
  property int externalOpenCount: 0
  property string lastExternalTarget: ""
  property var completedTests: []

  function captureExternalUrl(target) {
    test.externalOpenCount++
    test.lastExternalTarget = String(target)
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
      externalUrlOpener: test.captureExternalUrl
    }
  }

  Loader {
    id: padLoader
    active: true
    sourceComponent: padComponent
    onLoaded: {
      test.pad = item
      test.editor = item.editorItemForTests()
      test.testReady = true
      item.opened = true
      item.rawMode = false
    }
  }

  // A separate native window makes the FocusScope lose active focus. This
  // exercises the same cleanup path as the user clicking another application.
  Window {
    id: focusSink
    width: 40
    height: 40
    visible: false
    color: "black"
  }

  TestCase {
    id: testCase
    // The TestCase follows the production TextEdit into its FloatingWindow;
    // this makes QtTest's current focus window the window receiving the real
    // key events.
    parent: test.editor
    visible: false
    name: "JotPinLinkKeyboard"
    // Quickshell's ShellRoot is not the qmltestrunner wrapper Window, so the
    // attached windowShown flag is not emitted for a TestCase reparented into
    // a FloatingWindow. Start after the production editor exists and let
    // keyPress/keyRelease prove whether that native window can receive QtTest
    // events; a failure must be visible rather than hanging on windowShown.
    when: test.testReady

    // Quickshell does not install qmltestrunner's text logger. Preserve real
    // QtTest event delivery, but make failed assertions explicit in its log.
    function verify(condition, message) {
      if (!condition) {
        console.log("JOTPIN_LINK_KEYS_FAIL: " + message)
        throw new Error(message)
      }
    }
    function compare(actual, expected, message) {
      verify(actual === expected, (message || "comparison") +
        ": actual=" + actual + " expected=" + expected)
    }
    function tryVerify(predicate, timeout, message) {
      var deadline = Date.now() + (timeout || 5000)
      while (!predicate() && Date.now() < deadline) wait(10)
      verify(predicate(), message || "condition timed out")
    }
    function tryCompare(object, property, expected, timeout, message) {
      tryVerify(function() { return object[property] === expected }, timeout,
        (message || property) + ": actual=" + object[property] + " expected=" + expected)
    }

    function findRenderer(item, seen) {
      if (!item) return null
      var visited = seen || []
      if (visited.indexOf(item) >= 0) return null
      visited.push(item)
      if (typeof item.linkTargetForPoint === "function" &&
          typeof item.linkPointerMarkerVisible !== "undefined") return item

      var children = item.children
      if (children) {
        for (var childIndex = 0; childIndex < children.length; childIndex++) {
          var child = findRenderer(children[childIndex], visited)
          if (child) return child
        }
      }
      if (item.contentItem) {
        var content = findRenderer(item.contentItem, visited)
        if (content) return content
      }
      if (item.contentChildren) {
        for (var contentIndex = 0;
             contentIndex < item.contentChildren.length; contentIndex++) {
          var contentChild = findRenderer(item.contentChildren[contentIndex],
            visited)
          if (contentChild) return contentChild
        }
      }
      return null
    }

    function validRectangle(rectangle) {
      return rectangle && isFinite(Number(rectangle.x)) &&
        isFinite(Number(rectangle.y)) && Number(rectangle.width) > 0 &&
        Number(rectangle.height) > 0
    }

    function linkPoint() {
      var labelStart = test.source.indexOf("[" + test.linkLabel + "](") + 1
      verify(labelStart > 0, "the keyboard link fixture is present")
      var rectangle = test.renderer.cursorRectangleForSource(labelStart + 2)
      verify(validRectangle(rectangle),
        "the visible link label has rendered geometry")
      var point = {
        x: Number(rectangle.x) + Number(rectangle.width) / 2,
        y: Number(rectangle.y) + Number(rectangle.height) / 2
      }
      compare(String(test.renderer.linkTargetForPoint(point.x, point.y)),
        test.linkTarget,
        "the link point resolves through the renderer hit test")
      return point
    }

    function blankPoint() {
      var labelStart = test.source.indexOf("[" + test.linkLabel + "](") + 1
      var rectangle = test.renderer.cursorRectangleForSource(labelStart + 2)
      verify(validRectangle(rectangle),
        "the link geometry exists before checking blank space")
      var point = {
        x: Math.max(1, Number(test.renderer.width) - 12),
        y: Number(rectangle.y) + Number(rectangle.height) / 2
      }
      verify(point.x > Number(rectangle.x) + Number(rectangle.width),
        "the blank-space probe is visually outside the link label")
      return point
    }

    function initTestCase() {
      verify(test.pad, "JotPin loaded in the isolated Quickshell host")
      test.pad.rawMode = false
      tryVerify(function() {
        return test.pad.presentationSettingsLoaded &&
          !test.pad.loadingFromFile
      }, 15000, "JotPin isolated startup settles")
      test.pad.setEditorText(test.source)
      test.editor = test.pad.editorItemForTests()
      verify(test.editor, "the production editor TextEdit is available")
      test.renderer = findRenderer(test.pad)
      if (!test.renderer) test.renderer = findRenderer(test.editor.parent)
      verify(test.renderer, "the production renderer is reachable in the item tree")
      tryVerify(function() {
        return test.renderer.layoutReady &&
          test.renderer.layoutMatchesCurrentInput() &&
          !test.renderer.parsePending && !test.renderer.parseInFlight &&
          test.renderer.pendingStyledReconcileRequestId < 0
      }, 15000, "the link fixture finishes native rendering")
      test.editor.Window.window.requestActivate()
      test.editor.forceActiveFocus()
      tryCompare(test.editor, "activeFocus", true, 2000,
        "the production editor receives active focus")
      tryCompare(test.pad, "controlKeyHeld", false, 2000,
        "the test starts with Ctrl state cleared")
      test.testReady = true
    }

    function test_control_press_and_release_routes_to_jotpin() {
      test.editor.forceActiveFocus()
      tryCompare(test.editor, "activeFocus", true, 2000)

      var point = linkPoint()
      mouseMove(test.renderer, point.x, point.y)
      tryCompare(test.renderer, "hoveredLinkTarget", test.linkTarget, 2000,
        "the pointer is over the rendered link before Ctrl")
      compare(test.renderer.linkPointerMarkerVisible, false,
        "the marker is hidden before Ctrl is pressed")

      keyPress(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", true, 2000,
        "a real Qt Ctrl key press reaches JotPin")
      tryCompare(test.renderer, "linkPointerMarkerVisible", true, 2000,
        "Ctrl press reveals the marker over the rendered link")

      keyRelease(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", false, 2000,
        "a real Qt Ctrl key release clears JotPin state")
      tryCompare(test.renderer, "linkPointerMarkerVisible", false, 2000,
        "Ctrl release hides the rendered link marker")
    }

    function test_ctrl_marker_stays_off_in_blank_space() {
      test.editor.forceActiveFocus()
      var point = blankPoint()
      mouseMove(test.renderer, point.x, point.y)
      compare(String(test.renderer.hoveredLinkTarget), "",
        "blank space does not resolve to the link")
      keyPress(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", true, 2000)
      tryCompare(test.renderer, "linkPointerMarkerVisible", false, 2000,
        "Ctrl in blank space does not show a link marker")
      keyRelease(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", false, 2000)
    }

    function test_product_link_dispatch_requires_ctrl_and_opens_once() {
      test.editor.forceActiveFocus()
      var point = linkPoint()
      mouseMove(test.renderer, point.x, point.y)
      tryCompare(test.renderer, "hoveredLinkTarget", test.linkTarget, 2000)

      test.externalOpenCount = 0
      test.lastExternalTarget = ""
      mouseClick(test.renderer, point.x, point.y, Qt.LeftButton)
      wait(50)
      compare(test.externalOpenCount, 0,
        "a plain rendered-link click does not open an external URL")

      var blank = blankPoint()
      mouseMove(test.renderer, blank.x, blank.y)
      keyPress(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", true, 2000)
      mouseClick(test.renderer, blank.x, blank.y, Qt.LeftButton,
        Qt.ControlModifier)
      wait(50)
      compare(test.externalOpenCount, 0,
        "a Ctrl+click in blank space does not open an external URL")

      mouseMove(test.renderer, point.x, point.y)
      tryCompare(test.renderer, "hoveredLinkTarget", test.linkTarget, 2000)
      mouseClick(test.renderer, point.x, point.y, Qt.LeftButton,
        Qt.ControlModifier)
      tryCompare(test, "externalOpenCount", 1, 2000,
        "a real Ctrl+click reaches the product URL opener once")
      compare(test.lastExternalTarget, test.linkTarget,
        "the product receives the renderer's resolved URL")
      wait(50)
      compare(test.externalOpenCount, 1,
        "the product opens one URL for one stationary Ctrl+click")

      keyRelease(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", false, 2000)
    }

    function test_focus_loss_clears_ctrl_state_and_marker() {
      test.editor.forceActiveFocus()
      var point = linkPoint()
      mouseMove(test.renderer, point.x, point.y)
      tryCompare(test.renderer, "hoveredLinkTarget", test.linkTarget, 2000)
      keyPress(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", true, 2000,
        "Ctrl is held before the focus-loss transition")
      tryCompare(test.renderer, "linkPointerMarkerVisible", true, 2000)

      focusSink.visible = true
      focusSink.requestActivate()
      tryCompare(focusSink, "active", true, 2000,
        "the isolated focus sink becomes the active native window")
      tryCompare(test.pad, "controlKeyHeld", false, 2000,
        "JotPin clears Ctrl when its FocusScope loses active focus")
      tryCompare(test.renderer, "linkPointerMarkerVisible", false, 2000,
        "focus loss removes the stale link marker")

      focusSink.visible = false
      test.editor.Window.window.requestActivate()
      test.editor.forceActiveFocus()
      tryCompare(test.editor, "activeFocus", true, 2000,
        "the production editor can reclaim focus after the test")
      // The synthetic Ctrl press was intentionally interrupted by focus loss;
      // ensure the native key state is balanced before the next test.
      keyRelease(Qt.Key_Control)
      tryCompare(test.pad, "controlKeyHeld", false, 2000)
    }

    function cleanup() {
      if (!qtest_results.failed && !qtest_results.skipped)
        test.completedTests.push(String(qtest_results.functionName))
    }

    function cleanupTestCase() {
      var expected = [
        "test_control_press_and_release_routes_to_jotpin",
        "test_ctrl_marker_stays_off_in_blank_space",
        "test_focus_loss_clears_ctrl_state_and_marker",
        "test_product_link_dispatch_requires_ctrl_and_opens_once"
      ]
      var success = qtest_results.failCount === 0 &&
        qtest_results.skipCount === 0 && qtest_results.passCount === 5 &&
        JSON.stringify(test.completedTests.slice().sort()) === JSON.stringify(expected)
      console.log((success ? "JOTPIN_LINK_KEYS_RESULT: pass " : "JOTPIN_LINK_KEYS_FAIL: ") +
        JSON.stringify({completed: test.completedTests, failures: qtest_results.failCount,
          skipped: qtest_results.skipCount}))
      focusSink.visible = false
      if (test.pad) test.pad.opened = false
      Qt.callLater(function() { Qt.exit(success ? 0 : 1) })
    }
  }
}
