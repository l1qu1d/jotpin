import QtQuick
import "SyntaxHighlight.js" as SyntaxHighlight
import "EditorModel.js" as EditorModel

// Production Live renderer: micromark/mdast owns parsing and canonical source
// offsets, while Qt's native QTextDocument owns rich-text layout.
Item {
  id: root

  property string sourceText: ""
  property color foreground: "white"
  property color background: "black"
  property color surfaceBackground: "black"
  property color accent: "white"
  property string fontFamily: "monospace"
  property url baseUrl: ""
  property string homePath: ""
  property bool interactiveEditsEnabled: true
  property bool controlKeyHeld: false
  property int bodyPixelSize: 16
  property real taskCheckboxSize: Math.max(11,
    Math.round(bodyPixelSize * 0.7))
  property int horizontalPadding: 16
  property int verticalPadding: 16
  property int cursorPosition: -1
  property real bodyCaretHeight: bodyPixelSize
  property int selectionStart: 0
  property int selectionEnd: 0
  property color selectionFill: "transparent"
  property bool selectionRenderingEnabled: true
  property var selectionRects: []
  property var selectionTargets: selectionRects
  property int selectionRevision: 0
  property int selectionGeometrySourceStart: 0
  property int selectionGeometrySourceEnd: 0
  property bool nativeSelectAllActive: false
  property int sourceRevision: 0
  property int layoutRevision: 0
  property string layoutSourceText: ""
  property int layoutCursorPosition: -1
  property bool layoutReady: false
  readonly property bool viewportGeometrySettled: layoutReady
  property bool viewportRenderingEnabled: false
  property real viewportY: 0
  property real viewportHeight: height
  property real viewportOverscan: Math.max(256, viewportHeight)
  property int tableToolbarSourceStart: -1
  property real tableToolbarGap: 0
  readonly property string tableToolbarSlotMarker: "\u2063"
  readonly property string emptyListItemSlotMarker: "\u2064"

  property var syntaxTree: null
  property string renderedHtml: ""
  property var codeBlocks: []
  property var codeHighlightResults: []
  property var images: []
  property var imageLoadStates: []
  property var imageLoadCache: ({})
  property var imageRects: []
  property var quoteRailRects: []
  property var taskCheckboxRects: []
  property int taskCheckboxGeometryRevision: 0
  property int quoteRailGeometryRevision: 0
  property int imageGeometryRevision: 0
  property int selectedImageIndex: -1
  property int previewImageIndex: -1
  property int previewImageWidth: 0
  property bool imageResizeActive: false
  property string imageResizeCorner: ""
  property real imageResizeStartPointerX: 0
  property real imageResizeStartPointerY: 0
  property real imageResizeStartWidth: 0
  property real imageResizeStartHeight: 0
  property int pendingImageResizeWidth: 0
  readonly property real imageHandleSize: Math.max(8, bodyPixelSize * 0.65)
  property int codeHighlightPendingCount: 0
  property bool codeHighlightDispatchPending: false
  property int codeFallbackPaintCount: 0
  property int codeHighlightedPaintCount: 0
  property string codePaintState: "none"
  property int pendingStyledReconcileRequestId: -1
  property var sourceToDocument: []
  property var documentToSource: []
  property var tableSourceRegions: []
  property string documentPlainText: ""
  property string documentSourceText: ""
  property int parseRequestId: 0
  property int settledRequestId: -1
  property bool parsePending: false
  property bool parseInFlight: false
  property bool immediateParseRequested: false
  property int parseDispatchCount: 0
  property int parseCompletionCount: 0
  property int optimisticEditCount: 0
  property int parseIdleDelayMs: 40
  property int mouseSelectionAnchor: -1
  property bool mouseSelectionActive: false
  property bool mouseSelectionUpdatePending: false
  property real pendingMouseSelectionX: 0
  property real pendingMouseSelectionY: 0
  property int mouseClickCount: 0
  property string mouseClickKey: ""
  property double mouseClickTimestamp: 0
  property string pendingLinkActivationTarget: ""
  property real pendingLinkPressX: 0
  property real pendingLinkPressY: 0
  property bool pendingLinkPressMoved: false
  readonly property int mouseDoubleClickInterval: Math.max(1,
    Number(Qt.styleHints.mouseDoubleClickInterval) || 400)
  readonly property real linkActivationDragThreshold: Math.max(4,
    Number(Qt.styleHints.startDragDistance) || 10)
  readonly property int pointerCursorShape: pointerArea.cursorShape
  readonly property string hoveredLinkTarget: pointerArea.containsMouse
    ? linkTargetForPoint(pointerArea.mouseX, pointerArea.mouseY) : ""
  readonly property bool linkPointerMarkerVisible: controlKeyHeld &&
    hoveredLinkTarget !== ""
  readonly property point linkPointerMarkerCenter: Qt.point(
    linkPointerMarker.x + linkPointerMarker.width / 2,
    linkPointerMarker.y + linkPointerMarker.height / 2)

  // QTextEdit.contentHeight excludes its top and bottom padding even though
  // cursor rectangles are offset by the top padding. Include both edges in
  // the scroll extent so the final rendered row can rise fully above the
  // viewport boundary with the same inset as the first row.
  implicitHeight: Math.max(bodyPixelSize + verticalPadding * 2,
    nativeDocument.contentHeight + verticalPadding * 2)

  signal layoutUpdated()
  signal heightIndexAdjusted(real delta, real blockTop)
  signal taskToggled(int sourcePosition)
  signal sourcePositionRequested(int sourcePosition)
  signal sourceSelectionRequested(int anchorPosition, int sourcePosition)
  signal imageResizeRequested(int sourceStart, int sourceEnd, int width)
  signal linkActivated(string target)

  function clampSourcePosition(value) {
    return Math.max(0, Math.min(Number(value) || 0, sourceText.length))
  }

  function clampDocumentPosition(value) {
    return Math.max(0, Math.min(Number(value) || 0, nativeDocument.length))
  }

  function requestLayout() {
    styledReconcileTimer.stop()
    pendingStyledReconcileRequestId = -1
    sourceRevision++
    parseRequestId++
    immediateParseRequested = false
    var optimistic = interactiveEditsEnabled &&
      tryApplyOptimisticPlainEdit(String(sourceText || ""))
    if (!optimistic) {
      layoutReady = false
      layoutSourceText = ""
      layoutCursorPosition = -1
      if (!interactiveEditsEnabled) clearProjectedDocumentForLoad()
    }
    parsePending = true
    if (immediateParseRequested && !parseInFlight) {
      parseDelayTimer.stop()
      dispatchParse()
    } else if (!interactiveEditsEnabled || (!syntaxTree && !parseInFlight))
      dispatchParse()
    else scheduleDeferredParse()
  }

  function scheduleDeferredParse() {
    // A restart-on-every-edit debounce never fires while a key is repeating.
    // Keep the first deadline so authoritative parsing advances at a bounded
    // cadence even during a continuous Enter/Backspace stream.
    if (!parseDelayTimer.running) parseDelayTimer.start()
  }

  function clearProjectedDocumentForLoad() {
    renderedHtml = ""
    codeBlocks = []
    codeHighlightResults = []
    codeHighlightPendingCount = 0
    images = []
    imageLoadStates = []
    imageRects = []
    quoteRailRects = []
    taskCheckboxRects = []
    selectedImageIndex = -1
    selectionRects = []
    sourceToDocument = []
    documentToSource = []
    tableSourceRegions = []
    documentPlainText = ""
    documentSourceText = ""
    nativeDocument.text = styledDocumentHtml("")
  }

  function sourceRangeTouchesImageResizeMetadata(sourceValue, startValue,
      endValue) {
    var source = String(sourceValue || "")
    var start = Math.max(0, Math.min(source.length,
      Number(startValue) || 0))
    var end = Math.max(start, Math.min(source.length,
      Number(endValue) || start))
    var metadataPattern =
      /<!--[ \t]*jotpin:image[ \t]+width[ \t]*=[ \t]*[0-9]{1,5}[ \t]*-->/ig
    var match = null
    while ((match = metadataPattern.exec(source)) !== null) {
      var metadataStart = Number(match.index)
      var metadataEnd = metadataStart + String(match[0]).length
      if ((end > start && start < metadataEnd && end > metadataStart) ||
          (end === start && start >= metadataStart &&
            start <= metadataEnd)) return true
    }
    return false
  }

  function sourceRangeTouchesImageProjection(startValue, endValue) {
    var start = Math.max(0, Number(startValue) || 0)
    var end = Math.max(start, Number(endValue) || start)

    function touchesRange(rangeStartValue, rangeEndValue) {
      var rangeStart = Math.max(0, Number(rangeStartValue) || 0)
      var rangeEnd = Math.max(rangeStart, Number(rangeEndValue) || rangeStart)
      if (rangeEnd <= rangeStart) return false
      if (end > start) return start < rangeEnd && end > rangeStart
      // A point edit at the range's outer boundary is adjacent source text,
      // while a point strictly inside changes the projected structure.
      return start > rangeStart && start < rangeEnd
    }

    var imageModels = Array.isArray(images) ? images : []
    for (var imageIndex = 0; imageIndex < imageModels.length; imageIndex++) {
      var image = imageModels[imageIndex] || {}
      if (touchesRange(image.sourceStart, image.sourceEnd)) return true
    }

    return false
  }

  function sourceRangeTouchesCodeFenceHeader(startValue, endValue) {
    var start = Math.max(0, Number(startValue) || 0)
    var end = Math.max(start, Number(endValue) || start)
    var blocks = Array.isArray(codeBlocks) ? codeBlocks : []
    for (var index = 0; index < blocks.length; index++) {
      var block = blocks[index] || {}
      var headerStart = Math.max(0, Number(block.sourceStart) || 0)
      var headerEnd = Math.max(headerStart, Number(block.codeStart) || 0)
      if (headerEnd <= headerStart) continue
      if ((end > start && start < headerEnd && end > headerStart) ||
          (end === start && start > headerStart && start < headerEnd))
        return true
    }
    return false
  }

  function sourceRangeTouchesTaskMarker(sourceValue, startValue, endValue) {
    var source = String(sourceValue || "")
    var start = Math.max(0, Math.min(source.length,
      Number(startValue) || 0))
    var end = Math.max(start, Math.min(source.length,
      Number(endValue) || start))
    var taskPattern = /(^|\n)[ \t]*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\]/g
    var match
    while ((match = taskPattern.exec(source)) !== null) {
      var statePosition = Number(match.index) + String(match[0]).length - 2
      if ((end > start && start <= statePosition && end > statePosition) ||
          (end === start && start === statePosition)) return true
    }
    return false
  }

  function sourceRangeTouchesListMarker(sourceValue, startValue, endValue) {
    var source = String(sourceValue || "")
    var start = Math.max(0, Math.min(source.length,
      Number(startValue) || 0))
    var end = Math.max(start, Math.min(source.length,
      Number(endValue) || start))
    var listPattern = /(^|\n)[ \t]*(?:[-+*]|\d+[.)])[ \t]+/g
    var match
    while ((match = listPattern.exec(source)) !== null) {
      var linePrefixLength = String(match[1] || "").length
      var markerStart = Number(match.index) + linePrefixLength
      var markerEnd = Number(match.index) + String(match[0]).length
      if ((end > start && start < markerEnd && end > markerStart) ||
          (end === start && start >= markerStart && start <= markerEnd))
        return true
    }
    return false
  }

  function headingLevelForOptimisticInsertion(sourceValue, positionValue) {
    var source = String(sourceValue || "")
    var position = Math.max(0, Math.min(source.length,
      Number(positionValue) || 0))
    var lineStart = position > 0
      ? source.lastIndexOf("\n", position - 1) + 1 : 0
    var lineEnd = source.indexOf("\n", position)
    if (lineEnd < 0) lineEnd = source.length
    var line = source.slice(lineStart, lineEnd).replace(/\r$/, "")
    var heading = /^ {0,3}(#{1,6})[ \t]+/.exec(line)
    if (!heading || position < lineStart + String(heading[0]).length ||
        !/\S/.test(line.slice(String(heading[0]).length))) return 0
    return String(heading[1]).length
  }

  function fallbackOptimisticHeadingFormat(levelValue) {
    var level = Math.max(0, Number(levelValue) || 0)
    if (level === 1)
      return {valid: true, pixelSize: Math.round(bodyPixelSize * 2), bold: true}
    if (level === 2)
      return {valid: true, pixelSize: Math.round(bodyPixelSize * 1.5), bold: true}
    if (level === 3)
      return {valid: true, pixelSize: Math.round(bodyPixelSize * 1.17), bold: true}
    if (level === 4)
      return {valid: true, pixelSize: bodyPixelSize, bold: true}
    if (level === 5)
      return {valid: true, pixelSize: Math.round(bodyPixelSize * 0.83), bold: true}
    // Qt's rich-text implementation treats h6 as body-style text under the
    // current shared h4-h6 rule. Preserve that authoritative presentation.
    if (level === 6)
      return {valid: true, pixelSize: Math.round(bodyPixelSize * 1.15), bold: false}
    return ({valid: false})
  }

  function optimisticHeadingFormat(sourceValue, sourcePosition,
      previousSourceValue, previousEndValue, oldSourceToDocumentValue) {
    var level = headingLevelForOptimisticInsertion(
      sourceValue, sourcePosition)
    if (level <= 0) return ({valid: false})
    var previousSource = String(previousSourceValue || "")
    var previousEnd = Math.max(0, Math.min(previousSource.length,
      Number(previousEndValue) || 0))
    var lineStart = sourcePosition > 0
      ? previousSource.lastIndexOf("\n", sourcePosition - 1) + 1 : 0
    var lineEnd = previousSource.indexOf("\n", previousEnd)
    if (lineEnd < 0) lineEnd = previousSource.length
    var previousLine = previousSource.slice(lineStart, lineEnd)
      .replace(/\r$/, "")
    var heading = /^ {0,3}(#{1,6})[ \t]+/.exec(previousLine)
    var contentStart = heading
      ? lineStart + String(heading[0]).length : lineStart
    var candidates = []
    for (var left = Math.min(sourcePosition - 1, lineEnd - 1);
        left >= contentStart; left--)
      candidates.push(left)
    for (var right = Math.max(previousEnd, contentStart);
        right < lineEnd; right++)
      candidates.push(right)
    var map = Array.isArray(oldSourceToDocumentValue)
      ? oldSourceToDocumentValue : []
    for (var index = 0; index < candidates.length; index++) {
      var candidate = candidates[index]
      if (/\s/.test(previousSource.charAt(candidate))) continue
      var documentStart = Number(map[candidate])
      var documentEnd = Number(map[candidate + 1])
      if (!isFinite(documentStart) || !isFinite(documentEnd) ||
          documentEnd <= documentStart) continue
      nativeDocument.select(documentStart, documentEnd)
      var referenceFont = nativeDocument.cursorSelection.font
      var result = {valid: true,
        pixelSize: Number(referenceFont.pixelSize),
        bold: Boolean(referenceFont.bold)}
      nativeDocument.deselect()
      if (result.pixelSize > 0) return result
    }
    return fallbackOptimisticHeadingFormat(level)
  }

  function applyOptimisticHeadingFormat(formatValue, documentStartValue,
      documentLengthValue) {
    var format = formatValue || {}
    var length = Math.max(0, Number(documentLengthValue) || 0)
    if (!format.valid || length <= 0) return
    var start = clampDocumentPosition(documentStartValue)
    var end = clampDocumentPosition(start + length)
    if (end <= start) return
    nativeDocument.select(start, end)
    var headingFont = nativeDocument.cursorSelection.font
    headingFont.pixelSize = Number(format.pixelSize)
    headingFont.bold = Boolean(format.bold)
    nativeDocument.cursorSelection.font = headingFont
    nativeDocument.deselect()
  }

  function tryApplyOptimisticFenceLanguageEdit(previousSourceValue,
      nextSourceValue, prefixValue, previousEndValue, nextEndValue,
      oldSourceToDocumentValue) {
    var previousSource = String(previousSourceValue || "")
    var nextSource = String(nextSourceValue || "")
    var prefix = Math.max(0, Number(prefixValue) || 0)
    var previousEnd = Math.max(prefix, Number(previousEndValue) || prefix)
    var nextEnd = Math.max(prefix, Number(nextEndValue) || prefix)
    var oldSourceToDocument = oldSourceToDocumentValue || []
    var blocks = Array.isArray(codeBlocks) ? codeBlocks : []
    var targetIndex = -1
    for (var index = 0; index < blocks.length; index++) {
      var candidate = blocks[index] || {}
      var candidateLanguageStart = Math.max(0,
        Number(candidate.languageStart) || 0)
      var candidateLanguageEnd = Math.max(candidateLanguageStart,
        Number(candidate.languageEnd) || candidateLanguageStart)
      if (prefix >= candidateLanguageStart &&
          previousEnd <= candidateLanguageEnd) {
        targetIndex = index
        break
      }
    }
    if (targetIndex < 0) return false

    var block = blocks[targetIndex] || {}
    var languageStart = Math.max(0, Number(block.languageStart) || 0)
    var languageEnd = Math.max(languageStart,
      Number(block.languageEnd) || languageStart)
    var sourceDelta = nextSource.length - previousSource.length
    var nextLanguageEnd = languageEnd + sourceDelta
    if (nextLanguageEnd < languageStart || nextLanguageEnd > nextSource.length)
      return false
    var previousLanguage = previousSource.slice(languageStart, languageEnd)
    var nextLanguage = nextSource.slice(languageStart, nextLanguageEnd)
    if (/\s/.test(previousLanguage) || /\s/.test(nextLanguage)) return false

    var previousProjection = codeLanguageProjection(previousLanguage)
    var nextProjection = codeLanguageProjection(nextLanguage)
    var previousLabel = String(previousProjection.label || "")
    var nextLabel = String(nextProjection.label || "")
    var documentStart = Number(oldSourceToDocument[languageStart])
    if (!isFinite(documentStart) || documentStart < 0 ||
        documentStart + previousLabel.length > nativeDocument.length ||
        documentPlainText.slice(documentStart,
          documentStart + previousLabel.length) !== previousLabel)
      return false

    var labelPixelSize = Math.max(1, Math.round(bodyPixelSize * 0.8))
    if (previousLabel.length > 0) {
      nativeDocument.select(documentStart, documentStart + previousLabel.length)
      var previousFont = nativeDocument.cursorSelection.font
      if (Number(previousFont.pixelSize) > 0)
        labelPixelSize = Number(previousFont.pixelSize)
      nativeDocument.deselect()
    }
    if (previousLabel.length > 0)
      nativeDocument.remove(documentStart,
        documentStart + previousLabel.length)
    if (nextLabel.length > 0) nativeDocument.insert(documentStart, nextLabel)
    if (nextLabel.length > 0) {
      nativeDocument.select(documentStart, documentStart + nextLabel.length)
      var nextFont = nativeDocument.cursorSelection.font
      nextFont.pixelSize = labelPixelSize
      nextFont.bold = !nextProjection.placeholder
      nextFont.italic = Boolean(nextProjection.placeholder)
      nativeDocument.cursorSelection.font = nextFont
      nativeDocument.cursorSelection.color = nextProjection.placeholder
        ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.48)
        : accent
      nativeDocument.deselect()
    }

    var documentDelta = nextLabel.length - previousLabel.length
    var nextSourceToDocument = new Array(nextSource.length + 1)
    for (var before = 0; before < languageStart; before++)
      nextSourceToDocument[before] = oldSourceToDocument[before]
    for (var languageOffset = 0;
        languageOffset <= nextLanguage.length; languageOffset++) {
      nextSourceToDocument[languageStart + languageOffset] = documentStart +
        (nextLanguage.length > 0
          ? Math.round(languageOffset * nextLabel.length /
              nextLanguage.length) : 0)
    }
    for (var nextPosition = nextLanguageEnd + 1;
        nextPosition <= nextSource.length; nextPosition++) {
      var previousPosition = nextPosition - sourceDelta
      nextSourceToDocument[nextPosition] =
        Number(oldSourceToDocument[previousPosition]) + documentDelta
    }

    sourceToDocument = nextSourceToDocument
    documentPlainText = nativeDocument.getText(0, nativeDocument.length)
    documentToSource = new Array(nativeDocument.length + 1)
    mapProjectedRun(documentStart, nextLabel.length,
      languageStart, nextLanguage.length)
    for (var sourcePosition = 0; sourcePosition <= nextSource.length;
        sourcePosition++) {
      var mappedDocumentPosition = Number(sourceToDocument[sourcePosition])
      if (isFinite(mappedDocumentPosition) && mappedDocumentPosition >= 0 &&
          mappedDocumentPosition <= nativeDocument.length &&
          documentToSource[mappedDocumentPosition] === undefined)
        documentToSource[mappedDocumentPosition] = sourcePosition
    }
    fillNearestMappings(documentToSource, nativeDocument.length, 0)

    var nextBlocks = []
    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      var previousBlock = blocks[blockIndex] || {}
      var nextBlock = {}
      for (var key in previousBlock) nextBlock[key] = previousBlock[key]
      if (blockIndex === targetIndex) {
        nextBlock.language = nextLanguage
        nextBlock.languageEnd = Number(previousBlock.languageEnd) + sourceDelta
        nextBlock.codeStart = Number(previousBlock.codeStart) + sourceDelta
        nextBlock.sourceEnd = Number(previousBlock.sourceEnd) + sourceDelta
      } else if (blockIndex > targetIndex) {
        nextBlock.sourceStart = Number(previousBlock.sourceStart) + sourceDelta
        nextBlock.sourceEnd = Number(previousBlock.sourceEnd) + sourceDelta
        nextBlock.languageStart = Number(previousBlock.languageStart) + sourceDelta
        nextBlock.languageEnd = Number(previousBlock.languageEnd) + sourceDelta
        nextBlock.codeStart = Number(previousBlock.codeStart) + sourceDelta
      }
      nextBlocks.push(nextBlock)
    }
    codeBlocks = nextBlocks
    documentSourceText = nextSource
    tableSourceRegions = EditorModel.tableRegions(nextSource)
    settledRequestId = parseRequestId
    layoutSourceText = nextSource
    layoutCursorPosition = clampSourcePosition(cursorPosition)
    layoutRevision++
    layoutReady = true
    optimisticEditCount++
    rebuildSelectionRects()
    layoutUpdated()
    return true
  }

  function tryApplyOptimisticPlainEdit(nextSourceValue) {
    var previousSource = String(documentSourceText || "")
    var nextSource = String(nextSourceValue || "")
    if (!layoutReady ||
        previousSource !== String(layoutSourceText || "") ||
        previousSource === nextSource || sourceToDocument.length === 0)
      return false

    var prefix = 0
    var prefixLimit = Math.min(previousSource.length, nextSource.length)
    while (prefix < prefixLimit &&
        previousSource.charAt(prefix) === nextSource.charAt(prefix)) prefix++
    var suffix = 0
    while (suffix < previousSource.length - prefix &&
        suffix < nextSource.length - prefix &&
        previousSource.charAt(previousSource.length - 1 - suffix) ===
          nextSource.charAt(nextSource.length - 1 - suffix)) suffix++

    var previousEnd = previousSource.length - suffix
    var nextEnd = nextSource.length - suffix
    var removed = previousSource.slice(prefix, previousEnd)
    var inserted = nextSource.slice(prefix, nextEnd)
    // Image width metadata is intentionally absent from the rich document.
    // This must cover later resizes that replace only the width digits, not
    // just the first resize that inserts the complete metadata comment.
    if (sourceRangeTouchesImageResizeMetadata(previousSource, prefix,
          previousEnd) ||
        sourceRangeTouchesImageResizeMetadata(nextSource, prefix, nextEnd) ||
        sourceRangeTouchesImageProjection(prefix, previousEnd))
      return false
    // A fence language is a styled projection rather than raw document text.
    // Replace that projected label synchronously, preserve its source mapping,
    // and let the worker reconcile the authoritative tree in the background.
    // This keeps every repeated character and Backspace visible without a
    // transient code-body style or a caret jump to the following row.
    if (sourceRangeTouchesCodeFenceHeader(prefix, previousEnd)) {
      if (tryApplyOptimisticFenceLanguageEdit(previousSource, nextSource,
            prefix, previousEnd, nextEnd, sourceToDocument.slice()))
        return true
      immediateParseRequested = true
      return false
    }
    // Task state is represented by a dedicated QML control. Echoing the raw
    // source character into QTextDocument would briefly flash an "x" beside
    // the checkbox before the parser catches up.
    if (sourceRangeTouchesTaskMarker(previousSource, prefix, previousEnd) ||
        sourceRangeTouchesTaskMarker(nextSource, prefix, nextEnd)) {
      immediateParseRequested = true
      return false
    }
    // List markers are styled projections. Echoing a generated "- " into the
    // plain document makes the raw Markdown dash flash before the parser
    // replaces it with the themed bullet.
    if (sourceRangeTouchesListMarker(previousSource, prefix, previousEnd) ||
        sourceRangeTouchesListMarker(nextSource, prefix, nextEnd)) {
      immediateParseRequested = true
      return false
    }
    // Ordinary edits and pure line-break runs can be echoed directly into the
    // QTextDocument. This keeps every repeated Enter and newline Backspace
    // visible while the authoritative Markdown parse reconciles styling.
    // Mixed structural transitions (for example a generated list marker or
    // complete fence) still wait for the parser so raw syntax never flashes.
    var touchesLineBreak = removed.indexOf("\n") >= 0 ||
      removed.indexOf("\r") >= 0 || inserted.indexOf("\n") >= 0 ||
      inserted.indexOf("\r") >= 0
    var removedIsLineBreakRun = removed === "" ||
      /^(?:\r\n|\r|\n)+$/.test(removed)
    var insertedIsLineBreakRun = inserted === "" ||
      /^(?:\r\n|\r|\n)+$/.test(inserted)
    if (touchesLineBreak &&
        (!removedIsLineBreakRun || !insertedIsLineBreakRun)) return false

    var oldSourceToDocument = sourceToDocument.slice()
    var documentStart = Number(oldSourceToDocument[prefix])
    var documentEnd = Number(oldSourceToDocument[previousEnd])
    if (!isFinite(documentStart) || !isFinite(documentEnd) ||
        documentStart < 0 || documentEnd < documentStart ||
        documentEnd > nativeDocument.length) return false

    var headingFormat = optimisticHeadingFormat(nextSource, prefix,
      previousSource, previousEnd, oldSourceToDocument)

    if (documentEnd > documentStart)
      nativeDocument.remove(documentStart, documentEnd)
    var recoveredWhitespaceStart = prefix
    var recoveredDocumentPrefix = ""
    var previousInsertionAtLineEnd = prefix >= previousSource.length ||
      previousSource.charAt(prefix) === "\n" ||
      previousSource.charAt(prefix) === "\r"
    if (!touchesLineBreak && removed.length === 0 &&
        inserted.length > 0 && previousInsertionAtLineEnd) {
      while (recoveredWhitespaceStart > 0 &&
          previousSource.charAt(recoveredWhitespaceStart - 1) === " ")
        recoveredWhitespaceStart--
      // An authoritative CommonMark render omits a single trailing source
      // space. If the user pauses after Space, both sides of that source range
      // therefore map to the same QTextDocument position. Restore the missing
      // display columns in the same insertion as the next character; otherwise
      // that character paints beside the preceding word for one frame.
      if (recoveredWhitespaceStart < prefix &&
          Number(oldSourceToDocument[recoveredWhitespaceStart]) ===
            documentStart) {
        recoveredDocumentPrefix = new Array(
          prefix - recoveredWhitespaceStart + 1).join("\u00a0")
      }
    }
    var documentInserted = recoveredDocumentPrefix + inserted
    // QTextDocument visually collapses an ordinary space while it is the last
    // character in a block. Keep that just-typed space visible in the
    // optimistic document so the next character cannot appear to jump back
    // against the preceding word. This is display-only: documentSourceText and
    // the saved Markdown retain the original ASCII space, and NBSP has the same
    // one-character source mapping.
    var insertionEndsAtLineBoundary = nextEnd >= nextSource.length ||
      nextSource.charAt(nextEnd) === "\n" ||
      nextSource.charAt(nextEnd) === "\r"
    if (!touchesLineBreak && insertionEndsAtLineBoundary &&
        / +$/.test(documentInserted)) {
      documentInserted = documentInserted.replace(/ +$/, function(spaces) {
        return new Array(spaces.length + 1).join("\u00a0")
      })
    }
    var insertedDocumentOffsets = null
    if (touchesLineBreak && inserted.length > 0) {
      // QTextDocument collapses a trailing bare newline. Bracket each source
      // line break with the same zero-width anchor used by authoritative blank
      // rows so every held Enter has a distinct immediate document position.
      documentInserted = ""
      insertedDocumentOffsets = new Array(inserted.length + 1)
      insertedDocumentOffsets[0] = 0
      var sourceOffset = 0
      while (sourceOffset < inserted.length) {
        if (inserted.charAt(sourceOffset) === "\r" &&
            inserted.charAt(sourceOffset + 1) === "\n") {
          documentInserted += "\u200b\n\u200b"
          insertedDocumentOffsets[sourceOffset + 1] =
            documentInserted.length - 1
          insertedDocumentOffsets[sourceOffset + 2] = documentInserted.length
          sourceOffset += 2
        } else if (inserted.charAt(sourceOffset) === "\n" ||
            inserted.charAt(sourceOffset) === "\r") {
          documentInserted += "\u200b\n\u200b"
          insertedDocumentOffsets[sourceOffset + 1] = documentInserted.length
          sourceOffset++
        } else {
          documentInserted += inserted.charAt(sourceOffset)
          insertedDocumentOffsets[sourceOffset + 1] = documentInserted.length
          sourceOffset++
        }
      }
    }
    if (documentInserted.length > 0)
      nativeDocument.insert(documentStart, documentInserted)
    applyOptimisticHeadingFormat(headingFormat, documentStart,
      documentInserted.length)

    var sourceDelta = inserted.length - removed.length
    var documentDelta = documentInserted.length -
      (documentEnd - documentStart)
    var nextSourceToDocument = new Array(nextSource.length + 1)
    for (var before = 0; before <= prefix; before++)
      nextSourceToDocument[before] = oldSourceToDocument[before]
    for (var recoveredOffset = 1;
        recoveredOffset <= prefix - recoveredWhitespaceStart;
        recoveredOffset++) {
      nextSourceToDocument[recoveredWhitespaceStart + recoveredOffset] =
        documentStart + recoveredOffset
    }
    var recoveredDocumentLength = recoveredDocumentPrefix.length
    for (var insertedOffset = 1; insertedOffset <= inserted.length;
        insertedOffset++)
      nextSourceToDocument[prefix + insertedOffset] =
        documentStart + recoveredDocumentLength + (insertedDocumentOffsets
          ? Number(insertedDocumentOffsets[insertedOffset])
          : insertedOffset)
    for (var nextPosition = nextEnd; nextPosition <= nextSource.length;
        nextPosition++) {
      var previousPosition = nextPosition - sourceDelta
      nextSourceToDocument[nextPosition] =
        Number(oldSourceToDocument[previousPosition]) + documentDelta
    }

    sourceToDocument = nextSourceToDocument
    documentPlainText = nativeDocument.getText(0, nativeDocument.length)
    documentToSource = new Array(nativeDocument.length + 1)
    for (var sourcePosition = 0; sourcePosition <= nextSource.length;
        sourcePosition++) {
      var mappedDocumentPosition = Number(sourceToDocument[sourcePosition])
      if (isFinite(mappedDocumentPosition) && mappedDocumentPosition >= 0 &&
          mappedDocumentPosition <= nativeDocument.length)
        documentToSource[mappedDocumentPosition] = sourcePosition
    }
    fillNearestMappings(documentToSource, nativeDocument.length, 0)
    documentSourceText = nextSource
    tableSourceRegions = EditorModel.tableRegions(nextSource)
    settledRequestId = parseRequestId
    layoutSourceText = nextSource
    layoutCursorPosition = clampSourcePosition(cursorPosition)
    layoutRevision++
    layoutReady = true
    optimisticEditCount++
    rebuildSelectionRects()
    layoutUpdated()
    return true
  }

  function characterFormatForSourceForTests(sourcePositionValue) {
    if (!layoutMatchesCurrentInput()) return ({valid: false})
    var sourcePosition = clampSourcePosition(sourcePositionValue)
    var documentStart = documentPositionForSource(sourcePosition)
    var documentEnd = documentPositionForSource(sourcePosition + 1)
    if (documentEnd <= documentStart) return ({valid: false})
    return characterFormatForDocumentForTests(documentStart)
  }

  function characterFormatForDocumentForTests(documentPositionValue) {
    var documentStart = clampDocumentPosition(documentPositionValue)
    var documentEnd = clampDocumentPosition(documentStart + 1)
    if (documentEnd <= documentStart) return ({valid: false})
    nativeDocument.select(documentStart, documentEnd)
    var selectedFont = nativeDocument.cursorSelection.font
    var result = {
      valid: true,
      pixelSize: Number(selectedFont.pixelSize),
      bold: Boolean(selectedFont.bold)
    }
    nativeDocument.deselect()
    return result
  }

  function colorByte(value) {
    var byte = Math.round(Math.max(0, Math.min(1,
      Number(value) || 0)) * 255).toString(16)
    return byte.length < 2 ? "0" + byte : byte
  }

  function compositeColor(value, underValue) {
    var color = value || foreground
    var under = underValue || surfaceBackground
    var alpha = Math.max(0, Math.min(1, Number(color.a)))
    return Qt.rgba(
      Number(color.r) * alpha + Number(under.r) * (1 - alpha),
      Number(color.g) * alpha + Number(under.g) * (1 - alpha),
      Number(color.b) * alpha + Number(under.b) * (1 - alpha), 1)
  }

  function cssColor(value, underValue) {
    var color = compositeColor(value, underValue || surfaceBackground)
    return "#" + colorByte(color.r) + colorByte(color.g) +
      colorByte(color.b)
  }

  function escapeHtml(value) {
    return String(value || "").replace(/&/g, "&amp;")
      .replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
  }

  function styledDocumentHtml(bodyValue) {
    var foregroundCss = cssColor(foreground)
    var canvasColor = compositeColor(background, surfaceBackground)
    var mutedForeground = Qt.rgba(foreground.r, foreground.g,
      foreground.b, 0.78)
    var subtleBorder = Qt.rgba(foreground.r, foreground.g,
      foreground.b, 0.36)
    var quoteRail = Qt.rgba(foreground.r, foreground.g,
      foreground.b, 0.35)
    var codeBackground = Qt.rgba(foreground.r, foreground.g,
      foreground.b, 0.06)
    var inlineCodeBackground = Qt.rgba(accent.r, accent.g,
      accent.b, 0.16)
    var codeBackgroundCss = cssColor(codeBackground, canvasColor)
    var inlineCodeBackgroundCss = cssColor(
      inlineCodeBackground, canvasColor)
    var family = String(fontFamily || "sans-serif").replace(/'/g, "\\'")
    var paragraphGap = Math.max(4, Math.round(bodyPixelSize * 0.55))
    var blockGap = Math.max(5, Math.round(bodyPixelSize * 0.65))
    var quoteGap = Math.max(4, Math.round(bodyPixelSize * 0.4))
    var codePadding = Math.max(6, Math.round(bodyPixelSize * 0.65))
    var cellVerticalPadding = Math.max(4, Math.round(bodyPixelSize * 0.35))
    var cellHorizontalPadding = Math.max(6, Math.round(bodyPixelSize * 0.55))
    var body = String(bodyValue || "")
      .split("JOTPIN_ACCENT").join(cssColor(accent))
      .split("JOTPIN_INLINE_CODE_BG").join(inlineCodeBackgroundCss)
      .split("JOTPIN_QUOTE_RAIL").join(cssColor(quoteRail))
      .split("JOTPIN_QUOTE_TEXT").join(cssColor(mutedForeground))
      .split("JOTPIN_QUOTE_GAP").join(String(quoteGap))
      .split("JOTPIN_CODE_BG").join(codeBackgroundCss)
    return '<!DOCTYPE html><html><head><meta charset="utf-8"/>' +
      '<style type="text/css">' +
      'body{color:' + foregroundCss + ';font-family:\'' + family +
        '\';font-size:' + bodyPixelSize +
        'px;margin:0;}' +
      'p{margin-top:0;margin-bottom:0;}' +
      'p.jotpin-blank-row{margin:0;padding:0;}' +
      'h1{font-size:' + Math.round(bodyPixelSize * 1.55) +
        'px;margin-top:0;margin-bottom:0;}' +
      'h2{font-size:' + Math.round(bodyPixelSize * 1.3) +
        'px;margin-top:0;margin-bottom:0;}' +
      'h3{font-size:' + Math.round(bodyPixelSize * 1.15) +
        'px;margin-top:0;margin-bottom:0;}' +
      'h4,h5,h6{font-size:' + Math.round(bodyPixelSize * 1.15) +
        'px;margin-top:0;margin-bottom:0;}' +
      'a{color:' + foregroundCss + ';text-decoration:underline;}' +
      'blockquote{color:' + cssColor(mutedForeground) +
        ';margin-left:' + Math.round(bodyPixelSize * 1.2) +
        'px;margin-right:' + cellVerticalPadding +
        'px;border-left:2px solid ' + cssColor(quoteRail) + ';}' +
      '.jotpin-list{margin:0;padding:0;}' +
      '.jotpin-list-item,.jotpin-task-list-item{' +
        'margin:0;padding:0;}' +
      '.jotpin-quote td{border:0;padding:0;}' +
      '.jotpin-code-block td{border:0;}' +
      '.jotpin-image{margin:0;padding:0;}' +
      '.jotpin-image-caption{color:' + cssColor(mutedForeground) + ';}' +
      '.jotpin-image-status{color:' + cssColor(mutedForeground) +
        ';font-style:italic;}' +
      '.jotpin-inline-code{font-family:monospace;}' +
      'code{font-family:monospace;}' +
      'pre{font-family:monospace;background-color:' +
        codeBackgroundCss + ';color:' + foregroundCss +
        ';margin-top:0;margin-bottom:0' +
        'px;padding:' + codePadding + 'px;}' +
      'table{border-collapse:collapse;margin-top:0;margin-bottom:0;}' +
      'table.jotpin-table-helper-space{border:0;margin:0;width:1px;height:' +
        Math.max(0, Math.round(tableToolbarGap)) + 'px;}' +
      'table.jotpin-table-helper-space td{border:0;padding:0;width:1px;height:' +
        Math.max(0, Math.round(tableToolbarGap)) +
        'px;font-size:' + Math.max(1, Math.round(tableToolbarGap)) +
        'px;line-height:' + Math.max(1, Math.round(tableToolbarGap)) +
        'px;color:transparent;}' +
      'th,td{border:1px solid ' + cssColor(subtleBorder) +
        ';padding:' + cellVerticalPadding + 'px ' +
        cellHorizontalPadding + 'px;}' +
      'th{font-weight:bold;background-color:' + codeBackgroundCss + ';}' +
      'hr{height:1px;border-width:0;background-color:' +
        cssColor(Qt.rgba(foreground.r, foreground.g,
          foreground.b, 0.45)) + ';}' +
      '</style></head><body>' + body + '</body></html>'
  }

  function codeLanguageLabel(value) {
    var token = String(value || "").trim().split(/\s+/)[0] || ""
    token = token.replace(/^\./, "")
    if (!token || /^(?:none|plain|text|txt)$/i.test(token)) return ""
    return SyntaxHighlight.languageLabel(token) || token
  }

  function codeLanguageProjection(value) {
    var token = String(value || "").trim().split(/\s+/)[0] || ""
    token = token.replace(/^\./, "")
    return token
      ? {label: codeLanguageLabel(token) || token, placeholder: false}
      : {label: "Language", placeholder: true}
  }

  function imageTagWithWidth(tagValue, widthValue) {
    var tag = String(tagValue || "")
    var width = Math.max(48, Math.round(Number(widthValue) || 0))
    if (!tag || width <= 0) return tag
    tag = tag.replace(/[ \t]+width=(?:"[^"]*"|'[^']*'|[^ \t>]+)/i, "")
    return tag.replace(/^<img\b/i, '<img width="' + width + '"')
  }

  function imageLoadStateAt(indexValue) {
    var index = Math.max(0, Number(indexValue) || 0)
    var state = index < imageLoadStates.length
      ? String(imageLoadStates[index] || "") : ""
    return state === "ready" || state === "error" ? state : "loading"
  }

  function cachedImageLoadState(urlValue) {
    var resolved = linkSourceUrl(urlValue)
    var state = String(imageLoadCache[resolved] || "")
    return state === "ready" || state === "error" ? state : ""
  }

  function imageFallbackText(indexValue, stateValue) {
    var index = Math.max(0, Number(indexValue) || 0)
    var model = index < images.length ? images[index] || {} : {}
    var state = String(stateValue || imageLoadStateAt(index))
    if (state !== "error") return "Loading image..."
    var message = "Image cannot be displayed."
    var alt = String(model.alt || "")
    return Boolean(model.standalone) || !alt
      ? message : message + " " + alt
  }

  function setImageLoadState(indexValue, requestIdValue, urlValue,
      stateValue) {
    var index = Math.max(0, Number(indexValue) || 0)
    if (Number(requestIdValue) !== parseRequestId || index >= images.length)
      return
    var model = images[index] || {}
    if (String(model.url || "") !== String(urlValue || "")) return
    var state = String(stateValue || "loading")
    if (state !== "ready" && state !== "error") state = "loading"
    if (imageLoadStateAt(index) === state) return
    var nextStates = imageLoadStates.slice()
    while (nextStates.length < images.length) nextStates.push("loading")
    nextStates[index] = state
    imageLoadStates = nextStates
    var resolved = linkSourceUrl(model.url)
    if (resolved) {
      var nextCache = Object.assign({}, imageLoadCache)
      nextCache[resolved] = state
      imageLoadCache = nextCache
    }
    // Rebuild the same native document after the asynchronous load result so
    // a failed QTextDocument image object is never left as Qt's broken-file
    // icon. The canonical Markdown source is unchanged.
    if (refreshStyledDocument()) {
      layoutReady = false
      settleCurrentDocument()
    }
  }

  function htmlWithEffectiveImageWidths(value) {
    var html = String(value || "")
    var models = Array.isArray(images) ? images : []
    if (models.length === 0) return html
    var maximumWidth = Math.max(48, Number(width) - horizontalPadding * 2)
    var expression = /<img\b[^>]*>/ig
    var result = ""
    var cursor = 0
    var index = 0
    var match
    while ((match = expression.exec(html)) !== null) {
      result += html.slice(cursor, Number(match.index))
      var model = index < models.length ? models[index] : null
      var requested = index === previewImageIndex && previewImageWidth > 0
        ? previewImageWidth : Number(model && model.width) || 0
      result += requested > 0
        ? imageTagWithWidth(match[0], Math.min(maximumWidth, requested))
        : match[0]
      cursor = Number(match.index) + String(match[0]).length
      index++
    }
    return result + html.slice(cursor)
  }

  function htmlWithImageLoadStates(value) {
    var html = String(value || "")
    var models = Array.isArray(images) ? images : []
    if (models.length === 0) return html
    var expression = /<img\b[^>]*>/ig
    var index = 0
    return html.replace(expression, function(match) {
      var state = imageLoadStateAt(index)
      var replacement = match
      if (state !== "ready") {
        replacement = '<span class="jotpin-image-status">' +
          escapeHtml(imageFallbackText(index, state)) + '</span>'
      }
      index++
      return replacement
    })
  }

  function tableOrdinalForSourceStart(sourceStartValue) {
    var target = Number(sourceStartValue)
    if (!isFinite(target) || target < 0 || !syntaxTree) return -1
    var ordinal = 0
    var found = -1

    function visit(node) {
      if (!node || found >= 0) return
      if (String(node.type || "") === "table") {
        var position = node.position || {}
        var start = position.start || {}
        if (Number(start.offset) === target) {
          found = ordinal
          return
        }
        ordinal++
      }
      var children = Array.isArray(node.children) ? node.children : []
      for (var index = 0; index < children.length; index++)
        visit(children[index])
    }

    visit(syntaxTree)
    return found
  }

  function htmlWithActiveTableGap(value) {
    var html = String(value || "")
    if (tableToolbarGap <= 0) return html
    var targetOrdinal = tableOrdinalForSourceStart(tableToolbarSourceStart)
    if (targetOrdinal < 0) return html
    // The renderer also uses borderless tables to lay out code blocks and
    // blockquotes. Only GFM tables carry border=1, so do not count those
    // internal layout tables when locating the active Markdown table.
    var expression = /<table\b[^>]*>/ig
    var ordinal = 0
    return html.replace(expression, function(match) {
      if (!/\bborder\s*=\s*(?:"1"|'1'|1)(?=\s|\/?\>)/i.test(match))
        return match
      if (ordinal++ !== targetOrdinal) return match
      return '<table class="jotpin-table-helper-space"><tr><td>' +
        '&#8291;</td></tr></table>' + match
    })
  }

  function htmlWithEmptyListItemSlots(value) {
    var html = String(value || "")
    // QTextDocument collapses a paragraph containing only a visible list
    // marker onto the preceding paragraph. Give parsed empty list items an
    // invisible document character so their caret owns a real visual row.
    return html.replace(
      /(<p class="jotpin-list-item">)((?:\u00a0\u00a0)*(?:• |\d+\. ))(<\/p>)/g,
      "$1$2<span class=\"jotpin-empty-list-slot\">&#8292;</span>$3")
  }

  function listItemStyle(prefixLength) {
    var hangingIndent = Math.max(1,
      Number(prefixLength) * bodyPixelSize * 0.58)
    return ' style="margin:0 0 0 ' + hangingIndent +
      'px;padding:0;text-indent:-' + hangingIndent + 'px"'
  }

  function htmlWithListHangingIndents(value) {
    var html = String(value || "")
    html = html.replace(
      /<p class="jotpin-list-item">((?:\u00a0\u00a0)*(?:• |\d+\. ))/g,
      function(match, prefix) {
        return '<p class="jotpin-list-item"' +
          listItemStyle(String(prefix || "").length) + '>' + prefix
      })
    return html.replace(
      /<p class="jotpin-task-list-item">((?:\u00a0\u00a0)*)<span\b/g,
      function(match, indentation) {
        // Checkbox projection occupies three glyph columns and is followed by
        // the source separator before task text, for four columns total.
        return '<p class="jotpin-task-list-item"' +
          listItemStyle(String(indentation || "").length + 4) + '>' +
          indentation + '<span'
      })
  }

  function refreshStyledDocument() {
    if (!renderedHtml) {
      codePaintState = "none"
      nativeDocument.text = styledDocumentHtml("")
      imageGeometryTimer.restart()
      return true
    }
    var body = htmlWithImageLoadStates(htmlWithEffectiveImageWidths(
      htmlWithListHangingIndents(htmlWithEmptyListItemSlots(
        htmlWithActiveTableGap(renderedHtml)))))
    var blocks = Array.isArray(codeBlocks) ? codeBlocks : []
    var results = Array.isArray(codeHighlightResults)
      ? codeHighlightResults : []
    for (var pendingIndex = 0; pendingIndex < blocks.length;
         pendingIndex++) {
      // Keep the already-painted, optimistically updated code document until
      // Highlight.js has resolved every block for this exact source revision.
      // Painting fallback HTML here and replacing it milliseconds later is the
      // per-character syntax-color flash reported during code-body typing.
      if (results[pendingIndex] === undefined) return false
    }
    var usedCodeFallback = false
    for (var index = 0; index < blocks.length; index++) {
      var block = blocks[index] || {}
      var token = String(block.token || "")
      if (!token) continue
      var highlighted = results[index]
      var replacement = highlighted !== undefined && String(highlighted)
        ? String(highlighted) : String(block.fallbackHtml || "")
      if (highlighted === undefined || !String(highlighted))
        usedCodeFallback = true
      var languageProjection = codeLanguageProjection(block.language)
      var languageLabel = String(languageProjection.label || "")
      var languageColor = languageProjection.placeholder
        ? cssColor(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.48))
        : cssColor(accent)
      var languageMarkup = languageProjection.placeholder
        ? '<i>' + escapeHtml(languageLabel) + '</i>'
        : '<b>' + escapeHtml(languageLabel) + '</b>'
      replacement = '<font color="' + languageColor + '"><small>' +
        languageMarkup + '</small></font><br/>' + replacement
      body = body.split(token).join(replacement)
    }
    if (blocks.length === 0) {
      codePaintState = "none"
    } else if (usedCodeFallback) {
      codePaintState = "fallback"
      codeFallbackPaintCount++
    } else {
      codePaintState = "highlighted"
      codeHighlightedPaintCount++
    }
    nativeDocument.text = styledDocumentHtml(body)
    imageGeometryTimer.restart()
    return true
  }

  function codeHighlightDark() {
    return Number(background.r) * 0.2126 +
      Number(background.g) * 0.7152 + Number(background.b) * 0.0722 < 0.5
  }

  function dispatchCodeHighlights() {
    var blocks = Array.isArray(codeBlocks) ? codeBlocks : []
    codeHighlightPendingCount = blocks.length
    if (blocks.length === 0) {
      codeHighlightDispatchPending = false
      return
    }
    if (!codeHighlightWorker.ready) {
      codeHighlightDispatchPending = true
      return
    }
    codeHighlightDispatchPending = false
    for (var index = 0; index < blocks.length; index++) {
      var block = blocks[index] || {}
      codeHighlightWorker.sendMessage({
        type: "highlight",
        key: String(parseRequestId) + ":" + String(index),
        code: String(block.code || ""),
        language: String(block.language || ""),
        dark: codeHighlightDark()
      })
    }
  }

  function settleCurrentDocument() {
    settleTimer.requestId = parseRequestId
    settleTimer.attempts = 0
    settleTimer.restart()
  }

  function scheduleStyledReconcile(requestIdValue) {
    pendingStyledReconcileRequestId = Number(requestIdValue)
    styledReconcileTimer.restart()
  }

  function reconcileProjectedDocument() {
    var requestId = Number(pendingStyledReconcileRequestId)
    pendingStyledReconcileRequestId = -1
    if (requestId !== parseRequestId || parseInFlight || parsePending ||
        documentSourceText !== String(sourceText || "") ||
        layoutSourceText !== String(sourceText || "") || !layoutReady)
      return false
    if (!refreshStyledDocument()) return false
    // Both documents represent this exact source revision. Rebuild the maps in
    // the same event as the repaint so a newly arriving key can never observe
    // a replaced QTextDocument paired with the prior mapping table.
    rebuildMappings(requestId)
    return true
  }

  function dispatchParse() {
    if (!parserWorker.ready || parseInFlight) {
      parsePending = true
      return
    }
    parsePending = false
    parseInFlight = true
    parseDispatchCount++
    parserWorker.sendMessage({
      type: "parse",
      key: String(parseRequestId),
      source: String(sourceText || "")
    })
  }

  function collectLeafSegments(node, result, insideTable, imageState) {
    if (!node) return
    var currentImageState = imageState || {index: 0}
    var type = String(node.type || "")
    var leafInsideTable = Boolean(insideTable) || type === "table"
    var children = Array.isArray(node.children) ? node.children : []
    if (children.length > 0) {
      for (var childIndex = 0; childIndex < children.length; childIndex++)
        collectLeafSegments(children[childIndex], result, leafInsideTable,
          currentImageState)
      return
    }
    if (!node.position || !node.position.start || !node.position.end) return
    if (type === "text" || type === "inlineCode" || type === "code" ||
        type === "blank") {
      result.push({
        type: type,
        value: String(node.value || ""),
        start: Number(node.position.start.offset),
        end: Number(node.position.end.offset),
        insideTable: leafInsideTable
      })
    } else if (type === "image") {
      result.push({
        type: type,
        imageIndex: currentImageState.index++,
        value: String(node.alt || ""),
        start: Number(node.position.start.offset),
        end: Number(node.position.end.offset),
        insideTable: leafInsideTable
      })
    }
  }

  function mapRun(documentStart, sourceStart, length) {
    var count = Math.max(0, Number(length) || 0)
    for (var offset = 0; offset <= count; offset++) {
      var documentPosition = clampDocumentPosition(documentStart + offset)
      var sourcePosition = clampSourcePosition(sourceStart + offset)
      documentToSource[documentPosition] = sourcePosition
      sourceToDocument[sourcePosition] = documentPosition
    }
  }

  function mapProjectedRun(documentStart, documentLength,
      sourceStart, sourceLength) {
    var safeDocumentLength = Math.max(0, Number(documentLength) || 0)
    var safeSourceLength = Math.max(0, Number(sourceLength) || 0)
    for (var documentOffset = 0; documentOffset <= safeDocumentLength;
         documentOffset++) {
      var sourceOffset = safeDocumentLength > 0
        ? Math.round(documentOffset * safeSourceLength / safeDocumentLength) : 0
      documentToSource[clampDocumentPosition(documentStart + documentOffset)] =
        clampSourcePosition(sourceStart + sourceOffset)
    }
    for (var sourceOffset = 0; sourceOffset <= safeSourceLength;
         sourceOffset++) {
      var documentOffset = safeSourceLength > 0
        ? Math.round(sourceOffset * safeDocumentLength / safeSourceLength) : 0
      sourceToDocument[clampSourcePosition(sourceStart + sourceOffset)] =
        clampDocumentPosition(documentStart + documentOffset)
    }
  }

  function mapCodeLanguageLabels() {
    var blocks = Array.isArray(codeBlocks) ? codeBlocks : []
    var documentSearch = 0
    for (var index = 0; index < blocks.length; index++) {
      var block = blocks[index] || {}
      var projection = codeLanguageProjection(block.language)
      var label = String(projection.label || "")
      var languageStart = clampSourcePosition(block.languageStart)
      var languageEnd = clampSourcePosition(block.languageEnd)
      if (!label || languageEnd < languageStart) continue

      var codeStart = clampSourcePosition(block.codeStart)
      var codeDocumentPosition = sourceToDocument[codeStart]
      var labelDocumentPosition = -1
      if (codeDocumentPosition !== undefined &&
          Number(codeDocumentPosition) >= documentSearch) {
        labelDocumentPosition = documentPlainText.lastIndexOf(
          label, Math.max(documentSearch,
            Number(codeDocumentPosition) - 1))
        if (labelDocumentPosition < documentSearch)
          labelDocumentPosition = -1
      }
      if (labelDocumentPosition < 0)
        labelDocumentPosition = documentPlainText.indexOf(label, documentSearch)
      if (labelDocumentPosition < 0) continue

      mapProjectedRun(labelDocumentPosition, label.length,
        languageStart, languageEnd - languageStart)

      // The opening fence is hidden by the styled language header. Anchor its
      // first source boundary to that header instead of leaving it on the end
      // of a preceding synthetic blank row. Without this explicit boundary,
      // the final blank newline and the opening fence can share one caret row,
      // making the blank row impossible to distinguish or select visually.
      var fenceStart = clampSourcePosition(block.sourceStart)
      sourceToDocument[fenceStart] = labelDocumentPosition

      // An empty fenced body has no leaf text for mapLeafSegment() to anchor.
      // Keep its first editable source position on the visual row after the
      // language header instead of letting nearest-neighbor filling collapse
      // it back onto the end of the header label.
      if (String(block.code || "") === "") {
        var emptyCodeDocumentPosition = clampDocumentPosition(
          labelDocumentPosition + label.length + 1)
        sourceToDocument[codeStart] = emptyCodeDocumentPosition
        documentToSource[emptyCodeDocumentPosition] = codeStart
      }
      documentSearch = labelDocumentPosition + label.length
    }
  }

  function mapEmptyListItems() {
    var emptyItems = []
    function collect(node) {
      if (!node) return
      var children = Array.isArray(node.children) ? node.children : []
      if (String(node.type || "") === "listItem" && children.length === 0 &&
          node.position && node.position.start && node.position.end) {
        emptyItems.push({
          start: Number(node.position.start.offset),
          end: Number(node.position.end.offset)
        })
      }
      for (var index = 0; index < children.length; index++)
        collect(children[index])
    }
    collect(syntaxTree)

    var documentSearch = 0
    for (var itemIndex = 0; itemIndex < emptyItems.length; itemIndex++) {
      var item = emptyItems[itemIndex]
      var slot = documentPlainText.indexOf(
        emptyListItemSlotMarker, documentSearch)
      if (slot < 0) break
      var markerText = sourceText.slice(item.start, item.end)
      var markerLength = Math.max(1, markerText.length)
      var markerStart = Math.max(documentSearch, slot - markerLength)
      mapProjectedRun(markerStart, slot - markerStart,
        item.start, item.end - item.start)
      sourceToDocument[clampSourcePosition(item.end)] = slot
      documentToSource[clampDocumentPosition(slot)] =
        clampSourcePosition(item.end)
      documentSearch = slot + 1
    }
  }

  function normalizedDocumentText(value) {
    return String(value || "").replace(/[\u2028\u2029]/g, "\n")
      .replace(/\u00a0/g, " ")
  }

  function exactSegmentDocumentPosition(segment, documentStart) {
    if (!segment) return -1
    var value = String(segment.value || "")
    if (!value) return -1
    var start = Math.max(0, Number(documentStart) || 0)
    return segment.type === "code"
      ? normalizedDocumentText(documentPlainText).indexOf(value, start)
      : documentPlainText.indexOf(value, start)
  }

  function firstSegmentDocumentPosition(segment, documentStart) {
    var exact = exactSegmentDocumentPosition(segment, documentStart)
    if (exact >= 0) return exact
    var match = /\S+/.exec(String(segment && segment.value || ""))
    return match ? documentPlainText.indexOf(
      String(match[0] || ""), Math.max(0, Number(documentStart) || 0)) : -1
  }

  function mapLeafSegment(segment, searchState) {
    var value = String(segment.value || "")
    var sourceStart = clampSourcePosition(segment.start)
    var sourceEnd = clampSourcePosition(segment.end)
    var sourceSlice = sourceText.slice(sourceStart, sourceEnd)
    var valueOffset = sourceSlice.indexOf(value)
    var contentSourceStart = valueOffset >= 0
      ? sourceStart + valueOffset : sourceStart

    if (segment.type === "image") {
      var imageIndex = Math.max(0, Number(segment.imageIndex) || 0)
      var imageState = imageLoadStateAt(imageIndex)
      var caption = String(segment.value || "")
      if (imageState === "ready") {
        var imageDocumentPosition = documentPlainText.indexOf(
          "\ufffc", searchState.document)
        if (imageDocumentPosition >= 0) {
          mapProjectedRun(imageDocumentPosition, 1,
            sourceStart, sourceEnd - sourceStart)
          searchState.document = imageDocumentPosition + 1
        }
      } else {
        var fallback = imageFallbackText(imageIndex, imageState)
        var fallbackPosition = fallback
          ? documentPlainText.indexOf(fallback, searchState.document) : -1
        if (fallbackPosition >= 0) {
          mapProjectedRun(fallbackPosition, fallback.length,
            sourceStart, sourceEnd - sourceStart)
          searchState.document = fallbackPosition + fallback.length
        }
      }
      var captionPosition = caption
        ? documentPlainText.indexOf(caption, searchState.document) : -1
      if (captionPosition >= 0) {
        var captionSourceOffset = sourceSlice.indexOf(caption)
        var captionSourceStart = captionSourceOffset >= 0
          ? sourceStart + captionSourceOffset : sourceStart
        mapRun(captionPosition, captionSourceStart, caption.length)
        if (imageState === "ready") {
          sourceToDocument[sourceStart] = captionPosition
          sourceToDocument[sourceEnd] = captionPosition + caption.length
        }
        documentToSource[captionPosition + caption.length] = sourceEnd
        searchState.document = captionPosition + caption.length
      }
      return
    }

    // Code is emitted as one contiguous preformatted run. Map the complete
    // value, including its newlines and otherwise-collapsible whitespace, so
    // every source column in a fence remains directly editable.
    if (segment.type === "code" && valueOffset >= 0) {
      var codeDocumentPosition = normalizedDocumentText(
        documentPlainText).indexOf(value, searchState.document)
      if (codeDocumentPosition >= 0) {
        mapRun(codeDocumentPosition, contentSourceStart, value.length)
        searchState.document = codeDocumentPosition + value.length
        return
      }
    }

    var expression = /\S+/g
    var match
    var sourceSearch = Math.max(0, contentSourceStart - sourceStart)
    while ((match = expression.exec(value)) !== null) {
      var token = String(match[0] || "")
      if (!token) continue
      var documentPosition = documentPlainText.indexOf(token,
        searchState.document)
      if (documentPosition < 0) continue
      var localSourcePosition = sourceSlice.indexOf(token, sourceSearch)
      var tokenSourceStart = localSourcePosition >= 0
        ? sourceStart + localSourcePosition
        : Math.min(sourceEnd, contentSourceStart + Number(match.index))
      mapRun(documentPosition, tokenSourceStart, token.length)
      searchState.document = documentPosition + token.length
      sourceSearch = Math.max(sourceSearch,
        tokenSourceStart - sourceStart + token.length)
    }
  }

  function fillNearestMappings(map, maximum, fallback) {
    var next = new Array(maximum + 1)
    var nextValue = -1
    for (var reverse = maximum; reverse >= 0; reverse--) {
      if (map[reverse] !== undefined && Number(map[reverse]) >= 0)
        nextValue = Number(map[reverse])
      next[reverse] = nextValue
    }
    var previousValue = -1
    var previousIndex = -1
    for (var index = 0; index <= maximum; index++) {
      if (map[index] !== undefined && Number(map[index]) >= 0) {
        previousValue = Number(map[index])
        previousIndex = index
        continue
      }
      var followingValue = next[index]
      if (previousValue < 0) map[index] = followingValue >= 0
        ? followingValue : fallback
      else if (followingValue < 0) map[index] = previousValue
      else {
        var followingIndex = index
        while (followingIndex <= maximum &&
            (map[followingIndex] === undefined ||
             Number(map[followingIndex]) < 0)) followingIndex++
        map[index] = index - previousIndex <= followingIndex - index
          ? previousValue : followingValue
      }
    }
  }

  function rebuildMappings(requestId) {
    if (requestId !== parseRequestId || !syntaxTree) return
    documentPlainText = nativeDocument.getText(0, nativeDocument.length)
    documentSourceText = String(sourceText || "")
    tableSourceRegions = EditorModel.tableRegions(sourceText)
    sourceToDocument = new Array(sourceText.length + 1)
    documentToSource = new Array(nativeDocument.length + 1)
    var segments = []
    collectLeafSegments(syntaxTree, segments, false, {index: 0})
    var searchState = {document: 0}
    for (var segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
      var nextSegment = segmentIndex + 1 < segments.length
        ? segments[segmentIndex + 1] : null
      var documentBoundary = exactSegmentDocumentPosition(
        nextSegment, searchState.document)
      var segment = segments[segmentIndex]
      var segmentCandidate = firstSegmentDocumentPosition(
        segment, searchState.document)
      // GFM can discard surplus table cells. Do not let a token from one of
      // those omitted cells jump forward to a later occurrence and move the
      // search cursor past every intervening block.
      if (segment.insideTable && nextSegment && documentBoundary >= 0 &&
          segmentCandidate >= 0 &&
          segmentCandidate > documentBoundary &&
          String(segment.value || "") !== String(nextSegment.value || ""))
        continue
      mapLeafSegment(segment, searchState)
    }
    mapCodeLanguageLabels()
    mapEmptyListItems()

    if (sourceText.length === 0 || nativeDocument.length === 0) {
      sourceToDocument[0] = 0
      documentToSource[0] = 0
    }
    fillNearestMappings(sourceToDocument, sourceText.length, 0)
    fillNearestMappings(documentToSource, nativeDocument.length, 0)
    settledRequestId = requestId
    layoutSourceText = String(sourceText || "")
    layoutCursorPosition = clampSourcePosition(cursorPosition)
    layoutRevision++
    layoutReady = true
    rebuildQuoteRailRects()
    rebuildTaskCheckboxRects()
    rebuildSelectionRects()
    rebuildImageRects()
    layoutUpdated()
  }

  function layoutMatchesCurrentInput() {
    // requestLayout() advances parseRequestId synchronously for every source
    // change. Comparing the complete source strings here made every caret and
    // selection geometry lookup O(note length), turning viewport-sized Ctrl+A
    // painting into quadratic work on large notes.
    return layoutReady && settledRequestId === parseRequestId
  }

  function documentPositionForSource(sourcePosition) {
    if (!layoutMatchesCurrentInput()) return 0
    var position = clampSourcePosition(sourcePosition)
    return clampDocumentPosition(sourceToDocument[position])
  }

  function documentRectangle(documentPosition) {
    var rectangle = nativeDocument.positionToRectangle(
      clampDocumentPosition(documentPosition))
    if (!rectangle) return null
    return Qt.rect(Number(rectangle.x), Number(rectangle.y),
      Number(rectangle.width), Number(rectangle.height))
  }

  function tableToolbarSlotRectangle() {
    if (!layoutMatchesCurrentInput() || tableToolbarGap <= 0) return null
    var documentPosition = documentPlainText.indexOf(tableToolbarSlotMarker)
    if (documentPosition < 0) return null
    var rectangle = documentRectangle(documentPosition)
    if (!rectangle) return null
    return Qt.rect(Number(rectangle.x), Number(rectangle.y),
      Number(rectangle.width), Number(rectangle.height))
  }

  function nativeRectangleForDocumentPositionForTests(documentPosition) {
    return documentRectangle(documentPosition)
  }

  function rebuildImageRects() {
    var models = Array.isArray(images) ? images : []
    var nextRects = new Array(models.length)
    var documentSearch = 0
    for (var index = 0; index < models.length; index++) {
      var model = models[index] || {}
      if (imageLoadStateAt(index) !== "ready") continue
      var documentPosition = documentPlainText.indexOf(
        "\ufffc", documentSearch)
      if (documentPosition < 0) break
      documentSearch = documentPosition + 1
      if (!Boolean(model.standalone)) continue
      var start = documentRectangle(documentPosition)
      var after = documentRectangle(documentPosition + 1)
      if (!start || !after ||
          Math.abs(Number(after.y) - Number(start.y)) > 0.75) continue
      var imageWidth = Number(after.x) - Number(start.x)
      var imageHeight = Number(start.height) - Math.max(1, bodyPixelSize * 0.3)
      if (!isFinite(imageWidth) || !isFinite(imageHeight) ||
          imageWidth < 2 || imageHeight < 2) continue
      nextRects[index] = {
        index: index,
        x: Number(start.x),
        y: Number(start.y),
        width: imageWidth,
        height: imageHeight,
        sourceStart: Number(model.sourceStart),
        sourceEnd: Number(model.sourceEnd),
        metadataStart: Number(model.metadataStart),
        metadataEnd: Number(model.metadataEnd),
        url: String(model.url || ""),
        alt: String(model.alt || "")
      }
    }
    imageRects = nextRects
    if (selectedImageIndex >= nextRects.length ||
        !nextRects[selectedImageIndex]) selectedImageIndex = -1
    imageGeometryRevision++
  }

  function imageRectangleAt(indexValue) {
    var index = Number(indexValue)
    if (!isFinite(index) || index < 0 || index >= imageRects.length)
      return null
    return imageRects[index] || null
  }

  function selectedImageRectangle() {
    return imageRectangleAt(selectedImageIndex)
  }

  function imageIndexAtPoint(pointX, pointY) {
    var x = Number(pointX)
    var y = Number(pointY)
    if (!isFinite(x) || !isFinite(y)) return -1
    for (var index = imageRects.length - 1; index >= 0; index--) {
      var rect = imageRects[index]
      if (rect && x >= Number(rect.x) &&
          x <= Number(rect.x) + Number(rect.width) &&
          y >= Number(rect.y) && y <= Number(rect.y) + Number(rect.height))
        return index
    }
    return -1
  }

  function rebuildTaskCheckboxRects() {
    if (!layoutMatchesCurrentInput()) {
      taskCheckboxRects = []
      taskCheckboxGeometryRevision++
      return
    }
    var source = String(sourceText || "")
    var taskPattern = /(^|\n)([ \t]*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\][ \t]+)/g
    var match
    var documentSearch = 0
    var nextRects = []
    while ((match = taskPattern.exec(source)) !== null) {
      var sourceStart = Number(match.index) + String(match[1] || "").length
      var contentStart = sourceStart + String(match[2] || "").length
      var checked = String(match[3] || "").toLowerCase() === "x"
      var documentPosition = documentPlainText.indexOf("☐", documentSearch)
      if (documentPosition < 0) break
      documentSearch = documentPosition + 1

      var glyph = documentRectangle(documentPosition)
      var content = cursorRectangleForSource(contentStart)
      if (!glyph || !content) continue
      var size = Math.max(11, Number(taskCheckboxSize) || 11)
      var lineHeight = Math.max(size, Number(content.height) || bodyPixelSize)
      var boxX = Number(glyph.x)
      var boxY = Number(content.y) + (lineHeight - size) / 2
      var hitX = Math.max(horizontalPadding, boxX - 5)
      var hitRight = Math.max(boxX + size + 5, Number(content.x) - 2)
      nextRects.push({
        sourceStart: sourceStart,
        contentStart: contentStart,
        checked: checked,
        x: boxX,
        y: boxY,
        width: size,
        height: size,
        hitX: hitX,
        hitY: Number(content.y) - 4,
        hitWidth: Math.max(size + 10, hitRight - hitX),
        hitHeight: lineHeight + 8
      })
    }
    taskCheckboxRects = nextRects
    taskCheckboxGeometryRevision++
  }

  function taskCheckboxSourceAtPoint(pointX, pointY) {
    var x = Number(pointX)
    var y = Number(pointY)
    if (!isFinite(x) || !isFinite(y)) return -1
    for (var index = taskCheckboxRects.length - 1; index >= 0; index--) {
      var rect = taskCheckboxRects[index]
      if (rect && x >= Number(rect.hitX) &&
          x <= Number(rect.hitX) + Number(rect.hitWidth) &&
          y >= Number(rect.hitY) &&
          y <= Number(rect.hitY) + Number(rect.hitHeight))
        return Number(rect.sourceStart)
    }
    return -1
  }

  function clearImageSelection() {
    if (imageResizeActive) endImageResize(false)
    selectedImageIndex = -1
  }

  function maximumImageWidth(rectangle) {
    var rect = rectangle || selectedImageRectangle()
    return Math.max(48, Number(width) -
      Number(rect && rect.x || horizontalPadding) - horizontalPadding)
  }

  function beginImageResize(cornerValue, pointX, pointY) {
    var rect = selectedImageRectangle()
    var corner = String(cornerValue || "")
    if (!rect || ["topLeft", "topRight", "bottomLeft", "bottomRight"]
        .indexOf(corner) < 0) return false
    imageResizeActive = true
    imageResizeCorner = corner
    imageResizeStartPointerX = Number(pointX) || 0
    imageResizeStartPointerY = Number(pointY) || 0
    imageResizeStartWidth = Number(rect.width)
    imageResizeStartHeight = Number(rect.height)
    previewImageIndex = selectedImageIndex
    previewImageWidth = Math.max(48, Math.round(imageResizeStartWidth))
    pendingImageResizeWidth = previewImageWidth
    return true
  }

  function imageResizeWidthForPoint(pointX, pointY) {
    if (!imageResizeActive) return 0
    var deltaX = (Number(pointX) || 0) - imageResizeStartPointerX
    var deltaY = (Number(pointY) || 0) - imageResizeStartPointerY
    var horizontal = imageResizeCorner.indexOf("Right") >= 0
      ? deltaX : -deltaX
    var aspect = imageResizeStartHeight > 0
      ? imageResizeStartWidth / imageResizeStartHeight : 1
    var vertical = (imageResizeCorner.indexOf("bottom") === 0
      ? deltaY : -deltaY) * aspect
    var delta = Math.abs(deltaX) < 1 ? vertical
      : Math.abs(deltaY) < 1 ? horizontal : (horizontal + vertical) / 2
    return Math.max(48, Math.min(maximumImageWidth(),
      Math.round(imageResizeStartWidth + delta)))
  }

  function requestImageResize(pointX, pointY) {
    if (!imageResizeActive) return false
    pendingImageResizeWidth = imageResizeWidthForPoint(pointX, pointY)
    if (!imageResizeFrameTimer.running) imageResizeFrameTimer.start()
    return true
  }

  function flushImageResizePreview() {
    if (!imageResizeActive || pendingImageResizeWidth <= 0) return false
    var nextWidth = Number(pendingImageResizeWidth)
    if (previewImageWidth === nextWidth) return true
    previewImageWidth = nextWidth
    refreshStyledDocument()
    return true
  }

  function endImageResize(commit) {
    if (!imageResizeActive) return false
    imageResizeFrameTimer.stop()
    flushImageResizePreview()
    var rect = selectedImageRectangle()
    var width = Math.max(48, Math.round(Number(previewImageWidth) || 0))
    imageResizeActive = false
    imageResizeCorner = ""
    pendingImageResizeWidth = 0
    if (commit && rect && width > 0) {
      imageResizeRequested(Number(rect.sourceStart), Number(rect.sourceEnd), width)
      return true
    }
    previewImageIndex = -1
    previewImageWidth = 0
    refreshStyledDocument()
    return false
  }

  function sourcePositionForDocument(documentPosition) {
    if (!layoutMatchesCurrentInput()) return 0
    var position = clampDocumentPosition(documentPosition)
    return clampSourcePosition(documentToSource[position])
  }

  function rawCursorRectangleForSource(sourcePosition) {
    var rectangle = nativeDocument.positionToRectangle(
      documentPositionForSource(sourcePosition))
    if (!rectangle) return null
    return Qt.rect(Number(rectangle.x), Number(rectangle.y),
      Math.max(1, Number(rectangle.width) || 1),
      Math.max(1, Number(rectangle.height) || bodyCaretHeight || bodyPixelSize))
  }

  function trailingWhitespaceRun(sourcePosition) {
    var position = clampSourcePosition(sourcePosition)
    var lineStart = position > 0
      ? sourceText.lastIndexOf("\n", position - 1) + 1 : 0
    var lineEnd = sourceText.indexOf("\n", position)
    if (lineEnd < 0) lineEnd = sourceText.length
    var line = sourceText.slice(lineStart, lineEnd)
    var match = /[ \t]+$/.exec(line)
    if (!match) return null
    var whitespaceStart = lineStart + Number(match.index)
    if (position < whitespaceStart || position > lineEnd) return null
    return {start: whitespaceStart, end: lineEnd}
  }

  function whitespaceAdvance(startPosition, endPosition) {
    var text = sourceText.slice(startPosition, endPosition)
    var columns = 0
    for (var index = 0; index < text.length; index++)
      columns += text.charAt(index) === "\t" ? 4 : 1
    return columns * cursorWidth(" ", fontFamily)
  }

  function tableRowContextForSource(sourcePosition) {
    var position = clampSourcePosition(sourcePosition)
    var regions = Array.isArray(tableSourceRegions) ? tableSourceRegions : []
    var regionLow = 0
    var regionHigh = regions.length - 1
    var region = null
    while (regionLow <= regionHigh) {
      var regionIndex = Math.floor((regionLow + regionHigh) / 2)
      var candidateRegion = regions[regionIndex] || {}
      if (position <= Number(candidateRegion.sourceStart)) {
        regionHigh = regionIndex - 1
      } else if (position >= Number(candidateRegion.sourceEnd)) {
        regionLow = regionIndex + 1
      } else {
        region = candidateRegion
        break
      }
    }
    if (!region || (position >= Number(region.separatorStart) &&
        position <= Number(region.separatorEnd))) return null
    var rows = Array.isArray(region.rows) ? region.rows : []
    var rowLow = 0
    var rowHigh = rows.length - 1
    while (rowLow <= rowHigh) {
      var rowIndex = Math.floor((rowLow + rowHigh) / 2)
      var row = rows[rowIndex] || {}
      if (position < Number(row.lineStart)) rowHigh = rowIndex - 1
      else if (position > Number(row.lineEnd)) rowLow = rowIndex + 1
      else return {region: region, row: row, rowIndex: rowIndex}
    }
    return null
  }

  function tableCellVisibleBounds(spanValue) {
    var span = spanValue || {}
    var start = clampSourcePosition(span.start)
    var end = clampSourcePosition(span.end)
    while (start < end && /[ \t]/.test(sourceText.charAt(start))) start++
    while (end > start && /[ \t]/.test(sourceText.charAt(end - 1))) end--
    return {start: start, end: end}
  }

  function tableCursorRectangleForSource(sourcePosition) {
    var position = clampSourcePosition(sourcePosition)
    var context = tableRowContextForSource(position)
    if (!context) return null
    var row = context.row || {}
    var spans = Array.isArray(row.spans) ? row.spans : []
    if (spans.length === 0) return null
    var anchors = []
    for (var spanIndex = 0; spanIndex < spans.length; spanIndex++) {
      var bounds = tableCellVisibleBounds(spans[spanIndex])
      if (bounds.end <= bounds.start) continue
      if (position >= bounds.start && position <= bounds.end) return null
      var startRectangle = rawCursorRectangleForSource(bounds.start)
      var endRectangle = rawCursorRectangleForSource(bounds.end)
      if (startRectangle)
        anchors.push({source: bounds.start, rectangle: startRectangle})
      if (endRectangle)
        anchors.push({source: bounds.end, rectangle: endRectangle})
    }
    if (anchors.length === 0) return null
    anchors.sort(function(left, right) {
      return Number(left.source) - Number(right.source)
    })

    var first = anchors[0]
    var last = anchors[anchors.length - 1]
    var spaceWidth = cursorWidth(" ", fontFamily)
    anchors.unshift({
      source: Number(row.lineStart),
      rectangle: Qt.rect(Math.max(horizontalPadding,
        Number(first.rectangle.x) - spaceWidth *
          Math.max(1, Number(first.source) - Number(row.lineStart))),
        Number(first.rectangle.y), Number(first.rectangle.width),
        Number(first.rectangle.height))
    })
    anchors.push({
      source: Number(row.lineEnd),
      rectangle: Qt.rect(Number(last.rectangle.x) + spaceWidth *
          Math.max(1, Number(row.lineEnd) - Number(last.source)),
        Number(last.rectangle.y), Number(last.rectangle.width),
        Number(last.rectangle.height))
    })

    var leftAnchor = anchors[0]
    var rightAnchor = anchors[anchors.length - 1]
    for (var anchorIndex = 0; anchorIndex + 1 < anchors.length;
         anchorIndex++) {
      if (position < Number(anchors[anchorIndex].source) ||
          position > Number(anchors[anchorIndex + 1].source)) continue
      leftAnchor = anchors[anchorIndex]
      rightAnchor = anchors[anchorIndex + 1]
      break
    }
    var leftSource = Number(leftAnchor.source)
    var rightSource = Number(rightAnchor.source)
    if (rightSource <= leftSource) return leftAnchor.rectangle
    var ratio = Math.max(0, Math.min(1,
      (position - leftSource) / (rightSource - leftSource)))
    var leftRectangle = leftAnchor.rectangle
    var rightRectangle = rightAnchor.rectangle
    return Qt.rect(
      Number(leftRectangle.x) +
        (Number(rightRectangle.x) - Number(leftRectangle.x)) * ratio,
      Number(leftRectangle.y) +
        (Number(rightRectangle.y) - Number(leftRectangle.y)) * ratio,
      Math.max(1, Number(leftRectangle.width) || 1),
      Math.max(1, Number(leftRectangle.height) || bodyCaretHeight ||
        bodyPixelSize))
  }

  function cursorRectangleForSource(sourcePosition) {
    if (!layoutMatchesCurrentInput()) return null
    var position = clampSourcePosition(sourcePosition)
    var fenceLanguageRectangle = codeLanguageCursorRectangle(position)
    if (fenceLanguageRectangle) return fenceLanguageRectangle
    var tableRectangle = tableCursorRectangleForSource(position)
    if (tableRectangle) return tableRectangle
    var whitespace = trailingWhitespaceRun(position)
    if (!whitespace) return rawCursorRectangleForSource(position)
    var base = rawCursorRectangleForSource(whitespace.start)
    if (!base) return null
    return Qt.rect(Number(base.x) + whitespaceAdvance(
        whitespace.start, position), Number(base.y), Number(base.width),
      Number(base.height))
  }

  function codeLanguageCursorRectangle(sourcePositionValue) {
    var position = clampSourcePosition(sourcePositionValue)
    var blocks = Array.isArray(codeBlocks) ? codeBlocks : []
    for (var index = 0; index < blocks.length; index++) {
      var block = blocks[index] || {}
      var languageStart = clampSourcePosition(block.languageStart)
      var languageEnd = clampSourcePosition(block.languageEnd)
      if (position < languageStart || position > languageEnd) continue
      var projection = codeLanguageProjection(block.language)
      var label = String(projection.label || "")
      if (!label) continue
      var documentStart = Number(sourceToDocument[languageStart])
      if (!isFinite(documentStart) || documentStart < 0) continue
      var base = documentRectangle(documentStart)
      if (!base) continue
      var sourceLength = Math.max(0, languageEnd - languageStart)
      var labelOffset = sourceLength > 0
        ? Math.round((position - languageStart) * label.length / sourceLength)
        : 0
      codeLanguageMetrics.font.bold = !projection.placeholder
      codeLanguageMetrics.font.italic = Boolean(projection.placeholder)
      codeLanguageMetrics.text = label.slice(0, labelOffset)
      return Qt.rect(Number(base.x) + Number(codeLanguageMetrics.advanceWidth),
        Number(base.y), 1, Number(base.height))
    }
    return null
  }

  function followingCursorRectangleForSource(sourcePosition) {
    return cursorRectangleForSource(clampSourcePosition(sourcePosition) + 1)
  }

  function rebuildQuoteRailRects() {
    if (!layoutMatchesCurrentInput() || !syntaxTree) {
      quoteRailRects = []
      quoteRailGeometryRevision++
      return
    }

    var quoteModels = []
    function collectQuotes(node, quoteDepth) {
      if (!node) return
      var type = String(node.type || "")
      var depth = quoteDepth + (type === "blockquote" ? 1 : 0)
      if (type === "blockquote") quoteModels.push({node: node, depth: depth})
      var children = Array.isArray(node.children) ? node.children : []
      for (var index = 0; index < children.length; index++)
        collectQuotes(children[index], depth)
    }
    collectQuotes(syntaxTree, 0)

    var visibleSourceStart = 0
    var visibleSourceEnd = sourceText.length
    if (viewportRenderingEnabled && nativeDocument.length > 0) {
      var viewportTop = Math.max(0,
        Number(viewportY) - Number(viewportOverscan))
      var viewportBottom = Math.max(viewportTop,
        Number(viewportY) + Number(viewportHeight) +
          Number(viewportOverscan))
      var topDocumentPosition = nativeDocument.positionAt(
        horizontalPadding, viewportTop)
      var bottomDocumentPosition = nativeDocument.positionAt(
        horizontalPadding, viewportBottom)
      visibleSourceStart = sourcePositionForDocument(
        Math.min(topDocumentPosition, bottomDocumentPosition))
      visibleSourceEnd = sourcePositionForDocument(
        Math.max(topDocumentPosition, bottomDocumentPosition))
      if (visibleSourceEnd < visibleSourceStart) {
        var visibleSwap = visibleSourceStart
        visibleSourceStart = visibleSourceEnd
        visibleSourceEnd = visibleSwap
      }
    }

    function visibleLeaves(node, quoteDepth, result) {
      if (!node) return
      var type = String(node.type || "")
      var depth = quoteDepth + (type === "blockquote" ? 1 : 0)
      var children = Array.isArray(node.children) ? node.children : []
      if (children.length > 0) {
        for (var index = 0; index < children.length; index++)
          visibleLeaves(children[index], depth, result)
        return
      }
      if (type === "blank" || !node.position || !node.position.start ||
          !node.position.end) return
      var start = Number(node.position.start.offset)
      var end = Number(node.position.end.offset)
      if (!isFinite(start) || !isFinite(end) || end < start) return
      result.push({start: start, end: end, depth: depth})
    }

    var railWidth = Math.max(2, Math.round(bodyPixelSize / 8))
    var levelAdvance = railWidth + Math.max(8,
      Math.round(bodyPixelSize * 0.625))
    var nextRects = []
    for (var quoteIndex = 0; quoteIndex < quoteModels.length; quoteIndex++) {
      var quote = quoteModels[quoteIndex]
      var quotePosition = quote.node.position || {}
      var quoteStart = Number(quotePosition.start &&
        quotePosition.start.offset) || 0
      var quoteEnd = Number(quotePosition.end &&
        quotePosition.end.offset) || quoteStart
      if (viewportRenderingEnabled &&
          (quoteEnd < visibleSourceStart || quoteStart > visibleSourceEnd))
        continue
      var leaves = []
      visibleLeaves(quote.node, quote.depth - 1, leaves)
      if (leaves.length === 0) continue
      var first = leaves[0]
      var last = leaves[leaves.length - 1]
      // Quote endpoints are visible leaf text, so raw document geometry is
      // sufficient and avoids the table-region scan used for editable table
      // delimiters. This keeps notes with hundreds of quotes linear.
      var firstRect = rawCursorRectangleForSource(first.start)
      var lastPosition = last.end > last.start ? last.end - 1 : last.start
      var lastRect = rawCursorRectangleForSource(lastPosition)
      if (!firstRect || !lastRect) continue
      var inheritedLevels = Math.max(1,
        Number(first.depth) - Number(quote.depth) + 1)
      var top = Number(firstRect.y)
      var bottom = Number(lastRect.y) + Math.max(1,
        Number(lastRect.height) || bodyCaretHeight || bodyPixelSize)
      nextRects.push({
        x: Math.max(0, Number(firstRect.x) -
          inheritedLevels * levelAdvance),
        y: top,
        width: railWidth,
        height: Math.max(railWidth, bottom - top),
        depth: Number(quote.depth),
        sourceStart: quoteStart,
        sourceEnd: quoteEnd
      })
    }
    quoteRailRects = nextRects
    quoteRailGeometryRevision++
  }

  function tableSourcePositionForPoint(nativeSourcePosition, pointX, pointY) {
    var context = tableRowContextForSource(nativeSourcePosition)
    if (!context) return -1
    var row = context.row || {}
    var spans = Array.isArray(row.spans) ? row.spans : []
    var bounds = []
    for (var spanIndex = 0; spanIndex < spans.length; spanIndex++) {
      var visible = tableCellVisibleBounds(spans[spanIndex])
      if (visible.end > visible.start) bounds.push(visible)
    }
    if (bounds.length === 0) return -1
    var hiddenRanges = []
    for (var boundsIndex = 0; boundsIndex + 1 < bounds.length;
         boundsIndex++) {
      hiddenRanges.push({start: Number(bounds[boundsIndex].end),
        end: Number(bounds[boundsIndex + 1].start)})
    }

    for (var rangeIndex = 0; rangeIndex < hiddenRanges.length;
         rangeIndex++) {
      var range = hiddenRanges[rangeIndex]
      if (range.end <= range.start) continue
      var leftRectangle = cursorRectangleForSource(range.start)
      var rightRectangle = cursorRectangleForSource(range.end)
      if (!leftRectangle || !rightRectangle) continue
      var top = Math.min(Number(leftRectangle.y),
        Number(rightRectangle.y))
      var bottom = Math.max(Number(leftRectangle.y) +
          Number(leftRectangle.height), Number(rightRectangle.y) +
          Number(rightRectangle.height))
      if (pointY < top || pointY > bottom) continue
      var leftX = Number(leftRectangle.x)
      var rightX = Number(rightRectangle.x)
      var minimumX = Math.min(leftX, rightX)
      var maximumX = Math.max(leftX, rightX)
      if (pointX < minimumX || pointX > maximumX) continue
      if (Math.abs(rightX - leftX) < 0.5) return range.start
      var ratio = Math.max(0, Math.min(1,
        (pointX - leftX) / (rightX - leftX)))
      return clampSourcePosition(Math.round(range.start +
        ratio * (range.end - range.start)))
    }
    return -1
  }

  function sourcePositionForPoint(localX, localY) {
    if (!layoutMatchesCurrentInput()) return 0
    var pointX = Number(localX) || 0
    var pointY = Number(localY) || 0
    var documentPosition = nativeDocument.positionAt(
      pointX, pointY)
    var nativeSourcePosition = sourcePositionForDocument(documentPosition)
    var tableSourcePosition = tableSourcePositionForPoint(
      nativeSourcePosition, pointX, pointY)
    if (tableSourcePosition >= 0) return tableSourcePosition
    // A synthetic blank row is one zero-width document character. Qt places
    // a point on that row after the marker, whose reverse mapping belongs to
    // the following block. Recover only a measured adjacent blank source row
    // so clicks and vertical navigation can actually enter it.
    var blankSourcePosition = blankLineSourcePositionForPoint(
      nativeSourcePosition, pointY)
    if (blankSourcePosition >= 0) return blankSourcePosition
    // Qt already resolved the visual row. Only inspect that source line for
    // synthetic trailing columns; scanning the whole note here makes pointer
    // movement quadratic on large documents.
    var line = sourceLineSelectionRange(nativeSourcePosition)
    var lineText = sourceText.slice(line.start, line.end)
    var match = /[ \t]+$/.exec(lineText)
    if (!match) return nativeSourcePosition
    var whitespaceStart = line.start + Number(match.index)
    var base = rawCursorRectangleForSource(whitespaceStart)
    if (!base || pointY < Number(base.y) ||
        pointY > Number(base.y) + Number(base.height))
      return nativeSourcePosition
    var previousX = Number(base.x)
    for (var position = whitespaceStart; position < line.end; position++) {
      var nextX = Number(base.x) + whitespaceAdvance(
        whitespaceStart, position + 1)
      if (pointX < (previousX + nextX) / 2) return position
      previousX = nextX
    }
    return pointX <= previousX + cursorWidth(" ", fontFamily) / 2
      ? line.end : nativeSourcePosition
  }

  function blankLineSourcePositionForPoint(nativeSourcePositionValue,
      pointYValue) {
    var source = String(sourceText || "")
    var nativePosition = clampSourcePosition(nativeSourcePositionValue)
    var currentStart = nativePosition > 0
      ? source.lastIndexOf("\n", nativePosition - 1) + 1 : 0
    var candidates = [currentStart]
    if (currentStart > 0) {
      var previousEnd = currentStart - 1
      candidates.push(previousEnd > 0
        ? source.lastIndexOf("\n", previousEnd - 1) + 1 : 0)
    }
    var currentEnd = source.indexOf("\n", currentStart)
    if (currentEnd >= 0 && currentEnd < source.length)
      candidates.push(currentEnd + 1)

    var pointY = Number(pointYValue) || 0
    for (var index = 0; index < candidates.length; index++) {
      var candidateStart = Math.max(0, Math.min(source.length,
        Number(candidates[index]) || 0))
      var candidateEnd = source.indexOf("\n", candidateStart)
      if (candidateEnd < 0) candidateEnd = source.length
      var candidateText = source.slice(candidateStart, candidateEnd)
      // Whitespace-bearing rows retain their normal column-aware hit path,
      // including whitespace-only lines inside fenced code.
      if (candidateText !== "" && candidateText !== "\r") continue
      var rectangle = rawCursorRectangleForSource(candidateStart)
      if (!rectangle || pointY < Number(rectangle.y) ||
          pointY > Number(rectangle.y) + Number(rectangle.height)) continue
      return candidateStart
    }
    return -1
  }

  function appendRangeRectangle(rectangles, rectangle, nextRectangle,
      minimumWidth) {
    if (!rectangle) return
    var x = Number(rectangle.x)
    var y = Number(rectangle.y)
    var height = Math.max(1, Number(rectangle.height) || bodyPixelSize)
    var sameLine = nextRectangle &&
      Math.abs(Number(nextRectangle.y) - y) < 0.75 &&
      Number(nextRectangle.x) >= x
    var fallbackWidth = Math.max(2, Number(minimumWidth) || 0,
      Number(rectangle.width) || cursorWidth("x", fontFamily))
    var width = sameLine ? Number(nextRectangle.x) - x : fallbackWidth
    if (width <= 0) width = fallbackWidth
    var previous = rectangles.length > 0
      ? rectangles[rectangles.length - 1] : null
    if (previous && Math.abs(Number(previous.y) - y) < 0.75 &&
        x <= Number(previous.x) + Number(previous.width) + 1) {
      previous.width = Math.max(Number(previous.width),
        x + width - Number(previous.x))
      return
    }
    rectangles.push({x: x, y: y, width: width, height: height,
      underlineY: y + height - 1})
  }

  function sourceRangeRectangles(startValue, endValue) {
    if (!layoutMatchesCurrentInput()) return []
    var sourceStart = clampSourcePosition(Math.min(
      Number(startValue) || 0, Number(endValue) || 0))
    var sourceEnd = clampSourcePosition(Math.max(
      Number(startValue) || 0, Number(endValue) || 0))
    if (sourceEnd <= sourceStart) return []
    var rectangles = []
    for (var position = sourceStart; position < sourceEnd; position++) {
      var rectangle = cursorRectangleForSource(position)
      var nextRectangle = cursorRectangleForSource(position + 1)
      var sourceCharacter = sourceText.charAt(position)
      var minimumWidth = sourceCharacter === "\n" || sourceCharacter === "\r"
        ? cursorWidth(" ", fontFamily) : 0
      appendRangeRectangle(rectangles, rectangle, nextRectangle, minimumWidth)
    }
    return rectangles
  }

  function viewportSourceRange() {
    if (!layoutMatchesCurrentInput() || !viewportRenderingEnabled ||
        nativeDocument.length <= 0)
      return {start: 0, end: sourceText.length}
    var viewportTop = Math.max(0,
      Number(viewportY) - Number(viewportOverscan))
    var viewportBottom = Math.max(viewportTop,
      Number(viewportY) + Number(viewportHeight) +
        Number(viewportOverscan))
    var topDocumentPosition = nativeDocument.positionAt(
      horizontalPadding, viewportTop)
    var bottomDocumentPosition = nativeDocument.positionAt(
      horizontalPadding, viewportBottom)
    var start = sourcePositionForDocument(Math.min(
      topDocumentPosition, bottomDocumentPosition))
    var end = sourcePositionForDocument(Math.max(
      topDocumentPosition, bottomDocumentPosition))
    var startLine = sourceLineSelectionRange(start)
    var endLine = sourceLineSelectionRange(end)
    return {
      start: Math.max(0, Number(startLine.start) || 0),
      end: Math.min(sourceText.length,
        Math.max(Number(endLine.end) || 0, end) +
          (Number(endLine.end) < sourceText.length ? 1 : 0))
    }
  }

  function selectionRangeRectangles() {
    if (!selectionRenderingEnabled) {
      nativeDocument.deselect()
      nativeSelectAllActive = false
      selectionGeometrySourceStart = 0
      selectionGeometrySourceEnd = 0
      return []
    }
    var start = clampSourcePosition(Math.min(selectionStart, selectionEnd))
    var end = clampSourcePosition(Math.max(selectionStart, selectionEnd))
    if (sourceText.length > 0 && start === 0 && end === sourceText.length) {
      // Ctrl+A maps to the complete native document, so let QTextEdit paint
      // that selection in C++ instead of asking QML for one rectangle per
      // source character. Copy/cut still operate on the hidden source editor.
      nativeDocument.select(0, nativeDocument.length)
      nativeSelectAllActive = true
      selectionGeometrySourceStart = 0
      selectionGeometrySourceEnd = 0
      return []
    }
    if (nativeSelectAllActive) nativeDocument.deselect()
    nativeSelectAllActive = false
    if (viewportRenderingEnabled) {
      var visible = viewportSourceRange()
      start = Math.max(start, Number(visible.start) || 0)
      end = Math.min(end, Number(visible.end) || 0)
    }
    selectionGeometrySourceStart = start
    selectionGeometrySourceEnd = Math.max(start, end)
    return sourceRangeRectangles(start, end)
  }

  function rebuildSelectionRects() {
    selectionRects = selectionRangeRectangles()
    selectionTargets = selectionRects
    selectionRevision++
  }

  function verticalNavigationTarget(sourcePosition, preferredX, direction) {
    var current = cursorRectangleForSource(sourcePosition)
    if (!current || Number(direction) === 0) return -1
    var step = Math.max(bodyPixelSize,
      Number(current.height) || bodyPixelSize)
    for (var attempt = 1; attempt <= 4; attempt++) {
      var candidate = sourcePositionForPoint(
        Number(preferredX) || Number(current.x),
        Number(current.y) + Number(direction) * step * attempt +
          Number(current.height) / 2)
      if (candidate !== clampSourcePosition(sourcePosition)) return candidate
    }
    return -1
  }

  function topLevelNodeForSource(sourcePosition) {
    var children = syntaxTree && Array.isArray(syntaxTree.children)
      ? syntaxTree.children : []
    var position = clampSourcePosition(sourcePosition)
    for (var index = 0; index < children.length; index++) {
      var node = children[index]
      if (!node.position || !node.position.start || !node.position.end) continue
      if (position >= Number(node.position.start.offset) &&
          position <= Number(node.position.end.offset)) return node
    }
    return null
  }

  function cursorTargetForSource(sourcePosition) {
    var node = topLevelNodeForSource(sourcePosition)
    return {blockType: node ? String(node.type || "none") : "none",
      blockIndex: node && syntaxTree.children
        ? syntaxTree.children.indexOf(node) : -1, itemIndex: -1}
  }

  function previousBlockBottomForSource(sourceStartValue) {
    if (!layoutMatchesCurrentInput()) return -1
    var children = syntaxTree && Array.isArray(syntaxTree.children)
      ? syntaxTree.children : []
    var target = Number(sourceStartValue)
    if (!isFinite(target) || target < 0) return -1
    for (var index = 0; index < children.length; index++) {
      var node = children[index] || {}
      var position = node.position || {}
      var start = position.start || {}
      if (Number(start.offset) !== target) continue
      for (var previousIndex = index - 1; previousIndex >= 0;
           previousIndex--) {
        var previous = children[previousIndex] || {}
        var previousPosition = previous.position || {}
        var previousEnd = previousPosition.end || {}
        var endOffset = Number(previousEnd.offset)
        if (!isFinite(endOffset)) continue
        var rectangle = cursorRectangleForSource(Math.max(0, endOffset - 1))
        if (rectangle) return Number(rectangle.y) + Number(rectangle.height)
      }
      return verticalPadding
    }
    return -1
  }

  function layoutMetricsForTests() {
    var result = []
    var children = syntaxTree && Array.isArray(syntaxTree.children)
      ? syntaxTree.children : []
    for (var index = 0; index < children.length; index++) {
      var node = children[index]
      if (!node.position || !node.position.start || !node.position.end) continue
      var start = Number(node.position.start.offset)
      var end = Number(node.position.end.offset)
      var first = cursorRectangleForSource(start)
      var last = cursorRectangleForSource(end > start ? end - 1 : end)
      result.push({type: String(node.type || ""), sourceStart: start,
        sourceEnd: end, y: first ? Number(first.y) : -1,
        height: first && last
          ? Number(last.y) + Number(last.height) - Number(first.y) : -1,
        contentActive: true})
    }
    return result
  }

  function cursorWidth(value, family) {
    return Math.max(1, String(value || "x").length * bodyPixelSize * 0.58)
  }

  function wordRangeAt(sourcePosition) {
    var position = clampSourcePosition(sourcePosition)
    var start = position
    var end = position
    while (start > 0 && /[A-Za-z0-9_\u00c0-\u024f'-]/.test(
        sourceText.charAt(start - 1)))
      start--
    while (end < sourceText.length &&
        /[A-Za-z0-9_\u00c0-\u024f'-]/.test(sourceText.charAt(end))) end++
    return {start: start, end: end}
  }

  function sourceLineSelectionRange(sourcePosition) {
    var position = clampSourcePosition(sourcePosition)
    var start = position > 0
      ? sourceText.lastIndexOf("\n", position - 1) + 1 : 0
    var end = sourceText.indexOf("\n", position)
    if (end < 0) end = sourceText.length
    return {start: start, end: end}
  }

  function mouseClickKeyForSourcePosition(sourcePosition) {
    var line = sourceLineSelectionRange(sourcePosition)
    var word = wordRangeAt(sourcePosition)
    var wordStart = word.end > word.start ? word.start : sourcePosition
    var wordEnd = word.end > word.start ? word.end : sourcePosition
    return [line.start, line.end, wordStart, wordEnd].join(":")
  }

  function registerRenderedMousePress(sourcePosition) {
    var now = Date.now()
    var key = mouseClickKeyForSourcePosition(sourcePosition)
    var sameSequence = key === mouseClickKey &&
      now - Number(mouseClickTimestamp) <= mouseDoubleClickInterval
    mouseClickCount = sameSequence ? Math.min(3, mouseClickCount + 1) : 1
    mouseClickKey = key
    mouseClickTimestamp = now
    mouseClickResetTimer.restart()
    return mouseClickCount
  }

  function beginMouseSelection() {
    mouseSelectionFrameTimer.stop()
    mouseSelectionUpdatePending = false
    mouseSelectionActive = true
  }

  function requestMouseSelection(pointX, pointY) {
    if (!mouseSelectionActive || mouseSelectionAnchor < 0) return
    pendingMouseSelectionX = Number(pointX) || 0
    pendingMouseSelectionY = Number(pointY) || 0
    mouseSelectionUpdatePending = true
    if (!mouseSelectionFrameTimer.running) mouseSelectionFrameTimer.start()
  }

  function flushMouseSelection() {
    if (!mouseSelectionUpdatePending || mouseSelectionAnchor < 0) return false
    mouseSelectionUpdatePending = false
    sourceSelectionRequested(mouseSelectionAnchor,
      sourcePositionForPoint(pendingMouseSelectionX, pendingMouseSelectionY))
    return true
  }

  function endMouseSelection() {
    if (!mouseSelectionActive) return
    mouseSelectionFrameTimer.stop()
    flushMouseSelection()
    mouseSelectionActive = false
  }

  function linkSourceUrl(value) {
    var raw = String(value || "").trim()
    if (!raw || raw.charAt(0) === "#") return raw
    if (raw.indexOf("~/") === 0 && String(homePath || ""))
      raw = String(homePath).replace(/\/+$/, "") + raw.slice(1)
    if (/^\/\//.test(raw)) raw = "https:" + raw
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) return encodeURI(raw)
    if (raw.charAt(0) === "/") return "file://" + encodeURI(raw)
    var base = String(baseUrl || "")
    if (base) {
      if (base.charAt(base.length - 1) !== "/") base += "/"
      return base + encodeURI(raw)
    }
    return encodeURI(raw)
  }

  function linkTargetForPoint(localX, localY) {
    if (!layoutMatchesCurrentInput()) return ""
    var x = Number(localX)
    var y = Number(localY)
    if (!isFinite(x) || !isFinite(y)) return ""
    // Query the painted anchor, never the nearest source caret. Qt's
    // QQuickTextEdit::linkAt adds (topPadding, leftPadding) to its input;
    // positionToRectangle also includes the item's (leftPadding, topPadding).
    // Undo both translations. Independent HTML-layout tests cover zero and
    // asymmetric padding, wrapped labels, formatting and reference links.
    // https://github.com/qt/qtdeclarative/blob/dev/src/quick/items/qquicktextedit.cpp
    return linkSourceUrl(String(nativeDocument.linkAt(
      x - nativeDocument.leftPadding - nativeDocument.topPadding,
      y - nativeDocument.topPadding - nativeDocument.leftPadding) || ""))
  }

  function taskSourceAtPoint(localX, localY, sourcePosition) {
    var renderedTask = taskCheckboxSourceAtPoint(localX, localY)
    if (renderedTask >= 0) return renderedTask
    var anchor = clampSourcePosition(sourcePosition)
    var lineStart = sourceText.lastIndexOf("\n", Math.max(0, anchor - 1)) + 1
    var lineEnd = sourceText.indexOf("\n", anchor)
    if (lineEnd < 0) lineEnd = sourceText.length
    var line = sourceText.slice(lineStart, lineEnd)
    var task = /^(\s*)([-+*]|\d+[.)])([ \t]+)\[([ xX])\]([ \t]+)/.exec(line)
    if (!task) return -1
    var contentStart = lineStart + task[0].length
    var textRectangle = cursorRectangleForSource(contentStart)
    if (!textRectangle) return -1
    var markerRight = Number(textRectangle.x) + 2
    var markerLeft = Math.max(horizontalPadding,
      Number(textRectangle.x) - Math.max(28, bodyPixelSize * 2.25))
    var markerTop = Number(textRectangle.y) - 2
    var markerBottom = Number(textRectangle.y) +
      Math.max(bodyPixelSize, Number(textRectangle.height)) + 2
    return Number(localX) >= markerLeft && Number(localX) <= markerRight &&
        Number(localY) >= markerTop && Number(localY) <= markerBottom
      ? lineStart : -1
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
  }

  TextMetrics {
    id: codeLanguageMetrics
    font.family: root.fontFamily
    font.pixelSize: Math.max(1, Math.round(root.bodyPixelSize * 0.8))
  }

  TextEdit {
    id: nativeDocument
    z: 1
    width: root.width
    height: Math.max(contentHeight, root.height)
    readOnly: true
    activeFocusOnPress: false
    selectByMouse: false
    persistentSelection: true
    textFormat: TextEdit.RichText
    wrapMode: TextEdit.Wrap
    color: root.foreground
    selectionColor: root.selectionFill
    selectedTextColor: root.foreground
    baseUrl: root.baseUrl
    font.family: root.fontFamily
    font.pixelSize: root.bodyPixelSize
    leftPadding: root.horizontalPadding
    rightPadding: root.horizontalPadding
    topPadding: root.verticalPadding
    bottomPadding: root.verticalPadding
    onContentHeightChanged: if (root.layoutReady) {
      imageGeometryTimer.restart()
      taskCheckboxGeometryTimer.restart()
    }
  }

  Repeater {
    model: root.selectionRects
    delegate: Rectangle {
      z: 0
      x: Number(modelData.x) || 0
      y: Number(modelData.y) || 0
      width: Math.max(1, Number(modelData.width) || 1)
      height: Math.max(1, Number(modelData.height) || 1)
      color: root.selectionFill
    }
  }

  Repeater {
    model: root.quoteRailRects
    delegate: Rectangle {
      z: 0
      x: Number(modelData.x) || 0
      y: Number(modelData.y) || 0
      width: Math.max(2, Number(modelData.width) || 2)
      height: Math.max(2, Number(modelData.height) || 2)
      color: Qt.rgba(root.foreground.r, root.foreground.g,
        root.foreground.b, 0.35)
    }
  }

  Repeater {
    model: root.taskCheckboxRects
    delegate: Rectangle {
      z: 2
      x: Number(modelData.x) || 0
      y: Number(modelData.y) || 0
      width: Math.max(11, Number(modelData.width) || 11)
      height: Math.max(11, Number(modelData.height) || 11)
      radius: Math.max(2, Math.round(width * 0.16))
      color: Boolean(modelData.checked) ? root.accent : "transparent"
      border.width: Math.max(1, root.bodyPixelSize / 12)
      border.color: Boolean(modelData.checked) ? root.accent
        : Qt.rgba(root.foreground.r, root.foreground.g,
            root.foreground.b, 0.72)

      Text {
        anchors.centerIn: parent
        visible: Boolean(modelData.checked)
        text: "✓"
        color: Qt.rgba(1, 1, 1, 0.96)
        font.family: root.fontFamily
        font.pixelSize: Math.max(10, root.bodyPixelSize * 0.75)
        font.bold: true
      }
    }
  }

  // QTextDocument exposes no per-image failure status to QML and otherwise
  // paints its generic broken-file icon. Probe the same resolved URLs with
  // QQuickImage, then render either the native image or a textual fallback.
  Repeater {
    model: root.images
    delegate: Image {
      required property int index
      required property var modelData
      readonly property int ownerRequestId: root.parseRequestId
      readonly property string ownerUrl: String(modelData &&
        modelData.url || "")
      readonly property string cachedState:
        root.cachedImageLoadState(ownerUrl)
      visible: false
      asynchronous: true
      cache: true
      source: cachedState ? "" : root.linkSourceUrl(ownerUrl)

      function reportStatus() {
        var state = cachedState || (status === Image.Ready ? "ready"
          : status === Image.Error ? "error" : "loading")
        root.setImageLoadState(index, ownerRequestId, ownerUrl, state)
      }

      onStatusChanged: reportStatus()
      onOwnerRequestIdChanged: reportStatus()
      onOwnerUrlChanged: reportStatus()
      onCachedStateChanged: reportStatus()
      Component.onCompleted: reportStatus()
    }
  }

  Rectangle {
    id: imageSelectionFrame
    readonly property var geometry: root.selectedImageRectangle()
    z: 3
    visible: geometry !== null && geometry !== undefined
    x: visible ? Number(geometry.x) : 0
    y: visible ? Number(geometry.y) : 0
    width: visible ? Math.max(1, Number(geometry.width)) : 1
    height: visible ? Math.max(1, Number(geometry.height)) : 1
    color: "transparent"
    border.width: Math.max(1, root.bodyPixelSize / 12)
    border.color: root.accent

    Repeater {
      model: [
        {name: "topLeft", left: true, top: true},
        {name: "topRight", left: false, top: true},
        {name: "bottomLeft", left: true, top: false},
        {name: "bottomRight", left: false, top: false}
      ]

      delegate: Rectangle {
        required property var modelData
        width: root.imageHandleSize
        height: root.imageHandleSize
        radius: Math.max(1, width * 0.16)
        x: modelData.left ? -width / 2 : imageSelectionFrame.width - width / 2
        y: modelData.top ? -height / 2 : imageSelectionFrame.height - height / 2
        color: root.surfaceBackground
        border.width: Math.max(1, root.bodyPixelSize / 10)
        border.color: root.accent

        MouseArea {
          id: resizeHandleArea
          anchors.fill: parent
          anchors.margins: -Math.max(2, root.imageHandleSize * 0.35)
          acceptedButtons: Qt.LeftButton
          cursorShape: modelData.name === "topLeft" ||
              modelData.name === "bottomRight"
            ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

          onPressed: function(mouse) {
            var point = resizeHandleArea.mapToItem(root, mouse.x, mouse.y)
            root.beginImageResize(modelData.name, point.x, point.y)
            mouse.accepted = true
          }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            var point = resizeHandleArea.mapToItem(root, mouse.x, mouse.y)
            root.requestImageResize(point.x, point.y)
          }
          onReleased: function(mouse) {
            var point = resizeHandleArea.mapToItem(root, mouse.x, mouse.y)
            root.requestImageResize(point.x, point.y)
            root.endImageResize(true)
            mouse.accepted = true
          }
          onCanceled: root.endImageResize(false)
        }
      }
    }
  }

  MouseArea {
    id: pointerArea
    z: 2
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: {
      if (root.taskCheckboxSourceAtPoint(mouseX, mouseY) >= 0)
        return Qt.PointingHandCursor
      return root.linkTargetForPoint(mouseX, mouseY)
        ? Qt.PointingHandCursor : Qt.IBeamCursor
    }

    onPressed: function(mouse) {
      root.pendingLinkActivationTarget = ""
      root.pendingLinkPressMoved = false
      if (mouse.modifiers & Qt.ControlModifier) {
        var pressedTarget = root.linkTargetForPoint(mouse.x, mouse.y)
        if (pressedTarget) {
          root.pendingLinkActivationTarget = pressedTarget
          root.pendingLinkPressX = mouse.x
          root.pendingLinkPressY = mouse.y
          root.mouseSelectionAnchor = -1
          mouse.accepted = true
          return
        }
      }
      var imageIndex = root.imageIndexAtPoint(mouse.x, mouse.y)
      if (imageIndex >= 0) {
        root.selectedImageIndex = imageIndex
        var image = imageIndex < root.images.length
          ? root.images[imageIndex] : null
        if (image) root.sourcePositionRequested(Number(image.sourceStart) || 0)
        root.mouseSelectionAnchor = -1
        mouse.accepted = true
        return
      }
      root.clearImageSelection()
      var renderedTaskSource = root.taskCheckboxSourceAtPoint(mouse.x, mouse.y)
      if (renderedTaskSource >= 0) {
        root.taskToggled(renderedTaskSource)
        root.mouseSelectionAnchor = -1
        mouse.accepted = true
        return
      }
      var position = root.sourcePositionForPoint(mouse.x, mouse.y)
      var taskSource = root.taskSourceAtPoint(mouse.x, mouse.y, position)
      if (taskSource >= 0) {
        root.taskToggled(taskSource)
        root.mouseSelectionAnchor = -1
        mouse.accepted = true
        return
      }
      root.mouseSelectionAnchor = position
      root.beginMouseSelection()
      if (mouse.modifiers & Qt.ShiftModifier)
        root.sourceSelectionRequested(root.selectionStart, position)
      else {
        root.sourcePositionRequested(position)
        if (root.registerRenderedMousePress(position) >= 3) {
          var line = root.sourceLineSelectionRange(position)
          root.sourceSelectionRequested(line.start, line.end)
        }
      }
      mouse.accepted = true
    }

    onPositionChanged: function(mouse) {
      if (root.pendingLinkActivationTarget) {
        var deltaX = Number(mouse.x) - root.pendingLinkPressX
        var deltaY = Number(mouse.y) - root.pendingLinkPressY
        if (Math.sqrt(deltaX * deltaX + deltaY * deltaY) >
            root.linkActivationDragThreshold)
          root.pendingLinkPressMoved = true
        return
      }
      if (!(mouse.buttons & Qt.LeftButton) || root.mouseSelectionAnchor < 0) return
      root.requestMouseSelection(mouse.x, mouse.y)
    }

    onReleased: function(mouse) {
      var pendingTarget = root.pendingLinkActivationTarget
      root.pendingLinkActivationTarget = ""
      if (pendingTarget && !root.pendingLinkPressMoved &&
          (mouse.modifiers & Qt.ControlModifier)) {
        if (root.linkTargetForPoint(mouse.x, mouse.y) === pendingTarget)
          root.linkActivated(pendingTarget)
      }
      root.pendingLinkPressMoved = false
      root.endMouseSelection()
      root.mouseSelectionAnchor = -1
    }

    onCanceled: {
      root.pendingLinkActivationTarget = ""
      root.pendingLinkPressMoved = false
      root.endMouseSelection()
      root.mouseSelectionAnchor = -1
    }

    onDoubleClicked: function(mouse) {
      if (root.mouseClickCount >= 3) return
      var range = root.wordRangeAt(
        root.sourcePositionForPoint(mouse.x, mouse.y))
      root.sourceSelectionRequested(range.start, range.end)
    }
  }

  // Some compositors intentionally hide the native pointer after any key
  // press. Keep the Ctrl+click target visible inside JotPin without depending
  // on compositor cursor policy or changing system-wide settings.
  Item {
    id: linkPointerMarker
    z: 3
    enabled: false
    visible: root.linkPointerMarkerVisible
    width: Math.max(14, Math.round(root.bodyPixelSize * 0.9))
    height: width
    x: Math.max(0, Math.min(root.width - width,
      pointerArea.mouseX - width / 2))
    y: Math.max(0, Math.min(root.height - height,
      pointerArea.mouseY - height / 2))

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: root.surfaceBackground
      border.width: Math.max(2, Math.round(width * 0.14))
      border.color: root.accent
    }

    Rectangle {
      anchors.centerIn: parent
      width: Math.max(3, Math.round(parent.width * 0.22))
      height: width
      radius: width / 2
      color: root.accent
    }
  }

  WorkerScript {
    id: parserWorker
    source: Qt.resolvedUrl("markdown/MarkdownParserWorker.js")
    onReadyChanged: if (ready && root.parsePending) {
      if (!root.syntaxTree) root.dispatchParse()
      else root.scheduleDeferredParse()
    }
    onMessage: function(message) {
      root.parseInFlight = false
      root.parseCompletionCount++
      if (String(message.key || "") !== String(root.parseRequestId)) {
        root.parsePending = true
        if (root.immediateParseRequested) {
          parseDelayTimer.stop()
          root.dispatchParse()
        }
        else if (root.interactiveEditsEnabled) root.scheduleDeferredParse()
        else root.dispatchParse()
        return
      }
      if (String(message.type || "") === "parseError") {
        console.error("Native Markdown parse failed: " +
          String(message.message || "unknown error"))
        return
      }
      if (String(message.type || "") !== "parsed") return
      root.immediateParseRequested = false
      var projectedCurrent = root.layoutReady &&
        root.documentSourceText === String(root.sourceText || "") &&
        root.layoutSourceText === String(root.sourceText || "")
      root.syntaxTree = message.tree
      root.renderedHtml = String(message.html || "")
      root.codeBlocks = Array.isArray(message.codeBlocks)
        ? message.codeBlocks : []
      // A current optimistic projection remains the interactive document until
      // input has been idle long enough to replace it and its mappings as one
      // operation. Clearing readiness here lets a repeat event land between
      // the authoritative repaint and mapping rebuild.
      if (!projectedCurrent) root.layoutReady = false
      var parsedImages = Array.isArray(message.images) ? message.images : []
      root.imageLoadStates = new Array(parsedImages.length)
      for (var imageIndex = 0; imageIndex < parsedImages.length; imageIndex++) {
        var parsedImage = parsedImages[imageIndex] || {}
        root.imageLoadStates[imageIndex] =
          root.cachedImageLoadState(parsedImage.url) || "loading"
      }
      root.images = parsedImages
      if (!root.imageResizeActive && root.previewImageIndex >= 0) {
        var previewModel = root.previewImageIndex < root.images.length
          ? root.images[root.previewImageIndex] : null
        if (!previewModel || Number(previewModel.width) ===
            Number(root.previewImageWidth)) {
          root.previewImageIndex = -1
          root.previewImageWidth = 0
        }
      }
      root.codeHighlightResults = new Array(root.codeBlocks.length)
      root.documentSourceText = String(root.sourceText || "")
      root.dispatchCodeHighlights()
      if (root.codeBlocks.length === 0) {
        if (projectedCurrent)
          root.scheduleStyledReconcile(root.parseRequestId)
        else if (root.refreshStyledDocument()) root.settleCurrentDocument()
      }
    }
  }

  Timer {
    id: parseDelayTimer
    interval: root.parseIdleDelayMs
    repeat: false
    onTriggered: root.dispatchParse()
  }

  Timer {
    id: styledReconcileTimer
    interval: Math.max(60, root.parseIdleDelayMs)
    repeat: false
    onTriggered: root.reconcileProjectedDocument()
  }

  Timer {
    id: mouseSelectionFrameTimer
    interval: 8
    repeat: false
    onTriggered: root.flushMouseSelection()
  }

  Timer {
    id: mouseClickResetTimer
    interval: root.mouseDoubleClickInterval
    repeat: false
    onTriggered: {
      root.mouseClickCount = 0
      root.mouseClickKey = ""
    }
  }

  Timer {
    id: imageResizeFrameTimer
    interval: 16
    repeat: false
    onTriggered: root.flushImageResizePreview()
  }

  Timer {
    id: imageGeometryTimer
    interval: 0
    repeat: false
    onTriggered: root.rebuildImageRects()
  }

  Timer {
    id: quoteGeometryTimer
    interval: 0
    repeat: false
    onTriggered: root.rebuildQuoteRailRects()
  }

  Timer {
    id: selectionGeometryTimer
    interval: 0
    repeat: false
    onTriggered: root.rebuildSelectionRects()
  }

  Timer {
    id: taskCheckboxGeometryTimer
    interval: 0
    repeat: false
    onTriggered: root.rebuildTaskCheckboxRects()
  }

  WorkerScript {
    id: codeHighlightWorker
    source: Qt.resolvedUrl("syntax/HighlightWorker.js")
    onReadyChanged: if (ready && root.codeHighlightDispatchPending)
      root.dispatchCodeHighlights()
    onMessage: function(message) {
      if (String(message.type || "") !== "highlighted") return
      var key = String(message.key || "")
      var separator = key.indexOf(":")
      if (separator < 0 || key.slice(0, separator) !==
          String(root.parseRequestId)) return
      var index = Number(key.slice(separator + 1))
      if (!isFinite(index) || index < 0 || index >= root.codeBlocks.length ||
          root.codeHighlightResults[index] !== undefined) return
      var results = root.codeHighlightResults.slice()
      results[index] = String(message.markup || "")
      root.codeHighlightResults = results
      root.codeHighlightPendingCount = Math.max(0,
        root.codeHighlightPendingCount - 1)
      if (root.codeHighlightPendingCount === 0) {
        var projectedCurrent = root.layoutReady &&
          root.documentSourceText === String(root.sourceText || "") &&
          root.layoutSourceText === String(root.sourceText || "")
        if (projectedCurrent)
          root.scheduleStyledReconcile(root.parseRequestId)
        else {
          root.refreshStyledDocument()
          root.settleCurrentDocument()
        }
      }
    }
  }

  Timer {
    id: tableToolbarLayoutTimer
    interval: 0
    repeat: false
    onTriggered: {
      if (!root.renderedHtml) return
      if (root.refreshStyledDocument()) {
        root.layoutReady = false
        root.settleCurrentDocument()
      }
    }
  }

  Timer {
    id: settleTimer
    property int requestId: -1
    property int attempts: 0
    interval: 0
    repeat: false
    onTriggered: {
      if (requestId !== root.parseRequestId) return
      attempts++
      if (root.sourceText.length > 0 && nativeDocument.length === 0 &&
          attempts < 8) {
        interval = 8
        restart()
        return
      }
      interval = 0
      root.rebuildMappings(requestId)
    }
  }

  onSourceTextChanged: requestLayout()
  onCursorPositionChanged: {
    layoutCursorPosition = clampSourcePosition(cursorPosition)
    if (layoutReady) layoutUpdated()
  }
  onSelectionStartChanged: selectionGeometryTimer.restart()
  onSelectionEndChanged: selectionGeometryTimer.restart()
  onSelectionRenderingEnabledChanged: selectionGeometryTimer.restart()
  onTableToolbarSourceStartChanged: tableToolbarLayoutTimer.restart()
  onTableToolbarGapChanged: tableToolbarLayoutTimer.restart()
  onViewportYChanged: if (layoutReady) {
    quoteGeometryTimer.restart()
    selectionGeometryTimer.restart()
  }
  onViewportHeightChanged: if (layoutReady) {
    quoteGeometryTimer.restart()
    selectionGeometryTimer.restart()
  }
  onViewportOverscanChanged: if (layoutReady) {
    quoteGeometryTimer.restart()
    selectionGeometryTimer.restart()
  }
  onForegroundChanged: refreshStyledDocument()
  onBackgroundChanged: refreshStyledDocument()
  onSurfaceBackgroundChanged: refreshStyledDocument()
  onAccentChanged: refreshStyledDocument()
  onFontFamilyChanged: refreshStyledDocument()
  onBodyPixelSizeChanged: refreshStyledDocument()
  onWidthChanged: if (layoutReady) Qt.callLater(function() {
    if (root.refreshStyledDocument())
      root.rebuildMappings(root.parseRequestId)
  })
  Component.onCompleted: requestLayout()
}
