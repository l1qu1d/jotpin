import {fromMarkdown} from "mdast-util-from-markdown"
import {gfmFromMarkdown} from "mdast-util-gfm"
import {toHast} from "mdast-util-to-hast"
import {defaultSchema, sanitize} from "hast-util-sanitize"
import {toHtml} from "hast-util-to-html"
import {gfm} from "micromark-extension-gfm"

function compactPosition(position) {
  if (!position || !position.start || !position.end) return null
  return {
    start: {
      line: position.start.line,
      column: position.start.column,
      offset: position.start.offset
    },
    end: {
      line: position.end.line,
      column: position.end.column,
      offset: position.end.offset
    }
  }
}

function compactNode(node) {
  const result = {
    type: String(node.type || ""),
    position: compactPosition(node.position)
  }
  if (typeof node.value === "string") result.value = node.value
  if (typeof node.depth === "number") result.depth = node.depth
  if (typeof node.lang === "string" || node.lang === null)
    result.lang = node.lang
  if (typeof node.meta === "string" || node.meta === null)
    result.meta = node.meta
  if (typeof node.url === "string") result.url = node.url
  if (typeof node.title === "string" || node.title === null)
    result.title = node.title
  if (typeof node.alt === "string") result.alt = node.alt
  if (typeof node.checked === "boolean" || node.checked === null)
    result.checked = node.checked
  if (typeof node.ordered === "boolean") result.ordered = node.ordered
  if (typeof node.start === "number" || node.start === null)
    result.start = node.start
  if (typeof node.spread === "boolean") result.spread = node.spread
  if (Array.isArray(node.align)) result.align = node.align.slice()
  if (Array.isArray(node.children))
    result.children = node.children.map(compactNode)
  return result
}

function lineStartsForSource(source) {
  const starts = [0]
  for (let index = 0; index < source.length; index++) {
    if (source.charAt(index) === "\n") starts.push(index + 1)
  }
  return starts
}

function sourcePoint(offsetValue, lineStarts) {
  const offset = Math.max(0, Number(offsetValue) || 0)
  let low = 0
  let high = lineStarts.length - 1
  while (low < high) {
    const middle = Math.ceil((low + high) / 2)
    if (lineStarts[middle] <= offset) low = middle
    else high = middle - 1
  }
  return {line: low + 1, column: offset - lineStarts[low] + 1, offset}
}

function blankRowsForGap(source, startValue, endValue, mode) {
  const start = Math.max(0, Number(startValue) || 0)
  const end = Math.max(start, Math.min(source.length,
    Number(endValue) || 0))
  let cursor = start
  if (mode === "leading" && source.indexOf("\n", cursor) >= end) return []
  if (mode !== "leading") {
    const firstNewline = source.indexOf("\n", cursor)
    if (firstNewline < 0 || firstNewline >= end) return []
    cursor = firstNewline + 1
  }
  const rows = []
  while (cursor < end) {
    const newline = source.indexOf("\n", cursor)
    if (newline < 0 || newline >= end) {
      rows.push({start: cursor, end})
      cursor = end
    } else {
      rows.push({start: cursor, end: newline + 1})
      cursor = newline + 1
    }
  }
  if (mode === "trailing" && end > start &&
      source.charAt(end - 1) === "\n") rows.push({start: end, end})
  return rows
}

function blankNode(row, lineStarts) {
  return {
    type: "blank",
    value: "\u200b",
    position: {
      start: sourcePoint(row.start, lineStarts),
      end: sourcePoint(row.end, lineStarts)
    }
  }
}

