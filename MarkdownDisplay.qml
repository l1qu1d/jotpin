import QtQuick
import qs.Commons
import qs.Ui
import "HtmlEntities.js" as HtmlEntities
import "SyntaxHighlight.js" as SyntaxHighlight

Item {
  id: root

  property string sourceText: ""
  property color foreground: "white"
  property color background: "black"
  property color accent: "white"
  property string fontFamily: "monospace"
  property url baseUrl: ""
  property string homePath: ""
  property bool controlKeyHeld: false
  property int bodyPixelSize: 16
  property int horizontalPadding: Style.spacing.panelPadding
  property int verticalPadding: Style.spacing.panelPadding
  // Source rows are editor rows. Extra Column spacing around a blank block
  // makes an explicit empty line taller than a soft wrap or ordinary newline.
  property int blockSpacing: 0
  readonly property real bodyLineHeightFactor: 1.0
  property int cursorPosition: -1
  property real bodyCaretHeight: 0
  property int selectionStart: 0
  property int selectionEnd: 0
  property color selectionFill: "transparent"
  property var selectionRects: []
  property var selectionTargets: []
  property int selectionRevision: 0
  property int sourceRevision: 0
  property int layoutRevision: 0
  property int taskStateRevision: 0
  property string observedSourceText: ""
  property var taskCheckedOverrides: ({})
  // Production supplies the containing Flickable's visible content range.
  // Tests and standalone uses keep the legacy all-block renderer unless they
  // opt in explicitly, which keeps geometry fixtures deterministic.
  property bool viewportRenderingEnabled: false
  property real viewportY: 0
  property real viewportHeight: height
  property real viewportOverscan: Math.max(256, viewportHeight)
  property int forcedBlockIndex: -1
  property var blockGeometry: []
  property int blockGeometryRevision: 0
  property var pendingBlockMeasurements: ({})
  readonly property bool viewportGeometrySettled:
    !blockMeasurementTimer.running && !viewportSettleTimer.running &&
    Object.keys(root.pendingBlockMeasurements).length === 0
  property var measuredBlockHeightCache: ({
    entries: ({}),
    entryCount: 0,
    sourceCharacters: 0
  })
  readonly property int measuredBlockHeightCacheEntryLimit: 4096
  readonly property int measuredBlockHeightCacheSourceLimit: 524288
  property bool mouseSelectionActive: false
  property bool mouseSelectionUpdatePending: false
  property int pendingMouseSelectionAnchor: -1
  property real pendingMouseSelectionX: 0
  property real pendingMouseSelectionY: 0
  property int mouseClickCount: 0
  property string mouseClickKey: ""
  property double mouseClickTimestamp: 0
  readonly property int mouseDoubleClickInterval: Math.max(1,
    Number(Qt.styleHints.mouseDoubleClickInterval) || 400)
  property var blocks: []
  property var referenceDefinitions: ({})
  property string referenceDefinitionsKey: "{}"
  property int referenceDefinitionsRevision: 0
  // Mutate this plain JS object in place so cache updates made while QML is
  // evaluating text bindings do not emit property-change notifications. The
  // source/context revision prevents stale Markdown projections from crossing
  // edits, while the hard limits keep an unusually fragmented note bounded.
  property var plainInlineProjectionCache: ({
    revision: 0,
    entries: ({}),
    entryCount: 0,
    sourceCharacters: 0,
    prefixCharacters: 0,
    parseHits: 0,
    parseMisses: 0,
    prefixHits: 0,
    prefixMisses: 0
  })
  readonly property int projectionCacheEntryLimit: 2048
  readonly property int projectionCacheSourceLimit: 262144
  readonly property int projectionCachePrefixLimit: 1048576
  readonly property int projectionCachePrefixesPerEntry: 32
  property var codeHighlightCache: ({})
  property var codeHighlightPending: ({})
  property var codeHighlightQueued: ({})
  property var codeHighlightDeferred: ({})
  property var codeHighlightOrder: []
  readonly property int codeHighlightCacheLimit: 256
  readonly property int codeHighlightDelayMs: 500
  readonly property rect bodyCapBounds: bodyFontMetrics.tightBoundingRect("H")
  readonly property rect bodyCaretBounds: bodyFontMetrics.tightBoundingRect("xg")
  property string layoutSourceText: ""
  property int layoutCursorPosition: -1
  property bool layoutReady: false

  signal layoutUpdated()
  signal heightIndexAdjusted(real delta, real blockTop)
  signal taskToggled(int sourcePosition)
  signal sourcePositionRequested(int sourcePosition)
  signal sourceSelectionRequested(int anchorPosition, int sourcePosition)

  implicitHeight: displayColumn.implicitHeight + root.verticalPadding * 2

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
  }

  function codeLanguageFromInfo(value) {
    return SyntaxHighlight.hasLanguage(value)
      ? SyntaxHighlight.normalizeLanguage(value) : ""
  }

  function codeLanguageLabelFromInfo(value) {
    var token = String(value || "").trim().split(/\s+/)[0] || ""
    token = token.replace(/^\./, "")
    if (!token || /^(?:none|plain|text|txt)$/i.test(token)) return ""
    return SyntaxHighlight.languageLabel(token) || token
  }

  function codeHighlightDark() {
    var luminance = Number(root.background.r) * 0.2126 +
      Number(root.background.g) * 0.7152 + Number(root.background.b) * 0.0722
    return !isFinite(luminance) || luminance < 0.55
  }

  function codeHighlightKey(blockValue) {
    var block = blockValue || {}
    var language = String(block.language || "")
    var code = String(block.text || "")
    if (!language || !SyntaxHighlight.hasLanguage(language)) return ""
    var hash = 2166136261
    for (var index = 0; index < code.length; index++) {
      hash ^= code.charCodeAt(index)
      hash = ((hash << 1) + (hash << 4) + (hash << 7) +
        (hash << 8) + (hash << 24)) >>> 0
    }
    return language + "|" + (root.codeHighlightDark() ? "dark" : "light") +
      "|" + code.length + "|" + hash.toString(16)
  }

  function codeHighlightSlot(blockValue) {
    var block = blockValue || {}
    return String(block.language || "") + "|" +
      String(Number(block.sourceStart) || 0) + "|" +
      (root.codeHighlightDark() ? "dark" : "light")
  }

  function codePlainMarkup(blockValue) {
    var block = blockValue || {}
    return root.escapeHtml(String(block.text || ""))
      .replace(/ {2,}/g, function(spaces) {
        return new Array(spaces.length + 1).join("&nbsp;")
      })
      .replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;")
      .replace(/\n/g, "<br/>")
  }

  function requestCodeHighlight(blockValue) {
    var block = blockValue || {}
    var key = root.codeHighlightKey(block)
    if (!key || root.codeHighlightCache[key] !== undefined ||
        root.codeHighlightPending[key]) return
    var deferred = Object.assign({}, root.codeHighlightDeferred)
    deferred[root.codeHighlightSlot(block)] = {
      type: "highlight",
      key: key,
      code: String(block.text || ""),
      language: String(block.language || ""),
      dark: root.codeHighlightDark()
    }
    root.codeHighlightDeferred = deferred
    codeHighlightDelayTimer.restart()
  }

  function dispatchCodeHighlightRequest(requestValue) {
    var request = requestValue || {}
    var key = String(request.key || "")
    if (!key || root.codeHighlightCache[key] !== undefined ||
        root.codeHighlightPending[key]) return
    var pending = Object.assign({}, root.codeHighlightPending)
    pending[key] = true
    root.codeHighlightPending = pending
    if (codeHighlightWorker.ready) {
      codeHighlightWorker.sendMessage(request)
    } else {
      var queued = Object.assign({}, root.codeHighlightQueued)
      queued[key] = request
      root.codeHighlightQueued = queued
    }
  }

  function flushDeferredCodeHighlights() {
    var deferred = root.codeHighlightDeferred || ({})
    root.codeHighlightDeferred = ({})
    var slots = Object.keys(deferred)
    for (var index = 0; index < slots.length; index++)
      root.dispatchCodeHighlightRequest(deferred[slots[index]])
  }

  function flushCodeHighlightQueue() {
    if (!codeHighlightWorker.ready) return
    var queued = root.codeHighlightQueued || ({})
    root.codeHighlightQueued = ({})
    var keys = Object.keys(queued)
    for (var index = 0; index < keys.length; index++)
      codeHighlightWorker.sendMessage(queued[keys[index]])
  }

  function codeHighlightMarkup(blockValue) {
    var key = root.codeHighlightKey(blockValue)
    if (key && root.codeHighlightCache[key] !== undefined)
      return String(root.codeHighlightCache[key] || "")
    // Keep the current source painted while its async highlight is pending.
    // Showing stale colored markup would hide the newest character; swapping
    // to the TextEdit layer made the whole code block flash on every edit.
    return root.codePlainMarkup(blockValue)
  }

  function storeCodeHighlight(keyValue, markupValue) {
    var key = String(keyValue || "")
    if (!key) return
    var pending = Object.assign({}, root.codeHighlightPending)
    delete pending[key]
    root.codeHighlightPending = pending
    var queued = Object.assign({}, root.codeHighlightQueued)
    delete queued[key]
    root.codeHighlightQueued = queued
    var cache = Object.assign({}, root.codeHighlightCache)
    var order = root.codeHighlightOrder.slice()
    cache[key] = String(markupValue || "")
    var oldIndex = order.indexOf(key)
    if (oldIndex >= 0) order.splice(oldIndex, 1)
    order.push(key)
    while (order.length > root.codeHighlightCacheLimit) delete cache[order.shift()]
    root.codeHighlightCache = cache
    root.codeHighlightOrder = order
  }

  WorkerScript {
    id: codeHighlightWorker
    source: Qt.resolvedUrl("syntax/HighlightWorker.js")
    onReadyChanged: root.flushCodeHighlightQueue()
    onMessage: function(message) {
      if (message.type === "highlighted")
        root.storeCodeHighlight(message.key, message.markup)
    }
  }

  Timer {
    id: codeHighlightDelayTimer
    interval: root.codeHighlightDelayMs
    repeat: false
    onTriggered: root.flushDeferredCodeHighlights()
  }

  function inlineCodeCssColor(value, alpha) {
    var red = Math.round(Math.max(0, Math.min(1, Number(value.r))) * 255)
    var green = Math.round(Math.max(0, Math.min(1, Number(value.g))) * 255)
    var blue = Math.round(Math.max(0, Math.min(1, Number(value.b))) * 255)
    var opacity = Math.max(0, Math.min(1, Number(alpha)))
    return "rgba(" + red + "," + green + "," + blue + "," + opacity + ")"
  }

  function inlineCodeHtml(value) {
    var codeColor = root.inlineCodeCssColor(root.accent, 1)
    var codeBackground = root.inlineCodeCssColor(root.accent, 0.16)
    return "<code style=\"background-color:" + codeBackground +
      "; color:" + codeColor + ";\">" + root.escapeHtml(value) +
      "</code>"
  }

  function richTextCssColor(value) {
    var red = Math.round(Math.max(0, Math.min(1, Number(value.r))) * 255)
    var green = Math.round(Math.max(0, Math.min(1, Number(value.g))) * 255)
    var blue = Math.round(Math.max(0, Math.min(1, Number(value.b))) * 255)
    return "#" + ("0" + red.toString(16)).slice(-2) +
      ("0" + green.toString(16)).slice(-2) +
      ("0" + blue.toString(16)).slice(-2)
  }

  function linkCssColor() {
    // Accent colors are allowed to be decorative and can be too dark for a
    // link on the current surface. The theme foreground is already chosen for
    // readable body text, so use it for links and add an underline below.
    // Qt rich text accepts the hex form here; rgba(...) is rejected by its
    // <font color> parser and silently falls back to an unreadable color.
    return root.richTextCssColor(root.foreground)
  }

  function linkForPointer(textItem, x, y, modifiers) {
    if (!(Number(modifiers) & Qt.ControlModifier) || !textItem ||
        typeof textItem.linkAt !== "function") return ""
    return String(textItem.linkAt(Number(x) || 0, Number(y) || 0) || "")
  }

  function linkCursorShape(textItem, x, y) {
    return root.controlKeyHeld && root.linkForPointer(
      textItem, x, y, Qt.ControlModifier) !== ""
      ? Qt.PointingHandCursor : Qt.IBeamCursor
  }

  function openLink(link) {
    var target = root.linkSourceUrl(link)
    if (target === "") return false
    Qt.openUrlExternally(target)
    return true
  }

  function linkSourceUrl(value) {
    var raw = String(value || "").trim()
    if (raw === "" || raw.charAt(0) === "#") return raw
    if (raw.indexOf("~/") === 0 && String(root.homePath || "") !== "") {
      raw = String(root.homePath).replace(/\/+$/, "") + raw.slice(1)
    }
    if (/^\/\//.test(raw)) raw = "https:" + raw
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) return encodeURI(raw)
    if (raw.charAt(0) === "/") return "file://" + encodeURI(raw)

    var base = String(root.baseUrl || "")
    if (base !== "") {
      if (base.charAt(base.length - 1) !== "/") base += "/"
      return base + encodeURI(raw)
    }
    return encodeURI(raw)
  }

  function imageSourceUrl(value) {
    return root.linkSourceUrl(value)
  }

  function standaloneImageData(value) {
    var raw = String(value || "")
    var leading = /^\s*/.exec(raw)[0].length
    var trailing = /\s*$/.exec(raw)[0].length
    var matches = root.inlineLinkMatches(raw)
    if (matches.length !== 1 || !matches[0].image ||
        matches[0].start !== leading ||
        matches[0].end !== raw.length - trailing) return null
    return {
      alt: matches[0].label,
      url: matches[0].target,
      altSourceStart: matches[0].labelStart,
      altSourceEnd: matches[0].labelEnd
    }
  }

  function normalizedReferenceLabel(value) {
    return String(value || "").replace(/\s+/g, " ").trim().toLowerCase()
  }

  function referenceDefinitionForLine(value) {
    var match = /^ {0,3}\[([^\]]+)\]:[ \t]*(?:<([^>\n]*)>|(\S+?))(?:[ \t]+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?[ \t]*$/.exec(
      String(value || ""))
    if (!match) return null
    return {
      label: root.normalizedReferenceLabel(match[1]),
      target: match[2] !== undefined ? match[2] : match[3],
      title: match[4] !== undefined ? match[4]
        : match[5] !== undefined ? match[5]
        : match[6] !== undefined ? match[6] : ""
    }
  }

  function referenceDefinitionsForLines(lines) {
    var definitions = {}
    var fenceMarker = ""
    var fenceLength = 0
    for (var index = 0; index < lines.length; index++) {
      var line = String(lines[index] || "")
      if (fenceMarker !== "") {
        var closingFence = new RegExp(
          "^ {0,3}" + fenceMarker + "{" + fenceLength + ",}\\s*$")
        if (closingFence.test(line)) {
          fenceMarker = ""
          fenceLength = 0
        }
        continue
      }
      var openingFence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line)
      if (openingFence && !(openingFence[1].charAt(0) === "`" &&
          openingFence[2].indexOf("`") >= 0)) {
        fenceMarker = openingFence[1].charAt(0)
        fenceLength = openingFence[1].length
        continue
      }
      var definition = root.referenceDefinitionForLine(lines[index])
      if (definition && definition.label !== "" &&
          definitions[definition.label] === undefined) {
        definitions[definition.label] = {
          target: definition.target,
          title: definition.title
        }
      }
    }
    return definitions
  }

  function isEscapedSourcePosition(value, position) {
    var raw = String(value || "")
    var slashCount = 0
    for (var index = position - 1;
         index >= 0 && raw.charAt(index) === "\\"; index--) slashCount++
    return slashCount % 2 === 1
  }

  function inlineDestinationAt(value, start) {
    var raw = String(value || "")
    var index = Number(start) || 0
    while (index < raw.length && /[ \t\n]/.test(raw.charAt(index))) index++
    var target = ""
    var title = ""
    if (raw.charAt(index) === "<") {
      var enclosedStart = ++index
      while (index < raw.length && raw.charAt(index) !== ">" &&
             raw.charAt(index) !== "\n") index++
      if (raw.charAt(index) !== ">") return null
      target = raw.slice(enclosedStart, index)
      index++
    } else {
      var targetStart = index
      var depth = 0
      while (index < raw.length) {
        var character = raw.charAt(index)
        if (character === "\\" && index + 1 < raw.length) {
          index += 2
          continue
        }
        if (character === "(") depth++
        else if (character === ")") {
          if (depth === 0) break
          depth--
        } else if (/[ \t\n]/.test(character) && depth === 0) break
        index++
      }
      if (depth !== 0) return null
      target = raw.slice(targetStart, index)
    }

    while (index < raw.length && /[ \t\n]/.test(raw.charAt(index))) index++
    if (raw.charAt(index) !== ")") {
      var opener = raw.charAt(index)
      var closer = opener === "(" ? ")" : opener
      if (opener !== "\"" && opener !== "'" && opener !== "(") return null
      var titleStart = ++index
      while (index < raw.length && raw.charAt(index) !== closer) {
        if (raw.charAt(index) === "\\" && index + 1 < raw.length) index += 2
        else index++
      }
      if (raw.charAt(index) !== closer) return null
      title = raw.slice(titleStart, index)
      index++
      while (index < raw.length && /[ \t\n]/.test(raw.charAt(index))) index++
      if (raw.charAt(index) !== ")") return null
    }
    return { target: target.replace(/\\([()])/g, "$1"),
      title: title, end: index + 1 }
  }

  function inlineLinkMatches(value) {
    var raw = String(value || "")
    var matches = []
    var codeRanges = root.codeSpanMatches(raw)

    function insideCode(position) {
      for (var codeIndex = 0; codeIndex < codeRanges.length; codeIndex++) {
        if (position >= codeRanges[codeIndex].start &&
            position < codeRanges[codeIndex].end) return true
      }
      return false
    }

    for (var index = 0; index < raw.length; index++) {
      var image = raw.charAt(index) === "!" && raw.charAt(index + 1) === "["
      var open = image ? index + 1 : index
      if (raw.charAt(open) !== "[" || insideCode(index) ||
          root.isEscapedSourcePosition(raw, index)) continue

      var depth = 1
      var close = open + 1
      while (close < raw.length && depth > 0) {
        if (raw.charAt(close) === "\\" && close + 1 < raw.length) {
          close += 2
          continue
        }
        if (raw.charAt(close) === "[") depth++
        else if (raw.charAt(close) === "]") depth--
        close++
      }
      if (depth !== 0) continue
      var labelEnd = close - 1
      var label = raw.slice(open + 1, labelEnd)
      var end = close
      var target = ""
      var title = ""

      if (raw.charAt(close) === "(") {
        var destination = root.inlineDestinationAt(raw, close + 1)
        if (!destination) continue
        target = destination.target
        title = destination.title
        end = destination.end
      } else if (raw.charAt(close) === "[") {
        var referenceEnd = close + 1
        while (referenceEnd < raw.length && raw.charAt(referenceEnd) !== "]") {
          if (raw.charAt(referenceEnd) === "\\" &&
              referenceEnd + 1 < raw.length) referenceEnd += 2
          else referenceEnd++
        }
        if (raw.charAt(referenceEnd) !== "]") continue
        var referenceLabel = raw.slice(close + 1, referenceEnd)
        if (referenceLabel === "") referenceLabel = label
        var definition = root.referenceDefinitions[
          root.normalizedReferenceLabel(referenceLabel)]
        if (definition === undefined) continue
        target = definition.target
        title = definition.title
        end = referenceEnd + 1
      } else {
        definition = root.referenceDefinitions[
          root.normalizedReferenceLabel(label)]
        if (definition === undefined) continue
        target = definition.target
        title = definition.title
      }

      matches.push({ start: index, end: end, image: image,
        label: label, labelStart: open + 1, labelEnd: labelEnd,
        target: String(target || ""),
        title: String(title || "") })
      index = end - 1
    }
    return matches
  }

  function replaceInlineLinks(value, tokens, rich) {
    var raw = String(value || "")
    var matches = root.inlineLinkMatches(raw)
    var result = ""
    var sourceIndex = 0
    for (var index = 0; index < matches.length; index++) {
      var match = matches[index]
      result += raw.slice(sourceIndex, match.start)
      var replacement = root.finishPlainInline(match.label, tokens)
      if (rich) {
        replacement = match.image
          ? "<img src=\"" + root.escapeHtml(
              root.imageSourceUrl(match.target)) + "\" alt=\"" +
              root.escapeHtml(match.label) + "\"" +
              (match.title === "" ? "" : " title=\"" +
                root.escapeHtml(match.title) + "\"") + ">"
          : root.richLinkHtml(match.label, match.target, match.title)
      }
      result += root.protect(tokens, replacement)
      sourceIndex = match.end
    }
    return result + raw.slice(sourceIndex)
  }

  function protect(tokens, value) {
    var index = tokens.length
    tokens.push(value)
    return "\u0000" + index + "\u0000"
  }

  function restoreProtected(value, tokens) {
    var restored = String(value || "")
    // Link labels can contain an escaped character or entity token, so token
    // restoration may reveal another token. Resolve those nested placeholders
    // without letting Markdown markup inside a protected span run again.
    for (var pass = 0; pass <= tokens.length && /\u0000\d+\u0000/.test(restored);
         pass++) {
      restored = restored.replace(/\u0000(\d+)\u0000/g,
        function(match, index) { return tokens[Number(index)] || "" })
    }
    return restored
  }

  function decodedEntity(value) {
    var entity = String(value || "")
    var numeric = /^&#(x[0-9a-f]+|[0-9]+);$/i.exec(entity)
    if (!numeric) return HtmlEntities.decodeNamed(entity)
    var codePoint = numeric[1].charAt(0).toLowerCase() === "x"
      ? parseInt(numeric[1].slice(1), 16) : parseInt(numeric[1], 10)
    if (!isFinite(codePoint) || codePoint <= 0 || codePoint > 0x10ffff ||
        (codePoint >= 0xd800 && codePoint <= 0xdfff)) return "\ufffd"
    if (codePoint <= 0xffff) return String.fromCharCode(codePoint)
    codePoint -= 0x10000
    return String.fromCharCode(0xd800 + (codePoint >> 10),
      0xdc00 + (codePoint & 0x3ff))
  }

  function richLinkHtml(label, target, title) {
    var titleAttribute = String(title || "") === "" ? "" :
      " title=\"" + root.escapeHtml(title) + "\""
    return "<a href=\"" + root.escapeHtml(root.linkSourceUrl(target)) + "\"" +
      titleAttribute + ">" +
      "<font color=\"" + root.linkCssColor() + "\"><u>" +
      root.inlineLabelHtml(label) + "</u></font></a>"
  }

  function inlineLabelHtml(value) {
    var text = root.escapeHtml(value)
    text = text.replace(/\*\*\*([^*]+)\*\*\*/g,
      "<em><strong>$1</strong></em>")
    text = text.replace(/\*\*([^*]*?)\*([^*]+)\*([^*]*?)\*\*/g,
      "<strong>$1<em>$2</em>$3</strong>")
    text = text.replace(/\*([^*]*?)\*\*([^*]+)\*\*([^*]*?)\*/g,
      "<em>$1<strong>$2</strong>$3</em>")
    text = text.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>")
    text = text.replace(/\*([^*]+)\*/g, "<em>$1</em>")
    return text
  }

  function codeSpanMatches(value) {
    var raw = String(value || "")
    var matches = []
    var index = 0
    while (index < raw.length) {
      if (raw.charAt(index) !== "`") {
        index++
        continue
      }

      var openStart = index
      while (index < raw.length && raw.charAt(index) === "`") index++
      var runLength = index - openStart
      var search = index
      var matched = false
      while (search < raw.length) {
        if (raw.charAt(search) !== "`") {
          search++
          continue
        }

        var closeStart = search
        while (search < raw.length && raw.charAt(search) === "`") search++
        var closeLength = search - closeStart
        if (closeLength !== runLength) continue

        var rawContent = raw.slice(index, closeStart)
        var trimStart = 0
        var trimEnd = rawContent.length
        if (rawContent.length >= 2 && rawContent.charAt(0) === " " &&
            rawContent.charAt(rawContent.length - 1) === " " &&
            !/^ +$/.test(rawContent)) {
          trimStart = 1
          trimEnd = rawContent.length - 1
        }
        matches.push({
          start: openStart,
          end: search,
          openLength: runLength,
          contentStart: index,
          closeStart: closeStart,
          rawContent: rawContent,
          content: rawContent.slice(trimStart, trimEnd),
          trimStart: trimStart,
          trimEnd: trimEnd
        })
        index = search
        matched = true
        break
      }

      // An unmatched run is literal Markdown while the user is still
      // typing. Leave it in the source stream so the rendered text and caret
      // retain its width until a matching run is actually present.
      if (!matched) index = openStart + runLength
    }
    return matches
  }

  function replaceCodeSpans(value, replacer) {
    var raw = String(value || "")
    var matches = root.codeSpanMatches(raw)
    var result = ""
    var sourceIndex = 0
    for (var index = 0; index < matches.length; index++) {
      var match = matches[index]
      result += raw.slice(sourceIndex, match.start)
      result += replacer(match)
      sourceIndex = match.end
    }
    return result + raw.slice(sourceIndex)
  }

  function finishPlainInline(value, tokens) {
    var raw = String(value || "")
      .replace(/\\([!\"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~])/g,
        function(match, character) {
          return root.protect(tokens, character)
        })
      .replace(/&(?:#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);/g,
        function(match) {
          return root.protect(tokens, root.decodedEntity(match))
        })
      .replace(/<([a-z][a-z0-9+.-]{1,31}:[^ <>]*)>/gi, "$1")
      .replace(/<([a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,})>/gi,
        "$1")
      // Strip only delimiters that form the same rendered spans as
      // inlineHtml(). Literal/unmatched markers must retain their width for
      // source-aligned caret and hit-test geometry.
      .replace(/\*\*\*([^*]+)\*\*\*/g, "$1")
      .replace(/\*\*([^*]*?)\*([^*]+)\*([^*]*?)\*\*/g, "$1$2$3")
      .replace(/\*([^*]*?)\*\*([^*]+)\*\*([^*]*?)\*/g, "$1$2$3")
      .replace(/\*\*([^*\n]+)\*\*/g, "$1")
      .replace(/(^|[^A-Za-z0-9])__([^_\n]+)__([^A-Za-z0-9]|$)/g,
        "$1$2$3")
      .replace(/~~([^~\n]+)~~/g, "$1")
      .replace(/\*([^*]+)\*/g, "$1")
      .replace(/(^|[^A-Za-z0-9])_([^_\n]+)_([^A-Za-z0-9]|$)/g,
        "$1$2$3")
    raw = root.replaceInlineLinks(raw, tokens, false)
    return root.restoreProtected(raw, tokens)
  }

  function matchedInlineDelimiterMask(value) {
    var raw = String(value || "")
    var mask = []
    var protectedRanges = root.codeSpanMatches(raw)
    var linkMatches = root.inlineLinkMatches(raw)
    for (var linkIndex = 0; linkIndex < linkMatches.length; linkIndex++) {
      protectedRanges.push({start: linkMatches[linkIndex].start,
        end: linkMatches[linkIndex].end})
    }

    function protectedPosition(position) {
      // A delimiter already claimed by an earlier, more specific span cannot
      // also open or close a later emphasis match. For example, without this
      // guard the final `*` in `**bold**` can be paired with the opening `*`
      // in the following `*italic*`, leaving italic's closing marker visible
      // in the source-to-render projection.
      if (mask[position]) return true
      for (var rangeIndex = 0; rangeIndex < protectedRanges.length;
           rangeIndex++) {
        if (position >= protectedRanges[rangeIndex].start &&
            position < protectedRanges[rangeIndex].end) return true
      }
      var slashCount = 0
      for (var slash = position - 1;
           slash >= 0 && raw.charAt(slash) === "\\"; slash--) slashCount++
      return slashCount % 2 === 1
    }

    function mark(start, length) {
      for (var index = 0; index < length; index++) mask[start + index] = true
    }

    function collect(pattern, openingOffset, openingLength,
                     contentCapture, closingLength) {
      var match
      while ((match = pattern.exec(raw)) !== null) {
        var open = match.index + openingOffset(match)
        var close = open + openingLength + match[contentCapture].length
        if (!protectedPosition(open) && !protectedPosition(close)) {
          mark(open, openingLength)
          mark(close, closingLength)
        } else {
          // RegExp.global advances past the entire rejected match. Resume one
          // source character after its opening delimiter so a valid adjacent
          // span inside that consumed interval can still be considered.
          pattern.lastIndex = open + 1
        }
        if (match[0].length === 0) pattern.lastIndex++
      }
    }

    function collectOuter(pattern, openingLength, closingLength) {
      var match
      while ((match = pattern.exec(raw)) !== null) {
        var open = match.index
        var close = match.index + match[0].length - closingLength
        if (!protectedPosition(open) && !protectedPosition(close)) {
          mark(open, openingLength)
          mark(close, closingLength)
        } else {
          pattern.lastIndex = open + 1
        }
        if (match[0].length === 0) pattern.lastIndex++
      }
    }

    collect(/\*\*\*([^*]+)\*\*\*/g, function() { return 0 }, 3, 1, 3)
    collectOuter(/\*\*([^*]*?)\*([^*]+)\*([^*]*?)\*\*/g, 2, 2)
    collectOuter(/\*([^*]*?)\*\*([^*]+)\*\*([^*]*?)\*/g, 1, 1)
    collect(/\*\*([^*\n]+)\*\*/g, function() { return 0 }, 2, 1, 2)
    collect(/~~([^~\n]+)~~/g, function() { return 0 }, 2, 1, 2)
    collect(/(^|[^A-Za-z0-9])__([^_\n]+)__([^A-Za-z0-9]|$)/g,
      function(match) { return match[1].length }, 2, 2, 2)
    collect(/\*([^*]+)\*/g, function() { return 0 }, 1, 1, 1)
    collect(/(^|[^A-Za-z0-9])_([^_\n]+)_([^A-Za-z0-9]|$)/g,
      function(match) { return match[1].length }, 1, 2, 1)
    return mask
  }

  function visiblePlainSourceSlice(value, start, end, delimiterMask) {
    var raw = String(value || "")
    var result = ""
    for (var index = Math.max(0, Number(start) || 0);
         index < Math.min(raw.length, Number(end) || 0); index++) {
      if (!delimiterMask[index]) result += raw.charAt(index)
    }
    return result
  }

  function resetPlainInlineProjectionCache() {
    var cache = root.plainInlineProjectionCache
    cache.revision = root.sourceRevision
    cache.entries = ({})
    cache.entryCount = 0
    cache.sourceCharacters = 0
    cache.prefixCharacters = 0
    cache.parseHits = 0
    cache.parseMisses = 0
    cache.prefixHits = 0
    cache.prefixMisses = 0
  }

  function plainInlineProjectionEntry(value) {
    var raw = String(value || "")
    var cache = root.plainInlineProjectionCache
    if (cache.revision !== root.sourceRevision) {
      root.resetPlainInlineProjectionCache()
      cache = root.plainInlineProjectionCache
    }

    // Prefix the key so source such as `__proto__` can never address an
    // inherited Object member. Reference definitions are part of the context:
    // the same `[label][id]` source can project differently after an edit to
    // its definition elsewhere in the note.
    var key = "$" + root.referenceDefinitionsRevision + "\u0000" + raw
    var entry = cache.entries[key]
    if (entry && entry.source === raw &&
        entry.contextRevision === root.referenceDefinitionsRevision) {
      cache.parseHits++
      return entry
    }

    cache.parseMisses++
    entry = {
      source: raw,
      contextRevision: root.referenceDefinitionsRevision,
      matches: root.codeSpanMatches(raw),
      mask: root.matchedInlineDelimiterMask(raw),
      prefixes: ({}),
      prefixCount: 0,
      cached: false
    }
    if (cache.entryCount < root.projectionCacheEntryLimit &&
        cache.sourceCharacters + raw.length <=
          root.projectionCacheSourceLimit) {
      entry.cached = true
      cache.entries[key] = entry
      cache.entryCount++
      cache.sourceCharacters += raw.length
    }
    return entry
  }

  function projectionCacheStatsForTests() {
    var cache = root.plainInlineProjectionCache
    return {
      sourceRevision: root.sourceRevision,
      layoutRevision: root.layoutRevision,
      referenceDefinitionsRevision: root.referenceDefinitionsRevision,
      cacheRevision: Number(cache.revision),
      entries: Number(cache.entryCount),
      sourceCharacters: Number(cache.sourceCharacters),
      prefixCharacters: Number(cache.prefixCharacters),
      parseHits: Number(cache.parseHits),
      parseMisses: Number(cache.parseMisses),
      prefixHits: Number(cache.prefixHits),
      prefixMisses: Number(cache.prefixMisses)
    }
  }

  function plainInlinePrefix(value, sourcePosition) {
    var raw = String(value || "")
    var position = Number(sourcePosition)
    if (!isFinite(position)) position = raw.length
    position = Math.max(0, Math.min(position, raw.length))

    var tokens = []
    var entry = root.plainInlineProjectionEntry(raw)
    var prefixKey = "p" + position
    var cachedPrefix = entry.prefixes[prefixKey]
    if (cachedPrefix !== undefined) {
      root.plainInlineProjectionCache.prefixHits++
      return cachedPrefix
    }
    root.plainInlineProjectionCache.prefixMisses++

    var matches = entry.matches
    var delimiterMask = entry.mask
    var result = ""
    var sourceIndex = 0
    for (var index = 0; index < matches.length; index++) {
      var match = matches[index]
      if (match.start >= position) break
      result += root.visiblePlainSourceSlice(raw, sourceIndex,
        Math.min(match.start, position), delimiterMask)

      if (position <= match.end) {
        var contentEnd = Math.min(position, match.closeStart)
        var sourceContentLength = Math.max(0,
          contentEnd - match.contentStart)
        var renderedContentEnd = Math.min(
          match.trimEnd, sourceContentLength)
        var contentPrefix = renderedContentEnd > match.trimStart
          ? match.rawContent.slice(match.trimStart, renderedContentEnd)
          : ""
        if (contentPrefix !== "") {
          result += root.protect(tokens, contentPrefix)
        }
        sourceIndex = position
        result = root.finishPlainInline(result, tokens)
        if (entry.cached &&
            entry.prefixCount < root.projectionCachePrefixesPerEntry &&
            root.plainInlineProjectionCache.prefixCharacters + result.length <=
              root.projectionCachePrefixLimit) {
          entry.prefixes[prefixKey] = result
          entry.prefixCount++
          root.plainInlineProjectionCache.prefixCharacters += result.length
        }
        return result
      }

      result += root.protect(tokens, match.content)
      sourceIndex = match.end
    }

    result += root.visiblePlainSourceSlice(raw, sourceIndex, position,
      delimiterMask)
    result = root.finishPlainInline(result, tokens)
    if (entry.cached &&
        entry.prefixCount < root.projectionCachePrefixesPerEntry &&
        root.plainInlineProjectionCache.prefixCharacters + result.length <=
          root.projectionCachePrefixLimit) {
      entry.prefixes[prefixKey] = result
      entry.prefixCount++
      root.plainInlineProjectionCache.prefixCharacters += result.length
    }
    return result
  }

  function inlineHtml(value) {
    var tokens = []
    var raw = String(value || "")

    raw = raw.replace(/\\([!\"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~])/g,
      function(match, character) {
        return root.protect(tokens, root.escapeHtml(character))
      })
    raw = raw.replace(
      /&(?:#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]+);/g,
      function(match) {
        return root.protect(tokens,
          root.escapeHtml(root.decodedEntity(match)))
      })
    raw = raw.replace(/<([a-z][a-z0-9+.-]{1,31}:[^ <>]*)>/gi,
      function(match, target) {
        return root.protect(tokens, root.richLinkHtml(target, target))
      })
    raw = raw.replace(
      /<([a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,})>/gi,
      function(match, address) {
        return root.protect(tokens,
          root.richLinkHtml(address, "mailto:" + address))
      })
    raw = root.replaceCodeSpans(raw, function(match) {
      return root.protect(tokens, root.inlineCodeHtml(match.content))
    })
    raw = root.replaceInlineLinks(raw, tokens, true)

    var text = root.escapeHtml(raw)
    text = text.replace(/\*\*\*([^*]+)\*\*\*/g,
      "<em><strong>$1</strong></em>")
    text = text.replace(/\*\*([^*]*?)\*([^*]+)\*([^*]*?)\*\*/g,
      "<strong>$1<em>$2</em>$3</strong>")
    text = text.replace(/\*([^*]*?)\*\*([^*]+)\*\*([^*]*?)\*/g,
      "<em>$1<strong>$2</strong>$3</em>")
    text = text.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>")
    text = text.replace(
      /(^|[^A-Za-z0-9])__([^_\n]+)__([^A-Za-z0-9]|$)/g,
      "$1<strong>$2</strong>$3")
    text = text.replace(/~~([^~\n]+)~~/g, "<del>$1</del>")
    text = text.replace(/\*([^*]+)\*/g, "<em>$1</em>")
    text = text.replace(
      /(^|[^A-Za-z0-9])_([^_\n]+)_([^A-Za-z0-9]|$)/g,
      "$1<em>$2</em>$3")
    return root.preserveRichTextSpaceRuns(
      root.restoreProtected(text, tokens))
  }

  function preserveRichTextSpaceRuns(value) {
    var html = String(value || "")
    var parts = html.split(/(<[^>]*>)/g)
    for (var partIndex = 0; partIndex < parts.length; partIndex++) {
      if (parts[partIndex].charAt(0) === "<") continue
      parts[partIndex] = parts[partIndex].replace(/ {2,}/g,
        function(run) {
          var preserved = " "
          for (var index = 1; index < run.length; index++)
            preserved += "&#160;"
          return preserved
        })
    }
    return parts.join("")
  }

  // Selection overlays use the same rich-text metrics as the visible
  // Markdown, but their glyphs must stay transparent so the real renderer
  // remains the only text surface. Neutralize inline colors while preserving
  // bold, italic, underline, and code-span geometry.
  function selectionOverlayHtml(value) {
    var html = String(value || "")
    html = html.replace(
      /(<font\b[^>]*\bcolor\s*=\s*)(["'])(.*?)\2/gi,
      function(match, prefix, quote) {
        return prefix + quote + "transparent" + quote
      })
    html = html.replace(
      /(style\s*=\s*)(["'])(.*?)\2/gi,
      function(match, prefix, quote, style) {
        var neutralStyle = style.replace(
          /((?:background-)?color)\s*:\s*[^;"']+/gi,
          "$1:transparent")
        return prefix + quote + neutralStyle + quote
      })
    return html
  }

  function splitTableRow(value) {
    var row = String(value || "").trim()
    if (row.charAt(0) === "|") row = row.slice(1)
    if (row.charAt(row.length - 1) === "|") row = row.slice(0, -1)

    var cells = []
    var current = ""
    var escaped = false
    var codeRunLength = 0
    var linkDestinationDepth = 0
    for (var index = 0; index < row.length; index++) {
      var character = row.charAt(index)
      if (character === "`" && !escaped) {
        var runStart = index
        while (index + 1 < row.length && row.charAt(index + 1) === "`") index++
        var runLength = index - runStart + 1
        if (codeRunLength === 0) codeRunLength = runLength
        else if (codeRunLength === runLength) codeRunLength = 0
        current += row.slice(runStart, index + 1)
        continue
      }
      if (codeRunLength === 0 && linkDestinationDepth === 0 &&
          character === "]" && index + 1 < row.length &&
          row.charAt(index + 1) === "(") {
        current += "]("
        index++
        linkDestinationDepth = 1
        continue
      }
      if (codeRunLength === 0 && linkDestinationDepth > 0) {
        if (character === "(") linkDestinationDepth++
        else if (character === ")") linkDestinationDepth--
        current += character
        continue
      }
      if (character === "|" && !escaped && codeRunLength === 0) {
        cells.push(current.trim())
        current = ""
        continue
      }
      if (character === "\\" && !escaped) {
        escaped = true
        current += character
        continue
      }
      escaped = false
      current += character
    }
    cells.push(current.trim())
    return cells
  }

  function isTableSeparator(value) {
    var cells = root.splitTableRow(value)
    if (cells.length < 1) return false
    for (var index = 0; index < cells.length; index++) {
      if (!/^:?-{3,}:?$/.test(cells[index])) return false
    }
    return true
  }

  function isTableStart(header, separator) {
    if (String(header || "").indexOf("|") < 0 ||
        !root.isTableSeparator(separator)) return false
    return root.splitTableRow(header).length ===
      root.splitTableRow(separator).length
  }

  function tableAlignments(separator) {
    var cells = root.splitTableRow(separator)
    var alignments = []
    for (var index = 0; index < cells.length; index++) {
      var left = cells[index].charAt(0) === ":"
      var right = cells[index].charAt(cells[index].length - 1) === ":"
      alignments.push(left && right ? "center" : right ? "right" : "left")
    }
    return alignments
  }

  function listItem(value, allowIncomplete) {
    var raw = String(value || "")
    var match = /^(\s*)([-+*]|\d+[.)])[ \t]+(.*)$/.exec(raw)
    var incomplete = false
    if (!match && allowIncomplete) {
      var incompleteMatch = /^(\s*)([-+*]|\d+[.)])$/.exec(raw)
      if (incompleteMatch) {
        match = [incompleteMatch[0], incompleteMatch[1],
          incompleteMatch[2], ""]
        incomplete = true
      }
    }
    if (!match) return null

    var content = match[3]
    var task = /^\[([ xX])\][ \t]+(.*)$/.exec(content)
    return {
      indent: match[1].replace(/\t/g, "    ").length,
      marker: match[2],
      ordered: /^\d/.test(match[2]),
      number: /^\d/.test(match[2]) ? parseInt(match[2], 10) : 0,
      task: !!task,
      checked: !!task && task[1].toLowerCase() === "x",
      plain: task ? task[2] : content,
      html: root.inlineHtml(task ? task[2] : content),
      incomplete: incomplete
    }
  }

  function activeIncompleteListLine(lines, index, lineOffsets) {
    var line = lines[index] || ""
    if (!/^\s*([-+*]|\d+[.)])$/.test(line)) return false
    var cursor = Number(root.cursorPosition)
    return isFinite(cursor) && lineOffsets &&
      cursor === lineOffsets[index] + line.length
  }

  function isBlockStart(lines, index, lineOffsets) {
    var line = lines[index] || ""
    if (/^\s*$/.test(line)) return true
    if (root.activeIncompleteListLine(lines, index, lineOffsets)) return true
    if (root.standaloneImageData(line)) return true
    if (root.referenceDefinitionForLine(line)) return true
    if (/^ {0,3}(#{1,6})[ \t]+/.test(line)) return true
    if (/^ {0,3}(`{3,}|~{3,})/.test(line)) return true
    if (/^ {0,3}>/.test(line)) return true
    if (/^\s*([-+*]|\d+[.)])[ \t]+/.test(line)) return true
    if (/^ {0,3}((\* ?){3,}|(- ?){3,}|(_ ?){3,})$/.test(line)) return true
    if (index + 1 < lines.length &&
        root.isTableStart(line, lines[index + 1])) return true
    return false
  }

  function tableCellRequiredHeight(value, availableWidth, bold) {
    tableHeightProbe.width = Math.max(1, Number(availableWidth) || 1)
    tableHeightProbe.font.bold = Boolean(bold)
    tableHeightProbe.text = root.inlineHtml(value)
    return Math.max(1, Number(tableHeightProbe.implicitHeight) || 1)
  }

  function tableMetrics(rows) {
    var columnCount = 0
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      columnCount = Math.max(columnCount, rows[rowIndex].length)
    }

    var widths = []
    var cellPadding = Style.space(7)
    var totalCellPadding = cellPadding * 2
    var characterWidth = root.bodyPixelSize * 0.62
    for (var column = 0; column < columnCount; column++) {
      var longest = 1
      for (var row = 0; row < rows.length; row++) {
        if (rows[row][column] !== undefined) {
          longest = Math.max(longest, String(rows[row][column]).length)
        }
      }
      widths[column] = Math.max(
        Style.space(82),
        Math.min(Style.space(260), longest * characterWidth + totalCellPadding))
    }

    var available = Math.max(1, root.width - root.horizontalPadding * 2)
    var total = widths.reduce(function(sum, width) { return sum + width }, 0)
    if (total > available) {
      var scale = available / total
      for (var scaled = 0; scaled < widths.length; scaled++) {
        widths[scaled] = Math.max(Style.space(62), Math.floor(widths[scaled] * scale))
      }
    }

    var rowHeights = []
    for (var heightRow = 0; heightRow < rows.length; heightRow++) {
      var maxRequiredHeight = root.bodyLineAdvance()
      for (var heightColumn = 0; heightColumn < columnCount; heightColumn++) {
        var cellText = rows[heightRow][heightColumn] || ""
        var usable = Math.max(1, widths[heightColumn] - totalCellPadding)
        maxRequiredHeight = Math.max(maxRequiredHeight,
          root.tableCellRequiredHeight(cellText, usable, heightRow === 0))
      }
      rowHeights.push(Math.ceil(maxRequiredHeight + totalCellPadding + 1))
    }
    return { widths: widths, rowHeights: rowHeights }
  }

  function parseMarkdown(value) {
    var source = String(value || "")
    var lines = source.replace(/\r\n/g, "\n").split("\n")
    var result = []
    var index = 0
    var lineOffsets = []
    var sourceOffset = 0
    for (var offsetLine = 0; offsetLine < lines.length; offsetLine++) {
      lineOffsets.push(sourceOffset)
      sourceOffset += lines[offsetLine].length
      if (offsetLine < lines.length - 1) {
        sourceOffset += source.slice(sourceOffset, sourceOffset + 2) === "\r\n"
          ? 2 : 1
      }
    }
    root.referenceDefinitions = root.referenceDefinitionsForLines(lines)
    var nextReferenceDefinitionsKey = JSON.stringify(root.referenceDefinitions)
    if (nextReferenceDefinitionsKey !== root.referenceDefinitionsKey) {
      root.referenceDefinitionsKey = nextReferenceDefinitionsKey
      root.referenceDefinitionsRevision++
    }

    while (index < lines.length) {
      var line = lines[index]
      var blockStart = lineOffsets[index]
      if (/^\s*$/.test(line)) {
        // Keep every source blank line in the rendered layout. If the row is
        // only created after the caret enters it, the native editor's click
        // target is collapsed and the caret cannot be placed there with the
        // mouse. Give it the complete one-line paragraph height so typing the
        // first character changes its content, not its geometry.
        result.push({
          type: "blank",
          sourceStart: blockStart,
          sourceEnd: blockStart + line.length,
          layoutHeight: root.blankLineLayoutHeight()
        })
        index++
        continue
      }

      if (root.referenceDefinitionForLine(line)) {
        result.push({
          type: "blank",
          sourceStart: blockStart,
          sourceEnd: blockStart + line.length,
          layoutHeight: root.blankLineLayoutHeight()
        })
        index++
        continue
      }

      var fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line)
      if (fence) {
        if (fence[1].charAt(0) === "`" && fence[2].indexOf("`") >= 0) {
          fence = null
        }
      }
      if (fence) {
        var fenceIndent = line.indexOf(fence[1])
        var fenceMarker = fence[1].charAt(0)
        var closingFence = new RegExp(
          "^ {0,3}" + fenceMarker + "{" + fence[1].length + ",}\\s*$")
        var closingIndex = index + 1
        while (closingIndex < lines.length &&
               !closingFence.test(lines[closingIndex])) {
          closingIndex++
        }
        // CommonMark fenced code blocks continue to end-of-document when a
        // matching closing fence is absent. This is also important when
        // opening existing Markdown authored outside JotPin.
        var codeLines = []
        index++
        var codeSourceStart = index < lines.length
          ? lineOffsets[index]
          : blockStart + line.length
        while (index < lines.length && !closingFence.test(lines[index])) {
          codeLines.push(root.normalizedFencedCodeText(
            lines[index], fenceIndent))
          index++
        }
        var codeSourceEnd = codeLines.length > 0
          ? lineOffsets[index - 1] + lines[index - 1].length
          : codeSourceStart
        if (index < lines.length) index++
        result.push({
          type: "code",
          text: codeLines.join("\n"),
          codeIndent: fenceIndent,
          language: root.codeLanguageFromInfo(fence[2]),
          languageLabel: root.codeLanguageLabelFromInfo(fence[2]),
          sourceStart: blockStart,
          sourceEnd: index > 0
            ? lineOffsets[index - 1] + lines[index - 1].length : blockStart,
          codeSourceStart: codeSourceStart,
          codeSourceEnd: codeSourceEnd
        })
        continue
      }

      var standaloneImage = root.standaloneImageData(line)
      if (standaloneImage) {
        result.push({
          type: "image",
          alt: standaloneImage.alt,
          imageSource: root.imageSourceUrl(standaloneImage.url),
          altSourceStart: blockStart + standaloneImage.altSourceStart,
          altSourceEnd: blockStart + standaloneImage.altSourceEnd,
          sourceStart: blockStart,
          sourceEnd: blockStart + line.length
        })
        index++
        continue
      }

      var heading = /^ {0,3}(#{1,6})[ \t]+(.*?)\s*#*\s*$/.exec(line)
      if (heading) {
        var headingPrefix = /^ {0,3}#{1,6}[ \t]+/.exec(line)
        var headingContentStart = headingPrefix ? headingPrefix[0].length : 0
        result.push({
          type: "heading",
          level: heading[1].length,
          html: root.inlineHtml(heading[2]),
          plain: heading[2],
          contentSourceStart: blockStart + headingContentStart,
          contentSourceEnd: blockStart + headingContentStart + heading[2].length,
          sourceStart: blockStart,
          sourceEnd: blockStart + line.length
        })
        index++
        continue
      }

      var setextUnderlineItem = index + 1 < lines.length
        ? root.listItem(lines[index + 1],
          root.activeIncompleteListLine(lines, index + 1, lineOffsets)) : null
      if (index + 1 < lines.length &&
          /^(?: {0,3})(=+|-+)\s*$/.test(lines[index + 1]) &&
          !/^\s*([-+*]|\d+[.)])[ \t]+/.test(line) &&
          !(setextUnderlineItem && setextUnderlineItem.plain === "")) {
        var setextPlain = line.trim()
        var setextContentStart = line.indexOf(setextPlain)
        result.push({
          type: "heading",
          level: lines[index + 1].trim().charAt(0) === "=" ? 1 : 2,
          html: root.inlineHtml(setextPlain),
          plain: setextPlain,
          contentSourceStart: blockStart + Math.max(0, setextContentStart),
          contentSourceEnd: blockStart + Math.max(0, setextContentStart) +
            setextPlain.length,
          sourceStart: blockStart,
          sourceEnd: lineOffsets[index + 1] + lines[index + 1].length
        })
        index += 2
        continue
      }

      if (/^ {0,3}((\* ?){3,}|(- ?){3,}|(_ ?){3,})$/.test(line)) {
        result.push({ type: "rule", sourceStart: blockStart, sourceEnd: blockStart + line.length })
        index++
        continue
      }

      if (index + 1 < lines.length &&
          root.isTableStart(line, lines[index + 1])) {
        var tableRows = [root.splitTableRow(line)]
        var tableColumnCount = tableRows[0].length
        var alignments = root.tableAlignments(lines[index + 1])
        index += 2
        while (index < lines.length && !/^\s*$/.test(lines[index]) &&
               (tableColumnCount === 1 || lines[index].indexOf("|") >= 0) &&
               !(tableColumnCount === 1 &&
                 root.isBlockStart(lines, index, lineOffsets))) {
          var bodyCells = root.splitTableRow(lines[index]).slice(
            0, tableColumnCount)
          while (bodyCells.length < tableColumnCount) bodyCells.push("")
          tableRows.push(bodyCells)
          index++
        }
        var metrics = root.tableMetrics(tableRows)
        var tableData = []
        for (var tableRow = 0; tableRow < tableRows.length; tableRow++) {
          var cells = []
          for (var tableColumn = 0; tableColumn < tableRows[tableRow].length; tableColumn++) {
            cells.push({
              html: root.inlineHtml(tableRows[tableRow][tableColumn]),
              plain: tableRows[tableRow][tableColumn]
            })
          }
          tableData.push(cells)
        }
        result.push({
          type: "table",
          rows: tableData,
          alignments: alignments,
          columnWidths: metrics.widths,
          rowHeights: metrics.rowHeights,
          sourceStart: blockStart,
          sourceEnd: index > 0 ? lineOffsets[index - 1] + lines[index - 1].length : blockStart
        })
        continue
      }

      var firstListItem = root.listItem(line,
        root.activeIncompleteListLine(lines, index, lineOffsets))
      if (firstListItem) {
        var listItems = []
        var baseIndent = firstListItem.indent
        while (index < lines.length) {
          var parsedItem = root.listItem(lines[index],
            root.activeIncompleteListLine(lines, index, lineOffsets))
          if (parsedItem) {
            parsedItem.sourceStart = lineOffsets[index]
            parsedItem.sourceEnd = lineOffsets[index] + lines[index].length
            parsedItem.level = Math.max(0,
              Math.ceil((parsedItem.indent - baseIndent) / 4))
            listItems.push(parsedItem)
            index++
            continue
          }

          var lastListItem = listItems.length > 0
            ? listItems[listItems.length - 1] : null
          var nextListItem = index + 1 < lines.length
            ? root.listItem(lines[index + 1],
                root.activeIncompleteListLine(
                  lines, index + 1, lineOffsets)) : null
          var blankContinuation = /^\s*$/.test(lines[index]) &&
            index + 1 < lines.length &&
            (nextListItem || /^\s+\S/.test(lines[index + 1]))
          var indentedContinuation = /^\s+\S/.test(lines[index])
          if (!lastListItem || (!blankContinuation &&
              !indentedContinuation)) break

          if (blankContinuation) {
            lastListItem.plain += "\n"
            lastListItem.html += "<br>"
          } else {
            var continuation = root.structuralQuoteLine(lines[index])
            lastListItem.plain += "\n" + continuation
            lastListItem.html += "<br>" +
              root.inlineHtmlWithLeadingSpaces(continuation)
          }
          lastListItem.sourceEnd = lineOffsets[index] + lines[index].length
          index++
        }
        result.push({
          type: "list",
          items: listItems,
          sourceStart: blockStart,
          sourceEnd: index > 0 ? lineOffsets[index - 1] + lines[index - 1].length : blockStart
        })
        continue
      }

      if (/^ {0,3}>/.test(line)) {
        var quoteLines = []
        while (index < lines.length && /^ {0,3}>/.test(lines[index])) {
          var quoteLine = lines[index].replace(/^ {0,3}>[ \t]?/, "")
          quoteLines.push(/^\s*$/.test(quoteLine) ? "" :
            root.inlineHtml(root.structuralQuoteLine(quoteLine)))
          index++
        }
        result.push({
          type: "quote",
          html: quoteLines.join("<br>"),
          sourceStart: blockStart,
          sourceEnd: index > 0 ? lineOffsets[index - 1] + lines[index - 1].length : blockStart
        })
        continue
      }

      var paragraphLines = [line]
      index++
      while (index < lines.length &&
             !root.isBlockStart(lines, index, lineOffsets)) {
        paragraphLines.push(lines[index])
        index++
      }
      var paragraphMarkdown = paragraphLines.map(function(paragraphLine) {
        return paragraphLine.replace(/ {2,}$/, "")
      }).join("\n")
      var paragraphHtml = root.inlineHtml(paragraphMarkdown).replace(
        /\n/g, "<br>")
      result.push({
        type: "paragraph",
        html: paragraphHtml,
        sourceLineCount: paragraphLines.length,
        sourceStart: blockStart,
        sourceEnd: index > 0 ? lineOffsets[index - 1] + lines[index - 1].length : blockStart
      })
    }

    return result
  }

  function rebuild() {
    var sourceSnapshot = String(root.sourceText || "")
    var cursorSnapshot = Number(root.cursorPosition)
    var previousSource = String(root.layoutSourceText || "")
    var previousBlocks = root.blocks
    var previousGeometry = root.blockGeometry
    root.layoutReady = false
    root.layoutSourceText = sourceSnapshot
    root.layoutCursorPosition = isFinite(cursorSnapshot) ? cursorSnapshot : -1
    root.layoutRevision++
    root.taskCheckedOverrides = ({})
    var parsedBlocks = root.parseMarkdown(sourceSnapshot)
    for (var blockIndex = 0; blockIndex < parsedBlocks.length; blockIndex++) {
      var block = parsedBlocks[blockIndex]
      block.modelIndex = blockIndex
      block.modelRevision = root.sourceRevision
      block.layoutRevision = root.layoutRevision
      block.modelId = [root.sourceRevision, String(block.type || ""),
        Number(block.sourceStart) || 0, Number(block.sourceEnd) || 0].join(":")
    }
    root.rebuildBlockGeometry(parsedBlocks,
      previousSource !== sourceSnapshot ? previousBlocks : null,
      previousSource !== sourceSnapshot ? previousGeometry : null)
    root.blocks = parsedBlocks
    root.forcedBlockIndex = isFinite(cursorSnapshot) && cursorSnapshot >= 0
      ? root.blockIndexForSourcePosition(cursorSnapshot) : -1
    layoutSettleTimer.restart()
  }

  function invalidateLayout() {
    root.layoutReady = false
    rebuildTimer.restart()
  }

  function taskStateChangePosition(previousValue, nextValue) {
    var previous = String(previousValue || "")
    var next = String(nextValue || "")
    if (previous.length !== next.length || previous === next) return -1
    var changed = -1
    for (var index = 0; index < next.length; index++) {
      if (previous.charAt(index) === next.charAt(index)) continue
      if (changed >= 0) return -1
      changed = index
    }
    if (changed < 0 || " xX".indexOf(previous.charAt(changed)) < 0 ||
        " xX".indexOf(next.charAt(changed)) < 0) return -1

    var lineStart = next.lastIndexOf("\n", Math.max(0, changed - 1)) + 1
    var lineEnd = next.indexOf("\n", changed)
    if (lineEnd < 0) lineEnd = next.length
    var task = /^([ \t]*(?:[-+*]|\d+[.)])[ \t]+\[)([ xX])(\][ \t]+)/.exec(
      next.slice(lineStart, lineEnd))
    if (!task || lineStart + task[1].length !== changed) return -1
    return changed
  }

  function applyTaskStateOnlyChange(previousValue, nextValue) {
    if (!root.layoutReady ||
        root.layoutSourceText !== String(previousValue || "")) return false
    var changed = root.taskStateChangePosition(previousValue, nextValue)
    if (changed < 0) return false

    var nextChecked = String(nextValue).charAt(changed).toLowerCase() === "x"
    var changedItem = null
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var block = root.blocks[blockIndex]
      if (String(block.type || "") !== "list" ||
          changed < Number(block.sourceStart) ||
          changed > Number(block.sourceEnd)) continue
      for (var itemIndex = 0; itemIndex < block.items.length; itemIndex++) {
        var item = block.items[itemIndex]
        if (item.task && changed >= Number(item.sourceStart) &&
            changed <= Number(item.sourceEnd)) {
          item.checked = nextChecked
          changedItem = item
          break
        }
      }
      if (changedItem) break
    }
    if (!changedItem) return false

    var checkedOverrides = Object.assign({}, root.taskCheckedOverrides)
    checkedOverrides["$" + Number(changedItem.sourceStart)] = nextChecked
    root.taskCheckedOverrides = checkedOverrides

    root.layoutSourceText = String(nextValue || "")
    root.layoutCursorPosition = Number(root.cursorPosition)
    for (var revisionIndex = 0;
         revisionIndex < root.blocks.length; revisionIndex++) {
      var revisionBlock = root.blocks[revisionIndex]
      revisionBlock.modelRevision = root.sourceRevision
      revisionBlock.modelId = [root.sourceRevision,
        String(revisionBlock.type || ""),
        Number(revisionBlock.sourceStart) || 0,
        Number(revisionBlock.sourceEnd) || 0].join(":")
    }
    root.taskStateRevision++
    Qt.callLater(function() {
      root.rebuildSelection()
      root.layoutUpdated()
    })
    return true
  }

  function richTextContentChanged() {
    if (!root.layoutReady) return
    // Images may arrive after the initial rich-text layout. Re-settle the
    // existing source revision so block heights, selection, and caret geometry
    // follow the loaded image without reparsing the note.
    root.layoutReady = false
    layoutSettleTimer.restart()
  }

  function viewportContentChanged() {
    if (!root.viewportRenderingEnabled || viewportSettleTimer.running) return
    // Scrolling can cross several block boundaries in one frame. Hydrate the
    // newest overscan window first, then publish selection/caret geometry once
    // after the Column has polished its corrected spacer heights.
    viewportSettleTimer.start()
  }

  function layoutMatchesCurrentInput() {
    return root.layoutSourceText === String(root.sourceText || "") &&
      root.layoutCursorPosition === Number(root.cursorPosition)
  }

  function sourceLineAt(position) {
    var source = String(root.sourceText || "")
    var requested = Math.max(0, Math.min(Number(position) || 0, source.length))
    var start = source.lastIndexOf("\n", Math.max(0, requested - 1)) + 1
    var end = source.indexOf("\n", requested)
    if (end < 0) end = source.length
    return source.slice(start, end)
  }

  function cursorSensitiveLine(position) {
    var line = root.sourceLineAt(position)
    // Blank rows are always represented by parseMarkdown, so moving the
    // caret into one does not change the rendered layout. Rebuilding here
    // during a drag briefly made hit testing return source position 0.
    return /^\s*([-+*]|\d+[.)])$/.test(line)
  }

  function cursorMovementRequiresRebuild(previousPosition, nextPosition) {
    return root.cursorSensitiveLine(previousPosition) ||
      root.cursorSensitiveLine(nextPosition)
  }

  function beginMouseSelection() {
    mouseSelectionFrameTimer.stop()
    root.mouseSelectionUpdatePending = false
    root.pendingMouseSelectionAnchor = -1
    root.mouseSelectionActive = true
  }

  function requestMouseSelection(anchorPosition, pointX, pointY) {
    if (!root.mouseSelectionActive) return
    root.pendingMouseSelectionAnchor = Number(anchorPosition)
    root.pendingMouseSelectionX = Number(pointX) || 0
    root.pendingMouseSelectionY = Number(pointY) || 0
    root.mouseSelectionUpdatePending = true
    // Keep only the newest pointer coordinate and resolve at most once per
    // display frame. This prevents queued mouse events from building an
    // increasingly stale trail behind the pointer.
    if (!mouseSelectionFrameTimer.running) mouseSelectionFrameTimer.start()
  }

  function flushMouseSelection() {
    if (!root.mouseSelectionUpdatePending ||
        root.pendingMouseSelectionAnchor < 0) return false
    var anchor = root.pendingMouseSelectionAnchor
    var pointX = root.pendingMouseSelectionX
    var pointY = root.pendingMouseSelectionY
    root.mouseSelectionUpdatePending = false
    root.sourceSelectionRequested(anchor,
      root.sourcePositionForPoint(pointX, pointY))
    return true
  }

  function endMouseSelection() {
    if (!root.mouseSelectionActive) return
    mouseSelectionFrameTimer.stop()
    root.flushMouseSelection()
    root.mouseSelectionActive = false
    if (root.cursorSensitiveLine(root.cursorPosition)) {
      root.invalidateLayout()
    } else {
      // Publish the final caret once. Publishing on every drag event floods
      // the event queue and makes the highlight trail behind the pointer.
      Qt.callLater(function() { root.layoutUpdated() })
    }
  }

  function cursorMoved() {
    var nextPosition = Number(root.cursorPosition)
    var sourceMatches = root.layoutSourceText === String(root.sourceText || "")
    var sensitive = root.cursorMovementRequiresRebuild(
      root.layoutCursorPosition, nextPosition)

    // Keep the last settled geometry usable while a press-drag selection is
    // in progress. The source cursor can pass through a bare list marker, but
    // reparsing at that moment would make sourcePositionForPoint fall back to
    // zero before the next mouse event and select the entire prefix of a note.
    if (isFinite(nextPosition)) {
      root.forcedBlockIndex = root.blockIndexForSourcePosition(nextPosition)
    }

    if (root.mouseSelectionActive && isFinite(nextPosition) &&
        root.layoutReady && sourceMatches) {
      root.layoutCursorPosition = nextPosition
      return
    }

    if (!isFinite(nextPosition) || !root.layoutReady ||
        !sourceMatches || sensitive) {
      root.invalidateLayout()
      return
    }

    root.layoutCursorPosition = nextPosition
    Qt.callLater(function() { root.layoutUpdated() })
  }

  function selectionIntersects(start, end, selectionStartValue, selectionEndValue) {
    return selectionEndValue > start && selectionStartValue < end
  }

  function appendSelectionRect(rects, x, y, width, height) {
    if (!isFinite(x) || !isFinite(y) || !isFinite(width) ||
        !isFinite(height) || width <= 0 || height <= 0) return
    rects.push({
      x: x,
      y: y,
      width: width,
      height: height
    })
  }

  function appendSelectedNewlineRects(rects, start, end) {
    var source = String(root.sourceText || "")
    var contentWidth = Math.max(
      Style.space(2), root.width - root.horizontalPadding * 2)

    // Blank source rows are already represented as blocks. Walk those blocks
    // instead of every selected source byte so a long drag stays cheap.
    var previousGapTop = -1
    var previousGapBottom = -1
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var blankBlock = root.blocks[blockIndex]
      if (blankBlock.type !== "blank") continue
      var blankBlockItem = blockRepeater.itemAt(blockIndex)
      if (root.viewportRenderingEnabled &&
          (!blankBlockItem || !blankBlockItem.contentActive)) continue
      var position = Number(blankBlock.sourceEnd)
      if (!isFinite(position) || source.charAt(position) !== "\n" ||
          position < start || position >= end) continue

      // Native TextEdit selection overlays handle ordinary text rows,
      // including their line breaks. Only paint the vertical gap belonging to
      // a genuinely blank Markdown row here; extending every selected newline
      // to the editor edge is what made Live selection look like oversized
      // block bars.
      var previousBlockIndex = blockIndex - 1
      while (previousBlockIndex >= 0 &&
             root.blocks[previousBlockIndex].type === "blank") {
        previousBlockIndex--
      }
      var nextBlockIndex = blockIndex + 1
      while (nextBlockIndex < root.blocks.length &&
             root.blocks[nextBlockIndex].type === "blank") {
        nextBlockIndex++
      }

      var previousBlockItem = previousBlockIndex >= 0
        ? blockRepeater.itemAt(previousBlockIndex) : null
      var nextBlockItem = nextBlockIndex >= 0
        ? blockRepeater.itemAt(nextBlockIndex) : null
      var previousBottom = previousBlockItem
        ? displayColumn.y + previousBlockItem.y + previousBlockItem.height
        : displayColumn.y
      var nextTop = nextBlockItem
        ? displayColumn.y + nextBlockItem.y
        : previousBottom + root.blockSpacing

      if (nextTop > previousBottom &&
          (previousBottom !== previousGapBottom || nextTop !== previousGapTop)) {
        root.appendSelectionRect(
          rects,
          root.horizontalPadding,
          previousBottom,
          contentWidth,
          nextTop - previousBottom)
        previousGapBottom = previousBottom
        previousGapTop = nextTop
      }
    }
  }

  function paragraphPlainPrefix(value, sourcePosition) {
    var raw = String(value || "")
    var position = Number(sourcePosition)
    if (!isFinite(position)) position = raw.length
    position = Math.max(0, Math.min(position, raw.length))

    return root.plainInlinePrefix(raw, position).replace(/ {2,}\n/g, "\n")
  }

  function quotePlainPrefix(value, sourcePosition) {
    var raw = String(value || "")
    var position = Number(sourcePosition)
    if (!isFinite(position)) position = raw.length
    position = Math.max(0, Math.min(position, raw.length))

    var result = ""
    var lineStart = 0
    while (lineStart < position) {
      var lineEnd = raw.indexOf("\n", lineStart)
      if (lineEnd < 0) lineEnd = raw.length
      var line = raw.slice(lineStart, lineEnd)
      if (line.charAt(line.length - 1) === "\r") line = line.slice(0, -1)
      var prefixMatch = /^ {0,3}>[ \t]?/.exec(line)
      var contentStart = prefixMatch ? prefixMatch[0].length : 0
      var column = Math.max(0, Math.min(line.length - contentStart,
        position - lineStart - contentStart))
      if (column > 0) {
        result += root.plainInlinePrefix(
          line.slice(contentStart), column)
      }
      if (lineEnd < raw.length && position > lineEnd) result += "\n"
      if (lineEnd >= raw.length) break
      lineStart = lineEnd + 1
    }
    return result
  }

  function structuralQuoteLine(value) {
    var remaining = String(value || "")
    var prefix = ""
    while (true) {
      var nested = /^(\s*)>([ \t]?)/.exec(remaining)
      if (!nested) break
      prefix += nested[1] + "│" + nested[2]
      remaining = remaining.slice(nested[0].length)
    }
    remaining = remaining.replace(/^((?:[ \t]|│)*)([-+*])([ \t]+)/,
      "$1•$3")
    return prefix + remaining
  }

  function inlineHtmlWithLeadingSpaces(value) {
    var raw = String(value || "")
    var leading = /^ */.exec(raw)[0].length
    var prefix = ""
    for (var index = 0; index < leading; index++) prefix += "&nbsp;"
    return prefix + root.inlineHtml(raw.slice(leading))
  }

  function selectionTargetOffset(target, sourcePosition) {
    var item = target || {}
    var sourceStart = Math.max(0, Number(item.sourceStart) || 0)
    var sourceEnd = Math.max(sourceStart,
      Math.min(root.sourceText.length, Number(item.sourceEnd) || sourceStart))
    var position = Number(sourcePosition)
    if (!isFinite(position)) position = sourceStart
    position = Math.max(sourceStart, Math.min(sourceEnd, position))
    var source = root.sourceText.slice(sourceStart, sourceEnd)
    var localPosition = position - sourceStart

    if (item.kind === "paragraph") {
      return root.paragraphPlainPrefix(source, localPosition).length
    }
    if (item.kind === "quote") {
      return root.quotePlainPrefix(source, localPosition).length
    }
    if (item.kind === "code") {
      return root.normalizedFencedCodeText(
        source.slice(0, localPosition), item.codeIndent).length
    }
    return root.plainInlinePrefix(source, localPosition).length
  }

  function selectionRangeForTargetSource(target, startValue, endValue) {
    var item = target || {}
    var start = Math.min(Number(startValue), Number(endValue))
    var end = Math.max(Number(startValue), Number(endValue))
    var sourceStart = Number(item.sourceStart) || 0
    var sourceEnd = Number(item.sourceEnd) || sourceStart
    if (!isFinite(start) || !isFinite(end) || end <= start ||
        end <= sourceStart || start >= sourceEnd) {
      return { start: 0, end: 0 }
    }

    var visibleStart = root.selectionTargetOffset(item,
      Math.max(start, sourceStart))
    var visibleEnd = root.selectionTargetOffset(item,
      Math.min(end, sourceEnd))
    var visibleLength = Math.max(0, Number(item.visibleLength) || 0)
    return {
      start: Math.max(0, Math.min(visibleLength, visibleStart)),
      end: Math.max(0, Math.min(visibleLength, visibleEnd))
    }
  }

  function selectionRangeForTarget(target) {
    return root.selectionRangeForTargetSource(
      target, root.selectionStart, root.selectionEnd)
  }

  function appendSelectionTarget(targets, kind, sourceStart, sourceEnd,
                                 html, x, y, width, height, pixelSize,
                                 bold, lineHeight, selectionZ, codeIndent) {
    var start = Number(sourceStart)
    var end = Number(sourceEnd)
    if (!isFinite(start) || !isFinite(end) || end < start ||
        !isFinite(Number(x)) || !isFinite(Number(y)) ||
        !isFinite(Number(width)) || !isFinite(Number(height)) ||
        Number(width) <= 0 || Number(height) <= 0) return

    var target = {
      kind: kind,
      sourceStart: start,
      sourceEnd: end,
      html: String(html || ""),
      x: Number(x),
      y: Number(y),
      width: Number(width),
      height: Number(height),
      pixelSize: Number(pixelSize) || root.bodyPixelSize,
      bold: Boolean(bold),
      lineHeight: Number(lineHeight) || root.bodyLineHeightFactor,
      selectionZ: Number(selectionZ) || 0.5
    }
    if (kind === "code") target.codeIndent = Number(codeIndent) || 0
    target.visibleLength = root.selectionTargetOffset(target, end)
    targets.push(target)
  }

  function selectionMirrorVerticalScale(targetHeight, nativeContentHeight) {
    var target = Number(targetHeight)
    var nativeHeight = Number(nativeContentHeight)
    // This is a ratio of two measured logical-content heights, not a device
    // or display scale. It therefore follows each user's font metrics and
    // compositor scale without assuming a particular pixel density.
    return isFinite(target) && target > 0 &&
      isFinite(nativeHeight) && nativeHeight > 0
      ? target / nativeHeight : 1
  }

  function tableCellSourceRange(blockValue, rowIndex, columnIndex) {
    var block = blockValue || {}
    var sourceStart = Number(block.sourceStart) || 0
    var sourceEnd = Number(block.sourceEnd) || sourceStart
    var source = root.sourceText.slice(sourceStart, sourceEnd)
    var lines = source.split("\n")
    var lineIndex = Number(rowIndex) === 0 ? 0 : Number(rowIndex) + 1
    if (lineIndex < 0 || lineIndex >= lines.length) return null

    var lineStart = 0
    for (var index = 0; index < lineIndex; index++) {
      lineStart += lines[index].length + 1
    }
    var line = lines[lineIndex]
    if (line.charAt(line.length - 1) === "\r") line = line.slice(0, -1)
    var cells = root.splitTableRow(line)
    var searchStart = line.charAt(0) === "|" ? 1 : 0
    for (var cellIndex = 0; cellIndex < cells.length; cellIndex++) {
      var cell = String(cells[cellIndex] || "")
      var found = line.indexOf(cell, searchStart)
      if (found < 0) found = searchStart
      if (cellIndex === Number(columnIndex)) {
        return {
          start: sourceStart + lineStart + found,
          end: sourceStart + lineStart + found + cell.length
        }
      }
      searchStart = found + cell.length
    }
    return null
  }

  function rebuildSelectionTargets() {
    var targets = []
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var block = root.blocks[blockIndex]
      var blockItem = blockRepeater.itemAt(blockIndex)
      if (!blockItem || !blockItem.contentActive) continue
      var originX = displayColumn.x
      var originY = displayColumn.y + Number(blockItem.y || 0)

      if (block.type === "heading") {
        var headingTextItem = blockItem.headingTextReference
        if (!headingTextItem) continue
        var headingSource = root.sourceText.slice(
          block.sourceStart, block.sourceEnd)
        var firstLineEnd = headingSource.indexOf("\n")
        if (firstLineEnd < 0) firstLineEnd = headingSource.length
        var firstLine = headingSource.slice(0, firstLineEnd)
        var headingPrefix = /^ {0,3}#{1,6}[ \t]+/.exec(firstLine)
        var headingMatch = /^ {0,3}#{1,6}[ \t]+(.*?)\s*#*\s*$/.exec(firstLine)
        var headingContentStart = headingPrefix
          ? headingPrefix[0].length : 0
        var headingContent = headingMatch
          ? headingMatch[1] : firstLine.slice(headingContentStart)
        if (!headingMatch && !headingPrefix) {
          var leadingWhitespace = /^\s*/.exec(firstLine)
          headingContentStart = leadingWhitespace
            ? leadingWhitespace[0].length : 0
          headingContent = firstLine.trim()
        }
        var headingStart = block.sourceStart + headingContentStart
        root.appendSelectionTarget(
          targets, "inline", headingStart, headingStart + headingContent.length,
          block.html, originX + Number(headingTextItem.x || 0),
          originY + Number(headingTextItem.y || 0), headingTextItem.width,
          headingTextItem.height, root.bodyPixelSize *
            (block.level === 1 ? 1.55 : block.level === 2 ? 1.3 : 1.15),
          true, root.bodyLineHeightFactor, 0.5)
        continue
      }

      if (block.type === "paragraph") {
        var paragraphTextItem = blockItem.paragraphTextReference
        if (!paragraphTextItem) continue
        root.appendSelectionTarget(
          targets, "paragraph", block.sourceStart, block.sourceEnd,
          block.html, originX + Number(paragraphTextItem.x || 0),
          originY + Number(paragraphTextItem.y || 0), paragraphTextItem.width,
          paragraphTextItem.height, root.bodyPixelSize, false,
          root.bodyLineHeightFactor, 0.5)
        continue
      }

      if (block.type === "list") {
        var listView = blockItem.listViewReference
        if (!listView) continue
        for (var itemIndex = 0; itemIndex < block.items.length; itemIndex++) {
          var item = block.items[itemIndex]
          var listItem = listView.itemAtIndex(itemIndex)
          if (!listItem || !listItem.itemTextReference) continue
          var contentStart = root.listItemContentStart(item)
          var itemText = listItem.itemTextReference
          root.appendSelectionTarget(
            targets, "inline", item.sourceStart + contentStart,
            item.sourceStart + contentStart + String(item.plain || "").length,
            item.html, originX + Number(listView.x || 0) +
              Number(listItem.textOriginX || 0),
            originY + Number(listView.y || 0) + Number(listItem.y || 0) +
              Number(listItem.textOriginY || 0), itemText.width,
            itemText.height, root.bodyPixelSize, false,
            root.bodyLineHeightFactor, 0.5)
        }
        continue
      }

      if (block.type === "quote") {
        var quoteTextItem = blockItem.quoteTextReference
        var quoteContentItem = blockItem.quoteContentReference
        if (!quoteTextItem || !quoteContentItem) continue
        root.appendSelectionTarget(
          targets, "quote", block.sourceStart, block.sourceEnd,
          block.html, originX + Number(quoteContentItem.x || 0) +
            Number(quoteTextItem.x || 0),
          originY + Number(quoteContentItem.y || 0) +
            Number(quoteTextItem.y || 0), quoteTextItem.width,
          quoteTextItem.height, root.bodyPixelSize, false,
          root.bodyLineHeightFactor, 0.5)
        continue
      }

      if (block.type === "table") {
        var tableContentItem = blockItem.tableReference
        if (!tableContentItem || !blockItem.tableRowsReference) continue
        for (var rowIndex = 0; rowIndex < block.rows.length; rowIndex++) {
          var tableRowItem = blockItem.tableRowsReference.itemAt(rowIndex)
          if (!tableRowItem || !tableRowItem.cellRepeaterReference) continue
          for (var columnIndex = 0;
               columnIndex < block.rows[rowIndex].length; columnIndex++) {
            var cellItem = tableRowItem.cellRepeaterReference.itemAt(columnIndex)
            var cellTextItem = cellItem && cellItem.cellTextReference
            var cellRange = root.tableCellSourceRange(
              block, rowIndex, columnIndex)
            if (!cellItem || !cellTextItem || !cellRange) continue
            root.appendSelectionTarget(
              targets, "inline", cellRange.start, cellRange.end,
              block.rows[rowIndex][columnIndex].html,
              originX + Number(tableContentItem.x || 0) +
                Number(tableRowItem.x || 0) + Number(cellItem.x || 0) +
                Number(cellTextItem.x || 0),
              originY + Number(tableContentItem.y || 0) +
                Number(tableRowItem.y || 0) + Number(cellItem.y || 0) +
                Number(cellTextItem.y || 0), cellTextItem.width,
              cellTextItem.height, root.bodyPixelSize,
              rowIndex === 0, root.bodyLineHeightFactor, 1.5)
          }
        }
        continue
      }

      if (block.type === "code") {
        var codeTextItem = blockItem.codeTextReference
        var codeContentItem = blockItem.codeReference
        if (!codeTextItem || !codeContentItem) continue
        root.appendSelectionTarget(
          targets, "code", block.codeSourceStart, block.codeSourceEnd,
          block.text, originX + Number(codeContentItem.x || 0) +
            Number(codeTextItem.x || 0),
          originY + Number(codeContentItem.y || 0) +
            Number(codeTextItem.y || 0), codeTextItem.width,
          codeTextItem.height, root.bodyPixelSize, false,
          root.bodyLineHeightFactor, 1.5,
          block.codeIndent)
      }
    }
    root.selectionTargets = targets
  }

  function scheduleSelectionUpdate() {
    // Coalesce rapid drag events into the next event-loop turn without
    // repeatedly postponing an already scheduled highlight paint.
    if (!selectionUpdateTimer.running) selectionUpdateTimer.start()
  }

  function rebuildSelection() {
    var start = Math.min(Number(root.selectionStart), Number(root.selectionEnd))
    var end = Math.max(Number(root.selectionStart), Number(root.selectionEnd))
    var rects = []
    if (!isFinite(start) || !isFinite(end) || end <= start) {
      root.selectionRects = rects
      return
    }

    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var block = root.blocks[blockIndex]
      if (block.sourceStart === undefined || block.sourceEnd === undefined ||
          !root.selectionIntersects(block.sourceStart, block.sourceEnd, start, end)) {
        continue
      }

      // TextEdit selection overlays own the glyph-accurate highlight for all
      // text-bearing blocks. The fallback layer is deliberately limited to
      // visual objects that do not have a text selection surface of their own.
      if (block.type === "heading" || block.type === "paragraph" ||
          block.type === "list" || block.type === "quote" ||
          block.type === "table" || block.type === "code") {
        continue
      }

      var blockItem = blockRepeater.itemAt(blockIndex)
      if (!blockItem || !blockItem.contentActive) continue
      var originX = displayColumn.x
      var originY = displayColumn.y + blockItem.y

      if (block.type === "image") {
        var imageSurface = blockItem.imageContentReference
        if (imageSurface) {
          var imageWidth = Number(imageSurface.renderedWidth) ||
            Math.max(Style.space(2), Number(imageSurface.width) || 0)
          var imageHeight = Number(imageSurface.height) ||
            root.bodyTextGlyphHeight()
          root.appendSelectionRect(
            rects,
            originX + Number(imageSurface.x || 0),
            originY + Number(imageSurface.y || 0),
            Math.max(Style.space(2), imageWidth),
            Math.max(Style.space(2), imageHeight))
        }
        continue
      }

      if (block.type === "rule") {
        root.appendSelectionRect(
          rects,
          originX + blockItem.ruleReference.x,
          originY + blockItem.ruleReference.y,
          blockItem.ruleReference.width,
          blockItem.ruleReference.height)
      }
    }
    root.appendSelectedNewlineRects(rects, start, end)
    root.selectionRects = rects
  }

  function appendTextRangeRectangle(rects, xValue, yValue,
                                    endXValue, heightValue) {
    var x = Number(xValue)
    var y = Number(yValue)
    var endX = Number(endXValue)
    var height = Number(heightValue)
    if (!isFinite(x) || !isFinite(y) || !isFinite(endX) ||
        !isFinite(height) || endX <= x || height <= 0) return
    var previous = rects.length > 0 ? rects[rects.length - 1] : null
    if (previous && Math.abs(Number(previous.y) - y) < 0.75 &&
        x <= Number(previous.x) + Number(previous.width) + 1) {
      previous.width = Math.max(Number(previous.width), endX - previous.x)
      previous.height = Math.max(Number(previous.height), height)
      return
    }
    rects.push({x: x, y: y, width: endX - x, height: height})
  }

  function attachTextRangeUnderlineBaselines(rects, startValue, endValue) {
    var start = Math.max(0, Number(startValue) || 0)
    var end = Math.max(start, Number(endValue) || start)
    for (var position = start; position < end; position++) {
      var caret = root.cursorRectangleForSource(position)
      if (!caret || Number(caret.height) <= 0) continue
      var caretCenterY = Number(caret.y) + Number(caret.height) / 2
      var caretCenterX = Number(caret.x) + Number(caret.width) / 2
      for (var rectIndex = 0; rectIndex < rects.length; rectIndex++) {
        var rect = rects[rectIndex]
        if (caretCenterY < Number(rect.y) - 1 ||
            caretCenterY > Number(rect.y) + Number(rect.height) + 1 ||
            caretCenterX < Number(rect.x) - 1 ||
            caretCenterX > Number(rect.x) + Number(rect.width) + 1) continue
        // The selection mirror rectangle covers the full proportional line
        // box. Anchor spelling decoration to the much tighter visible caret
        // band so the squiggle sits directly below the glyphs.
        rect.underlineY = Number(caret.y) + Number(caret.height) -
          Math.max(0.5, Number(caret.height) * 0.04)
        break
      }
    }
    return rects
  }

  function sourceRangeRectangles(startValue, endValue) {
    var start = Math.max(0, Math.min(root.sourceText.length,
      Math.min(Number(startValue), Number(endValue))))
    var end = Math.max(start, Math.min(root.sourceText.length,
      Math.max(Number(startValue), Number(endValue))))
    var rects = []
    if (!isFinite(start) || !isFinite(end) || end <= start ||
        !root.layoutReady || !root.layoutMatchesCurrentInput()) return rects

    for (var targetIndex = 0;
         targetIndex < root.selectionTargets.length; targetIndex++) {
      var target = root.selectionTargets[targetIndex]
      if (!root.selectionIntersects(
          target.sourceStart, target.sourceEnd, start, end)) continue
      var textItem = selectionMirrorRepeater.itemAt(targetIndex)
      if (!textItem || !textItem.positionToRectangle) continue
      var range = root.selectionRangeForTargetSource(target, start, end)
      var visibleStart = Math.max(0,
        Math.min(Number(textItem.length) || 0, Number(range.start) || 0))
      var visibleEnd = Math.max(visibleStart,
        Math.min(Number(textItem.length) || 0, Number(range.end) || 0))
      var yScale = root.selectionMirrorVerticalScale(
        Number(target.height) || 0, Number(textItem.contentHeight) || 0)
      for (var offset = visibleStart; offset < visibleEnd; offset++) {
        var nativeRect = textItem.positionToRectangle(offset)
        var nextRect = textItem.positionToRectangle(offset + 1)
        if (!nativeRect || !nextRect) continue
        var x = Number(target.x) + Number(nativeRect.x || 0)
        var y = Number(target.y) + Number(nativeRect.y || 0) * yScale
        var height = Math.max(1, Number(nativeRect.height) * yScale || 1)
        var nextSameLine = Math.abs(
          Number(nextRect.y) - Number(nativeRect.y)) < 0.75 &&
          Number(nextRect.x) >= Number(nativeRect.x)
        var endX = nextSameLine
          ? Number(target.x) + Number(nextRect.x)
          : x + Math.max(2, root.cursorWidth(
              textItem.getText(offset, offset + 1),
              Number(target.pixelSize) || root.bodyPixelSize))
        root.appendTextRangeRectangle(rects, x, y, endX, height)
      }
    }

    if (rects.length > 0)
      return root.attachTextRangeUnderlineBaselines(rects, start, end)

    // Standalone image captions do not use the rich-text selection mirrors.
    // Keep a source-caret fallback for those plain-text ranges only.
    for (var position = start; position < end; position++) {
      var rect = root.cursorRectangleForSource(position)
      var next = root.cursorRectangleForSource(position + 1)
      if (!rect || !next || Number(rect.height) <= 0) continue
      var sameLine = Math.abs(Number(next.y) - Number(rect.y)) < 0.75 &&
        Number(next.x) >= Number(rect.x)
      var fallbackEndX = sameLine ? Number(next.x) :
        Number(rect.x) + Math.max(2, root.cursorWidth(
          root.sourceText.slice(position, position + 1), root.bodyPixelSize))
      root.appendTextRangeRectangle(rects,
        Number(rect.x), Number(rect.y), fallbackEndX, Number(rect.height))
    }
    return root.attachTextRangeUnderlineBaselines(rects, start, end)
  }

  function plainInline(value) {
    var raw = String(value || "")
    return root.plainInlinePrefix(raw, raw.length)
  }

  function estimatedWrappedLineCount(value, availableWidth, pixelSize) {
    var text = String(value || "")
    var width = Math.max(1, Number(availableWidth) || 1)
    var size = Math.max(1, Number(pixelSize) || root.bodyPixelSize)
    // JotPin's configured editor font is monospace. Keep the estimate
    // deliberately conservative so a newly hydrated block normally shrinks
    // slightly instead of pushing a large unseen block into the viewport.
    var columns = Math.max(1, Math.floor(width / (size * 0.62)))
    var lines = text.replace(/\r\n/g, "\n").split("\n")
    var count = 0
    for (var index = 0; index < lines.length; index++) {
      count += Math.max(1, Math.ceil(lines[index].length / columns))
    }
    return Math.max(1, count)
  }

  function estimatedBlockHeight(blockValue, availableWidth) {
    var block = blockValue || {}
    var width = Math.max(1, Number(availableWidth) || 1)
    if (block.type === "blank") return Number(block.layoutHeight) || 0
    if (block.type === "rule") return Math.max(1, Style.space(1))
    if (block.type === "table") {
      var tableHeight = 0
      var rowHeights = block.rowHeights || []
      for (var row = 0; row < rowHeights.length; row++) {
        tableHeight += Math.max(1, Number(rowHeights[row]) || 0)
      }
      return Math.max(root.bodyLineAdvance(), tableHeight)
    }
    if (block.type === "code") {
      var codeHeight = root.codeSourceLineCount(block) *
        root.bodyLineAdvance() + Style.space(20)
      if (String(block.languageLabel || "") !== "") {
        codeHeight += Math.max(10, root.bodyPixelSize * 0.72) + Style.space(5)
      }
      return Math.max(root.bodyLineAdvance(), Math.ceil(codeHeight))
    }
    if (block.type === "image") {
      var altText = String(block.alt || "")
      var altCaptionHeight = altText === "" ? 0 :
        root.estimatedWrappedLineCount(altText, width, root.bodyPixelSize) *
          root.bodyLineAdvance() + Style.space(6)
      return Math.max(root.bodyLineAdvance(),
        root.bodyLineAdvance() + Style.space(12) + altCaptionHeight)
    }
    if (block.type === "list") {
      var listHeight = 0
      var items = block.items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        var item = items[itemIndex] || {}
        var itemWidth = Math.max(1, width -
          (Number(item.level) || 0) * Style.space(24) - Style.space(29))
        listHeight += root.estimatedWrappedLineCount(
          root.plainInline(item.plain || ""), itemWidth,
          root.bodyPixelSize) * root.bodyLineAdvance()
      }
      return Math.max(root.bodyLineAdvance(), Math.ceil(listHeight))
    }

    var pixelSize = root.bodyPixelSize
    var lineHeightFactor = root.bodyLineHeightFactor
    var source = root.sourceText.slice(
      Number(block.sourceStart) || 0, Number(block.sourceEnd) || 0)
    if (block.type === "heading") {
      pixelSize *= block.level === 1 ? 1.55 : block.level === 2 ? 1.3 : 1.15
      lineHeightFactor = root.bodyLineHeightFactor
      source = String(block.plain || source)
    } else if (block.type === "quote") {
      width = Math.max(1, width - Style.space(12))
      source = root.quotePlainPrefix(source, source.length)
    } else {
      source = root.plainInline(source)
    }
    return Math.max(1, Math.ceil(root.estimatedWrappedLineCount(
      source, width, pixelSize) * pixelSize * lineHeightFactor))
  }

  function stablePreviousBlockHeight(blockIndex, blockValue,
      previousBlocks, previousGeometry) {
    var index = Number(blockIndex)
    if (!previousBlocks || !previousGeometry || !isFinite(index) ||
        index < 0 || index >= previousBlocks.length ||
        index >= previousGeometry.length) return 0
    var previousBlock = previousBlocks[index] || {}
    var nextBlock = blockValue || {}
    if (String(previousBlock.type || "") !== String(nextBlock.type || ""))
      return 0
    var previousEntry = previousGeometry[index] || {}
    return Math.max(0, Number(previousEntry.height) || 0)
  }

  function rebuildBlockGeometry(blockValues, previousBlocks,
      previousGeometry) {
    var values = blockValues || []
    var availableWidth = Math.max(1,
      root.width - root.horizontalPadding * 2)
    var entries = []
    var top = 0
    for (var index = 0; index < values.length; index++) {
      var cacheKey = root.measuredBlockHeightCacheKey(
        values[index], availableWidth)
      values[index].heightCacheKey = cacheKey
      var cachedHeight = root.cachedMeasuredBlockHeight(
        cacheKey, values[index])
      var estimate = Math.max(0,
        Number(root.estimatedBlockHeight(values[index], availableWidth)) || 0)
      var stableHeight = cachedHeight > 0 ? 0 :
        root.stablePreviousBlockHeight(index, values[index],
          previousBlocks, previousGeometry)
      var initialHeight = cachedHeight > 0 ? cachedHeight :
        stableHeight > 0 ? stableHeight : estimate
      entries.push({
        blockIndex: index,
        top: top,
        height: initialHeight,
        estimatedHeight: estimate,
        measuredHeight: cachedHeight > 0 ? cachedHeight : stableHeight,
        provisionalHeight: stableHeight,
        exact: cachedHeight > 0 || values[index].type === "blank" ||
          values[index].type === "rule" || values[index].type === "table"
      })
      top += initialHeight
      if (index < values.length - 1) top += root.blockSpacing
    }
    root.blockGeometry = entries
    root.blockGeometryRevision++
  }

  function geometryStableBlockSource(blockType, sourceValue) {
    var source = String(sourceValue || "")
    if (String(blockType || "") !== "list") return source
    // Checked state is painted inside a fixed-size checkbox and cannot alter
    // list geometry. Canonicalize only that one source character so toggling
    // a task can reuse the already measured block height instead of briefly
    // falling back to an estimate and shifting neighboring text.
    return source.replace(
      /^([ \t]*(?:[-+*]|\d+[.)])[ \t]+\[)[ xX](\][ \t]+)/gm,
      "$1 $2")
  }

  function measuredBlockHeightSource(blockValue) {
    var block = blockValue || {}
    var start = Math.max(0, Number(block.sourceStart) || 0)
    var end = Math.max(start, Number(block.sourceEnd) || start)
    return root.geometryStableBlockSource(
      block.type, root.sourceText.slice(start, end))
  }

  function measuredBlockHeightCacheKeyForSource(blockType, sourceValue,
      availableWidth) {
    var raw = root.geometryStableBlockSource(blockType, sourceValue)
    return "$" + root.referenceDefinitionsRevision + "\u0000" +
      Math.round(Number(availableWidth) * 100) + "\u0000" +
      root.bodyPixelSize + "\u0000" + root.fontFamily + "\u0000" +
      String(root.baseUrl || "") + "\u0000" + String(blockType || "") +
      "\u0000" + raw.length + "\u0000" +
      root.measuredBlockHeightSourceHash(raw)
  }

  function measuredBlockHeightCacheKey(blockValue, availableWidth) {
    var block = blockValue || {}
    return root.measuredBlockHeightCacheKeyForSource(
      block.type, root.measuredBlockHeightSource(block), availableWidth)
  }

  function measuredBlockHeightSourceHash(value) {
    var source = String(value || "")
    var hash = 2166136261
    for (var index = 0; index < source.length; index++) {
      hash ^= source.charCodeAt(index)
      // `Math.imul` keeps the multiplication in a deterministic 32-bit lane.
      hash = Math.imul(hash, 16777619)
    }
    return (hash >>> 0).toString(36)
  }

  function cachedMeasuredBlockHeight(cacheKey, blockValue) {
    var entry = root.measuredBlockHeightCache.entries[String(cacheKey || "")]
    if (!entry) return 0
    var raw = root.measuredBlockHeightSource(blockValue)
    return entry.source === raw
      ? Math.max(0, Number(entry.height) || 0) : 0
  }

  function rememberMeasuredBlockHeight(blockIndex, measuredHeight) {
    var index = Number(blockIndex)
    if (!isFinite(index) || index < 0 || index >= root.blocks.length) return
    var block = root.blocks[index]
    var key = String(block.heightCacheKey || "")
    if (key === "") return
    var cache = root.measuredBlockHeightCache
    var raw = root.measuredBlockHeightSource(block)
    var rawLength = raw.length
    var existing = cache.entries[key]
    if (existing && existing.source === raw) {
      existing.height = Number(measuredHeight)
      return
    }
    // A 32-bit hash collision must degrade to an uncached measurement, never
    // reuse geometry from different Markdown source.
    if (existing) return
    if (cache.entryCount >= root.measuredBlockHeightCacheEntryLimit ||
        cache.sourceCharacters + rawLength >
          root.measuredBlockHeightCacheSourceLimit) return
    cache.entries[key] = {
      height: Number(measuredHeight),
      source: raw
    }
    cache.entryCount++
    cache.sourceCharacters += rawLength
  }

  function blockGeometryEntry(blockIndex) {
    // Reading the revision makes bindings react after an entry is updated in
    // place; replacing hundreds of small JS objects for one measured height
    // would create needless garbage during a scroll.
    var revision = root.blockGeometryRevision
    var index = Number(blockIndex)
    if (!isFinite(index) || index < 0 || index >= root.blockGeometry.length) {
      return null
    }
    return root.blockGeometry[index]
  }

  function queueMeasuredBlockHeight(blockIndex, measuredHeight) {
    var index = Number(blockIndex)
    var height = Number(measuredHeight)
    if (!isFinite(index) || index < 0 || !isFinite(height) || height <= 0) return
    root.pendingBlockMeasurements["b" + index] = {
      index: index,
      height: height,
      layoutRevision: root.layoutRevision
    }
    if (!blockMeasurementTimer.running) blockMeasurementTimer.start()
  }

  function flushMeasuredBlockHeights() {
    var pending = root.pendingBlockMeasurements
    root.pendingBlockMeasurements = ({})
    var keys = Object.keys(pending)
    keys.sort(function(left, right) {
      return Number(pending[left].index) - Number(pending[right].index)
    })
    var changed = false
    var anchorDelta = 0
    for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
      var measurement = pending[keys[keyIndex]]
      if (Number(measurement.layoutRevision) !== root.layoutRevision) continue
      var index = Number(measurement.index)
      var height = Math.max(0, Number(measurement.height) || 0)
      if (index < 0 || index >= root.blockGeometry.length || height <= 0) continue
      var entry = root.blockGeometry[index]
      var oldHeight = Math.max(0, Number(entry.height) || 0)
      var delta = height - oldHeight
      entry.measuredHeight = height
      entry.exact = true
      root.rememberMeasuredBlockHeight(index, height)
      if (Math.abs(delta) <= 0.25) continue
      if (Number(entry.top) + root.verticalPadding < root.viewportY) {
        anchorDelta += delta
      }
      entry.height = height
      changed = true
    }
    if (!changed) return

    var top = 0
    for (var geometryIndex = 0;
         geometryIndex < root.blockGeometry.length; geometryIndex++) {
      root.blockGeometry[geometryIndex].top = top
      top += Math.max(0,
        Number(root.blockGeometry[geometryIndex].height) || 0)
      if (geometryIndex < root.blockGeometry.length - 1)
        top += root.blockSpacing
    }
    root.blockGeometryRevision++
    if (Math.abs(anchorDelta) > 0.25) {
      root.heightIndexAdjusted(anchorDelta,
        Math.max(0, root.viewportY - root.verticalPadding - 1))
    }
    root.viewportContentChanged()
  }

  function blockIntersectsRenderWindow(blockIndex, blockY, blockHeight) {
    if (!root.viewportRenderingEnabled ||
        Number(blockIndex) === Number(root.forcedBlockIndex)) return true
    var overscan = Math.max(0, Number(root.viewportOverscan) || 0)
    var top = Math.max(0, Number(root.viewportY) || 0) - overscan
    var bottom = Math.max(top,
      (Number(root.viewportY) || 0) +
      Math.max(1, Number(root.viewportHeight) || 1) + overscan)
    var entry = root.blockGeometryEntry(blockIndex)
    var y = entry ? Number(entry.top) || 0 : Number(blockY) || 0
    var height = entry ? Math.max(1, Number(entry.height) || 1) :
      Math.max(1, Number(blockHeight) || 1)
    return y + height >= top && y <= bottom
  }

  function renderedBlockCountForTests() {
    var count = 0
    for (var index = 0; index < root.blocks.length; index++) {
      var item = blockRepeater.itemAt(index)
      if (item && item.contentActive) count++
    }
    return count
  }

  function viewportStatsForTests() {
    var first = -1
    var last = -1
    var rendered = 0
    for (var index = 0; index < root.blocks.length; index++) {
      var item = blockRepeater.itemAt(index)
      if (!item || !item.contentActive) continue
      if (first < 0) first = index
      last = index
      rendered++
    }
    return {
      enabled: root.viewportRenderingEnabled,
      viewportY: Number(root.viewportY) || 0,
      viewportHeight: Number(root.viewportHeight) || 0,
      overscan: Number(root.viewportOverscan) || 0,
      totalBlocks: root.blocks.length,
      renderedBlocks: rendered,
      firstRenderedBlock: first,
      lastRenderedBlock: last,
      forcedBlockIndex: root.forcedBlockIndex,
      contentHeight: root.implicitHeight,
      cachedMeasuredBlocks: Number(root.measuredBlockHeightCache.entryCount),
      cachedMeasuredSourceCharacters:
        Number(root.measuredBlockHeightCache.sourceCharacters)
    }
  }

  function wrappedTextLineCount(value, availableWidth) {
    paragraphWrapProbe.width = Math.max(1, Number(availableWidth) || 1)
    paragraphWrapProbe.text = String(value || "")
    return Math.max(1, Number(paragraphWrapProbe.lineCount) || 1)
  }

  function wrappedTextCursorLocation(value, availableWidth) {
    var sourceValue = String(value || "")
    var lineCount = root.wrappedTextLineCount(sourceValue, availableWidth)
    var lineStart = 0
    if (lineCount > 1) {
      var low = 0
      var high = sourceValue.length
      while (low < high) {
        var middle = Math.floor((low + high) / 2)
        if (root.wrappedTextLineCount(
              sourceValue.slice(0, middle), availableWidth) >= lineCount) {
          high = middle
        } else {
          low = middle + 1
        }
      }
      lineStart = low
    }
    return {
      lineIndex: lineCount - 1,
      text: sourceValue.slice(lineStart)
    }
  }

  function paragraphProbeLineCount(value, availableWidth) {
    return root.wrappedTextLineCount(root.plainInline(value), availableWidth)
  }

  function paragraphCursorLocation(value, availableWidth, sourcePosition) {
    var sourceValue = String(value || "")
    var cursor = Number(sourcePosition)
    if (!isFinite(cursor)) cursor = sourceValue.length
    cursor = Math.max(0, Math.min(cursor, sourceValue.length))
    var explicitLineStart = sourceValue.lastIndexOf("\n",
      Math.max(0, cursor - 1)) + 1
    var renderedDocumentPrefix = root.paragraphPlainPrefix(
      sourceValue, cursor)
    var renderedPrefix = renderedDocumentPrefix.slice(
      renderedDocumentPrefix.lastIndexOf("\n") + 1)
    var renderedLocation = root.wrappedTextCursorLocation(
      renderedPrefix, availableWidth)
    var explicitLineIndex = sourceValue.slice(0, explicitLineStart)
      .split("\n").length - 1
    return {
      lineIndex: explicitLineIndex + renderedLocation.lineIndex,
      // Keep trailing spaces in the caret probe. Rich text does not paint
      // them, but they are still real source columns and the editor must be
      // able to show a caret moving through each one.
      text: renderedLocation.text
    }
  }

  function sourceColumnForX(value, x) {
    var sourceValue = String(value || "")
    var targetX = Math.max(0, Number(x) || 0)

    // Complex Unicode shaping can make adjacent UTF-16 prefix widths equal
    // or even non-monotonic (for example, a combining mark changes the glyph
    // before it). Preserve the exact scan for those rows; ordinary Markdown
    // and code rows can use the much cheaper monotonic ASCII lookup below.
    if (!/^[\x20-\x7e\t]*$/.test(sourceValue)) {
      var bestColumn = 0
      var bestDistance = Math.abs(
        root.cursorWidth("", root.bodyPixelSize) - targetX)
      for (var column = 1; column <= sourceValue.length; column++) {
        var distance = Math.abs(root.cursorWidth(
          sourceValue.slice(0, column), root.bodyPixelSize) - targetX)
        if (distance < bestDistance) {
          bestColumn = column
          bestDistance = distance
        }
      }
      return bestColumn
    }

    var low = 0
    var high = sourceValue.length
    while (low < high) {
      var middle = Math.floor((low + high) / 2)
      var middleWidth = root.cursorWidth(
        sourceValue.slice(0, middle), root.bodyPixelSize)
      if (middleWidth < targetX) low = middle + 1
      else high = middle
    }

    var rightColumn = low
    var leftColumn = Math.max(0, rightColumn - 1)
    var leftDistance = Math.abs(root.cursorWidth(
      sourceValue.slice(0, leftColumn), root.bodyPixelSize) - targetX)
    var rightDistance = Math.abs(root.cursorWidth(
      sourceValue.slice(0, rightColumn), root.bodyPixelSize) - targetX)
    // Match the former linear scan's tie behavior by preferring the earlier
    // source boundary when a click is exactly halfway between glyphs.
    return rightDistance < leftDistance ? rightColumn : leftColumn
  }

  function sourceOffsetForPlainColumn(value, plainColumn) {
    var sourceValue = String(value || "")
    var plainValue = root.plainInline(sourceValue)
    var target = Math.max(0, Math.min(Number(plainColumn) || 0,
      plainValue.length))
    // Most note text has no inline syntax. When projection preserves every
    // UTF-16 boundary exactly, the native TextEdit column already is the
    // source offset; avoid a binary search through Markdown prefixes.
    if (plainValue === sourceValue) return target
    return root.sourceOffsetForVisibleColumn(sourceValue, target, false)
  }

  function sourceOffsetForQuotePlainColumn(value, plainColumn) {
    var sourceValue = String(value || "")
    var target = Math.max(0, Math.min(Number(plainColumn) || 0,
      root.quotePlainPrefix(sourceValue, sourceValue.length).length))
    return root.sourceOffsetForVisibleColumn(sourceValue, target, true)
  }

  function sourceOffsetForVisibleColumn(value, visibleColumn, quoteMode) {
    var sourceValue = String(value || "")
    var target = Math.max(0, Number(visibleColumn) || 0)
    var bestOffset = 0
    var low = 0
    var high = sourceValue.length
    while (low <= high) {
      var offset = Math.floor((low + high) / 2)
      var renderedLength = quoteMode
        ? root.quotePlainPrefix(sourceValue, offset).length
        : root.plainInlinePrefix(sourceValue, offset).length
      if (renderedLength <= target) {
        bestOffset = offset
        low = offset + 1
      } else {
        high = offset - 1
      }
    }
    return bestOffset
  }

  function sourceLineSelectionRange(sourcePosition) {
    var source = String(root.sourceText || "")
    var position = Number(sourcePosition)
    if (!isFinite(position)) position = 0
    position = Math.max(0, Math.min(source.length, Math.floor(position)))
    var start = source.lastIndexOf("\n", Math.max(0, position - 1)) + 1
    var end = source.indexOf("\n", position)
    if (end < 0) end = source.length
    return { start: start, end: end }
  }

  function selectLineAtSourcePosition(sourcePosition) {
    var range = root.sourceLineSelectionRange(sourcePosition)
    if (Number(range.end) <= Number(range.start)) return false
    root.sourceSelectionRequested(range.start, range.end)
    return true
  }

  function isSourceWordCharacter(value) {
    var character = String(value || "")
    if (character.length !== 1) return false
    return /[A-Za-z0-9_]/.test(character) ||
      character.toLowerCase() !== character.toUpperCase()
  }

  function sourceWordSelectionRange(sourcePosition) {
    var source = String(root.sourceText || "")
    var position = Number(sourcePosition)
    if (!isFinite(position)) position = 0
    position = Math.max(0, Math.min(source.length, Math.floor(position)))

    // Hit testing returns a caret boundary. When that boundary is just after
    // a word, treat the character on its left as the double-click target.
    if (position > 0 &&
        !root.isSourceWordCharacter(source.charAt(position)) &&
        root.isSourceWordCharacter(source.charAt(position - 1))) {
      position--
    }
    if (!root.isSourceWordCharacter(source.charAt(position))) {
      return { start: position, end: position }
    }

    var start = position
    while (start > 0 && root.isSourceWordCharacter(source.charAt(start - 1))) {
      start--
    }
    var end = position
    while (end < source.length && root.isSourceWordCharacter(source.charAt(end))) {
      end++
    }
    return { start: start, end: end }
  }

  function selectWordAtSourcePosition(sourcePosition) {
    var range = root.sourceWordSelectionRange(sourcePosition)
    if (Number(range.end) <= Number(range.start)) return false
    root.sourceSelectionRequested(range.start, range.end)
    return true
  }

  function mouseClickKeyForSourcePosition(sourcePosition) {
    var line = root.sourceLineSelectionRange(sourcePosition)
    var word = root.sourceWordSelectionRange(sourcePosition)
    var wordStart = Number(word.end) > Number(word.start)
      ? Number(word.start) : Number(sourcePosition)
    var wordEnd = Number(word.end) > Number(word.start)
      ? Number(word.end) : Number(sourcePosition)
    return [line.start, line.end, wordStart, wordEnd].join(":")
  }

  function registerRenderedMousePress(sourcePosition) {
    var now = Date.now()
    var key = root.mouseClickKeyForSourcePosition(sourcePosition)
    var sameSequence = key === root.mouseClickKey &&
      now - Number(root.mouseClickTimestamp) <=
      root.mouseDoubleClickInterval
    root.mouseClickCount = sameSequence
      ? Math.min(3, root.mouseClickCount + 1) : 1
    root.mouseClickKey = key
    root.mouseClickTimestamp = now
    mouseClickResetTimer.restart()
    return root.mouseClickCount
  }

  function handleRenderedDoubleClick(sourcePosition) {
    // The third press is handled in onPressed so a MouseArea implementation
    // that also reports a second double-click cannot replace the line range
    // with the word range after triple-click selection has been applied.
    if (root.mouseClickCount >= 3) return false
    return root.selectWordAtSourcePosition(sourcePosition)
  }

  function listItemContentStart(itemValue) {
    var item = itemValue || {}
    var itemStart = Math.max(0, Number(item.sourceStart) || 0)
    var itemEnd = Math.max(itemStart,
      Number(item.sourceEnd) || itemStart)
    var rawItem = root.sourceText.slice(itemStart, itemEnd)
    var itemPrefix = /^(\s*)([-+*]|\d+[.)])[ \t]+/.exec(rawItem)
    if (!itemPrefix) itemPrefix = /^(\s*)([-+*]|\d+[.)])$/.exec(rawItem)
    var contentStart = itemPrefix ? itemPrefix[0].length : 0
    var taskPrefix = /^\[[ xX]\][ \t]+/.exec(rawItem.slice(contentStart))
    if (taskPrefix) contentStart += taskPrefix[0].length
    return Math.max(0, Math.min(rawItem.length, contentStart))
  }

  function listItemFirstSelectablePosition(itemValue) {
    var item = itemValue || {}
    var itemStart = Math.max(0, Number(item.sourceStart) || 0)
    var itemEnd = Math.max(itemStart,
      Number(item.sourceEnd) || itemStart)
    var rawItem = root.sourceText.slice(itemStart, itemEnd)
    var contentStart = root.listItemContentStart(item)
    var content = rawItem.slice(contentStart)
    // Match the left edge of the rendered text, so inline Markdown markers
    // are skipped as well as the non-selectable list prefix.
    return itemStart + contentStart +
      root.sourceOffsetForPlainColumn(content, 0)
  }

  function listSourcePosition(itemValue, hitProbe, localX, localY) {
    var item = itemValue || {}
    var itemStart = Number(item.sourceStart) || 0
    var itemEnd = Number(item.sourceEnd) || itemStart
    var rawItem = root.sourceText.slice(itemStart, itemEnd)
    var contentStart = root.listItemContentStart(item)

    var content = rawItem.slice(contentStart)
    var plainContent = root.plainInline(content)
    var renderedOffset
    if (hitProbe && hitProbe.positionAt) {
      var visibleMetrics = root.listTextLineMetrics(
        hitProbe.parent, plainContent)
      var visibleRow = Math.round(((Number(localY) || 0) -
        visibleMetrics.glyphHeight / 2) / visibleMetrics.lineAdvance)
      visibleRow = Math.max(0, Math.min(
        visibleMetrics.lineCount - 1, visibleRow))
      var probeHeight = Math.max(1,
        Number(hitProbe.contentHeight) || Number(hitProbe.height) || 1)
      var probeLineCount = Math.max(1,
        Number(hitProbe.lineCount) || visibleMetrics.lineCount)
      var probeLineAdvance = probeHeight / probeLineCount
      var probeY = (Math.min(visibleRow, probeLineCount - 1) + 0.5) *
        probeLineAdvance
      renderedOffset = hitProbe.positionAt(
        Math.max(0, Math.min(Number(hitProbe.width) || 0,
          Number(localX) || 0)),
        Math.max(0, Math.min(probeHeight, probeY)))
    } else {
      renderedOffset = root.sourceColumnForX(plainContent, localX)
    }
    return itemStart + contentStart +
      root.sourceOffsetForPlainColumn(content, renderedOffset)
  }

  function quoteSourcePosition(blockValue, hitProbe, localX, localY) {
    var block = blockValue || {}
    var sourceStart = Math.max(0, Number(block.sourceStart) || 0)
    var sourceEnd = Math.max(sourceStart,
      Math.min(root.sourceText.length, Number(block.sourceEnd) || sourceStart))
    var source = root.sourceText.slice(sourceStart, sourceEnd)
    var probeScale = hitProbe && hitProbe.parent
      ? root.selectionMirrorVerticalScale(
          Number(hitProbe.parent.height) || 0,
          Number(hitProbe.contentHeight) || 0) : 1
    var renderedOffset = hitProbe && hitProbe.positionAt
      ? hitProbe.positionAt(
          Math.max(0, Math.min(Number(hitProbe.width) || 0,
            Number(localX) || 0)),
          Math.max(0, Math.min(Number(hitProbe.contentHeight) || 0,
            (Number(localY) || 0) / probeScale)))
      : root.sourceColumnForX(
          root.quotePlainPrefix(source, source.length), localX)
    return sourceStart + root.sourceOffsetForQuotePlainColumn(
      source, renderedOffset)
  }

  function listSourcePositionForBlockPoint(blockValue, blockItemValue,
                                           localX, localY) {
    var block = blockValue || {}
    var blockItem = blockItemValue || root.blockItemForValue(block)
    var listView = blockItem ? blockItem.listViewReference : null
    var items = block.items || []
    if (!listView || items.length === 0) {
      return Math.max(0, Number(block.sourceStart) || 0)
    }

    var targetY = Number(localY) || 0
    var bestIndex = -1
    var bestDistance = Infinity
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
      var listItem = listView.itemAtIndex(itemIndex)
      if (!listItem) continue
      var itemTop = Number(listItem.y) || 0
      var itemBottom = itemTop + Math.max(0, Number(listItem.height) || 0)
      var distance = targetY < itemTop ? itemTop - targetY
        : targetY > itemBottom ? targetY - itemBottom : 0
      if (distance < bestDistance) {
        bestIndex = itemIndex
        bestDistance = distance
      }
      if (distance === 0) break
    }
    if (bestIndex < 0) return Math.max(0, Number(block.sourceStart) || 0)

    var selectedItem = listView.itemAtIndex(bestIndex)
    var itemData = selectedItem.itemData || items[bestIndex]
    var textX = Number(selectedItem.textOriginX) || 0
    var textY = (Number(selectedItem.y) || 0) +
      (Number(selectedItem.textOriginY) || 0)
    if ((Number(localX) || 0) < textX) {
      return root.listItemFirstSelectablePosition(itemData)
    }
    return root.listSourcePosition(
      itemData, selectedItem.hitProbeReference,
      (Number(localX) || 0) - textX, targetY - textY)
  }

  function blockItemForValue(blockValue) {
    var block = blockValue || {}
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var candidate = root.blocks[blockIndex]
      if (candidate === blockValue ||
          candidate.sourceStart === block.sourceStart &&
          candidate.sourceEnd === block.sourceEnd) {
        return blockRepeater.itemAt(blockIndex)
      }
    }
    return null
  }

  function blockIndexForSourcePosition(sourcePosition) {
    var position = Math.max(0, Math.min(
      Number(sourcePosition) || 0, root.sourceText.length))
    var low = 0
    var high = root.blocks.length - 1
    var candidate = -1
    while (low <= high) {
      var middle = Math.floor((low + high) / 2)
      var middleStart = Number(root.blocks[middle].sourceStart)
      if (!isFinite(middleStart) || middleStart > position) {
        high = middle - 1
      } else {
        candidate = middle
        low = middle + 1
      }
    }
    if (candidate < 0) return -1

    // Adjacent Markdown blocks can share one boundary. Preserve the original
    // first-match behavior at that boundary without scanning the whole note.
    while (candidate > 0 &&
           Number(root.blocks[candidate - 1].sourceEnd) >= position) {
      candidate--
    }
    for (var index = candidate; index < root.blocks.length; index++) {
      var block = root.blocks[index]
      var start = Number(block.sourceStart)
      var end = Number(block.sourceEnd)
      if (isFinite(start) && start > position) break
      if (isFinite(start) && isFinite(end) &&
          position >= start && position <= end) return index
    }
    return -1
  }

  function blockIndexForPointY(targetYValue) {
    if (root.blocks.length === 0) return -1
    var contentY = (Number(targetYValue) || 0) - root.verticalPadding
    var geometry = root.blockGeometry
    if (geometry.length === root.blocks.length && geometry.length > 0) {
      var geometryLow = 0
      var geometryHigh = geometry.length - 1
      var geometryCandidate = 0
      while (geometryLow <= geometryHigh) {
        var geometryMiddle = Math.floor((geometryLow + geometryHigh) / 2)
        if (Number(geometry[geometryMiddle].top) <= contentY) {
          geometryCandidate = geometryMiddle
          geometryLow = geometryMiddle + 1
        } else {
          geometryHigh = geometryMiddle - 1
        }
      }
      if (geometryCandidate + 1 < geometry.length) {
        var candidateBottom = Number(geometry[geometryCandidate].top) +
          Number(geometry[geometryCandidate].height)
        var nextTop = Number(geometry[geometryCandidate + 1].top)
        if (contentY > candidateBottom &&
            (root.blocks[geometryCandidate + 1].type === "blank" ||
             nextTop - contentY < contentY - candidateBottom)) {
          geometryCandidate++
        }
      }
      return geometryCandidate
    }

    var low = 0
    var high = root.blocks.length - 1
    var candidate = 0
    while (low <= high) {
      var middle = Math.floor((low + high) / 2)
      var item = blockRepeater.itemAt(middle)
      if (!item) {
        high = middle - 1
        continue
      }
      if (Number(item.y) <= contentY) {
        candidate = middle
        low = middle + 1
      } else {
        high = middle - 1
      }
    }

    var candidateItem = blockRepeater.itemAt(candidate)
    var nextItem = candidate + 1 < root.blocks.length
      ? blockRepeater.itemAt(candidate + 1) : null
    if (candidateItem && nextItem) {
      var candidateBottom = Number(candidateItem.y) +
        Number(candidateItem.height)
      if (contentY > candidateBottom &&
          (root.blocks[candidate + 1].type === "blank" ||
           Number(nextItem.y) - contentY < contentY - candidateBottom)) {
        candidate++
      }
    }
    return candidate
  }

  function blockHitProbeText(blockValue) {
    var block = blockValue || {}
    var sourceStart = Number(block.sourceStart) || 0
    var sourceEnd = Number(block.sourceEnd) || sourceStart
    var source = root.sourceText.slice(sourceStart, sourceEnd)

    if (block.type === "heading") return root.plainInline(block.plain || "")
    if (block.type === "paragraph")
      return root.paragraphPlainPrefix(source, source.length)
    return ""
  }

  function sourceCaretCenterY(sourcePosition) {
    var caret = root.cursorRectangleForSource(sourcePosition)
    return caret
      ? Number(caret.y) + Number(caret.height) / 2
      : NaN
  }

  function verticalNavigationTarget(sourcePosition, preferredX, direction) {
    if (!root.layoutReady || !root.layoutMatchesCurrentInput()) return -1

    var step = Number(direction) > 0 ? 1 : Number(direction) < 0 ? -1 : 0
    if (step === 0) return -1
    var sourceLength = root.sourceText.length
    var position = Math.max(0, Math.min(
      Number(sourcePosition) || 0, sourceLength))
    var currentCaret = root.cursorRectangleForSource(position)
    if (!currentCaret) return -1
    var currentY = root.caretCenterY(currentCaret)
    var targetSeed = -1

    if (step > 0) {
      if (position >= sourceLength) return -1
      targetSeed = root.firstSourcePositionAtOrAfterY(
        position + 1, sourceLength, currentY + 0.75)
      if (targetSeed > sourceLength) return -1
    } else {
      var currentRowStart = root.firstSourcePositionAtOrAfterY(
        0, position, currentY - 0.75)
      if (currentRowStart <= 0) return -1
      targetSeed = currentRowStart - 1
    }

    var targetCaret = root.cursorRectangleForSource(targetSeed)
    if (!targetCaret) return -1
    var targetY = root.caretCenterY(targetCaret)
    if (!isFinite(targetY) ||
        (step > 0 && targetY <= currentY + 0.75) ||
        (step < 0 && targetY >= currentY - 0.75)) return -1

    var targetX = Number(preferredX)
    if (!isFinite(targetX) || targetX < 0) {
      targetX = Number(currentCaret.x) + Number(currentCaret.width) / 2
    }
    var candidate = root.sourcePositionForPoint(targetX, targetY)
    var candidateCaret = root.cursorRectangleForSource(candidate)
    if (!candidateCaret ||
        Math.abs(root.caretCenterY(candidateCaret) - targetY) > 0.75) {
      candidate = targetSeed
    }
    return Math.max(0, Math.min(sourceLength, candidate))
  }

  function firstSourcePositionAtOrAfterY(sourceStart, sourceEnd, targetY) {
    var low = sourceStart
    var high = sourceEnd + 1
    while (low < high) {
      var middle = Math.floor((low + high) / 2)
      var caretY = root.sourceCaretCenterY(middle)
      if (!isFinite(caretY) || caretY < targetY) low = middle + 1
      else high = middle
    }
    return low
  }

  function nearestSourcePositionForBlock(blockValue, blockItem,
                                          targetX, targetY) {
    var block = blockValue || {}
    var sourceStart = Math.max(0, Number(block.sourceStart) || 0)
    var sourceEnd = Math.max(sourceStart,
      Math.min(root.sourceText.length,
        Number(block.sourceEnd) || sourceStart))

    var firstAtTarget = root.firstSourcePositionAtOrAfterY(
      sourceStart, sourceEnd, targetY)
    var pivot = Math.max(sourceStart,
      Math.min(sourceEnd, firstAtTarget))
    var before = Math.max(sourceStart, pivot - 1)
    var pivotY = root.sourceCaretCenterY(pivot)
    var beforeY = root.sourceCaretCenterY(before)
    var rowY = isFinite(pivotY) &&
      (!isFinite(beforeY) || Math.abs(pivotY - targetY) <=
        Math.abs(beforeY - targetY)) ? pivotY : beforeY
    if (!isFinite(rowY)) return sourceStart

    // Carets in one visual row share a Y center. Restrict the horizontal
    // search to that row so clicking a long note does not scan every source
    // position in the file.
    var rowStart = root.firstSourcePositionAtOrAfterY(
      sourceStart, sourceEnd, rowY - 0.75)
    var rowEndExclusive = root.firstSourcePositionAtOrAfterY(
      sourceStart, sourceEnd, rowY + 0.75)
    var rowEnd = Math.max(rowStart,
      Math.min(sourceEnd, rowEndExclusive - 1))
    var bestPosition = Math.max(rowStart, Math.min(rowEnd, pivot))
    var bestScore = Infinity
    for (var position = rowStart; position <= rowEnd; position++) {
      var caret = root.cursorRectangleForSource(position)
      if (!caret) continue
      var caretX = Number(caret.x) + Number(caret.width) / 2
      var caretY = Number(caret.y) + Number(caret.height) / 2
      var horizontalDistance = Math.abs(targetX - caretX)
      var verticalDistance = Math.abs(targetY - caretY)
      var score = verticalDistance * 12 + horizontalDistance
      if (score < bestScore) {
        bestPosition = position
        bestScore = score
      }
    }
    return bestPosition
  }

  function imageSourcePositionForPoint(blockValue, imageSurface,
                                       localX, localY) {
    var block = blockValue || {}
    var sourceStart = Math.max(0, Number(block.sourceStart) || 0)
    var altStart = Number(block.altSourceStart)
    var altEnd = Number(block.altSourceEnd)
    var altText = imageSurface ? imageSurface.imageAltTextReference : null
    if (!imageSurface || !altText || !altText.visible ||
        !isFinite(altStart) || !isFinite(altEnd) || altEnd < altStart) {
      return sourceStart
    }

    var altY = Number(altText.y) || 0
    var altHeight = Math.max(1, Number(altText.implicitHeight) || 0)
    var targetY = Number(localY) || 0
    if (targetY < altY) return sourceStart

    var altProbe = imageSurface.imageAltHitProbeReference
    var altWidth = Math.max(1, Number(altText.width) || 0)
    var probeX = Math.max(0, Math.min(altWidth,
      (Number(localX) || 0) - Number(altText.x || 0)))
    var probeY = Math.max(0, Math.min(altHeight,
      targetY - altY))
    var renderedOffset = altProbe && altProbe.positionAt
      ? Number(altProbe.positionAt(probeX, probeY)) || 0
      : root.sourceColumnForX(String(block.alt || ""), probeX)
    return Math.max(altStart, Math.min(altEnd,
      altStart + renderedOffset))
  }

  function imageAltCaretRectangle(blockValue, blockItem, imageSurface,
                                  sourcePosition) {
    var block = blockValue || {}
    var altStart = Number(block.altSourceStart)
    var altEnd = Number(block.altSourceEnd)
    var position = Number(sourcePosition)
    var altText = imageSurface ? imageSurface.imageAltTextReference : null
    if (!blockItem || !imageSurface || !altText || !altText.visible ||
        !isFinite(altStart) || !isFinite(altEnd) || altEnd < altStart ||
        !isFinite(position) || position < altStart || position > altEnd) {
      return null
    }

    var altProbe = imageSurface.imageAltHitProbeReference
    var offset = Math.max(0, Math.min(altEnd - altStart,
      position - altStart))
    var nativeRect = altProbe && altProbe.positionToRectangle
      ? altProbe.positionToRectangle(offset) : null
    var altLineCount = Math.max(1,
      Number(altText.lineCount) ||
      root.wrappedTextLineCount(String(block.alt || ""), altText.width))
    var altLineAdvance = Math.max(1,
      Number(altText.implicitHeight) / altLineCount ||
      root.bodyLineAdvance())
    var lineIndex = 0
    var caretX = root.cursorWidth(
      String(block.alt || "").slice(0, offset), root.bodyPixelSize)
    if (nativeRect) {
      var probeLineCount = Math.max(1, Number(altProbe.lineCount) ||
        altLineCount)
      var probeLineAdvance = Math.max(1,
        Number(altProbe.contentHeight) / probeLineCount ||
        Number(nativeRect.height) || altLineAdvance)
      lineIndex = Math.max(0, Math.min(altLineCount - 1,
        Math.floor((Number(nativeRect.y) + Number(nativeRect.height) / 2) /
          probeLineAdvance)))
      caretX = Number(nativeRect.x) || 0
    }

    var caretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
    return Qt.rect(
      root.horizontalPadding + Number(imageSurface.x || 0) +
        Number(altText.x || 0) + caretX,
      root.verticalPadding + Number(blockItem.y || 0) +
        Number(imageSurface.y || 0) + Number(altText.y || 0) +
        root.centeredCaretY(lineIndex * altLineAdvance,
          altLineAdvance, caretHeight),
      Math.max(1, Style.space(1)), Math.ceil(caretHeight))
  }

  function sourcePositionForBlockPoint(blockValue, localX, localY,
                                       knownBlockItem) {
    var block = blockValue || {}
    var sourceStart = Math.max(0, Number(block.sourceStart) || 0)
    var sourceEnd = Math.max(sourceStart,
      Math.min(root.sourceText.length,
        Number(block.sourceEnd) || sourceStart))
    var blockItem = knownBlockItem || root.blockItemForValue(blockValue)
    if (!blockItem || !root.layoutReady || !root.layoutMatchesCurrentInput()) {
      return sourceStart
    }

    if (block.type === "image") {
      var imageSurface = blockItem.imageContentReference
      if (!imageSurface) return sourceStart
      return root.imageSourcePositionForPoint(
        block, imageSurface,
        (Number(localX) || 0) - Number(imageSurface.x || 0),
        (Number(localY) || 0) - Number(imageSurface.y || 0))
    }

    var targetX = root.horizontalPadding + (Number(localX) || 0)
    var targetY = root.verticalPadding + Number(blockItem.y || 0) +
      (Number(localY) || 0)
    var probe = blockItem.blockHitProbeReference
    if (probe && probe.positionAt &&
        (block.type === "paragraph" || block.type === "heading") &&
        String(probe.text || "") !== "") {
      var probeWidth = Math.max(1, Number(probe.width) || 1)
      var probeHeight = Math.max(1, Number(probe.height) || 1)
      var probeX = Math.max(0, Math.min(probeWidth,
        Number(localX) || 0))
      var probeContentHeight = Math.max(1,
        Number(probe.contentHeight) || probeHeight)
      var probeY
      if (block.type === "paragraph") {
        // TextEdit does not support Text's proportional lineHeight. Resolve
        // the visible row with the painted paragraph metrics, then hit-test
        // the corresponding native TextEdit row. Scaling the complete Y
        // range drifts across wrapped rows and can send a click to a different
        // word several rows away.
        var paragraphMetrics = root.paragraphLineMetrics(block, blockItem)
        var paragraphSource = root.sourceText.slice(sourceStart, sourceEnd)
        var visibleLineCount = Math.max(1, paragraphMetrics.lineCount)
        var rowIndex = Math.round(((Number(localY) || 0) -
          paragraphMetrics.glyphHeight / 2) /
          paragraphMetrics.lineAdvance)
        rowIndex = Math.max(0, Math.min(visibleLineCount - 1, rowIndex))
        var probeLineCount = Math.max(1,
          Number(probe.lineCount) || visibleLineCount)
        var probeLineAdvance = probeContentHeight / probeLineCount
        probeY = (Math.min(rowIndex, probeLineCount - 1) + 0.5) *
          probeLineAdvance
      } else {
        var probeScale = root.selectionMirrorVerticalScale(
          probeHeight, probeContentHeight)
        probeY = (Number(localY) || 0) / probeScale
      }
      probeY = Math.max(0, Math.min(probeContentHeight, probeY))
      var plainPosition = Math.max(0, Number(probe.positionAt(
        probeX, probeY)) || 0)
      var source = root.sourceText.slice(sourceStart, sourceEnd)
      if (block.type === "heading") {
        var headingStart = Number(block.contentSourceStart)
        var headingEnd = Number(block.contentSourceEnd)
        if (isFinite(headingStart) && isFinite(headingEnd))
          return Math.max(headingStart, Math.min(headingEnd,
            headingStart + root.sourceOffsetForPlainColumn(
              String(block.plain || ""), plainPosition)))
      } else {
        return Math.max(sourceStart, Math.min(sourceEnd,
          sourceStart + root.sourceOffsetForPlainColumn(
            source, plainPosition)))
      }
    }

    return root.nearestSourcePositionForBlock(blockValue, blockItem,
      targetX, targetY)
  }

  function sourcePositionForPoint(localX, localY) {
    if (!root.layoutReady || !root.layoutMatchesCurrentInput()) return 0

    var targetX = Number(localX) || 0
    var targetY = Number(localY) || 0
    // Block delegates are laid out in source order. Resolve the pointer's Y
    // coordinate with a binary search, then do the detailed hit test only for
    // that block. The former drag path recalculated every block on every mouse
    // event and each candidate caret scanned the blocks again.
    var blockIndex = root.blockIndexForPointY(targetY)
    if (blockIndex < 0) return 0
    var block = root.blocks[blockIndex]
    var blockItem = blockRepeater.itemAt(blockIndex)
    if (!block || !blockItem || block.sourceStart === undefined ||
        block.sourceEnd === undefined) return 0

    var blockLocalX = targetX - root.horizontalPadding
    var blockLocalY = targetY - root.verticalPadding -
      Number(blockItem.y || 0)
    var candidate
    if (block.type === "heading" || block.type === "paragraph") {
      candidate = root.sourcePositionForBlockPoint(
        block, blockLocalX, blockLocalY, blockItem)
    } else if (block.type === "list") {
      candidate = root.listSourcePositionForBlockPoint(
        block, blockItem, blockLocalX, blockLocalY)
    } else if (block.type === "code") {
      candidate = root.codeSourcePosition(
        block, blockLocalX, blockLocalY, blockItem)
    } else if (block.type === "quote") {
      var quoteProbe = blockItem.quoteHitProbeReference
      if (quoteProbe) {
        var quotePoint = quoteProbe.mapFromItem(root, targetX, targetY)
        candidate = root.quoteSourcePosition(
          block, quoteProbe, quotePoint.x, quotePoint.y)
      } else {
        candidate = root.nearestSourcePositionForBlock(
          block, blockItem, targetX, targetY)
      }
    } else {
      candidate = root.nearestSourcePositionForBlock(
        block, blockItem, targetX, targetY)
    }
    return Math.max(0, Math.min(root.sourceText.length, candidate))
  }

  function codeTextItemForBlock(blockValue) {
    var block = blockValue || {}
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var candidate = root.blocks[blockIndex]
      if (candidate.sourceStart !== block.sourceStart ||
          candidate.sourceEnd !== block.sourceEnd) continue
      var blockItem = blockRepeater.itemAt(blockIndex)
      return blockItem ? blockItem.codeTextReference : null
    }
    return null
  }

  function codeDefinitionNameForBlock(blockValue) {
    var block = blockValue || {}
    return SyntaxHighlight.languageLabel(block.language || "")
  }

  function codeHighlightMarkupForBlock(blockValue) {
    return root.codeHighlightMarkup(blockValue)
  }

  function codeTextOffsetForSourcePosition(blockValue, sourcePosition) {
    var block = blockValue || {}
    var source = String(root.sourceText || "")
    var sourceStart = Number(block.codeSourceStart)
    var sourceEnd = Number(block.codeSourceEnd)
    var textLength = String(block.text || "").length
    if (!isFinite(sourceStart) || !isFinite(sourceEnd)) return 0

    var position = Number(sourcePosition)
    if (!isFinite(position)) position = sourceStart
    position = Math.max(sourceStart, Math.min(sourceEnd, position))
    if (position <= sourceStart) return 0
    if (position >= sourceEnd) return textLength

    return Math.max(0, Math.min(textLength,
      root.normalizedFencedCodeText(
        source.slice(sourceStart, position), block.codeIndent).length))
  }

  function codeSourcePositionForTextOffset(blockValue, textOffset) {
    var block = blockValue || {}
    var source = String(root.sourceText || "")
    var sourceStart = Number(block.codeSourceStart)
    var sourceEnd = Number(block.codeSourceEnd)
    var textLength = String(block.text || "").length
    if (!isFinite(sourceStart) || !isFinite(sourceEnd)) {
      return Number(block.sourceStart) || 0
    }

    var offset = Number(textOffset)
    if (!isFinite(offset)) offset = 0
    offset = Math.max(0, Math.min(textLength, offset))
    var content = source.slice(sourceStart, sourceEnd)
    var bestOffset = 0
    var low = 0
    var high = content.length
    while (low <= high) {
      var sourceOffset = Math.floor((low + high) / 2)
      var normalizedLength = root.normalizedFencedCodeText(
        content.slice(0, sourceOffset), block.codeIndent).length
      if (normalizedLength <= offset) {
        bestOffset = sourceOffset
        low = sourceOffset + 1
      } else {
        high = sourceOffset - 1
      }
    }
    return sourceStart + bestOffset
  }

  function normalizedFencedCodeText(value, indentation) {
    var indent = Math.max(0, Math.min(3, Number(indentation) || 0))
    var lines = String(value || "").replace(/\r\n/g, "\n").split("\n")
    for (var index = 0; index < lines.length; index++) {
      var leading = /^ */.exec(lines[index])[0].length
      lines[index] = lines[index].slice(Math.min(indent, leading))
    }
    return lines.join("\n")
  }

  function codeLanguageSourcePositionForPoint(blockValue, blockItem,
                                               localX) {
    var block = blockValue || {}
    var source = String(root.sourceText || "")
    var range = root.codeLanguageSourceRange(block, source)
    if (!range || !blockItem || !blockItem.codeReference) {
      return Number(block.sourceStart) || 0
    }

    var targetX = root.horizontalPadding +
      Number(blockItem.codeReference.x || 0) + (Number(localX) || 0)
    var bestPosition = range.tokenStart
    var bestDistance = Infinity
    for (var position = range.infoStart; position <= range.infoEnd;
         position++) {
      var caret = root.cursorRectangleForCodeLanguage(
        block, blockItem, source, position)
      if (!caret) continue
      var distance = Math.abs(targetX -
        (Number(caret.x) + Number(caret.width) / 2))
      if (distance < bestDistance ||
          distance === bestDistance && position > bestPosition) {
        bestPosition = position
        bestDistance = distance
      }
    }
    return Math.max(range.infoStart, Math.min(range.infoEnd, bestPosition))
  }

  function codeSourcePosition(blockValue, localX, localY, knownBlockItem) {
    var block = blockValue || {}
    var source = String(root.sourceText || "")
    var blockItem = knownBlockItem || root.blockItemForValue(blockValue)
    var languageLabel = blockItem
      ? blockItem.codeLanguageLabelReference : null
    if (languageLabel && languageLabel.visible &&
        Number(localY) >= Number(languageLabel.y) &&
        Number(localY) <= Number(languageLabel.y) +
          Number(languageLabel.height)) {
      return root.codeLanguageSourcePositionForPoint(
        block, blockItem, localX)
    }
    var codeTextItem = blockItem
      ? blockItem.codeTextReference : root.codeTextItemForBlock(block)
    if (codeTextItem && codeTextItem.positionAt) {
      var textWidth = Math.max(1, Number(codeTextItem.width) || 0)
      var textHeight = Math.max(1,
        Number(codeTextItem.height) || Number(codeTextItem.contentHeight) || 0)
      var textX = Math.max(0, Math.min(textWidth,
        (Number(localX) || 0) - Number(codeTextItem.x || 0)))
      var textY = Math.max(0, Math.min(textHeight,
        (Number(localY) || 0) - Number(codeTextItem.y || 0)))
      return root.codeSourcePositionForTextOffset(block,
        codeTextItem.positionAt(textX, textY))
    }

    var codeSource = source.slice(
      Number(block.sourceStart) || 0, Number(block.sourceEnd) || 0)
    var codeLines = String(block.text || "").split("\n")
    var lineAdvance = root.codeLineAdvanceForBlock(block)
    var lineIndex = Math.max(0, Math.min(codeLines.length - 1,
      Math.floor((Number(localY) - Style.space(10)) / lineAdvance)))
    var codeWidth = Math.max(1,
      root.width - root.horizontalPadding * 2 - Style.space(20))
    var column = root.sourceColumnForX(
      codeLines[lineIndex] || "",
      Math.max(0, Math.min(codeWidth, Number(localX) - Style.space(10))))

    var firstLineBreak = codeSource.indexOf("\n")
    var sourceLineStart = firstLineBreak >= 0
      ? (Number(block.sourceStart) || 0) + firstLineBreak + 1
      : Number(block.sourceEnd) || 0
    for (var line = 0; line < lineIndex; line++) {
      sourceLineStart += (codeLines[line] || "").length
      sourceLineStart += source.slice(sourceLineStart,
        sourceLineStart + 2) === "\r\n" ? 2 : 1
    }
    return Math.max(Number(block.sourceStart) || 0,
      Math.min(Number(block.sourceEnd) || source.length,
        sourceLineStart + column))
  }

  function cursorWidth(value, pixelSize) {
    cursorMetrics.font.family = root.fontFamily
    cursorMetrics.font.pixelSize = pixelSize
    cursorMetrics.text = String(value || "")
    return cursorMetrics.advanceWidth
  }

  function caretHeightForPixelSize(pixelSize) {
    var bodySize = Math.max(1, Number(root.bodyPixelSize) || 1)
    var nativeBodyHeight = Number(root.bodyCaretHeight)
    if (!isFinite(nativeBodyHeight) || nativeBodyHeight <= 0) {
      nativeBodyHeight = bodyFontMetrics.height
    }
    return Math.max(1, nativeBodyHeight * Math.max(1, pixelSize) / bodySize)
  }

  function centeredCaretY(lineTop, lineHeight, caretHeight) {
    return lineTop + Math.max(0, (lineHeight - caretHeight) / 2)
  }

  function caretTopForBaseline(baselineY, pixelSize, caretHeight) {
    var bodySize = Math.max(1, Number(root.bodyPixelSize) || 1)
    var scale = Math.max(1, Number(pixelSize) || 1) / bodySize
    var visibleTop = Number(root.bodyCaretBounds.y) * scale
    var visibleHeight = Math.max(1,
      Number(root.bodyCaretBounds.height) || 1) * scale
    // The font's full ascent/height box includes invisible leading and
    // descender room, so centering there makes the Live caret look too high
    // beside ordinary text. Center on representative lowercase glyphs with
    // both x-height and a descender, matching the body text around the caret.
    return Number(baselineY) + visibleTop + visibleHeight / 2 -
      Number(caretHeight) / 2
  }

  function caretCenterY(rect) {
    return Number(rect.y) + Number(rect.height) / 2
  }

  function paragraphLineMetrics(block, blockItem) {
    var textItem = blockItem ? blockItem.paragraphTextReference : null
    var continuationProbe = blockItem
      ? blockItem.paragraphContinuationReference : null
    if (!textItem || !continuationProbe) {
      var fallbackHeight = Math.max(1,
        Number(root.bodyPixelSize) || 1)
      return {
        glyphHeight: fallbackHeight,
        lineAdvance: fallbackHeight,
        lineCount: 1
      }
    }

    // RichText Text does not expose a dependable lineCount here. Measure the
    // same source projection used by paragraph caret wrapping so glyph height
    // is not mistaken for the complete multi-row paragraph height.
    var paragraphSource = root.sourceText.slice(
      Number(block.sourceStart) || 0, Number(block.sourceEnd) || 0)
    var currentHeight = Math.max(1, Number(textItem.implicitHeight) || 1)
    var continuedHeight = Math.max(currentHeight,
      Number(continuationProbe.implicitHeight) || currentHeight)
    var metricsKey = [root.layoutRevision, Number(textItem.width) || 0,
      currentHeight, continuedHeight, Number(block.sourceLineCount) || 1,
      root.bodyPixelSize, root.fontFamily].join(":")
    var cachedMetrics = block.paragraphLineMetricsCache
    if (cachedMetrics && cachedMetrics.key === metricsKey) {
      return cachedMetrics.value
    }
    var renderedLineCount = Math.max(1,
      root.paragraphProbeLineCount(paragraphSource, textItem.width),
      Number(block.sourceLineCount) || 1)
    var lineAdvance = Math.max(1, continuedHeight - currentHeight)
    var glyphHeight = Math.max(1,
      currentHeight - (renderedLineCount - 1) * lineAdvance)
    var metrics = {
      glyphHeight: glyphHeight,
      lineAdvance: lineAdvance,
      lineCount: renderedLineCount
    }
    block.paragraphLineMetricsCache = {key: metricsKey, value: metrics}
    return metrics
  }

  function listTextLineMetrics(textItem, plainText) {
    var fallbackHeight = Math.max(1, root.bodyTextGlyphHeight())
    if (!textItem) {
      return { lineCount: 1, glyphHeight: fallbackHeight,
        lineAdvance: root.bodyLineAdvance() }
    }
    var lineCount = Math.max(1,
      root.wrappedTextLineCount(String(plainText || ""), textItem.width))
    var lineAdvance = root.bodyLineAdvance()
    var textHeight = Math.max(1,
      Number(textItem.implicitHeight) || Number(textItem.height) || 1)
    var glyphHeight = Math.max(1,
      textHeight - (lineCount - 1) * lineAdvance)
    return { lineCount: lineCount, glyphHeight: glyphHeight,
      lineAdvance: lineAdvance }
  }

  function bodyLineAdvance() {
    var glyphHeight = Math.max(1, Number(bodyFontMetrics.height) || 0,
      Number(root.bodyPixelSize) || 1)
    return Math.max(1, glyphHeight * root.bodyLineHeightFactor)
  }

  function codeSourceLineCount(blockValue) {
    return Math.max(1, String(blockValue && blockValue.text || "")
      .replace(/\r\n/g, "\n").split("\n").length)
  }

  function codeLineAdvanceForText(textItem, sourceLineCount) {
    // Code, prose, explicit newlines, and soft wraps intentionally share the
    // same font-derived editor row advance. Avoid reading implicitHeight here:
    // this function participates in codeText.height and doing so creates a
    // height binding loop.
    return root.bodyLineAdvance()
  }

  function codeLineAdvanceForBlock(blockValue) {
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var candidate = root.blocks[blockIndex]
      if (candidate.sourceStart !== blockValue.sourceStart ||
          candidate.sourceEnd !== blockValue.sourceEnd) continue
      var blockItem = blockRepeater.itemAt(blockIndex)
      return root.codeLineAdvanceForText(
        blockItem ? blockItem.codeTextReference : null,
        root.codeSourceLineCount(candidate))
    }
    return root.bodyLineAdvance()
  }

  // Fenced-code markers are source-only rows. When a blank Markdown row sits
  // immediately before a fence, anchoring it to the first rendered code
  // glyph makes the live caret overlap the language header. Use the visible
  // code surface top as the block boundary instead.
  function cursorRectangleForBlockStart(blockIndex) {
    var block = root.blocks[blockIndex]
    var blockItem = blockRepeater.itemAt(blockIndex)
    if (!block || !blockItem) return null
    if (block.type !== "code") {
      return root.cursorRectangleForSource(block.sourceStart)
    }

    var codeContent = blockItem.codeReference
    if (!codeContent) return null
    var caretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
    return Qt.rect(
      root.horizontalPadding + Number(codeContent.x || 0),
      root.verticalPadding + Number(blockItem.y || 0) +
        Number(codeContent.y || 0),
      Math.max(1, Style.space(1)),
      Math.ceil(caretHeight))
  }

  function codeLanguageSourceRange(blockValue, sourceValue) {
    var block = blockValue || {}
    var source = String(sourceValue || "")
    var blockStart = Number(block.sourceStart)
    if (!isFinite(blockStart) || blockStart < 0 || blockStart > source.length) {
      return null
    }

    var openingLineEnd = source.indexOf("\n", blockStart)
    if (openingLineEnd < 0) openingLineEnd = source.length
    var openingLine = source.slice(blockStart, openingLineEnd)
    if (openingLine.charAt(openingLine.length - 1) === "\r") {
      openingLine = openingLine.slice(0, -1)
    }
    var fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(openingLine)
    if (!fence) return null

    var infoStart = blockStart + fence[0].length - fence[2].length
    var infoEnd = blockStart + openingLine.length
    var tokenMatch = /^\s*(\S+)/.exec(fence[2])
    var tokenStart = infoStart
    var tokenEnd = infoStart
    if (tokenMatch) {
      tokenStart += tokenMatch[0].length - tokenMatch[1].length
      tokenEnd = tokenStart + tokenMatch[1].length
    }
    return {
      infoStart: infoStart,
      infoEnd: infoEnd,
      tokenStart: tokenStart,
      tokenEnd: tokenEnd
    }
  }

  function cursorRectangleForCodeLanguage(blockValue, blockItem,
                                           sourceValue, sourcePosition) {
    if (!blockItem) return null
    var codeContent = blockItem.codeReference
    var languageLabel = blockItem.codeLanguageLabelReference
    if (!codeContent || !languageLabel || !languageLabel.visible) return null

    var range = root.codeLanguageSourceRange(blockValue, sourceValue)
    var position = Number(sourcePosition)
    if (!range || !isFinite(position) || position < range.infoStart ||
        position > range.infoEnd) return null

    var labelText = String(languageLabel.text || "")
    var sourceTokenLength = Math.max(0, range.tokenEnd - range.tokenStart)
    var sourceTokenOffset = Math.max(0, Math.min(sourceTokenLength,
      position - range.tokenStart))
    var labelOffset = sourceTokenLength > 0
      ? Math.round(sourceTokenOffset * labelText.length / sourceTokenLength)
      : 0
    var labelPrefix = labelText.slice(0, labelOffset)

    var labelPixelSize = Number(languageLabel.font.pixelSize) ||
      root.bodyPixelSize
    var labelCaretHeight = root.caretHeightForPixelSize(labelPixelSize)
    var labelLineHeight = Math.max(1, Number(languageLabel.height) ||
      Number(languageLabel.implicitHeight) || labelCaretHeight)
    return Qt.rect(
      root.horizontalPadding + Number(codeContent.x || 0) +
        Number(languageLabel.x || 0) +
        root.cursorWidth(labelPrefix, labelPixelSize),
      root.centeredCaretY(
        root.verticalPadding + Number(blockItem.y || 0) +
          Number(codeContent.y || 0) + Number(languageLabel.y || 0),
        labelLineHeight, labelCaretHeight),
      Math.max(1, Style.space(1)), Math.ceil(labelCaretHeight))
  }

  function bodyTextGlyphHeight() {
    bodyGlyphProbe.width = Math.max(1,
      root.width - root.horizontalPadding * 2)
    return Math.max(1, Number(bodyGlyphProbe.implicitHeight) ||
      Number(root.bodyPixelSize) || 1)
  }

  function blankLineLayoutHeight() {
    bodyGlyphProbe.width = Math.max(1,
      root.width - root.horizontalPadding * 2)
    // RichText's painted box includes the proportional line-height leading
    // that its implicit glyph box omits. Paragraph delegates size themselves
    // from this painted box, so a blank row must reserve the same height.
    return Math.max(1, Math.ceil(Number(bodyGlyphProbe.paintedHeight) ||
      Number(bodyGlyphProbe.implicitHeight) ||
      Number(root.bodyPixelSize) || 1))
  }

  function cursorRectangleForSource(sourcePosition) {
    if (!root.layoutReady || !root.layoutMatchesCurrentInput()) return null
    var position = Math.max(0, Math.min(Number(sourcePosition || 0), root.sourceText.length))
    var source = String(root.sourceText || "")

    var matchingBlockIndex = root.blockIndexForSourcePosition(position)
    if (matchingBlockIndex >= 0) {
      var blockIndex = matchingBlockIndex
      var block = root.blocks[blockIndex]

      var blockItem = blockRepeater.itemAt(blockIndex)
      if (!blockItem || !blockItem.contentActive ||
          !blockItem.loadedContent) return null

      if (block.type === "blank") {
        var blankCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        // The blank delegate is a real paragraph-sized row. Position its
        // caret with the same glyph box used by a one-line paragraph so the
        // caret baseline is already final before the first character exists.
        var blankCaretY = root.centeredCaretY(
          root.verticalPadding + blockItem.y,
          root.bodyTextGlyphHeight(), blankCaretHeight)

        var blankColumn = Math.max(0, Math.min(
          block.sourceEnd - block.sourceStart,
          position - block.sourceStart))
        var blankSource = source.slice(block.sourceStart, block.sourceEnd)

        return Qt.rect(
          root.horizontalPadding + root.cursorWidth(
            blankSource.slice(0, blankColumn), root.bodyPixelSize),
          blankCaretY,
          Math.max(1, Style.space(1)),
          Math.ceil(blankCaretHeight))
      }

      if (block.type === "image") {
        var imageSurface = blockItem.imageContentReference
        if (!imageSurface) return null
        var imageAltCaret = root.imageAltCaretRectangle(
          block, blockItem, imageSurface, position)
        if (imageAltCaret) return imageAltCaret
        var altEnd = Number(block.altSourceEnd)
        if (isFinite(altEnd) && position > altEnd) {
          // The destination and optional title are source-only after the
          // visible alt caption. Collapse those trailing positions to the
          // caption end so a following blank row is anchored below the image,
          // not halfway between the image's top edge and the next block.
          var imageTrailingCaret = root.imageAltCaretRectangle(
            block, blockItem, imageSurface, altEnd)
          if (imageTrailingCaret) return imageTrailingCaret
        }
        var imageCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        return Qt.rect(
          root.horizontalPadding + Number(imageSurface.x || 0),
          root.verticalPadding + Number(blockItem.y || 0) +
            Number(imageSurface.y || 0),
          Math.max(1, Style.space(1)), Math.ceil(imageCaretHeight))
      }

      if (block.type === "heading") {
        var headingContentStart = Math.max(0,
          Number(block.contentSourceStart) - Number(block.sourceStart))
        var headingContent = String(block.plain || "")
        var headingColumn = Math.max(0, Math.min(
          headingContent.length,
          position - block.sourceStart - headingContentStart))
        var headingBefore = root.plainInlinePrefix(
          headingContent, headingColumn)
        var headingSize = root.bodyPixelSize *
          (block.level === 1 ? 1.55 : block.level === 2 ? 1.3 : 1.15)
        var headingLineHeight = Math.max(1,
          Number(blockItem.headingTextReference.implicitHeight))
        var headingCaretHeight = root.caretHeightForPixelSize(headingSize)
        return Qt.rect(
          root.horizontalPadding + root.cursorWidth(headingBefore, headingSize),
          root.centeredCaretY(
            root.verticalPadding + blockItem.y + blockItem.headingTextReference.y,
            headingLineHeight, headingCaretHeight),
          Math.max(1, Style.space(1)),
          Math.ceil(headingCaretHeight))
      }

      if (block.type === "quote") {
        var quoteSource = source.slice(block.sourceStart, block.sourceEnd)
        var quoteTextItem = blockItem.quoteTextReference
        var quoteProbe = blockItem.quoteHitProbeReference
        var visibleOffset = root.quotePlainPrefix(
          quoteSource, position - block.sourceStart).length
        var quoteNativeRect = quoteProbe && quoteProbe.positionToRectangle
          ? quoteProbe.positionToRectangle(visibleOffset) : null
        var quoteCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        if (quoteNativeRect) {
          var quoteProbeScale = root.selectionMirrorVerticalScale(
            quoteTextItem.height, quoteProbe.contentHeight)
          return Qt.rect(
            root.horizontalPadding + blockItem.quoteContentReference.x +
              quoteTextItem.x + Number(quoteNativeRect.x || 0),
            root.centeredCaretY(
              root.verticalPadding + blockItem.y +
                blockItem.quoteContentReference.y + quoteTextItem.y +
                Number(quoteNativeRect.y || 0) * quoteProbeScale,
              Math.max(1, Number(quoteNativeRect.height) * quoteProbeScale ||
                quoteCaretHeight),
              quoteCaretHeight),
            Math.max(1, Style.space(1)), Math.ceil(quoteCaretHeight))
        }
        var quoteLocation = root.wrappedTextCursorLocation(
          root.quotePlainPrefix(quoteSource,
            position - block.sourceStart), quoteTextItem.width)
        var quoteLineAdvance = root.bodyLineAdvance()
        return Qt.rect(
          root.horizontalPadding + blockItem.quoteContentReference.x +
            quoteTextItem.x + root.cursorWidth(
              quoteLocation.text, root.bodyPixelSize),
          root.centeredCaretY(
            root.verticalPadding + blockItem.y + quoteTextItem.y +
              quoteLineIndex * quoteLineAdvance +
              quoteLocation.lineIndex * quoteLineAdvance,
            quoteLineAdvance, quoteCaretHeight),
          Math.max(1, Style.space(1)), Math.ceil(quoteCaretHeight))
      }

      if (block.type === "code") {
        var languageCaret = root.cursorRectangleForCodeLanguage(
          block, blockItem, source, position)
        if (languageCaret) return languageCaret

        var codeTextItem = blockItem.codeTextReference
        if (codeTextItem && codeTextItem.positionToRectangle) {
          var codeOffset = root.codeTextOffsetForSourcePosition(
            block, position)
          var codeRect = codeTextItem.positionToRectangle(codeOffset)
          var codeRectHeight = Math.max(1, Number(codeRect.height) ||
            root.codeLineAdvanceForText(codeTextItem,
              root.codeSourceLineCount(block)))
          var codeCaretHeight = Math.min(codeRectHeight,
            root.caretHeightForPixelSize(root.bodyPixelSize))
          return Qt.rect(
            root.horizontalPadding + codeTextItem.x + Number(codeRect.x || 0),
            root.verticalPadding + blockItem.y + codeTextItem.y +
              Number(codeRect.y || 0) +
              Math.max(0, (codeRectHeight - codeCaretHeight) / 2),
            Math.max(1, Style.space(1)), Math.ceil(codeCaretHeight))
        }

        var codeSource = source.slice(block.sourceStart, block.sourceEnd)
        var codeLines = codeSource.replace(/\r\n/g, "\n").split("\n")
        var codeTextLines = String(block.text || "").split("\n")
        var codeLineIndex = Math.max(0, Math.min(
          Math.max(0, codeTextLines.length - 1),
          codeSource.slice(0, Math.max(0, position - block.sourceStart))
            .split("\n").length - 2))
        var codeLine = codeTextLines[codeLineIndex] || ""
        var codeLineStart = 0
        for (var codeIndex = 0; codeIndex < codeLineIndex + 1 &&
             codeIndex < codeLines.length; codeIndex++) {
          codeLineStart += codeLines[codeIndex].length + 1
        }
        var codeColumn = Math.max(0, Math.min(codeLine.length,
          position - block.sourceStart - codeLineStart))
        var codeLocation = root.wrappedTextCursorLocation(
          codeLine.slice(0, codeColumn), codeTextItem.width)
        var codeLineAdvance = root.codeLineAdvanceForText(codeTextItem,
          root.codeSourceLineCount(block))
        var codeCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        return Qt.rect(
          root.horizontalPadding + codeTextItem.x +
            root.cursorWidth(codeLocation.text, root.bodyPixelSize),
          root.centeredCaretY(
            root.verticalPadding + blockItem.y + codeTextItem.y +
              codeLineIndex * codeLineAdvance +
              codeLocation.lineIndex * codeLineAdvance,
            codeLineAdvance, codeCaretHeight),
          Math.max(1, Style.space(1)), Math.ceil(codeCaretHeight))
      }

      if (block.type === "rule") {
        var ruleCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        var ruleLineAdvance = root.bodyLineAdvance()
        return Qt.rect(
          root.horizontalPadding,
          root.centeredCaretY(
            root.verticalPadding + blockItem.y,
            ruleLineAdvance, ruleCaretHeight),
          Math.max(1, Style.space(1)), Math.ceil(ruleCaretHeight))
      }

      if (block.type === "table") {
        var tableSource = source.slice(block.sourceStart, block.sourceEnd)
        var tableLines = tableSource.split("\n")
        var tableLineIndex = Math.max(0, Math.min(
          tableLines.length - 1,
          tableSource.slice(0, Math.max(0, position - block.sourceStart))
            .split("\n").length - 1))
        var tableLineStart = block.sourceStart
        for (var tableLine = 0; tableLine < tableLineIndex; tableLine++) {
          tableLineStart += tableLines[tableLine].length + 1
        }
        var tableLineText = (tableLines[tableLineIndex] || "").replace(/\r$/, "")
        var tableLineColumn = Math.max(0,
          position - tableLineStart)
        var tableCells = root.splitTableRow(tableLineText)
        var tableColumnIndex = 0
        var tableColumnStart = 0
        for (var tableColumn = 0; tableColumn < tableCells.length;
             tableColumn++) {
          var cellText = String(tableCells[tableColumn] || "")
          var foundCellStart = tableLineText.indexOf(cellText, tableColumnStart)
          if (foundCellStart < 0) foundCellStart = tableColumnStart
          var foundCellEnd = foundCellStart + cellText.length
          tableColumnIndex = tableColumn
          tableColumnStart = foundCellEnd + 1
          if (tableLineColumn <= foundCellEnd ||
              tableColumn === tableCells.length - 1) {
            var cellColumn = Math.max(0, Math.min(cellText.length,
              tableLineColumn - foundCellStart))
            break
          }
        }
        var tableRowIndex = Math.max(0, Math.min(
          (block.rows || []).length - 1, tableLineIndex - 1))
        var tableRowItem = blockItem.tableRowsReference
          ? blockItem.tableRowsReference.itemAt(tableRowIndex) : null
        var tableRowHeight = tableRowItem
          ? Number(tableRowItem.height) : Style.space(34)
        var tableCell = tableRowItem && tableRowItem.cellRepeaterReference
          ? tableRowItem.cellRepeaterReference.itemAt(tableColumnIndex) : null
        var tableCellText = tableCell && tableCell.cellTextReference
          ? tableCell.cellTextReference : null
        var tableCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        var tableRowY = tableRowItem ? Number(tableRowItem.y) : 0
        var tableTextY = tableCellText ? Number(tableCellText.y) : Style.space(7)
        var tableCellContent = tableCells[tableColumnIndex] || ""
        var tableLocation = root.wrappedTextCursorLocation(
          root.plainInlinePrefix(tableCellContent, cellColumn),
          tableCellText ? tableCellText.width : Style.space(60))
        var tableLineAdvance = root.bodyLineAdvance()
        var tableRenderedLineCount = tableCellText
          ? Math.max(1, Number(tableCellText.lineCount) || 1) : 1
        var tableCellHeight = tableCellText
          ? Math.max(1, Number(tableCellText.implicitHeight) || 1) :
            Math.max(1, tableRowHeight - Style.space(14))
        var tableGlyphHeight = Math.max(1,
          tableCellHeight - (tableRenderedLineCount - 1) * tableLineAdvance)
        return Qt.rect(
          root.horizontalPadding + (tableCell ? Number(tableCell.x) : 0) +
            (tableCellText ? Number(tableCellText.x) : Style.space(7)) +
            root.cursorWidth(tableLocation.text, root.bodyPixelSize),
          root.centeredCaretY(
            root.verticalPadding + blockItem.y + tableRowY + tableTextY +
              tableLocation.lineIndex * tableLineAdvance,
            tableGlyphHeight,
            tableCaretHeight),
          Math.max(1, Style.space(1)), Math.ceil(tableCaretHeight))
      }

      if (block.type === "paragraph") {
        var paragraphTextItem = blockItem.paragraphTextReference
        var paragraphSource = root.sourceText.slice(
          block.sourceStart, block.sourceEnd)
        var paragraphProbe = blockItem.blockHitProbeReference
        var paragraphSourceOffset = Math.max(0,
          position - block.sourceStart)
        var paragraphProbeText = root.blockHitProbeText(block)
        // A source-aligned plain paragraph can use the native TextEdit caret
        // rectangle directly. Markdown delimiters and hard-break spaces make
        // the final visible projection shorter than the source; keep the
        // established source-aware fallback for those positions.
        var paragraphNativeRect = paragraphProbe &&
          paragraphProbeText.length === paragraphSource.length &&
          paragraphProbe.positionToRectangle
          ? paragraphProbe.positionToRectangle(paragraphSourceOffset)
          : null
        var paragraphMetrics = root.paragraphLineMetrics(block, blockItem)
        var paragraphCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
        if (paragraphNativeRect) {
          var paragraphProbeLineCount = Math.max(1,
            Number(paragraphProbe.lineCount) || 1)
          var paragraphProbeLineAdvance = Math.max(1,
            Number(paragraphProbe.contentHeight) /
              paragraphProbeLineCount ||
            Number(paragraphNativeRect.height) || 1)
          var paragraphRowIndex = Math.max(0, Math.min(
            paragraphProbeLineCount - 1,
            Math.floor((Number(paragraphNativeRect.y) +
              Number(paragraphNativeRect.height) / 2) /
              paragraphProbeLineAdvance)))
          return Qt.rect(
            root.horizontalPadding + Number(paragraphNativeRect.x || 0),
            root.centeredCaretY(
              root.verticalPadding + blockItem.y + paragraphTextItem.y +
                paragraphRowIndex * paragraphMetrics.lineAdvance,
              paragraphMetrics.glyphHeight, paragraphCaretHeight),
            Math.max(1, Style.space(1)),
            Math.ceil(paragraphCaretHeight))
        }
        var paragraphCursor = root.paragraphCursorLocation(
          paragraphSource, paragraphTextItem.width,
          Math.max(0, position - block.sourceStart))
        var paragraphLineTop = root.verticalPadding + blockItem.y +
          paragraphTextItem.y + paragraphCursor.lineIndex *
            paragraphMetrics.lineAdvance
        return Qt.rect(
          root.horizontalPadding +
            root.cursorWidth(paragraphCursor.text, root.bodyPixelSize),
          root.centeredCaretY(paragraphLineTop,
            paragraphMetrics.glyphHeight, paragraphCaretHeight),
          Math.max(1, Style.space(1)),
          Math.ceil(paragraphCaretHeight))
      }

      if (block.type === "list") {
        for (var itemIndex = 0; itemIndex < block.items.length; itemIndex++) {
          var item = block.items[itemIndex]
          if (position < item.sourceStart || position > item.sourceEnd) continue
          var listItem = blockItem.listViewReference.itemAtIndex(itemIndex)
          if (!listItem) return null

          var rawItem = root.sourceText.slice(item.sourceStart, item.sourceEnd)
          var contentStart = root.listItemContentStart(item)
          var markerPrefix = /^(\s*)([-+*]|\d+[.)])/.exec(rawItem)
          var separatorStart = markerPrefix ? markerPrefix[0].length : contentStart
          var rawOffset = Math.max(0, position - item.sourceStart)
          var listCaretX
          var emptyPlainItem = !item.task &&
            String(item.plain || "") === ""
          if (emptyPlainItem && rawOffset >= separatorStart &&
              rawOffset <= contentStart) {
            // An empty bullet has no rendered text to anchor its separator
            // spaces. Give each source space its own caret column so typing
            // or navigating through `-  ` remains visible in Live mode.
            var separatorText = rawItem.slice(separatorStart, contentStart)
            var separatorColumn = Math.max(0, Math.min(
              rawOffset - separatorStart, separatorText.length))
            listCaretX = root.horizontalPadding + listItem.textOriginX -
              root.cursorWidth(" ", root.bodyPixelSize) +
              root.cursorWidth(separatorText.slice(0, separatorColumn),
                root.bodyPixelSize)
          } else if (rawOffset < contentStart) {
            // Source positions inside a Markdown marker/checkbox have no
            // separate editable glyph in Live mode. Keep the caret at the
            // visible start of the marker area instead of falsely placing it
            // at the first text column for several consecutive positions.
            listCaretX = root.horizontalPadding + listItem.rowReference.x
          } else {
            var itemContent = rawItem.slice(contentStart)
            var itemColumn = Math.max(0, Math.min(
              itemContent.length, rawOffset - contentStart))
            listCaretX = root.horizontalPadding + listItem.textOriginX +
              root.cursorWidth(root.wrappedTextCursorLocation(
                root.plainInlinePrefix(itemContent, itemColumn),
                listItem.itemTextReference.width).text, root.bodyPixelSize)
          }
          var listCaretHeight = root.caretHeightForPixelSize(root.bodyPixelSize)
          var listContent = rawItem.slice(contentStart)
          var listColumn = Math.max(0, Math.min(
            listContent.length, rawOffset - contentStart))
          var listPlainContent = root.plainInline(listContent)
          var listLineMetrics = root.listTextLineMetrics(
            listItem.itemTextReference, listPlainContent)
          var listHitProbe = listItem.hitProbeReference
          var listNativeRect = !emptyPlainItem &&
            rawOffset >= contentStart &&
            listPlainContent.length === listContent.length &&
            listHitProbe && listHitProbe.positionToRectangle
            ? listHitProbe.positionToRectangle(listColumn) : null
          if (listNativeRect) {
            var listProbeLineCount = Math.max(1,
              Number(listHitProbe.lineCount) || 1)
            var listProbeLineAdvance = Math.max(1,
              Number(listHitProbe.contentHeight) / listProbeLineCount ||
              Number(listNativeRect.height) || 1)
            var listNativeRow = Math.max(0, Math.min(
              listLineMetrics.lineCount - 1,
              Math.floor((Number(listNativeRect.y) +
                Number(listNativeRect.height) / 2) /
                listProbeLineAdvance)))
            return Qt.rect(
              root.horizontalPadding + listItem.textOriginX +
                Number(listNativeRect.x || 0),
              root.caretTopForBaseline(
                root.verticalPadding + blockItem.y + listItem.y +
                  listItem.textOriginY +
                  Number(listItem.itemTextReference.baselineOffset) +
                  listNativeRow * listLineMetrics.lineAdvance,
                root.bodyPixelSize, listCaretHeight),
              Math.max(1, Style.space(1)),
              Math.ceil(listCaretHeight))
          }
          var listTextMetrics = root.wrappedTextCursorLocation(
            root.plainInlinePrefix(listContent, listColumn),
            listItem.itemTextReference.width)
          return Qt.rect(
            listCaretX,
            root.caretTopForBaseline(
              root.verticalPadding + blockItem.y + listItem.y +
                listItem.textOriginY +
                Number(listItem.itemTextReference.baselineOffset) +
                (rawOffset < contentStart ? 0 :
                  listTextMetrics.lineIndex * listLineMetrics.lineAdvance),
              root.bodyPixelSize, listCaretHeight),
            Math.max(1, Style.space(1)),
            Math.ceil(listCaretHeight))
        }
      }
    }
    // A CRLF newline occupies two source positions. The parser keeps source
    // offsets in the original file, so map the LF half to the same visual
    // caret as the preceding CR half.
    if (source.charAt(position) === "\n" &&
        source.charAt(Math.max(0, position - 1)) === "\r") {
      return root.cursorRectangleForSource(position - 1)
    }
    return null
  }

  function cursorTargetForSource(sourcePosition) {
    var position = Math.max(0,
      Math.min(Number(sourcePosition) || 0, root.sourceText.length))
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var block = root.blocks[blockIndex]
      if (block.sourceStart === undefined || block.sourceEnd === undefined ||
          position < block.sourceStart || position > block.sourceEnd) continue
      if (block.type !== "list") {
        return { blockType: block.type, blockIndex: blockIndex, itemIndex: -1 }
      }
      for (var itemIndex = 0; itemIndex < block.items.length; itemIndex++) {
        var item = block.items[itemIndex]
        if (position >= item.sourceStart && position <= item.sourceEnd) {
          return { blockType: block.type, blockIndex: blockIndex,
            itemIndex: itemIndex }
        }
      }
      return { blockType: block.type, blockIndex: blockIndex, itemIndex: -1 }
    }
    return { blockType: "none", blockIndex: -1, itemIndex: -1 }
  }

  // Kept intentionally small so live regression tests can compare the
  // rendered row geometry with the source-position caret geometry. This also
  // makes spacing failures diagnosable without relying on a screenshot alone.
  function layoutMetricsForTests() {
    var metrics = []
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var block = root.blocks[blockIndex]
      var blockItem = blockRepeater.itemAt(blockIndex)
      var geometryEntry = root.blockGeometryEntry(blockIndex)
      var entry = {
        type: String(block.type || ""),
        sourceStart: Number(block.sourceStart),
        sourceEnd: Number(block.sourceEnd),
        y: blockItem ? Number(blockItem.y) : -1,
        height: blockItem ? Number(blockItem.height) : -1,
        layoutHeight: Number(block.layoutHeight) || 0,
        contentActive: Boolean(blockItem && blockItem.contentActive),
        estimatedHeight: blockItem ? Number(blockItem.estimatedHeight) : 0,
        measuredHeight: blockItem ? Number(blockItem.measuredHeight) : 0,
        provisionalHeight: geometryEntry
          ? Number(geometryEntry.provisionalHeight) || 0 : 0
      }
      entry.geometryTop = geometryEntry ? Number(geometryEntry.top) : -1
      entry.geometryHeight = geometryEntry ? Number(geometryEntry.height) : -1
      if (block.type === "paragraph" && blockItem &&
          blockItem.paragraphTextReference) {
        var paragraphMetrics = root.paragraphLineMetrics(block, blockItem)
        entry.sourceLineCount = Number(block.sourceLineCount) || 1
        entry.textY = Number(blockItem.paragraphTextReference.y)
        entry.textHeight = Number(blockItem.paragraphTextReference.implicitHeight)
        entry.glyphHeight = Number(paragraphMetrics.glyphHeight)
        entry.lineAdvance = Number(paragraphMetrics.lineAdvance)
      }
      if (block.type === "image" && blockItem &&
          blockItem.imageContentReference) {
        var imageSurface = blockItem.imageContentReference
        entry.imageSource = String(block.imageSource || "")
        entry.imageStatus = Number(imageSurface.imageStatus)
        entry.imageWidth = Number(imageSurface.renderedWidth) || 0
        entry.imageHeight = Number(imageSurface.renderedHeight) || 0
        entry.imageContentHeight = Number(imageSurface.height) || 0
        entry.imageAltText = imageSurface.imageAltTextReference
          ? String(imageSurface.imageAltTextReference.text || "") : ""
        entry.imageAltVisible = Boolean(imageSurface.imageAltTextReference &&
          imageSurface.imageAltTextReference.visible)
        entry.imageAltY = imageSurface.imageAltTextReference
          ? Number(imageSurface.imageAltTextReference.y) : 0
        entry.imageAltHeight = imageSurface.imageAltTextReference
          ? Number(imageSurface.imageAltTextReference.implicitHeight) || 0 : 0
      }
      if (block.type === "blank" && blockItem &&
          blockItem.blankContentReference) {
        var blankSurface = blockItem.blankContentReference
        var blankHitArea = blankSurface.blankHitAreaReference
        entry.blankHitAreaY = blankHitArea ? Number(blankHitArea.y) : 0
        entry.blankHitAreaHeight = blankHitArea
          ? Number(blankHitArea.height) : 0
      }
      if (block.type === "list" && blockItem && blockItem.listViewReference) {
        var firstItem = blockItem.listViewReference.itemAtIndex(0)
        if (firstItem) {
          entry.textY = Number(firstItem.y + firstItem.textOriginY)
          entry.textHeight = Number(firstItem.itemTextReference.implicitHeight)
        }
        entry.listItems = []
        for (var listMetricIndex = 0;
             listMetricIndex < block.items.length; listMetricIndex++) {
          var metricItem = blockItem.listViewReference.itemAtIndex(listMetricIndex)
          if (!metricItem) continue
          var metricPlainText = root.plainInline(
            metricItem.itemData.plain || "")
          var metricLineMetrics = root.listTextLineMetrics(
            metricItem.itemTextReference, metricPlainText)
          entry.listItems.push({
            task: Boolean(metricItem.itemData.task),
            checked: Boolean(metricItem.taskBoxReference.checked),
            plain: String(metricItem.itemData.plain || ""),
            hitAfterTwoPosition: root.listSourcePosition(
              metricItem.itemData,
              metricItem.hitProbeReference,
              root.cursorWidth("fs", root.bodyPixelSize),
              metricItem.hitProbeReference.baselineOffset),
            hitAfterFourPosition: root.listSourcePosition(
              metricItem.itemData,
              metricItem.hitProbeReference,
              root.cursorWidth("fsda", root.bodyPixelSize),
              metricItem.hitProbeReference.baselineOffset),
            firstSelectablePosition: root.listItemFirstSelectablePosition(
              metricItem.itemData),
            markerHitEnabled: Boolean(
              metricItem.markerHitAreaReference.enabled),
            markerCursorShape: Number(
              metricItem.markerHitAreaReference.cursorShape),
            textCursorShape: Number(
              metricItem.itemHitAreaReference.cursorShape),
            checkboxY: Number(metricItem.taskBoxReference.y),
            checkboxHeight: Number(metricItem.taskBoxReference.height),
            textBaseline: Number(metricItem.itemTextReference.baselineOffset),
            fontCapTop: Number(root.bodyCapBounds.y),
            fontCapHeight: Number(root.bodyCapBounds.height),
            fontCaretTop: Number(root.bodyCaretBounds.y),
            fontCaretHeight: Number(root.bodyCaretBounds.height),
            fontAscent: Number(bodyFontMetrics.ascent),
            fontHeight: Number(bodyFontMetrics.height),
            caretHeight: Number(root.caretHeightForPixelSize(
              root.bodyPixelSize)),
            itemY: Number(metricItem.y),
            textY: Number(metricItem.textOriginY),
            textOriginX: Number(metricItem.textOriginX),
            lineCount: Number(metricLineMetrics.lineCount),
            lineAdvance: Number(metricLineMetrics.lineAdvance),
            glyphHeight: Number(metricLineMetrics.glyphHeight)
          })
        }
      }
      if (block.type === "table" && blockItem && blockItem.tableRowsReference) {
        entry.rowCount = Number((block.rows || []).length)
        entry.columnCount = Number((block.columnWidths || []).length)
        entry.tableRows = []
        for (var tableRowIndex = 0;
             tableRowIndex < entry.rowCount; tableRowIndex++) {
          var tableRowItem = blockItem.tableRowsReference.itemAt(tableRowIndex)
          var requiredHeight = 0
          if (tableRowItem && tableRowItem.cellRepeaterReference) {
            for (var cellIndex = 0;
                 cellIndex < entry.columnCount; cellIndex++) {
              var cellItem = tableRowItem.cellRepeaterReference.itemAt(cellIndex)
              if (cellItem && cellItem.cellTextReference) {
                requiredHeight = Math.max(requiredHeight,
                  Number(cellItem.cellTextReference.implicitHeight) +
                    Style.space(14))
              }
            }
          }
          entry.tableRows.push({
            height: tableRowItem ? Number(tableRowItem.height) : 0,
            requiredHeight: requiredHeight,
            lineCount: tableRowItem && tableRowItem.cellRepeaterReference &&
              tableRowItem.cellRepeaterReference.itemAt(0) &&
              tableRowItem.cellRepeaterReference.itemAt(0).cellTextReference
              ? Number(tableRowItem.cellRepeaterReference.itemAt(0)
                .cellTextReference.lineCount) : 0
          })
        }
      }
      if (block.type === "code" && blockItem &&
          blockItem.codeTextReference) {
        entry.codeLineCount = Math.max(1,
          Number(blockItem.codeTextReference.lineCount) || 0)
        entry.codeSourceLineCount = root.codeSourceLineCount(block)
        entry.codeLanguage = String(block.language || "")
        entry.codeLabel = blockItem.codeLanguageLabelReference &&
          blockItem.codeLanguageLabelReference.visible
          ? String(blockItem.codeLanguageLabelReference.text || "") : ""
        entry.codeLabelY = blockItem.codeLanguageLabelReference &&
          blockItem.codeLanguageLabelReference.visible
          ? Number(blockItem.codeLanguageLabelReference.y) : 0
        entry.codeLabelHeight = blockItem.codeLanguageLabelReference &&
          blockItem.codeLanguageLabelReference.visible
          ? Number(blockItem.codeLanguageLabelReference.height) : 0
        entry.codeDefinitionName = root.codeDefinitionNameForBlock(block)
        entry.codeTextHeight = Number(
          blockItem.codeTextReference.contentHeight) ||
          Number(blockItem.codeTextReference.implicitHeight) || 0
        entry.codeContentHeight = Number(blockItem.codeReference.height) || 0
        entry.codeContentY = Number(blockItem.codeReference.y) || 0
        entry.codeTextY = Number(blockItem.codeTextReference.y) || 0
        entry.codeLineAdvance = root.codeLineAdvanceForText(
          blockItem.codeTextReference, entry.codeSourceLineCount)
      }
      metrics.push(entry)
    }
    return metrics
  }

  function followingCursorRectangleForSource(sourcePosition) {
    var position = Math.max(0,
      Math.min(Number(sourcePosition) || 0, root.sourceText.length))
    for (var blockIndex = 0; blockIndex < root.blocks.length; blockIndex++) {
      var block = root.blocks[blockIndex]
      if (block.sourceStart === undefined || block.sourceStart <= position ||
          block.type === "blank") continue
      return root.cursorRectangleForBlockStart(blockIndex)
    }
    return null
  }

  TextMetrics {
    id: cursorMetrics
  }

  Text {
    id: paragraphWrapProbe
    x: -100000
    y: -100000
    width: 1
    height: 1
    opacity: 0
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    font.family: root.fontFamily
    font.pixelSize: root.bodyPixelSize
    lineHeight: root.bodyLineHeightFactor
    lineHeightMode: Text.ProportionalHeight
  }

  Text {
    id: bodyGlyphProbe
    x: -100000
    y: -100000
    width: Math.max(1, root.width - root.horizontalPadding * 2)
    height: Math.ceil(paintedHeight)
    opacity: 0
    text: "x"
    textFormat: Text.RichText
    wrapMode: Text.Wrap
    font.family: root.fontFamily
    font.pixelSize: root.bodyPixelSize
    lineHeight: root.bodyLineHeightFactor
    lineHeightMode: Text.ProportionalHeight
  }

  Text {
    id: codeLineProbe
    x: -100000
    y: -100000
    width: 1
    opacity: 0
    text: "x\nx"
    textFormat: Text.PlainText
    wrapMode: Text.NoWrap
    font.family: root.fontFamily
    font.pixelSize: root.bodyPixelSize
    lineHeight: root.bodyLineHeightFactor
    lineHeightMode: Text.ProportionalHeight
  }

  Text {
    id: tableHeightProbe
    x: -100000
    y: -100000
    width: 1
    height: 1
    opacity: 0
    baseUrl: root.baseUrl
    textFormat: Text.RichText
    wrapMode: Text.Wrap
    font.family: root.fontFamily
    font.pixelSize: root.bodyPixelSize
    lineHeight: root.bodyLineHeightFactor
    lineHeightMode: Text.ProportionalHeight
  }

  FontMetrics {
    id: bodyFontMetrics
    font.family: root.fontFamily
    font.pixelSize: root.bodyPixelSize
  }

  Timer {
    id: rebuildTimer
    interval: 0
    repeat: false
    onTriggered: root.rebuild()
  }

  Timer {
    id: layoutSettleTimer
    interval: 0
    repeat: false
    onTriggered: {
      if (!root.layoutMatchesCurrentInput()) {
        root.invalidateLayout()
        return
      }
      root.layoutReady = true
      selectionTargetSettleTimer.restart()
      root.layoutUpdated()
    }
  }

  Timer {
    id: selectionTargetSettleTimer
    // Let the Column/Repeater polish pass finish before taking coordinates
    // from the rendered delegates. A zero-delay timer can run before those
    // positions are final on the first frame of a newly parsed note.
    interval: 16
    repeat: false
    onTriggered: {
      if (!root.layoutReady || !root.layoutMatchesCurrentInput()) return
      root.rebuildSelectionTargets()
      root.rebuildSelection()
    }
  }

  Timer {
    id: viewportSettleTimer
    interval: 16
    repeat: false
    onTriggered: {
      if (!root.layoutMatchesCurrentInput()) return
      selectionTargetSettleTimer.restart()
      root.layoutUpdated()
    }
  }

  Timer {
    id: blockMeasurementTimer
    interval: 0
    repeat: false
    onTriggered: root.flushMeasuredBlockHeights()
  }

  Timer {
    id: mouseSelectionFrameTimer
    interval: 8
    repeat: false
    onTriggered: root.flushMouseSelection()
  }

  Timer {
    id: selectionUpdateTimer
    interval: 0
    repeat: false
    onTriggered: {
      root.selectionRevision += 1
      root.rebuildSelection()
    }
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

  Item {
    id: selectionLayer
    anchors.fill: parent
    // Keep selection behind rendered glyphs so selected text remains readable.
    // The fenced-code surface is translucent, so the highlight still shows
    // through its background without covering the code itself.
    z: 0

    Repeater {
      model: root.selectionRects

      delegate: Rectangle {
        x: modelData.x
        y: modelData.y
        width: modelData.width
        height: modelData.height
        // Selection surfaces should meet like normal editor rows; rounded
        // corners make every selected line look like a separate pill.
        radius: 0
        color: root.selectionFill
      }
    }
  }

  // TextEdit already knows how to paint a selection over wrapped rich text:
  // it produces one square, glyph-aligned range per visual row and updates
  // the range without rebuilding the Markdown layout. These transparent
  // mirrors provide that native selection paint while the real Markdown
  // delegates below remain the only visible text.
  Item {
    id: selectionTextLayer
    anchors.fill: parent
    z: 0.5

    Repeater {
      id: selectionMirrorRepeater
      model: root.selectionTargets

      delegate: TextEdit {
        property var targetData: modelData
        property int selectionRevision: root.selectionRevision

        x: Number(targetData.x) || 0
        y: Number(targetData.y) || 0
        z: Number(targetData.selectionZ) || 0.5
        width: Math.max(1, Number(targetData.width) || 1)
        property real targetHeight: Math.max(1, Number(targetData.height) || 1)
        height: targetHeight
        // Text uses a deliberate proportional line height while TextEdit's
        // native selection surface uses the platform line advance. Stretch
        // only the transparent mirror so its native highlight rows line up
        // with the visible Markdown glyph rows.
        transform: Scale {
          origin.x: 0
          origin.y: 0
          yScale: root.selectionMirrorVerticalScale(
            targetHeight, contentHeight)
        }
        text: targetData.kind === "code"
          ? String(targetData.html || "")
          : root.selectionOverlayHtml(targetData.html)
        baseUrl: root.baseUrl
        textFormat: targetData.kind === "code"
          ? TextEdit.PlainText : TextEdit.RichText
        wrapMode: TextEdit.Wrap
        readOnly: true
        selectByMouse: false
        selectByKeyboard: false
        activeFocusOnPress: false
        persistentSelection: true
        cursorVisible: false
        color: "transparent"
        selectionColor: root.selectionFill
        selectedTextColor: "transparent"
        font.family: root.fontFamily
        font.pixelSize: Number(targetData.pixelSize) || root.bodyPixelSize
        font.bold: Boolean(targetData.bold)

        function syncSelection() {
          if (!targetData) return
          var range = root.selectionRangeForTarget(targetData)
          var start = Math.max(0, Math.min(length, Number(range.start) || 0))
          var end = Math.max(0, Math.min(length, Number(range.end) || 0))
          if (start === selectionStart && end === selectionEnd) return
          select(start, end)
        }

        onSelectionRevisionChanged: syncSelection()
        onTextChanged: Qt.callLater(syncSelection)
        Component.onCompleted: Qt.callLater(syncSelection)
      }
    }
  }

  Column {
    id: displayColumn
    z: 1
    x: root.horizontalPadding
    y: root.verticalPadding
    width: Math.max(0, root.width - root.horizontalPadding * 2)
    spacing: root.blockSpacing

    Repeater {
      id: blockRepeater
      model: root.blocks

      delegate: Item {
        id: blockDelegate
        property var block: modelData
        property real geometryTop: {
          var revision = root.blockGeometryRevision
          var entry = root.blockGeometry[index]
          return entry ? Number(entry.top) || 0 : 0
        }
        property real measuredHeight: {
          var revision = root.blockGeometryRevision
          var entry = root.blockGeometry[index]
          return entry ? Number(entry.measuredHeight) || 0 : 0
        }
        property real estimatedHeight: {
          var revision = root.blockGeometryRevision
          var entry = root.blockGeometry[index]
          return entry ? Number(entry.estimatedHeight) || 0 :
            root.estimatedBlockHeight(block, width)
        }
        property real renderExtent: {
          var revision = root.blockGeometryRevision
          var entry = root.blockGeometry[index]
          return entry ? Math.max(1, Number(entry.height) || 1) :
            Math.max(1, measuredHeight, estimatedHeight)
        }
        property bool contentActive: root.blockIntersectsRenderWindow(
          index, geometryTop, renderExtent)
        property var loadedContent: blockContentLoader.item
        property real loadedContentHeight: loadedContent
          ? Number(loadedContent.implicitHeight) || 0 : 0
        property var blankContentReference: loadedContent
          ? loadedContent.blankContentReference : null
        property var imageContentReference: loadedContent
          ? loadedContent.imageContentReference : null
        property var blockHitProbeReference: loadedContent
          ? loadedContent.blockHitProbeReference : null
        property var headingTextReference: loadedContent
          ? loadedContent.headingTextReference : null
        property var paragraphTextReference: loadedContent
          ? loadedContent.paragraphTextReference : null
        property var paragraphContinuationReference: loadedContent
          ? loadedContent.paragraphContinuationReference : null
        property var listViewReference: loadedContent
          ? loadedContent.listViewReference : null
        property var quoteContentReference: loadedContent
          ? loadedContent.quoteContentReference : null
        property var quoteTextReference: loadedContent
          ? loadedContent.quoteTextReference : null
        property var quoteHitProbeReference: loadedContent
          ? loadedContent.quoteHitProbeReference : null
        property var codeReference: loadedContent
          ? loadedContent.codeReference : null
        property var codeLanguageLabelReference: loadedContent
          ? loadedContent.codeLanguageLabelReference : null
        property var codeTextReference: loadedContent
          ? loadedContent.codeTextReference : null
        property var codePaintReference: loadedContent
          ? loadedContent.codePaintReference : null
        property var ruleReference: loadedContent
          ? loadedContent.ruleReference : null
        property var tableReference: loadedContent
          ? loadedContent.tableReference : null
        property var tableRowsReference: loadedContent
          ? loadedContent.tableRowsReference : null
        width: displayColumn.width
        implicitHeight: {
          var revision = root.blockGeometryRevision
          var entry = root.blockGeometry[index]
          return entry ? Math.max(0, Number(entry.height) || 0) :
            block.type === "blank" ? Number(block.layoutHeight) || 0 :
            Math.max(1, measuredHeight || estimatedHeight)
        }
        height: implicitHeight
        // The shell must remain in the Column even while its heavy Loader is
        // inactive; QML positioners omit invisible children, which would
        // collapse every offscreen spacer and corrupt the height index.
        visible: true

        onContentActiveChanged: root.viewportContentChanged()
        onBlockChanged: {
          if (contentActive && block.type === "code")
            root.requestCodeHighlight(block)
        }
        onLoadedContentHeightChanged: {
          if (contentActive && loadedContentHeight > 0)
            root.queueMeasuredBlockHeight(index, loadedContentHeight)
        }

        Loader {
          id: blockContentLoader
          width: parent.width
          active: blockDelegate.contentActive
          asynchronous: false

          sourceComponent: Component {
            Item {
              id: loadedBlockContent
              width: blockDelegate.width
              implicitHeight: block.type === "blank"
                ? Number(block.layoutHeight) || 0
                : blockContent.implicitHeight
              height: implicitHeight
              property var blankContentReference: blankContent
              property var imageContentReference: imageContent
              property var blockHitProbeReference: blockHitProbe
              property var headingTextReference: headingText
              property var paragraphTextReference: paragraphText
              property var paragraphContinuationReference: paragraphContinuationProbe
              property var listViewReference: listContent
              property var quoteContentReference: quoteContent
              property var quoteTextReference: quoteText
              property var quoteHitProbeReference: quoteHitProbe
              property var codeReference: codeContent
              property var codeLanguageLabelReference: codeLanguageLabel
              property var codeTextReference: codeText
              property var codePaintReference: codePaint
              property var ruleReference: ruleContent
              property var tableReference: tableContent
              property var tableRowsReference: tableRows

              Component.onCompleted: {
                if (block.type === "code") root.requestCodeHighlight(block)
              }

        TextEdit {
          id: blockHitProbe
          x: 0
          y: 0
          width: parent.width
          height: parent.height
          opacity: 0
          readOnly: true
          activeFocusOnPress: false
          selectByMouse: false
          selectByKeyboard: false
          cursorVisible: false
          text: root.blockHitProbeText(block)
          baseUrl: root.baseUrl
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          font.family: root.fontFamily
          font.pixelSize: block.type === "heading"
            ? root.bodyPixelSize *
              (block.level === 1 ? 1.55 : block.level === 2 ? 1.3 : 1.15)
          : root.bodyPixelSize
          font.bold: block.type === "heading"
        }

        MouseArea {
          id: blockHitArea
          anchors.fill: parent
          enabled: block.type === "heading" || block.type === "paragraph" ||
            block.type === "quote" || block.type === "rule" ||
            block.type === "table"
          acceptedButtons: Qt.LeftButton
          preventStealing: true
          hoverEnabled: true
          cursorShape: Qt.IBeamCursor
          property int anchorPosition: -1

          onPressed: function(mouse) {
            root.beginMouseSelection()
            anchorPosition = root.sourcePositionForBlockPoint(
              block, mouse.x, mouse.y)
            root.sourcePositionRequested(anchorPosition)
            if (root.registerRenderedMousePress(anchorPosition) >= 3) {
              root.selectLineAtSourcePosition(anchorPosition)
            }
            mouse.accepted = true
          }

          onDoubleClicked: function(mouse) {
            root.handleRenderedDoubleClick(
              root.sourcePositionForBlockPoint(
              block, mouse.x, mouse.y))
            mouse.accepted = true
          }

          onPositionChanged: function(mouse) {
            if (!(mouse.buttons & Qt.LeftButton) || anchorPosition < 0) return
            var point = blockHitArea.mapToItem(root, mouse.x, mouse.y)
            root.requestMouseSelection(anchorPosition, point.x, point.y)
            mouse.accepted = true
          }

          onReleased: function(mouse) {
            if (anchorPosition >= 0) mouse.accepted = true
            anchorPosition = -1
            root.endMouseSelection()
          }

          onCanceled: {
            anchorPosition = -1
            root.endMouseSelection()
          }
        }

        Column {
          id: blockContent
          width: parent.width

          Item {
            id: blankContent
            visible: block.type === "blank"
            width: parent.width
            implicitHeight: visible
              ? Number(block.layoutHeight) || 0 : 0
            height: implicitHeight
            property var blankHitAreaReference: blankMouseArea

            MouseArea {
              id: blankMouseArea
              // Column spacing is part of the visible blank source row, but
              // it is not owned by either neighboring delegate. Include the
              // preceding gap so a click immediately below a variable-height
              // block (such as an image with an alt caption) still reaches
              // this blank row.
              x: 0
              y: -root.blockSpacing
              width: parent.width
              height: parent.height + root.blockSpacing
              acceptedButtons: Qt.LeftButton
              preventStealing: true
              cursorShape: Qt.IBeamCursor
              property int anchorPosition: -1

              onPressed: function(mouse) {
                root.beginMouseSelection()
                anchorPosition = block.sourceStart +
                  root.sourceColumnForX(
                    root.sourceText.slice(block.sourceStart, block.sourceEnd),
                    mouse.x)
                root.sourcePositionRequested(anchorPosition)
                mouse.accepted = true
              }

              onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton) || anchorPosition < 0) return
                var point = mapToItem(root, mouse.x, mouse.y)
                root.requestMouseSelection(anchorPosition, point.x, point.y)
                mouse.accepted = true
              }

              onReleased: function(mouse) {
                if (anchorPosition >= 0) mouse.accepted = true
                anchorPosition = -1
                root.endMouseSelection()
              }

              onCanceled: {
                anchorPosition = -1
                root.endMouseSelection()
              }
            }
          }

          Item {
            id: imageContent
            visible: block.type === "image"
            width: parent.width
            property int imageStatus: imageItem.status
            property real naturalWidth: imageItem.status === Image.Ready
              ? Number(imageItem.sourceSize.width) ||
                Number(imageItem.implicitWidth) || 0 : 0
            property real naturalHeight: imageItem.status === Image.Ready
              ? Number(imageItem.sourceSize.height) ||
                Number(imageItem.implicitHeight) || 0 : 0
            property real renderedWidth: naturalWidth > 0
              ? Math.min(width, naturalWidth) : 0
            property real renderedHeight: naturalWidth > 0 && naturalHeight > 0
              ? renderedWidth * naturalHeight / naturalWidth : 0
            property real imageAltSpacing: imageAltText.visible
              ? Style.space(6) : 0
            property var imageAltTextReference: imageAltText
            property var imageAltHitProbeReference: imageAltHitProbe
            implicitHeight: visible
              ? imageItem.status === Image.Ready && renderedHeight > 0
                ? renderedHeight + imageAltSpacing + imageAltText.implicitHeight
                : imageFallback.implicitHeight + Style.space(12)
              : 0
            height: implicitHeight

            Image {
              id: imageItem
              visible: status === Image.Ready && imageContent.renderedHeight > 0
              source: block.imageSource || ""
              asynchronous: true
              cache: true
              fillMode: Image.PreserveAspectFit
              width: imageContent.renderedWidth
              height: imageContent.renderedHeight

              onStatusChanged: root.richTextContentChanged()
            }

            Text {
              id: imageFallback
              visible: imageItem.status !== Image.Ready ||
                imageContent.renderedHeight <= 0
              width: parent.width
              text: imageItem.status === Image.Loading
                ? "Loading image…"
                : "Image unavailable: " + String(block.alt || "untitled image")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.bodyPixelSize
              wrapMode: Text.WordWrap
            }

            Text {
              id: imageAltText
              visible: imageItem.status === Image.Ready &&
                imageContent.renderedHeight > 0 &&
                String(block.alt || "") !== ""
              x: 0
              y: imageItem.height + imageContent.imageAltSpacing
              width: Math.max(1, imageContent.renderedWidth)
              text: root.inlineCodeHtml(block.alt)
              textFormat: Text.RichText
              baseUrl: root.baseUrl
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.bodyPixelSize
              wrapMode: Text.Wrap
              onContentHeightChanged: root.richTextContentChanged()
            }

            TextEdit {
              id: imageAltHitProbe
              x: imageAltText.x
              y: imageAltText.y
              width: imageAltText.width
              height: Math.max(1, imageAltText.implicitHeight)
              opacity: 0
              readOnly: true
              activeFocusOnPress: false
              selectByMouse: false
              selectByKeyboard: false
              cursorVisible: false
              text: String(block.alt || "")
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.Wrap
              font.family: root.fontFamily
              font.pixelSize: root.bodyPixelSize
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              preventStealing: true
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              property int anchorPosition: -1

            onPressed: function(mouse) {
              root.beginMouseSelection()
              anchorPosition = root.imageSourcePositionForPoint(
                block, imageContent, mouse.x, mouse.y)
              root.sourcePositionRequested(anchorPosition)
              if (root.registerRenderedMousePress(anchorPosition) >= 3) {
                root.selectLineAtSourcePosition(anchorPosition)
              }
              mouse.accepted = true
            }

            onDoubleClicked: function(mouse) {
              root.handleRenderedDoubleClick(anchorPosition >= 0
                ? anchorPosition : block.sourceStart)
              mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!pressed || anchorPosition < 0) return
                var point = imageContent.mapToItem(root, mouse.x, mouse.y)
                root.requestMouseSelection(anchorPosition, point.x, point.y)
                mouse.accepted = true
              }

              onReleased: function(mouse) {
                if (anchorPosition >= 0) mouse.accepted = true
                anchorPosition = -1
                root.endMouseSelection()
              }

              onCanceled: {
                anchorPosition = -1
                root.endMouseSelection()
              }
            }
          }

          Text {
            id: headingText
            visible: block.type === "heading"
            width: parent.width
            height: visible ? Math.ceil(paintedHeight) : 0
            text: block.html || ""
            baseUrl: root.baseUrl
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.bodyPixelSize *
              (block.level === 1 ? 1.55 : block.level === 2 ? 1.3 : 1.15)
            font.bold: true
            lineHeight: root.bodyLineHeightFactor
            lineHeightMode: Text.ProportionalHeight
            onContentHeightChanged: root.richTextContentChanged()

            HoverHandler {
              id: headingLinkHover
              cursorShape: root.linkCursorShape(
                headingText, point.position.x, point.position.y)
            }

            TapHandler {
              acceptedButtons: Qt.LeftButton
              acceptedModifiers: Qt.ControlModifier
              enabled: headingLinkHover.hovered &&
                root.linkForPointer(
                  headingText, headingLinkHover.point.position.x,
                  headingLinkHover.point.position.y,
                  Qt.ControlModifier) !== ""
              gesturePolicy: TapHandler.ReleaseWithinBounds

              onTapped: function(eventPoint) {
                root.openLink(root.linkForPointer(
                  headingText, eventPoint.position.x, eventPoint.position.y,
                  Qt.ControlModifier))
              }
            }
          }

          Text {
            id: paragraphText
            visible: block.type === "paragraph"
            width: parent.width
            height: visible ? Math.ceil(paintedHeight) : 0
            text: block.html || ""
            baseUrl: root.baseUrl
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.bodyPixelSize
            lineHeight: root.bodyLineHeightFactor
            lineHeightMode: Text.ProportionalHeight
            onContentHeightChanged: root.richTextContentChanged()

            HoverHandler {
              id: paragraphLinkHover
              cursorShape: root.linkCursorShape(
                paragraphText, point.position.x, point.position.y)
            }

            TapHandler {
              acceptedButtons: Qt.LeftButton
              acceptedModifiers: Qt.ControlModifier
              enabled: paragraphLinkHover.hovered &&
                root.linkForPointer(
                  paragraphText, paragraphLinkHover.point.position.x,
                  paragraphLinkHover.point.position.y,
                  Qt.ControlModifier) !== ""
              gesturePolicy: TapHandler.ReleaseWithinBounds

              onTapped: function(eventPoint) {
                root.openLink(root.linkForPointer(
                  paragraphText, eventPoint.position.x, eventPoint.position.y,
                  Qt.ControlModifier))
              }
            }
          }

          Text {
            id: paragraphContinuationProbe
            visible: false
            width: parent.width
            text: (block.html || "") + "<br>x"
            baseUrl: root.baseUrl
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: root.bodyPixelSize
            lineHeight: root.bodyLineHeightFactor
            lineHeightMode: Text.ProportionalHeight
          }

          ListView {
            id: listContent
            visible: block.type === "list"
            width: parent.width
            height: visible ? contentHeight : 0
            interactive: false
            clip: false
            spacing: 0

            model: block.items || []

            delegate: Item {
                id: listItemDelegate
                property var itemData: modelData
                property var itemTextReference: itemText
                property var hitProbeReference: itemHitProbe
                property var itemHitAreaReference: itemHitArea
                property var markerHitAreaReference: markerHitArea
                property var taskBoxReference: taskBox
                property var rowReference: listRow
                property real textOriginX: listRow.x +
                  (itemData.task ? Style.space(16) : Style.space(22)) + listRow.spacing
                property real textOriginY: listRow.y
                width: listContent.width
                height: Math.max(Style.space(18), itemText.implicitHeight)

                Row {
                  id: listRow
                  x: itemData.level * Style.space(24)
                  width: Math.max(0, parent.width - x)
                  spacing: Style.space(7)

              Item {
                    width: itemData.task ? Style.space(16) : Style.space(22)
                    height: Math.max(Style.space(16), itemText.implicitHeight)

                    Rectangle {
                      id: taskBox
                      property bool checked: {
                        var revision = root.taskStateRevision
                        var override = root.taskCheckedOverrides[
                          "$" + Number(itemData.sourceStart)]
                        return override === undefined
                          ? Boolean(itemData.checked) : Boolean(override)
                      }
                      visible: itemData.task
                      anchors.left: parent.left
                      y: Math.max(0,
                        itemText.baselineOffset + root.bodyCapBounds.y +
                          (root.bodyCapBounds.height - height) / 2)
                      width: Style.space(13)
                      height: Style.space(13)
                      radius: Style.space(2)
                      color: checked ? root.accent : "transparent"
                      border.color: checked ? root.accent :
                        Qt.rgba(root.foreground.r, root.foreground.g,
                          root.foreground.b, 0.72)
                      border.width: Math.max(1, Style.space(1))

                      Text {
                        visible: taskBox.checked
                        anchors.centerIn: parent
                        text: "✓"
                        color: root.background
                        font.family: root.fontFamily
                        font.pixelSize: root.bodyPixelSize * 0.75
                        font.bold: true
                      }

                      MouseArea {
                        anchors.fill: parent
                        enabled: itemData.task
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                          root.taskToggled(itemData.sourceStart)
                          mouse.accepted = true
                        }
                      }
                    }

                    Text {
                      visible: !itemData.task
                      anchors.left: parent.left
                      anchors.top: parent.top
                      width: parent.width
                      text: itemData.ordered ? String(itemData.number) + "." : "•"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: root.bodyPixelSize
                      horizontalAlignment: Text.AlignRight
                    }

                    MouseArea {
                      id: markerHitArea
                      anchors.fill: parent
                      enabled: !itemData.task
                      acceptedButtons: Qt.LeftButton
                      preventStealing: true
                      hoverEnabled: true
                      cursorShape: Qt.IBeamCursor
                      property int anchorPosition: -1

                      // The Markdown marker is presentation-only. A click
                      // there should enter the editable source at the first
                      // selectable boundary, immediately before the first
                      // visible list character, rather than doing nothing.
                      onPressed: function(mouse) {
                        root.beginMouseSelection()
                        anchorPosition = root.listItemFirstSelectablePosition(
                          itemData)
                        root.sourcePositionRequested(anchorPosition)
                        if (root.registerRenderedMousePress(anchorPosition) >= 3) {
                          root.selectLineAtSourcePosition(anchorPosition)
                        }
                        mouse.accepted = true
                      }

                      onDoubleClicked: function(mouse) {
                        root.handleRenderedDoubleClick(
                          root.listItemFirstSelectablePosition(itemData))
                        mouse.accepted = true
                      }

                      onPositionChanged: function(mouse) {
                        if (!pressed || anchorPosition < 0) return
                        var point = markerHitArea.mapToItem(
                          root, mouse.x, mouse.y)
                        root.requestMouseSelection(
                          anchorPosition, point.x, point.y)
                        mouse.accepted = true
                      }

                      onReleased: function(mouse) {
                        if (anchorPosition >= 0) mouse.accepted = true
                        anchorPosition = -1
                        root.endMouseSelection()
                      }

                      onCanceled: {
                        anchorPosition = -1
                        root.endMouseSelection()
                      }
                    }
                  }

                  Text {
                    id: itemText
                    width: Math.max(0, listRow.width - listRow.spacing -
                      (itemData.task ? Style.space(16) : Style.space(22)))
                    text: itemData.html || ""
                    baseUrl: root.baseUrl
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: root.bodyPixelSize
                    lineHeight: root.bodyLineHeightFactor
                    lineHeightMode: Text.ProportionalHeight
                    onContentHeightChanged: root.richTextContentChanged()

                    TextEdit {
                      id: itemHitProbe
                      anchors.fill: parent
                      opacity: 0
                      text: root.plainInline(itemData.plain || "")
                      textFormat: TextEdit.PlainText
                      wrapMode: TextEdit.Wrap
                      readOnly: true
                      activeFocusOnPress: false
                      selectByMouse: false
                      selectByKeyboard: false
                      cursorVisible: false
                      font.family: root.fontFamily
                      font.pixelSize: root.bodyPixelSize
                    }

                    MouseArea {
                      id: itemHitArea
                      anchors.fill: parent
                      acceptedButtons: Qt.LeftButton
                      preventStealing: true
                      hoverEnabled: true
                      cursorShape: Qt.IBeamCursor
                      property int anchorPosition: -1

                      onPressed: function(mouse) {
                        root.beginMouseSelection()
                        anchorPosition = root.listSourcePosition(
                          itemData, itemHitProbe, mouse.x, mouse.y)
                        root.sourcePositionRequested(anchorPosition)
                        if (root.registerRenderedMousePress(anchorPosition) >= 3) {
                          root.selectLineAtSourcePosition(anchorPosition)
                        }
                        mouse.accepted = true
                      }

                      onDoubleClicked: function(mouse) {
                        root.handleRenderedDoubleClick(
                          root.listSourcePosition(
                            itemData, itemHitProbe, mouse.x, mouse.y))
                        mouse.accepted = true
                      }

                      onPositionChanged: function(mouse) {
                        if (!pressed || anchorPosition < 0) return
                        var point = itemHitArea.mapToItem(root, mouse.x, mouse.y)
                        root.requestMouseSelection(
                          anchorPosition, point.x, point.y)
                        mouse.accepted = true
                      }

                      onReleased: function(mouse) {
                        if (anchorPosition >= 0) mouse.accepted = true
                        anchorPosition = -1
                        root.endMouseSelection()
                      }

                      onCanceled: {
                        anchorPosition = -1
                        root.endMouseSelection()
                      }
                    }

                    HoverHandler {
                      id: itemLinkHover
                      cursorShape: root.linkCursorShape(
                        itemText, point.position.x, point.position.y)
                    }

                    TapHandler {
                      acceptedButtons: Qt.LeftButton
                      acceptedModifiers: Qt.ControlModifier
                      enabled: itemLinkHover.hovered &&
                        root.linkForPointer(
                          itemText, itemLinkHover.point.position.x,
                          itemLinkHover.point.position.y,
                          Qt.ControlModifier) !== ""
                      gesturePolicy: TapHandler.ReleaseWithinBounds

                      onTapped: function(eventPoint) {
                        root.openLink(root.linkForPointer(
                          itemText, eventPoint.position.x,
                          eventPoint.position.y, Qt.ControlModifier))
                      }
                    }
                  }
                }

            }
          }

          Row {
            id: quoteContent
            visible: block.type === "quote"
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: Style.space(10)

            Rectangle {
              width: Math.max(2, Style.space(2))
              height: quoteText.implicitHeight
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.35)
            }

            Text {
              id: quoteText
              width: Math.max(0, quoteContent.width - quoteContent.spacing -
                Style.space(2))
              text: block.html || ""
              baseUrl: root.baseUrl
              textFormat: Text.RichText
              wrapMode: Text.Wrap
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.78)
              font.family: root.fontFamily
              font.pixelSize: root.bodyPixelSize
              lineHeight: root.bodyLineHeightFactor
              lineHeightMode: Text.ProportionalHeight
              onContentHeightChanged: root.richTextContentChanged()

              TextEdit {
                id: quoteHitProbe
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: contentHeight
                opacity: 0
                text: root.quotePlainPrefix(
                  root.sourceText.slice(block.sourceStart, block.sourceEnd),
                  Math.max(0, block.sourceEnd - block.sourceStart))
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: false
                activeFocusOnPress: false
                cursorVisible: false
                font.family: root.fontFamily
                font.pixelSize: root.bodyPixelSize
              }

              MouseArea {
                id: quoteHitArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
                property int anchorPosition: -1

                onPressed: function(mouse) {
                  if ((mouse.modifiers & Qt.ControlModifier) &&
                      root.linkForPointer(quoteText, mouse.x, mouse.y,
                        mouse.modifiers) !== "") {
                    mouse.accepted = false
                    return
                  }
                  root.beginMouseSelection()
                  anchorPosition = root.quoteSourcePosition(
                    block, quoteHitProbe, mouse.x, mouse.y)
                  root.sourcePositionRequested(anchorPosition)
                  if (root.registerRenderedMousePress(anchorPosition) >= 3) {
                    root.selectLineAtSourcePosition(anchorPosition)
                  }
                  mouse.accepted = true
                }

                onDoubleClicked: function(mouse) {
                  root.handleRenderedDoubleClick(root.quoteSourcePosition(
                    block, quoteHitProbe, mouse.x, mouse.y))
                  mouse.accepted = true
                }

                onPositionChanged: function(mouse) {
                  if (!pressed || anchorPosition < 0)
                    return
                  var point = quoteHitArea.mapToItem(root, mouse.x, mouse.y)
                  root.requestMouseSelection(anchorPosition, point.x, point.y)
                  mouse.accepted = true
                }

                onReleased: function(mouse) {
                  if (anchorPosition >= 0) mouse.accepted = true
                  anchorPosition = -1
                  root.endMouseSelection()
                }

                onCanceled: {
                  anchorPosition = -1
                  root.endMouseSelection()
                }
              }

              HoverHandler {
                id: quoteLinkHover
                cursorShape: root.linkCursorShape(
                  quoteText, point.position.x, point.position.y)
              }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                acceptedModifiers: Qt.ControlModifier
                enabled: quoteLinkHover.hovered &&
                  root.linkForPointer(
                    quoteText, quoteLinkHover.point.position.x,
                    quoteLinkHover.point.position.y,
                    Qt.ControlModifier) !== ""
                gesturePolicy: TapHandler.ReleaseWithinBounds

                onTapped: function(eventPoint) {
                  root.openLink(root.linkForPointer(
                    quoteText, eventPoint.position.x, eventPoint.position.y,
                    Qt.ControlModifier))
                }
              }
            }
          }

          Rectangle {
            id: ruleContent
            visible: block.type === "rule"
            width: parent.width
            height: visible ? Math.max(1, Style.space(1)) : 0
            color: Qt.rgba(root.foreground.r, root.foreground.g,
              root.foreground.b, 0.45)
          }

          Rectangle {
            id: codeContent
            visible: block.type === "code"
            width: parent.width
            height: visible ? codeText.y + codeText.height + Style.space(10) : 0
            radius: Style.space(4)
            color: Qt.rgba(root.foreground.r, root.foreground.g,
              root.foreground.b, 0.06)

            Text {
              id: codeLanguageLabel
              visible: block.type === "code" &&
                String(block.languageLabel || "") !== ""
              x: Style.space(10)
              y: Style.space(7)
              width: Math.max(0, parent.width - Style.space(20))
              height: visible ? Math.ceil(paintedHeight) : 0
              text: block.languageLabel || ""
              color: Qt.rgba(root.accent.r, root.accent.g,
                root.accent.b, 0.9)
              font.family: root.fontFamily
              font.pixelSize: Math.max(10, root.bodyPixelSize * 0.72)
              font.bold: true
            }

            TextEdit {
              id: codeText
              x: Style.space(10)
              y: codeLanguageLabel.visible
                ? codeLanguageLabel.y + codeLanguageLabel.height + Style.space(5)
                : Style.space(10)
              width: Math.max(0, parent.width - Style.space(20))
              height: Math.max(implicitHeight,
                root.codeSourceLineCount(block) *
                root.codeLineAdvanceForText(
                  codeText, root.codeSourceLineCount(block)))
              text: block.text || ""
              readOnly: true
              selectByMouse: false
              selectByKeyboard: false
              cursorVisible: false
              activeFocusOnPress: false
              textFormat: TextEdit.PlainText
              wrapMode: TextEdit.Wrap
              color: "transparent"
              font.family: root.fontFamily
              font.pixelSize: root.bodyPixelSize
            }

            Text {
              id: codePaint
              x: codeText.x
              y: codeText.y
              width: codeText.width
              height: codeText.height
              text: root.codeHighlightMarkup(block)
              visible: block.type === "code"
              textFormat: Text.StyledText
              wrapMode: Text.Wrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: root.bodyPixelSize
              lineHeight: root.bodyLineHeightFactor
              lineHeightMode: Text.ProportionalHeight
            }

            MouseArea {
              id: codeMouseArea
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              preventStealing: true
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              property int anchorPosition: -1

              onPressed: function(mouse) {
                root.beginMouseSelection()
                anchorPosition = root.codeSourcePosition(
                  block, mouse.x, mouse.y)
                root.sourcePositionRequested(anchorPosition)
                if (root.registerRenderedMousePress(anchorPosition) >= 3) {
                  root.selectLineAtSourcePosition(anchorPosition)
                }
                mouse.accepted = true
              }

              onDoubleClicked: function(mouse) {
                root.handleRenderedDoubleClick(root.codeSourcePosition(
                  block, mouse.x, mouse.y))
                mouse.accepted = true
              }

              onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton) || anchorPosition < 0) return
                var point = codeMouseArea.mapToItem(root, mouse.x, mouse.y)
                root.requestMouseSelection(anchorPosition, point.x, point.y)
                mouse.accepted = true
              }

              onReleased: function(mouse) {
                if (anchorPosition >= 0) mouse.accepted = true
                anchorPosition = -1
                root.endMouseSelection()
              }

              onCanceled: {
                anchorPosition = -1
                root.endMouseSelection()
              }
            }
          }

          Column {
            id: tableContent
            visible: block.type === "table"
            width: parent.width
            height: visible ? implicitHeight : 0

            Repeater {
              id: tableRows
              model: block.rows || []

              delegate: Row {
                id: tableRow
                property int rowIndex: index
                property var cellRepeaterReference: tableCells
                width: tableContent.width
                property real renderedRequiredHeight: {
                  var required = Number((block.rowHeights || [])[rowIndex]) ||
                    Style.space(34)
                  for (var cellIndex = 0; cellIndex < tableCells.count;
                       cellIndex++) {
                    var cell = tableCells.itemAt(cellIndex)
                    var cellText = cell && cell.cellTextReference
                    if (cellText) {
                      required = Math.max(required,
                        Number(cellText.implicitHeight) + Style.space(14))
                    }
                  }
                  return required
                }
                height: renderedRequiredHeight

                Repeater {
                  id: tableCells
                  model: modelData

                  delegate: Rectangle {
                    property int columnIndex: index
                    width: (block.columnWidths || [Style.space(90)])[columnIndex] || Style.space(90)
                    height: tableRow.height
                    color: tableRow.rowIndex === 0
                      ? Qt.rgba(root.foreground.r, root.foreground.g,
                        root.foreground.b, 0.06)
                      : "transparent"
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                      root.foreground.b, 0.36)
                    border.width: Math.max(1, Style.space(1))

                    property var cellTextReference: tableCellText

                    Text {
                      id: tableCellText
                      anchors.fill: parent
                      anchors.margins: Style.space(7)
                      text: modelData.html || ""
                      baseUrl: root.baseUrl
                      textFormat: Text.RichText
                      wrapMode: Text.Wrap
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: root.bodyPixelSize
                      font.bold: tableRow.rowIndex === 0
                      horizontalAlignment:
                        String((block.alignments || [])[columnIndex] || "left") === "center"
                          ? Text.AlignHCenter
                          : String((block.alignments || [])[columnIndex] || "left") === "right"
                            ? Text.AlignRight : Text.AlignLeft
                      lineHeight: root.bodyLineHeightFactor
                      lineHeightMode: Text.ProportionalHeight
                      onContentHeightChanged: root.richTextContentChanged()

                      HoverHandler {
                        id: tableCellLinkHover
                        cursorShape: root.linkCursorShape(
                          tableCellText, point.position.x, point.position.y)
                      }

                      TapHandler {
                        acceptedButtons: Qt.LeftButton
                        acceptedModifiers: Qt.ControlModifier
                        enabled: tableCellLinkHover.hovered &&
                          root.linkForPointer(
                            tableCellText,
                            tableCellLinkHover.point.position.x,
                            tableCellLinkHover.point.position.y,
                            Qt.ControlModifier) !== ""
                        gesturePolicy: TapHandler.ReleaseWithinBounds

                        onTapped: function(eventPoint) {
                          root.openLink(root.linkForPointer(
                            tableCellText, eventPoint.position.x,
                            eventPoint.position.y, Qt.ControlModifier))
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
            }
          }
        }
      }
    }
  }

  MouseArea {
    id: documentHitFallback
    anchors.fill: parent
    z: 0
    acceptedButtons: Qt.LeftButton
    preventStealing: true
    hoverEnabled: true
    cursorShape: Qt.IBeamCursor
    property int anchorPosition: -1

    // Lazy block delegates retain their indexed geometry while their content
    // is unloaded. Handle otherwise-unclaimed pixels at the document level so
    // source-only blank rows remain clickable regardless of hydration state.
    onPressed: function(mouse) {
      root.beginMouseSelection()
      anchorPosition = root.sourcePositionForPoint(mouse.x, mouse.y)
      root.sourcePositionRequested(anchorPosition)
      if (root.registerRenderedMousePress(anchorPosition) >= 3) {
        root.selectLineAtSourcePosition(anchorPosition)
      }
      mouse.accepted = true
    }

    onDoubleClicked: function(mouse) {
      root.handleRenderedDoubleClick(
        root.sourcePositionForPoint(mouse.x, mouse.y))
      mouse.accepted = true
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton) || anchorPosition < 0) return
      root.requestMouseSelection(anchorPosition, mouse.x, mouse.y)
      mouse.accepted = true
    }

    onReleased: function(mouse) {
      if (anchorPosition >= 0) mouse.accepted = true
      anchorPosition = -1
      root.endMouseSelection()
    }

    onCanceled: {
      anchorPosition = -1
      root.endMouseSelection()
    }
  }

  onSourceTextChanged: {
    var previousSource = root.observedSourceText
    var nextSource = String(root.sourceText || "")
    codeHighlightDelayTimer.stop()
    root.codeHighlightDeferred = ({})
    root.observedSourceText = nextSource
    root.sourceRevision++
    root.resetPlainInlineProjectionCache()
    if (root.applyTaskStateOnlyChange(previousSource, nextSource)) return
    root.invalidateLayout()
  }
  onWidthChanged: {
    root.invalidateLayout()
  }
  onSelectionStartChanged: root.scheduleSelectionUpdate()
  onSelectionEndChanged: root.scheduleSelectionUpdate()
  onCursorPositionChanged: root.cursorMoved()
  onBodyPixelSizeChanged: root.invalidateLayout()
  onBodyCaretHeightChanged: root.invalidateLayout()
  onFontFamilyChanged: root.invalidateLayout()
  onForegroundChanged: root.invalidateLayout()
  onAccentChanged: root.invalidateLayout()
  onBaseUrlChanged: root.invalidateLayout()
  onBlocksChanged: {
    Qt.callLater(root.rebuildSelection)
    layoutSettleTimer.restart()
  }
  Component.onCompleted: {
    root.observedSourceText = String(root.sourceText || "")
    root.rebuild()
    Qt.callLater(root.rebuildSelection)
  }
}
