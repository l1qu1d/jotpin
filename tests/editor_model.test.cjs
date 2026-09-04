#!/usr/bin/env node

const assert = require("node:assert/strict")
const model = require("../EditorModel.js")

function pass(message) {
  process.stdout.write(`PASS: ${message}\n`)
}

function equal(actual, expected, message) {
  assert.deepEqual(actual, expected, message)
  pass(message)
}

equal(
  model.resizeMarkdownImage(
    "Before ![photo](photo.png) after", 7, 26, 420, 34),
  {
    changed: true,
    source: "Before ![photo](photo.png)<!-- jotpin:image width=420 --> after",
    cursor: 63,
    metadataStart: 26,
    metadataEnd: 57,
    width: 420
  },
  "image resize adds portable hidden width metadata and translates a later caret"
)
equal(
  model.resizeMarkdownImage(
    "![photo](photo.png)<!-- jotpin:image width=420 -->", 0, 19,
    275.6, 0),
  {
    changed: true,
    source: "![photo](photo.png)<!-- jotpin:image width=276 -->",
    cursor: 0,
    metadataStart: 19,
    metadataEnd: 50,
    width: 276
  },
  "image resize replaces existing metadata without moving a caret before it"
)
equal(
  model.imageResizeMetadataAt(
    "![photo](photo.png)<!-- jotpin:image width = 276 -->", 19),
  { start: 19, end: 52, width: 276 },
  "image resize recognizes its narrowly scoped metadata comment"
)
equal(
  model.resizeMarkdownImage("plain text", 0, 5, 300, 2),
  {
    changed: false,
    source: "plain text",
    cursor: 2,
    metadataStart: -1,
    metadataEnd: -1,
    width: 0
  },
  "image resize rejects a range that is not Markdown image source"
)

equal(
  model.findText("Alpha beta alpha", "alpha", 1, false, false),
  { found: true, start: 11, end: 16, wrapped: false, index: 2, count: 2 },
  "Find searches forward case-insensitively from the requested source position"
)
equal(
  model.findText("Alpha beta alpha", "Alpha", 16, false, true),
  { found: true, start: 0, end: 5, wrapped: true, index: 1, count: 1 },
  "Find wraps forward and honors case sensitivity"
)
equal(
  model.findText("one two one", "one", 8, true, true),
  { found: true, start: 0, end: 3, wrapped: false, index: 1, count: 2 },
  "Find searches backward before the current source position"
)
equal(
  model.findText("one two one", "one", 0, true, true),
  { found: true, start: 8, end: 11, wrapped: true, index: 2, count: 2 },
  "Find Previous wraps from the first source position to the final match"
)
equal(
  model.findText("one two one", "missing", 0, false, false),
  { found: false, start: -1, end: -1, wrapped: false, index: 0, count: 0 },
  "Find reports a missing literal without changing a selection"
)
equal(
  model.findText("alpha beta alpha final alpha", "alpha", 12, false, false),
  { found: true, start: 23, end: 28, wrapped: false, index: 3, count: 3 },
  "Find reports the current match number and total match count"
)
equal(
  model.findTextMatches("aaaa", "aa", true),
  [{ start: 0, end: 2 }, { start: 2, end: 4 }],
  "Find counts the same non-overlapping matches that navigation visits"
)
equal(
  model.replaceAllText("Cat cat scatter", "cat", "dog", false),
  { source: "dog dog sdogter", count: 3, cursor: 12 },
  "Replace All performs literal case-insensitive replacements"
)
equal(
  model.replaceAllText("Cat cat", "Cat", "dog", true),
  { source: "dog cat", count: 1, cursor: 3 },
  "Replace All honors case sensitivity"
)
equal(
  model.replaceAllText("unchanged", "", "x", false),
  { source: "unchanged", count: 0, cursor: 0 },
  "Replace All rejects an empty query"
)

const manyMatches = "x ".repeat(5000)
const replaceAllStarted = process.hrtime.bigint()
const manyReplacements = model.replaceAllText(
  manyMatches, "x", "replacement", true)
const replaceAllElapsedMs = Number(
  process.hrtime.bigint() - replaceAllStarted) / 1e6
equal(
  {
    count: manyReplacements.count,
    startsCorrectly: manyReplacements.source.startsWith("replacement "),
    endsCorrectly: manyReplacements.source.endsWith("replacement ")
  },
  { count: 5000, startsCorrectly: true, endsCorrectly: true },
  "Replace All handles thousands of matches in one pass"
)
assert.ok(replaceAllElapsedMs < 1000,
  `Replace All took ${replaceAllElapsedMs.toFixed(1)} ms`)
pass(`Replace All performance stays linear (${replaceAllElapsedMs.toFixed(1)} ms)`)
equal(
  model.linePosition("one\r\ntwo\r\nthree", 2),
  { valid: true, position: 5, line: 2, lineCount: 3, clamped: false },
  "Go to Line finds CRLF source rows without changing their bytes"
)
equal(
  model.linePosition("one\ntwo", 99),
  { valid: true, position: 4, line: 2, lineCount: 2, clamped: true },
  "Go to Line clamps a request beyond the final row"
)
equal(
  model.linePosition("one\ntwo", 0),
  { valid: false, position: -1, line: 0, lineCount: 2 },
  "Go to Line rejects non-positive rows"
)
equal(
  model.indentEdit("plain", 2, 2, 1, 4),
  { handled: true, changed: true, source: "pl  ain", cursor: 4,
    selectionStart: 4, selectionEnd: 4 },
  "Tab inserts spaces to the next four-column stop in ordinary text"
)
equal(
  model.indentEdit("- item", 6, 6, 1, 4),
  { handled: true, changed: true, source: "  - item", cursor: 8,
    selectionStart: 8, selectionEnd: 8 },
  "Tab indents a complete Markdown list row from anywhere in the item"
)
equal(
  model.indentEdit("10. item", 8, 8, 1, 4),
  { handled: true, changed: true, source: "    10. item", cursor: 12,
    selectionStart: 12, selectionEnd: 12 },
  "ordered-list indentation follows the marker content column"
)
equal(
  model.indentEdit("    - [ ] task", 10, 10, -1, 4),
  { handled: true, changed: true, source: "- [ ] task", cursor: 6,
    selectionStart: 6, selectionEnd: 6 },
  "Shift Tab outdents a nested task-list row"
)
equal(
  model.indentEdit("one\r\ntwo\r\nthree", 1, 9, 1, 4),
  { handled: true, changed: true,
    source: "    one\r\n    two\r\nthree", cursor: 17,
    selectionStart: 5, selectionEnd: 17 },
  "Tab indents every selected CRLF row without changing line endings"
)
equal(
  model.indentEdit("    one\n  two\nthree", 0, 14, -1, 4),
  { handled: true, changed: true, source: "one\ntwo\nthree", cursor: 8,
    selectionStart: 0, selectionEnd: 8 },
  "Shift Tab removes up to four leading spaces from selected rows"
)
equal(
  model.indentEdit("one\ntwo", 0, 4, 1, 4),
  { handled: true, changed: true, source: "    one\ntwo", cursor: 8,
    selectionStart: 0, selectionEnd: 8 },
  "a selection ending at the next row start does not indent that row"
)
equal(
  model.indentEdit("plain", 3, 3, -1, 4),
  { handled: true, changed: false, source: "plain", cursor: 3,
    selectionStart: 3, selectionEnd: 3 },
  "Shift Tab on an unindented row remains an editor no-op"
)
equal(
  model.indentEdit("  \t- item", 9, 9, -1, 4),
  { handled: true, changed: true, source: "- item", cursor: 6,
    selectionStart: 6, selectionEnd: 6 },
  "Shift Tab removes a mixed space-tab indentation level"
)
equal(
  model.indentEdit("\tone\n  two", 0, 10, -1, 4),
  { handled: true, changed: true, source: "one\ntwo", cursor: 7,
    selectionStart: 0, selectionEnd: 7 },
  "Shift Tab normalizes tabs and spaces across a selected block"
)
equal(
  model.indentEdit("\none", 0, 1, 1, 4),
  { handled: true, changed: true, source: "    \none", cursor: 5,
    selectionStart: 0, selectionEnd: 5 },
  "Tab indents a selected leading blank row"
)
equal(
  model.indentEdit("one\n\nthree", 0, 5, 1, 4),
  { handled: true, changed: true, source: "    one\n    \nthree", cursor: 13,
    selectionStart: 0, selectionEnd: 13 },
  "Tab preserves and indents a selected middle blank row"
)
equal(
  model.indentEdit("one\n", 4, 4, 1, 4),
  { handled: true, changed: true, source: "one\n    ", cursor: 8,
    selectionStart: 8, selectionEnd: 8 },
  "Tab creates indentation on a trailing blank source row"
)
equal(
  model.indentEdit("- one\n- [ ] two", 0, 15, 1, 4),
  { handled: true, changed: true,
    source: "    - one\n    - [ ] two", cursor: 23,
    selectionStart: 0, selectionEnd: 23 },
  "multiline list selections use one consistent four-space block indent"
)

