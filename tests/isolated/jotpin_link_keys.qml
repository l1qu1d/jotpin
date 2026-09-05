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
      manifest: ({ id: "dev.jotpin", version: "1.0.0" })
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

    function test_settings_backdrop_and_text_size() {
      var surface = test.editor.Window.window.contentItem
      test.pad.openSettings()
      wait(30)
      var popup = findChild(surface, "settingsCard")
      var overlay = findChild(surface, "settingsOverlay")
      verify(popup && overlay, "settings popup and backdrop exist")
      var version = findChild(popup, "settingsVersion")
      verify(version && version.visible, "settings version is visible")
      compare(version.text, "v1.0.0", "settings displays the host manifest version")
      var versionPosition = version.mapToItem(popup, 0, 0)
      verify(versionPosition.x > popup.width / 2 &&
        versionPosition.y < popup.height / 4 &&
        versionPosition.x + version.width <= popup.width,
        "version fits at the top right of settings")
      test.pad.manifest = ({ id: "dev.jotpin", version: "9.8.7" })
      compare(version.text, "v9.8.7", "version follows metadata instead of a hardcoded label")
      test.pad.manifest = ({ id: "dev.jotpin", version: "1.0.0" })
      function hasSpellcheckSection(item) {
        if (item.text !== undefined && String(item.text).indexOf("Spellcheck") >= 0)
          return true
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
          if (hasSpellcheckSection(children[i])) return true
        }
        return false
      }
      verify(!hasSpellcheckSection(popup), "settings has no spellcheck section")
      mouseClick(popup, 2, 2, Qt.LeftButton)
      verify(test.pad.settingsOpen, "inside padding click keeps settings open")
      var sourceBefore = test.editor.text
      var dirtyBefore = test.pad.dirty
      var originalSize = test.editor.font.pixelSize
      test.pad.setEditorTextScale(150)
      wait(100)
      compare(test.renderer.bodyPixelSize, test.pad.editorPixelSize,
        "Preview uses the selected size")
      compare(test.editor.font.pixelSize, Math.round(test.pad.editorPixelSize),
        "Raw uses the selected size")
      verify(test.editor.font.pixelSize > originalSize, "text grows")
      compare(test.editor.text, sourceBefore, "resizing preserves Markdown")
      compare(test.pad.dirty, dirtyBefore, "resizing does not dirty the note")
      var label = findChild(surface, "textSizeLabel")
      var increase = findChild(surface, "textSizeIncrease")
      var decrease = findChild(surface, "textSizeDecrease")
      var reset = findChild(surface, "textSizeReset")
      verify(label && increase && decrease && reset, "text size controls exist")
      increase.clicked()
      compare(test.pad.editorTextScale, 160, "plus increases percentage")
      compare(label.text, "160%", "label follows plus")
      decrease.clicked()
      compare(test.pad.editorTextScale, 150, "minus decreases percentage")
      compare(label.text, "150%", "label follows minus")
      reset.clicked()
      compare(test.pad.editorTextScale, 100, "reset restores default")
      compare(label.text, "100%", "label follows reset")
      mouseClick(overlay, 1, 1, Qt.LeftButton)
      verify(!test.pad.settingsOpen, "outside click closes settings")
      test.pad.setEditorTextScale(100)
    }

    function test_typing_after_checklist_preserves_blocks() {
      var source = "- [ ] Add your first thought\n- [ ] Click a checkbox in Preview\n" +
        "- [x] Enjoy checking something off\n\nYou can use **bold** and helpful links.\n"
      test.pad.setEditorText(source)
      var position = source.indexOf("\n\n") + 1
      tryVerify(function() { return test.renderer.layoutMatchesCurrentInput() },
        3000, "checklist layout settles")
      var rectangle = test.renderer.cursorRectangleForSource(position)
      var originalParagraph = test.renderer.cursorRectangleForSource(source.indexOf("You can"))
      mouseClick(test.renderer, rectangle.x + 1,
        rectangle.y + rectangle.height / 2, Qt.LeftButton)
      compare(test.editor.cursorPosition, position, "blank-row click sets source caret")
      keyClick(Qt.Key_T)
      var expected = source.slice(0, position) + "t" + source.slice(position)
      compare(test.editor.text, expected, "typing inserts only the requested character")
      tryVerify(function() { return test.renderer.layoutMatchesCurrentInput() },
        3000, "typed paragraph layout settles")
      wait(350)
      tryVerify(function() { return !test.renderer.parseInFlight &&
        !test.renderer.parsePending && test.renderer.layoutMatchesCurrentInput() },
        3000, "authoritative parser has settled")
      var taskRect = test.renderer.cursorRectangleForSource(source.indexOf("off"))
      var typedRect = test.renderer.cursorRectangleForSource(position)
      var paragraphRect = test.renderer.cursorRectangleForSource(expected.indexOf("You can"))
      compare(typedRect.y, rectangle.y, "typing stays on the original blank row")
      compare(typedRect.x, rectangle.x, "typing keeps the original horizontal position")
      compare(paragraphRect.y, originalParagraph.y, "following paragraph does not move")
      compare(paragraphRect.x, originalParagraph.x, "following paragraph keeps its left edge")
      verify(typedRect.y > taskRect.y && paragraphRect.y > typedRect.y,
        "typed text stays between checklist and following paragraph")
      test.pad.applyEditorHistory("undo")
      compare(test.editor.text, source, "one undo restores the original blank row")
      test.pad.setEditorText("")
      wait(50)
      test.pad.setEditorText(expected)
      wait(350)
      tryVerify(function() { return !test.renderer.parseInFlight &&
        !test.renderer.parsePending && test.renderer.layoutMatchesCurrentInput() },
        3000, "fresh parse settles without optimistic layout")
      compare(test.renderer.cursorRectangleForSource(position).x, rectangle.x,
        "freshly loaded text stays outside the bullet indentation")
      compare(test.renderer.cursorRectangleForSource(expected.indexOf("You can")).x,
        originalParagraph.x, "freshly loaded following paragraph stays unindented")
    }

    function test_z_backspace_prefix_keeps_row() {
      var prefixes = ["- ", "1. ", "- [ ] ", "## ", "> "]
      for (var index = 0; index < prefixes.length; index++) {
        var prefix = prefixes[index]
        var source = "Before\n\n" + prefix + "\n\nAfter"
        test.pad.setEditorText(source)
        test.pad.selectEditorRange(8 + prefix.length, 8 + prefix.length)
        test.editor.forceActiveFocus()
        wait(350)
        keyClick(Qt.Key_Backspace)
        compare(test.editor.text, "Before\n\n\n\nAfter",
          "Backspace removes only the formatting: " + prefix)
        compare(test.editor.cursorPosition, 8, "caret stays at the same source row")
        wait(350)
        tryVerify(function() { return !test.renderer.parseInFlight &&
          !test.renderer.parsePending && test.renderer.layoutMatchesCurrentInput() },
          3000, "unformatted row settles")
        var row = test.renderer.cursorRectangleForSource(8)
        var previous = test.renderer.cursorRectangleForSource(0)
        var following = test.renderer.cursorRectangleForSource(test.editor.text.indexOf("After"))
        verify(row.y > previous.y && row.y < following.y,
          "caret remains on its own visible row")
        test.pad.applyEditorHistory("undo")
        compare(test.editor.text, source, "undo restores formatting")
      }
    }

    function test_zz_inline_code_typing_color() {
      var source = "Before `code` after"
      test.pad.setEditorText(source)
      test.pad.selectEditorRange(8, 8)
      test.editor.forceActiveFocus()
      wait(350)
      for (var index = 0; index < 3; index++) {
        keyClick(Qt.Key_T)
        wait(1)
        var format = test.renderer.characterFormatForSourceForTests(8 + index)
        verify(format.valid, "typed code character has a format")
        compare(format.color, String(test.renderer.accent), "typed code color is stable immediately")
        wait(350)
        format = test.renderer.characterFormatForSourceForTests(8 + index)
        compare(format.color, String(test.renderer.accent), "typed code color stays stable after parsing")
      }
    }

    function test_zzz_type_image_and_drag_handles() {
      for (var variant = 0; variant < 4; variant++) {
        var prefix = variant % 2 === 0 ? "" : "An image: "
        test.pad.setEditorText(prefix)
        test.pad.selectEditorRange(prefix.length, prefix.length)
        test.editor.forceActiveFocus()
        wait(350)
        var syntax = variant < 2 ? "![Alt](markdown-image.svg)" : "![Alt](large-image.svg)."
        for (var index = 0; index < syntax.length; index++)
          keyClick(syntax.charAt(index))
        var original = prefix + syntax
        compare(test.editor.text, original, "manually typed image source stays exact")
        wait(350)
        tryVerify(function() { return !test.renderer.parseInFlight &&
          test.renderer.imageRectangleAt(0) !== null }, 4000, "typed image loads")
        verify(test.renderer.imageRectangleAt(0).width <= test.renderer.width -
          test.renderer.horizontalPadding * 2, "image fits the editor width")
        var introRect = prefix ? test.renderer.cursorRectangleForSource(0) : null
        var paintedRect = test.renderer.imageRectangleAt(0)
        if (introRect) verify(paintedRect.y > introRect.y,
          "image stays below the introductory text even when small")
        var captionPosition = test.renderer.documentPlainText.indexOf("Alt")
        verify(captionPosition >= 0, "image alt text is displayed as a caption")
        var captionRect = test.renderer.nativeRectangleForDocumentPositionForTests(captionPosition)
        verify(captionRect.y >= paintedRect.y + paintedRect.height - 1,
          "caption is below the image")
        waitForRendering(test.renderer)
        var paintedImage = grabImage(test.renderer)
        var probe = test.renderer.mapToItem(test.editor.Window.window.contentItem,
          paintedRect.x + paintedRect.width * 0.5, paintedRect.y + paintedRect.height * 0.1)
        var probeX = Math.round(probe.x)
        var probeY = Math.round(probe.y)
        verify(Math.abs(paintedImage.red(probeX, probeY) - 181) < 5 &&
          Math.abs(paintedImage.green(probeX, probeY) - 163) < 5 &&
          paintedImage.blue(probeX, probeY) > 250,
          "resize bounds cover the painted image")
        var corners = ["topLeft", "topRight", "bottomLeft", "bottomRight"]
        for (var cornerIndex = 0; cornerIndex < corners.length; cornerIndex++) {
          var rectangle = test.renderer.imageRectangleAt(0)
          mouseClick(test.renderer, rectangle.x + rectangle.width / 2,
            rectangle.y + rectangle.height / 2, Qt.LeftButton)
          var frame = findChild(test.renderer, "imageSelectionFrame")
          verify(frame && frame.visible, "click shows image selection frame")
          var caret = findChild(test.editor.Window.window.contentItem, "liveCursor")
          verify(caret && !caret.visible, "image selection hides the text caret")
          for (var handleIndex = 0; handleIndex < corners.length; handleIndex++) {
            var visibleHandle = findChild(frame, "imageHandle_" + corners[handleIndex])
            verify(visibleHandle && visibleHandle.visible, "all four handles are visible")
            compare(visibleHandle.color.a, 1, "resize handles are opaque")
            compare(String(visibleHandle.color), String(Qt.rgba(test.renderer.accent.r,
              test.renderer.accent.g, test.renderer.accent.b, 1)), "resize handles have a solid accent fill")
          }
          var corner = corners[cornerIndex]
          var handle = findChild(frame, "imageHandle_" + corner)
          var point = handle.mapToItem(test.renderer, handle.width / 2, handle.height / 2)
          var dx = corner.indexOf("Right") >= 0 ? 20 : -20
          var dy = corner.indexOf("bottom") === 0 ? 10 : -10
          if (variant >= 2) { dx = -dx; dy = -dy }
          mousePress(test.renderer, point.x, point.y, Qt.LeftButton)
          mouseMove(test.renderer, point.x + dx, point.y + dy, 20, Qt.LeftButton)
          if (introRect) {
            compare(test.renderer.cursorRectangleForSource(0).y, introRect.y,
              "resizing does not move the introductory text")
            verify(test.renderer.imageRectangleAt(0).y > introRect.y,
              "resizing keeps the image below the introduction")
          }
          mouseRelease(test.renderer, point.x + dx, point.y + dy, Qt.LeftButton)
          verify(test.editor.text.indexOf("<!-- jotpin:image width=") >= 0,
            "drag commits resize metadata through the product")
          var resized = /jotpin:image width=(\d+)/.exec(test.editor.text)
          verify(resized && (variant >= 2 ? Number(resized[1]) < rectangle.width
            : Number(resized[1]) > rectangle.width), "drag changes the requested image size")
          test.pad.applyEditorHistory("undo")
          compare(test.editor.text, original, "one undo restores the image source")
          wait(350)
        }
      }
    }

    function test_zzzz_save_keeps_newer_selection() {
      test.pad.saveNow()
      tryVerify(function() { return !test.pad.noteSaveInFlight && !test.pad.dirty },
        3000, "previous save settles before the race test")
      test.pad.setEditorText("A note with a newer selection")
      test.pad.noteEdited()
      test.pad.selectEditorRange(test.editor.length, test.editor.length)
      test.pad.saveNow()
      verify(test.pad.noteSaveInFlight, "race test starts a real save")
      test.pad.selectEditorRange(2, 6)
      wait(100)
      compare(test.editor.selectionStart, 2, "saving does not overwrite a newer selection start")
      compare(test.editor.selectionEnd, 6, "saving does not overwrite a newer selection end")
    }

    function cleanupTestCase() {
      var expected = [
        "test_control_press_and_release_routes_to_jotpin",
        "test_ctrl_marker_stays_off_in_blank_space",
        "test_focus_loss_clears_ctrl_state_and_marker",
        "test_product_link_dispatch_requires_ctrl_and_opens_once",
        "test_settings_backdrop_and_text_size",
        "test_typing_after_checklist_preserves_blocks",
        "test_z_backspace_prefix_keeps_row",
        "test_zz_inline_code_typing_color",
        "test_zzz_type_image_and_drag_handles",
        "test_zzzz_save_keeps_newer_selection"
      ]
      var success = qtest_results.failCount === 0 &&
        qtest_results.skipCount === 0 && qtest_results.passCount === 11 &&
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
