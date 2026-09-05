import QtQuick
import QtTest

Item {
  id: scene
  width: 520
  height: 360

  property int probePressCount: 0
  property int selectionAnchor: 0
  property int selectionTarget: 0
  property string linkLabel: "test"
  property string linkTarget: "https://google.com"
  property string source: "# Welcome to JotPin\n\n" +
    "| JotPin handles | Great for |\n" +
    "| --- | --- |\n" +
    "| Lists and tasks | Todos and planning |f\n" +
    "| Tables and links | Research and reference |\n" +
    "| Images and code | Visual notes and snippets |\n\n" +
    "- [ ] Click a checkbox in Preview\n" +
    "- [x] Enjoy checking something off\n\n" +
    "To add an image, use `![Alt text](/absolute/path.png)`.\n\n" +
    "![resizable image](markdown-image.svg)<!-- jotpin:image width=202 -->\n\n" +
    "```tes\n" +
    "test\n" +
    "```\n\n" +
    "```\n" +
    "plain code without a language\n" +
    "```\n\n" +
    "## Useful shortcuts\n\n" +
    "| Shortcut | Action |\n" +
    "| --- | --- |\n" +
    "| `Ctrl+P` | Toggle Preview / Raw Markdown |\n\n" +
    "## Tips\n\n" +
    "ffffffffffffffffffffffffffffffff\n\n" +
    "Your notes remain ordinary files.\n\n" +
    "Keep editing below the fenced code block.\n\n" +
    "Open [" + linkLabel + "](" + linkTarget + ") with Ctrl+click."

  Flickable {
    id: viewport
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: true
    acceptedButtons: Qt.NoButton
    contentWidth: width
    contentHeight: Math.max(height, sourceLayout.contentHeight,
      display.implicitHeight)

    TextEdit {
      id: sourceLayout
      width: viewport.width
      height: Math.max(viewport.height, contentHeight)
      text: scene.source
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.Wrap
      font.family: "monospace"
      font.pixelSize: 16
      leftPadding: 16
      rightPadding: 16
      topPadding: 16
      bottomPadding: 16
      color: "transparent"
      enabled: false
      z: 0
    }

    NativeMarkdownDisplay {
      id: display
      z: 1
      width: viewport.width
      height: Math.max(viewport.height, implicitHeight)
      sourceText: scene.source
      foreground: "#ffcca3"
      background: "#090b16"
      surfaceBackground: "#090b16"
      accent: "#b5a3ff"
      baseUrl: Qt.resolvedUrl("./")
      fontFamily: "monospace"
      bodyPixelSize: 16
      interactiveEditsEnabled: true
      selectionStart: scene.selectionAnchor
      selectionEnd: scene.selectionTarget

      onSourcePositionRequested: function(position) {
        scene.selectionAnchor = position
        scene.selectionTarget = position
      }
      onSourceSelectionRequested: function(anchor, target) {
        scene.selectionAnchor = anchor
        scene.selectionTarget = target
      }
    }

    MouseArea {
      id: productionMouseShield
      anchors.fill: parent
      z: 0
      acceptedButtons: Qt.LeftButton
      onPressed: mouse.accepted = true
    }
  }

  MouseArea {
    id: directProbe
    z: 100
    x: scene.width - 30
    y: 0
    width: 30
    height: 30
    onPressed: scene.probePressCount++
  }

  TestCase {
    id: testCase
    name: "NativeMarkdownMouseBelowFence"
    when: windowShown

    SignalSpy {
      id: positionSpy
      target: display
      signalName: "sourcePositionRequested"
    }

    SignalSpy {
      id: selectionSpy
      target: display
      signalName: "sourceSelectionRequested"
    }

    SignalSpy {
      id: imageResizeSpy
      target: display
      signalName: "imageResizeRequested"
    }

    SignalSpy {
      id: taskToggleSpy
      target: display
      signalName: "taskToggled"
    }

    SignalSpy {
      id: linkActivationSpy
      target: display
      signalName: "linkActivated"
    }

    function caretAt(position, label) {
      verify(position >= 0, "fixture position is present: " + label)
      var rectangle = display.cursorRectangleForSource(position)
      verify(rectangle !== null && rectangle !== undefined &&
        isFinite(Number(rectangle.x)) && isFinite(Number(rectangle.y)),
        "fixture position has caret geometry: " + label)
      return {position: position, rectangle: rectangle}
    }

    function caretFor(token, offset) {
      return caretAt(scene.source.indexOf(token) + Number(offset || 0), token)
    }

    function center(rectangle) {
      return {x: Number(rectangle.x) +
          Math.max(1, Number(rectangle.width)) / 2,
        y: Number(rectangle.y) +
          Math.max(1, Number(rectangle.height)) / 2}
    }

    function reveal(rectangle) {
      viewport.contentY = Math.max(0, Math.min(
        viewport.contentHeight - viewport.height,
        Number(rectangle.y) - viewport.height / 3))
      wait(20)
    }

    function clickAndVerify(token, offset) {
      var target = caretFor(token, offset)
      reveal(target.rectangle)
      var point = center(target.rectangle)
      var windowPoint = display.mapToItem(scene, point.x, point.y)
      verify(Math.abs(Number(display.sourcePositionForPoint(
          point.x, point.y)) - target.position) <= 2,
        "the click point maps back to its Markdown source position")
      verify(windowPoint.x >= 0 && windowPoint.x < scene.width &&
        windowPoint.y >= 0 && windowPoint.y < scene.height,
        "click target is inside the visible viewport: " +
          JSON.stringify({token: token, local: point, visible: windowPoint,
            contentY: viewport.contentY, displayHeight: display.height}))
      positionSpy.clear()
      mouseClick(scene,
        windowPoint.x, windowPoint.y, Qt.LeftButton)
      tryCompare(positionSpy, "count", 1, 2000)
      var returned = Number(positionSpy.signalArguments[0][0])
      verify(Math.abs(returned - target.position) <= 2,
        "click below the fence maps near " + token + ": " +
          JSON.stringify({expected: target.position, returned: returned}))
      compare(scene.selectionAnchor, scene.selectionTarget,
        "a click collapses the source selection")
      verify(Math.abs(scene.selectionTarget - target.position) <= 2,
        "the application selection follows the clicked source position")
    }

    function renderedLinkPoint() {
      var linkStart = scene.source.indexOf("[" + scene.linkLabel + "](") + 1
      var expectedTarget = String(display.linkSourceUrl(scene.linkTarget))
      var rectangle = display.cursorRectangleForSource(linkStart + 2)
      verify(rectangle !== null && rectangle !== undefined,
        "the rendered link has source-mapped caret geometry")
      var point = center(rectangle)
      compare(String(display.linkTargetForPoint(point.x, point.y)),
        expectedTarget,
        "the visible link label resolves its exact Markdown target")
      return point
    }

    function initTestCase() {
      waitForRendering(scene)
      compare(viewport.interactive, true,
        "touch and flick scrolling remain enabled")
      compare(viewport.acceptedButtons, Qt.NoButton,
        "physical mouse buttons cannot pan the viewport")
      mouseClick(directProbe, 10, 10, Qt.LeftButton)
      compare(scene.probePressCount, 1, "QtTest delivers pointer events")
      tryVerify(function() {
        return display.layoutReady && display.layoutMatchesCurrentInput() &&
          !display.parseInFlight && !display.parsePending &&
          display.codeHighlightPendingCount === 0
      }, 15000, "native Markdown fixture settles")
    }

    function test_clicks_in_scratchpad_shaped_fence() {
      var languageStart = scene.source.indexOf("```tes") + 3
      var language = caretAt(languageStart + 2, "scratchpad language")
      var beforeFence = caretFor("To add an image", 5)
      var finalLine = caretFor("Keep editing", 5)
      verify(Number(language.rectangle.y) > Number(beforeFence.rectangle.y),
        "the resized image remains before the language-label geometry")
      verify(Number(finalLine.rectangle.y) > Number(language.rectangle.y),
        "the final line retains distinct rendered geometry")
      reveal(language.rectangle)
      var languagePoint = center(language.rectangle)
      var languageWindowPoint = display.mapToItem(
        scene, languagePoint.x, languagePoint.y)
      positionSpy.clear()
      mouseClick(scene, languageWindowPoint.x, languageWindowPoint.y,
        Qt.LeftButton)
      tryCompare(positionSpy, "count", 1, 2000)
      verify(Math.abs(Number(positionSpy.signalArguments[0][0]) -
          language.position) <= 1,
        "the scratchpad-shaped language label accepts a mouse click")
      clickAndVerify("test", 2)
      clickAndVerify("To add an image", 5)
      clickAndVerify("Useful shortcuts", 5)
      clickAndVerify("Toggle Preview", 5)
      clickAndVerify("Keep editing", 5)
    }

    function test_clicks_rendered_task_checkbox() {
      tryCompare(display.taskCheckboxRects, "length", 2, 4000)
      var checkbox = display.taskCheckboxRects[0]
      verify(checkbox && !Boolean(checkbox.checked),
        "the first task exposes its unchecked rendered control")
      verify(Number(checkbox.hitWidth) > Number(checkbox.width) &&
          Number(checkbox.hitHeight) > Number(checkbox.height),
        "the rendered checkbox has a larger click target than its outline")
      reveal(checkbox)
      var localPoint = {
        x: Number(checkbox.hitX) + Number(checkbox.hitWidth) / 2,
        y: Number(checkbox.hitY) + Number(checkbox.hitHeight) / 2
      }
      var windowPoint = display.mapToItem(scene, localPoint.x, localPoint.y)
      taskToggleSpy.clear()
      positionSpy.clear()
      mouseClick(scene, windowPoint.x, windowPoint.y, Qt.LeftButton)
      tryCompare(taskToggleSpy, "count", 1, 2000)
      compare(Number(taskToggleSpy.signalArguments[0][0]),
        scene.source.indexOf("- [ ] Click a checkbox in Preview"),
        "clicking the visual checkbox targets its exact Markdown task line")
      compare(positionSpy.count, 0,
        "a checkbox click toggles instead of moving the text caret")
    }

    function test_ctrl_click_activates_link_only_with_modifier() {
      var linkStart = scene.source.indexOf("[" + scene.linkLabel + "](") + 1
      verify(linkStart >= 0, "the link label is present in the fixture")
      var target = caretAt(linkStart + 2, "Markdown link label")
      reveal(target.rectangle)
      var point = renderedLinkPoint()
      var windowPoint = display.mapToItem(scene, point.x, point.y)
      verify(windowPoint.x >= 0 && windowPoint.x < scene.width &&
        windowPoint.y >= 0 && windowPoint.y < scene.height,
        "the rendered link target is inside the visible viewport: " +
          JSON.stringify({local: point, visible: windowPoint,
            contentY: viewport.contentY}))
      compare(String(display.linkTargetForPoint(point.x, point.y)),
        String(display.linkSourceUrl(scene.linkTarget)),
        "the rendered link hit-test resolves the expected target")

      linkActivationSpy.clear()
      mouseClick(scene, windowPoint.x, windowPoint.y, Qt.LeftButton)
      wait(50)
      compare(linkActivationSpy.count, 0,
        "a plain link click does not activate the external target")

      mouseClick(scene, windowPoint.x, windowPoint.y, Qt.LeftButton,
        Qt.ControlModifier)
      tryCompare(linkActivationSpy, "count", 1, 2000,
        "Ctrl+click emits one link activation")
      compare(String(linkActivationSpy.signalArguments[0][0]),
        String(display.linkSourceUrl(scene.linkTarget)),
        "Ctrl+click emits the resolved link target")
      wait(50)
      compare(linkActivationSpy.count, 1,
        "one Ctrl+click activates the link exactly once")
    }

    function test_ctrl_link_cursor_stays_visible() {
      var linkStart = scene.source.indexOf("[" + scene.linkLabel + "](") + 1
      var target = caretAt(linkStart + 2, "stable link cursor")
      reveal(target.rectangle)
      var point = renderedLinkPoint()
      var windowPoint = display.mapToItem(scene, point.x, point.y)

      mouseMove(scene, windowPoint.x, windowPoint.y)
      tryCompare(display, "pointerCursorShape", Qt.PointingHandCursor, 2000,
        "a link exposes a visible hand cursor before Ctrl is pressed")
      display.controlKeyHeld = true
      tryCompare(display, "linkPointerMarkerVisible", true, 2000,
        "JotPin supplies its own visible target marker while Ctrl is held")
      verify(Math.abs(Number(display.linkPointerMarkerCenter.x) - point.x) <= 1 &&
          Math.abs(Number(display.linkPointerMarkerCenter.y) - point.y) <= 1,
        "the in-app marker identifies the exact Ctrl+click position")
      mousePress(scene, windowPoint.x, windowPoint.y, Qt.LeftButton,
        Qt.ControlModifier)
      compare(display.pointerCursorShape, Qt.PointingHandCursor,
        "the link cursor remains a visible hand while Ctrl is held")
      compare(display.linkPointerMarkerVisible, true,
        "the in-app target marker remains visible during Ctrl+mouse-down")
      mouseRelease(scene, windowPoint.x, windowPoint.y, Qt.LeftButton,
        Qt.ControlModifier)
      compare(display.pointerCursorShape, Qt.PointingHandCursor,
        "the link cursor remains stable after Ctrl+click")
      compare(display.linkPointerMarkerVisible, true,
        "the in-app target marker remains until Ctrl is released")
      display.controlKeyHeld = false
      tryCompare(display, "linkPointerMarkerVisible", false, 2000,
        "releasing Ctrl removes only JotPin's temporary marker")
    }

    function test_ctrl_link_blank_space_is_inert() {
      var original = scene.source
      try {
        scene.source = "Before\n\n[" + scene.linkLabel + "](" + scene.linkTarget + ")"
        tryVerify(function() {
          return display.layoutMatchesCurrentInput() && !display.parseInFlight &&
            !display.parsePending
        }, 15000)
        viewport.contentY = 0
        var start = scene.source.indexOf("[" + scene.linkLabel) + 1
        var first = display.cursorRectangleForSource(start)
        var last = display.cursorRectangleForSource(start + scene.linkLabel.length)
        var middleY = first.y + first.height / 2
        var points = [
          {x: first.x - 4, y: middleY},
          {x: last.x + 4, y: middleY},
          {x: scene.width - 30, y: middleY},
          {x: first.x + 5, y: first.y - 4},
          {x: first.x + 5, y: first.y + first.height + 4},
          {x: first.x + 5, y: scene.height - 20}
        ]
        display.controlKeyHeld = true
        linkActivationSpy.clear()
        for (var i = 0; i < points.length; i++) {
          var point = points[i]
          compare(String(display.linkTargetForPoint(point.x, point.y)), "",
            "blank space must not snap to a link: " + JSON.stringify(point))
          mouseMove(scene, point.x, point.y)
          tryCompare(display, "linkPointerMarkerVisible", false, 2000)
          mouseClick(scene, point.x, point.y, Qt.LeftButton, Qt.ControlModifier)
          compare(linkActivationSpy.count, 0, "blank-space Ctrl+click is inert")
        }
        for (var column = 0; column < scene.linkLabel.length; column++) {
          var a = display.cursorRectangleForSource(start + column)
          var b = display.cursorRectangleForSource(start + column + 1)
          var x = (a.x + b.x) / 2
          compare(String(display.linkTargetForPoint(x, middleY)), scene.linkTarget,
            "each visible link character remains clickable")
          mouseClick(scene, x, middleY, Qt.LeftButton, Qt.ControlModifier)
          compare(linkActivationSpy.count, column + 1)
        }
      } finally {
        display.controlKeyHeld = false
        scene.source = original
        tryVerify(function() {
          return display.layoutMatchesCurrentInput() && !display.parseInFlight &&
            !display.parsePending && display.codeHighlightPendingCount === 0
        }, 15000)
      }
    }

    function test_ctrl_drag_does_not_activate_link() {
      var linkStart = scene.source.indexOf("[" + scene.linkLabel + "](") + 1
      var link = caretAt(linkStart + 2, "Ctrl-drag link start")
      var nonLink = caretFor("Open [", 1)
      reveal(link.rectangle)
      var linkPoint = renderedLinkPoint()
      var startPoint = display.mapToItem(scene, linkPoint.x, linkPoint.y)
      var endPoint = display.mapToItem(scene, center(nonLink.rectangle).x,
        center(nonLink.rectangle).y)
      verify(Math.abs(Number(startPoint.x) - Number(endPoint.x)) > 10,
        "the drag fixture has a measurable path out of the link")

      linkActivationSpy.clear()
      mousePress(scene, startPoint.x, startPoint.y, Qt.LeftButton,
        Qt.ControlModifier)
      mouseMove(scene, endPoint.x, endPoint.y, 20, Qt.LeftButton,
        Qt.ControlModifier)
      mouseRelease(scene, endPoint.x, endPoint.y, Qt.LeftButton,
        Qt.ControlModifier)
      wait(50)
      compare(linkActivationSpy.count, 0,
        "dragging away from a link does not activate its target")
    }

    function test_drag_selects_code_language() {
      var languageStart = scene.source.indexOf("```tes") + 3
      var languageEnd = languageStart + "tes".length
      var start = caretAt(languageStart, "scratchpad language start")
      var end = caretAt(languageEnd, "scratchpad language end")
      reveal(start.rectangle)
      var startPoint = display.mapToItem(scene,
        Number(start.rectangle.x) + 0.25,
        Number(start.rectangle.y) + Number(start.rectangle.height) / 2)
      var endPoint = display.mapToItem(scene,
        Number(end.rectangle.x) + 0.25,
        Number(end.rectangle.y) + Number(end.rectangle.height) / 2)

      selectionSpy.clear()
      mousePress(scene, startPoint.x, startPoint.y, Qt.LeftButton)
      mouseMove(scene, endPoint.x, endPoint.y, 20, Qt.LeftButton)
      mouseRelease(scene, endPoint.x, endPoint.y, Qt.LeftButton)

      tryVerify(function() { return selectionSpy.count > 0 }, 2000,
        "dragging the rendered code language emits a source selection")
      var selectedStart = Math.min(
        Number(scene.selectionAnchor), Number(scene.selectionTarget))
      var selectedEnd = Math.max(
        Number(scene.selectionAnchor), Number(scene.selectionTarget))
      verify(selectedStart >= languageStart &&
          selectedStart <= languageStart + 1 &&
          selectedEnd >= languageEnd - 1 && selectedEnd <= languageEnd,
        "dragging the rendered code language selects its source token: " +
          JSON.stringify({selectedStart: selectedStart,
            selectedEnd: selectedEnd, languageStart: languageStart,
            languageEnd: languageEnd}))
      tryVerify(function() {
        return display.selectionRects.some(function(rectangle) {
          return Math.abs(Number(rectangle.y) -
            Number(start.rectangle.y)) <= 1 && Number(rectangle.width) > 8
        })
      }, 2000, "the selected code language paints on its label row")
    }

    function test_drag_selects_code_language_after_styled_edit() {
      var originalSource = String(scene.source)
      var originalOptimisticCount = Number(display.optimisticEditCount)
      scene.source = originalSource.replace("```tes", "```te")
      compare(display.layoutReady, true,
        "the fence-language edit paints without waiting for parsing")
      compare(Number(display.optimisticEditCount), originalOptimisticCount + 1,
        "the fence-language edit uses its styled projection path")
      compare(String(display.documentSourceText), String(scene.source),
        "the projected document tracks the edited fence source immediately")
      verify(String(display.documentPlainText).indexOf("te") >= 0,
        "the edited language is visible before authoritative parsing")
      tryVerify(function() {
        return display.layoutReady && display.layoutMatchesCurrentInput() &&
          display.layoutSourceText === String(scene.source) &&
          !display.parseInFlight && Number(display.codeHighlightPendingCount) === 0
      }, 15000, "the edited language receives authoritative styling")

      var languageStart = scene.source.indexOf("```te") + 3
      var languageEnd = languageStart + "te".length
      var start = caretAt(languageStart, "edited language start")
      var end = caretAt(languageEnd, "edited language end")
      reveal(start.rectangle)
      var startPoint = display.mapToItem(scene,
        Number(start.rectangle.x) + 0.25,
        Number(start.rectangle.y) + Number(start.rectangle.height) / 2)
      var endPoint = display.mapToItem(scene,
        Number(end.rectangle.x) + 0.25,
        Number(end.rectangle.y) + Number(end.rectangle.height) / 2)
      selectionSpy.clear()
      mousePress(scene, startPoint.x, startPoint.y, Qt.LeftButton)
      mouseMove(scene, endPoint.x, endPoint.y, 20, Qt.LeftButton)
      mouseRelease(scene, endPoint.x, endPoint.y, Qt.LeftButton)
      tryVerify(function() { return selectionSpy.count > 0 }, 2000,
        "a just-edited code language remains mouse-selectable")
      var selectedStart = Math.min(
        Number(scene.selectionAnchor), Number(scene.selectionTarget))
      var selectedEnd = Math.max(
        Number(scene.selectionAnchor), Number(scene.selectionTarget))
      verify(selectedStart >= languageStart &&
          selectedStart <= languageStart + 1 &&
          selectedEnd >= languageEnd - 1 && selectedEnd <= languageEnd,
        "styled language selection covers the edited source token: " +
          JSON.stringify({selectedStart: selectedStart,
            selectedEnd: selectedEnd, languageStart: languageStart,
            languageEnd: languageEnd}))

      scene.source = originalSource
      tryVerify(function() {
        return display.layoutReady && display.layoutMatchesCurrentInput() &&
          display.layoutSourceText === originalSource
      }, 15000, "the mouse fixture restores after the styled language edit")
    }

    function test_clicks_empty_code_language_slot() {
      var plainCode = scene.source.indexOf("plain code without a language")
      var opening = scene.source.lastIndexOf("```", plainCode)
      var insertion = opening + 3
      var slot = caretAt(insertion, "empty code language slot")
      verify(String(display.documentPlainText || "").indexOf("Language") >= 0,
        "an unlabeled fence paints an editable language placeholder")
      reveal(slot.rectangle)
      var point = center(slot.rectangle)
      var windowPoint = display.mapToItem(scene, point.x, point.y)
      positionSpy.clear()
      mouseClick(scene, windowPoint.x, windowPoint.y, Qt.LeftButton)
      tryCompare(positionSpy, "count", 1, 2000)
      compare(Number(positionSpy.signalArguments[0][0]), insertion,
        "clicking the empty language slot enters the opening fence header")
      compare(scene.selectionTarget, insertion,
        "the application caret follows the empty language slot click")
    }

    function test_selection_drag_does_not_scroll() {
      var start = caretFor("To add an image", 3)
      var end = caretFor("Useful shortcuts", 8)
      reveal(start.rectangle)
      var startPoint = center(start.rectangle)
      var endPoint = center(end.rectangle)
      var initialContentY = Number(viewport.contentY)
      selectionSpy.clear()

      var startWindowPoint = display.mapToItem(
        scene, startPoint.x, startPoint.y)
      var endWindowPoint = display.mapToItem(
        scene, endPoint.x, endPoint.y)
      mousePress(scene,
        startWindowPoint.x, startWindowPoint.y, Qt.LeftButton)
      mouseMove(scene,
        endWindowPoint.x, endWindowPoint.y, 20, Qt.LeftButton)
      mouseRelease(scene,
        endWindowPoint.x, endWindowPoint.y, Qt.LeftButton)

      tryVerify(function() { return selectionSpy.count > 0 }, 2000,
        "drag below the fence emits a source selection")
      compare(Number(viewport.contentY), initialContentY,
        "left-button selection drag never scrolls the editor viewport")
      var last = selectionSpy.signalArguments[selectionSpy.count - 1]
      compare(Number(last[0]), start.position,
        "selection anchor stays at the pressed source position")
      verify(Number(last[1]) >= end.position - 2 &&
        Number(last[1]) <= end.position + 2,
        "selection target maps below the fenced code block")
      tryVerify(function() {
        return display.selectionRects.length > 0
      }, 2000, "the application paints the lower-file source selection")
    }

    function test_image_shows_four_corner_resize_frame() {
      tryVerify(function() {
        return Array.isArray(display.imageRects) &&
          display.imageRects.length === 1 && display.imageRects[0]
      }, 4000, "standalone image geometry settles")
      var rect = display.imageRects[0]
      reveal(rect)
      var centerPoint = display.mapToItem(scene,
        Number(rect.x) + Number(rect.width) / 2,
        Number(rect.y) + Number(rect.height) / 2)
      positionSpy.clear()
      mouseClick(scene, centerPoint.x, centerPoint.y, Qt.LeftButton)
      tryCompare(display, "selectedImageIndex", 0, 2000)
      tryCompare(positionSpy, "count", 1, 2000)

      var originalSource = String(scene.source)
      var originalWidth = Number(rect.width)
      var cornerPoint = display.mapToItem(scene,
        Number(rect.x) + originalWidth,
        Number(rect.y) + Number(rect.height))
      imageResizeSpy.clear()
      mousePress(scene, cornerPoint.x, cornerPoint.y, Qt.LeftButton)
      mouseMove(scene, cornerPoint.x + 32, cornerPoint.y + 16,
        20, Qt.LeftButton)
      mouseRelease(scene, cornerPoint.x + 32, cornerPoint.y + 16,
        Qt.LeftButton)
      tryCompare(imageResizeSpy, "count", 1, 2000)
      verify(Number(imageResizeSpy.signalArguments[0][2]) > originalWidth,
        "bottom-right corner drag requests a larger image width")
      compare(String(scene.source), originalSource,
        "live corner dragging does not directly mutate source")
      display.previewImageIndex = -1
      display.previewImageWidth = 0
      display.refreshStyledDocument()
    }
  }
}
