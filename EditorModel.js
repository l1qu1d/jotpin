// Pure Markdown editor transitions shared by the QML editor and the
// non-interactive regression suite. Keep desktop focus, file I/O, and visual
// layout out of this module so it can be exercised without a running shell.

function sourceText(value) {
  return String(value || "")
}

function clampPosition(source, value) {
  var text = sourceText(source)
  var position = Number(value)
  if (!isFinite(position)) position = 0
  return Math.max(0, Math.min(position, text.length))
}

function lineBounds(source, value) {
  var text = sourceText(source)
  var position = clampPosition(text, value)
  var lineStart = text.lastIndexOf("\n", Math.max(0, position - 1)) + 1
  var lineEnd = text.indexOf("\n", position)
  if (lineEnd < 0) lineEnd = text.length
  var lineBreak = lineEnd < text.length && lineEnd > lineStart &&
    text.charAt(lineEnd - 1) === "\r" ? "\r\n" : "\n"
  var contentEnd = lineEnd > lineStart && text.charAt(lineEnd - 1) === "\r"
    ? lineEnd - 1 : lineEnd
  return {
    source: text,
    position: position,
    lineStart: lineStart,
    lineEnd: lineEnd,
    line: text.slice(lineStart, contentEnd),
    lineBreak: lineBreak
  }
}

function imageResizeMetadataAt(sourceValue, imageEndValue) {
  var source = sourceText(sourceValue)
  var imageEnd = clampPosition(source, imageEndValue)
  var match = /^<!--[ \t]*jotpin:image[ \t]+width[ \t]*=[ \t]*([0-9]{1,5})[ \t]*-->/i
    .exec(source.slice(imageEnd))
  if (!match) return null
  return {
    start: imageEnd,
    end: imageEnd + match[0].length,
    width: Number(match[1])
  }
}

function resizeMarkdownImage(sourceValue, imageStartValue, imageEndValue,
                             widthValue, cursorValue) {
  var source = sourceText(sourceValue)
  var imageStart = clampPosition(source, imageStartValue)
  var imageEnd = clampPosition(source, imageEndValue)
  var width = Math.round(Number(widthValue))
  var cursor = clampPosition(source, cursorValue)
  if (imageEnd <= imageStart || source.slice(imageStart, imageStart + 2) !== "![" ||
      !isFinite(width) || width < 1) {
    return { changed: false, source: source, cursor: cursor,
      metadataStart: -1, metadataEnd: -1, width: 0 }
  }

  width = Math.max(48, Math.min(8192, width))
  var existing = imageResizeMetadataAt(source, imageEnd)
  var replaceStart = imageEnd
  var replaceEnd = existing ? existing.end : imageEnd
  var metadata = "<!-- jotpin:image width=" + width + " -->"
  var nextSource = source.slice(0, replaceStart) + metadata +
    source.slice(replaceEnd)
  var nextCursor = cursor
  if (cursor > replaceStart) {
    if (cursor >= replaceEnd)
      nextCursor = cursor + metadata.length - (replaceEnd - replaceStart)
    else nextCursor = replaceStart + metadata.length
  }
  return {
    changed: nextSource !== source,
    source: nextSource,
    cursor: nextCursor,
    metadataStart: replaceStart,
    metadataEnd: replaceStart + metadata.length,
    width: width
  }
}

function findTextMatches(sourceValue, queryValue, caseSensitive) {
  var source = sourceText(sourceValue)
  var query = sourceText(queryValue)
  var matches = []
  if (query === "") return matches
  var comparisonQuery = caseSensitive ? query : query.toLocaleLowerCase()

  function matchesAt(index) {
    if (index < 0 || index + query.length > source.length) return false
    var candidate = source.slice(index, index + query.length)
    return caseSensitive
      ? candidate === query
      : candidate.toLocaleLowerCase() === comparisonQuery
  }

  // Match navigation advances past the selected query, so count the same
  // non-overlapping occurrences that Next and Previous can visit.
  for (var index = 0; index + query.length <= source.length;) {
    if (matchesAt(index)) {
      matches.push({ start: index, end: index + query.length })
      index += query.length
    } else {
      index++
    }
  }
  return matches
}

function findText(sourceValue, queryValue, fromValue, backwards,
                  caseSensitive) {
  var source = sourceText(sourceValue)
  var query = sourceText(queryValue)
  var matches = findTextMatches(source, query, caseSensitive)
  if (matches.length === 0) {
    return { found: false, start: -1, end: -1, wrapped: false,
      index: 0, count: 0 }
  }

  var from = clampPosition(source, fromValue)
  var matchIndex = -1
  var wrapped = false

  if (backwards) {
    for (var previous = matches.length - 1; previous >= 0; previous--) {
      if (matches[previous].start < from) {
        matchIndex = previous
        break
      }
    }
    if (matchIndex < 0) {
      matchIndex = matches.length - 1
      wrapped = true
    }
  } else {
    for (var next = 0; next < matches.length; next++) {
      if (matches[next].start >= from) {
        matchIndex = next
        break
      }
    }
    if (matchIndex < 0) {
      matchIndex = 0
      wrapped = true
    }
  }

  return {
    found: true,
    start: matches[matchIndex].start,
    end: matches[matchIndex].end,
    wrapped: wrapped,
    index: matchIndex + 1,
    count: matches.length
  }
}

function replaceAllText(sourceValue, queryValue, replacementValue,
                        caseSensitive) {
  var source = sourceText(sourceValue)
  var query = sourceText(queryValue)
  var replacement = sourceText(replacementValue)
  if (query === "") return { source: source, count: 0, cursor: 0 }

  var matches = findTextMatches(source, query, caseSensitive)
  if (matches.length === 0) return { source: source, count: 0, cursor: 0 }

  var next = ""
  var scan = 0
  var lastCursor = 0
  for (var matchIndex = 0; matchIndex < matches.length; matchIndex++) {
    var match = matches[matchIndex]
    next += source.slice(scan, match.start) + replacement
    scan = match.end
    lastCursor = next.length
  }
  next += source.slice(scan)
  return { source: next, count: matches.length, cursor: lastCursor }
}

function linePosition(sourceValue, lineNumberValue) {
  var source = sourceText(sourceValue)
  var lineCount = source.split("\n").length
  var requested = Math.floor(Number(lineNumberValue))
  if (!isFinite(requested) || requested < 1) {
    return { valid: false, position: -1, line: 0, lineCount: lineCount }
  }

  var line = Math.min(requested, lineCount)
  var position = 0
  for (var index = 1; index < line; index++) {
    position = source.indexOf("\n", position) + 1
  }
  return {
    valid: true,
    position: position,
    line: line,
    lineCount: lineCount,
    clamped: line !== requested
  }
}

function indentEdit(sourceValue, selectionStartValue, selectionEndValue,
                    directionValue, tabSizeValue) {
  var source = sourceText(sourceValue)
  var start = clampPosition(source, selectionStartValue)
  var end = clampPosition(source, selectionEndValue)
  if (end < start) {
    var swap = start
    start = end
    end = swap
  }
  var direction = Number(directionValue) < 0 ? -1 : 1
  var tabSize = Math.floor(Number(tabSizeValue))
  if (!isFinite(tabSize) || tabSize < 1) tabSize = 4
  var hasSelection = start !== end

  function sourceLineStartAt(position) {
    return position <= 0 ? 0 : source.lastIndexOf("\n", position - 1) + 1
  }

  var firstLineStart = sourceLineStartAt(start)

  function removableIndentAt(lineStart) {
    var leading = /^[ \t]*/.exec(source.slice(lineStart))[0]
    var tabIndex = leading.indexOf("\t")
    if (tabIndex >= 0 && tabIndex < tabSize) return tabIndex + 1
    var count = 0
    while (count < tabSize && source.charAt(lineStart + count) === " ")
      count++
    return count
  }

  if (!hasSelection && direction > 0) {
    var bounds = lineBounds(source, start)
    var listMatch = /^(\s*)([-+*]|\d+[.)])([ \t]+)/.exec(bounds.line)
    var isList = Boolean(listMatch)
    var insertAt = isList ? bounds.lineStart : start
    var insertLength = isList
      ? listMatch[2].length + listMatch[3].length
      : tabSize - ((start - bounds.lineStart) % tabSize)
    var inserted = new Array(insertLength + 1).join(" ")
    return {
      handled: true,
      changed: true,
      source: source.slice(0, insertAt) + inserted + source.slice(insertAt),
      cursor: start + insertLength,
      selectionStart: start + insertLength,
      selectionEnd: start + insertLength
    }
  }

  var finalSelectedPosition = hasSelection ? Math.max(start, end - 1) : start
  var lastLineStart = sourceLineStartAt(finalSelectedPosition)
  var lineStarts = []
  var lineStart = firstLineStart
  while (lineStart <= lastLineStart) {
    lineStarts.push(lineStart)
    var nextBreak = source.indexOf("\n", lineStart)
    if (nextBreak < 0 || nextBreak + 1 > lastLineStart) break
    lineStart = nextBreak + 1
  }

  var edits = []
  for (var lineIndex = 0; lineIndex < lineStarts.length; lineIndex++) {
    var editStart = lineStarts[lineIndex]
    var removeLength = direction < 0 ? removableIndentAt(editStart) : 0
    if (direction > 0) {
      edits.push({ start: editStart, remove: 0,
        insert: new Array(tabSize + 1).join(" ") })
    } else if (removeLength > 0) {
      edits.push({ start: editStart, remove: removeLength, insert: "" })
    }
  }

  if (edits.length === 0) {
    return { handled: true, changed: false, source: source, cursor: end,
      selectionStart: start, selectionEnd: end }
  }

  function mappedPosition(position) {
    var mapped = position
    for (var editIndex = 0; editIndex < edits.length; editIndex++) {
      var edit = edits[editIndex]
      var delta = edit.insert.length - edit.remove
      if (position <= edit.start) continue
      if (position <= edit.start + edit.remove) {
        mapped += edit.start - position
        position = edit.start
      } else {
        mapped += delta
      }
    }
    return mapped
  }

  var nextSource = source
  for (var reverseIndex = edits.length - 1; reverseIndex >= 0;
       reverseIndex--) {
    var nextEdit = edits[reverseIndex]
    nextSource = nextSource.slice(0, nextEdit.start) + nextEdit.insert +
      nextSource.slice(nextEdit.start + nextEdit.remove)
  }
  var nextStart = mappedPosition(start)
  var nextEnd = mappedPosition(end)
  return {
    handled: true,
    changed: nextSource !== source,
    source: nextSource,
    cursor: nextEnd,
    selectionStart: nextStart,
    selectionEnd: nextEnd
  }
}

function listPrefixAt(source, value) {
  var bounds = lineBounds(source, value)
  var match = /^(\s*)([-+*]|\d+[.)])([ \t]+)(.*)$/.exec(bounds.line)
  if (!match) return null

  var contentStart = match[1].length + match[2].length + match[3].length
  var content = match[4]
  var task = /^\[([ xX])\]([ \t]+)(.*)$/.exec(content)
  // Only the checkbox syntax is hidden in Live mode. The final capture is the
  // editable task text and must retain one native caret stop per character.
  if (task) contentStart += task[0].length - task[3].length

  return {
    source: bounds.source,
    position: bounds.position,
    lineStart: bounds.lineStart,
    lineEnd: bounds.lineEnd,
    line: bounds.line,
    lineBreak: bounds.lineBreak,
    indent: match[1],
    marker: match[2],
    separator: match[3],
    content: content,
    contentStart: contentStart,
    task: task
  }
}

function horizontalListBoundaryTarget(source, value, direction, rawMode,
                                      selectionStart, selectionEnd) {
  if (rawMode || direction === 0 || selectionStart !== selectionEnd) return -1

  var list = listPrefixAt(source, value)
  if (!list) return -1

  var absoluteContentStart = list.lineStart + list.contentStart
  if (direction < 0 && list.position > list.lineStart &&
      list.position <= absoluteContentStart) return list.lineStart
  if (direction > 0 && list.position >= list.lineStart &&
      list.position < absoluteContentStart) return absoluteContentStart
  return -1
}