const listSource = "test\n\n- hi\n- test"
equal(
  model.horizontalListBoundaryTarget(listSource, 8, -1, false, 8, 8),
  6,
  "Left from the first bullet letter reaches one visible marker boundary"
)
equal(
  model.horizontalListBoundaryTarget(listSource, 6, 1, false, 6, 6),
  8,
  "Right from the marker boundary reaches the first bullet letter"
)
equal(
  model.horizontalListBoundaryTarget(listSource, 5, 1, false, 5, 5),
  -1,
  "Right on a blank source line remains native navigation"
)
equal(
  model.horizontalListBoundaryTarget(listSource, 8, -1, true, 8, 8),
  -1,
  "Raw mode never applies live list-prefix navigation"
)
equal(
  model.horizontalListBoundaryTarget(listSource, 8, -1, false, 8, 9),
  -1,
  "Selections never collapse through a live list prefix"
)

let position = 8
for (const direction of [-1, -1, -1]) {
  const boundary = model.horizontalListBoundaryTarget(
    listSource, position, direction, false, position, position)
  position = boundary >= 0 ? boundary : position + direction
}
equal(position, 4, "Three Left presses traverse visible rows without a prefix stall")

for (const direction of [1, 1, 1]) {
  const boundary = model.horizontalListBoundaryTarget(
    listSource, position, direction, false, position, position)
  position = boundary >= 0 ? boundary : position + direction
}
equal(position, 8, "Three Right presses return to the first bullet letter")

equal(
  model.horizontalListBoundaryTarget("x\n1. item", 5, -1, false, 5, 5),
  2,
  "Ordered-list prefixes use the same single visual boundary"
)
equal(
  model.horizontalListBoundaryTarget("x\n- [ ] item", 8, -1, false, 8, 8),
  2,
  "Task-list prefixes collapse through the checkbox structure"
)

const taskSource = "- [ ] fsdaf"
let taskPosition = taskSource.length
for (let step = 0; step < "fsdaf".length; step++) {
  const boundary = model.horizontalListBoundaryTarget(
    taskSource, taskPosition, -1, false, taskPosition, taskPosition)
  taskPosition = boundary >= 0 ? boundary : taskPosition - 1
}
equal(
  taskPosition,
  taskSource.indexOf("fsdaf"),
  "Left visits every character boundary in checkbox bullet text"
)
equal(
  model.horizontalListBoundaryTarget(
    taskSource, taskPosition, -1, false, taskPosition, taskPosition),
  0,
  "Left skips only the hidden checkbox and bullet prefix"
)

taskPosition = 0
let taskBoundary = model.horizontalListBoundaryTarget(
  taskSource, taskPosition, 1, false, taskPosition, taskPosition)
taskPosition = taskBoundary >= 0 ? taskBoundary : taskPosition + 1
for (let step = 0; step < "fsdaf".length; step++) {
  taskBoundary = model.horizontalListBoundaryTarget(
    taskSource, taskPosition, 1, false, taskPosition, taskPosition)
  taskPosition = taskBoundary >= 0 ? taskBoundary : taskPosition + 1
}
equal(
  taskPosition,
  taskSource.length,
  "Right visits every character boundary in checkbox bullet text"
)

const tableSource =
  "| JotPin handles | Great for |\n" +
  "| --- | --- |\n" +
  "| Lists and tasks t | Todos and planning |\n" +
  "| Tables and links | Research and reference |"
const tableRegions = model.tableRegions(tableSource)
assert.equal(tableRegions.length, 1)
assert.equal(tableRegions[0].rows.length, 3)
assert.equal(tableRegions[0].columnCount, 2)
pass("Live table parsing identifies header and body cells without exposing the separator row")

const firstBodyCell = tableRegions[0].rows[1].spans[0]
const secondBodyCell = tableRegions[0].rows[1].spans[1]
equal(
  model.tableNavigationTarget(tableSource, firstBodyCell.end, 1,
    "horizontal", false, firstBodyCell.end, firstBodyCell.end),
  secondBodyCell.start,
  "Right from a cell end skips hidden padding and the table delimiter"
)
equal(
  model.tableNavigationTarget(tableSource, secondBodyCell.start, -1,
    "horizontal", false, secondBodyCell.start, secondBodyCell.start),
  firstBodyCell.end,
  "Left from a cell start reaches the previous editable cell boundary"
)
equal(
  model.tableNavigationTarget(tableSource, firstBodyCell.start + 3, 1,
    "horizontal", false, firstBodyCell.start + 3,
    firstBodyCell.start + 3),
  -1,
  "Left and Right remain native while the caret is inside table-cell text"
)
equal(
  model.tableNavigationTarget(tableSource, firstBodyCell.start, 1,
    "tab", false, firstBodyCell.start, firstBodyCell.start),
  secondBodyCell.start,
  "Tab moves to the next table cell without inserting indentation"
)
equal(
  model.tableNavigationTarget(tableSource, secondBodyCell.start, 1,
    "row", false, secondBodyCell.start, secondBodyCell.start),
  tableRegions[0].rows[2].spans[1].start,
  "Enter moves down the same table column without splitting the Markdown row"
)
equal(
  {
    home: model.tableNavigationTarget(tableSource, firstBodyCell.start + 5,
      -1, "home", false, firstBodyCell.start + 5,
      firstBodyCell.start + 5),
    end: model.tableNavigationTarget(tableSource, firstBodyCell.start + 5,
      1, "end", false, firstBodyCell.start + 5,
      firstBodyCell.start + 5)
  },
  {home: firstBodyCell.start, end: firstBodyCell.end},
  "Home and End stay within the current rendered table cell"
)

equal(
  model.tableDelete(tableSource, secondBodyCell.start,
    secondBodyCell.start, secondBodyCell.start, -1, false),
  {handled: true, changed: false, source: tableSource,
    cursor: secondBodyCell.start},
  "Backspace at a cell start cannot delete the preceding column delimiter"
)
equal(
  model.tableDelete(tableSource, firstBodyCell.end,
    firstBodyCell.end, firstBodyCell.end, 1, false),
  {handled: true, changed: false, source: tableSource,
    cursor: firstBodyCell.end},
  "Delete at a cell end cannot delete the following column delimiter"
)

const crossCellStart = firstBodyCell.end - 1
const crossCellEnd = secondBodyCell.start + 1
const crossCellDelete = model.tableDelete(tableSource, crossCellEnd,
  crossCellStart, crossCellEnd, -1, false)
assert.equal(crossCellDelete.handled, true)
assert.equal(crossCellDelete.changed, false)
assert.equal(crossCellDelete.source, tableSource)
assert.equal(model.tableRegions(crossCellDelete.source).length, 1)
pass("deleting a selection across cells is blocked so cell contents cannot merge")

