import QtQuick
import Quickshell

// A disposable offscreen contract test for the native Markdown display
// vertical slice. The shell runner copies the component and its parser worker
// into a private config directory, so this fixture never opens a window or
// touches the user's note/state files.
ShellRoot {
  id: shell

  property string source: "\n# Native preview test\n\n" +
    "## Second heading\n\n" +
    "### Third heading\n\n" +
    "A **strong** word, *emphasis*, `inline code`, and a [link text](https://example.com).\n" +
    "Hard break  \ncontinues.\n\n" +
    "> quoted line\n>\n> quoted second line\n\n" +
    "---\n\n" +
    "- bullet item\n" +
    "  - nested item\n\n" +
    "1. ordered first\n" +
    "2. ordered second\n\n" +
    "- [ ] unchecked task\n" +
    "- [x] checked task\n\n" +
    "```javascript\n" +
    "const answer = 42\n" +
    "console.log(answer)\n" +
    "```\n\n" +
    "| column-a  | column-b | column-c |\n" +
    "| :--- | :---: | ---: |\n" +
    "| cell-alpha | wrapped cell value | cell-gamma |\n\n" +
    "![offline image](markdown-image.svg)<!-- jotpin:image width=192 -->\n\n" +
    "![This is an alt text.](missing-image-does-not-exist.svg)\n"
  property int cursorPosition: source.indexOf("answer") + 3
  property int selectionStart: source.indexOf("strong")
  property int selectionEnd: selectionStart + "strong".length
  property var failures: []
  property int settleAttempts: 0
  property double startedAt: 0
  property bool repeatRunning: false
  property int repeatSent: 0
  property int repeatIntermediateLayouts: 0
  property int lastRepeatLayoutLength: -1
  property int repeatDispatchStart: 0
  property int repeatCompletionStart: 0
  property int repeatOptimisticStart: 0
  property int repeatCharacterOptimisticEdits: 0
  property string repeatExpectedSource: ""
  property string repeatSpacedSource: ""
  property int repeatSpacingCompletionStart: 0
  property int repeatSpacingLayoutRevision: 0
  property real repeatCaretAfterSpaceX: -1
  property string spacingSource: "tim"
  property int spacingCursorPosition: 3
  property string headingTypingSource: "# one\n## two\n### three\n" +
    "#### four\n##### five\n###### six\n"
  property int headingTypingCursorPosition: headingTypingSource.length
  property string paragraphFenceBoundarySource:
    "To add an image, use `![Alt text](/absolute/path/to/image.png)`. " +
    "tethisi\n\n```python\nprint('x')\n```\n"
  property int paragraphFenceBoundaryCursorPosition:
    paragraphFenceBoundarySource.indexOf("\n\n") + 1
  property int initialCursorPosition: source.indexOf("answer") + 3
  property var initialResult: null
  property int selectionRequestCount: 0
  property int lastSelectionRequestEnd: -1
  property int imageResizeRequestCount: 0
  property int lastImageResizeWidth: 0
  property bool fenceBackspaceRunning: false
  property int fenceBackspaceRemaining: 0
  property int fenceLanguageInsertSent: 0
  property int fenceLanguageIntermediateLayouts: 0
  property real fenceLanguageRowY: -1
  property int fenceBackspaceOptimisticStart: 0
  property string fenceBackspacePhase: ""
  property string codeFlashSource: ""
  property string codeFlashPhase: ""
  property int codeFlashSent: 0
  property int codeFlashFallbackStart: 0
  property int codeFlashCompletionBeforeEdit: -1

  NativeMarkdownDisplay {
    id: display
    width: 760
    foreground: Qt.rgba(1, 0.79, 0.64, 1)
    background: Qt.rgba(1, 0.79, 0.64, 0.035)
    surfaceBackground: Qt.rgba(0.02, 0.03, 0.08, 1)
    accent: "#b5a3ff"
    baseUrl: Qt.resolvedUrl("./")
    sourceText: shell.source
    cursorPosition: shell.cursorPosition
    selectionStart: shell.selectionStart
    selectionEnd: shell.selectionEnd
    onImageResizeRequested: function(sourceStart, sourceEnd, width) {
      shell.imageResizeRequestCount++
      shell.lastImageResizeWidth = Number(width)
    }
  }

  NativeMarkdownDisplay {
    id: headingTypingDisplay
    width: 360
    height: 240
    sourceText: shell.headingTypingSource
    cursorPosition: shell.headingTypingCursorPosition
    fontFamily: display.fontFamily
    bodyPixelSize: display.bodyPixelSize
  }

  NativeMarkdownDisplay {
    id: spacingDisplay
    width: 240
    height: 80
    sourceText: shell.spacingSource
    cursorPosition: shell.spacingCursorPosition
    fontFamily: display.fontFamily
    bodyPixelSize: display.bodyPixelSize
  }

  NativeMarkdownDisplay {
    id: paragraphFenceBoundaryDisplay
    width: 520
    height: 180
    sourceText: shell.paragraphFenceBoundarySource
    cursorPosition: shell.paragraphFenceBoundaryCursorPosition
    fontFamily: display.fontFamily
    bodyPixelSize: display.bodyPixelSize
  }

  function fail(message) {
    failures.push(String(message))
    console.error("NATIVE_DISPLAY_FAIL: " + message)
  }

  function check(condition, message) {
    if (!condition) fail(message)
  }

  function finite(value) {
    return isFinite(Number(value))
  }

  function validRect(rect) {
    return rect !== null && rect !== undefined &&
      finite(rect.x) && finite(rect.y) &&
      finite(rect.width) && finite(rect.height) &&
      Number(rect.width) > 0 && Number(rect.height) > 0
  }

  function rectCenter(rect) {
    return {
      x: Number(rect.x) + Number(rect.width) / 2,
      y: Number(rect.y) + Number(rect.height) / 2
    }
  }

  function sourceSamplePositions() {
    return [
      {name: "heading", position: source.indexOf("Native preview") + 4},
      {name: "second-heading", position: source.indexOf("Second heading") + 3},
      {name: "third-heading", position: source.indexOf("Third heading") + 3},
      {name: "strong", position: source.indexOf("strong") + 2},
      {name: "emphasis", position: source.indexOf("emphasis") + 2},
      {name: "inline-code", position: source.indexOf("inline code") + 4},
      {name: "link", position: source.indexOf("link text") + 4},
      {name: "hard-break-continuation", position: source.indexOf("continues") + 3},
      {name: "blockquote", position: source.indexOf("quoted line") + 3},
      {name: "nested-list", position: source.indexOf("nested item") + 3},
      {name: "ordered-list", position: source.indexOf("ordered first") + 3},
      {name: "unchecked-task", position: source.indexOf("unchecked task") + 5},
      {name: "checked-task", position: source.indexOf("checked task") + 4},
      {name: "fenced-code", position: source.indexOf("answer") + 3},
      {name: "table-cell", position: source.indexOf("cell-alpha") + 4},
      {name: "image", position: source.indexOf("offline image") + 4},
      {name: "failed-image", position: source.indexOf(
        "This is an alt text.") + 4}
    ]
  }

  function checkLayoutMetrics(metrics) {
    check(Array.isArray(metrics) && metrics.length > 0,
      "layoutMetricsForTests() returns nonempty metrics")
    if (!Array.isArray(metrics)) return

    for (var index = 0; index < metrics.length; index++) {
      var metric = metrics[index] || {}
      check(finite(metric.y) && finite(metric.height) &&
          Number(metric.height) > 0,
        "layout metric " + index + " has finite geometry: " +
          JSON.stringify(metric))
    }
  }

  function checkCaretAndPointMapping() {
    var samples = sourceSamplePositions()
    var observations = []
    var nearbyTolerance = 24
    for (var index = 0; index < samples.length; index++) {
      var sample = samples[index]
      var position = Math.max(0, Math.min(source.length,
        Number(sample.position)))
      var caret = display.cursorRectangleForSource(position)
      check(validRect(caret), sample.name +
        " source caret has a valid rectangle: " + JSON.stringify(caret))
      if (!validRect(caret)) continue

      var center = rectCenter(caret)
      var roundTrip = Number(display.sourcePositionForPoint(
        center.x, center.y))
      check(finite(roundTrip) && roundTrip >= 0 && roundTrip <= source.length,
        sample.name + " point hit-test returns a source position: " +
          roundTrip)
      if (finite(roundTrip)) {
        check(Math.abs(roundTrip - position) <= nearbyTolerance,
          sample.name + " point hit-test returns a nearby source position: " +
            JSON.stringify({requested: position, returned: roundTrip,
              tolerance: nearbyTolerance}))
      }
      observations.push({name: sample.name, sourcePosition: position,
        caret: caret, roundTrip: roundTrip})
    }
    return observations
  }

  function checkSelectionGeometry() {
    var rectangles = display.sourceRangeRectangles(
      selectionStart, selectionEnd)
    check(Array.isArray(rectangles) && rectangles.length > 0,
      "sourceRangeRectangles() returns nonempty selection geometry")
    if (!Array.isArray(rectangles)) return 0

    var invalid = 0
    for (var index = 0; index < rectangles.length; index++) {
      if (!validRect(rectangles[index])) invalid++
    }
    check(invalid === 0,
      "selection geometry contains only valid rectangles: " +
        JSON.stringify(rectangles))
    return rectangles.length
  }

  function checkVerticalNavigation(observations) {
    if (!observations.length) return -1
    var starting = observations[0]
    var preferredX = Number(starting.caret.x) +
      Number(starting.caret.width) / 2
    var target = Number(display.verticalNavigationTarget(
      starting.sourcePosition, preferredX, 1))
    check(finite(target) && target >= 0 && target <= source.length &&
        target !== starting.sourcePosition,
      "vertical navigation returns a different valid source position: " +
        JSON.stringify({from: starting.sourcePosition, to: target}))
    if (!finite(target) || target < 0 || target > source.length ||
        target === starting.sourcePosition) return target

    var targetCaret = display.cursorRectangleForSource(target)
    check(validRect(targetCaret),
      "vertical navigation target has a valid caret rectangle: " +
        JSON.stringify(targetCaret))
    check(Number(targetCaret.y) > Number(starting.caret.y),
      "downward vertical navigation moves to a later visual row: " +
        JSON.stringify({from: starting.caret, to: targetCaret}))
    return target
  }

  function checkTableGeometry() {
    var headerLeft = display.cursorRectangleForSource(
      source.indexOf("column-a") + 2)
    var headerRight = display.cursorRectangleForSource(
      source.indexOf("column-b") + 2)
    var bodyLeft = display.cursorRectangleForSource(
      source.indexOf("cell-alpha") + 2)
    var bodyRight = display.cursorRectangleForSource(
      source.indexOf("cell-gamma") + 2)
    check(validRect(headerLeft) && validRect(headerRight) &&
        validRect(bodyLeft) && validRect(bodyRight),
      "table headers and cells expose native text geometry")
    if (!validRect(headerLeft) || !validRect(headerRight) ||
        !validRect(bodyLeft) || !validRect(bodyRight)) return false
    check(Number(headerRight.x) > Number(headerLeft.x) + 20 &&
        Number(bodyRight.x) > Number(bodyLeft.x) + 20,
      "table columns render as distinct horizontal cells")
    check(Number(bodyLeft.y) > Number(headerLeft.y) &&
        Number(bodyRight.y) > Number(headerRight.y),
      "table body renders on a row below its header")
    var hiddenStart = source.indexOf("column-a") + "column-a".length
    var nextContent = source.indexOf("column-b")
    var previousHiddenX = -1
    for (var hiddenPosition = hiddenStart;
         hiddenPosition <= nextContent; hiddenPosition++) {
      var hiddenCaret = display.cursorRectangleForSource(hiddenPosition)
      check(validRect(hiddenCaret),
        "hidden table source position has caret geometry at " +
          hiddenPosition)
      if (!validRect(hiddenCaret)) continue
      check(previousHiddenX < 0 || Number(hiddenCaret.x) > previousHiddenX,
        "table caret advances through hidden padding and delimiter source at " +
          hiddenPosition + ": " + JSON.stringify(hiddenCaret))
      var hiddenRoundTrip = Number(display.sourcePositionForPoint(
        Number(hiddenCaret.x), Number(hiddenCaret.y) +
          Number(hiddenCaret.height) / 2))
      check(hiddenRoundTrip === hiddenPosition,
        "hidden table caret point maps back to its exact source position at " +
          hiddenPosition + ": " + hiddenRoundTrip)
      previousHiddenX = Number(hiddenCaret.x)
    }
    return true
  }

  function checkImageResizeContract() {
    check(Array.isArray(display.images) && display.images.length === 2,
      "native display exposes valid and failed parsed image models")
    check(Array.isArray(display.imageRects) && display.imageRects.length === 2 &&
        validRect(display.imageRects[0]),
      "standalone image exposes finite native object geometry")
    if (!Array.isArray(display.imageRects) ||
        !validRect(display.imageRects[0])) return
    var rect = display.imageRects[0]
    check(Math.abs(Number(rect.width) - 192) <= 1,
      "persisted image width controls the native rich-text object: " +
        JSON.stringify(rect))
    check(display.imageIndexAtPoint(Number(rect.x) + Number(rect.width) / 2,
        Number(rect.y) + Number(rect.height) / 2) === 0,
      "clicking inside the image identifies its selection frame")

    var originalSource = String(display.sourceText || "")
    var visibleDocumentBeforeMetadataEdit = String(display.documentPlainText)
    var optimisticCountBeforeMetadataEdit = display.optimisticEditCount
    var resizedSource = originalSource.replace("width=192", "width=240")
    check(!display.tryApplyOptimisticPlainEdit(resizedSource),
      "changing only image width digits bypasses optimistic visible text")
    check(display.optimisticEditCount === optimisticCountBeforeMetadataEdit &&
        String(display.documentPlainText) ===
          visibleDocumentBeforeMetadataEdit &&
        String(display.documentPlainText).indexOf("240") < 0,
      "image width digits never flash in the native document")

    var altEditedSource = originalSource.replace(
      "offline image", "offline Ximage")
    check(!display.tryApplyOptimisticPlainEdit(altEditedSource) &&
        String(display.documentPlainText) ===
          visibleDocumentBeforeMetadataEdit &&
        String(display.documentPlainText).indexOf("offline Ximage") < 0,
      "image alt text waits for styled rendering without a size flash")

    display.selectedImageIndex = 0
    var corners = [
      {name: "topLeft", x: rect.x, y: rect.y, dx: -32, dy: -16},
      {name: "topRight", x: rect.x + rect.width, y: rect.y,
        dx: 32, dy: -16},
      {name: "bottomLeft", x: rect.x, y: rect.y + rect.height,
        dx: -32, dy: 16},
      {name: "bottomRight", x: rect.x + rect.width,
        y: rect.y + rect.height, dx: 32, dy: 16}
    ]
    var cornerWidths = []
    for (var index = 0; index < corners.length; index++) {
      var corner = corners[index]
      check(display.beginImageResize(corner.name, corner.x, corner.y),
        corner.name + " corner begins an image resize")
      var width = display.imageResizeWidthForPoint(
        corner.x + corner.dx, corner.y + corner.dy)
      cornerWidths.push(width)
      check(width > Number(rect.width),
        corner.name + " outward drag increases image width")
      display.requestImageResize(
        corner.x + corner.dx, corner.y + corner.dy)
      display.flushImageResizePreview()
      check(String(display.sourceText || "") === originalSource,
        corner.name + " live resize does not mutate Markdown source")
      display.endImageResize(false)
      display.selectedImageIndex = 0
    }
    check(cornerWidths.every(function(width) {
      return Math.abs(Number(width) - Number(cornerWidths[0])) <= 1
    }), "all four corner handles use symmetric aspect-preserving resize math")

    var finalCorner = corners[3]
    imageResizeRequestCount = 0
    lastImageResizeWidth = 0
    display.beginImageResize(finalCorner.name, finalCorner.x, finalCorner.y)
    display.requestImageResize(finalCorner.x + 24, finalCorner.y + 12)
    display.endImageResize(true)
    check(imageResizeRequestCount === 1 && lastImageResizeWidth > rect.width,
      "releasing a corner emits one source resize request")
    display.previewImageIndex = -1
    display.previewImageWidth = 0
    display.refreshStyledDocument()
  }

  function checkFailedImageContract() {
    check(Array.isArray(display.imageLoadStates) &&
        display.imageLoadStates.length === 2 &&
        String(display.imageLoadStates[0]) === "ready" &&
        String(display.imageLoadStates[1]) === "error",
      "native image probes distinguish a valid image from a failed load")
    check(!display.imageRects[1],
      "a failed image exposes no selection or resize geometry")
    check(display.documentPlainText.indexOf(
        "Image cannot be displayed.") >= 0 &&
        display.documentPlainText.indexOf("This is an alt text.") >= 0,
      "a failed standalone image renders an explicit message and its alt text")
    var objectCount = (display.documentPlainText.match(/\ufffc/g) || []).length
    check(objectCount === 1,
      "only the successfully loaded image remains a native image object")
    var altCaret = display.cursorRectangleForSource(
      source.indexOf("This is an alt text.") + 4)
    check(validRect(altCaret),
      "failed-image alt text retains editable source caret geometry")
  }

  function checkBlankRowGeometry() {
    var leading = display.cursorRectangleForSource(0)
    var firstHeading = display.cursorRectangleForSource(
      source.indexOf("Native preview"))
    var firstHeadingEnd = display.cursorRectangleForSource(
      source.indexOf("test") + "test".length)
    var between = display.cursorRectangleForSource(
      source.indexOf("\n\n", source.indexOf("Native preview")) + 1)
    var secondHeading = display.cursorRectangleForSource(
      source.indexOf("Second heading"))
    var image = display.cursorRectangleForSource(
      source.indexOf("offline image") + 3)
    var trailing = display.cursorRectangleForSource(source.length)
    check(validRect(leading) && validRect(firstHeading) &&
        Number(leading.y) < Number(firstHeading.y),
      "leading blank source row has its own row before the first heading")
    check(validRect(firstHeadingEnd) && validRect(between) &&
        validRect(secondHeading) &&
        Number(between.y) > Number(firstHeadingEnd.y) &&
        Number(between.y) < Number(secondHeading.y),
      "blank source row between headings has distinct vertical geometry")
    check(validRect(image) && validRect(trailing) &&
        Number(trailing.y) > Number(image.y),
      "trailing newline exposes an editable row after the final image")
  }

  function checkListGeometry() {
    var bullet = display.cursorRectangleForSource(
      source.indexOf("bullet item"))
    var nested = display.cursorRectangleForSource(
      source.indexOf("nested item"))
    var task = display.cursorRectangleForSource(
      source.indexOf("unchecked task"))
    check(validRect(bullet) && validRect(nested) &&
        Number(nested.x) > Number(bullet.x),
      "nested list text is indented beyond its parent")
    check(validRect(bullet) && validRect(task),
      "ordinary and task list text retain editable geometry")
    var boxes = display.taskCheckboxRects
    check(Array.isArray(boxes) && boxes.length === 2,
      "task list exposes one rendered checkbox control per source task")
    if (!Array.isArray(boxes) || boxes.length !== 2) return
    check(!Boolean(boxes[0].checked) && Boolean(boxes[1].checked),
      "rendered checkbox controls preserve unchecked and checked state")
    check(Number(boxes[0].width) >= 11 &&
        Number(boxes[0].x) < Number(task.x),
      "rendered checkbox is a visible control before the task text")
    check(Number(boxes[0].hitWidth) > Number(boxes[0].width) &&
        Number(boxes[0].hitHeight) > Number(boxes[0].height),
      "checkbox control has a forgiving pointer target")
    var firstStart = source.indexOf("- [ ] unchecked task")
    check(Number(display.taskCheckboxSourceAtPoint(
        Number(boxes[0].hitX) + Number(boxes[0].hitWidth) / 2,
        Number(boxes[0].hitY) + Number(boxes[0].hitHeight) / 2)) === firstStart,
      "checkbox hit target resolves to the exact task source line")
    var statePosition = source.indexOf("[ ] unchecked task") + 1
    var toggledSource = source.slice(0, statePosition) + "x" +
      source.slice(statePosition + 1)
    var optimisticBeforeToggle = display.optimisticEditCount
    var documentBeforeToggle = String(display.documentPlainText)
    check(!display.tryApplyOptimisticPlainEdit(toggledSource) &&
        display.immediateParseRequested &&
        display.optimisticEditCount === optimisticBeforeToggle &&
        String(display.documentPlainText) === documentBeforeToggle,
      "task toggles never flash a raw state character in the rendered list")
    display.immediateParseRequested = false
  }

  function checkVisualContract() {
    var styledHtml = display.styledDocumentHtml(display.renderedHtml)
    check(styledHtml.indexOf("h1{font-size:25px") >= 0 &&
        styledHtml.indexOf("h2{font-size:21px") >= 0 &&
        styledHtml.indexOf("h3{font-size:18px") >= 0,
      "heading scale matches the established 1.55/1.3/1.15 treatment")
    check(styledHtml.indexOf("a{color:#ffc9a3;text-decoration:underline") >= 0,
      "links retain readable underlined foreground styling")
    check(styledHtml.indexOf(
          ".jotpin-list{margin:0;padding:0;}") >= 0 &&
        styledHtml.indexOf(
          ".jotpin-list-item,.jotpin-task-list-item{margin:0;padding:0;}") >= 0 &&
        display.renderedHtml.indexOf(
          'class="jotpin-task-list-item"') >= 0,
      "task list styling suppresses the ordinary list bullet")
    check(styledHtml.indexOf("border-left:2px solid") >= 0,
      "blockquotes retain the established vertical rail")
    check(styledHtml.indexOf(
        'style="color:#b5a3ff;background-color:') >= 0,
      "inline code retains accent text and background styling")
    check(display.documentPlainText.indexOf("JavaScript") >= 0,
      "fenced code retains its visible language label")
    check(display.renderedHtml.indexOf(
          '<table border="1" cellspacing="0" cellpadding="7">') >= 0 &&
        display.renderedHtml.indexOf('<th align="left"') >= 0,
      "tables keep compact sizing and explicit left header alignment")
  }

  function checkInteractionContract() {
    var quotePosition = source.indexOf("quoted second line") + 4
    var line = display.sourceLineSelectionRange(quotePosition)
    check(source.slice(line.start, line.end) === "> quoted second line",
      "line selection returns the complete canonical source row")
    display.mouseClickCount = 0
    display.mouseClickKey = ""
    display.mouseClickTimestamp = 0
    var first = display.registerRenderedMousePress(quotePosition)
    var second = display.registerRenderedMousePress(quotePosition)
    var third = display.registerRenderedMousePress(quotePosition)
    check(first === 1 && second === 2 && third === 3,
      "rendered click tracking preserves single, double, and triple click")
    display.homePath = "/home/tester"
    check(display.linkSourceUrl("~/note.md") ===
        "file:///home/tester/note.md" ||
        display.linkSourceUrl("~/note.md") === "/home/tester/note.md",
      "home-relative links resolve through the configured home path")
    check(display.linkSourceUrl("relative.md").indexOf("relative.md") >= 0,
      "relative links resolve through the active note base URL")

    selectionRequestCount = 0
    lastSelectionRequestEnd = -1
    var dragAnchor = source.indexOf("strong")
    var firstDragCaret = display.cursorRectangleForSource(
      source.indexOf("emphasis"))
    var finalDragPosition = source.indexOf("inline code") + 4
    var finalDragCaret = display.cursorRectangleForSource(finalDragPosition)
    display.mouseSelectionAnchor = dragAnchor
    display.beginMouseSelection()
    display.requestMouseSelection(Number(firstDragCaret.x),
      Number(firstDragCaret.y) + Number(firstDragCaret.height) / 2)
    display.requestMouseSelection(Number(finalDragCaret.x),
      Number(finalDragCaret.y) + Number(finalDragCaret.height) / 2)
    display.requestMouseSelection(Number(finalDragCaret.x) + 1,
      Number(finalDragCaret.y) + Number(finalDragCaret.height) / 2)
    check(selectionRequestCount === 0 && display.mouseSelectionUpdatePending,
      "rapid drag positions are coalesced before the display-frame flush")
    check(display.flushMouseSelection() && selectionRequestCount === 1,
      "one display-frame flush publishes only the newest drag position")
    check(Math.abs(lastSelectionRequestEnd - finalDragPosition) <= 2,
      "coalesced drag selection resolves the newest pointer coordinate: " +
        JSON.stringify({mapped: lastSelectionRequestEnd,
          expected: finalDragPosition}))
    display.endMouseSelection()
    display.mouseSelectionAnchor = -1

    var languageStart = source.indexOf("javascript")
    var languageEnd = languageStart + "javascript".length
    var languageCaretBeforeBackspace = display.cursorRectangleForSource(
      languageEnd)
    check(validRect(languageCaretBeforeBackspace),
      "fenced language exposes editable caret geometry before rapid edits")
    var previousLanguageX = -1
    for (var languageOffset = 0;
         languageOffset <= "javascript".length; languageOffset++) {
      var languagePosition = languageStart + languageOffset
      var languageCaret = display.cursorRectangleForSource(languagePosition)
      check(validRect(languageCaret),
        "code language source column " + languageOffset +
          " has editable caret geometry: " + JSON.stringify(languageCaret))
      if (!validRect(languageCaret)) continue
      check(previousLanguageX < 0 || Number(languageCaret.x) > previousLanguageX,
        "code language caret advances at source column " + languageOffset +
          ": " + JSON.stringify({previousX: previousLanguageX,
            caret: languageCaret}))
      previousLanguageX = Number(languageCaret.x)
      if (languageOffset < "javascript".length) {
        var languageHit = display.sourcePositionForPoint(
          Number(languageCaret.x) + Number(languageCaret.width) / 2,
          Number(languageCaret.y) + Number(languageCaret.height) / 2)
        check(languageHit >= languageStart && languageHit <= languageEnd,
          "clicking rendered code language column " + languageOffset +
            " maps into its editable source token: " +
            JSON.stringify({mapped: languageHit, expectedStart: languageStart,
              expectedEnd: languageEnd}))
      }
    }
  }

  function checkInitialLayout() {
    var metrics = display.layoutMetricsForTests()
    check(display.sourceText === source,
      "canonical sourceText remains unchanged after rendering")
    check(display.layoutSourceText === source,
      "layoutSourceText matches the canonical source")
    check(Number(display.layoutCursorPosition) === cursorPosition,
      "layoutCursorPosition matches the requested source cursor")
    check(Boolean(display.layoutReady), "layoutReady is true after settling")
    check(Number(display.implicitHeight) > 0,
      "display implicitHeight is positive")
    check(display.renderedHtml.indexOf("<h1>") >= 0 &&
        display.renderedHtml.indexOf("<strong>") >= 0 &&
        display.renderedHtml.indexOf('class="jotpin-quote"') >= 0 &&
        display.renderedHtml.indexOf("<hr>") >= 0 &&
        display.renderedHtml.indexOf("<table ") >= 0 &&
        display.renderedHtml.indexOf('class="jotpin-code-block"') >= 0 &&
        display.renderedHtml.indexOf("<img ") >= 0,
      "parser supplies structural GFM HTML")
    check(display.documentPlainText.indexOf("JOTPIN_CODE_BLOCK_") < 0 &&
        display.documentPlainText.indexOf("const answer = 42") >= 0,
      "fenced code is rendered as code text instead of a placeholder")
    check(Array.isArray(display.codeHighlightResults) &&
        display.codeHighlightResults.length === 1 &&
        String(display.codeHighlightResults[0] || "").indexOf(
          "<font color=") >= 0,
      "fenced JavaScript is rendered through the Highlight.js worker")
    var styledHtml = display.styledDocumentHtml(display.renderedHtml)
    check(styledHtml.indexOf("body{color:#ffc9a3;background:") < 0,
      "the RichText body remains transparent over the editor surface")
    check(styledHtml.indexOf("background-color:#ffc9a3") < 0,
      "translucent editor tints never become opaque code/table backgrounds")
    checkLayoutMetrics(metrics)
    var observations = checkCaretAndPointMapping()
    var selectionCount = checkSelectionGeometry()
    var verticalTarget = checkVerticalNavigation(observations)
    var tableGeometryValid = checkTableGeometry()
    checkImageResizeContract()
    checkFailedImageContract()
    checkBlankRowGeometry()
    checkListGeometry()
    checkVisualContract()
    checkInteractionContract()

    initialResult = {
      schemaVersion: 1,
      sourceLength: source.length,
      sourceUnchanged: display.sourceText === source &&
        display.layoutSourceText === source,
      layoutReady: Boolean(display.layoutReady),
      layoutCursorPosition: Number(display.layoutCursorPosition),
      implicitHeight: Number(display.implicitHeight),
      metricCount: Array.isArray(metrics) ? metrics.length : 0,
      caretCount: observations.length,
      selectionRectangleCount: selectionCount,
      verticalNavigationTarget: verticalTarget,
      tableGeometryValid: tableGeometryValid,
      elapsedMs: Math.max(0, Date.now() - startedAt),
      failures: failures
    }
    var initialLanguageEnd = source.indexOf("javascript") +
      "javascript".length
    var initialLanguageCaret = display.cursorRectangleForSource(
      initialLanguageEnd)
    fenceLanguageRowY = initialLanguageCaret
      ? Number(initialLanguageCaret.y) : -1
    fenceBackspaceOptimisticStart = display.optimisticEditCount
    fenceBackspaceRemaining = "javascript".length - 1
    fenceBackspacePhase = "delete"
    fenceBackspaceRunning = true
    fenceLanguageBurstTimer.start()
  }

  function beginFenceBackspaceStep() {
    var languageStart = source.indexOf("javascript")
    var languageEnd = languageStart + "javascript".length
    var shortened = "javascript".slice(0, fenceBackspaceRemaining)
    var nextSource = source.slice(0, languageStart) + shortened +
      source.slice(languageEnd)
    cursorPosition = languageStart + shortened.length
    var optimisticBeforeEdit = display.optimisticEditCount
    display.sourceText = nextSource
    var caret = display.cursorRectangleForSource(cursorPosition)
    check(display.layoutReady &&
        display.layoutSourceText === nextSource &&
        display.documentSourceText === nextSource &&
        display.optimisticEditCount === optimisticBeforeEdit + 1 &&
        validRect(caret) && fenceLanguageRowY >= 0 &&
        Math.abs(Number(caret.y) - fenceLanguageRowY) <= 1,
      "fence-language Backspace paints its current revision on the label row: " +
        JSON.stringify({remaining: fenceBackspaceRemaining,
          layoutReady: display.layoutReady,
          layoutMatches: display.layoutSourceText === nextSource,
          documentMatches: display.documentSourceText === nextSource,
          caret: caret, expectedY: fenceLanguageRowY}))
    fenceLanguageIntermediateLayouts++
  }

  function finishFenceBackspaceRegression() {
    check(display.optimisticEditCount - fenceBackspaceOptimisticStart >=
        "javascript".length + fenceLanguageInsertSent,
      "rapid fence-language typing and Backspace use the immediate styled path")
    check(fenceLanguageIntermediateLayouts >=
        "javascript".length + fenceLanguageInsertSent,
      "every rapid fence-language edit publishes an intermediate layout")
    initialResult.fenceLanguageRapidBackspaces = "javascript".length
    initialResult.fenceLanguageRapidCharacters = fenceLanguageInsertSent
    initialResult.fenceLanguageIntermediateLayouts =
      fenceLanguageIntermediateLayouts
    fenceBackspacePhase = "restore"
    cursorPosition = initialCursorPosition
    display.sourceText = source
    fenceBackspaceSettleTimer.attempts = 0
    fenceBackspaceSettleTimer.start()
  }

  function startRepeatRegression() {
    repeatDispatchStart = display.parseDispatchCount
    repeatCompletionStart = display.parseCompletionCount
    repeatOptimisticStart = display.optimisticEditCount
    repeatRunning = true
    repeatTimer.start()
  }

  function startCodeHighlightStabilityRegression() {
    codeFlashSource = source
    codeFlashPhase = "typing"
    codeFlashSent = 0
    codeFlashFallbackStart = display.codeFallbackPaintCount
    codeFlashCompletionBeforeEdit = -1
    codeFlashTimer.start()
  }

  function finishRepeat() {
    var expected = source + new Array(repeatSent + 1).join("f")
    check(display.layoutSourceText === expected,
      "repeat burst settles the newest complete source revision")
    check(display.documentPlainText.indexOf(
        new Array(repeatSent + 1).join("f")) >= 0,
      "repeat burst is visible in the native document after reconciliation: " +
        JSON.stringify(display.documentPlainText.slice(-repeatSent - 12)))
    check(repeatIntermediateLayouts >= 2,
      "repeat burst paints intermediate source revisions while held: " +
        repeatIntermediateLayouts)
    var characterOptimisticEdits =
      display.optimisticEditCount - repeatOptimisticStart
    check(characterOptimisticEdits >= repeatSent - 2,
      "repeat burst echoes nearly every character without waiting for parse: " +
        characterOptimisticEdits)
    check(display.parseDispatchCount - repeatDispatchStart <= repeatSent,
      "repeat burst never dispatches more parser jobs than source revisions")

    repeatCharacterOptimisticEdits = characterOptimisticEdits
    repeatExpectedSource = expected
    check(paragraphFenceBoundaryDisplay.layoutReady &&
        paragraphFenceBoundaryDisplay.layoutSourceText ===
          paragraphFenceBoundarySource,
      "paragraph-to-fence boundary fixture starts from an authoritative layout")
    var boundaryParagraphEnd = paragraphFenceBoundarySource.indexOf("\n\n")
    var boundaryBlankStart = boundaryParagraphEnd + 1
    var boundaryFenceStart = boundaryBlankStart + 1
    var boundaryParagraphCaret = paragraphFenceBoundaryDisplay.
      cursorRectangleForSource(boundaryParagraphEnd)
    var boundaryBlankCaret = paragraphFenceBoundaryDisplay.
      cursorRectangleForSource(boundaryBlankStart)
    var boundaryFenceCaret = paragraphFenceBoundaryDisplay.
      cursorRectangleForSource(boundaryFenceStart + 3)
    check(validRect(boundaryParagraphCaret) && validRect(boundaryBlankCaret) &&
        validRect(boundaryFenceCaret) &&
        Number(boundaryBlankCaret.y) > Number(boundaryParagraphCaret.y) &&
        Number(boundaryBlankCaret.y) < Number(boundaryFenceCaret.y),
      "blank row between a paragraph and fence has distinct caret geometry: " +
        JSON.stringify({paragraph: boundaryParagraphCaret,
          blank: boundaryBlankCaret, fence: boundaryFenceCaret}))
    var boundaryBlankPoint = rectCenter(boundaryBlankCaret)
    var boundaryClicked = paragraphFenceBoundaryDisplay.sourcePositionForPoint(
      boundaryBlankPoint.x, boundaryBlankPoint.y)
    check(boundaryClicked === boundaryBlankStart,
      "clicking the paragraph-to-fence blank row selects that row: " +
        JSON.stringify({expected: boundaryBlankStart,
          returned: boundaryClicked, caret: boundaryBlankCaret}))
    var boundaryWideClick = paragraphFenceBoundaryDisplay.sourcePositionForPoint(
      paragraphFenceBoundaryDisplay.width * 0.7, boundaryBlankPoint.y)
    check(boundaryWideClick === boundaryBlankStart,
      "the complete paragraph-to-fence blank row remains clickable: " +
        JSON.stringify({expected: boundaryBlankStart,
          returned: boundaryWideClick}))
    var boundaryDown = paragraphFenceBoundaryDisplay.verticalNavigationTarget(
      boundaryParagraphEnd, boundaryBlankPoint.x, 1)
    check(boundaryDown === boundaryBlankStart,
      "Down enters the paragraph-to-fence blank row: " +
        JSON.stringify({expected: boundaryBlankStart, returned: boundaryDown}))
    var boundaryUp = paragraphFenceBoundaryDisplay.verticalNavigationTarget(
      boundaryFenceStart + 3, boundaryBlankPoint.x, -1)
    check(boundaryUp === boundaryBlankStart,
      "Up enters the paragraph-to-fence blank row: " +
        JSON.stringify({expected: boundaryBlankStart, returned: boundaryUp}))
    check(headingTypingDisplay.layoutReady &&
        headingTypingDisplay.layoutSourceText === headingTypingSource,
      "heading typing fixture starts from an authoritative layout")
    var headingWords = ["", "one", "two", "three", "four", "five", "six"]
    for (var headingLevel = 6; headingLevel >= 1; headingLevel--) {
      var headingPrefix = new Array(headingLevel + 1).join("#") + " "
      var headingStart = headingTypingSource.indexOf(headingPrefix)
      var headingEnd = headingTypingSource.indexOf("\n", headingStart)
      if (headingEnd < 0) headingEnd = headingTypingSource.length
      var existingDocumentPosition = String(
        headingTypingDisplay.documentPlainText).indexOf(
          headingWords[headingLevel])
      var existingFormat = headingTypingDisplay.
        characterFormatForDocumentForTests(existingDocumentPosition)
      headingTypingCursorPosition = headingEnd + 1
      headingTypingSource = headingTypingSource.slice(0, headingEnd) + "x" +
        headingTypingSource.slice(headingEnd)
      var insertedFormat = headingTypingDisplay.
        characterFormatForSourceForTests(headingEnd)
      check(existingFormat.valid && insertedFormat.valid &&
          insertedFormat.pixelSize === existingFormat.pixelSize &&
          insertedFormat.bold === existingFormat.bold,
        "level " + headingLevel +
          " optimistic title character immediately inherits heading format: " +
          JSON.stringify({existing: existingFormat, inserted: insertedFormat,
            documentPosition: existingDocumentPosition,
            documentText: headingTypingDisplay.documentPlainText}))
    }
    check(spacingDisplay.layoutReady &&
        spacingDisplay.layoutSourceText === "tim",
      "the focused word-spacing fixture starts from a settled word")
    var caretBeforeSpace = spacingDisplay.cursorRectangleForSource(3)
    var spacedSource = "tim "
    repeatSpacedSource = spacedSource
    repeatSpacingCompletionStart = spacingDisplay.parseCompletionCount
    spacingCursorPosition = spacedSource.length
    spacingSource = spacedSource
    repeatSpacingLayoutRevision = spacingDisplay.layoutRevision
    var caretAfterSpace = spacingDisplay.cursorRectangleForSource(
      spacedSource.length)
    check(spacingDisplay.layoutReady &&
        spacingDisplay.layoutSourceText === spacedSource &&
        spacingDisplay.sourceText === spacedSource &&
        String(spacingDisplay.documentPlainText).slice(-1) === "\u00a0",
      "a newly typed trailing source space stays visibly present immediately")
    check(validRect(caretBeforeSpace) && validRect(caretAfterSpace) &&
        Number(caretAfterSpace.x) > Number(caretBeforeSpace.x),
      "a newly typed trailing space advances the immediate caret geometry")
    repeatCaretAfterSpaceX = Number(caretAfterSpace.x)
    settledTrailingSpaceTimer.attempts = 0
    settledTrailingSpaceTimer.start()
  }

  function finishSettledTrailingSpaceRegression() {
    var spacedSource = repeatSpacedSource
    var trailingPosition = spacedSource.length
    check(Number(spacingDisplay.sourceToDocument[trailingPosition]) ===
        Number(spacingDisplay.sourceToDocument[trailingPosition - 1]),
      "the fixture reaches the authoritative collapsed trailing-space mapping")

    var wordAfterSpaceSource = spacedSource + "e"
    spacingCursorPosition = wordAfterSpaceSource.length
    spacingSource = wordAfterSpaceSource
    var caretAfterNextCharacter =
      spacingDisplay.cursorRectangleForSource(wordAfterSpaceSource.length)
    check(spacingDisplay.layoutReady &&
        spacingDisplay.layoutSourceText === wordAfterSpaceSource &&
        spacingDisplay.sourceText === wordAfterSpaceSource &&
        String(spacingDisplay.documentPlainText).slice(-2) === "\u00a0e",
      "the first character after a settled trailing space is inserted with its missing display gap: " +
        JSON.stringify({tail: String(spacingDisplay.documentPlainText).slice(-8),
          optimisticEdits: spacingDisplay.optimisticEditCount,
          sourceMap: spacingDisplay.sourceToDocument}))
    check(validRect(caretAfterNextCharacter) &&
        Number(caretAfterNextCharacter.x) > repeatCaretAfterSpaceX,
      "the first character after a trailing space advances from its visible position")

    finishRepeatLineRegression(repeatExpectedSource)
  }

  function finishRepeatLineRegression(expected) {
    var lineOptimisticStart = display.optimisticEditCount
    var lineSource = expected
    var lineIntermediateLayouts = 0
    var lineDebug = []
    for (var enterIndex = 0; enterIndex < 12; enterIndex++) {
      lineSource += "\n"
      cursorPosition = lineSource.length
      display.sourceText = lineSource
      if (display.layoutReady && display.layoutSourceText === lineSource)
        lineIntermediateLayouts++
      if (enterIndex < 3) lineDebug.push({phase: "ordinary-enter",
        index: enterIndex, ready: display.layoutReady,
        layoutMatches: display.layoutSourceText === lineSource,
        optimistic: display.optimisticEditCount - lineOptimisticStart,
        sourceMapLength: display.sourceToDocument.length,
        documentMapLength: display.documentToSource.length,
        documentTail: String(display.documentPlainText).slice(-16)})
    }
    for (var ordinaryBackspaceIndex = 0; ordinaryBackspaceIndex < 12;
         ordinaryBackspaceIndex++) {
      lineSource = lineSource.slice(0, -1)
      cursorPosition = lineSource.length
      display.sourceText = lineSource
      if (display.layoutReady && display.layoutSourceText === lineSource)
        lineIntermediateLayouts++
    }

    var fenceStart = lineSource.indexOf("```javascript")
    var codeCloseStart = lineSource.indexOf("\n```\n", fenceStart) + 1
    check(fenceStart >= 0 && codeCloseStart > fenceStart,
      "repeat fixture retains its fenced code block")
    for (var codeEnterIndex = 0; codeEnterIndex < 8; codeEnterIndex++) {
      lineSource = lineSource.slice(0, codeCloseStart) + "\n" +
        lineSource.slice(codeCloseStart)
      codeCloseStart++
      cursorPosition = codeCloseStart
      display.sourceText = lineSource
      if (display.layoutReady && display.layoutSourceText === lineSource)
        lineIntermediateLayouts++
    }
    for (var codeBackspaceIndex = 0; codeBackspaceIndex < 8;
         codeBackspaceIndex++) {
      lineSource = lineSource.slice(0, codeCloseStart - 1) +
        lineSource.slice(codeCloseStart)
      codeCloseStart--
      cursorPosition = codeCloseStart
      display.sourceText = lineSource
      if (display.layoutReady && display.layoutSourceText === lineSource)
        lineIntermediateLayouts++
    }
    check(lineSource === expected && lineIntermediateLayouts === 40,
      "held Enter/Backspace line edits paint every ordinary and code row: " +
        JSON.stringify({sourceMatches: lineSource === expected,
          layouts: lineIntermediateLayouts, debug: lineDebug}))
    check(display.optimisticEditCount - lineOptimisticStart === 40,
      "pure line-break repeats use the immediate projected edit path: " +
        (display.optimisticEditCount - lineOptimisticStart))

    initialResult.repeatCharacters = repeatSent
    initialResult.repeatIntermediateLayouts = repeatIntermediateLayouts
    initialResult.repeatParseDispatches =
      display.parseDispatchCount - repeatDispatchStart
    initialResult.repeatParseCompletions =
      display.parseCompletionCount - repeatCompletionStart
    initialResult.repeatOptimisticEdits = repeatCharacterOptimisticEdits
    initialResult.optimisticTrailingSpace = true
    initialResult.repeatLineEdits = 40
    initialResult.repeatLineIntermediateLayouts = lineIntermediateLayouts
    initialResult.failures = failures
    console.log("NATIVE_DISPLAY_RESULT: " + JSON.stringify(initialResult))
    Qt.exit(failures.length === 0 ? 0 : 1)
  }

  Connections {
    target: display
    function onSourceSelectionRequested(start, end) {
      shell.selectionRequestCount++
      shell.lastSelectionRequestEnd = Number(end)
    }
    function onLayoutUpdated() {
      if (!shell.repeatRunning) return
      var length = String(display.layoutSourceText || "").length
      var minimum = shell.source.length + 1
      if (repeatTimer.running && length >= minimum &&
          length !== shell.lastRepeatLayoutLength) {
        shell.repeatIntermediateLayouts++
        shell.lastRepeatLayoutLength = length
      }
    }
  }

  Timer {
    id: settleTimer
    interval: 1
    repeat: true
    onTriggered: {
      shell.settleAttempts++
      if (display.layoutReady &&
          display.layoutSourceText === shell.source &&
          Number(display.layoutCursorPosition) === shell.cursorPosition &&
          Number(display.codeHighlightPendingCount) === 0 &&
          display.imageLoadStates.length === 2 &&
          display.imageLoadStates.every(function(state) {
            return state === "ready" || state === "error"
          })) {
        settleTimer.stop()
        shell.checkInitialLayout()
      // Worker startup on a cold CI host is not a performance measurement.
      // Bound readiness by elapsed time rather than 250 one-ms timer ticks.
      } else if (Date.now() - shell.startedAt >= 5000) {
        settleTimer.stop()
        shell.fail("layout did not settle: " + JSON.stringify({
          layoutReady: display.layoutReady,
          layoutSourceTextLength: String(display.layoutSourceText).length,
          sourceLength: shell.source.length,
          layoutCursorPosition: display.layoutCursorPosition,
          cursorPosition: shell.cursorPosition
        }))
        Qt.exit(1)
      }
    }
  }

  Timer {
    id: fenceLanguageBurstTimer
    interval: 8
    repeat: true
    onTriggered: {
      if (shell.fenceBackspacePhase === "delete") {
        shell.beginFenceBackspaceStep()
        shell.fenceBackspaceRemaining--
        if (shell.fenceBackspaceRemaining < 0) {
          shell.fenceBackspacePhase = "insert"
          shell.fenceLanguageInsertSent = 0
        }
        return
      }
      if (shell.fenceBackspacePhase === "insert" &&
          shell.fenceLanguageInsertSent < 40) {
        shell.fenceLanguageInsertSent++
        var languageStart = shell.source.indexOf("javascript")
        var languageEnd = languageStart + "javascript".length
        var language = new Array(shell.fenceLanguageInsertSent + 1).join("z")
        var nextSource = shell.source.slice(0, languageStart) + language +
          shell.source.slice(languageEnd)
        shell.cursorPosition = languageStart + language.length
        var optimisticBeforeEdit = display.optimisticEditCount
        display.sourceText = nextSource
        var caret = display.cursorRectangleForSource(shell.cursorPosition)
        var format = display.characterFormatForSourceForTests(languageStart)
        shell.check(display.layoutReady &&
            display.layoutSourceText === nextSource &&
            display.documentSourceText === nextSource &&
            display.optimisticEditCount === optimisticBeforeEdit + 1 &&
            shell.validRect(caret) && shell.fenceLanguageRowY >= 0 &&
            Math.abs(Number(caret.y) - shell.fenceLanguageRowY) <= 1 &&
            format.valid && format.bold,
          "fence-language repeat paints styled text and caret before parsing: " +
            JSON.stringify({sent: shell.fenceLanguageInsertSent,
              layoutReady: display.layoutReady,
              layoutMatches: display.layoutSourceText === nextSource,
              documentMatches: display.documentSourceText === nextSource,
              caret: caret, expectedY: shell.fenceLanguageRowY,
              format: format}))
        shell.fenceLanguageIntermediateLayouts++
        return
      }
      stop()
      shell.fenceBackspacePhase = "settle-burst"
      fenceBackspaceSettleTimer.attempts = 0
      fenceBackspaceSettleTimer.start()
    }
  }

  Timer {
    id: fenceBackspaceSettleTimer
    property int attempts: 0
    interval: 2
    repeat: true
    onTriggered: {
      attempts++
      if (display.layoutReady &&
          display.layoutSourceText === String(display.sourceText || "") &&
          Number(display.layoutCursorPosition) === shell.cursorPosition &&
          Number(display.codeHighlightPendingCount) === 0) {
        stop()
        if (shell.fenceBackspacePhase === "restore") {
          shell.fenceBackspaceRunning = false
          shell.startCodeHighlightStabilityRegression()
          return
        }
        var caret = display.cursorRectangleForSource(shell.cursorPosition)
        check(validRect(caret) && shell.fenceLanguageRowY >= 0 &&
            Math.abs(Number(caret.y) - shell.fenceLanguageRowY) <= 1,
          "authoritative fence-language reconciliation keeps the caret row: " +
            JSON.stringify({caret: caret,
              expectedY: shell.fenceLanguageRowY}))
        shell.finishFenceBackspaceRegression()
      } else if (attempts >= 1000) {
        stop()
        shell.fail("fence-language Backspace regression did not settle")
        shell.fenceBackspaceRunning = false
        shell.startRepeatRegression()
      }
    }
  }

  Timer {
    id: codeFlashTimer
    interval: 2
    repeat: true
    onTriggered: {
      if (shell.codeFlashSent > 0 &&
          display.parseCompletionCount <=
            shell.codeFlashCompletionBeforeEdit) return
      if (!display.layoutReady ||
          display.layoutSourceText !== String(display.sourceText || "") ||
          Number(display.codeHighlightPendingCount) !== 0) return
      if (shell.codeFlashPhase === "typing" && shell.codeFlashSent < 6) {
        var fenceStart = shell.codeFlashSource.indexOf("```javascript")
        var codeEnd = shell.codeFlashSource.indexOf("\n```\n", fenceStart)
        shell.codeFlashSource = shell.codeFlashSource.slice(0, codeEnd) +
          "x" + shell.codeFlashSource.slice(codeEnd)
        shell.cursorPosition = codeEnd + 1
        shell.codeFlashSent++
        shell.codeFlashCompletionBeforeEdit = display.parseCompletionCount
        display.sourceText = shell.codeFlashSource
        return
      }
      if (shell.codeFlashPhase === "typing") {
        var fallbackDelta = display.codeFallbackPaintCount -
          shell.codeFlashFallbackStart
        check(fallbackDelta === 0,
          "code-body typing never paints an unhighlighted intermediate frame: " +
            JSON.stringify({characters: shell.codeFlashSent,
              fallbackBefore: shell.codeFlashFallbackStart,
              fallbackAfter: display.codeFallbackPaintCount}))
        initialResult.codeTypingCharacters = shell.codeFlashSent
        initialResult.codeFallbackPaintsDuringTyping = fallbackDelta
        shell.codeFlashPhase = "restore"
        shell.cursorPosition = shell.initialCursorPosition
        shell.codeFlashCompletionBeforeEdit = display.parseCompletionCount
        display.sourceText = shell.source
        return
      }
      stop()
      shell.startRepeatRegression()
    }
  }

  Timer {
    id: repeatTimer
    interval: 8
    repeat: true
    onTriggered: {
      shell.repeatSent++
      display.sourceText = shell.source +
        new Array(shell.repeatSent + 1).join("f")
      if (shell.repeatSent >= 60) {
        stop()
        repeatSettleTimer.start()
      }
    }
  }

  Timer {
    id: repeatSettleTimer
    property int attempts: 0
    interval: 2
    repeat: true
    onTriggered: {
      attempts++
      var expected = shell.source +
        new Array(shell.repeatSent + 1).join("f")
      if (display.layoutReady && display.layoutSourceText === expected &&
          display.parseCompletionCount > shell.repeatCompletionStart) {
        stop()
        shell.repeatRunning = false
        shell.finishRepeat()
      } else if (attempts >= 1000) {
        stop()
        shell.fail("repeat burst did not settle to its final source")
        shell.repeatRunning = false
        shell.finishRepeat()
      }
    }
  }

  Timer {
    id: settledTrailingSpaceTimer
    property int attempts: 0
    interval: 2
    repeat: true
    onTriggered: {
      attempts++
      if (spacingDisplay.layoutReady &&
          spacingDisplay.layoutSourceText === shell.repeatSpacedSource &&
          spacingDisplay.layoutRevision > shell.repeatSpacingLayoutRevision &&
          !spacingDisplay.parsePending && !spacingDisplay.parseInFlight &&
          spacingDisplay.parseCompletionCount >
            shell.repeatSpacingCompletionStart) {
        stop()
        shell.finishSettledTrailingSpaceRegression()
      } else if (attempts >= 1000) {
        stop()
        shell.fail("trailing-space parser settlement did not complete")
        shell.finishSettledTrailingSpaceRegression()
      }
    }
  }

  Component.onCompleted: {
    shell.startedAt = Date.now()
    settleTimer.start()
  }
}