function tableCellSourceSpans(value) {
  var line = sourceText(value).replace(/\r$/, "")
  var trimStart = 0
  while (trimStart < line.length && /\s/.test(line.charAt(trimStart)))
    trimStart++
  var trimEnd = line.length
  while (trimEnd > trimStart && /\s/.test(line.charAt(trimEnd - 1)))
    trimEnd--

  var structuralPipes = []
  var escaped = false
  var codeRunLength = 0
  var linkDestinationDepth = 0
  for (var index = trimStart; index < trimEnd; index++) {
    var character = line.charAt(index)
    if (character === "`" && !escaped) {
      var runStart = index
      while (index + 1 < trimEnd && line.charAt(index + 1) === "`")
        index++
      var runLength = index - runStart + 1
      if (codeRunLength === 0) codeRunLength = runLength
      else if (codeRunLength === runLength) codeRunLength = 0
      escaped = false
      continue
    }
    if (codeRunLength === 0 && linkDestinationDepth === 0 &&
        character === "]" && index + 1 < trimEnd &&
        line.charAt(index + 1) === "(") {
      index++
      linkDestinationDepth = 1
      escaped = false
      continue
    }
    if (codeRunLength === 0 && linkDestinationDepth > 0) {
      if (character === "(") linkDestinationDepth++
      else if (character === ")") linkDestinationDepth--
      escaped = false
      continue
    }
    if (character === "|" && !escaped && codeRunLength === 0)
      structuralPipes.push(index)
    if (character === "\\" && !escaped) escaped = true
    else escaped = false
  }

  var contentStart = trimStart
  var contentEnd = trimEnd
  if (structuralPipes.length > 0 && structuralPipes[0] === trimStart)
    contentStart++
  if (structuralPipes.length > 0 &&
      structuralPipes[structuralPipes.length - 1] === trimEnd - 1)
    contentEnd--

  var boundaries = [contentStart]
  for (var pipeIndex = 0; pipeIndex < structuralPipes.length; pipeIndex++) {
    var pipe = structuralPipes[pipeIndex]
    if (pipe > contentStart && pipe < contentEnd) boundaries.push(pipe)
  }
  boundaries.push(contentEnd)

  var spans = []
  for (var boundaryIndex = 0;
       boundaryIndex + 1 < boundaries.length; boundaryIndex++) {
    var rawStart = boundaries[boundaryIndex] +
      (boundaryIndex > 0 ? 1 : 0)
    var rawEnd = boundaries[boundaryIndex + 1]
    // A conventional pipe table uses one optional padding character on each
    // side of a cell. Reserve only that single character as syntax. Additional
    // spaces are user content and must remain editable/visible so typing
    // Space repeatedly advances the Live caret instead of collapsing every
    // position onto the final non-space character.
    var start = rawStart
    if (start < rawEnd && /[ \t]/.test(line.charAt(start))) start++
    var end = rawEnd
    if (end > start && /[ \t]/.test(line.charAt(end - 1))) end--
    spans.push({
      text: line.slice(start, end),
      start: start,
      end: end
    })
  }
  if (spans.length === 0) spans.push({text: "", start: 0, end: 0})
  return spans
}

function tableRowCells(value) {
  var spans = tableCellSourceSpans(value)
  var cells = []
  for (var index = 0; index < spans.length; index++)
    cells.push(spans[index].text)
  return cells
}

function isTableSeparator(value) {
  var cells = tableRowCells(value)
  if (cells.length < 1) return false
  for (var index = 0; index < cells.length; index++) {
    if (!/^:?-{3,}:?$/.test(cells[index])) return false
  }
  return true
}

function isTableStart(headerValue, separatorValue) {
  var header = sourceText(headerValue)
  if (header.indexOf("|") < 0 || !isTableSeparator(separatorValue))
    return false
  return tableRowCells(header).length ===
    tableRowCells(separatorValue).length
}

function sourceLines(sourceValue) {
  var source = sourceText(sourceValue)
  var values = source.split("\n")
  var lines = []
  var start = 0
  for (var index = 0; index < values.length; index++) {
    var raw = values[index]
    var text = raw.charAt(raw.length - 1) === "\r"
      ? raw.slice(0, -1) : raw
    lines.push({
      text: text,
      start: start,
      end: start + text.length,
      rawEnd: start + raw.length,
      index: index
    })
    start += raw.length + (index + 1 < values.length ? 1 : 0)
  }
  return lines
}

function tableRegions(sourceValue) {
  var source = sourceText(sourceValue)
  var lines = sourceLines(source)
  var regions = []
  for (var headerIndex = 0; headerIndex + 1 < lines.length;) {
    if (!isTableStart(lines[headerIndex].text,
        lines[headerIndex + 1].text)) {
      headerIndex++
      continue
    }

    var columnCount = tableRowCells(lines[headerIndex].text).length
    var renderedLineIndexes = [headerIndex]
    var finalLineIndex = headerIndex + 1
    var bodyIndex = headerIndex + 2
    while (bodyIndex < lines.length &&
        !/^\s*$/.test(lines[bodyIndex].text) &&
        (columnCount === 1 || lines[bodyIndex].text.indexOf("|") >= 0)) {
      renderedLineIndexes.push(bodyIndex)
      finalLineIndex = bodyIndex
      bodyIndex++
    }

    var rows = []
    for (var rowIndex = 0; rowIndex < renderedLineIndexes.length;
         rowIndex++) {
      var line = lines[renderedLineIndexes[rowIndex]]
      var relativeSpans = tableCellSourceSpans(line.text)
      var spans = []
      for (var spanIndex = 0; spanIndex < columnCount; spanIndex++) {
        var relative = relativeSpans[spanIndex] || {
          text: "", start: line.text.length, end: line.text.length
        }
        spans.push({
          text: relative.text,
          start: line.start + relative.start,
          end: line.start + relative.end,
          lineStart: line.start,
          lineEnd: line.end,
          rowIndex: rowIndex,
          columnIndex: spanIndex
        })
      }
      rows.push({
        rowIndex: rowIndex,
        lineIndex: line.index,
        lineStart: line.start,
        lineEnd: line.end,
        spans: spans
      })
    }

    regions.push({
      sourceStart: lines[headerIndex].start,
      sourceEnd: lines[finalLineIndex].end,
      separatorStart: lines[headerIndex + 1].start,
      separatorEnd: lines[headerIndex + 1].end,
      columnCount: columnCount,
      rows: rows
    })
    headerIndex = Math.max(headerIndex + 2, bodyIndex)
  }
  return regions
}

function tableRegionForPosition(sourceValue, value) {
  var source = sourceText(sourceValue)
  var position = clampPosition(source, value)
  var regions = tableRegions(source)
  return tableRegionForPositionInRegions(regions, position)
}

function tableRegionForPositionInRegions(regionsValue, positionValue) {
  var regions = Array.isArray(regionsValue) ? regionsValue : []
  var position = Number(positionValue)
  if (!isFinite(position)) position = 0
  for (var index = 0; index < regions.length; index++) {
    if (position >= regions[index].sourceStart &&
      position <= regions[index].sourceEnd) return regions[index]
  }
  return null
}

function sameTableRegion(first, second) {
  return Boolean(first && second &&
    first.sourceStart === second.sourceStart &&
    first.sourceEnd === second.sourceEnd)
}

function tableCellContext(sourceValue, value, preferPrevious) {
  var source = sourceText(sourceValue)
  var position = clampPosition(source, value)
  var region = tableRegionForPositionInRegions(tableRegions(source), position)
  return tableCellContextInRegion(region, position, preferPrevious)
}

function tableCellContextInRegion(region, positionValue, preferPrevious) {
  var position = Number(positionValue)
  if (!isFinite(position)) position = 0
  if (!region || (position >= region.separatorStart &&
      position <= region.separatorEnd)) return null

  for (var rowIndex = 0; rowIndex < region.rows.length; rowIndex++) {
    var row = region.rows[rowIndex]
    if (position < row.lineStart || position > row.lineEnd) continue
    for (var columnIndex = 0; columnIndex < row.spans.length;
         columnIndex++) {
      var span = row.spans[columnIndex]
      if (position < span.start) {
        var chosen = preferPrevious !== false && columnIndex > 0
          ? row.spans[columnIndex - 1] : span
        return {region: region, row: row, span: chosen,
          rowIndex: rowIndex, columnIndex: chosen.columnIndex,
          position: position}
      }
      if (position <= span.end || columnIndex === row.spans.length - 1) {
        return {region: region, row: row, span: span,
          rowIndex: rowIndex, columnIndex: columnIndex,
          position: position}
      }
    }
  }
  return null
}

function adjacentTableCell(contextValue, direction, sameColumn) {
  var context = contextValue
  if (!context || !context.region) return null
  var rows = context.region.rows
  if (sameColumn) {
    var nextRow = context.rowIndex + (direction < 0 ? -1 : 1)
    if (nextRow < 0 || nextRow >= rows.length) return null
    return rows[nextRow].spans[Math.min(
      context.columnIndex, rows[nextRow].spans.length - 1)] || null
  }
  var flatIndex = context.rowIndex * context.region.columnCount +
    context.columnIndex + (direction < 0 ? -1 : 1)
  var flatCount = rows.length * context.region.columnCount
  if (flatIndex < 0 || flatIndex >= flatCount) return null
  var rowIndex = Math.floor(flatIndex / context.region.columnCount)
  var columnIndex = flatIndex % context.region.columnCount
  return rows[rowIndex].spans[columnIndex] || null
}

function tableNavigationTarget(sourceValue, value, direction, mode, rawMode,
                               selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  if (rawMode || direction === 0 || selectionStart !== selectionEnd) return -1
  var context = tableCellContext(source, cursor, direction < 0)
  if (!context) return -1

  if (mode === "home") return context.span.start
  if (mode === "end") return context.span.end
  if (mode === "row") {
    var rowCell = adjacentTableCell(context, direction, true)
    return rowCell ? rowCell.start : cursor
  }
  if (mode === "tab") {
    var tabCell = adjacentTableCell(context, direction, false)
    return tabCell ? tabCell.start : cursor
  }
  if (mode !== "horizontal") return -1

  if (direction < 0) {
    if (cursor > context.span.start && cursor <= context.span.end) return -1
    var previousCell = adjacentTableCell(context, -1, false)
    return previousCell ? previousCell.end : context.span.start
  }
  if (cursor >= context.span.start && cursor < context.span.end) return -1
  var nextCell = adjacentTableCell(context, 1, false)
  return nextCell ? nextCell.start : context.span.end
}

function tableEditableCharacter(region, sourceIndex) {
  if (!region) return false
  for (var rowIndex = 0; rowIndex < region.rows.length; rowIndex++) {
    var spans = region.rows[rowIndex].spans
    for (var columnIndex = 0; columnIndex < spans.length; columnIndex++) {
      if (sourceIndex >= spans[columnIndex].start &&
          sourceIndex < spans[columnIndex].end) return true
    }
  }
  return false
}

function sanitizeTableInsertion(value) {
  var text = sourceText(value).replace(/\r\n?|\n/g, " ")
  var sanitized = ""
  var backslashRun = 0
  for (var index = 0; index < text.length; index++) {
    var character = text.charAt(index)
    if (character === "|") {
      if (backslashRun % 2 === 0) sanitized += "\\"
      sanitized += character
      backslashRun = 0
    } else {
      sanitized += character
      if (character === "\\") backslashRun++
      else backslashRun = 0
    }
  }
  return sanitized
}

