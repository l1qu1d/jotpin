import QtQuick
import QtQuick.Window
import Quickshell
import "./jotpin" as JotPin

// A deterministic, offscreen performance baseline. It measures the real QML
// parser and rendered Live layout without connecting to Wayland or opening the
// user's notes. The generous budgets are regression alarms, not optimization
// targets; the emitted measurements are the before/after comparison record.
ShellRoot {
  id: shell

  property var failures: []
  property var parserResults: []
  property var layoutResults: []
  property var workloads: []
  property int workloadIndex: -1
  property string activeSource: ""
  property double layoutStartedAt: 0
  property bool awaitingLayout: false
  property real virtualViewportY: 0
  property var pendingLayoutResult: null
  property string viewportProbePhase: ""
  property int viewportProbeBlockIndex: -1
  property int viewportProbePosition: -1
  property int viewportProbeRetries: 0
  property real cachedHeightBeforeEdit: 0
  property real viewportYBeforeEdit: 0
  property string imageBaseUrl: Quickshell.env("JOTPIN_TEST_IMAGE_DIR") === ""
    ? "" : "file://" + Quickshell.env("JOTPIN_TEST_IMAGE_DIR") + "/"

  function mixedNote(targetLength) {
    var sections = []
    var length = 0
    var index = 0
    while (length < targetLength) {
      var section = "## Section " + index + "\n\n" +
        "Paragraph " + index + " has **bold Markdown**, an " +
        "[internal link](note-" + index + ".md), and enough ordinary text " +
        "to wrap while caret and selection geometry are measured.\n\n" +
        "- item " + index + "\n- [ ] task " + index + "\n\n" +
        "```javascript\nconst value = " + index + "\n```"
      sections.push(section)
      length += section.length + (sections.length > 1 ? 2 : 0)
      index++
    }
    return sections.join("\n\n").slice(0, targetLength)
  }

  function mixedNoteWithImage(targetLength) {
    var imageSource = "![viewport fixture](markdown-image.svg)"
    var prefix = mixedNote(Math.floor(targetLength / 2))
    var suffixLength = Math.max(0,
      targetLength - prefix.length - imageSource.length - 4)
    return (prefix + "\n\n" + imageSource + "\n\n" +
      mixedNote(suffixLength)).slice(0, targetLength)
  }

  function fail(message) {
    failures.push(message)
    console.log("PERF_FAIL: " + message)
  }

  function check(condition, message) {
    if (!condition) fail(message)
  }

  function validRect(rect) {
    return rect !== null && rect !== undefined &&
      isFinite(Number(rect.x)) && isFinite(Number(rect.y)) &&
      isFinite(Number(rect.width)) && isFinite(Number(rect.height)) &&
      Number(rect.width) > 0 && Number(rect.height) > 0
  }

  function measureParser(spec) {
    // Warm the QML engine and inline parser cache before recording the three
    // samples. Keep the minimum: timer granularity and unrelated host load can
    // make a median/max threshold flaky, while any large regression affects
    // every sample and therefore the minimum too.
    console.log("PERF_PROGRESS: parsing " + spec.name)
    display.parseMarkdown(spec.source)
    var samples = []
    var blockCount = 0
    for (var sample = 0; sample < 3; sample++) {
      var started = Date.now()
      var blocks = display.parseMarkdown(spec.source)
      samples.push(Date.now() - started)
      blockCount = blocks.length
    }
    var bestMs = Math.min.apply(Math, samples)
    check(blockCount > 0, spec.name + " parser produced blocks")
    check(bestMs < spec.parseBudgetMs,
      spec.name + " parser took " + bestMs +
      " ms; budget " + spec.parseBudgetMs + " ms")
    parserResults.push({name: spec.name, bytes: spec.source.length,
      blocks: blockCount, samplesMs: samples, bestMs: bestMs,
      regressionBudgetMs: spec.parseBudgetMs,
      interactiveTargetMs: spec.parseTargetMs,
      meetsInteractiveTarget: bestMs <= spec.parseTargetMs})
  }

  function startNextLayout() {
    workloadIndex++
    if (workloadIndex >= workloads.length) {
      finish()
      return
    }
    var spec = workloads[workloadIndex]
    console.log("PERF_PROGRESS: laying out " + spec.name)
    activeSource = spec.source
    virtualViewportY = 0
    display.selectionStart = 0
    display.selectionEnd = 0
    display.cursorPosition = 0
    layoutStartedAt = Date.now()
    awaitingLayout = true
    display.sourceText = spec.source
  }

  function measureSettledLayout() {
    var spec = workloads[workloadIndex]
    console.log("PERF_PROGRESS: measuring " + spec.name)
    var layoutMs = Date.now() - layoutStartedAt
    var metrics = display.layoutMetricsForTests()
    check(display.layoutReady && display.layoutSourceText === spec.source,
      spec.name + " layout matches the measured source revision")
    check(metrics.length === display.blocks.length,
      spec.name + " exposes geometry for every rendered block")
    var maximumIndexDrift = 0
    for (var driftIndex = 0; driftIndex < metrics.length; driftIndex++) {
      maximumIndexDrift = Math.max(maximumIndexDrift, Math.abs(
        Number(metrics[driftIndex].y) -
          Number(metrics[driftIndex].geometryTop)))
    }
    check(maximumIndexDrift < 0.5,
      spec.name + " height index matches Column positions; max drift " +
        maximumIndexDrift)
    check(layoutMs < spec.layoutBudgetMs,
      spec.name + " Live layout took " + layoutMs +
      " ms; budget " + spec.layoutBudgetMs + " ms")

    var viewportStats = display.viewportStatsForTests()
    check(Number(viewportStats.cachedMeasuredBlocks) <=
          Number(display.measuredBlockHeightCacheEntryLimit) &&
        Number(viewportStats.cachedMeasuredSourceCharacters) <=
          Number(display.measuredBlockHeightCacheSourceLimit),
      spec.name + " measured-height cache stays bounded")
    var activeMetrics = []
    for (var activeIndex = 0; activeIndex < metrics.length; activeIndex++) {
      if (metrics[activeIndex].contentActive) activeMetrics.push(metrics[activeIndex])
    }
    check(activeMetrics.length === Number(viewportStats.renderedBlocks) &&
        activeMetrics.length > 0,
      spec.name + " reports the exact hydrated block count")
    if (spec.expectVirtualization) {
      check(Number(viewportStats.renderedBlocks) <
          Number(viewportStats.totalBlocks),
        spec.name + " hydrates fewer blocks than the full parsed note: " +
          JSON.stringify(viewportStats))
    }

    var geometryMetrics = []
    for (var geometryIndex = 0; geometryIndex < activeMetrics.length;
         geometryIndex++) {
      if (activeMetrics[geometryIndex].type !== "blank" &&
          Number(activeMetrics[geometryIndex].sourceEnd) >
            Number(activeMetrics[geometryIndex].sourceStart)) {
        geometryMetrics.push(activeMetrics[geometryIndex])
      }
    }
    check(geometryMetrics.length > 0,
      spec.name + " hydrates at least one text-bearing block")

    var caretInvalid = 0
    var caretStarted = Date.now()
    for (var caretSample = 0; caretSample < 120; caretSample++) {
      var caretMetric = geometryMetrics[caretSample % geometryMetrics.length]
      var caretSpan = Math.max(0,
        Number(caretMetric.sourceEnd) - Number(caretMetric.sourceStart))
      var position = Number(caretMetric.sourceStart) +
        Math.max(1, Math.floor(caretSpan * (1 + caretSample % 7) / 8))
      position = Math.min(Number(caretMetric.sourceEnd), position)
      if (!validRect(display.cursorRectangleForSource(position))) caretInvalid++
    }
    var caretMs = Date.now() - caretStarted
    check(caretInvalid === 0,
      spec.name + " caret lookup covers every sampled source position")
    check(caretMs < spec.geometryBudgetMs,
      spec.name + " caret lookup took " + caretMs +
      " ms; budget " + spec.geometryBudgetMs + " ms")

    var pointerInvalid = 0
    var pointerStarted = Date.now()
    for (var pointerSample = 0; pointerSample < 120; pointerSample++) {
      var metric = activeMetrics[pointerSample % activeMetrics.length]
      var pointerPosition = display.sourcePositionForPoint(
        display.horizontalPadding + 8 + pointerSample % 160,
        display.verticalPadding + Number(metric.y) +
          Math.max(1, Number(metric.height) / 2))
      if (pointerPosition < Number(metric.sourceStart) ||
          pointerPosition > Number(metric.sourceEnd)) pointerInvalid++
    }
    var pointerMs = Date.now() - pointerStarted
    check(pointerInvalid === 0,
      spec.name + " pointer lookup stays in the sampled rendered block")
    check(pointerMs < spec.geometryBudgetMs,
      spec.name + " pointer lookup took " + pointerMs +
      " ms; budget " + spec.geometryBudgetMs + " ms")

    display.selectionStart = 0
    display.selectionEnd = spec.source.length
    var selectionStarted = Date.now()
    display.rebuildSelectionTargets()
    display.rebuildSelection()
    var selectionMs = Date.now() - selectionStarted
    var activeTargets = 0
    for (var targetIndex = 0;
         targetIndex < display.selectionTargets.length; targetIndex++) {
      var range = display.selectionRangeForTarget(
        display.selectionTargets[targetIndex])
      if (Number(range.end) > Number(range.start)) activeTargets++
    }
    check(activeTargets > 0,
      spec.name + " select-all activates rendered selection targets")
    check(selectionMs < spec.selectionBudgetMs,
      spec.name + " selection rebuild took " + selectionMs +
      " ms; budget " + spec.selectionBudgetMs + " ms")

    var cacheStats = display.projectionCacheStatsForTests()
    check(Number(cacheStats.cacheRevision) ===
        Number(cacheStats.sourceRevision),
      spec.name + " projection cache matches its source revision")
    check(Number(cacheStats.entries) <=
          Number(display.projectionCacheEntryLimit) &&
        Number(cacheStats.sourceCharacters) <=
          Number(display.projectionCacheSourceLimit) &&
        Number(cacheStats.prefixCharacters) <=
          Number(display.projectionCachePrefixLimit),
      spec.name + " projection cache stays bounded")
    check(Number(cacheStats.parseHits) > 0 &&
        Number(cacheStats.prefixHits) > 0,
      spec.name + " caret pointer and selection paths reuse projections")

    pendingLayoutResult = {name: spec.name, bytes: spec.source.length,
      blocks: display.blocks.length, renderedMetrics: metrics.length,
      initiallyHydratedBlocks: activeMetrics.length,
      selectionTargets: display.selectionTargets.length,
      activeSelectionTargets: activeTargets, layoutMs: layoutMs,
      caret120Ms: caretMs, pointer120Ms: pointerMs,
      selectionRebuildMs: selectionMs,
      projectionCache: cacheStats,
      regressionBudgetsMs: {layout: spec.layoutBudgetMs,
        geometry: spec.geometryBudgetMs,
        selection: spec.selectionBudgetMs},
      interactiveTargetsMs: {layout: spec.layoutTargetMs,
        geometry: spec.geometryTargetMs,
        selection: spec.selectionTargetMs},
      meetsInteractiveTargets: {
        layout: layoutMs <= spec.layoutTargetMs,
        caret: caretMs <= spec.geometryTargetMs,
        pointer: pointerMs <= spec.geometryTargetMs,
        selection: selectionMs <= spec.selectionTargetMs
      }, viewportProbes: []}
    beginViewportProbe("middle")
  }

  function probeBlockIndex(fraction) {
    if (display.blocks.length === 0) return -1
    if (viewportProbePhase === "middle") {
      for (var imageIndex = 0; imageIndex < display.blocks.length;
           imageIndex++) {
        if (display.blocks[imageIndex].type === "image") return imageIndex
      }
    }
    var index = Math.max(0, Math.min(display.blocks.length - 1,
      Math.floor((display.blocks.length - 1) * fraction)))
    while (index > 0 && display.blocks[index].type === "blank") index--
    return index
  }

  function beginViewportProbe(phase) {
    viewportProbePhase = phase
    viewportProbeRetries = 0
    viewportProbeBlockIndex = probeBlockIndex(phase === "middle" ? 0.5 : 0.96)
    var block = display.blocks[viewportProbeBlockIndex]
    viewportProbePosition = Math.floor(
      (Number(block.sourceStart) + Number(block.sourceEnd)) / 2)
    viewportProbePhase = phase + "-force"
    display.cursorPosition = viewportProbePosition
    viewportProbeTimer.restart()
  }

  function validateViewportProbe() {
    if (viewportProbePhase === "edit") {
      if ((!display.layoutReady ||
           display.layoutSourceText !== activeSource) &&
          viewportProbeRetries < 20) {
        viewportProbeRetries++
        viewportProbeTimer.restart()
        return
      }
      var editedMetrics = display.layoutMetricsForTests()
      var unchangedMetric = editedMetrics[0]
      var editedStats = display.viewportStatsForTests()
      check(unchangedMetric && Number(unchangedMetric.measuredHeight) > 0 &&
          Math.abs(Number(unchangedMetric.geometryHeight) -
            cachedHeightBeforeEdit) < 0.5,
        pendingLayoutResult.name +
          " source edit reuses exact height for an unchanged offscreen block")
      check(Math.abs(virtualViewportY - viewportYBeforeEdit) <
          display.viewportHeight,
        pendingLayoutResult.name +
          " source edit preserves the current viewport anchor")
      check(Number(editedStats.cachedMeasuredBlocks) <=
            Number(display.measuredBlockHeightCacheEntryLimit) &&
          Number(editedStats.cachedMeasuredSourceCharacters) <=
            Number(display.measuredBlockHeightCacheSourceLimit),
        pendingLayoutResult.name +
          " source edit keeps measured-height reuse bounded")
      pendingLayoutResult.viewportProbes.push({
        phase: "edit",
        cachedHeight: cachedHeightBeforeEdit,
        restoredHeight: Number(unchangedMetric.geometryHeight),
        viewportYBefore: viewportYBeforeEdit,
        viewportYAfter: virtualViewportY,
        retries: viewportProbeRetries
      })
      finishViewportWorkload()
      return
    }

    var block = display.blocks[viewportProbeBlockIndex]
    var metrics = display.layoutMetricsForTests()
    var metric = metrics[viewportProbeBlockIndex]
    var caret = display.cursorRectangleForSource(viewportProbePosition)
    var imagePending = block && block.type === "image" &&
      (!metric || Number(metric.imageWidth) <= 0 ||
        Number(metric.imageHeight) <= 0)
    if ((!display.layoutReady || !metric || !metric.contentActive ||
         !validRect(caret) || imagePending) && viewportProbeRetries < 20) {
      viewportProbeRetries++
      viewportProbeTimer.restart()
      return
    }

    if (viewportProbePhase.slice(-6) === "-force") {
      check(Number(display.forcedBlockIndex) === viewportProbeBlockIndex &&
          Boolean(metric && metric.contentActive) && validRect(caret),
        pendingLayoutResult.name + " " + viewportProbePhase +
          " pins exact caret geometry before the viewport scrolls")
      var destinationPhase = viewportProbePhase.slice(0, -6)
      virtualViewportY = Math.max(0, Math.min(
        Math.max(0, display.implicitHeight - display.viewportHeight),
        Number(metric.y) - display.viewportHeight / 2))
      viewportProbePhase = destinationPhase
      viewportProbeRetries = 0
      viewportProbeTimer.restart()
      return
    }

    check(Boolean(metric && metric.contentActive),
      pendingLayoutResult.name + " " + viewportProbePhase +
        " viewport hydrates the target source block")
    check(validRect(caret), pendingLayoutResult.name + " " +
      viewportProbePhase + " viewport resolves the exact Live caret")
    if (block.type === "image") {
      check(Number(metric.imageWidth) > 0 && Number(metric.imageHeight) > 0 &&
          Math.abs(Number(metric.geometryHeight) -
            Number(metric.imageContentHeight)) < 0.5,
        pendingLayoutResult.name +
          " virtualized image loads and corrects its indexed height")
    }
    if (validRect(caret)) {
      var hit = display.sourcePositionForPoint(
        Number(caret.x) + Number(caret.width) / 2,
        Number(caret.y) + Number(caret.height) / 2)
      check(hit >= Number(block.sourceStart) && hit <= Number(block.sourceEnd),
        pendingLayoutResult.name + " " + viewportProbePhase +
          " caret-center hit stays in the same source block: " + hit)
    }

    var stats = display.viewportStatsForTests()
    if (workloads[workloadIndex].expectVirtualization) {
      check(Number(stats.renderedBlocks) < Number(stats.totalBlocks),
        pendingLayoutResult.name + " " + viewportProbePhase +
          " viewport remains bounded: " + JSON.stringify(stats))
    }
    check(display.selectionStart === 0 &&
        display.selectionEnd === activeSource.length,
      pendingLayoutResult.name + " " + viewportProbePhase +
        " preserves the global source selection")
    check(display.selectionTargets.length > 0,
      pendingLayoutResult.name + " " + viewportProbePhase +
        " rebuilds selection mirrors for newly hydrated blocks")
    pendingLayoutResult.viewportProbes.push({
      phase: viewportProbePhase,
      blockIndex: viewportProbeBlockIndex,
      sourcePosition: viewportProbePosition,
      viewportY: virtualViewportY,
      renderedBlocks: Number(stats.renderedBlocks),
      totalBlocks: Number(stats.totalBlocks),
      firstRenderedBlock: Number(stats.firstRenderedBlock),
      lastRenderedBlock: Number(stats.lastRenderedBlock),
      itemY: Number(metric.y),
      geometryTop: Number(metric.geometryTop),
      retries: viewportProbeRetries
    })

    if (viewportProbePhase === "middle") {
      beginViewportProbe("bottom")
      return
    }
    if (pendingLayoutResult.name === "long-note") {
      var firstMetric = metrics[0]
      cachedHeightBeforeEdit = Number(firstMetric.geometryHeight)
      viewportYBeforeEdit = virtualViewportY
      viewportProbePhase = "edit"
      viewportProbeRetries = 0
      activeSource = activeSource + "x"
      display.selectionEnd = activeSource.length
      display.cursorPosition = activeSource.length
      display.sourceText = activeSource
      viewportProbeTimer.restart()
      return
    }
    finishViewportWorkload()
  }

  function finishViewportWorkload() {
    console.log("PERF_VIEWPORT_PASS: " + pendingLayoutResult.name)
    layoutResults.push(pendingLayoutResult)
    pendingLayoutResult = null
    viewportProbePhase = ""
    display.selectionStart = 0
    display.selectionEnd = 0
    Qt.callLater(startNextLayout)
  }

  function finish() {
    console.log("PERF_QML_RESULT: " + JSON.stringify({
      parser: parserResults,
      layout: layoutResults,
      failures: failures
    }))
    Qt.exit(failures.length === 0 ? 0 : 1)
  }

  Window {
    width: 720
    height: 900
    visible: true
    color: "#101322"

    JotPin.MarkdownDisplay {
      id: display
      anchors.fill: parent
      viewportRenderingEnabled: true
      viewportY: shell.virtualViewportY
      viewportHeight: parent.height
      viewportOverscan: parent.height
      foreground: "#f0d0b0"
      background: "#101322"
      accent: "#b5a3ff"
      baseUrl: shell.imageBaseUrl
      fontFamily: "monospace"
      bodyPixelSize: 16
      bodyCaretHeight: 16
      sourceText: ""
      cursorPosition: 0
      selectionStart: 0
      selectionEnd: 0
      selectionFill: "#806c78"
      onHeightIndexAdjusted: function(delta, blockTop) {
        if (Number(blockTop) + verticalPadding >= shell.virtualViewportY) return
        shell.virtualViewportY = Math.max(0,
          shell.virtualViewportY + Number(delta))
      }
      onLayoutUpdated: {
        if (!shell.awaitingLayout || !layoutReady ||
            layoutSourceText !== shell.activeSource) return
        shell.awaitingLayout = false
        // Selection-target creation intentionally waits for the delegate
        // polish pass in production. Measure after that same settling window.
        settledMeasurementTimer.restart()
      }
    }
  }

  Timer {
    id: settledMeasurementTimer
    interval: 24
    repeat: false
    onTriggered: shell.measureSettledLayout()
  }

  Timer {
    id: viewportProbeTimer
    interval: 32
    repeat: false
    onTriggered: shell.validateViewportProbe()
  }

  Timer {
    id: startTimer
    interval: 0
    repeat: false
    onTriggered: {
      var parseOnly = [
        {name: "small-note", source: shell.mixedNote(1024),
          parseBudgetMs: 100, parseTargetMs: 16},
        {name: "normal-note", source: shell.mixedNote(10 * 1024),
          parseBudgetMs: 100, parseTargetMs: 50},
        {name: "long-note", source: shell.mixedNoteWithImage(25 * 1024),
          parseBudgetMs: 250, parseTargetMs: 125},
        {name: "large-parse-only-note", source: shell.mixedNote(100 * 1024),
          parseBudgetMs: 750, parseTargetMs: 500}
      ]
      for (var index = 0; index < parseOnly.length; index++)
        shell.measureParser(parseOnly[index])

      shell.workloads = [
        {name: "small-note", source: parseOnly[0].source,
          layoutBudgetMs: 500, geometryBudgetMs: 500,
          selectionBudgetMs: 250,
          layoutTargetMs: 100, geometryTargetMs: 120,
          selectionTargetMs: 32, expectVirtualization: false},
        {name: "normal-note", source: parseOnly[1].source,
          layoutBudgetMs: 1500, geometryBudgetMs: 4000,
          selectionBudgetMs: 750,
          layoutTargetMs: 150, geometryTargetMs: 240,
          selectionTargetMs: 50, expectVirtualization: true},
        {name: "long-note", source: parseOnly[2].source,
          layoutBudgetMs: 8000, geometryBudgetMs: 10000,
          selectionBudgetMs: 4000,
          layoutTargetMs: 500, geometryTargetMs: 240,
          selectionTargetMs: 150, expectVirtualization: true}
      ]
      shell.startNextLayout()
    }
  }

  Component.onCompleted: startTimer.start()
}