const sameCellDelete = model.tableDelete(tableSource,
  firstBodyCell.start + 5, firstBodyCell.start,
  firstBodyCell.start + 5, -1, false)
assert.equal(sameCellDelete.handled, true)
assert.ok(sameCellDelete.source.includes("|  and tasks t |"))
assert.equal(model.tableRegions(sameCellDelete.source).length, 1)
pass("Backspace still edits text selected wholly inside one table cell")

const nativeCrossCellSource = tableSource.slice(0, crossCellStart) +
  tableSource.slice(crossCellEnd)
const protectedCrossCell = model.protectLiveTableEdit(
  tableSource, nativeCrossCellSource, crossCellEnd,
  crossCellStart, crossCellEnd, false)
assert.equal(protectedCrossCell.protected, true)
assert.equal(protectedCrossCell.source, tableSource)
pass("modified Backspace, Delete, or cut cannot remove across table cells")

const boundaryWordDelete = model.tableDelete(tableSource, secondBodyCell.start,
  firstBodyCell.end - 5, secondBodyCell.start, -1, false)
assert.equal(boundaryWordDelete.handled, true)
assert.equal(boundaryWordDelete.changed, false)
assert.equal(boundaryWordDelete.source, tableSource)
pass("Ctrl Backspace at a cell start cannot delete text from the prior cell")

const tableAndParagraphSelection = "Before\n" + tableSource + "\nAfter"
const selectedTableStart = tableAndParagraphSelection.indexOf("Before")
const selectedTableEnd = tableAndParagraphSelection.indexOf("After") + 1
const blockedSelectedTable = model.tableDelete(
  tableAndParagraphSelection, selectedTableEnd, selectedTableStart,
  selectedTableEnd, -1, false)
assert.equal(blockedSelectedTable.handled, true)
assert.equal(blockedSelectedTable.changed, false)
assert.equal(blockedSelectedTable.source, tableAndParagraphSelection)
pass("Backspace cannot remove a table through a selection that crosses its boundary")

const delimiterPosition = tableSource.indexOf(" | Todos") + 1
const deletedDelimiter = tableSource.slice(0, delimiterPosition) +
  tableSource.slice(delimiterPosition + 1)
equal(
  model.protectLiveTableEdit(tableSource, deletedDelimiter,
    delimiterPosition + 1, delimiterPosition + 1,
    delimiterPosition + 1, false),
  {protected: true, source: tableSource, cursor: secondBodyCell.start},
  "native cut or deletion cannot remove a structural table delimiter"
)

const literalPipePosition = firstBodyCell.start + 5
const literalPipeSource = tableSource.slice(0, literalPipePosition) + "|" +
  tableSource.slice(literalPipePosition)
const protectedPipe = model.protectLiveTableEdit(
  tableSource, literalPipeSource, literalPipePosition,
  literalPipePosition, literalPipePosition, false)
assert.equal(protectedPipe.protected, true)
assert.equal(protectedPipe.source.slice(
  literalPipePosition, literalPipePosition + 2), "\\|")
assert.equal(model.tableRegions(protectedPipe.source).length, 1)
pass("typing a literal pipe in Live mode escapes it instead of creating a column")

const pastedLineBreak = tableSource.slice(0, literalPipePosition) + "a\nb" +
  tableSource.slice(literalPipePosition)
const protectedLineBreak = model.protectLiveTableEdit(
  tableSource, pastedLineBreak, literalPipePosition,
  literalPipePosition, literalPipePosition, false)
assert.equal(protectedLineBreak.protected, true)
assert.equal(protectedLineBreak.source.slice(
  literalPipePosition, literalPipePosition + 3), "a b")
assert.equal(model.tableRegions(protectedLineBreak.source).length, 1)
pass("pasted line breaks remain inside one Markdown table row")

const spacedCellLine = "| word    | next |"
const spacedCellSpans = model.tableCellSourceSpans(spacedCellLine)
assert.equal(spacedCellSpans[0].text, "word   ")
assert.equal(spacedCellSpans[0].end - spacedCellSpans[0].start,
  "word   ".length)
assert.equal(spacedCellLine.charAt(spacedCellSpans[0].end), " ")
pass("table cells preserve user spaces while reserving one delimiter-padding space")

let repeatedSpaceSource = tableSource
let repeatedSpaceContext = model.tableCellContext(
  repeatedSpaceSource, repeatedSpaceSource.indexOf("Lists and tasks"), false)
let repeatedSpaceCursor = repeatedSpaceContext.span.end
for (let spaceIndex = 0; spaceIndex < 3; spaceIndex++) {
  const nativeSpaceSource = repeatedSpaceSource.slice(0, repeatedSpaceCursor) +
    " " + repeatedSpaceSource.slice(repeatedSpaceCursor)
  const protectedSpace = model.protectLiveTableEdit(
    repeatedSpaceSource, nativeSpaceSource, repeatedSpaceCursor,
    repeatedSpaceCursor, repeatedSpaceCursor, false)
  assert.equal(protectedSpace.protected, false)
  assert.equal(protectedSpace.tableCell, true)
  assert.equal(protectedSpace.source, nativeSpaceSource)
  repeatedSpaceSource = nativeSpaceSource
  repeatedSpaceCursor++
  repeatedSpaceContext = model.tableCellContext(
    repeatedSpaceSource, repeatedSpaceCursor, true)
  assert.equal(repeatedSpaceContext.columnIndex, 0)
  assert.equal(repeatedSpaceContext.span.end, repeatedSpaceCursor)
}
pass("three consecutive Space edits remain inside one Live table cell")

equal(
  model.tableCellSourceSpans(
    " Name |  | \\| | `a|b` | [go](https://a|b) ").map(
      span => span.text),
  ["Name", "", "\\|", "`a|b`", "[go](https://a|b)"],
  "table cell spans handle no outer pipes, empty cells, escapes, code, and links"
)
equal(
  model.tableDelete(tableSource, secondBodyCell.start,
    secondBodyCell.start, secondBodyCell.start, -1, true).handled,
  false,
  "Raw mode retains direct Markdown table syntax editing"
)

equal(
  model.tableToolbarState(tableSource, secondBodyCell.start, false),
  {
    active: true,
    tableStart: 0,
    tableEnd: tableSource.length,
    tableContentStart: tableRegions[0].rows[0].spans[0].start,
    rowIndex: 1,
    columnIndex: 1,
    rowCount: 3,
    columnCount: 2,
    canDeleteRow: true,
    canDeleteColumn: true,
    needsRepair: false
  },
  "the contextual toolbar follows the active rendered cell"
)
equal(
  model.tableToolbarState(tableSource, secondBodyCell.start, true),
  {active: false},
  "Raw mode does not show visual table controls"
)
equal(
  model.tableToolbarState(tableSource, 0, false),
  {active: false},
  "the contextual toolbar stays hidden at the table's opening delimiter"
)
equal(
  model.tableToolbarState(tableSource,
    tableRegions[0].rows[0].spans[0].start, false).active,
  true,
  "the contextual toolbar appears at the first editable table character"
)
equal(
  model.tableToolbarState(tableSource,
    tableRegions[0].rows[0].spans[0].start - 1, false).active,
  true,
  "the contextual toolbar remains visible in leading table-cell padding"
)
equal(
  model.tableToolbarState(tableSource,
    tableRegions[0].rows[0].spans[0].end + 1, false).active,
  true,
  "the contextual toolbar remains visible at trailing table-cell padding"
)
equal(
  model.tableToolbarState(tableSource, tableSource.length, false),
  {active: false},
  "the contextual toolbar stays hidden at the table's outer end boundary"
)
const surroundedTableSource = "Before\n\n" + tableSource + "\n\nAfter"
equal(
  model.tableToolbarState(surroundedTableSource,
    surroundedTableSource.indexOf(tableSource) - 1, false),
  {active: false},
  "the contextual toolbar stays hidden on the blank line before a table"
)
equal(
  model.tableToolbarState(surroundedTableSource,
    surroundedTableSource.indexOf("\n\nAfter") + 1, false),
  {active: false},
  "the contextual toolbar stays hidden on the blank line after a table"
)