function protectedTableSelectionEdit(sourceValue, startValue, endValue,
                                     insertedValue) {
  var source = sourceText(sourceValue)
  var start = clampPosition(source, startValue)
  var end = clampPosition(source, endValue)
  if (start > end) {
    var swap = start
    start = end
    end = swap
  }
  var startRegion = tableRegionForPosition(source, start)
  var endRegion = tableRegionForPosition(source, end)
  if (!sameTableRegion(startRegion, endRegion) ||
      (start <= startRegion.sourceStart && end >= startRegion.sourceEnd)) {
    return {handled: false, source: source, cursor: start}
  }

  var inserted = sanitizeTableInsertion(insertedValue)
  var context = tableCellContext(source, start, false) ||
    tableCellContext(source, start, true)
  if (!context) {
    return {handled: true, changed: false, source: source, cursor: start}
  }
  for (var protectedIndex = start; protectedIndex < end;
       protectedIndex++) {
    if (!tableEditableCharacter(startRegion, protectedIndex)) {
      return {handled: true, changed: false, source: source,
        cursor: context.span.start}
    }
  }
  var finalSelectedPosition = Math.max(start, end - 1)
  var endContext = tableCellContext(source, finalSelectedPosition, true) ||
    tableCellContext(source, finalSelectedPosition, false)
  if (!endContext || endContext.rowIndex !== context.rowIndex ||
      endContext.columnIndex !== context.columnIndex) {
    return {handled: true, changed: false, source: source,
      cursor: context.span.start}
  }
  var insertAt = Math.max(context.span.start,
    Math.min(context.span.end, start))
  var replacement = ""
  var cursor = start
  var insertedWritten = false
  var removedEditable = false
  for (var index = start; index < end; index++) {
    if (!insertedWritten && index === insertAt) {
      replacement += inserted
      cursor = start + replacement.length
      insertedWritten = true
    }
    if (!tableEditableCharacter(startRegion, index))
      replacement += source.charAt(index)
    else removedEditable = true
  }
  if (!insertedWritten) {
    replacement += inserted
    cursor = start + replacement.length
  }
  var nextSource = source.slice(0, start) + replacement + source.slice(end)
  if (!removedEditable && inserted === "") {
    return {handled: true, changed: false, source: source,
      cursor: context.span.start}
  }
  return {
    handled: true,
    changed: nextSource !== source,
    source: nextSource,
    cursor: cursor
  }
}

function tableRegionOverlappingRange(sourceValue, startValue, endValue) {
  var source = sourceText(sourceValue)
  var start = clampPosition(source, startValue)
  var end = clampPosition(source, endValue)
  if (start > end) {
    var swap = start
    start = end
    end = swap
  }
  var regions = tableRegions(source)
  for (var index = 0; index < regions.length; index++) {
    var region = regions[index]
    if (start === end) {
      if (start >= region.sourceStart && start <= region.sourceEnd)
        return region
    } else if (start < region.sourceEnd && end > region.sourceStart) {
      return region
    }
  }
  return null
}

function tableDelete(sourceValue, value, selectionStart, selectionEnd,
                     direction, rawMode) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  if (rawMode) return {handled: false, source: source, cursor: cursor}
  var start = clampPosition(source, selectionStart)
  var end = clampPosition(source, selectionEnd)
  if (start !== end) {
    var startRegion = tableRegionForPosition(source, start)
    var finalRegion = tableRegionForPosition(source,
      Math.max(start, end - 1))
    if (!sameTableRegion(startRegion, finalRegion)) {
      var overlappingRegion = tableRegionOverlappingRange(source, start, end)
      if (overlappingRegion) {
        var safeContext = tableCellContext(source, start, false) ||
          tableCellContext(source, start, true)
        return {handled: true, changed: false, source: source,
          cursor: safeContext ? safeContext.span.start :
            overlappingRegion.sourceStart}
      }
    }
    return protectedTableSelectionEdit(source, start, end, "")
  }
  var context = tableCellContext(source, cursor, direction < 0)
  if (!context) return {handled: false, source: source, cursor: cursor}
  if (direction < 0 && cursor <= context.span.start) {
    return {handled: true, changed: false, source: source,
      cursor: context.span.start}
  }
  if (direction > 0 && cursor >= context.span.end) {
    return {handled: true, changed: false, source: source,
      cursor: context.span.end}
  }
  if (cursor < context.span.start || cursor > context.span.end) {
    return {handled: true, changed: false, source: source,
      cursor: direction < 0 ? context.span.end : context.span.start}
  }
  return {handled: false, source: source, cursor: cursor}
}

function protectLiveTableEdit(beforeValue, afterValue, cursorBeforeValue,
                              selectionStartValue, selectionEndValue,
                              rawMode) {
  var before = sourceText(beforeValue)
  var after = sourceText(afterValue)
  if (rawMode || before === after) {
    return {protected: false, source: after, cursor: clampPosition(after,
      cursorBeforeValue)}
  }
  var transaction = makeEditTransaction(before, after, {
    cursor: cursorBeforeValue,
    selectionStart: selectionStartValue,
    selectionEnd: selectionEndValue
  }, {cursor: 0, selectionStart: 0, selectionEnd: 0}, 0)
  if (!transaction) {
    return {protected: false, source: after, cursor: after.length}
  }
  // A longest-common-prefix diff cannot identify which identical space in a
  // run was inserted. Use the native pre-edit selection when it reproduces the
  // exact result; otherwise the second/third Space can be misclassified as an
  // insertion into delimiter padding and unnecessarily rewritten or blocked.
  var intendedStart = clampPosition(before,
    Math.min(Number(selectionStartValue), Number(selectionEndValue)))
  var intendedEnd = clampPosition(before,
    Math.max(Number(selectionStartValue), Number(selectionEndValue)))
  var intendedInsertedLength = after.length -
    (before.length - (intendedEnd - intendedStart))
  if (intendedInsertedLength >= 0) {
    var intendedInserted = after.slice(
      intendedStart, intendedStart + intendedInsertedLength)
    var intendedAfter = before.slice(0, intendedStart) + intendedInserted +
      before.slice(intendedEnd)
    if (intendedAfter === after) {
      transaction.start = intendedStart
      transaction.removed = before.slice(intendedStart, intendedEnd)
      transaction.inserted = intendedInserted
    }
  }
  var start = transaction.start
  var end = start + transaction.removed.length
  // Normal typing used to parse every table in the complete note three times:
  // once for each edit boundary and once again for its cell context. Resolve
  // all three queries from one immutable region snapshot.
  var regions = tableRegions(before)
  var region = tableRegionForPositionInRegions(regions, start)
  var endRegion = tableRegionForPositionInRegions(regions, end)
  if (!sameTableRegion(region, endRegion)) {
    var overlappingRegion = tableRegionOverlappingRange(before, start, end)
    if (overlappingRegion) {
      var safeContext = tableCellContext(before, start, false) ||
        tableCellContext(before, start, true)
      return {protected: true, source: before,
        cursor: safeContext ? safeContext.span.start :
          overlappingRegion.sourceStart}
    }
    return {protected: false, source: after,
      cursor: start + transaction.inserted.length}
  }

  var context = tableCellContextInRegion(region, start, false) ||
    tableCellContextInRegion(region, start, true)
  var insertionAllowed = context && start >= context.span.start &&
    start <= context.span.end
  var structuralRemoval = false
  for (var index = start; index < end; index++) {
    if (!tableEditableCharacter(region, index)) {
      structuralRemoval = true
      break
    }
  }
  var sanitized = sanitizeTableInsertion(transaction.inserted)
  if (!structuralRemoval && insertionAllowed &&
      sanitized === transaction.inserted) {
    return {protected: false, source: after,
      cursor: start + transaction.inserted.length, tableCell: true}
  }

  var protectedEdit = protectedTableSelectionEdit(
    before, start, end, sanitized)
  return {
    protected: true,
    source: protectedEdit.source,
    cursor: protectedEdit.cursor
  }
}

function tableToolbarState(sourceValue, value, rawMode) {
  var source = sourceText(sourceValue)
  if (rawMode) return {active: false}
  var cursor = clampPosition(source, value)
  var context = tableCellContext(source, cursor, true) ||
    tableCellContext(source, cursor, false)
  if (!context) return {active: false}
  // Rendered cell padding and hidden internal delimiters are still visibly
  // inside the table. Keep the helper active there and associate them with the
  // preceding cell. Only the outer source boundaries can also represent the
  // adjacent blank rendered row, so exclude those exact positions.
  var outerStart = context.region.sourceStart
  var outerEnd = context.region.sourceEnd
  if (cursor === outerStart && source.charAt(outerStart) === "|" ||
      cursor === outerEnd && source.charAt(Math.max(0, outerEnd - 1)) === "|")
    return {active: false}
  var needsRepair = false
  for (var rowIndex = 0; rowIndex < context.region.rows.length; rowIndex++) {
    var row = context.region.rows[rowIndex]
    var line = source.slice(row.lineStart, row.lineEnd)
    if (tableRowCells(line).length !== context.region.columnCount) {
      needsRepair = true
      break
    }
  }
  return {
    active: true,
    tableStart: context.region.sourceStart,
    tableEnd: context.region.sourceEnd,
    tableContentStart: context.region.rows[0].spans[0].start,
    rowIndex: context.rowIndex,
    columnIndex: context.columnIndex,
    rowCount: context.region.rows.length,
    columnCount: context.region.columnCount,
    canDeleteRow: context.rowIndex > 0,
    canDeleteColumn: context.region.columnCount > 1,
    needsRepair: needsRepair
  }
}

function formattedTableRow(cellsValue) {
  var cells = Array.isArray(cellsValue) ? cellsValue : []
  return "| " + cells.join(" | ") + " |"
}

function normalizedTableCells(cellsValue, columnCountValue, fillValue,
                              preserveOverflow) {
  var cells = Array.isArray(cellsValue) ? cellsValue : []
  var columnCount = Math.max(1, Number(columnCountValue) || 1)
  var fill = sourceText(fillValue)
  var normalized = cells.slice(0, columnCount)
  while (normalized.length < columnCount) normalized.push(fill)
  if (preserveOverflow && cells.length > columnCount) {
    var folded = [normalized[columnCount - 1]]
    for (var index = columnCount; index < cells.length; index++) {
      if (sourceText(cells[index]).trim() !== "") folded.push(cells[index])
    }
    if (folded.length > 1) {
      normalized[columnCount - 1] = sanitizeTableInsertion(
        folded.join(" | "))
    }
  }
  return normalized
}