function compactTreeWithBlankRows(tree, source) {
  const compact = compactNode(tree)
  const children = Array.isArray(tree.children) ? tree.children : []
  const lineStarts = lineStartsForSource(source)
  const result = []
  let previousEnd = 0
  let positionedChildren = 0
  for (const child of children) {
    if (!child.position || !child.position.start || !child.position.end) {
      result.push(compactNode(child))
      continue
    }
    const start = Number(child.position.start.offset)
    const mode = positionedChildren === 0 ? "leading" : "between"
    for (const row of blankRowsForGap(source, previousEnd, start, mode))
      result.push(blankNode(row, lineStarts))
    if (child.type === "definition") {
      const definitionRows = blankRowsForGap(source, start,
        Number(child.position.end.offset), "leading")
      if (definitionRows.length > 0) {
        for (const row of definitionRows) result.push(blankNode(row, lineStarts))
      } else {
        result.push(blankNode({start,
          end: Number(child.position.end.offset)}, lineStarts))
      }
    } else result.push(compactNode(child))
    previousEnd = Number(child.position.end.offset)
    positionedChildren++
  }
  for (const row of blankRowsForGap(
      source, previousEnd, source.length, "trailing"))
    result.push(blankNode(row, lineStarts))
  compact.children = result
  return compact
}

function textContent(node) {
  if (!node) return ""
  if (node.type === "text") return String(node.value || "")
  const children = Array.isArray(node.children) ? node.children : []
  return children.map(textContent).join("")
}

function escapeHtml(value) {
  return String(value || "").split("\n").map(line => {
    const trailing = /[ \t]+$/.exec(line)
    const body = trailing ? line.slice(0, -trailing[0].length) : line
    const escapedBody = body.replace(/&/g, "&amp;")
      .replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/ {2,}/g, spaces => "&nbsp;".repeat(spaces.length))
      .replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;")
    const escapedTrailing = trailing ? trailing[0].replace(/ /g, "&nbsp;")
      .replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;") : ""
    return escapedBody + escapedTrailing
  }).join("<br/>")
}

function blankElement(row) {
  return {
    type: "element",
    tagName: "p",
    properties: {className: ["jotpin-blank-row"]},
    children: [{type: "text", value: "\u200b"}],
    position: {
      start: {offset: row.start},
      end: {offset: row.end}
    }
  }
}

function injectBlankRows(tree, source) {
  const children = Array.isArray(tree.children) ? tree.children : []
  const result = []
  let previousEnd = 0
  let positionedChildren = 0
  for (const child of children) {
    if (!child.position || !child.position.start || !child.position.end) {
      result.push(child)
      continue
    }
    const start = Number(child.position.start.offset)
    const mode = positionedChildren === 0 ? "leading" : "between"
    for (const row of blankRowsForGap(source, previousEnd, start, mode))
      result.push(blankElement(row))
    result.push(child)
    previousEnd = Number(child.position.end.offset)
    positionedChildren++
  }
  for (const row of blankRowsForGap(
      source, previousEnd, source.length, "trailing"))
    result.push(blankElement(row))
  tree.children = result
  return tree
}

function preserveSourceLineBreaks(node, insideParagraph) {
  if (!node || !Array.isArray(node.children)) return
  const preservesBreaks = Boolean(insideParagraph) ||
    node.type === "element" && node.tagName === "p"
  const expanded = []
  for (const child of node.children) {
    if (child && child.type === "text" &&
        preservesBreaks && String(child.value || "").indexOf("\n") >= 0) {
      const parts = String(child.value || "").split("\n")
      for (let index = 0; index < parts.length; index++) {
        if (index > 0 && !(parts[index] === "" &&
            expanded.length > 0 && expanded[expanded.length - 1] &&
            expanded[expanded.length - 1].type === "element" &&
            expanded[expanded.length - 1].tagName === "br"))
          expanded.push({type: "element", tagName: "br", properties: {},
            children: []})
        if (parts[index] !== "")
          expanded.push({type: "text", value: parts[index]})
      }
    } else {
      preserveSourceLineBreaks(child, preservesBreaks)
      expanded.push(child)
    }
  }
  node.children = expanded
}

// Give images their own presentation blocks without rewriting the Markdown.
// Their size must not decide whether surrounding prose shares a baseline.
function separateParagraphImages(node) {
  if (!node || !Array.isArray(node.children)) return
  const children = []
  for (const child of node.children) {
    separateParagraphImages(child)
    if (child.type !== "element" || child.tagName !== "p" ||
        !child.children.some(part => part.type === "element" && part.tagName === "img")) {
      children.push(child)
      continue
    }
    let run = []
    const flush = () => {
      if (run.some(part => part.type !== "text" || /\S/.test(part.value || "")))
        children.push({...child, children: run})
      run = []
    }
    for (const part of child.children) {
      if (part.type === "element" && part.tagName === "img") {
        flush()
        children.push({...child, children: [part]})
      } else run.push(part)
    }
    flush()
  }
  node.children = children
}

