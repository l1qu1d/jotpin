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

    function test_zzzzz_file_tabs_wrap_and_scroll() {
      var surface = test.editor.Window.window.contentItem
      var viewport = findChild(surface, "fileTabsViewport")
      var rail = findChild(surface, "fileTabScrollRail")
      var thumb = findChild(surface, "fileTabScrollThumb")
      verify(viewport && rail && thumb, "the production file strip and scrollbar exist")
      var originalFiles = test.pad.openFiles
      var originalRows = test.pad.fileTabRows
      var welcome = {path: test.pad.notePath}
      var longTab = {path: "/tmp/sync-latency-test-" + "bigboss-".repeat(26) + ".md"}
      var untitled = {path: "/tmp/untitled.md"}

      try {
        test.pad.setFileTabRows(2)
        test.pad.openFiles = [welcome, longTab, untitled]
        tryVerify(function() { return rail.visible }, 2000,
          "a wide filename overflows the visible tab strip")
        var first = findChild(viewport.contentItem, "fileTab_0")
        var long = findChild(viewport.contentItem, "fileTab_1")
        var third = findChild(viewport.contentItem, "fileTab_2")
        verify(first && long && third, "all three tab delegates exist")
        compare(third.y, first.y, "the short tabs share the first row")
        verify(third.x >= first.x + first.width && third.x - first.x - first.width < 20,
          "the next short tab sits directly after the first tab")
        verify(long.y > first.y && long.x === 0, "the long tab starts the second row")

        mouseWheel(viewport, 24, 8, 0, -120, Qt.NoButton)
        tryVerify(function() { return viewport.contentX > 0 }, 1000,
          "a regular mouse wheel scrolls the file strip sideways")
        var afterVerticalWheel = viewport.contentX
        mouseWheel(viewport, 24, 8, -120, 0, Qt.NoButton)
        tryVerify(function() { return viewport.contentX > afterVerticalWheel }, 1000,
          "horizontal wheel input also scrolls the file strip")
        mouseWheel(viewport, 24, 8, 0, 120000, Qt.NoButton)
        tryCompare(viewport, "contentX", 0, 1000, "scrolling clamps at the left edge")

        verify(rail.height >= 12 && thumb.height >= 3, "the rail has a larger target and thumb")
        var trackX = Math.floor((thumb.width + rail.width) / 2)
        mousePress(rail, trackX, 1, Qt.LeftButton)
        var afterTrackPress = viewport.contentX
        verify(afterTrackPress > 0, "pressing the bare track in its padding scrolls")
        mouseMove(rail, 10, 1, 20)
        mouseRelease(rail, 10, 1, Qt.LeftButton)
        verify(viewport.contentX < afterTrackPress, "the same track press continues as a drag")

        var thumbX = Math.round(thumb.x + thumb.width / 2)
        var beforeThumbDrag = viewport.contentX
        mouseDrag(rail, thumbX, 1, Math.floor((rail.width - thumbX) / 2), 0, Qt.LeftButton)
        verify(viewport.contentX > beforeThumbDrag, "the thumb drags from the padded hit area")

        test.pad.setFileTabRows(1)
        tryVerify(function() { return long.y === first.y && third.y === first.y }, 2000,
          "the row preference still controls wrapping")
        test.pad.openFiles = [welcome, untitled]
        tryVerify(function() { return !rail.visible && viewport.contentX === 0 }, 2000,
          "closing wide tabs hides the rail and returns the strip to the left")
      } finally {
        test.pad.openFiles = originalFiles
        test.pad.setFileTabRows(originalRows)
      }
    }

    function test_zzzzzz_enter_moves_live_caret_before_parse() {
      var cases = [
        {name: "end of prose", source: "Plain prose", position: 11, count: 2},
        {name: "split prose", source: "Plain prose", position: 6, count: 1},
        {name: "empty note", source: "", position: 0, count: 2},
        {name: "end of fenced code", source: "```\ncode\n```", position: 8, count: 1}
      ]
      for (var i = 0; i < cases.length; i++) {
        var spec = cases[i]
        test.pad.setEditorText(spec.source)
        tryVerify(function() {
          return test.renderer.layoutMatchesCurrentInput() &&
            !test.renderer.parsePending && !test.renderer.parseInFlight &&
            test.renderer.pendingStyledReconcileRequestId < 0
        }, 5000, spec.name + " settles before Enter")
        test.pad.selectEditorRange(spec.position, spec.position)
        test.editor.forceActiveFocus()
        tryCompare(test.editor, "activeFocus", true, 2000)
        var completedParses = test.renderer.parseCompletionCount
        var immediate
        for (var press = 0; press < spec.count; press++) {
          var before = JSON.parse(test.pad.caretState())
          keyPress(Qt.Key_Return)
          immediate = JSON.parse(test.pad.caretState())
          compare(test.editor.text, spec.source.slice(0, spec.position) +
            "\n".repeat(press + 1) + spec.source.slice(spec.position),
            spec.name + " inserts exactly one source newline per Enter")
          compare(test.renderer.parseCompletionCount, completedParses,
            spec.name + " does not need a worker reply to display Enter")
          verify(immediate.layoutSourceMatches &&
            immediate.renderedCursorY > before.renderedCursorY,
            spec.name + " advances the caret vertically on the keypress")
          compare(immediate.liveCursorY, immediate.renderedCursorY,
            spec.name + " paints the caret on the new row immediately")
          keyRelease(Qt.Key_Return)
        }
        tryVerify(function() {
          return test.renderer.parseCompletionCount > completedParses &&
            test.renderer.layoutMatchesCurrentInput() &&
            !test.renderer.parsePending && !test.renderer.parseInFlight &&
            test.renderer.pendingStyledReconcileRequestId < 0
        }, 5000, spec.name + " settles after Enter")
        var settled = JSON.parse(test.pad.caretState())
        verify(Math.abs(settled.renderedCursorY - immediate.renderedCursorY) <= 1 &&
          Math.abs(settled.renderedCursorX - immediate.renderedCursorX) <= 1,
          spec.name + " keeps the caret in place when the worker catches up")
      }
    }

    function settleLivePreview(source, position) {
      test.pad.setEditorText(source)
      test.pad.selectEditorRange(position, position)
      test.editor.forceActiveFocus()
      waitForLivePreview()
    }

    function waitForLivePreview() {
      tryVerify(function() {
        return test.renderer.layoutMatchesCurrentInput() &&
          !test.renderer.parsePending && !test.renderer.parseInFlight &&
          test.renderer.pendingStyledReconcileRequestId < 0 &&
          test.renderer.codeHighlightPendingCount === 0
      }, 5000, "the Live Preview fixture settles")
    }

    function test_zzzzzzz_backspace_to_empty_keeps_preview_row() {
      var cases = [
        {name: "paragraph", before: "First row\n\n", after: "\n\nLast row"},
        {name: "heading", before: "First row\n\n# ", after: "\n\nLast row"},
        {name: "indentation", before: "First row\n  ", after: "\nLast row"},
        {name: "task", before: "- First row\n- [ ] ", after: "\n- Last row"},
        {name: "code block", before: "```js\nFirst row\n", after: "\n```"}
      ]
      for (var spec of cases) {
        var text = "abc"
        settleLivePreview(spec.before + text + spec.after,
          spec.before.length + text.length)
        var initial = JSON.parse(test.pad.caretState())
        verify(initial.liveCursorVisible && initial.renderedCursorY > 0)
        var completedParses = test.renderer.parseCompletionCount
        while (text.length > 0) {
          keyPress(Qt.Key_Backspace)
          text = text.slice(0, -1)
          var caret = JSON.parse(test.pad.caretState())
          compare(test.editor.text, spec.before + text + spec.after)
          compare(caret.sourceLine, initial.sourceLine, spec.name)
          compare(caret.renderedCursorY, initial.renderedCursorY, spec.name)
          compare(caret.liveCursorY, initial.renderedCursorY, spec.name)
          compare(test.renderer.parseCompletionCount, completedParses)
          keyRelease(Qt.Key_Backspace)
        }
        tryVerify(function() {
          return test.renderer.parseCompletionCount > completedParses &&
            test.renderer.layoutMatchesCurrentInput() &&
            test.renderer.pendingStyledReconcileRequestId < 0
        }, 5000, spec.name + " settles after Backspace")
        compare(JSON.parse(test.pad.caretState()).renderedCursorY,
          initial.renderedCursorY, spec.name + " stays on the same row")
      }
    }

    function test_zzzzzzzz_live_viewport_waits_for_structural_edit() {
      var links = ("[Short label](https://example.com/" +
        "abcdef".repeat(25) + ")\n\n").repeat(24)
      settleLivePreview(links + "- \n\n" + links, links.length + 2)
      var initial = JSON.parse(test.pad.caretState())
      var scrollY = test.pad.setEditorScrollForTests(initial.renderedCursorY - 100)
      verify(scrollY > 0 &&
        initial.nativeCursorY > scrollY + test.renderer.viewportHeight,
        "the raw and preview caret rows paint in different viewport regions")
      keyPress(Qt.Key_Backspace)
      compare(test.editor.text, links + "\n\n" + links)
      verify(!test.renderer.layoutMatchesCurrentInput(),
        "removing a projected list marker requires the worker")
      keyRelease(Qt.Key_Backspace)
      compare(test.renderer.viewportY, scrollY,
        "the viewport stays on the rendered row while the worker runs")
      tryVerify(function() {
        return test.renderer.layoutMatchesCurrentInput() &&
          !test.pad.liveCursorRevealPending
      }, 5000, "the editor reveals the settled Live Preview caret")
      var caret = JSON.parse(test.pad.caretState())
      verify(caret.renderedCursorY >= test.renderer.viewportY &&
        caret.renderedCursorY < test.renderer.viewportY + test.renderer.viewportHeight)
    }

    function test_zzzzzzzzz_optimistic_preview_preserves_literal_text() {
      var before = "Above\n\nText"
      var after = "\n\nBelow"
      settleLivePreview(before + after, before.length)
      var initial = JSON.parse(test.pad.caretState())
      var completedParses = test.renderer.parseCompletionCount
      var typed = ""
      for (var character of ["<", "b", ">", "&"]) {
        keyPress(character)
        typed += character
        compare(test.editor.text, before + typed + after)
        verify(test.renderer.documentPlainText.indexOf("Text" + typed) >= 0,
          "the typed character displays literally before parsing")
        compare(JSON.parse(test.pad.caretState()).renderedCursorY,
          initial.renderedCursorY)
        keyRelease(character)
      }
      test.editor.insert(before.length + typed.length, "  more")
      verify(test.renderer.documentPlainText.indexOf("Text" + typed + "  more") >= 0,
        "the immediate preview shows both inserted spaces")
      compare(test.renderer.parseCompletionCount, completedParses)
    }

    function test_zzzzzzzzzz_dash_below_prose_starts_a_bullet() {
      var prose = "Ordinary text"
      settleLivePreview(prose, prose.length)
      keyClick(Qt.Key_Return)
      keyClick("-")
      var expected = prose + "\n\n- "
      tryVerify(function() {
        return test.renderer.layoutMatchesCurrentInput() &&
          !test.renderer.parsePending && !test.renderer.parseInFlight &&
          test.renderer.pendingStyledReconcileRequestId < 0
      }, 5000, "preview settles after typing a dash")
      compare(test.renderer.cursorTargetForSource(0).blockType, "paragraph",
        "the dash keeps preceding text at body size")
      compare(test.renderer.cursorTargetForSource(expected.length - 1).blockType,
        "list", "the dash creates a separate list")
      compare(test.editor.text, expected)
      compare(test.editor.cursorPosition, expected.length)
      verify(test.pad.undoEditorForTests(), "the dash can be undone")
      compare(test.editor.text, prose + "\n",
        "undo removes the dash and its generated separator together")
      verify(test.pad.redoEditorForTests(), "the bullet can be restored")
      compare(test.editor.text, expected)
      test.editor.forceActiveFocus()
      keyClick("x")
      compare(test.editor.text, expected + "x",
        "typing continues inside the new bullet")

      var heading = "Intentional heading\n-"
      settleLivePreview(heading, heading.length)
      compare(test.renderer.cursorTargetForSource(0).blockType, "heading",
        "a loaded Setext heading still renders normally")
      compare(test.editor.text, heading)
    }

    function test_zzzzzzzzzzz_hashes_stay_visible_until_heading_separator() {
      var before = "Above\n\n"
      var after = "\n\nBelow"
      settleLivePreview(before + after, before.length)
      var hashes = ""
      for (var count = 1; count <= 7; count++) {
        keyClick("#")
        hashes += "#"
        compare(test.editor.text, before + hashes + after)
        waitForLivePreview()
        verify(test.renderer.documentPlainText.indexOf(hashes) >= 0,
          "a paused " + hashes + " remains visible")
        compare(test.renderer.cursorTargetForSource(before.length + 1).blockType,
          "paragraph", "hashes alone keep body formatting")
        var start = test.renderer.cursorRectangleForSource(before.length)
        var end = test.renderer.cursorRectangleForSource(before.length + hashes.length)
        verify(end.x > start.x && end.y === start.y, "the hashes have caret stops")
      }
      keyClick(Qt.Key_Backspace)
      keyClick(Qt.Key_Backspace)
      compare(test.editor.text, before + "#####" + after,
        "Backspace removes one literal hash at a time")

      settleLivePreview(before + "#" + after, before.length + 1)
      for (var character of ["t", "a", "g"]) keyClick(character)
      waitForLivePreview()
      compare(test.editor.text, before + "#tag" + after)
      verify(test.renderer.documentPlainText.indexOf("#tag") >= 0)
      compare(test.renderer.cursorTargetForSource(before.length + 1).blockType, "paragraph")

      settleLivePreview(before + "#" + after, before.length + 1)
      keyClick(Qt.Key_Return)
      waitForLivePreview()
      compare(test.editor.text, before + "#\n" + after)
      verify(test.renderer.documentPlainText.indexOf("#") >= 0,
        "leaving the row keeps the literal hash visible")

      settleLivePreview(before + "#" + after, before.length + 1)
      keyClick(Qt.Key_Space)
      waitForLivePreview()
      compare(test.renderer.cursorTargetForSource(before.length + 1).blockType, "heading")
      verify(test.renderer.documentPlainText.indexOf("#") === -1,
        "the heading separator commits the formatting")
      keyClick("T")
      waitForLivePreview()
      compare(test.editor.text, before + "# T" + after)
      compare(test.renderer.cursorTargetForSource(before.length + 1).blockType, "heading")
      verify(test.renderer.documentPlainText.indexOf("T") >= 0)
    }

    function test_zzzzzzzzzzzz_other_standalone_markers_remain_editable() {
      var before = "Above\n\n"
      var after = "\n\nBelow"
      var cases = [
        {marker: ">", suffix: " quote", block: "blockquote"},
        {marker: ">>", suffix: " quote", block: "blockquote"},
        {marker: "1)", suffix: " list", block: "list"},
        {marker: "1.", suffix: " list", block: "list"},
        {marker: "+", suffix: " list", block: "list"},
        {marker: "*", suffix: " list", block: "list"},
        {marker: "*", suffix: "*bold**", block: "paragraph"},
        {marker: "`", suffix: "code`", block: "paragraph"},
        {marker: "~~", suffix: "strike~~", block: "paragraph"},
        {marker: "[", suffix: "link](https://example.com)", block: "paragraph"}
      ]
      for (var spec of cases) {
        settleLivePreview(before + after, before.length)
        for (var marker of spec.marker) keyClick(marker)
        waitForLivePreview()
        compare(test.editor.text, before + spec.marker + after)
        verify(test.renderer.documentPlainText.indexOf(spec.marker) >= 0,
          spec.marker + " remains visible before the next key")
        compare(test.renderer.cursorTargetForSource(before.length + 1).blockType,
          "paragraph", spec.marker + " starts as literal text")
        for (var character of spec.suffix) keyClick(character)
        waitForLivePreview()
        compare(test.editor.text, before + spec.marker + spec.suffix + after)
        compare(test.renderer.cursorTargetForSource(before.length + 1).blockType,
          spec.block, spec.marker + spec.suffix + " applies the expected structure")
        if (spec.suffix === "*bold**") {
          var format = test.renderer.characterFormatForSourceForTests(before.length + 2)
          verify(format.valid && format.bold, "line-start emphasis reaches the renderer")
        }
      }
    }

    function typeMarkdown(value) {
      for (var character of value) {
        if (character === "\n") keyClick(Qt.Key_Return)
        else keyClick(character)
      }
      waitForLivePreview()
    }

    function checkQuoteRow(position, expectedY, depth) {
      var caret = test.renderer.cursorRectangleForSource(position)
      verify(validRectangle(caret), "the quoted source row has a caret")
      if (expectedY >= 0) compare(caret.y, expectedY)
      var rails = test.renderer.quoteRailRects.filter(function(rail) {
        return rail.y <= caret.y && rail.y + rail.height >= caret.y + caret.height
      })
      compare(rails.length, depth, "each quote rail covers the editable row " +
        JSON.stringify({source: test.editor.text, position: position, caret: caret,
          rails: test.renderer.quoteRailRects}))
      if (rails.length > 0) verify(rails[rails.length - 1].x < caret.x)
      return caret.y
    }

    function observeLiveCaretRows(operation) {
      var rows = [test.pad.liveCursorRect.y]
      var record = function() { rows.push(test.pad.liveCursorRect.y) }
      test.pad.liveCursorRectChanged.connect(record)
      try {
        operation()
        record()
        waitForLivePreview()
        wait(35)
        return rows
      } finally {
        test.pad.liveCursorRectChanged.disconnect(record)
      }
    }

    function test_zzzzzzzzzzzzz_empty_quote_keeps_caret_and_rail_on_its_row() {
      var prose = "Above and 4k."
      for (var after of ["", "\nFollowing"]) {
        settleLivePreview(prose + "\n" + after, prose.length + 1)
        var proseY = test.renderer.cursorRectangleForSource(0).y
        typeMarkdown(">")
        var rowY = test.renderer.cursorRectangleForSource(prose.length + 2).y
        verify(rowY > proseY, "the new quote is below the prose")
        var paintedRows = observeLiveCaretRows(function() { keyClick(Qt.Key_Space) })
        verify(paintedRows.every(function(y) { return y === rowY }),
          "Space keeps the painted caret on its original row throughout the quote transition: " +
            JSON.stringify(paintedRows))
        compare(test.editor.text, prose + "\n> " + after)
        checkQuoteRow(test.editor.cursorPosition, rowY, 1)
        compare(JSON.parse(test.pad.caretState()).liveCursorY, rowY)
        typeMarkdown("x")
        checkQuoteRow(test.editor.cursorPosition, rowY, 1)
        keyClick(Qt.Key_Backspace)
        waitForLivePreview()
        checkQuoteRow(test.editor.cursorPosition, rowY, 1)
        if (after) verify(test.renderer.cursorRectangleForSource(
          test.editor.text.indexOf("Following")).y > rowY)
      }

      for (var quote of ["> One\n> \n> Two", "> \n> Two", "> One\n> ", "> \n> ",
          "> One\n>> \n>> Two", "> > "]) {
        settleLivePreview(prose + "\n\n" + quote + "\n\nFollowing", prose.length + 2)
        var previousY = test.renderer.cursorRectangleForSource(0).y
        var position = prose.length + 2
        for (var line of quote.split("\n")) {
          var contentEnd = position + line.replace(/\r$/, "").length
          var depth = line.match(/>/g).length
          var y = checkQuoteRow(contentEnd, -1, depth)
          verify(y > previousY, "each quoted line has a separate editable row")
          previousY = y
          position += line.length + 1
        }
        verify(test.renderer.cursorRectangleForSource(test.editor.text.indexOf(
          "Following")).y > previousY, "text after an empty quote stays below it")
      }
    }

    function test_zzzzzzzzzzzzzz_markdown_typing_keeps_visible_content_on_its_row() {
      var before = "Above\n\n"
      var after = "\n\nBelow"
      var cases = [
        {name: "ATX heading", keys: "# Title", html: "<h1>Title</h1>", visible: "Title"},
        {name: "Setext heading", keys: "Title\n===", html: "<h1>Title</h1>", visible: "Title"},
        {name: "emphasis", keys: "_italic_", html: "<em>italic</em>", visible: "italic"},
        {name: "strong", keys: "**bold**", html: "<strong>bold</strong>", visible: "bold"},
        {name: "strike", keys: "~~strike~~", html: "<del>strike</del>", visible: "strike"},
        {name: "escape", keys: "\\# hash", html: "<p># hash</p>", visible: "# hash"},
        {name: "entity", keys: "&amp;", html: "<p>&#x26;</p>", visible: "&"},
        {name: "inline code", keys: "`code`", html: "jotpin-inline-code", visible: "code"},
        {name: "link", keys: "[label](https://example.com/long-target)", html: "<a href=", visible: "label"},
        {name: "autolink", keys: "<https://example.com>", html: "<a href=", visible: "https://example.com"},
        {name: "dash list", keys: "-entry", source: "- entry", html: "jotpin-list-item", visible: "entry"},
        {name: "asterisk list", keys: "* entry", html: "jotpin-list-item", visible: "entry"},
        {name: "plus list", keys: "+ entry", html: "jotpin-list-item", visible: "entry"},
        {name: "ordered list", keys: "1) entry", html: "jotpin-list-item", visible: "entry"},
        {name: "divider", keys: "***", html: "<hr>", visible: ""},
        {name: "alternate divider", keys: "___", html: "<hr>", visible: ""}
      ]
      for (var spec of cases) {
        settleLivePreview(before + after, before.length)
        typeMarkdown(spec.keys)
        var source = before + (spec.source || spec.keys) + after
        compare(test.editor.text, source, spec.name + " preserves its Markdown source")
        verify(test.renderer.renderedHtml.indexOf(spec.html) >= 0,
          spec.name + " produces the expected rendered structure " +
            test.renderer.renderedHtml)
        verify(test.renderer.documentPlainText.indexOf(spec.visible) >= 0,
          spec.name + " keeps its content visible")
        var caret = JSON.parse(test.pad.caretState())
        var firstY = test.renderer.cursorRectangleForSource(0).y
        var nextY = test.renderer.cursorRectangleForSource(source.indexOf("Below")).y
        verify(caret.liveCursorY > firstY && caret.liveCursorY < nextY,
          spec.name + " keeps the caret between its neighbors")
        var content = spec.visible ? source.indexOf(spec.visible, before.length) : -1
        if (content >= 0)
          compare(caret.liveCursorY, test.renderer.cursorRectangleForSource(
            content + 1).y, spec.name + " stays on its rendered content row")
        if (spec.html === "<hr>")
          compare(caret.liveCursorY, test.renderer.cursorRectangleForSource(
            before.length).y, "the caret stays on the painted divider")
        keyClick(Qt.Key_Backspace)
        waitForLivePreview()
        compare(test.editor.text, source.slice(0, caret.cursorPosition - 1) +
          source.slice(caret.cursorPosition), spec.name + " deletes only its last source character")
      }
    }

    function test_zzzzzzzzzzzzzzz_empty_task_and_table_boundary_keep_their_rows() {
      var before = "Above\n\n"
      var after = "\n\nBelow"
      settleLivePreview(before + after, before.length)
      typeMarkdown("-[ ] ")
      compare(test.editor.text, before + "- [ ] " + after)
      compare(test.renderer.taskCheckboxRects.length, 1, "an empty task shows its checkbox")
      var box = test.renderer.taskCheckboxRects[0]
      var row = test.renderer.cursorRectangleForSource(test.editor.cursorPosition)
      verify(box.y >= row.y && box.y < row.y + row.height)
      mouseClick(test.renderer, box.x + box.width / 2, box.y + box.height / 2,
        Qt.LeftButton)
      waitForLivePreview()
      compare(test.editor.text, before + "- [x] " + after)
      test.pad.selectEditorRange(before.length + 6, before.length + 6)
      typeMarkdown("x")
      compare(test.editor.text, before + "- [x] x" + after)
      compare(test.renderer.cursorRectangleForSource(test.editor.cursorPosition).y, row.y)

      var table = "| Left | Right |\n| --- | --- |\n| one | two |"
      settleLivePreview(before + table + after, before.length + table.length)
      var lastCell = test.renderer.cursorRectangleForSource(
        test.editor.text.indexOf("two"))
      var boundary = test.renderer.cursorRectangleForSource(test.editor.cursorPosition)
      compare(boundary.y, lastCell.y, "the last pipe stays on the final table row")
      var cellEnd = test.editor.text.indexOf("two") + 3
      test.pad.selectEditorRange(cellEnd, cellEnd)
      typeMarkdown("x")
      verify(test.editor.text.indexOf("| one | twox |") >= 0, "caret editing stays in the final cell")
      compare(test.renderer.cursorRectangleForSource(test.editor.cursorPosition).y,
        test.renderer.cursorRectangleForSource(test.editor.text.indexOf("twox")).y,
        "the caret stays in the edited row with the contextual table toolbar open")

      var emptyRow = "|   |   |"
      var separator = "| --- | --- |"
      var body = "| one | two |"
      table = [emptyRow, separator, emptyRow, body, emptyRow].join("\n")
      settleLivePreview(before + table + after, before.length)
      var headerPosition = before.length + 2
      var middlePosition = before.length + emptyRow.length + separator.length + 4
      var populatedPosition = test.editor.text.indexOf("two")
      var endingPosition = before.length + table.length - 2
      var headerY = test.renderer.cursorRectangleForSource(headerPosition).y
      var middleY = test.renderer.cursorRectangleForSource(middlePosition).y
      var populatedY = test.renderer.cursorRectangleForSource(populatedPosition).y
      var endingY = test.renderer.cursorRectangleForSource(endingPosition).y
      var belowY = test.renderer.cursorRectangleForSource(test.editor.text.indexOf("Below")).y
      verify(test.renderer.cursorRectangleForSource(0).y < headerY &&
        headerY < middleY && middleY < populatedY && populatedY < endingY &&
        endingY < belowY, "empty table rows each have their own editable row")
      verify(test.renderer.cursorRectangleForSource(middlePosition + 4).x >
        test.renderer.cursorRectangleForSource(middlePosition).x,
        "an empty row keeps each cell separately reachable")
      test.pad.selectEditorRange(middlePosition, middlePosition)
      typeMarkdown("z")
      var edited = test.editor.text.indexOf("z")
      verify(edited >= 0, "an empty table cell accepts typing")
      compare(test.renderer.cursorRectangleForSource(test.editor.cursorPosition).y,
        test.renderer.cursorRectangleForSource(edited).y)
    }

    function test_zzzzzzzzzzzzzzzz_reference_links_and_fences_keep_editable_rows() {
      var before = "Above\n\n"
      var after = "\n\nBelow"
      var definition = "\n\n[ref]: example.md"
      settleLivePreview(before + definition + after, before.length)
      typeMarkdown("[label][ref]")
      var source = before + "[label][ref]" + definition + after
      compare(test.editor.text, source)
      verify(test.renderer.renderedHtml.indexOf('href="example.md"') >= 0)
      var linkEnd = test.renderer.cursorRectangleForSource(test.editor.cursorPosition)
      compare(linkEnd.y, test.renderer.cursorRectangleForSource(before.length + 2).y)
      var definitionStart = source.indexOf("[ref]:")
      var definitionEnd = source.indexOf(after, definitionStart)
      var definitionCaret = test.renderer.cursorRectangleForSource(definitionEnd)
      compare(definitionCaret.y, test.renderer.cursorRectangleForSource(definitionStart + 1).y)
      verify(definitionCaret.y > linkEnd.y && definitionCaret.y <
        test.renderer.cursorRectangleForSource(source.indexOf("Below")).y)

      settleLivePreview(before + after, before.length)
      typeMarkdown("```")
      compare(test.editor.text, before + "```\n\n```" + after)
      typeMarkdown("js")
      var header = test.renderer.cursorRectangleForSource(test.editor.cursorPosition)
      typeMarkdown("\n")
      var body = test.renderer.cursorRectangleForSource(test.editor.cursorPosition)
      verify(body.y > header.y, "Return enters the reserved code body")
      typeMarkdown("var value = 1")
      compare(test.editor.text, before + "```js\nvar value = 1\n```" + after)
      compare(test.renderer.codeBlocks[0].language, "js")
      verify(test.renderer.codeHighlightedPaintCount > 0)
      compare(test.renderer.cursorRectangleForSource(test.editor.cursorPosition).y, body.y)
    }

    function test_zzzzzzzzzzzzzzzzz_caret_stays_on_the_intended_row_during_edits() {
      var cases = [
        {source: "Above\n\nplain\n\nBelow", position: 12, key: "x", text: "plainx", rowDelta: 0},
        {source: "Above\n\nplain\n\nBelow", position: 12, key: Qt.Key_Backspace, text: "plai", rowDelta: 0},
        {source: "Above\n\nplain\n\nBelow", position: 13, key: Qt.Key_Return, text: "plain\n\n\nBelow", rowDelta: 1},
        {source: "Above\nword\nBelow", position: 6, key: Qt.Key_Backspace, text: "Aboveword", rowDelta: -1},
        {source: "Above\n\nplain\n\nBelow", position: 7, selectionEnd: 12,
          key: "x", text: "Above\n\nx\n\nBelow", rowDelta: 0}
      ]
      for (var spec of cases) {
        settleLivePreview(spec.source, spec.position)
        if (spec.selectionEnd !== undefined)
          test.pad.selectEditorRange(spec.position, spec.selectionEnd)
        tryCompare(test.pad, "liveCursorSourcePosition", test.editor.cursorPosition, 2000)
        var startY = test.pad.liveCursorRect.y
        var expectedY = startY + spec.rowDelta * test.pad.liveCursorRect.height
        var rows = observeLiveCaretRows(function() { keyClick(spec.key) })
        verify(test.editor.text.indexOf(spec.text) >= 0)
        compare(test.pad.liveCursorRect.y, expectedY)
        verify(rows.every(function(y) { return y === startY || y === expectedY }),
          "the caret only visits the starting and destination rows " + JSON.stringify(rows))
      }

      var wrapped = "This is a wrapped line of text. ".repeat(32)
      settleLivePreview(wrapped, Math.floor(wrapped.length / 2))
      tryCompare(test.pad, "liveCursorSourcePosition", test.editor.cursorPosition, 2000)
      var wrappedY = test.pad.liveCursorRect.y
      var wrappedHeight = test.pad.liveCursorRect.height
      keyClick(Qt.Key_Down)
      tryVerify(function() { return test.pad.liveCursorRect.y > wrappedY }, 2000)
      compare(test.pad.liveCursorRect.y, wrappedY + wrappedHeight)
      keyClick(Qt.Key_Up)
      tryCompare(test.pad, "liveCursorSourcePosition", test.editor.cursorPosition, 2000)
      compare(test.pad.liveCursorRect.y, wrappedY)
    }

    function test_zzzzzzzzzzzzzzzzzz_emoji_caret_and_backspace_preserve_text() {
      var before = "Above\n\na"
      var after = "b\n\nBelow"
      for (var glyph of ["🙂", "👩‍💻", "🇺🇸", "🫶🏽"]) {
        var source = before + glyph + after
        var glyphEnd = before.length + glyph.length
        settleLivePreview(source, before.length)
        tryCompare(test.pad, "liveCursorSourcePosition", before.length, 2000)
        var originalX = test.pad.liveCursorRect.x
        keyClick(Qt.Key_Right)
        compare(test.editor.cursorPosition, glyphEnd)
        tryCompare(test.pad, "liveCursorSourcePosition", glyphEnd, 2000)
        verify(test.pad.liveCursorRect.x > originalX, "Right moves visibly past " + glyph)
        keyClick(Qt.Key_Left)
        compare(test.editor.cursorPosition, before.length)
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        compare(test.editor.selectedText, glyph)

        test.pad.selectEditorRange(glyphEnd, glyphEnd)
        tryCompare(test.pad, "liveCursorSourcePosition", test.editor.cursorPosition, 2000)
        var y = test.pad.liveCursorRect.y
        var rows = observeLiveCaretRows(function() { keyClick(Qt.Key_Backspace) })
        compare(test.editor.text, before + after)
        compare(test.editor.cursorPosition, before.length)
        verify(rows.every(function(row) { return row === y }),
          "deleting " + glyph + " keeps the caret on its row")
        verify(test.pad.undoEditorForTests(), "deleting " + glyph + " is undoable")
        compare(test.editor.text, source)
      }
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
        "test_zzzz_save_keeps_newer_selection",
        "test_zzzzz_file_tabs_wrap_and_scroll",
        "test_zzzzzz_enter_moves_live_caret_before_parse",
        "test_zzzzzzz_backspace_to_empty_keeps_preview_row",
        "test_zzzzzzzz_live_viewport_waits_for_structural_edit",
        "test_zzzzzzzzz_optimistic_preview_preserves_literal_text",
        "test_zzzzzzzzzz_dash_below_prose_starts_a_bullet",
        "test_zzzzzzzzzzz_hashes_stay_visible_until_heading_separator",
        "test_zzzzzzzzzzzz_other_standalone_markers_remain_editable",
        "test_zzzzzzzzzzzzz_empty_quote_keeps_caret_and_rail_on_its_row",
        "test_zzzzzzzzzzzzzz_markdown_typing_keeps_visible_content_on_its_row",
        "test_zzzzzzzzzzzzzzz_empty_task_and_table_boundary_keep_their_rows",
        "test_zzzzzzzzzzzzzzzz_reference_links_and_fences_keep_editable_rows",
        "test_zzzzzzzzzzzzzzzzz_caret_stays_on_the_intended_row_during_edits",
        "test_zzzzzzzzzzzzzzzzzz_emoji_caret_and_backspace_preserve_text"
      ]
      var success = qtest_results.failCount === 0 &&
        qtest_results.skipCount === 0 && qtest_results.passCount === expected.length + 1 &&
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