function tableStructuralEdit(sourceValue, value, actionValue, rawMode) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var action = sourceText(actionValue)
  var context = rawMode ? null :
    (tableCellContext(source, cursor, false) ||
      tableCellContext(source, cursor, true))
  if (!context) {
    return {handled: false, changed: false, source: source, cursor: cursor}
  }

  var supported = ["rowBefore", "rowAfter", "rowDelete",
    "columnBefore", "columnAfter", "columnDelete", "tableDelete",
    "tableRepair"]
  if (supported.indexOf(action) < 0) {
    return {handled: false, changed: false, source: source, cursor: cursor}
  }

  var region = context.region
  if (action === "tableDelete") {
    var deleteStart = region.sourceStart
    var deleteEnd = region.sourceEnd
    if (source.slice(deleteEnd, deleteEnd + 2) === "\r\n") deleteEnd += 2
    else if (source.charAt(deleteEnd) === "\n") deleteEnd++
    else if (deleteStart > 0 && source.charAt(deleteStart - 1) === "\n") {
      deleteStart--
      if (deleteStart > 0 && source.charAt(deleteStart - 1) === "\r")
        deleteStart--
    }
    return {
      handled: true,
      changed: true,
      source: source.slice(0, deleteStart) + source.slice(deleteEnd),
      cursor: deleteStart
    }
  }

  var lines = sourceLines(source)
  var headerLine = null
  var separatorLine = null
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    if (lines[lineIndex].start === region.sourceStart)
      headerLine = lines[lineIndex]
    if (lines[lineIndex].start === region.separatorStart)
      separatorLine = lines[lineIndex]
  }
  if (!headerLine || !separatorLine) {
    return {handled: false, changed: false, source: source, cursor: cursor}
  }

  var headerCells = tableRowCells(headerLine.text)
  var separatorCells = tableRowCells(separatorLine.text)
  var bodyCells = []
  for (var rowIndex = 1; rowIndex < region.rows.length; rowIndex++) {
    var row = region.rows[rowIndex]
    bodyCells.push(tableRowCells(
      source.slice(row.lineStart, row.lineEnd)))
  }
  if (action === "tableRepair") {
    headerCells = headerCells.map(function(cell) { return sourceText(cell).trim() })
    separatorCells = separatorCells.map(function(cell) {
      return sourceText(cell).trim()
    })
    bodyCells = bodyCells.map(function(row) {
      return row.map(function(cell) { return sourceText(cell).trim() })
    })
  }
  var normalizedColumnCount = Math.max(1, headerCells.length)
  headerCells = normalizedTableCells(
    headerCells, normalizedColumnCount, "", true)
  separatorCells = normalizedTableCells(
    separatorCells, normalizedColumnCount, "---", false)
  for (var separatorIndex = 0;
       separatorIndex < separatorCells.length; separatorIndex++) {
    if (!/^:?-{3,}:?$/.test(separatorCells[separatorIndex]))
      separatorCells[separatorIndex] = "---"
  }
  for (var normalizeRow = 0; normalizeRow < bodyCells.length;
       normalizeRow++) {
    bodyCells[normalizeRow] = normalizedTableCells(
      bodyCells[normalizeRow], normalizedColumnCount, "", true)
  }
  var targetRow = context.rowIndex
  var targetColumn = context.columnIndex

  if (action === "rowBefore" || action === "rowAfter") {
    var insertionIndex = context.rowIndex === 0 ? 0 :
      context.rowIndex - 1 + (action === "rowAfter" ? 1 : 0)
    var emptyRow = []
    for (var emptyIndex = 0; emptyIndex < normalizedColumnCount; emptyIndex++)
      emptyRow.push("")
    bodyCells.splice(insertionIndex, 0, emptyRow)
    targetRow = insertionIndex + 1
  } else if (action === "rowDelete") {
    if (context.rowIndex === 0) {
      return {handled: true, changed: false, source: source, cursor: cursor}
    }
    bodyCells.splice(context.rowIndex - 1, 1)
    targetRow = bodyCells.length === 0 ? 0 :
      Math.min(context.rowIndex, bodyCells.length)
  } else if (action === "columnBefore" || action === "columnAfter") {
    var columnInsertion = context.columnIndex +
      (action === "columnAfter" ? 1 : 0)
    headerCells.splice(columnInsertion, 0, "")
    separatorCells.splice(columnInsertion, 0, "---")
    for (var bodyIndex = 0; bodyIndex < bodyCells.length; bodyIndex++)
      bodyCells[bodyIndex].splice(columnInsertion, 0, "")
    targetColumn = columnInsertion
  } else if (action === "columnDelete") {
    if (region.columnCount <= 1) {
      return {handled: true, changed: false, source: source, cursor: cursor}
    }
    headerCells.splice(context.columnIndex, 1)
    separatorCells.splice(context.columnIndex, 1)
    for (var deleteRow = 0; deleteRow < bodyCells.length; deleteRow++)
      bodyCells[deleteRow].splice(context.columnIndex, 1)
    targetColumn = Math.min(context.columnIndex, headerCells.length - 1)
  }

  var eol = source.slice(region.sourceStart, region.sourceEnd)
    .indexOf("\r\n") >= 0 ? "\r\n" : "\n"
  var replacementRows = [formattedTableRow(headerCells),
    formattedTableRow(separatorCells)]
  for (var replacementIndex = 0;
       replacementIndex < bodyCells.length; replacementIndex++) {
    replacementRows.push(formattedTableRow(bodyCells[replacementIndex]))
  }
  var replacementValid = isTableStart(
    replacementRows[0], replacementRows[1])
  for (var validationIndex = 0;
       replacementValid && validationIndex < replacementRows.length;
       validationIndex++) {
    replacementValid = tableRowCells(
      replacementRows[validationIndex]).length === headerCells.length
  }
  if (!replacementValid) {
    return {handled: true, changed: false, source: source, cursor: cursor}
  }
  var replacement = replacementRows.join(eol)
  var replaceEnd = region.sourceEnd
  var nextSource = source.slice(0, region.sourceStart) + replacement +
    source.slice(replaceEnd)
  var nextRegions = tableRegions(nextSource)
  var nextRegion = null
  for (var regionIndex = 0; regionIndex < nextRegions.length; regionIndex++) {
    if (nextRegions[regionIndex].sourceStart === region.sourceStart) {
      nextRegion = nextRegions[regionIndex]
      break
    }
  }
  var nextCursor = region.sourceStart
  if (nextRegion && nextRegion.rows.length > 0) {
    var nextRow = nextRegion.rows[Math.max(0, Math.min(
      targetRow, nextRegion.rows.length - 1))]
    var nextSpan = nextRow.spans[Math.max(0, Math.min(
      targetColumn, nextRow.spans.length - 1))]
    if (nextSpan) nextCursor = nextSpan.start
  }
  return {
    handled: true,
    changed: nextSource !== source,
    source: nextSource,
    cursor: nextCursor
  }
}

function tableMaterializeCell(sourceValue, tableStartValue, rowIndexValue,
                              columnIndexValue, rawMode) {
  var source = sourceText(sourceValue)
  if (rawMode) return {handled: false, changed: false, source: source,
    cursor: clampPosition(source, tableStartValue)}
  var tableStart = clampPosition(source, tableStartValue)
  var rowIndex = Math.max(0, Number(rowIndexValue) || 0)
  var columnIndex = Math.max(0, Number(columnIndexValue) || 0)
  var regions = tableRegions(source)
  var region = null
  for (var index = 0; index < regions.length; index++) {
    if (regions[index].sourceStart === tableStart) {
      region = regions[index]
      break
    }
  }
  if (!region || rowIndex >= region.rows.length ||
      columnIndex >= region.columnCount) {
    return {handled: false, changed: false, source: source,
      cursor: tableStart}
  }
  var row = region.rows[rowIndex]
  var rowSource = source.slice(row.lineStart, row.lineEnd)
  var cells = tableRowCells(rowSource).map(function(cell) {
    return sourceText(cell).trim()
  })
  if (cells.length > columnIndex) {
    return {handled: true, changed: false, source: source,
      cursor: row.spans[columnIndex].start}
  }
  while (cells.length < region.columnCount) cells.push("")
  var replacement = formattedTableRow(cells)
  var nextSource = source.slice(0, row.lineStart) + replacement +
    source.slice(row.lineEnd)
  var nextRegions = tableRegions(nextSource)
  for (var nextIndex = 0; nextIndex < nextRegions.length; nextIndex++) {
    var nextRegion = nextRegions[nextIndex]
    if (nextRegion.sourceStart !== tableStart ||
        rowIndex >= nextRegion.rows.length) continue
    var nextSpan = nextRegion.rows[rowIndex].spans[columnIndex]
    return {handled: true, changed: true, source: nextSource,
      cursor: nextSpan ? nextSpan.start : row.lineStart}
  }
  return {handled: true, changed: true, source: nextSource,
    cursor: row.lineStart}
}

function fencedBlockOpenBefore(sourceValue, lineStart) {
  var source = sourceText(sourceValue)
  var lines = source.slice(0, lineStart).split("\n")
  var openMarker = ""
  var openLength = 0

  for (var index = 0; index < lines.length; index++) {
    var fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(lines[index])
    if (!fence) continue

    var marker = fence[1].charAt(0)
    if (!openMarker) {
      openMarker = marker
      openLength = fence[1].length
      continue
    }

    if (marker !== openMarker) continue
    var closingFence = new RegExp(
      "^ {0,3}" + marker + "{" + openLength + ",}\\s*$")
    if (closingFence.test(lines[index])) {
      openMarker = ""
      openLength = 0
    }
  }

  return openMarker !== ""
}

function fencedCodeContext(sourceValue, value) {
  var source = sourceText(sourceValue)
  var position = clampPosition(source, value)
  var lineStart = source.lastIndexOf("\n", Math.max(0, position - 1)) + 1
  var scanStart = 0
  var openMarker = ""
  var openLength = 0
  var languageInfo = ""
  var contentStart = -1

  while (scanStart < lineStart) {
    var lineEnd = source.indexOf("\n", scanStart)
    if (lineEnd < 0 || lineEnd >= lineStart) break
    var line = source.slice(scanStart, lineEnd)
    if (line.charAt(line.length - 1) === "\r") line = line.slice(0, -1)
    var fence = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line)
    if (fence) {
      var marker = fence[1].charAt(0)
      if (!openMarker) {
        openMarker = marker
        openLength = fence[1].length
        languageInfo = fence[2]
        contentStart = lineEnd + 1
      } else if (marker === openMarker) {
        var closingFence = new RegExp(
          "^ {0,3}" + marker + "{" + openLength + ",}\\s*$")
        if (closingFence.test(line)) {
          openMarker = ""
          openLength = 0
          languageInfo = ""
          contentStart = -1
        }
      }
    }
    scanStart = lineEnd + 1
  }

  if (!openMarker || contentStart < 0 || position < contentStart) return null
  var token = languageInfo.trim().split(/\s+/)[0] || ""
  token = token.replace(/^\./, "").toLowerCase()
  return {
    languageInfo: languageInfo,
    languageToken: token,
    contentStart: contentStart,
    lineStart: lineStart,
    position: position,
    marker: openMarker,
    markerLength: openLength
  }
}

function languageHasHashComments(languageToken) {
  return /^(?:bash|csh|fish|ini|make|perl|python|py|r|ruby|rb|shell|sh|toml|yaml|yml)$/.test(
    languageToken)
}

function languageIsMarkup(languageToken) {
  return /^(?:html|htm|xml|xhtml|svg|jsx|tsx|vue|svelte)$/.test(
    languageToken)
}

function codeLexicalState(sourceValue, startValue, endValue, languageToken) {
  var source = sourceText(sourceValue)
  var start = Math.max(0, Number(startValue) || 0)
  var end = Math.max(start, Math.min(source.length, Number(endValue) || 0))
  var quote = ""
  var blockComment = false
  var lineComment = false
  var index = start

  while (index < end) {
    var character = source.charAt(index)
    var next = source.charAt(index + 1)

    if (lineComment) {
      if (character === "\n") lineComment = false
      index++
      continue
    }
    if (blockComment) {
      if (character === "*" && next === "/") {
        blockComment = false
        index += 2
      } else if (languageIsMarkup(languageToken) &&
                 source.slice(index, index + 3) === "-->") {
        blockComment = false
        index += 3
      } else {
        index++
      }
      continue
    }
    if (quote) {
      if (character === "\\") {
        index += Math.min(2, end - index)
      } else if (character === quote) {
        quote = ""
        index++
      } else {
        index++
      }
      continue
    }

    if (character === "/" && next === "*") {
      blockComment = true
      index += 2
      continue
    }
    if (languageIsMarkup(languageToken) &&
        source.slice(index, index + 4) === "<!--") {
      blockComment = true
      index += 4
      continue
    }
    if ((character === "/" && next === "/") ||
        (languageHasHashComments(languageToken) && character === "#") ||
        ((languageToken === "sql" || languageToken === "lua" ||
          languageToken === "haskell" || languageToken === "hs") &&
          character === "-" && next === "-")) {
      lineComment = true
      index += character === "/" && next === "/" ? 2 :
        character === "-" && next === "-" ? 2 : 1
      continue
    }
    if (character === "\"" || character === "'" || character === "`") {
      quote = character
    }
    index++
  }

  return {
    inString: quote !== "",
    inComment: blockComment || lineComment
  }
}