function decorateStandaloneImages(node) {
  if (!node || !Array.isArray(node.children)) return
  for (const child of node.children) decorateStandaloneImages(child)
  if (node.type !== "element" || node.tagName !== "p" ||
      node.children.length !== 1) return
  const image = node.children[0]
  if (!image || image.type !== "element" || image.tagName !== "img") return
  const alt = String(image.properties && image.properties.alt || "")
  node.properties = {...(node.properties || {}),
    className: ["jotpin-image"]}
  if (alt) {
    node.children = [image,
      {type: "element", tagName: "br", properties: {}, children: []},
      {type: "element", tagName: "small",
        properties: {className: ["jotpin-image-caption"]},
        children: [{type: "text", value: alt}]}]
  }
}

function preserveRawHtmlAsText(node) {
  if (!node || typeof node !== "object") return
  if (node.type === "html") node.type = "text"
  for (const child of Array.isArray(node.children) ? node.children : [])
    preserveRawHtmlAsText(child)
}

function imageResizeMetadata(value) {
  const match = /^<!--[ \t]*jotpin:image[ \t]+width[ \t]*=[ \t]*([0-9]{1,5})[ \t]*-->$/i
    .exec(String(value || ""))
  if (!match) return null
  const width = Math.max(48, Math.min(8192, Number(match[1]) || 0))
  return width > 0 ? {width} : null
}

function collectImageMetadata(node, result) {
  if (!node || !Array.isArray(node.children)) return
  const children = node.children
  const visibleChildren = children.filter(child => !(child &&
    child.type === "html" && imageResizeMetadata(child.value)))
  const retained = []
  for (let index = 0; index < children.length; index++) {
    const child = children[index]
    if (child && (child.type === "image" || child.type === "imageReference")) {
      const following = index + 1 < children.length ? children[index + 1] : null
      const metadata = following && following.type === "html"
        ? imageResizeMetadata(following.value) : null
      const position = child.position || {}
      const metadataPosition = metadata && following.position
        ? following.position : null
      result.push({
        sourceStart: position.start ? Number(position.start.offset) : -1,
        sourceEnd: position.end ? Number(position.end.offset) : -1,
        metadataStart: metadataPosition && metadataPosition.start
          ? Number(metadataPosition.start.offset) : -1,
        metadataEnd: metadataPosition && metadataPosition.end
          ? Number(metadataPosition.end.offset) : -1,
        width: metadata ? metadata.width : 0,
        url: typeof child.url === "string" ? child.url : "",
        alt: typeof child.alt === "string" ? child.alt : "",
        standalone: node.type === "paragraph" && visibleChildren.length === 1
      })
      retained.push(child)
      if (metadata) index++
      continue
    }
    collectImageMetadata(child, result)
    retained.push(child)
  }
  node.children = retained
}

function applyImageMetadata(node, images, state, parent) {
  if (!node || typeof node !== "object") return
  if (node.type === "element" && node.tagName === "img") {
    const index = state.index++
    const image = index < images.length ? images[index] : null
    if (image) {
      image.standalone = Boolean(parent && parent.tagName === "p" && parent.children.length === 1)
      const properties = {...(node.properties || {})}
      image.url = String(properties.src || image.url || "")
      image.alt = String(properties.alt || image.alt || "")
      if (Number(image.width) > 0) properties.width = Number(image.width)
      node.properties = properties
    }
  }
  for (const child of Array.isArray(node.children) ? node.children : [])
    applyImageMetadata(child, images, state, node)
}

