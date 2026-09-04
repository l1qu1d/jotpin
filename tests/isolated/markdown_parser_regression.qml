import QtQuick
import Quickshell

// Offscreen proof that the vendored micromark/mdast parser retains canonical
// source offsets after bundling into Qt's WorkerScript runtime.
ShellRoot {
  id: shell

  property string source: "# Heading\n\nA **bold** *italic* `code` and [link](https://example.com).\n\nLiteral https://example.org and person@example.org.\n\nHard break  \ncontinues.\n\n~~deleted~~\n\n- [ ] Task one\n- [x] Task done\n- bullet two\n  - nested bullet\n\n1. Ordered one\n2. Ordered two\n\n---\n\n> Quoted text\n\n```js\nconst answer = 42\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n![offline](markdown-image.svg)<!-- jotpin:image width=320 -->"
  property var failures: []
  property var typeCounts: ({})
  property int nodeCount: 0
  property int positionedNodeCount: 0
  property int maximumDepth: 0

  function fail(message) {
    failures.push(String(message))
    console.error("MARKDOWN_PARSER_FAIL: " + message)
  }

  function sourceSlice(node) {
    if (!node || !node.position || !node.position.start ||
        !node.position.end) return ""
    return source.slice(Number(node.position.start.offset),
      Number(node.position.end.offset))
  }

  function collect(node, depth, nodes) {
    if (!node) return
    var type = String(node.type || "")
    typeCounts[type] = Number(typeCounts[type] || 0) + 1
    nodeCount++
    maximumDepth = Math.max(maximumDepth, Number(depth) || 0)
    nodes.push(node)
    if (node.position && node.position.start && node.position.end) {
      var start = Number(node.position.start.offset)
      var end = Number(node.position.end.offset)
      if (!isFinite(start) || !isFinite(end) || start < 0 || end < start ||
          end > source.length) {
        fail(type + " has an invalid source range " + start + ".." + end)
      } else {
        positionedNodeCount++
      }
    } else {
      fail(type + " has no source position")
    }
    var children = Array.isArray(node.children) ? node.children : []
    for (var index = 0; index < children.length; index++)
      collect(children[index], depth + 1, nodes)
  }

  function findNode(nodes, type, predicate) {
    for (var index = 0; index < nodes.length; index++) {
      var node = nodes[index]
      if (String(node.type || "") === type &&
          (!predicate || predicate(node))) return node
    }
    return null
  }

  function expectSlice(nodes, type, expected, predicate) {
    var node = findNode(nodes, type, predicate)
    if (!node) {
      fail("missing " + type + " node for " + JSON.stringify(expected))
      return
    }
    var actual = sourceSlice(node)
    if (actual !== expected) {
      fail(type + " range sliced " + JSON.stringify(actual) +
        " instead of " + JSON.stringify(expected))
    }
  }

  function expectHtml(html, fragment, name) {
    if (String(html || "").indexOf(fragment) < 0)
      fail("generated HTML is missing " + name + ": " + fragment)
  }

  function validate(tree, html, codeBlocks, images, elapsedMs) {
    var nodes = []
    collect(tree, 0, nodes)
    expectSlice(nodes, "heading", "# Heading")
    expectSlice(nodes, "strong", "**bold**")
    expectSlice(nodes, "emphasis", "*italic*")
    expectSlice(nodes, "inlineCode", "`code`")
    expectSlice(nodes, "link", "[link](https://example.com)")
    expectSlice(nodes, "link", "https://example.org",
      function(node) { return node.url === "https://example.org" })
    expectSlice(nodes, "link", "person@example.org",
      function(node) { return node.url === "mailto:person@example.org" })
    expectSlice(nodes, "break", "  \n")
    expectSlice(nodes, "delete", "~~deleted~~")
    expectSlice(nodes, "listItem", "- [ ] Task one",
      function(node) { return node.checked === false })
    expectSlice(nodes, "listItem", "- [x] Task done",
      function(node) { return node.checked === true })
    expectSlice(nodes, "list", "1. Ordered one\n2. Ordered two",
      function(node) { return node.ordered === true })
    expectSlice(nodes, "thematicBreak", "---")
    expectSlice(nodes, "blockquote", "> Quoted text")
    expectSlice(nodes, "code", "```js\nconst answer = 42\n```",
      function(node) { return node.lang === "js" })
    expectSlice(nodes, "table", "| A | B |\n|---|---|\n| 1 | 2 |")
    expectSlice(nodes, "image", "![offline](markdown-image.svg)",
      function(node) { return node.alt === "offline" })

    expectHtml(html, "<h1>Heading</h1>", "heading")
    expectHtml(html, "<strong>bold</strong>", "strong emphasis")
    expectHtml(html, "<em>italic</em>", "emphasis")
    expectHtml(html, '<span class="jotpin-inline-code"', "inline code")
    expectHtml(html, '<a href="https://example.com">link</a>', "link")
    expectHtml(html, '<a href="https://example.org">https://example.org</a>',
      "bare URL")
    expectHtml(html, '<a href="mailto:person@example.org">', "bare email")
    expectHtml(html, "<br>", "hard line break")
    expectHtml(html, "<del>deleted</del>", "strikethrough")
    expectHtml(html, '<div class="jotpin-list">', "Qt-compatible list")
    expectHtml(html, "1. Ordered one", "ordered-list marker")
    expectHtml(html, "☐", "unchecked task marker")
    expectHtml(html, 'class="jotpin-task-checked"', "checked task state")
    expectHtml(html, 'style="color:transparent"',
      "invisible fixed-width checkbox layout placeholder")
    expectHtml(html, '<p class="jotpin-task-list-item">',
      "Qt-compatible task list without a second bullet marker")
    expectHtml(html, '<table class="jotpin-quote"', "blockquote rail")
    expectHtml(html, "<hr>", "thematic break")
    expectHtml(html, '<table class="jotpin-code-block"',
      "Qt-compatible fenced-code card")
    expectHtml(html,
      '<table border="1" cellspacing="0" cellpadding="7">',
      "Qt-compatible compact table")
    expectHtml(html, '<th align="left" valign="top">',
      "left-aligned table header")
    expectHtml(html,
      '<img src="markdown-image.svg" alt="offline" width="320">',
      "resized image")
    if (String(html || "").indexOf("jotpin:image") >= 0)
      fail("image resize metadata became visible HTML")
    if (!Array.isArray(images) || images.length !== 1) {
      fail("expected one source-mapped image: " + JSON.stringify(images))
    } else {
      var imageStart = source.indexOf("![offline]")
      var imageEnd = source.indexOf("<!-- jotpin:image")
      var image = images[0]
      if (Number(image.sourceStart) !== imageStart ||
          Number(image.sourceEnd) !== imageEnd ||
          Number(image.metadataStart) !== imageEnd ||
          Number(image.metadataEnd) !== source.length ||
          Number(image.width) !== 320 || !Boolean(image.standalone)) {
        fail("image metadata did not preserve source spans and width: " +
          JSON.stringify(image))
      }
    }
    if (!Array.isArray(codeBlocks) || codeBlocks.length !== 1) {
      fail("expected one extracted fenced code block: " +
        JSON.stringify(codeBlocks))
    } else {
      var codeBlock = codeBlocks[0]
      if (String(codeBlock.language || "") !== "js" ||
          String(codeBlock.code || "") !== "const answer = 42" ||
          String(html || "").indexOf(String(codeBlock.token || "")) < 0) {
        fail("fenced code extraction did not preserve language/text/token: " +
          JSON.stringify(codeBlock))
      }
      var languageStart = source.indexOf("js", source.indexOf("```"))
      var codeStart = source.indexOf("const answer")
      if (Number(codeBlock.languageStart) !== languageStart ||
          Number(codeBlock.languageEnd) !== languageStart + 2 ||
          Number(codeBlock.codeStart) !== codeStart) {
        fail("fenced code extraction did not preserve editable source ranges: " +
          JSON.stringify({block: codeBlock, languageStart: languageStart,
            codeStart: codeStart}))
      }
    }

    var result = {
      schemaVersion: 1,
      sourceLength: source.length,
      rootStart: tree.position.start.offset,
      rootEnd: tree.position.end.offset,
      nodeCount: nodeCount,
      positionedNodeCount: positionedNodeCount,
      maximumDepth: maximumDepth,
      typeCounts: typeCounts,
      parseElapsedMs: Number(elapsedMs) || 0,
      failures: failures
    }
    console.log("MARKDOWN_PARSER_RESULT: " + JSON.stringify(result))
    Qt.exit(failures.length === 0 ? 0 : 1)
  }

  WorkerScript {
    id: parserWorker
    source: "./markdown/MarkdownParserWorker.js"
    onMessage: function(message) {
      if (String(message.key || "") !== "representative") return
      if (String(message.type || "") === "parseError") {
        fail("worker parse error: " + String(message.message || "unknown"))
        Qt.exit(1)
        return
      }
      if (String(message.type || "") !== "parsed") return
      shell.validate(message.tree, message.html, message.codeBlocks,
        message.images, message.elapsedMs)
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: false
    onTriggered: {
      shell.fail("worker parse timed out")
      Qt.exit(1)
    }
  }

  Component.onCompleted: parserWorker.sendMessage({
    type: "parse",
    key: "representative",
    source: source
  })
}