function codeTagCompletion(sourceValue, context, cursor) {
  if (!languageIsMarkup(context.languageToken)) return null
  var source = sourceText(sourceValue)
  var prefix = source.slice(context.contentStart, cursor)
  if (/^<>$/.test(prefix)) return { openText: "<>", closeText: "</>" }

  var tag = /<([A-Za-z][A-Za-z0-9:._-]*)(?:\s+[^<>]*?)?\s*>$/.exec(prefix)
  if (!tag || /\/\s*>$/.test(tag[0])) return null
  var tagName = tag[1]
  if (/^(?:area|base|br|col|embed|hr|img|input|link|meta|param|source|track|wbr)$/i.test(tagName)) {
    return null
  }
  return {
    openText: tag[0],
    closeText: "</" + tagName + ">"
  }
}

function completeCodePair(currentValue, previousValue, value, pairs) {
  var current = sourceText(currentValue)
  var previous = sourceText(previousValue)
  var cursor = clampPosition(current, value)
  if (cursor < 1 || current.length !== previous.length + 1) {
    return { changed: false, source: current, cursor: cursor }
  }

  var insertedIndex = cursor - 1
  var inserted = current.charAt(insertedIndex)
  var pending = Array.isArray(pairs) ? pairs : []
  for (var pendingIndex = pending.length - 1;
       pendingIndex >= 0; pendingIndex--) {
    var pendingPair = pending[pendingIndex] || {}
    var pendingCloseStart = Number(pendingPair.closeStart)
    var pendingCloseText = sourceText(pendingPair.closeText)
    if (pendingCloseStart !== insertedIndex || pendingCloseText.length !== 1 ||
        pendingCloseText !== inserted ||
        current.slice(cursor, cursor + pendingCloseText.length) !==
          pendingCloseText) continue
    return {
      changed: true,
      action: "skip",
      pairIndex: pendingIndex,
      source: current.slice(0, insertedIndex) + current.slice(cursor),
      cursor: insertedIndex
    }
  }

  // Ordinary typing cannot produce a pair or HTML-tag completion. Reject it
  // before fencedCodeContext() scans all preceding lines in a large note.
  if ("([{'\"`>".indexOf(inserted) < 0) {
    return { changed: false, source: current, cursor: cursor }
  }

  var context = fencedCodeContext(current, cursor)
  if (!context) return { changed: false, source: current, cursor: cursor }
  var state = codeLexicalState(current, context.contentStart,
    insertedIndex, context.languageToken)
  if (state.inString || state.inComment) {
    return { changed: false, source: current, cursor: cursor }
  }

  var tagCompletion = inserted === ">"
    ? codeTagCompletion(current, context, cursor) : null
  if (tagCompletion) {
    return {
      changed: true,
      action: "insert",
      source: current.slice(0, cursor) + tagCompletion.closeText +
        current.slice(cursor),
      cursor: cursor,
      closeStart: cursor,
      closeText: tagCompletion.closeText,
      openText: tagCompletion.openText
    }
  }

  var pairClosers = {
    "(": ")",
    "[": "]",
    "{": "}",
    "\"": "\"",
    "'": "'",
    "`": "`"
  }
  var close = pairClosers[inserted]
  if (!close || (inserted === "\"" || inserted === "'" || inserted === "`") &&
      current.charAt(insertedIndex - 1) === "\\") {
    return { changed: false, source: current, cursor: cursor }
  }

  return {
    changed: true,
    action: "insert",
    source: current.slice(0, cursor) + close + current.slice(cursor),
    cursor: cursor,
    closeStart: cursor,
    closeText: close,
    openText: inserted
  }
}

function completeCodeFence(currentValue, previousValue, value) {
  var current = sourceText(currentValue)
  var previous = sourceText(previousValue)
  var cursor = clampPosition(current, value)
  if (cursor < 3 || current.length !== previous.length + 1) {
    return { changed: false, source: current, cursor: cursor }
  }

  var insertedIndex = cursor - 1
  if (current.charAt(insertedIndex) !== "`") {
    return { changed: false, source: current, cursor: cursor }
  }

  var lineStart = current.lastIndexOf("\n", insertedIndex - 1) + 1
  var lineEnd = current.indexOf("\n", cursor)
  if (lineEnd < 0) lineEnd = current.length
  var linePrefix = current.slice(lineStart, cursor)
  var lineSuffix = current.slice(cursor, lineEnd)
  var opener = /^( {0,3})(```)$/.exec(linePrefix)
  if (!opener || (lineSuffix !== "" && lineSuffix !== "\r") ||
      fencedBlockOpenBefore(current, lineStart)) {
    return { changed: false, source: current, cursor: cursor }
  }

  var newline = "\n"
  if (lineSuffix === "\r" || current.indexOf("\r\n") >= 0) {
    newline = "\r\n"
  }
  var closing = opener[1] + "```"
  var suffix = current.slice(cursor)
  var trailingNewline = suffix.indexOf("\r\n") === 0 ||
    suffix.charAt(0) === "\n" ? "" : newline
  var closeText = closing + trailingNewline
  return {
    changed: true,
    source: current.slice(0, cursor) + newline + newline + closeText + suffix,
    cursor: cursor,
    closeStart: cursor + newline.length * 2,
    closeText: closeText
  }
}

function completeListMarker(currentValue, previousValue, value) {
  var current = sourceText(currentValue)
  var previous = sourceText(previousValue)
  var cursor = clampPosition(current, value)
  if (cursor < 1 || current.length !== previous.length + 1) {
    return { changed: false, source: current, cursor: cursor }
  }

  var insertedIndex = cursor - 1
  if (!/[-+*]/.test(current.charAt(insertedIndex))) {
    return { changed: false, source: current, cursor: cursor }
  }

  var lineStart = current.lastIndexOf("\n", insertedIndex - 1) + 1
  if (fencedBlockOpenBefore(current, lineStart)) {
    return { changed: false, source: current, cursor: cursor }
  }
  if (!/^[ \t]*$/.test(current.slice(lineStart, insertedIndex)) ||
      (insertedIndex + 1 < current.length &&
       /^[ \t]/.test(current.charAt(insertedIndex + 1)))) {
    return { changed: false, source: current, cursor: cursor }
  }

  var nextSource = current.slice(0, insertedIndex + 1) + " " +
    current.slice(insertedIndex + 1)
  return { changed: true, source: nextSource, cursor: cursor + 1 }
}

function continuedListPrefix(list) {
  var nextMarker = list.marker
  var ordered = /^(\d+)([.)])$/.exec(nextMarker)
  if (ordered) nextMarker = String(Number(ordered[1]) + 1) + ordered[2]

  var nextPrefix = list.indent + nextMarker + list.separator
  if (list.task) nextPrefix += "[ ]" + list.task[2]
  return nextPrefix
}

function liveReturnSourcePosition(sourceValue, nativeValue, visibleValue,
                                  rawMode, selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var nativePosition = clampPosition(source, nativeValue)
  var visiblePosition = Number(visibleValue)

  if (rawMode === true || selectionStart !== selectionEnd ||
      !isFinite(visiblePosition) || visiblePosition < 0 ||
      visiblePosition > source.length) return nativePosition

  // In Live Preview, Qt can advance the hidden plain-text cursor across one
  // collapsed source newline before Keys.BeforeItem observes Return. The
  // painted Preview caret still identifies the position the user acted on.
  if (nativePosition === visiblePosition + 1 &&
      source.charAt(visiblePosition) === "\n") return visiblePosition

  return nativePosition
}

function listAroundBlankLine(source, value) {
  var current = lineBounds(source, value)
  if (!/^[ \t]*$/.test(current.line) || current.lineStart <= 0)
    return null

  var previous = listPrefixAt(source, current.lineStart - 1)
  if (!previous) return null
  var previousTask = previous.task ? previous.task[3] : previous.content
  if (/^\s*$/.test(previousTask)) return null

  var nextPosition = current.lineEnd < source.length
    ? current.lineEnd + 1 : source.length
  var next = null
  while (nextPosition < source.length) {
    var nextBounds = lineBounds(source, nextPosition)
    if (!/^[ \t]*$/.test(nextBounds.line)) {
      next = listPrefixAt(source, nextPosition)
      break
    }
    if (nextBounds.lineEnd >= source.length) break
    nextPosition = nextBounds.lineEnd + 1
  }
  if (!next || next.indent !== previous.indent) return null
  return {current: current, previous: previous, next: next}
}

function nextSameIndentListAfter(source, list) {
  if (!list || list.lineEnd >= source.length) return null
  var nextPosition = list.lineEnd + 1
  while (nextPosition < source.length) {
    var bounds = lineBounds(source, nextPosition)
    if (!/^[ \t]*$/.test(bounds.line)) {
      var next = listPrefixAt(source, nextPosition)
      return next && next.indent === list.indent ? next : null
    }
    if (bounds.lineEnd >= source.length) break
    nextPosition = bounds.lineEnd + 1
  }
  return null
}

function listReturn(sourceValue, value, selectionStart, selectionEnd,
                    allowBlankLineContinuation) {
  var source = sourceText(sourceValue)
  if (selectionStart !== selectionEnd) {
    return { handled: false, source: source, cursor: clampPosition(source, value) }
  }

  var list = listPrefixAt(source, value)
  if (!list && allowBlankLineContinuation === true) {
    var aroundBlank = listAroundBlankLine(source, value)
    if (aroundBlank) {
      var blankPrefix = continuedListPrefix(aroundBlank.previous)
      return {
        handled: true,
        source: source.slice(0, aroundBlank.current.lineStart) + blankPrefix +
          aroundBlank.previous.lineBreak +
          source.slice(aroundBlank.next.lineStart),
        cursor: aroundBlank.current.lineStart + blankPrefix.length
      }
    }
  }
  if (!list || list.position - list.lineStart < list.contentStart) {
    return { handled: false, source: source, cursor: list ? list.position : clampPosition(source, value) }
  }

  var cursor = list.position
  var contentStart = list.indent.length + list.marker.length +
    list.separator.length
  var content = list.content
  var task = /^\[([ xX])\]([ \t]+)(.*)$/.exec(content)
  var itemText = task ? task[3] : content
  if (/^\s*$/.test(itemText)) {
    return {
      handled: true,
      source: source.slice(0, list.lineStart) + source.slice(list.lineEnd),
      cursor: list.lineStart
    }
  }

  var nextPrefix = continuedListPrefix(list)
  if (allowBlankLineContinuation === true && cursor === list.lineEnd) {
    var nextList = nextSameIndentListAfter(source, list)
    if (nextList) {
      return {
        handled: true,
        source: source.slice(0, cursor) + list.lineBreak + nextPrefix +
          list.lineBreak + source.slice(nextList.lineStart),
        cursor: cursor + list.lineBreak.length + nextPrefix.length
      }
    }
  }
  return {
    handled: true,
    source: source.slice(0, cursor) + list.lineBreak + nextPrefix +
      source.slice(cursor),
    cursor: cursor + list.lineBreak.length + nextPrefix.length
  }
}

function plainReturn(sourceValue, value, selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)
  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = clampPosition(source, value)
    end = start
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }

  return {
    handled: true,
    source: source.slice(0, start) + "\n" + source.slice(end),
    cursor: start + 1
  }
}

function fenceHeaderReturn(sourceValue, value, selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)
  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }
  if (start !== end) return {handled: false, source: source, cursor: cursor}

  var bounds = lineBounds(source, cursor)
  var contentEnd = bounds.lineEnd > bounds.lineStart &&
    source.charAt(bounds.lineEnd - 1) === "\r"
    ? bounds.lineEnd - 1 : bounds.lineEnd
  if (cursor !== contentEnd || bounds.lineEnd >= source.length ||
      fencedBlockOpenBefore(source, bounds.lineStart)) {
    return {handled: false, source: source, cursor: cursor}
  }

  var opener = /^ {0,3}(`{3,}|~{3,})([^\r\n]*)$/.exec(bounds.line)
  if (!opener || (opener[1].charAt(0) === "`" &&
      String(opener[2] || "").indexOf("`") >= 0)) {
    return {handled: false, source: source, cursor: cursor}
  }

  // The line break after an opening fence already exists in the source.
  // Live Preview Return enters that code row instead of adding a hidden one.
  return {handled: true, source: source, cursor: bounds.lineEnd + 1}
}