let tableEdit = model.tableStructuralEdit(
  tableSource, secondBodyCell.start, "rowBefore", false)
assert.equal(tableEdit.handled, true)
assert.equal(tableEdit.changed, true)
assert.equal(tableEdit.source,
  "| JotPin handles | Great for |\n" +
  "| --- | --- |\n" +
  "|  |  |\n" +
  "| Lists and tasks t | Todos and planning |\n" +
  "| Tables and links | Research and reference |")
assert.equal(model.tableCellContext(
  tableEdit.source, tableEdit.cursor, false).rowIndex, 1)
pass("Add row above inserts a complete row and places the caret in it")

tableEdit = model.tableStructuralEdit(
  tableSource, secondBodyCell.start, "rowAfter", false)
assert.equal(tableEdit.source,
  "| JotPin handles | Great for |\n" +
  "| --- | --- |\n" +
  "| Lists and tasks t | Todos and planning |\n" +
  "|  |  |\n" +
  "| Tables and links | Research and reference |")
assert.equal(model.tableCellContext(
  tableEdit.source, tableEdit.cursor, false).rowIndex, 2)
pass("Add row below inserts relative to the active body row")

tableEdit = model.tableStructuralEdit(
  tableSource, secondBodyCell.start, "rowDelete", false)
assert.equal(tableEdit.source,
  "| JotPin handles | Great for |\n" +
  "| --- | --- |\n" +
  "| Tables and links | Research and reference |")
assert.equal(model.tableRegions(tableEdit.source)[0].rows.length, 2)
pass("Delete row removes only the active body row")

const headerSecondCell = tableRegions[0].rows[0].spans[1]
tableEdit = model.tableStructuralEdit(
  tableSource, headerSecondCell.start, "rowDelete", false)
equal(
  {handled: tableEdit.handled, changed: tableEdit.changed,
    source: tableEdit.source},
  {handled: true, changed: false, source: tableSource},
  "the header cannot be deleted as a data row"
)

tableEdit = model.tableStructuralEdit(
  tableSource, secondBodyCell.start, "columnBefore", false)
assert.equal(tableEdit.source,
  "| JotPin handles |  | Great for |\n" +
  "| --- | --- | --- |\n" +
  "| Lists and tasks t |  | Todos and planning |\n" +
  "| Tables and links |  | Research and reference |")
let editedContext = model.tableCellContext(
  tableEdit.source, tableEdit.cursor, false)
assert.equal(editedContext.columnIndex, 1)
assert.equal(editedContext.span.text, "")
pass("Add column left expands every table row and its separator")

tableEdit = model.tableStructuralEdit(
  tableSource, secondBodyCell.start, "columnAfter", false)
assert.equal(tableEdit.source,
  "| JotPin handles | Great for |  |\n" +
  "| --- | --- | --- |\n" +
  "| Lists and tasks t | Todos and planning |  |\n" +
  "| Tables and links | Research and reference |  |")
editedContext = model.tableCellContext(
  tableEdit.source, tableEdit.cursor, false)
assert.equal(editedContext.columnIndex, 2)
pass("Add column right expands the complete table")

tableEdit = model.tableStructuralEdit(
  tableSource, secondBodyCell.start, "columnDelete", false)
assert.equal(tableEdit.source,
  "| JotPin handles |\n" +
  "| --- |\n" +
  "| Lists and tasks t |\n" +
  "| Tables and links |")
assert.equal(model.tableRegions(tableEdit.source)[0].columnCount, 1)
pass("Delete column removes the active column while retaining a valid table")

const alignedTable =
  "Before\r\n\r\n" +
  "| Left | Center | Right |\r\n" +
  "| :--- | :---: | ---: |\r\n" +
  "| a | b | c |\r\n\r\nAfter"
const alignedCursor = alignedTable.indexOf("b | c")
tableEdit = model.tableStructuralEdit(
  alignedTable, alignedCursor, "columnDelete", false)
assert.ok(tableEdit.source.includes(
  "| Left | Right |\r\n| :--- | ---: |\r\n| a | c |"))
assert.ok(tableEdit.source.startsWith("Before\r\n\r\n"))
assert.ok(tableEdit.source.endsWith("\r\n\r\nAfter"))
pass("column edits preserve CRLF notes and the remaining alignments")

tableEdit = model.tableStructuralEdit(
  "Before\n\n" + tableSource + "\n\nAfter",
  "Before\n\n".length + secondBodyCell.start, "tableDelete", false)
equal(
  tableEdit.source,
  "Before\n\n\nAfter",
  "Delete table removes the complete structure without deleting nearby text"
)

equal(
  model.tableStructuralEdit(tableSource, secondBodyCell.start,
    "columnAfter", true).handled,
  false,
  "Raw mode leaves structural table changes to direct Markdown editing"
)

const malformedTable =
  "| JotPin handles | Great for |\n" +
  "| --- | --- |\n" +
  " Lists and tasks t Tod     |\n" +
  "| Tables and links | Research and reference |"
const malformedFirstCell = malformedTable.indexOf("Lists and tasks")
const malformedState = model.tableToolbarState(
  malformedTable, malformedFirstCell, false)
assert.equal(malformedState.active, true)
assert.equal(malformedState.needsRepair, true)
const materializedCell = model.tableMaterializeCell(
  malformedTable, malformedState.tableStart, 1, 1, false)
assert.equal(materializedCell.handled, true)
assert.equal(materializedCell.changed, true)
assert.ok(materializedCell.source.includes(
  "| Lists and tasks t Tod |  |"))
editedContext = model.tableCellContext(
  materializedCell.source, materializedCell.cursor, false)
assert.equal(editedContext.rowIndex, 1)
assert.equal(editedContext.columnIndex, 1)
assert.equal(editedContext.span.text, "")
pass("clicking a padded visual cell materializes a valid editable source cell")

tableEdit = model.tableStructuralEdit(
  malformedTable, malformedFirstCell, "tableRepair", false)
assert.equal(tableEdit.changed, true)
assert.ok(tableEdit.source.includes("| Lists and tasks t Tod |  |"))
assert.equal(model.tableToolbarState(
  tableEdit.source, tableEdit.cursor, false).needsRepair, false)
pass("Repair table normalizes every short row without discarding its content")

const overflowTable =
  "| JotPin handles | Great for |\n" +
  "| --- | --- |\n" +
  "| Lists and tasks | Todos and planning | stray | separators |\n" +
  "| Tables and links | Research and reference |"
const overflowCursor = overflowTable.indexOf("Todos and planning")
tableEdit = model.tableStructuralEdit(
  overflowTable, overflowCursor, "tableRepair", false)
assert.equal(model.tableRegions(tableEdit.source)[0].columnCount, 2)
assert.ok(tableEdit.source.includes(
  "| Lists and tasks | Todos and planning \\| stray \\| separators |"))
assert.equal(model.tableToolbarState(
  tableEdit.source, tableEdit.cursor, false).needsRepair, false)
pass("Repair uses the header width and folds overflow into the final cell")

const overflowActions = [
  ["tableRepair", 2], ["rowBefore", 2], ["rowAfter", 2],
  ["rowDelete", 2], ["columnBefore", 3], ["columnAfter", 3],
  ["columnDelete", 1]
]
for (const [overflowAction, expectedColumns] of overflowActions) {
  const overflowEdit = model.tableStructuralEdit(
    overflowTable, overflowCursor, overflowAction, false)
  assert.equal(overflowEdit.handled, true)
  assert.equal(model.tableRegions(overflowEdit.source)[0].columnCount,
    expectedColumns, overflowAction + " obeys the header width")
  const structuralLines = overflowEdit.source.split("\n")
  for (const structuralLine of structuralLines) {
    assert.equal(model.tableCellSourceSpans(structuralLine).length,
      expectedColumns, overflowAction + " leaves every row rectangular")
  }
}
pass("every table helper action normalizes overflow before changing structure")