function codeSourceMetadata(node, source, language) {
  const position = node && node.position
  const sourceStart = position && position.start
    ? Number(position.start.offset) || 0 : 0
  const sourceEnd = position && position.end
    ? Number(position.end.offset) || sourceStart : sourceStart
  const slice = source.slice(sourceStart, sourceEnd)
  const newline = slice.search(/[\r\n]/)
  const openingLine = newline >= 0 ? slice.slice(0, newline) : slice
  const opening = /^( {0,3})(`{3,}|~{3,})([^\r\n]*)/.exec(openingLine)
  let languageStart = sourceStart
  let languageEnd = sourceStart
  if (opening) {
    const info = String(opening[3] || "")
    const leading = /^\s*/.exec(info)
    const infoTokenStart = leading ? leading[0].length : 0
    const infoToken = /^\S*/.exec(info.slice(infoTokenStart))
    const tokenLength = infoToken ? infoToken[0].length : 0
    languageStart = sourceStart + String(opening[1] || "").length +
      String(opening[2] || "").length + infoTokenStart
    languageEnd = languageStart + tokenLength
  }
  const newlineLength = newline >= 0 && slice.charAt(newline) === "\r" &&
      slice.charAt(newline + 1) === "\n" ? 2 : newline >= 0 ? 1 : 0
  return {
    sourceStart,
    sourceEnd,
    languageStart,
    languageEnd,
    codeStart: newline >= 0 ? sourceStart + newline + newlineLength : sourceEnd
  }
}

function qtHtmlTree(tree, source) {
  const codeBlocks = []
  const sourceLines = source.split("\n")

  function hasClass(node, className) {
    const classes = node && node.properties &&
      Array.isArray(node.properties.className)
      ? node.properties.className : []
    return classes.some(value => String(value || "") === className)
  }

  function listItemContent(item) {
    const content = []
    const nested = []
    for (const child of Array.isArray(item.children) ? item.children : []) {
      if (child && child.type === "element" &&
          (child.tagName === "ul" || child.tagName === "ol")) {
        nested.push(child)
      } else if (child && child.type === "element" &&
          child.tagName === "p") {
        content.push(...(Array.isArray(child.children) ? child.children : []))
      } else content.push(child)
    }
    return {content, nested}
  }

  // Unindented lazy continuations keep their source rows and left edge in
  // Preview. Separate native paragraphs prevent the list's hanging indent
  // from leaking onto those rows, including their wrapped text.
  function listContentRows(children, listIndent) {
    const rows = [[]]
    for (const child of children) {
      if (child.type === "text" && String(child.value || "").includes("\n")) {
        const lines = String(child.value).split("\n")
        const startLine = Number(child.position && child.position.start.line) || 0
        for (let index = 0; index < lines.length; index++) {
          if (index > 0) {
            const raw = sourceLines[startLine + index - 1] || ""
            const indent = /^[ \t]*/.exec(raw)[0].length
            if (startLine > 0 && indent <= listIndent && /\S/.test(raw))
              rows.push([])
            else rows[rows.length - 1].push({type: "element", tagName: "br",
              properties: {}, children: []})
          }
          rows[rows.length - 1].push({...child, value: lines[index]})
        }
      } else if (Array.isArray(child.children)) {
        const nestedRows = listContentRows(child.children, listIndent)
        for (let index = 0; index < nestedRows.length; index++) {
          if (index > 0) rows.push([])
          rows[rows.length - 1].push({...child, children: nestedRows[index]})
        }
      } else rows[rows.length - 1].push(child)
    }
    return rows
  }

  function flattenedListChildren(list, depth) {
    const result = []
    const ordered = list.tagName === "ol"
    const start = Number(list.properties && list.properties.start) || 1
    const items = (Array.isArray(list.children) ? list.children : [])
      .filter(child => child && child.type === "element" &&
        child.tagName === "li")
    for (let itemIndex = 0; itemIndex < items.length; itemIndex++) {
      const item = items[itemIndex]
      const task = hasClass(item, "task-list-item")
      const parts = listItemContent(item)
      const indentation = "\u00a0\u00a0".repeat(Math.max(0, depth))
      const marker = task ? indentation : indentation +
        (ordered ? String(start + itemIndex) + ". " : "• ")
      const itemLine = sourceLines[(item.position && item.position.start.line || 1) - 1] || ""
      const listIndent = /^[ \t]*/.exec(itemLine)[0].length
      const rows = listContentRows(parts.content, listIndent)
      for (let rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        result.push({
          type: "element",
          tagName: "p",
          properties: rowIndex === 0 ? {className: [task
            ? "jotpin-task-list-item" : "jotpin-list-item"]} : {},
          children: rowIndex === 0
            ? [{type: "text", value: marker}, ...rows[rowIndex]] : rows[rowIndex],
          position: item.position
        })
      }
      for (const nested of parts.nested)
        result.push(...flattenedListChildren(nested, depth + 1))
    }
    return result
  }

  function flattenedQuoteRows(quote, depth, rows) {
    const result = rows || []
    for (const child of Array.isArray(quote.children) ? quote.children : []) {
      if (child && child.type === "text" && /^\s*$/.test(
          String(child.value || ""))) continue
      if (child && child.type === "element" &&
          child.tagName === "blockquote") {
        flattenedQuoteRows(child, depth + 1, result)
      } else if (child) {
        result.push({depth, child})
      }
    }
    return result
  }

  function quoteDepthSpan(rows, rowIndex, depth) {
    let span = 0
    for (let index = rowIndex; index < rows.length; index++) {
      if (Number(rows[index].depth) < depth) break
      span++
    }
    return Math.max(1, span)
  }

  function flattenedQuoteTableRows(quote) {
    const rows = flattenedQuoteRows(quote, 1, [])
    if (rows.length === 0) rows.push({depth: 1, child: {
      type: "text", value: "\u200b"
    }})
    const maximumDepth = rows.reduce((maximum, row) =>
      Math.max(maximum, Number(row.depth) || 1), 1)

    for (let index = 1; index < rows.length; index++) {
      const previousPosition = rows[index - 1].child &&
        rows[index - 1].child.position || {}
      const currentPosition = rows[index].child &&
        rows[index].child.position || {}
      const previousEndLine = Number(previousPosition.end &&
        previousPosition.end.line) || 0
      const currentStartLine = Number(currentPosition.start &&
        currentPosition.start.line) || 0
      rows[index].gapBefore = previousEndLine > 0 && currentStartLine >
        previousEndLine + 1
    }

    return rows.map((row, rowIndex) => {
      const depth = Math.max(1, Number(row.depth) || 1)
      const cells = []
      for (let level = 1; level <= depth; level++) {
        const previousDepth = rowIndex > 0
          ? Math.max(1, Number(rows[rowIndex - 1].depth) || 1) : 0
        if (previousDepth >= level) continue
        const rowSpan = quoteDepthSpan(rows, rowIndex, level)
        cells.push({type: "element", tagName: "td", properties: {
          width: 2, rowSpan,
          style: "border:0;padding:0"
        }, children: [{type: "text", value: " "}]})
        cells.push({type: "element", tagName: "td", properties: {
          width: 10, rowSpan, style: "border:0;padding:0"
        }, children: [{type: "text", value: " "}]})
      }
      const remainingColumns = 1 + (maximumDepth - depth) * 2
      cells.push({type: "element", tagName: "td", properties: {
        colSpan: remainingColumns,
        style: "border:0;padding:0;color:JOTPIN_QUOTE_TEXT" +
          (row.gapBefore ? ";padding-top:JOTPIN_QUOTE_GAPpx" : "")
      }, children: [row.child]})
      return {type: "element", tagName: "tr", properties: {},
        children: cells}
    })
  }

  function visit(node, parent) {
    if (!node || typeof node !== "object") return
    if (node.type === "element" && node.tagName === "pre") {
      const codeNode = (Array.isArray(node.children) ? node.children : [])
        .find(child => child && child.type === "element" &&
          child.tagName === "code")
      if (codeNode) {
        const classes = codeNode.properties &&
          Array.isArray(codeNode.properties.className)
          ? codeNode.properties.className : []
        const languageClass = classes.find(value =>
          String(value || "").startsWith("language-"))
        const language = languageClass
          ? String(languageClass).slice("language-".length) : ""
        const code = textContent(codeNode).replace(/\n$/, "")
        const token = "JOTPIN_CODE_BLOCK_" + codeBlocks.length + "_TOKEN"
        codeBlocks.push({token, language, code, fallbackHtml: escapeHtml(code),
          ...codeSourceMetadata(node, source, language)})
        node.tagName = "table"
        node.properties = {
          className: ["jotpin-code-block"], border: 0,
          cellSpacing: 0, cellPadding: 10, width: "100%",
          bgColor: "JOTPIN_CODE_BG"
        }
        node.children = [{
          type: "element", tagName: "tr", properties: {}, children: [{
            type: "element", tagName: "td",
            properties: {style: "border:0"},
            children: [{type: "text", value: token}]
          }]
        }]
        return
      }
    }
    if (node.type === "element" &&
        (node.tagName === "ul" || node.tagName === "ol")) {
      const flattened = flattenedListChildren(node, 0)
      node.tagName = "div"
      node.properties = {className: ["jotpin-list"]}
      node.children = flattened
    } else if (node.type === "element" && node.tagName === "blockquote") {
      const quoteRows = flattenedQuoteTableRows(node)
      node.tagName = "table"
      node.properties = {
        className: ["jotpin-quote"], border: 0, cellSpacing: 0,
        cellPadding: 0
      }
      node.children = quoteRows
    }
    if (node.type === "element" && node.tagName === "table" &&
        !hasClass(node, "jotpin-quote") &&
        !hasClass(node, "jotpin-code-block")) {
      node.properties = Object.assign({}, node.properties, {
        border: 1,
        cellSpacing: 0,
        cellPadding: 7
      })
    } else if (node.type === "element" &&
        (node.tagName === "th" || node.tagName === "td")) {
      node.properties = Object.assign({align: "left"}, node.properties, {
        vAlign: "top"
      })
    }
    if (node.type === "element" && node.tagName === "input" &&
        node.properties && node.properties.type === "checkbox") {
      const checked = Boolean(node.properties.checked)
      node.tagName = "span"
      node.properties = checked ? {
        className: ["jotpin-task-checked"],
        style: "color:transparent"
      } : {
        className: ["jotpin-task-unchecked"],
        style: "color:transparent"
      }
      // Keep one identical invisible layout placeholder for both states.
      // Several fonts assign different advances to the checked and unchecked
      // glyphs, which would otherwise make task text jump horizontally.
      node.children = [{type: "text", value: "☐ \u00a0"}]
      return
    }
    if (node.type === "element" && node.tagName === "code") {
      node.tagName = "span"
      node.properties = {
        className: ["jotpin-inline-code"],
        style: "color:JOTPIN_ACCENT;background-color:JOTPIN_INLINE_CODE_BG"
      }
    }
    const children = Array.isArray(node.children) ? node.children : []
    for (const child of children) visit(child, node)
  }

  visit(tree, null)
  return {tree, codeBlocks}
}

export function render(sourceValue) {
  const source = String(sourceValue || "")
  const gfmMdastExtensions = gfmFromMarkdown()
  // The micromark GFM tokenizer already emits positioned literal URL/email
  // nodes. Its mdast fallback transform uses regex lookbehind (unsupported by
  // QJSEngine) and replaces text with unpositioned nodes, so omit that one
  // redundant transform while retaining the token enter/exit handlers.
  delete gfmMdastExtensions[0].transforms
  const mdast = fromMarkdown(source, {
    extensions: [gfm()],
    mdastExtensions: [gfmMdastExtensions]
  })
  const images = []
  collectImageMetadata(mdast, images)
  preserveRawHtmlAsText(mdast)
  // Raw HTML from notes is intentionally not passed through. The established
  // mdast-to-hast conversion creates a structural tree, then the standard
  // sanitizer constrains links, images, attributes, and generated footnotes.
  const safeHast = injectBlankRows(
    sanitize(toHast(mdast), defaultSchema), source)
  separateParagraphImages(safeHast)
  applyImageMetadata(safeHast, images, {index: 0})
  preserveSourceLineBreaks(safeHast)
  decorateStandaloneImages(safeHast)
  const qt = qtHtmlTree(safeHast, source)
  return {
    tree: compactTreeWithBlankRows(mdast, source),
    html: toHtml(qt.tree),
    codeBlocks: qt.codeBlocks,
    images
  }
}