function fenceBodyBackspace(sourceValue, value, selectionStart, selectionEnd,
                            closeStartValue, closeTextValue) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)
  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }
  if (start !== end) return {handled: false, source: source, cursor: cursor}

  var closeStart = Number(closeStartValue)
  var closeText = sourceText(closeTextValue)
  if (!isFinite(closeStart) || closeStart < cursor || closeText === "" ||
      source.slice(closeStart, closeStart + closeText.length) !== closeText) {
    return {handled: false, source: source, cursor: cursor}
  }
  var bodyGap = source.slice(cursor, closeStart)
  if (bodyGap !== "" && bodyGap !== "\n" && bodyGap !== "\r\n")
    return {handled: false, source: source, cursor: cursor}

  var headerEnd = cursor
  if (source.slice(Math.max(0, cursor - 2), cursor) === "\r\n")
    headerEnd = cursor - 2
  else if (cursor > 0 && source.charAt(cursor - 1) === "\n")
    headerEnd = cursor - 1
  else
    return {handled: false, source: source, cursor: cursor}

  var headerStart = source.lastIndexOf("\n", Math.max(0, headerEnd - 1)) + 1
  var header = source.slice(headerStart, headerEnd)
  var opener = /^( {0,3})(`{3,}|~{3,})([^\r\n]*)$/.exec(header)
  if (!opener || (opener[2].charAt(0) === "`" &&
      String(opener[3] || "").indexOf("`") >= 0)) {
    return {handled: false, source: source, cursor: cursor}
  }

  // In Live Preview the language header and code body are separate visual
  // rows. Cross that boundary without deleting its structural source newline;
  // a continued Backspace can then erase the language and tracked opener.
  return {handled: true, source: source, cursor: headerEnd}
}

function backspaceEmptyCodePair(sourceValue, value, selectionStart,
                                selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)
  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }
  if (start !== end || cursor <= 0 || !fencedCodeContext(source, cursor))
    return {handled: false, changed: false, source: source, cursor: cursor}

  var opener = source.charAt(cursor - 1)
  var closerByOpener = {"(": ")", "[": "]", "{": "}"}
  var closer = closerByOpener[opener]
  if (!closer)
    return {handled: false, changed: false, source: source, cursor: cursor}

  // Generated pair metadata is intentionally transient and can disappear on
  // a tab switch or plugin reload. Reconstruct only an otherwise-empty pair:
  // the expected closer must be the next non-whitespace source character.
  // This preserves normal Backspace when real code exists between the pair.
  var closerPosition = cursor
  while (closerPosition < source.length &&
      /[ \t\r\n]/.test(source.charAt(closerPosition))) closerPosition++
  if (source.charAt(closerPosition) !== closer)
    return {handled: false, changed: false, source: source, cursor: cursor}

  return {
    handled: true,
    changed: true,
    source: source.slice(0, cursor - 1) +
      source.slice(cursor, closerPosition) +
      source.slice(closerPosition + 1),
    cursor: cursor - 1
  }
}

function backspaceOrphanCodeFence(sourceValue, value, selectionStart,
                                  selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)
  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }
  if (start !== end || fencedBlockOpenBefore(source, cursor))
    return {handled: false, changed: false, source: source, cursor: cursor}

  // After generated-fence tracking is lost, held Backspace can erase the
  // opener while its closer remains ahead of the caret. Preview then projects
  // that closer as a new empty opener, so native Backspace can never reach it.
  // Remove only a lone trailing triple-backtick row with whitespace between
  // it and the caret. A complete fence or a fence with content cannot match.
  var suffix = source.slice(cursor)
  var fenceOffset = 0
  while (fenceOffset < suffix.length &&
      /[ \t\r\n]/.test(suffix.charAt(fenceOffset))) fenceOffset++
  var fenceStart = cursor + fenceOffset
  var bounds = lineBounds(source, fenceStart)
  if (fenceStart !== bounds.lineStart &&
      !/^[ \t]*$/.test(source.slice(bounds.lineStart, fenceStart))) {
    return {handled: false, changed: false, source: source, cursor: cursor}
  }
  if (!/^ {0,3}```[ \t]*$/.test(bounds.line) ||
      !/^[ \t\r\n]*$/.test(source.slice(bounds.lineEnd))) {
    return {handled: false, changed: false, source: source, cursor: cursor}
  }

  return {
    handled: true,
    changed: source.length !== cursor,
    source: source.slice(0, cursor),
    cursor: cursor
  }
}

function headingSpace(sourceValue, value, selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  if (selectionStart !== selectionEnd || fencedCodeContext(source, cursor))
    return { handled: false, source: source, cursor: cursor }

  var bounds = lineBounds(source, cursor)
  var column = cursor - bounds.lineStart
  var before = bounds.line.slice(0, column)
  var after = bounds.line.slice(column)
  if (!/^ {0,3}#{1,6}$/.test(before) || !/^\S/.test(after))
    return { handled: false, source: source, cursor: cursor }

  return {
    handled: true,
    source: source.slice(0, cursor) + " " + source.slice(cursor),
    cursor: cursor + 1
  }
}

function formattingPrefixBackspace(sourceValue, value, selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var unchanged = {handled: false, source: source, cursor: cursor}
  if (selectionStart !== selectionEnd || fencedCodeContext(source, cursor))
    return unchanged
  var bounds = lineBounds(source, cursor)
  var prefix = /^(?:[ \t]*(?:[-+*]|\d+[.)])(?:[ \t]+(?:\[[ xX]\][ \t]*)?|$)| {0,3}#{1,6}(?:[ \t]+|$)|[ \t]*(?:>[ \t]*)+)/.exec(bounds.line)
  if (!prefix || cursor !== bounds.lineStart + prefix[0].length) return unchanged
  return {handled: true,
    source: source.slice(0, bounds.lineStart) + source.slice(cursor),
    cursor: bounds.lineStart}
}

function listBackspace(sourceValue, value, selectionStart, selectionEnd,
                       collapseEmptyItem) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  if (selectionStart !== selectionEnd) {
    return { handled: false, source: source, cursor: cursor }
  }

  if (collapseEmptyItem === true)
    return formattingPrefixBackspace(source, cursor, selectionStart, selectionEnd)

  var bounds = lineBounds(source, cursor)
  if (cursor !== bounds.lineEnd) {
    return { handled: false, source: source, cursor: cursor }
  }

  var list = /^(\s*)([-+*]|\d+[.)])([ \t]*)(.*)$/.exec(bounds.line)
  if (!list) return { handled: false, source: source, cursor: cursor }


  var markerEnd = list[1].length + list[2].length
  // Only consume the marker here, after the caret has reached the marker's
  // end and there is no remaining content. plainBackspace handles separator
  // spaces and task syntax one source character at a time.
  if (cursor !== bounds.lineStart + markerEnd ||
      bounds.line.slice(markerEnd) !== "") {
    return { handled: false, source: source, cursor: cursor }
  }

  return {
    handled: true,
    source: source.slice(0, bounds.lineStart) +
      source.slice(bounds.lineStart + markerEnd),
    cursor: bounds.lineStart + list[1].length
  }
}

function plainBackspace(sourceValue, value, selectionStart, selectionEnd) {
  var source = sourceText(sourceValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)

  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }

  if (start !== end) {
    return {
      handled: true,
      source: source.slice(0, start) + source.slice(end),
      cursor: start
    }
  }

  if (start <= 0) {
    return { handled: false, source: source, cursor: 0 }
  }

  return {
    handled: true,
    source: source.slice(0, start - 1) + source.slice(start),
    cursor: start - 1
  }
}

function trackAutoCodePairEdit(previousValue, currentValue, closeStartValue,
                               closeTextValue, allowInsertionAtCloseStart) {
  var previous = sourceText(previousValue)
  var current = sourceText(currentValue)
  var closeText = sourceText(closeTextValue)
  var closeStart = Number(closeStartValue)
  if (!isFinite(closeStart) || closeStart < 0 || closeText === "" ||
      previous.slice(closeStart, closeStart + closeText.length) !== closeText) {
    return { valid: false, closeStart: -1 }
  }

  if (previous === current) {
    return { valid: true, closeStart: closeStart }
  }

  var prefix = 0
  while (prefix < previous.length && prefix < current.length &&
         previous.charAt(prefix) === current.charAt(prefix)) {
    prefix++
  }

  var suffix = 0
  while (previous.length - suffix > prefix &&
         current.length - suffix > prefix &&
         previous.charAt(previous.length - suffix - 1) ===
           current.charAt(current.length - suffix - 1)) {
    suffix++
  }

  var previousChangeEnd = previous.length - suffix
  var currentChangeEnd = current.length - suffix
  var closeEnd = closeStart + closeText.length
  var insertion = prefix === previousChangeEnd
  var insertedText = insertion
    ? current.slice(prefix, currentChangeEnd) : ""
  var touchesCloser = insertion
    ? (prefix > closeStart && prefix < closeEnd) ||
      (allowInsertionAtCloseStart !== true && prefix === closeStart &&
       closeText.indexOf(insertedText) === 0)
    : prefix < closeEnd && previousChangeEnd > closeStart
  if (touchesCloser) return { valid: false, closeStart: -1 }

  var nextCloseStart = closeStart
  if (previousChangeEnd <= closeStart) {
    nextCloseStart += currentChangeEnd - previousChangeEnd
  } else if (prefix < closeEnd) {
    return { valid: false, closeStart: -1 }
  }

  if (nextCloseStart < 0 ||
      current.slice(nextCloseStart, nextCloseStart + closeText.length) !==
        closeText) {
    return { valid: false, closeStart: -1 }
  }
  return { valid: true, closeStart: nextCloseStart }
}

function trackAutoCodeFenceEdit(previousValue, currentValue, closeStartValue,
                                closeTextValue) {
  return trackAutoCodePairEdit(previousValue, currentValue, closeStartValue,
    closeTextValue, false)
}

function backspaceAutoCodePair(sourceValue, value, selectionStart,
                               selectionEnd, resultValue, resultCursor,
                               closeStartValue, closeTextValue, openTextValue) {
  var source = sourceText(sourceValue)
  var nextSource = sourceText(resultValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)
  var openText = sourceText(openTextValue)

  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }

  if (start !== end || openText === "" ||
      source.slice(Math.max(0, cursor - openText.length), cursor) !==
        openText) {
    return {
      handled: false,
      changed: false,
      keepPair: false,
      source: nextSource,
      cursor: clampPosition(nextSource, resultCursor)
    }
  }

  var tracked = trackAutoCodePairEdit(
    source, nextSource, closeStartValue, closeTextValue)
  if (!tracked.valid) {
    return {
      handled: false,
      changed: false,
      keepPair: false,
      source: nextSource,
      cursor: clampPosition(nextSource, resultCursor)
    }
  }

  var closeText = sourceText(closeTextValue)
  var nextPosition = clampPosition(nextSource, resultCursor)
  return {
    handled: true,
    changed: true,
    keepPair: false,
    source: nextSource.slice(0, tracked.closeStart) +
      nextSource.slice(tracked.closeStart + closeText.length),
    cursor: nextPosition
  }
}

function backspaceAutoCodeFence(sourceValue, value, selectionStart,
                                selectionEnd, resultValue, resultCursor,
                                closeStartValue, closeTextValue) {
  var source = sourceText(sourceValue)
  var nextSource = sourceText(resultValue)
  var cursor = clampPosition(source, value)
  var start = Number(selectionStart)
  var end = Number(selectionEnd)

  if (!isFinite(start) || !isFinite(end) || start < 0 || end < 0) {
    start = cursor
    end = cursor
  } else {
    start = clampPosition(source, start)
    end = clampPosition(source, end)
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
  }

  var tracked = trackAutoCodeFenceEdit(
    source, nextSource, closeStartValue, closeTextValue)
  if (!tracked.valid) {
    return {
      handled: false,
      changed: false,
      keepPair: false,
      source: nextSource,
      cursor: clampPosition(nextSource, resultCursor)
    }
  }

  var closeText = sourceText(closeTextValue)
  var closeFenceText = closeText
  if (closeFenceText.slice(-2) === "\r\n") {
    closeFenceText = closeFenceText.slice(0, -2)
  } else if (closeFenceText.charAt(closeFenceText.length - 1) === "\n") {
    closeFenceText = closeFenceText.slice(0, -1)
  }
  var probePosition = start !== end ? start : cursor
  var lineStart = source.lastIndexOf(
    "\n", Math.max(0, probePosition - 1)) + 1
  var lineEnd = source.indexOf("\n", probePosition)
  if (lineEnd < 0) lineEnd = source.length
  var contentEnd = lineEnd > lineStart && source.charAt(lineEnd - 1) === "\r"
    ? lineEnd - 1 : lineEnd
  var line = source.slice(lineStart, contentEnd)
  var completeOpener = /^( {0,3})(```)([^\r\n]*)$/.exec(line)
  var linePrefix = source.slice(lineStart, cursor)
  var partialOpener = /^( {0,3})(`{1,3})$/.exec(linePrefix)
  var selectionRemovesOpener = false
  if (start !== end && completeOpener) {
    var markerStart = lineStart + completeOpener[1].length
    var markerEnd = markerStart + completeOpener[2].length
    selectionRemovesOpener = start <= markerStart && end >= markerEnd &&
      end <= contentEnd
  }
  var opener = selectionRemovesOpener ? completeOpener : partialOpener
  if (!opener || closeFenceText !== opener[1] + "```" ||
      (start !== end && !selectionRemovesOpener)) {
    return {
      handled: false,
      changed: false,
      keepPair: false,
      source: nextSource,
      cursor: clampPosition(nextSource, resultCursor)
    }
  }

  var nextPosition = clampPosition(nextSource, resultCursor)

  if (start === end && opener[2].length > 1) {
    // The opener and closer were generated as one edit, so Backspace must not
    // expose one- and two-backtick intermediate sources. Those partial openers
    // are rendered as literal text while the surviving generated closer is
    // reinterpreted as a new empty fence. Remove the remaining opener ticks
    // now, then let the common cleanup below remove the paired closer and any
    // generated empty rows in the same source transition.
    var remainingMarkerStart = lineStart + opener[1].length
    var remainingMarkerEnd = nextPosition
    var remainingMarkerLength = Math.max(0,
      remainingMarkerEnd - remainingMarkerStart)
    nextSource = nextSource.slice(0, remainingMarkerStart) +
      nextSource.slice(remainingMarkerEnd)
    nextPosition = remainingMarkerStart
    tracked.closeStart -= remainingMarkerLength
  }

  var newline = "\n"
  if (nextSource.slice(tracked.closeStart - 2, tracked.closeStart) ===
      "\r\n") {
    newline = "\r\n"
  }
  var removeStart = tracked.closeStart
  var generatedGap = nextSource.slice(lineStart, tracked.closeStart)
  if (generatedGap === opener[1] + newline ||
      generatedGap === opener[1] + newline + newline)
    removeStart = lineStart

  return {
    handled: true,
    changed: true,
    keepPair: false,
    source: nextSource.slice(0, removeStart) +
      nextSource.slice(tracked.closeStart + closeText.length),
    cursor: Math.min(nextPosition, removeStart)
  }
}