equal(
  model.completeCodeFence("```", "``", 3),
  { changed: true, source: "```\n\n```\n", cursor: 3,
    closeStart: 5, closeText: "```\n" },
  "typing a line-start triple backtick adds a body row, closer, and escape line"
)
equal(
  model.completeCodeFence("  ```", "  ``", 5),
  { changed: true, source: "  ```\n\n  ```\n", cursor: 5,
    closeStart: 7, closeText: "  ```\n" },
  "triple backtick completion preserves indentation and adds body and escape rows"
)
equal(
  model.completeCodeFence("```\n", "``\n", 3),
  { changed: true, source: "```\n\n```\n", cursor: 3,
    closeStart: 5, closeText: "```" },
  "fence completion does not add a duplicate existing line ending"
)
equal(
  model.completeCodeFence("text ```", "text ``", 8),
  { changed: false, source: "text ```", cursor: 8 },
  "inline triple backticks are not treated as a fenced block opener"
)
equal(
  model.completeCodeFence("```\ncode\n```", "```\ncode\n``", 12),
  { changed: false, source: "```\ncode\n```", cursor: 12 },
  "typing a closing fence does not add a second closing fence"
)

const pairPrevious = "```\n\n```"
const pairCurrent = "```\n(\n```"
const pairCursor = pairCurrent.indexOf("(") + 1
equal(
  model.completeCodePair(pairCurrent, pairPrevious, pairCursor, []),
  { changed: true, action: "insert", source: "```\n()\n```",
    cursor: pairCursor, closeStart: pairCursor, closeText: ")",
    openText: "(" },
  "typing an opening bracket inside a fenced block adds its closer"
)

const tagPrevious = "```html\n<div\n```"
const tagCurrent = "```html\n<div>\n```"
const tagCursor = tagCurrent.indexOf(">") + 1
equal(
  model.completeCodePair(tagCurrent, tagPrevious, tagCursor, []),
  { changed: true, action: "insert", source: "```html\n<div></div>\n```",
    cursor: tagCursor, closeStart: tagCursor, closeText: "</div>",
    openText: "<div>" },
  "typing an HTML opening tag adds its matching closing tag"
)

const skipPrevious = "```\n()\n```"
const skipCurrent = "```\n())\n```"
const skipCursor = skipCurrent.indexOf(")") + 1
equal(
  model.completeCodePair(skipCurrent, skipPrevious, skipCursor,
    [{ closeStart: skipCursor - 1, closeText: ")", openText: "(" }]),
  { changed: true, action: "skip", pairIndex: 0,
    source: skipPrevious, cursor: skipCursor - 1 },
  "typing an existing generated closer moves over it without duplicating it"
)

const commentPrevious = "```dart\n// \n```"
const commentCurrent = "```dart\n// (\n```"
const commentCursor = commentCurrent.indexOf("(") + 1
equal(
  model.completeCodePair(commentCurrent, commentPrevious, commentCursor, []),
  { changed: false, source: commentCurrent, cursor: commentCursor },
  "brackets inside a fenced comment are not auto-closed"
)

const stringPrevious = "```dart\nprint(\"x\");\n```"
const stringCurrent = "```dart\nprint(\"x(\");\n```"
const stringCursor = stringCurrent.lastIndexOf("(") + 1
equal(
  model.completeCodePair(stringCurrent, stringPrevious, stringCursor, []),
  { changed: false, source: stringCurrent, cursor: stringCursor },
  "brackets inside a fenced string are not auto-closed"
)

equal(
  model.completeCodePair("```html\n<br>\n```", "```html\n<br\n```", 12, []),
  { changed: false, source: "```html\n<br>\n```", cursor: 12 },
  "void HTML tags do not receive a closing tag"
)

const largeOrdinarySource = `${"ordinary text\n".repeat(50000)}a`
const largeOrdinaryPrevious = largeOrdinarySource.slice(0, -1)
const ordinaryPairStarted = process.hrtime.bigint()
for (let index = 0; index < 200; index++) {
  const ordinaryPair = model.completeCodePair(
    largeOrdinarySource, largeOrdinaryPrevious,
    largeOrdinarySource.length, [])
  assert.equal(ordinaryPair.changed, false)
}
const ordinaryPairElapsedMs = Number(
  process.hrtime.bigint() - ordinaryPairStarted) / 1e6
assert.ok(ordinaryPairElapsedMs < 250,
  `Ordinary typing pair checks took ${ordinaryPairElapsedMs.toFixed(1)} ms`)
pass(`Ordinary typing skips fenced-code scans (${ordinaryPairElapsedMs.toFixed(1)} ms)`)

equal(
  model.completeListMarker("```dart\n-\n```", "```dart\n\n```", 9),
  { changed: false, source: "```dart\n-\n```", cursor: 9 },
  "Markdown list completion stays disabled inside a fenced code block"
)

const pairedSource = "```\n()\n```"
const pairedBackspace = model.plainBackspace(
  pairedSource, 5, 5, 5)
equal(
  model.backspaceAutoCodePair(
    pairedSource, 5, 5, 5, pairedBackspace.source, pairedBackspace.cursor,
    5, ")", "("),
  { handled: true, changed: true, keepPair: false,
    source: "```\n\n```", cursor: 4 },
  "backspace removes an untouched generated code pair together"
)

let autoFenceSource = "```\n```"
let autoFenceCursor = 3
let autoFenceCloseStart = 4
const finalAutoFenceBackspace = model.plainBackspace(
  autoFenceSource, autoFenceCursor, autoFenceCursor, autoFenceCursor)
equal(
  model.backspaceAutoCodeFence(
    autoFenceSource, autoFenceCursor, autoFenceCursor, autoFenceCursor,
    finalAutoFenceBackspace.source, finalAutoFenceBackspace.cursor,
    autoFenceCloseStart, "```"),
  { handled: true, changed: true, keepPair: false, source: "", cursor: 0 },
  "one Backspace deletes the generated opener and closer atomically"
)
equal(
  model.backspaceAutoCodeFence(
    "`\n```\n", 1, 1, 1,
    "\n```\n", 0, 2, "```\n"),
  { handled: true, changed: true, keepPair: false, source: "", cursor: 0 },
  "deleting an auto-paired opener also removes its generated escape line"
)
equal(
  model.backspaceAutoCodeFence(
    "```\n\n```\n", 3, 0, 3,
    "\n\n```\n", 0, 5, "```\n"),
  { handled: true, changed: true, keepPair: false, source: "", cursor: 0 },
  "deleting a selected generated opener removes its closer and escape line"
)
equal(
  model.backspaceAutoCodeFence(
    "```javascript\n\n```\n", 13, 0, 13,
    "\n\n```\n", 0, 15, "```\n"),
  { handled: true, changed: true, keepPair: false, source: "", cursor: 0 },
  "deleting a selected opener and language removes its generated pair"
)
equal(
  model.backspaceAutoCodeFence(
    "```javascript\n\n```\n", 3, 0, 3,
    "javascript\n\n```\n", 0, 15, "```\n"),
  { handled: true, changed: true, keepPair: false,
    source: "javascript\n\n", cursor: 0 },
  "deleting only a selected opener keeps its language as ordinary text"
)
equal(
  model.trackAutoCodeFenceEdit("```\n```", "```\n``x", 4, "```"),
  { valid: false, closeStart: -1 },
  "editing the generated closer ends its automatic pairing"
)
equal(
  model.trackAutoCodeFenceEdit("```\n```", "```bash\n```", 4, "```"),
  { valid: true, closeStart: 8 },
  "typing a language before the closer keeps the generated pair tracked"
)
equal(
  model.trackAutoCodeFenceEdit(
    "```bash\n\n```", "```bash\ncode\n```", 9, "```"),
  { valid: true, closeStart: 13 },
  "typing code before the closer keeps the generated pair tracked"
)

