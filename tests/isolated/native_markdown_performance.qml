import QtQuick
import Quickshell

// Disposable offscreen performance coverage for the production native
// Markdown renderer. The shell runner supplies NativeMarkdownDisplay and both
// committed workers from a private config directory. Nothing in this fixture
// opens a window or reads/writes a user note.
ShellRoot {
  id: shell

  property var failures: []
  property var results: []
  property var workloads: [
    {name: "1KiB", targetBytes: 1024, settlementBudgetMs: 3000,
      geometryBudgetMs: 1500, selectionBudgetMs: 1500,
      selectAllBudgetMs: 750},
    {name: "10KiB", targetBytes: 10 * 1024, settlementBudgetMs: 8000,
      geometryBudgetMs: 2500, selectionBudgetMs: 2500,
      selectAllBudgetMs: 1000},
    {name: "25KiB", targetBytes: 25 * 1024, settlementBudgetMs: 15000,
      geometryBudgetMs: 4000, selectionBudgetMs: 4000,
      selectAllBudgetMs: 1500},
    {name: "100KiB", targetBytes: 100 * 1024, settlementBudgetMs: 60000,
      geometryBudgetMs: 10000, selectionBudgetMs: 10000,
      selectAllBudgetMs: 2500}
  ]
  property int workloadIndex: -1
  property string activeName: ""
  property string activeSource: ""
  property int activeCursorPosition: -1
  property int activeSelectionStart: 0
  property int activeSelectionEnd: 0
  property double sourceAssignedAt: 0
  property int settleAttempts: 0
  property int parseDispatchStart: 0
  property int parseCompletionStart: 0
  property int layoutRevisionStart: 0

  NativeMarkdownDisplay {
    id: display
    width: 760
    viewportRenderingEnabled: true
    viewportY: 0
    viewportHeight: 900
    viewportOverscan: 900
    foreground: Qt.rgba(1, 0.79, 0.64, 1)
    background: Qt.rgba(1, 0.79, 0.64, 0.035)
    surfaceBackground: Qt.rgba(0.02, 0.03, 0.08, 1)
    accent: "#b5a3ff"
    baseUrl: Qt.resolvedUrl("./")
    sourceText: shell.activeSource
    cursorPosition: shell.activeCursorPosition
    selectionStart: shell.activeSelectionStart
    selectionEnd: shell.activeSelectionEnd
  }

  function fail(message) {
    failures.push(String(message))
    console.error("PERF_NATIVE_FAIL: " + message)
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

  function section(index, withCode) {
    var result = "## Section " + index + "\n\n" +
      "This deterministic paragraph has **bold text**, *emphasis*, " +
      "`inline code`, and a [link](https://example.com/" + index + ").\n\n" +
      "- [ ] pending task " + index + "\n" +
      "- [x] completed task " + index + "\n\n" +
      "> A quoted reminder for section " + index + ".\n\n" +
      "| Name | Value | Status |\n" +
      "| :--- | ---: | :---: |\n" +
      "| item-" + index + " | " + (index * 7 + 3) +
        " | ready |\n\n"
    if (withCode) {
      result += "```javascript\n" +
        "const sectionValue = " + index + "\n" +
        "console.log(sectionValue)\n" +
        "```\n\n"
    }
    return result
  }

  function sourceForLength(targetBytes) {
    // Keep every workload deterministic and begin with the same complete
    // feature sample. Additional sections stress the same production parser,
    // native rich-text layout, and source/document mapping at larger sizes.
    var source = "# Native Markdown performance fixture\n\n" +
      "The first block anchors the common Markdown/GFM layout contract.\n\n" +
      section(0, true)
    var index = 1
    while (source.length + section(index, false).length <= targetBytes) {
      source += section(index, false)
      index++
    }

    // Finish on ordinary paragraph text so the requested size never cuts a
    // fence, table delimiter, or list marker in half.
    var filler = "Additional deterministic body text keeps this note close to " +
      "the requested byte size while preserving a valid final paragraph. "
    while (source.length < targetBytes) source += filler
    return source.slice(0, targetBytes)
  }

  function sourceProbePositions(source) {
    var positions = []
    var tokens = [
      "Native Markdown", "performance fixture", "Section 0", "bold text",
      "inline code", "pending task", "quoted reminder", "item-0",
      "sectionValue"
    ]
    for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
      var tokenPosition = source.indexOf(tokens[tokenIndex])
      if (tokenPosition >= 0) positions.push(tokenPosition +
        Math.min(3, tokens[tokenIndex].length))
    }
    // Positions distributed across the full source catch mapping and native
    // layout regressions that only appear after many blocks.
    for (var fractionIndex = 1; fractionIndex <= 16; fractionIndex++) {
      positions.push(Math.min(source.length,
        Math.floor(source.length * fractionIndex / 17)))
    }
    return positions
  }

  function runLookups(spec) {
    var positions = sourceProbePositions(activeSource)
    var caretInvalid = 0
    var caretStartedAt = Date.now()
    for (var caretIndex = 0; caretIndex < positions.length; caretIndex++) {
      if (!validRect(display.cursorRectangleForSource(positions[caretIndex])))
        caretInvalid++
    }
    var caretMs = Date.now() - caretStartedAt
    check(caretInvalid === 0,
      spec.name + " caret probes returned invalid rectangles: " + caretInvalid)
    check(caretMs <= spec.geometryBudgetMs,
      spec.name + " caret probes took " + caretMs +
        " ms; ceiling " + spec.geometryBudgetMs + " ms")

    var pointInvalid = 0
    var pointOutside = 0
    var pointStartedAt = Date.now()
    for (var pointIndex = 0; pointIndex < positions.length; pointIndex++) {
      var caret = display.cursorRectangleForSource(positions[pointIndex])
      if (!validRect(caret)) {
        pointInvalid++
        continue
      }
      var hit = Number(display.sourcePositionForPoint(
        Number(caret.x) + Number(caret.width) / 2,
        Number(caret.y) + Number(caret.height) / 2))
      if (!finite(hit) || hit < 0 || hit > activeSource.length) {
        pointInvalid++
      } else if (Math.abs(hit - positions[pointIndex]) > 128) {
        pointOutside++
      }
    }
    var pointMs = Date.now() - pointStartedAt
    check(pointInvalid === 0,
      spec.name + " point-hit probes returned invalid positions: " +
        pointInvalid)
    check(pointOutside === 0,
      spec.name + " point-hit probes drifted outside the nearby source range: " +
        pointOutside)
    check(pointMs <= spec.geometryBudgetMs,
      spec.name + " point-hit probes took " + pointMs +
        " ms; ceiling " + spec.geometryBudgetMs + " ms")

    var selectionInvalid = 0
    var selectionRectangleCount = 0
    var selectionStartedAt = Date.now()
    for (var selectionIndex = 0; selectionIndex < positions.length;
         selectionIndex++) {
      var start = positions[selectionIndex]
      var end = Math.min(activeSource.length, start + 36)
      var rectangles = display.sourceRangeRectangles(start, end)
      if (!Array.isArray(rectangles) || rectangles.length === 0) {
        selectionInvalid++
        continue
      }
      selectionRectangleCount += rectangles.length
      for (var rectangleIndex = 0; rectangleIndex < rectangles.length;
           rectangleIndex++) {
        if (!validRect(rectangles[rectangleIndex])) selectionInvalid++
      }
    }
    var selectionMs = Date.now() - selectionStartedAt
    check(selectionInvalid === 0,
      spec.name + " selection probes returned invalid geometry: " +
        selectionInvalid)
    check(selectionRectangleCount > 0,
      spec.name + " selection probes returned no rectangles")
    check(selectionMs <= spec.selectionBudgetMs,
      spec.name + " selection probes took " + selectionMs +
        " ms; ceiling " + spec.selectionBudgetMs + " ms")

    return {
      caretLookups: positions.length,
      caretInvalid: caretInvalid,
      caretMs: caretMs,
      pointHitLookups: positions.length,
      pointHitInvalid: pointInvalid,
      pointHitOutsideNearbyRange: pointOutside,
      pointHitMs: pointMs,
      selectionLookups: positions.length,
      selectionInvalid: selectionInvalid,
      selectionRectangleCount: selectionRectangleCount,
      selectionMs: selectionMs
    }
  }

  function runSelectAll(spec) {
    var startedAt = Date.now()
    activeSelectionStart = 0
    activeSelectionEnd = activeSource.length
    display.rebuildSelectionRects()
    var elapsed = Date.now() - startedAt
    var scanned = Math.max(0,
      Number(display.selectionGeometrySourceEnd) -
        Number(display.selectionGeometrySourceStart))
    check(display.selectionStart === 0 &&
        display.selectionEnd === activeSource.length,
      spec.name + " Ctrl+A did not retain the complete source selection")
    check(display.nativeSelectAllActive,
      spec.name + " Ctrl+A did not use the native full-document selection")
    check(display.selectionRects.length === 0 && scanned === 0,
      spec.name + " Ctrl+A still generated per-character QML geometry")
    check(elapsed <= spec.selectAllBudgetMs,
      spec.name + " Ctrl+A geometry took " + elapsed +
        " ms; ceiling " + spec.selectAllBudgetMs + " ms")
    return {elapsedMs: elapsed, sourceCharacters: activeSource.length,
      geometrySourceCharacters: scanned,
      visibleRectangleCount: display.selectionRects.length}
  }

  function finishWorkload() {
    var spec = workloads[workloadIndex]
    var source = activeSource
    var parseAndNativeLayoutMs = Math.max(0,
      Date.now() - sourceAssignedAt)
    var treeChildren = display.syntaxTree &&
      Array.isArray(display.syntaxTree.children)
      ? display.syntaxTree.children : []
    check(source.length === spec.targetBytes,
      spec.name + " source length was " + source.length +
        "; expected " + spec.targetBytes)
    check(display.layoutReady && display.layoutSourceText === source,
      spec.name + " layout did not settle on the current source")
    check(display.sourceText === source,
      spec.name + " canonical source changed during rendering")
    check(String(display.renderedHtml || "").indexOf("<table") >= 0,
      spec.name + " rendered HTML did not contain a GFM table")
    check(String(display.renderedHtml || "").indexOf(
        'class="jotpin-quote"') >= 0,
      spec.name + " rendered HTML did not contain the styled blockquote")
    check(String(display.renderedHtml || "").indexOf("<h1>") >= 0 &&
        String(display.renderedHtml || "").indexOf("<strong>") >= 0 &&
        String(display.renderedHtml || "").indexOf("<em>") >= 0 &&
        String(display.renderedHtml || "").indexOf(
          'class="jotpin-inline-code"') >= 0 &&
        String(display.renderedHtml || "").indexOf(
          'class="jotpin-task-list-item"') >= 0 &&
        String(display.renderedHtml || "").indexOf(
          '<table border="1"') >= 0 &&
        String(display.renderedHtml || "").indexOf(
          'class="jotpin-code-block"') >= 0,
      spec.name + " rendered HTML lost a representative Markdown/GFM style")
    check(String(display.documentPlainText || "").length > 0,
      spec.name + " native document remained empty")
    check(String(display.documentPlainText || "").indexOf("sectionValue") >= 0,
      spec.name + " native document lost the syntax-highlighted code text")
    check(display.sourceToDocument.length === source.length + 1,
      spec.name + " source/document mapping did not cover the full source")
    check(display.codeBlocks.length >= 1 &&
        display.codeHighlightResults.length === display.codeBlocks.length &&
        String(display.codeHighlightResults[0] || "").length > 0,
      spec.name + " syntax worker result did not settle")

    var lookupResult = runLookups(spec)
    var selectAllResult = runSelectAll(spec)
    var result = {
      schemaVersion: 1,
      name: spec.name,
      targetBytes: spec.targetBytes,
      sourceBytes: source.length,
      topLevelBlockCount: treeChildren.length,
      renderedHtmlBytes: String(display.renderedHtml || "").length,
      nativeDocumentPlainTextBytes: String(display.documentPlainText || "").length,
      codeBlockCount: display.codeBlocks.length,
      parseAndNativeLayoutMs: parseAndNativeLayoutMs,
      settleAttempts: settleAttempts,
      parseDispatches: display.parseDispatchCount - parseDispatchStart,
      parseCompletions: display.parseCompletionCount - parseCompletionStart,
      layoutRevisionDelta: display.layoutRevision - layoutRevisionStart,
      regressionCeilingsMs: {
        parseAndNativeLayout: spec.settlementBudgetMs,
        geometry: spec.geometryBudgetMs,
        selection: spec.selectionBudgetMs,
        selectAll: spec.selectAllBudgetMs
      },
      lookupMeasurements: lookupResult,
      selectAllMeasurement: selectAllResult,
      failures: failures
    }
    check(result.parseAndNativeLayoutMs <= spec.settlementBudgetMs,
      spec.name + " parse/native layout settlement took " +
        result.parseAndNativeLayoutMs + " ms; ceiling " +
        spec.settlementBudgetMs + " ms")
    results.push(result)
    console.log("PERF_NATIVE_RESULT: " + JSON.stringify(result))
  }

  function startNextWorkload() {
    workloadIndex++
    if (workloadIndex >= workloads.length) {
      check(results.length === workloads.length,
        "completed " + results.length + " workloads; expected " +
          workloads.length)
      console.log("PERF_NATIVE_SUMMARY: " + JSON.stringify({
        schemaVersion: 1,
        workloadCount: results.length,
        failures: failures
      }))
      Qt.exit(failures.length === 0 ? 0 : 1)
      return
    }

    var spec = workloads[workloadIndex]
    var nextSource = sourceForLength(spec.targetBytes)
    activeName = spec.name
    activeCursorPosition = Math.max(0,
      nextSource.indexOf("bold text") + 2)
    activeSelectionStart = Math.max(0,
      nextSource.indexOf("item-0"))
    activeSelectionEnd = Math.min(nextSource.length,
      activeSelectionStart + 18)
    sourceAssignedAt = Date.now()
    settleAttempts = 0
    parseDispatchStart = display.parseDispatchCount
    parseCompletionStart = display.parseCompletionCount
    layoutRevisionStart = display.layoutRevision
    activeSource = nextSource
    console.log("PERF_NATIVE_PROGRESS: settling " + spec.name +
      " (" + activeSource.length + " bytes)")
    settleTimer.start()
  }

  Timer {
    id: settleTimer
    interval: 1
    repeat: true
    onTriggered: {
      shell.settleAttempts++
      var spec = shell.workloads[shell.workloadIndex]
      if (display.layoutReady && display.layoutSourceText ===
          shell.activeSource && !display.parseInFlight &&
          !display.parsePending && display.codeHighlightPendingCount === 0 &&
          String(display.renderedHtml || "").length > 0) {
        stop()
        shell.finishWorkload()
        shell.startNextWorkload()
      } else if (Date.now() - shell.sourceAssignedAt >=
          Number(spec.settlementBudgetMs)) {
        stop()
        shell.fail(shell.activeName + " layout did not settle: " +
          JSON.stringify({layoutReady: display.layoutReady,
            layoutSourceBytes: String(display.layoutSourceText || "").length,
            sourceBytes: shell.activeSource.length,
            parseInFlight: display.parseInFlight,
            parsePending: display.parsePending,
            codeHighlightPendingCount: display.codeHighlightPendingCount}))
        shell.finishWorkload()
        shell.startNextWorkload()
      }
    }
  }

  Timer {
    interval: 0
    running: true
    repeat: false
    onTriggered: shell.startNextWorkload()
  }
}