// ---------------------------------------------------------------------------
// Per-document edit history
// ---------------------------------------------------------------------------
//
// These helpers deliberately store only a source replacement and the editor
// state at either side of that replacement.  They do not retain a complete
// source snapshot, which keeps a history entry small while still allowing an
// undo/redo operation to refuse a stale or corrupted entry safely.
//
// An edit transaction has this JSON-serializable shape:
//
// {
//   start: <source offset>,
//   removed: <source text replaced by the edit>,
//   inserted: <text introduced by the edit>,
//   beforeCursor: <cursor in the old source>,
//   afterCursor: <cursor in the new source>,
//   beforeSelectionStart: <normalized old selection start>,
//   beforeSelectionEnd: <normalized old selection end>,
//   afterSelectionStart: <normalized new selection start>,
//   afterSelectionEnd: <normalized new selection end>,
//   kind: "insert" | "backspace" | "delete" | "replace",
//   coalescible: <true only for ordinary one-character edits>,
//   timestamp: <optional caller-supplied edit time in milliseconds>
// }
//
// makeEditTransaction() uses the positional signature below because it is
// convenient to call from QML.  The state-object form is also accepted:
//
//   makeEditTransaction(oldText, newText,
//     { cursor, selectionStart, selectionEnd },
//     { cursor, selectionStart, selectionEnd }, timestamp)
//
// State objects use the same field names as the resulting transaction.  A
// missing selection defaults to the supplied cursor, and all positions are
// clamped and converted to integer source offsets.

function historyIntegerPosition(source, value, fallback) {
  var number = Number(value)
  if (!isFinite(number)) number = Number(fallback)
  if (!isFinite(number)) number = 0
  return Math.max(0, Math.min(Math.floor(number), source.length))
}

function historyState(sourceValue, cursorValue, selectionStartValue,
                      selectionEndValue) {
  var source = sourceText(sourceValue)
  var cursor = historyIntegerPosition(source, cursorValue, 0)
  var selectionStart = Number(selectionStartValue)
  var selectionEnd = Number(selectionEndValue)

  if (!isFinite(selectionStart)) selectionStart = cursor
  if (!isFinite(selectionEnd)) selectionEnd = cursor
  selectionStart = historyIntegerPosition(source, selectionStart, cursor)
  selectionEnd = historyIntegerPosition(source, selectionEnd, cursor)
  if (selectionStart > selectionEnd) {
    var swap = selectionStart
    selectionStart = selectionEnd
    selectionEnd = swap
  }

  return {
    cursor: cursor,
    selectionStart: selectionStart,
    selectionEnd: selectionEnd
  }
}

function historyStateFromValue(sourceValue, value, cursorFallback) {
  var state = value && typeof value === "object" ? value : {}
  var cursor = state.cursor
  if (!isFinite(Number(cursor))) cursor = state.position
  if (!isFinite(Number(cursor))) cursor = cursorFallback
  var selectionStart = state.selectionStart
  var selectionEnd = state.selectionEnd
  if (!isFinite(Number(selectionStart))) selectionStart = state.anchor
  if (!isFinite(Number(selectionEnd))) selectionEnd = state.focus
  return historyState(sourceValue, cursor, selectionStart, selectionEnd)
}

function transactionKind(removed, inserted, beforeState, afterState) {
  var noBeforeSelection = beforeState.selectionStart ===
    beforeState.selectionEnd
  var noAfterSelection = afterState.selectionStart ===
    afterState.selectionEnd
  var noLineBreak = removed.indexOf("\n") < 0 && inserted.indexOf("\n") < 0

  if (removed === "" && inserted !== "" && noBeforeSelection &&
      noAfterSelection && beforeState.cursor === afterState.cursor -
      inserted.length && noLineBreak) {
    return "insert"
  }
  if (removed !== "" && inserted === "" && noBeforeSelection &&
      noAfterSelection && beforeState.cursor === afterState.cursor +
      removed.length && noLineBreak) {
    return "backspace"
  }
  if (removed !== "" && inserted === "" && noBeforeSelection &&
      noAfterSelection && beforeState.cursor === afterState.cursor &&
      noLineBreak) {
    return "delete"
  }
  return "replace"
}

function makeEditTransaction(beforeSourceValue, afterSourceValue,
                             beforeCursorOrState, afterCursorOrState,
                             beforeSelectionStartValue,
                             beforeSelectionEndValue,
                             afterSelectionStartValue,
                             afterSelectionEndValue, timestampValue) {
  var beforeSource = sourceText(beforeSourceValue)
  var afterSource = sourceText(afterSourceValue)
  if (beforeSource === afterSource) return null

  var beforeState
  var afterState
  var timestamp = timestampValue
  if (beforeCursorOrState && typeof beforeCursorOrState === "object") {
    beforeState = historyStateFromValue(beforeSource,
      beforeCursorOrState, 0)
    afterState = historyStateFromValue(afterSource,
      afterCursorOrState, 0)
    // In the state-object overload the optional timestamp is the fifth
    // argument, which occupies beforeSelectionStartValue in the positional
    // signature.
    timestamp = typeof timestampValue === "undefined"
      ? beforeSelectionStartValue : timestampValue
  } else {
    beforeState = historyState(beforeSource, beforeCursorOrState,
      beforeSelectionStartValue, beforeSelectionEndValue)
    afterState = historyState(afterSource, afterCursorOrState,
      afterSelectionStartValue, afterSelectionEndValue)
    timestamp = timestampValue
  }

  var prefixLength = 0
  var commonLength = Math.min(beforeSource.length, afterSource.length)
  while (prefixLength < commonLength &&
         beforeSource.charAt(prefixLength) ===
           afterSource.charAt(prefixLength)) {
    prefixLength++
  }

  var suffixLength = 0
  while (suffixLength < beforeSource.length - prefixLength &&
         suffixLength < afterSource.length - prefixLength &&
         beforeSource.charAt(beforeSource.length - 1 - suffixLength) ===
           afterSource.charAt(afterSource.length - 1 - suffixLength)) {
    suffixLength++
  }

  var removed = beforeSource.slice(prefixLength,
    beforeSource.length - suffixLength)
  var inserted = afterSource.slice(prefixLength,
    afterSource.length - suffixLength)
  var kind = transactionKind(removed, inserted, beforeState, afterState)
  var ordinarySingleCharacter = (kind === "insert" || kind === "backspace" ||
    kind === "delete") && removed.length + inserted.length === 1

  var transaction = {
    start: prefixLength,
    removed: removed,
    inserted: inserted,
    beforeCursor: beforeState.cursor,
    afterCursor: afterState.cursor,
    beforeSelectionStart: beforeState.selectionStart,
    beforeSelectionEnd: beforeState.selectionEnd,
    afterSelectionStart: afterState.selectionStart,
    afterSelectionEnd: afterState.selectionEnd,
    kind: kind,
    coalescible: ordinarySingleCharacter
  }

  if (isFinite(Number(timestamp))) transaction.timestamp = Number(timestamp)
  return transaction
}