let filledFenceSource = "```bash\ncode\n```"
let filledFenceCursor = 3
let filledFenceCloseStart = 13
const filledFinalBackspace = model.plainBackspace(
  filledFenceSource, filledFenceCursor,
  filledFenceCursor, filledFenceCursor)
equal(
  model.backspaceAutoCodeFence(
    filledFenceSource, filledFenceCursor,
    filledFenceCursor, filledFenceCursor,
    filledFinalBackspace.source, filledFinalBackspace.cursor,
    filledFenceCloseStart, "```"),
  { handled: true, changed: true, keepPair: false,
    source: "bash\ncode\n", cursor: 0 },
  "atomic generated-fence deletion preserves real language and code text"
)

equal(
  model.completeListMarker("text\n-", "text\n", 6),
  { changed: true, source: "text\n- ", cursor: 7 },
  "Typing a list marker inserts its Markdown separator and preserves the caret"
)
equal(
  model.completeListMarker("text -", "text ", 6),
  { changed: false, source: "text -", cursor: 6 },
  "Inline hyphens are never rewritten as list markers"
)
equal(
  model.completeListMarker("- ", "-", 2),
  { changed: false, source: "- ", cursor: 2 },
  "A space after an auto-completed empty bullet is preserved"
)
equal(
  model.completeListMarker("-  ", "- ", 3),
  { changed: false, source: "-  ", cursor: 3 },
  "Additional spaces on an empty bullet are preserved"
)

let typedSource = ""
let typedPrevious = ""
let typedCursor = 0
for (const character of ["-", " ", " ", " ", " "]) {
  typedPrevious = typedSource
  typedSource = typedSource.slice(0, typedCursor) + character +
    typedSource.slice(typedCursor)
  typedCursor++
  const completion = model.completeListMarker(
    typedSource, typedPrevious, typedCursor)
  if (completion.changed) {
    typedSource = completion.source
    typedCursor = completion.cursor
  }
}
equal(
  { source: typedSource, cursor: typedCursor },
  { source: "-     ", cursor: 6 },
  "Typing spaces after an auto-completed bullet preserves every source column"
)

equal(
  model.listReturn("text\n- item", 11, 11, 11),
  { handled: true, source: "text\n- item\n- ", cursor: 14 },
  "Enter after a bullet creates the next empty bullet"
)
const wrappedListFirst =
  "- JotPin autosaves after a short pause; use `Ctrl+S` to save immediately."
const wrappedListNext =
  "- Use Side, Center, or Full Screen to match the way you are working."
equal(
  model.listReturn(wrappedListFirst + "\n" + wrappedListNext,
    wrappedListFirst.length, wrappedListFirst.length, wrappedListFirst.length),
  {
    handled: true,
    source: wrappedListFirst + "\n- \n" + wrappedListNext,
    cursor: wrappedListFirst.length + 3
  },
  "Enter at a wrapped bullet end inserts a bullet before an existing item"
)
equal(
  model.listReturn(wrappedListFirst + "\n\n\n" + wrappedListNext,
    wrappedListFirst.length + 1, wrappedListFirst.length + 1,
    wrappedListFirst.length + 1, true),
  {
    handled: true,
    source: wrappedListFirst + "\n- \n" + wrappedListNext,
    cursor: wrappedListFirst.length + 3
  },
  "Live Enter recovers a blank line without retaining the hidden gap"
)
equal(
  model.listReturn(wrappedListFirst + "\n\n\n\n" + wrappedListNext,
    wrappedListFirst.length, wrappedListFirst.length,
    wrappedListFirst.length, true),
  {
    handled: true,
    source: wrappedListFirst + "\n- \n" + wrappedListNext,
    cursor: wrappedListFirst.length + 3
  },
  "Live Enter at the item end consumes every stranded row before the next bullet"
)
equal(
  model.listReturn(wrappedListFirst + "\n\n" + wrappedListNext,
    wrappedListFirst.length + 1, wrappedListFirst.length + 1,
    wrappedListFirst.length + 1),
  {
    handled: false,
    source: wrappedListFirst + "\n\n" + wrappedListNext,
    cursor: wrappedListFirst.length + 1
  },
  "Raw Enter preserves a blank line between existing list items"
)
const strandedListSource = wrappedListFirst + "\n\n\n\n" + wrappedListNext
equal(
  model.liveReturnSourcePosition(strandedListSource,
    wrappedListFirst.length + 2, wrappedListFirst.length + 1,
    false, wrappedListFirst.length + 2, wrappedListFirst.length + 2),
  wrappedListFirst.length + 1,
  "Live Return uses the painted caret when Qt advances over a collapsed newline"
)
equal(
  model.liveReturnSourcePosition(strandedListSource,
    wrappedListFirst.length + 2, wrappedListFirst.length + 2,
    false, wrappedListFirst.length + 2, wrappedListFirst.length + 2),
  wrappedListFirst.length + 2,
  "Live Return preserves a synchronized source caret"
)
equal(
  model.liveReturnSourcePosition(strandedListSource,
    wrappedListFirst.length + 2, wrappedListFirst.length + 1,
    true, wrappedListFirst.length + 2, wrappedListFirst.length + 2),
  wrappedListFirst.length + 2,
  "Raw Return never substitutes the Preview caret"
)
equal(
  model.liveReturnSourcePosition(strandedListSource,
    wrappedListFirst.length + 3, wrappedListFirst.length + 1,
    false, wrappedListFirst.length + 3, wrappedListFirst.length + 3),
  wrappedListFirst.length + 3,
  "Live Return does not hide a larger cursor disagreement"
)
equal(
  model.listReturn("text\n- ", 7, 7, 7),
  { handled: true, source: "text\n", cursor: 5 },
  "Enter on an empty bullet exits the list without leaving a marker"
)
equal(
  model.listReturn("text\n- [ ] item", 15, 15, 15),
  { handled: true, source: "text\n- [ ] item\n- [ ] ", cursor: 22 },
  "Enter continues task lists with an unchecked task marker"
)
equal(
  model.listReturn("- [ ] item", 2, 2, 2),
  { handled: false, source: "- [ ] item", cursor: 2 },
  "Enter inside raw task syntax never duplicates or mangles the checkbox"
)
equal(
  model.listReturn("- item\r\nnext", 6, 6, 6),
  { handled: true, source: "- item\r\n- \r\nnext", cursor: 10 },
  "Enter preserves CRLF while continuing a list"
)
equal(
  model.listPrefixAt("- item\r\nnext", 6).content,
  "item",
  "CRLF list parsing excludes the carriage return from item content"
)
equal(
  model.listReturn("text\n9. item", 12, 12, 12),
  { handled: true, source: "text\n9. item\n10. ", cursor: 17 },
  "Enter increments ordered-list markers"
)
equal(
  model.plainReturn("test", 4, 4, 4),
  { handled: true, source: "test\n", cursor: 5 },
  "Enter creates a trailing source newline"
)
equal(
  model.plainReturn("test\n", 5, 5, 5),
  { handled: true, source: "test\n\n", cursor: 6 },
  "repeated Enter preserves an empty source line"
)
equal(
  model.plainReturn("one two", 3, 3, 7),
  { handled: true, source: "one\n", cursor: 4 },
  "Enter replaces a selection with one source newline"
)
equal(
  model.fenceHeaderReturn("```javascript\n\n```\n", 13, 13, 13),
  { handled: true, source: "```javascript\n\n```\n", cursor: 14 },
  "Enter on a projected fence language moves into its existing code row"
)
equal(
  model.fenceHeaderReturn("```python\r\n\r\n```\r\n", 9, 9, 9),
  { handled: true, source: "```python\r\n\r\n```\r\n", cursor: 11 },
  "fence-language Enter moves over one existing CRLF source break"
)
equal(
  model.fenceHeaderReturn("```text\ncode\n```", 12, 12, 12),
  { handled: false, source: "```text\ncode\n```", cursor: 12 },
  "Enter inside fenced code remains an ordinary source edit"
)
equal(
  model.fenceBodyBackspace(
    "```js\n\n```\n", 6, 6, 6, 7, "```\n"),
  { handled: true, source: "```js\n\n```\n", cursor: 5 },
  "Backspace crosses from an empty generated body to its language header"
)
equal(
  model.fenceBodyBackspace(
    "```js\ncode\n```\n", 6, 6, 6, 11, "```\n"),
  { handled: false, source: "```js\ncode\n```\n", cursor: 6 },
  "fence-body Backspace never collapses a selection"
)
equal(
  model.backspaceEmptyCodePair(
    "```js\nfunction hello() {\n}\n```\n", 24, 24, 24),
  { handled: true, changed: true,
    source: "```js\nfunction hello() \n\n```\n", cursor: 23 },
  "Backspace reconstructs an empty generated brace pair after tracking is lost"
)
equal(
  model.backspaceEmptyCodePair(
    "```js\nfunction hello() {\n  work()\n}\n```\n", 24, 24, 24),
  { handled: false, changed: false,
    source: "```js\nfunction hello() {\n  work()\n}\n```\n", cursor: 24 },
  "Backspace preserves a populated code pair when tracking is absent"
)
equal(
  model.backspaceEmptyCodePair("ordinary {\n}\n", 10, 10, 10),
  { handled: false, changed: false,
    source: "ordinary {\n}\n", cursor: 10 },
  "untracked pair reconstruction is restricted to fenced code"
)
equal(
  model.backspaceOrphanCodeFence("\n\n```\n", 0, 0, 0),
  { handled: true, changed: true, source: "", cursor: 0 },
  "Backspace removes the exact orphaned generated closer after tracking is lost"
)
equal(
  model.backspaceOrphanCodeFence("before\n\n```\n", 6, 6, 6),
  { handled: true, changed: true, source: "before", cursor: 6 },
  "orphaned generated-fence cleanup preserves source before the caret"
)
equal(
  model.backspaceOrphanCodeFence("```\n\n```\n", 0, 0, 0),
  { handled: false, changed: false,
    source: "```\n\n```\n", cursor: 0 },
  "Backspace never mistakes a complete empty fence for an orphaned closer"
)
equal(
  model.backspaceOrphanCodeFence("\n\n```\ncode", 0, 0, 0),
  { handled: false, changed: false,
    source: "\n\n```\ncode", cursor: 0 },
  "Backspace preserves a trailing fence row when content follows it"
)

let heldFenceSource = "```js\n\n```\n"
let heldFenceCursor = 6
let heldFenceCloseStart = 7
const heldFenceBoundary = model.fenceBodyBackspace(
  heldFenceSource, heldFenceCursor, heldFenceCursor, heldFenceCursor,
  heldFenceCloseStart, "```\n")
equal(
  heldFenceBoundary,
  { handled: true, source: heldFenceSource, cursor: 5 },
  "held Backspace first crosses the empty code-row boundary"
)
heldFenceCursor = heldFenceBoundary.cursor
for (let heldFenceStep = 0; heldFenceStep < 5; heldFenceStep++) {
  const ordinaryDelete = model.plainBackspace(
    heldFenceSource, heldFenceCursor, heldFenceCursor, heldFenceCursor)
  const pairedDelete = model.backspaceAutoCodeFence(
    heldFenceSource, heldFenceCursor, heldFenceCursor, heldFenceCursor,
    ordinaryDelete.source, ordinaryDelete.cursor,
    heldFenceCloseStart, "```\n")
  const nextDelete = pairedDelete.handled ? pairedDelete : ordinaryDelete
  const trackedDelete = model.trackAutoCodeFenceEdit(
    heldFenceSource, nextDelete.source, heldFenceCloseStart, "```\n")
  heldFenceSource = nextDelete.source
  heldFenceCursor = nextDelete.cursor
  if (pairedDelete.handled && !pairedDelete.keepPair) break
  equal(
    trackedDelete.valid,
    true,
    "held Backspace retains the generated closer at step " + heldFenceStep
  )
  heldFenceCloseStart = trackedDelete.closeStart
}
equal(
  { source: heldFenceSource, cursor: heldFenceCursor },
  { source: "", cursor: 0 },
  "held Backspace removes the language and complete generated fence"
)

equal(
  model.headingSpace("####Watching movies", 4, 4, 4),
  { handled: true, source: "#### Watching movies", cursor: 5 },
  "Space between an ATX marker and its text creates the Markdown separator"
)
equal(
  model.headingSpace("```text\n#Watching\n```", 9, 9, 9),
  { handled: false, source: "```text\n#Watching\n```", cursor: 9 },
  "heading Space completion stays disabled inside fenced code"
)
equal(
  model.listBackspace("text\n- ", 7, 7, 7),
  { handled: false, source: "text\n- ", cursor: 7 },
  "Backspace leaves a generated bullet while its helper space is removed natively"
)
equal(
  model.listBackspace("text\n- ", 7, 7, 7, true),
  { handled: true, source: "text", cursor: 4 },
  "Preview Backspace removes an empty bullet row without hidden syntax stops"
)
equal(
  model.listBackspace("- test\n- \n- next", 9, 9, 9, true),
  { handled: true, source: "- test\n- next", cursor: 6 },
  "Preview Backspace removes only the empty bullet before another item"
)
equal(
  model.listBackspace("text\n-   ", 9, 9, 9),
  { handled: false, source: "text\n-   ", cursor: 9 },
  "Backspace preserves a bullet while separator spaces remain"
)
let backspaceSource = "text\n-   "
let backspaceCursor = backspaceSource.length
for (const expectedSource of ["text\n-  ", "text\n- ", "text\n-"]) {
  equal(
    model.listBackspace(backspaceSource, backspaceCursor,
      backspaceCursor, backspaceCursor),
    { handled: false, source: backspaceSource, cursor: backspaceCursor },
    "Repeated Backspace leaves the bullet while spaces remain: " +
      JSON.stringify(backspaceSource)
  )
  backspaceSource = backspaceSource.slice(0, backspaceCursor - 1) +
    backspaceSource.slice(backspaceCursor)
  backspaceCursor--
  equal(backspaceSource, expectedSource,
    "Native Backspace removes exactly one separator space")
}
equal(
  model.listBackspace(backspaceSource, backspaceCursor,
    backspaceCursor, backspaceCursor),
  { handled: true, source: "text\n", cursor: 5 },
  "Backspace removes the bullet only when it reaches the marker character"
)
equal(
  model.listBackspace("text\n- [ ] ", 11, 11, 11),
  { handled: false, source: "text\n- [ ] ", cursor: 11 },
  "Backspace removes empty task syntax one source character at a time"
)
equal(
  model.listBackspace("text\n- item", 10, 10, 10),
  { handled: false, source: "text\n- item", cursor: 10 },
  "Backspace never removes a populated list item"
)
let heldListSource = "- test\n- testas"
let heldListCursor = heldListSource.length
for (let heldListStep = 0; heldListStep < 8; heldListStep++) {
  let heldListEdit = model.listBackspace(
    heldListSource, heldListCursor, heldListCursor, heldListCursor, true)
  if (!heldListEdit.handled) {
    heldListEdit = model.plainBackspace(
      heldListSource, heldListCursor, heldListCursor, heldListCursor)
  }
  heldListSource = heldListEdit.source
  heldListCursor = heldListEdit.cursor
}
equal(
  { source: heldListSource, cursor: heldListCursor },
  { source: "- tes", cursor: 5 },
  "held Preview Backspace crosses one semantic bullet boundary without phantom stops"
)