function historyTransactionState(transactionValue) {
  if (!transactionValue || typeof transactionValue !== "object") return null
  var transaction = transactionValue
  var startNumber = Number(transaction.start)
  if (!isFinite(startNumber) || Math.floor(startNumber) !== startNumber ||
      startNumber < 0) return null

  var removed = transaction.removed
  var inserted = transaction.inserted
  if (typeof removed !== "string" || typeof inserted !== "string") return null

  var beforeCursor = Number(transaction.beforeCursor)
  var afterCursor = Number(transaction.afterCursor)
  var beforeSelectionStart = Number(transaction.beforeSelectionStart)
  var beforeSelectionEnd = Number(transaction.beforeSelectionEnd)
  var afterSelectionStart = Number(transaction.afterSelectionStart)
  var afterSelectionEnd = Number(transaction.afterSelectionEnd)
  var positions = [beforeCursor, afterCursor, beforeSelectionStart,
    beforeSelectionEnd, afterSelectionStart, afterSelectionEnd]
  for (var positionIndex = 0; positionIndex < positions.length;
       positionIndex++) {
    if (!isFinite(positions[positionIndex]) ||
        Math.floor(positions[positionIndex]) !== positions[positionIndex] ||
        positions[positionIndex] < 0) return null
  }
  if (beforeSelectionStart > beforeSelectionEnd ||
      afterSelectionStart > afterSelectionEnd) return null

  if (typeof transaction.kind !== "undefined" &&
      transaction.kind !== "insert" && transaction.kind !== "backspace" &&
      transaction.kind !== "delete" && transaction.kind !== "replace") {
    return null
  }
  if (typeof transaction.coalescible !== "undefined" &&
      typeof transaction.coalescible !== "boolean") return null
  if (typeof transaction.timestamp !== "undefined" &&
      !isFinite(Number(transaction.timestamp))) return null

  return {
    start: startNumber,
    removed: removed,
    inserted: inserted,
    beforeCursor: beforeCursor,
    afterCursor: afterCursor,
    beforeSelectionStart: beforeSelectionStart,
    beforeSelectionEnd: beforeSelectionEnd,
    afterSelectionStart: afterSelectionStart,
    afterSelectionEnd: afterSelectionEnd,
    kind: transaction.kind || "replace",
    coalescible: transaction.coalescible === true,
    timestamp: typeof transaction.timestamp === "undefined"
      ? undefined : Number(transaction.timestamp)
  }
}

function historyResult(source, cursor, selectionStart, selectionEnd,
                       valid, direction, reason) {
  var result = {
    valid: valid,
    changed: false,
    source: source,
    cursor: cursor,
    selectionStart: selectionStart,
    selectionEnd: selectionEnd
  }
  if (direction) result.direction = direction
  if (reason) result.reason = reason
  return result
}

function applyEditTransaction(sourceValue, transactionValue, directionValue) {
  var source = sourceText(sourceValue)
  var direction
  if (directionValue === "undo" || Number(directionValue) < 0) {
    direction = "undo"
  } else if (directionValue === "redo" || Number(directionValue) > 0) {
    direction = "redo"
  } else {
    return historyResult(source, 0, 0, 0, false, null,
      "invalid-direction")
  }

  var transaction = historyTransactionState(transactionValue)
  if (!transaction) {
    return historyResult(source, 0, 0, 0, false, direction,
      "invalid-transaction")
  }

  var expected = direction === "undo"
    ? transaction.inserted : transaction.removed
  var replacement = direction === "undo"
    ? transaction.removed : transaction.inserted
  var start = transaction.start
  if (start > source.length || start + expected.length > source.length ||
      source.slice(start, start + expected.length) !== expected) {
    return historyResult(source, 0, 0, 0, false, direction,
      "source-mismatch")
  }

  var resultingSource = source.slice(0, start) + replacement +
    source.slice(start + expected.length)
  var currentCursor = direction === "undo" ? transaction.afterCursor :
    transaction.beforeCursor
  var currentSelectionStart = direction === "undo"
    ? transaction.afterSelectionStart : transaction.beforeSelectionStart
  var currentSelectionEnd = direction === "undo"
    ? transaction.afterSelectionEnd : transaction.beforeSelectionEnd
  if (currentCursor > source.length || currentSelectionStart > source.length ||
      currentSelectionEnd > source.length) {
    return historyResult(source, 0, 0, 0, false, direction,
      "invalid-state")
  }
  var cursor = direction === "undo" ? transaction.beforeCursor :
    transaction.afterCursor
  var selectionStart = direction === "undo"
    ? transaction.beforeSelectionStart : transaction.afterSelectionStart
  var selectionEnd = direction === "undo"
    ? transaction.beforeSelectionEnd : transaction.afterSelectionEnd
  var resultLength = resultingSource.length
  if (cursor > resultLength || selectionStart > resultLength ||
      selectionEnd > resultLength) {
    return historyResult(source, 0, 0, 0, false, direction,
      "invalid-state")
  }

  var result = historyResult(resultingSource, cursor, selectionStart,
    selectionEnd, true, direction)
  result.changed = resultingSource !== source
  return result
}

function historyTimeGap(first, second) {
  var firstTimestamp = Number(first.timestamp)
  var secondTimestamp = Number(second.timestamp)
  if (!isFinite(firstTimestamp) || !isFinite(secondTimestamp)) return -1
  return secondTimestamp - firstTimestamp
}

function canCoalesceHistoryTransactions(first, second, windowValue) {
  if (!first || !second) return false
  var window = Number(windowValue)
  if (!isFinite(window) || window < 0) return false
  if (first.coalescible !== true || second.coalescible !== true) return false
  var gap = historyTimeGap(first, second)
  if (gap < 0 || gap > window) return false

  var firstBeforeCollapsed = first.beforeSelectionStart ===
    first.beforeSelectionEnd
  var firstAfterCollapsed = first.afterSelectionStart ===
    first.afterSelectionEnd
  var secondBeforeCollapsed = second.beforeSelectionStart ===
    second.beforeSelectionEnd
  var secondAfterCollapsed = second.afterSelectionStart ===
    second.afterSelectionEnd
  if (!firstBeforeCollapsed || !firstAfterCollapsed ||
      !secondBeforeCollapsed || !secondAfterCollapsed) return false

  if (first.kind === "insert" && second.kind === "insert") {
    return first.start + first.inserted.length === second.start &&
      first.afterCursor === second.beforeCursor
  }
  if (first.kind === "backspace" && second.kind === "backspace") {
    return second.start + second.removed.length === first.start &&
      first.afterCursor === second.beforeCursor
  }
  if (first.kind === "delete" && second.kind === "delete") {
    return first.start === second.start &&
      first.afterCursor === second.beforeCursor
  }
  return false
}

function coalesceEditTransactions(firstValue, secondValue, windowValue) {
  var first = historyTransactionState(firstValue)
  var second = historyTransactionState(secondValue)
  if (!first || !second || !canCoalesceHistoryTransactions(first, second,
      windowValue)) return null

  var merged = {
    start: first.start,
    removed: "",
    inserted: "",
    beforeCursor: first.beforeCursor,
    afterCursor: second.afterCursor,
    beforeSelectionStart: first.beforeSelectionStart,
    beforeSelectionEnd: first.beforeSelectionEnd,
    afterSelectionStart: second.afterSelectionStart,
    afterSelectionEnd: second.afterSelectionEnd,
    kind: first.kind,
    coalescible: true
  }

  if (first.kind === "insert") {
    merged.start = first.start
    merged.inserted = first.inserted + second.inserted
  } else if (first.kind === "backspace") {
    merged.start = second.start
    merged.removed = second.removed + first.removed
  } else {
    merged.start = first.start
    merged.removed = first.removed + second.removed
  }

  if (typeof second.timestamp !== "undefined") {
    merged.timestamp = second.timestamp
  }
  return merged
}

function validateEditTransactionChain(sourceValue, pastValue, futureValue) {
  var source = sourceText(sourceValue)
  var past = Array.isArray(pastValue) ? pastValue : null
  var future = Array.isArray(futureValue) ? futureValue : null
  if (!past || !future) {
    return { valid: false, source: source, reason: "invalid-history" }
  }

  // Undo the past stack from newest to oldest to reach its root.  This both
  // validates each expected inserted slice and confirms the stack's order.
  var rootSource = source
  for (var pastIndex = past.length - 1; pastIndex >= 0; pastIndex--) {
    var undone = applyEditTransaction(rootSource, past[pastIndex], "undo")
    if (!undone.valid) {
      return {
        valid: false,
        source: source,
        side: "past",
        index: pastIndex,
        reason: undone.reason || "invalid-past"
      }
    }
    rootSource = undone.source
  }

  // Replay the past stack to prove that it reconstructs the current source.
  var replayedSource = rootSource
  for (var replayIndex = 0; replayIndex < past.length; replayIndex++) {
    var replayed = applyEditTransaction(replayedSource,
      past[replayIndex], "redo")
    if (!replayed.valid) {
      return {
        valid: false,
        source: source,
        side: "past",
        index: replayIndex,
        reason: replayed.reason || "invalid-past"
      }
    }
    replayedSource = replayed.source
  }
  if (replayedSource !== source) {
    return { valid: false, source: source, side: "past",
      index: -1, reason: "past-does-not-reconstruct-source" }
  }

  // `future` is ordered in redo order: future[0] is the next transaction
  // that Ctrl+Y/Redo would apply.  Check the whole chain, then undo it again
  // so the validation never changes the caller's current source.
  var futureSource = source
  for (var futureIndex = 0; futureIndex < future.length; futureIndex++) {
    var advanced = applyEditTransaction(futureSource,
      future[futureIndex], "redo")
    if (!advanced.valid) {
      return {
        valid: false,
        source: source,
        side: "future",
        index: futureIndex,
        reason: advanced.reason || "invalid-future"
      }
    }
    futureSource = advanced.source
  }
  var restoredSource = futureSource
  for (var restoreIndex = future.length - 1; restoreIndex >= 0;
       restoreIndex--) {
    var restored = applyEditTransaction(restoredSource,
      future[restoreIndex], "undo")
    if (!restored.valid) {
      return {
        valid: false,
        source: source,
        side: "future",
        index: restoreIndex,
        reason: restored.reason || "invalid-future"
      }
    }
    restoredSource = restored.source
  }
  if (restoredSource !== source) {
    return { valid: false, source: source, side: "future",
      index: -1, reason: "future-does-not-restore-source" }
  }

  return {
    valid: true,
    source: source,
    rootSource: rootSource,
    futureSource: futureSource,
    pastCount: past.length,
    futureCount: future.length
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    clampPosition: clampPosition,
    lineBounds: lineBounds,
    findTextMatches: findTextMatches,
    findText: findText,
    replaceAllText: replaceAllText,
    imageResizeMetadataAt: imageResizeMetadataAt,
    resizeMarkdownImage: resizeMarkdownImage,
    linePosition: linePosition,
    indentEdit: indentEdit,
    listPrefixAt: listPrefixAt,
    horizontalListBoundaryTarget: horizontalListBoundaryTarget,
    tableCellSourceSpans: tableCellSourceSpans,
    tableRegions: tableRegions,
    tableCellContext: tableCellContext,
    tableNavigationTarget: tableNavigationTarget,
    sanitizeTableInsertion: sanitizeTableInsertion,
    protectedTableSelectionEdit: protectedTableSelectionEdit,
    tableDelete: tableDelete,
    protectLiveTableEdit: protectLiveTableEdit,
    tableToolbarState: tableToolbarState,
    tableStructuralEdit: tableStructuralEdit,
    tableMaterializeCell: tableMaterializeCell,
    fencedCodeContext: fencedCodeContext,
    codeLexicalState: codeLexicalState,
    codeTagCompletion: codeTagCompletion,
    completeCodePair: completeCodePair,
    completeCodeFence: completeCodeFence,
    completeListMarker: completeListMarker,
    liveReturnSourcePosition: liveReturnSourcePosition,
    listReturn: listReturn,
    plainReturn: plainReturn,
    fenceHeaderReturn: fenceHeaderReturn,
    fenceBodyBackspace: fenceBodyBackspace,
    backspaceEmptyCodePair: backspaceEmptyCodePair,
    backspaceOrphanCodeFence: backspaceOrphanCodeFence,
    headingSpace: headingSpace,
    trackAutoCodeFenceEdit: trackAutoCodeFenceEdit,
    trackAutoCodePairEdit: trackAutoCodePairEdit,
    listBackspace: listBackspace,
    formattingPrefixBackspace: formattingPrefixBackspace,
    plainBackspace: plainBackspace,
    backspaceAutoCodePair: backspaceAutoCodePair,
    backspaceAutoCodeFence: backspaceAutoCodeFence,
    makeEditTransaction: makeEditTransaction,
    applyEditTransaction: applyEditTransaction,
    coalesceEditTransactions: coalesceEditTransactions,
    validateEditTransactionChain: validateEditTransactionChain
  }
}