equal(
  model.plainBackspace("text\ncode", 5, 5, 5),
  { handled: true, source: "textcode", cursor: 4 },
  "ordinary Backspace removes a newline at a code-block boundary"
)
equal(
  model.plainBackspace("text", 4, 1, 3),
  { handled: true, source: "tt", cursor: 1 },
  "Backspace removes a selected source range"
)
equal(
  model.plainBackspace("text", 0, 0, 0),
  { handled: false, source: "text", cursor: 0 },
  "Backspace at the start of the document remains a no-op"
)

const historyInsert = model.makeEditTransaction(
  "hello", "hello!", 5, 6, 5, 5, 6, 6, 100)
equal(
  historyInsert,
  {
    start: 5,
    removed: "",
    inserted: "!",
    beforeCursor: 5,
    afterCursor: 6,
    beforeSelectionStart: 5,
    beforeSelectionEnd: 5,
    afterSelectionStart: 6,
    afterSelectionEnd: 6,
    kind: "insert",
    coalescible: true,
    timestamp: 100
  },
  "Edit transactions capture a minimal insertion and normalized state"
)
equal(
  model.makeEditTransaction(
    "abc", "aXYc", { cursor: 2, selectionStart: 2, selectionEnd: 1 },
    { cursor: 3, selectionStart: 3, selectionEnd: 3 }, 200),
  {
    start: 1,
    removed: "b",
    inserted: "XY",
    beforeCursor: 2,
    afterCursor: 3,
    beforeSelectionStart: 1,
    beforeSelectionEnd: 2,
    afterSelectionStart: 3,
    afterSelectionEnd: 3,
    kind: "replace",
    coalescible: false,
    timestamp: 200
  },
  "Edit transactions accept state objects and normalize reversed selections"
)

const historyReplacement = model.makeEditTransaction(
  "one two", "one cat", 7, 7, 4, 7, 4, 7, 300)
equal(
  historyReplacement,
  {
    start: 4,
    removed: "two",
    inserted: "cat",
    beforeCursor: 7,
    afterCursor: 7,
    beforeSelectionStart: 4,
    beforeSelectionEnd: 7,
    afterSelectionStart: 4,
    afterSelectionEnd: 7,
    kind: "replace",
    coalescible: false,
    timestamp: 300
  },
  "Edit transactions preserve selected-range replacement metadata"
)

equal(
  model.applyEditTransaction("hello!", historyInsert, "undo"),
  {
    valid: true,
    changed: true,
    direction: "undo",
    source: "hello",
    cursor: 5,
    selectionStart: 5,
    selectionEnd: 5
  },
  "Undo applies the transaction only to its inserted source slice"
)
equal(
  model.applyEditTransaction("hello", historyInsert, "redo"),
  {
    valid: true,
    changed: true,
    direction: "redo",
    source: "hello!",
    cursor: 6,
    selectionStart: 6,
    selectionEnd: 6
  },
  "Redo applies the transaction only to its removed source slice"
)
equal(
  model.applyEditTransaction("hello?", historyInsert, "undo"),
  {
    valid: false,
    changed: false,
    direction: "undo",
    source: "hello?",
    cursor: 0,
    selectionStart: 0,
    selectionEnd: 0,
    reason: "source-mismatch"
  },
  "Undo refuses a transaction when the current source slice is stale"
)
equal(
  model.applyEditTransaction("hello", historyInsert, "redo"),
  {
    valid: true,
    changed: true,
    direction: "redo",
    source: "hello!",
    cursor: 6,
    selectionStart: 6,
    selectionEnd: 6
  },
  "A valid redo remains repeatable without mutating the transaction"
)

const typedA = model.makeEditTransaction(
  "", "a", 0, 1, 0, 0, 1, 1, 1000)
const typedB = model.makeEditTransaction(
  "a", "ab", 1, 2, 1, 1, 2, 2, 1050)
equal(
  model.coalesceEditTransactions(typedA, typedB, 250),
  {
    start: 0,
    removed: "",
    inserted: "ab",
    beforeCursor: 0,
    afterCursor: 2,
    beforeSelectionStart: 0,
    beforeSelectionEnd: 0,
    afterSelectionStart: 2,
    afterSelectionEnd: 2,
    kind: "insert",
    coalescible: true,
    timestamp: 1050
  },
  "Adjacent ordinary typing transactions coalesce within the time window"
)
equal(
  model.coalesceEditTransactions(typedA, typedB, 25),
  null,
  "Typing transactions outside the time window remain separate"
)

const backspaceA = model.makeEditTransaction(
  "abc", "ab", 3, 2, 3, 3, 2, 2, 1100)
const backspaceB = model.makeEditTransaction(
  "ab", "a", 2, 1, 2, 2, 1, 1, 1150)
const backspaceMerged = model.coalesceEditTransactions(
  backspaceA, backspaceB, 250)
equal(
  backspaceMerged,
  {
    start: 1,
    removed: "bc",
    inserted: "",
    beforeCursor: 3,
    afterCursor: 1,
    beforeSelectionStart: 3,
    beforeSelectionEnd: 3,
    afterSelectionStart: 1,
    afterSelectionEnd: 1,
    kind: "backspace",
    coalescible: true,
    timestamp: 1150
  },
  "Adjacent backward deletions coalesce in source order"
)
equal(
  model.applyEditTransaction("a", backspaceMerged, "undo").source,
  "abc",
  "Undo restores a coalesced Backspace transaction as one edit"
)
equal(
  model.applyEditTransaction("abc", backspaceMerged, "redo").source,
  "a",
  "Redo applies a coalesced Backspace transaction as one edit"
)

const deleteA = model.makeEditTransaction(
  "abcd", "abd", 2, 2, 2, 2, 2, 2, 1200)
const deleteB = model.makeEditTransaction(
  "abd", "ab", 2, 2, 2, 2, 2, 2, 1250)
equal(
  model.coalesceEditTransactions(deleteA, deleteB, 250),
  {
    start: 2,
    removed: "cd",
    inserted: "",
    beforeCursor: 2,
    afterCursor: 2,
    beforeSelectionStart: 2,
    beforeSelectionEnd: 2,
    afterSelectionStart: 2,
    afterSelectionEnd: 2,
    kind: "delete",
    coalescible: true,
    timestamp: 1250
  },
  "Adjacent forward deletions coalesce at one source offset"
)
equal(
  model.coalesceEditTransactions(
    model.makeEditTransaction("a", "ab", 1, 2, 1, 1, 2, 2, 1300),
    model.makeEditTransaction("ab", "aXb", 1, 2, 1, 1, 2, 2, 1350),
    250),
  null,
  "Non-adjacent or replacement edits never coalesce"
)

const chainFirst = model.makeEditTransaction(
  "", "a", 0, 1, 0, 0, 1, 1, 2000)
const chainSecond = model.makeEditTransaction(
  "a", "ab", 1, 2, 1, 1, 2, 2, 2050)
const chainFuture = model.makeEditTransaction(
  "ab", "abc", 2, 3, 2, 2, 3, 3, 2100)
equal(
  model.validateEditTransactionChain("ab", [chainFirst, chainSecond],
    [chainFuture]),
  {
    valid: true,
    source: "ab",
    rootSource: "",
    futureSource: "abc",
    pastCount: 2,
    futureCount: 1
  },
  "History validation checks past order and future redo order"
)
equal(
  model.validateEditTransactionChain("ac", [chainFirst, chainSecond], []),
  {
    valid: false,
    source: "ac",
    side: "past",
    index: 1,
    reason: "source-mismatch"
  },
  "History validation rejects a past chain that cannot reach the source"
)
equal(
  model.validateEditTransactionChain("ab", [chainFirst, chainSecond], [
    model.makeEditTransaction("ac", "ax", 2, 2, 2, 2, 2, 2, 2150)
  ]),
  {
    valid: false,
    source: "ab",
    side: "future",
    index: 0,
    reason: "source-mismatch"
  },
  "History validation rejects a future transaction with the wrong source"
)

process.stdout.write("PASS: isolated editor model regressions passed\n")
