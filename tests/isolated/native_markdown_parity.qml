import QtQuick
import Quickshell

// Data-driven native-renderer parity coverage.  The retired MarkdownDisplay
// fixture remains the source of the cases, but assertions here use the
// production parser/document surface rather than the retired block delegates,
// projection cache, or block-item implementation details.
ShellRoot {
  id: shell

  property var cases: []
  property int caseIndex: -1
  property string activeSource: ""
  property int activeCursor: 0
  property int activeSelectionStart: 0
  property int activeSelectionEnd: 0
  property int activeWidth: 720
  property int settleAttempts: 0
  property int phase: 0
  property var failures: []
  property var ranCases: []
  property var beforeMetrics: []
  property var beforeSource: ""
  property int beforeCursor: 0
  property int beforeOptimisticEditCount: 0
  property int sourcePositionEvents: 0
  property int selectionEvents: 0
  property int taskToggleEvents: 0
  property int finalExitCode: 0
  property var display: displayLoader.item

  Timer {
    id: cleanExitTimer
    interval: 250
    repeat: false
    onTriggered: Qt.exit(shell.finalExitCode)
  }

  Loader {
    id: displayLoader
    active: true
    sourceComponent: Component {
      NativeMarkdownDisplay {
        width: shell.activeWidth
        height: Math.max(1, implicitHeight)
        foreground: Qt.rgba(1, 0.79, 0.64, 1)
        background: Qt.rgba(1, 0.79, 0.64, 0.035)
        surfaceBackground: Qt.rgba(0.02, 0.03, 0.08, 1)
        accent: "#b5a3ff"
        baseUrl: Qt.resolvedUrl("./")
        homePath: "/home/tester"
        sourceText: shell.activeSource
        cursorPosition: shell.activeCursor
        selectionStart: shell.activeSelectionStart
        selectionEnd: shell.activeSelectionEnd
        onSourcePositionRequested: shell.sourcePositionEvents++
        onSourceSelectionRequested: shell.selectionEvents++
        onTaskToggled: shell.taskToggleEvents++
      }
    }
  }

  function makeCase(name, source, expectedTypes, options) {
    // expectedTypes describes the native parser's visible top-level shape.
    // The retired delegate renderer called these shapes "quote", "rule", or
    // "image"; those labels were implementation details, so their native
    // equivalents are declared in the fixture data below instead of copied
    // into the assertions.
    var result = {name: name, source: String(source || ""),
      expectedTypes: expectedTypes}
    var extra = options || ({})
    var keys = Object.keys(extra)
    for (var index = 0; index < keys.length; index++)
      result[keys[index]] = extra[keys[index]]
    return result
  }

  function performanceSource() {
    var paragraphs = []
    for (var index = 0; index < 40; index++) {
      paragraphs.push("Paragraph " + index +
        " has **bold Markdown** and enough ordinary words to wrap across " +
        "the editor while selection follows the pointer without delay.")
    }
    return paragraphs.join("\n\n")
  }

  function buildCases() {
    return [
      makeCase("empty", "", []),
      makeCase("trailing-newline", "alpha\n", ["paragraph", "blank"]),
      makeCase("leading-and-multiple-blank-lines", "\nalpha\n\nbeta\n\n",
        ["blank", "paragraph", "blank", "paragraph", "blank", "blank"]),
      makeCase("inline-markdown",
        "# Heading\n\n**bold** *italic* ~~del~~ `code` [link](https://example.com)\n",
        ["heading", "blank", "paragraph", "blank"],
        {selectionStart: 11, selectionEnd: 41}),
      makeCase("final-line-bottom-padding",
        "# Inline code\n\nThis web site is using [markedjs/marked](https://marked.js.org/).",
        ["heading", "blank", "paragraph"],
        {selectionStart: 39, selectionEnd: 54}),
      makeCase("literal-inline-markers", "alpha *\nfoo_bar_baz\nomega ~",
        ["paragraph"]),
      makeCase("matched-emphasis-caret", "**bold** tail", ["paragraph"]),
      makeCase("nested-multiline-emphasis",
        "***both*** and **bold *inner***\n*across\nlines*", ["paragraph"]),
      makeCase("commonmark-inline-basics",
        "\\*literal\\* &amp; &#x41; <https://example.com> <person@example.com> [relative](other.md)",
        ["paragraph"]),
      makeCase("html5-entities",
        "&copy; &eacute; &larr; &NotEqualTilde; &AMP; &#x1F600; &#0; &#xD800; &notanentity;",
        ["paragraph"]),
      makeCase("commonmark-link-compatibility",
        "[nested](docs/a_(b).md \"title\") [full][guide] [collapsed][] [shortcut] [**bold**](bold.md)\n\n[guide]: guide.md 'Guide title'\n[collapsed]: collapsed.md\n[shortcut]: shortcut.md",
        ["paragraph", "blank", "blank", "blank", "blank"]),
      makeCase("reference-projection-with-definition",
        "[label][id]\n\n[id]: target.md", ["paragraph", "blank", "blank"]),
      makeCase("reference-projection-without-definition",
        "[label][id]\n\n[other]: target.md", ["paragraph", "blank", "blank"]),
      makeCase("fenced-reference-definition",
        "```text\n[bad]: bad.md\n```\n[bad]", ["code", "paragraph"]),
      makeCase("reference-image", "![fixture][asset]\n[asset]: markdown-image.svg",
        ["paragraph"]),
      makeCase("relative-image", "![fixture image](markdown-image.svg)", ["paragraph"]),
      makeCase("image-caption-following-blocks",
        "![fixture image](markdown-image.svg)\n\n## Below image\nnext line",
        ["paragraph", "blank", "heading", "paragraph"]),
      makeCase("inline-code-caret", "code `alpha` tail", ["paragraph"]),
      makeCase("setext-headings", "Title\n=====\n\nSubtitle\n-----",
        ["heading", "blank", "heading"]),
      makeCase("closing-atx-heading", "# Title #", ["heading"]),
      makeCase("preview-heading-backspace-literal", "####Watching movies and shows",
        ["paragraph"], {cursor: 4}),
      makeCase("preview-heading-separator-completed", "#### Watching movies and shows",
        ["heading"], {cursor: 5}),
      makeCase("quote-rule-code",
        "> quote\n> second\n\n---\n\n```dart\ncode\nsecond\n```",
        ["blockquote", "blank", "thematicBreak", "blank", "code"]),
      makeCase("quote-following-blank-heading",
        "> A fast, local Markdown scratchpad.\n\n## Make it yours",
        ["blockquote", "blank", "heading"]),
      makeCase("nested-quote-list-structure",
        "> - item\n>   - nested\n>\n> > deep quote", ["blockquote"]),
      makeCase("quote-mouse-hit",
        "> Markdown is a lightweight markup language with plain-text-formatting syntax, created in 2004 by John Gruber with Aaron Swartz.\n>\n>> Markdown is often used to format readme files, for writing messages in online discussion forums, and to create rich text using a plain text editor.",
        ["blockquote"], {width: 610}),
      makeCase("fenced-code-selection",
        "before\n\n```\ncode line\nsecond line\n```\n\nafter",
        ["paragraph", "blank", "code", "blank", "paragraph"],
        {selectAll: true}),
      makeCase("blank-lines-before-fenced-code-selection",
        "alpha\n\n\n```js\nfunction Test() {\n    return 'test';\n}\n```",
        ["paragraph", "blank", "blank", "code"],
        {selectionStart: 7, selectionEnd: 8}),
      makeCase("dart-code-highlighting",
        "```dart\nvoid main() {\n  final answer = 42;\n  print(answer);\n}\n```",
        ["code"], {cursorTokenEnd: "answer"}),
      makeCase("adjacent-highlighted-code-blocks",
        "```javascript\nfunction test() {\n    return 'ahello';\n}\n```\n```python\nmessafe = \"Markdown stays simple.\"\nprint(message)\n```",
        ["code", "code"]),
      makeCase("code-language-mouse-hit",
        "```javascript\nfunction test() {\n    reutrn hello;\n}\n```",
        ["code"]),
      makeCase("partial-fence-language-caret", "```b\n```", ["code"],
        {cursorTokenEnd: "b"}),
      makeCase("empty-fence-language-slot", "```\n```\n", ["code", "blank"],
        {cursor: 3}),
      makeCase("empty-code-row-after-language",
        "```javascript\n\n```\n", ["code", "blank"], {cursor: 14}),
      makeCase("fenced-code-last-line-caret",
        "```testtsets\n\nst\nststttt\nfvff\n```", ["code"],
        {cursorTokenEnd: "fvff"}),
      makeCase("unclosed-fenced-code", "```text\ncode to eof", ["code"]),
      makeCase("indented-fenced-code", "  ```text\n  alpha\n x\n    y\n  ```",
        ["code"]),
      makeCase("fenced-code-escape-row", "```text\ncode\n```\n",
        ["code", "blank"], {cursorTokenEnd: "code"}),
      makeCase("fenced-code-trailing-space-row",
        "```testtsets\nst\nststttt\nfsdfs\nfvff\n \n```", ["code"],
        {cursorTokenEnd: "fvff\n "}),
      makeCase("wrapped-quote",
        "> one two three four five six seven eight nine ten eleven twelve",
        ["blockquote"], {width: 230}),
      makeCase("wrapped-code",
        "```text\none two three four five six seven eight nine ten eleven twelve\n```",
        ["code"], {width: 230}),
      makeCase("ordered-list", "1. first\n2. second", ["list"]),
      makeCase("task-list", "- [x] test\n- [ ] test\n- [ ] fsdaf", ["list"]),
      makeCase("task-list-toggle-stability",
        "- [x] first task\n- [ ] second task\n\nText below the tasks",
        ["list", "blank", "paragraph"],
        {editedSource: "- [ ] first task\n- [ ] second task\n\nText below the tasks"}),
      makeCase("heading-edit-stability", "# Titl\n\nBody below the heading",
        ["heading", "blank", "paragraph"],
        {editedSource: "# Title\n\nBody below the heading", changedBlockIndex: 0}),
      makeCase("paragraph-edit-stability", "Paragrap\n\nBody below the paragraph",
        ["paragraph", "blank", "paragraph"],
        {editedSource: "Paragraph\n\nBody below the paragraph", changedBlockIndex: 0}),
      makeCase("blank-to-paragraph-edit-stability", "\n\nWatching movies",
        ["blank", "blank", "paragraph"],
        {cursor: 0, editedSource: "test\n\nWatching movies", editedCursor: 4,
          changedBlockIndex: 0, editedExpectedTypes: ["paragraph", "blank", "paragraph"]}),
      makeCase("inline-markdown-edit-stability",
        "Text with **bol** and `code`\n\nBody below the inline text",
        ["paragraph", "blank", "paragraph"],
        {editedSource: "Text with **bold** and `code`\n\nBody below the inline text",
          changedBlockIndex: 0}),
      makeCase("list-edit-stability", "- Ite\n\nBody below the list",
        ["list", "blank", "paragraph"],
        {editedSource: "- Item\n\nBody below the list", changedBlockIndex: 0}),
      makeCase("quote-edit-stability", "> Quot\n\nBody below the quote",
        ["blockquote", "blank", "paragraph"],
        {editedSource: "> Quote\n\nBody below the quote", changedBlockIndex: 0}),
      makeCase("code-edit-stability", "```text\nprin\n```\n\nBody below the code",
        ["code", "blank", "paragraph"],
        {editedSource: "```text\nprint\n```\n\nBody below the code", changedBlockIndex: 0}),
      makeCase("table-edit-stability",
        "| A | B |\n| --- | --- |\n| x | y |\n\nBody below the table",
        ["table", "blank", "paragraph"],
        {editedSource: "| A | B |\n| --- | --- |\n| z | y |\n\nBody below the table",
          changedBlockIndex: 0}),
      makeCase("image-caption-edit-stability",
        "![captio](markdown-image.svg)\n\nBody below the image",
        ["paragraph", "blank", "paragraph"],
        {editedSource: "![caption](markdown-image.svg)\n\nBody below the image",
          changedBlockIndex: 0}),
      makeCase("nested-list", "- parent\n    - child\n      - deep\n- sibling",
        ["list"], {cursorToken: "child"}),
      makeCase("list-container-continuations",
        "- parent\n  continuation paragraph\n    > nested quote\n\n- sibling",
        ["list"]),
      makeCase("wrapped-list-item",
        "- one two three four five six seven eight nine ten eleven twelve",
        ["list"], {width: 230, wrappedListToken: "one"}),
      makeCase("wrapped-ordered-list-item",
        "12. one two three four five six seven eight nine ten eleven twelve",
        ["list"], {width: 230, wrappedListToken: "one"}),
      makeCase("wrapped-task-list-item",
        "- [ ] task one two three four five six seven eight nine ten eleven",
        ["list"], {width: 230, wrappedListToken: "task"}),
      makeCase("wrapped-nested-list-item",
        "- parent\n  - child one two three four five six seven eight nine ten eleven",
        ["list"], {width: 230, wrappedListToken: "child"}),
      makeCase("new-empty-bullet-caret", "- item\n- ",
        ["list"], {cursor: 10}),
      makeCase("new-empty-bullet-before-existing-item",
        "- first item wraps across the preview before Enter is pressed\n- \n- existing item",
        ["list"], {width: 330, cursorTokenEnd: "\n- ",
          emptyBulletBeforeExisting: true}),
      makeCase("new-empty-bullet-before-separated-existing-item",
        "- JotPin autosaves after a short pause; use `Ctrl+S` to save immediately.\n- \n\n\n- Use Side, Center, or Full Screen to match the way you are working.",
        ["list"], {width: 330, cursorTokenEnd: "\n- ",
          emptyBulletBeforeExisting: true, expectedBulletCount: 3,
          existingToken: "Use Side"}),
      makeCase("stranded-blank-list-return-stability",
        "- JotPin autosaves after a short pause; use `Ctrl+S` to save immediately.\n\n\n\n- Use Side, Center, or Full Screen to match the way you are working.",
        ["list"],
        {width: 330,
          editedSource: "- JotPin autosaves after a short pause; use `Ctrl+S` to save immediately.\n- \n- Use Side, Center, or Full Screen to match the way you are working.",
          editedExpectedTypes: ["list"], changedBlockIndex: 0,
          noOptimisticEdit: true}),
      makeCase("wrapped-list-end-click-before-existing-item",
        "- first item wraps across the preview before Enter is pressed\n- existing item",
        ["list"], {width: 330, wrappedListEndBeforeExisting: true}),
      makeCase("wrapped-list-test-note",
        "- We should create a welcome note for new users that explains what it is, what it does, what you can do. it should be concise and pretty and use markdown",
        ["list"], {width: 560, wrappedListToken: "We"}),
      makeCase("table", "| Col | Value |\n| --- | --- |\n| A | B |",
        ["table"], {selectAll: true}),
      makeCase("wrapped-table-cell",
        "| Col | Description |\n| --- | --- |\n| A | one two three four five six seven eight nine ten eleven twelve |",
        ["table"], {width: 230}),
      makeCase("gfm-table-compatibility",
        "| Only\n| :---:\nvalue\n\n| Left | Right |\n| :--- | ---: |\n| \\| | `a|b` |\n| x | [go](https://a|b) |",
        ["table", "blank", "table"]),
      makeCase("wrapped-paragraph",
        "Hey! I created an account for you on my private media server.",
        ["paragraph"], {width: 560}),
      makeCase("wrapped-inline-range",
        "prefix supercalifragilisticmispeling suffix", ["paragraph"],
        {width: 150}),
      makeCase("wrapped-paragraph-mouse-hit",
        "This paragraph explains how clicking text should place the caret on the word should instead of keeping it on explains.",
        ["paragraph"], {width: 260}),
      makeCase("explicit-paragraph-lines", "line one\nline two\nline three",
        ["paragraph"], {selectionStart: 0, selectionEnd: 28}),
      makeCase("partial-selection-across-lines", "one two\nthree four\nfive six",
        ["paragraph"], {selectionStart: 4, selectionEnd: 15}),
      makeCase("partial-selection-across-blocks",
        "one line\n\nsecond line\n\nthird line",
        ["paragraph", "blank", "paragraph", "blank", "paragraph"],
        {selectionStart: 13, selectionEnd: 28}),
      makeCase("trailing-whitespace-columns",
        "asdf\nasdf    \nits better than ba                     ", ["paragraph"]),
      makeCase("internal-tab-spaces", "Em  phasis", ["paragraph"], {cursor: 4}),
      makeCase("whitespace-only-row", "asdf\n    \nits better than ba",
        ["paragraph", "blank", "paragraph"]),
      makeCase("heading-trailing-empty-row", "# this is a header:\n\n",
        ["heading", "blank", "blank"]),
      makeCase("heading-paragraph-gap", "# this is a header:\n\ntyping",
        ["heading", "blank", "paragraph"]),
      makeCase("empty-bullet-whitespace", "-  ", ["list"], {cursor: 3}),
      makeCase("empty-bullet-more-whitespace", "-     ", ["list"], {cursor: 6}),
      makeCase("active-incomplete-list-marker", "text\n-", ["heading"]),
      makeCase("special-characters", "<tag> & value _under_", ["paragraph"]),
      makeCase("crlf-source", "alpha\r\n- item\r\nsecond",
        ["paragraph", "list"]),
      makeCase("crlf-quote-table",
        "> one\r\n> two\r\n\r\n| A | B |\r\n| --- | --- |\r\n| x | y |",
        ["blockquote", "blank", "table"]),
      makeCase("selection-across-rows", "alpha\n\n- one\n- two\n\nbeta",
        ["paragraph", "blank", "list", "blank", "paragraph"],
        {selectAll: true}),
      makeCase("partial-selection", "alpha\nbeta\ngamma", ["paragraph"],
        {selectionStart: 1, selectionEnd: 3}),
      makeCase("selection-performance", performanceSource(), (function() {
        var types = []
        for (var index = 0; index < 40; index++) {
          if (index > 0) types.push("blank")
          types.push("paragraph")
        }
        return types
      })(), {skipEveryCaret: true})
    ]
  }

  function currentCase() {
    return cases[caseIndex] || ({name: "unknown", source: "", expectedTypes: []})
  }

  function fail(message) {
    var text = "case " + currentCase().name + ": " + String(message)
    failures.push(text)
    // Parity mismatches are expected production evidence, not QML/runtime
    // diagnostics. Keep them on the normal log channel so the shell runner
    // can still reject genuine warnings and errors.
    console.log("NATIVE_PARITY_FAIL: " + text)
  }

  function check(condition, message) {
    if (!condition) fail(message)
  }

  function finite(value) {
    return isFinite(Number(value))
  }

  function validRect(rect) {
    return rect !== null && rect !== undefined && finite(rect.x) &&
      finite(rect.y) && finite(rect.width) && finite(rect.height) &&
      Number(rect.width) > 0 && Number(rect.height) > 0
  }

  function rectCenter(rect) {
    return {x: Number(rect.x) + Number(rect.width) / 2,
      y: Number(rect.y) + Number(rect.height) / 2}
  }

  function actualTypes(metrics) {
    var result = []
    for (var index = 0; index < metrics.length; index++)
      result.push(String(metrics[index].type || ""))
    return result
  }

  function visibleTypes(metrics) {
    var result = []
    for (var index = 0; index < metrics.length; index++) {
      // mdast definition nodes have no rendered HTML of their own. They are
      // represented by the injected blank-row surface between visible blocks.
      var type = String(metrics[index].type || "")
      result.push(type === "definition" ? "blank" : type)
    }
    return result
  }

  function sourcePositionForToken(token, fromEnd) {
    var source = String(activeSource || "")
    var position = fromEnd ? source.lastIndexOf(String(token)) :
      source.indexOf(String(token))
    if (position < 0) return -1
    return position + (fromEnd ? String(token).length : 0)
  }

  function checkMetrics(metrics, expectedTypes) {
    // The old fixture also inspected projection-cache entries, delegate ids,
    // linear source-column helpers, and block-index internals. Those checks
    // are intentionally not ported: this harness only asserts the native
    // document's public geometry, source ranges, and semantic block shape.
    check(Array.isArray(metrics), "layoutMetricsForTests() returned no array")
    if (!Array.isArray(metrics)) return
    check(metrics.length === expectedTypes.length,
      "metric count differs from expected block count: " +
      JSON.stringify({actual: metrics.length, expected: expectedTypes.length,
        types: actualTypes(metrics)}))
    var previousTop = -1
    for (var index = 0; index < metrics.length; index++) {
      var metric = metrics[index] || {}
      check(finite(metric.y) && finite(metric.height) &&
          Number(metric.y) >= 0 && Number(metric.height) > 0,
        "metric " + index + " has finite positive geometry: " +
        JSON.stringify(metric))
      // QTextDocument caret rectangles can span a neighboring block's top
      // while their baselines remain correctly ordered. Preserve the old
      // user-facing ordering contract without asserting retired delegate-box
      // boundaries that the native document does not expose.
      if (index > 0)
        check(Number(metric.y) >= previousTop - 1,
          "metric " + index + " is visually above its preceding block: " +
            JSON.stringify({previousTop: previousTop, metric: metric}))
      previousTop = Number(metric.y)
      check(Number(metric.sourceStart) >= 0 &&
          Number(metric.sourceEnd) >= Number(metric.sourceStart) &&
          Number(metric.sourceEnd) <= activeSource.length,
        "metric " + index + " has an invalid source range")
    }
    check(visibleTypes(metrics).toString() === expectedTypes.toString(),
      "visible block types differ: " + JSON.stringify({actual: actualTypes(metrics),
        visible: visibleTypes(metrics), expected: expectedTypes}))
  }

  function checkCaretCoverage() {
    var source = String(activeSource || "")
    var spec = currentCase()
    var missing = []
    var step = spec.skipEveryCaret ? Math.max(1, Math.ceil(source.length / 200)) : 1
    for (var position = 0; position <= source.length; position += step) {
      if (!validRect(display.cursorRectangleForSource(position)))
        missing.push(position)
    }
    if (step > 1 && !validRect(display.cursorRectangleForSource(source.length)))
      missing.push(source.length)
    check(missing.length === 0,
      "source caret coverage has gaps: " + JSON.stringify(missing.slice(0, 20)))
  }

  function checkPointRoundTrips() {
    var source = String(activeSource || "")
    var positions = [0, source.length, Number(activeCursor),
      Number(activeSelectionStart), Number(activeSelectionEnd)]
    var stride = Math.max(1, Math.ceil(source.length / 8))
    for (var position = 0; position <= source.length; position += stride)
      positions.push(position)
    var failuresAt = []
    for (var index = 0; index < positions.length; index++) {
      var requested = Math.max(0, Math.min(source.length,
        Number(positions[index]) || 0))
      var caret = display.cursorRectangleForSource(requested)
      if (!validRect(caret)) {
        failuresAt.push({position: requested, reason: "missing-caret"})
        continue
      }
      var center = rectCenter(caret)
      var mapped = Number(display.sourcePositionForPoint(center.x, center.y))
      if (!finite(mapped) || mapped < 0 || mapped > source.length ||
          Math.abs(mapped - requested) > 48)
        failuresAt.push({position: requested, mapped: mapped, caret: caret})
    }
    check(failuresAt.length === 0,
      "caret center point round-trips drift outside nearby source: " +
      JSON.stringify(failuresAt.slice(0, 8)))
  }

  function checkSelectionGeometry() {
    var spec = currentCase()
    var start = spec.selectAll ? 0 : Number(spec.selectionStart || 0)
    var end = spec.selectAll ? activeSource.length :
      Number(spec.selectionEnd || 0)
    if (end <= start) return
    var rectangles = display.sourceRangeRectangles(start, end)
    check(Array.isArray(rectangles) && rectangles.length > 0,
      "selection range produced no geometry")
    if (!Array.isArray(rectangles)) return
    var invalid = []
    for (var index = 0; index < rectangles.length; index++) {
      var rect = rectangles[index]
      if (!validRect(rect)) invalid.push(index)
      else {
        var mapped = display.sourcePositionForPoint(
          Number(rect.x) + Number(rect.width) / 2,
          Number(rect.y) + Number(rect.height) / 2)
        if (!finite(mapped) || mapped < start - 1 || mapped > end + 1)
          invalid.push({index: index, mapped: mapped, rect: rect})
      }
    }
    check(invalid.length === 0,
      "selection rectangles are invalid or map outside their source range: " +
      JSON.stringify(invalid.slice(0, 8)))
  }

  function checkSourceRange(token, occurrence) {
    var source = String(activeSource || "")
    var start = -1
    var search = 0
    var count = Math.max(0, Number(occurrence) || 0)
    for (var index = 0; index <= count; index++) {
      start = source.indexOf(String(token), search)
      if (start < 0) break
      search = start + String(token).length
    }
    if (start < 0) {
      fail("fixture token is absent: " + token)
      return
    }
    var end = start + String(token).length
    var rectangles = display.sourceRangeRectangles(start, end)
    check(Array.isArray(rectangles) && rectangles.length > 0,
      "source range has no rendered rectangles for " + token)
    if (!Array.isArray(rectangles)) return
    for (var rectIndex = 0; rectIndex < rectangles.length; rectIndex++) {
      var rect = rectangles[rectIndex]
      check(validRect(rect), "source range rectangle is invalid for " + token)
      if (!validRect(rect)) continue
      var mapped = display.sourcePositionForPoint(
        Number(rect.x) + Number(rect.width) / 2,
        Number(rect.y) + Number(rect.height) / 2)
      check(finite(mapped) && mapped >= start - 1 && mapped <= end + 1,
        "source range rectangle maps outside " + token + ": " + mapped)
    }
  }

  function checkClickContract() {
    var source = String(activeSource || "")
    var word = source.indexOf("bold") >= 0 ? "bold" :
      source.indexOf("Markdown") >= 0 ? "Markdown" : ""
    if (word !== "") {
      var wordStart = source.indexOf(word)
      var range = display.wordRangeAt(wordStart)
      check(Number(range.start) <= wordStart && Number(range.end) >=
        wordStart + word.length, "word hit range does not contain visible word")
      var wordCaret = display.cursorRectangleForSource(wordStart + 1)
      if (validRect(wordCaret)) {
        var wordHit = Number(display.sourcePositionForPoint(
          Number(wordCaret.x) + Number(wordCaret.width) / 2,
          Number(wordCaret.y) + Number(wordCaret.height) / 2))
        check(finite(wordHit) && wordHit >= wordStart - 1 &&
          wordHit <= wordStart + word.length + 1,
          "rendered word click did not resolve to its nearby source range: " +
          JSON.stringify({word: word, requested: wordStart + 1,
            returned: wordHit}))
      }
    }
    var position = word === "" ? 0 : source.indexOf(word) + 1
    var line = display.sourceLineSelectionRange(position)
    check(Number(line.start) >= 0 && Number(line.end) >= Number(line.start) &&
      Number(line.end) <= source.length, "line selection range is invalid")
    display.mouseClickCount = 0
    display.mouseClickKey = ""
    var first = display.registerRenderedMousePress(position)
    var second = display.registerRenderedMousePress(position)
    var third = display.registerRenderedMousePress(position)
    check(first === 1 && second === 2 && third === 3,
      "single/double/triple rendered click sequence was not retained")
  }

  function checkSourceNavigation() {
    var source = String(activeSource || "")
    if (source.length === 0) return
    var positions = [0, source.length, Number(activeCursor),
      Number(activeSelectionStart), Number(activeSelectionEnd)]
    var stride = Math.max(1, Math.ceil(source.length / 6))
    for (var position = 0; position <= source.length; position += stride)
      positions.push(position)
    var seenPositions = ({})
    for (var index = 0; index < positions.length; index++) {
      var requested = Math.max(0, Math.min(source.length,
        Number(positions[index]) || 0))
      var positionKey = String(requested)
      if (seenPositions[positionKey] === true) continue
      seenPositions[positionKey] = true
      var line = display.sourceLineSelectionRange(requested)
      check(Number(line.start) >= 0 && Number(line.end) >= Number(line.start) &&
        Number(line.end) <= source.length && requested >= Number(line.start) &&
        requested <= Number(line.end),
        "source line navigation returned an invalid containing row: " +
        JSON.stringify({position: requested, line: line}))
      var target = display.cursorTargetForSource(requested)
      check(target !== null && target !== undefined &&
        Number(target.blockIndex) >= -1 && String(target.blockType || "") !== "",
        "source cursor navigation returned no public block target: " +
        JSON.stringify({position: requested, target: target}))
    }
    if (source.indexOf("\n") >= 0) {
      var start = source.indexOf("\n") + 1
      var caret = display.cursorRectangleForSource(start)
      if (validRect(caret)) {
        var next = display.verticalNavigationTarget(start,
          Number(caret.x) + Number(caret.width) / 2, 1)
        var hasLaterRow = source.indexOf("\n", start) >= 0
        if (hasLaterRow)
          check(finite(next) && next >= 0 && next <= source.length,
            "downward source navigation returned an invalid target: " + next)
      }
    }
  }

  function checkInlineContract() {
    var html = String(display.renderedHtml || "")
    var source = String(activeSource || "")
    if (source.indexOf("**") >= 0)
      check(html.indexOf("<strong>") >= 0, "strong inline markup was not rendered")
    if (/(^|[^\\*])\*[^*\n]+\*(?!\*)|(^|[^_])_[^_\n]+_(?!_)/.test(source))
      check(html.indexOf("<em>") >= 0 || source.indexOf("\n") >= 0,
        "emphasis fixture did not render an inline emphasis node")
    if (source.indexOf("`") >= 0)
      check(html.indexOf("jotpin-inline-code") >= 0,
        "inline code fixture did not render a code span")
    if (source.indexOf("[") >= 0 && source.indexOf("](") >= 0)
      check(html.indexOf("<a ") >= 0, "inline link fixture did not render an anchor")
    if (source.indexOf("&") >= 0)
      check(html.indexOf("&amp;") >= 0 || html.indexOf("&#x26;") >= 0 ||
        html.indexOf("&#38;") >= 0 || html.indexOf("©") >= 0 ||
        html.indexOf("😀") >= 0, "entity fixture lost escaped/decoded text")
    if (source.indexOf("bold") >= 0) checkSourceRange("bold", 0)
    if (source.indexOf("inline code") >= 0) checkSourceRange("inline code", 0)
  }

  function checkLinkContract() {
    var html = String(display.renderedHtml || "")
    var source = String(activeSource || "")
    // A reference definition inside a fenced block is intentionally not a
    // rendered link. Only inspect fixtures containing actual link/reference
    // syntax outside that code-only shape.
    var hasLinkSyntax = /(^|[^!])\[[^\]]+\](?:\([^)]*\)|\[[^\]]*\])/.test(source)
    if (hasLinkSyntax) {
      check(html.indexOf("href=") >= 0 || source.indexOf("[label]") >= 0,
        "link/reference fixture did not expose an href or unresolved label")
    }
    display.homePath = "/home/tester"
    check(display.linkSourceUrl("~/note.md").indexOf("note.md") >= 0,
      "home-relative URL did not resolve")
    check(display.linkSourceUrl("relative.md").indexOf("relative.md") >= 0,
      "relative URL did not resolve")
  }

  function checkImageContract() {
    var source = String(activeSource || "")
    if (source.indexOf("![") < 0) return
    var html = String(display.renderedHtml || "")
    if (currentCase().name === "reference-image" &&
        html.indexOf("<img ") < 0) {
      check(String(display.documentPlainText || "").indexOf(
          "![fixture][asset]") >= 0,
        "CommonMark-invalid adjacent reference image was not retained literally")
      return
    }
    check(html.indexOf("<img ") >= 0, "image fixture did not render an image")
    var imagePosition = source.indexOf("![")
    var imageCaret = display.cursorRectangleForSource(imagePosition)
    check(validRect(imageCaret), "image source has no caret geometry")
    if (source.indexOf("fixture") >= 0) checkSourceRange("fixture", 0)
  }

  function checkHeadingContract() {
    var source = String(activeSource || "")
    var html = String(display.renderedHtml || "")
    if (/^ {0,3}#{1,6}(?:\s|$)/m.test(source)) {
      check(html.indexOf("<h") >= 0, "heading fixture did not render a heading")
      var headingText = source.indexOf("Title") >= 0 ? "Title" :
        source.indexOf("Heading") >= 0 ? "Heading" : ""
      if (headingText !== "") checkSourceRange(headingText, 0)
    }
    if (source.indexOf("=====") >= 0 || source.indexOf("-----") >= 0)
      check(html.indexOf("<h") >= 0, "setext heading did not render a heading")
  }

  function checkQuoteContract() {
    var source = String(activeSource || "")
    if (!/^\s*>/m.test(source)) return
    var html = String(display.renderedHtml || "")
    check(html.indexOf('class="jotpin-quote"') >= 0,
      "blockquote fixture did not retain the quote surface")
    var word = source.indexOf("Markdown") >= 0 ? "Markdown" :
      source.indexOf("quoted") >= 0 ? "quoted" : ""
    if (word !== "") checkSourceRange(word, 0)
    var quoteLineBreak = source.indexOf("\n>")
    while (quoteLineBreak >= 0) {
      var lineEnd = source.indexOf("\n", quoteLineBreak + 1)
      if (lineEnd < 0) lineEnd = source.length
      var afterMarker = quoteLineBreak + 2
      while (afterMarker < lineEnd &&
          /[ >]/.test(source.charAt(afterMarker))) afterMarker++
      if (afterMarker < lineEnd) {
        var beforeLine = display.cursorRectangleForSource(
          Math.max(0, quoteLineBreak - 1))
        var afterLine = display.cursorRectangleForSource(afterMarker)
        check(validRect(beforeLine) && validRect(afterLine) &&
            Number(afterLine.y) > Number(beforeLine.y),
          "explicit quote source lines do not occupy distinct visual rows: " +
            JSON.stringify({before: beforeLine, after: afterLine}))
        break
      }
      quoteLineBreak = source.indexOf("\n>", quoteLineBreak + 2)
    }
    if (currentCase().name === "wrapped-quote") {
      var firstWord = display.cursorRectangleForSource(source.indexOf("one"))
      var lastWord = display.cursorRectangleForSource(source.indexOf("twelve"))
      check(validRect(firstWord) && validRect(lastWord) &&
          Number(lastWord.y) > Number(firstWord.y),
        "narrow quote content did not wrap onto a later visual row")
    }
    if (currentCase().name === "quote-mouse-hit") {
      var quoteTableCount = html.split('class="jotpin-quote"').length - 1
      check(quoteTableCount === 1 &&
          html.indexOf('rowspan="2"') >= 0 &&
          html.indexOf('padding-top:JOTPIN_QUOTE_GAPpx') >= 0,
        "nested quote does not share one flattened layout table: " +
          JSON.stringify({quoteTables: quoteTableCount, html: html}))
      var outerText = display.cursorRectangleForSource(
        source.indexOf("Markdown is a lightweight"))
      var outerLastLine = display.cursorRectangleForSource(
        source.indexOf("Swartz."))
      var nestedText = display.cursorRectangleForSource(
        source.indexOf("Markdown is often used"))
      check(validRect(outerText) && validRect(outerLastLine) &&
          validRect(nestedText) &&
          Number(nestedText.x) > Number(outerText.x) + 8 &&
          Number(nestedText.y) > Number(outerLastLine.y) +
            Number(outerLastLine.height) + 3,
        "nested quote text is not indented and vertically separated " +
          "from its parent: " +
          JSON.stringify({outer: outerText, nested: nestedText}))
      var rails = Array.isArray(display.quoteRailRects)
        ? display.quoteRailRects.slice() : []
      rails.sort(function(left, right) {
        return Number(left.depth) - Number(right.depth)
      })
      var outerRail = rails.length > 0 ? rails[0] : null
      var nestedRail = rails.length > 1 ? rails[1] : null
      check(rails.length === 2 && outerRail && nestedRail &&
          Number(nestedRail.x) > Number(outerRail.x) + 8 &&
          Number(nestedRail.y) >= Number(outerRail.y) &&
          Number(outerRail.y) + Number(outerRail.height) >=
            Number(nestedRail.y) + Number(nestedRail.height) &&
          Number(outerRail.height) > Number(nestedRail.height),
        "nested quote rails are not continuous and properly nested: " +
          JSON.stringify(rails))
    }
  }

  function checkFenceContract() {
    var source = String(activeSource || "")
    if (source.indexOf("```") < 0 && source.indexOf("~~~") < 0) return
    check(Array.isArray(display.codeBlocks), "codeBlocks is not an array")
    check(String(display.renderedHtml || "").indexOf(
      'class="jotpin-code-block"') >= 0,
      "fenced code did not render a code card")
    var lines = source.split(/\r?\n/)
    for (var index = 1; index < lines.length; index++) {
      if (lines[index] === "" || /^\s*(```|~~~)/.test(lines[index])) continue
      var position = source.indexOf(lines[index])
      if (position < 0) continue
      check(validRect(display.cursorRectangleForSource(position)),
        "fenced code line has no caret geometry: " + index)
      break
    }
    if (display.codeBlocks.length > 0) {
    check(String(display.documentPlainText || "").indexOf(
        String(display.codeBlocks[0].code || "").split("\n")[0]) >= 0,
        "native document lost fenced code text")
      var firstCode = display.codeBlocks[0]
      var languageStart = Number(firstCode.languageStart)
      var languageEnd = Number(firstCode.languageEnd)
      var codeStart = Number(firstCode.codeStart)
      if (String(firstCode.language || "") !== "") {
        check(languageStart >= 0 && languageEnd > languageStart &&
          source.slice(languageStart, languageEnd) ===
            String(firstCode.language),
          "fence language metadata does not cover its exact source token: " +
          JSON.stringify({block: firstCode, sourceSlice: source.slice(
            languageStart, languageEnd)}))
      }
      check(codeStart >= 0 && codeStart <= source.length,
        "fence code metadata has an invalid source start: " + codeStart)
    }
    if (currentCase().name === "adjacent-highlighted-code-blocks")
      check(display.codeBlocks.length === 2 &&
          String(display.codeBlocks[0].language) === "javascript" &&
          String(display.codeBlocks[1].language) === "python",
        "adjacent fences did not retain independent language definitions")
    if (currentCase().name === "empty-fence-language-slot") {
      var languageInsertion = source.indexOf("```") + 3
      var placeholderDocument = String(display.documentPlainText || "")
        .indexOf("Language")
      var placeholderCaret = display.cursorRectangleForSource(
        languageInsertion)
      check(languageStart === languageInsertion &&
          languageEnd === languageInsertion,
        "an empty fence does not expose its language insertion point: " +
          JSON.stringify(firstCode))
      check(placeholderDocument >= 0 && validRect(placeholderCaret) &&
          Number(display.documentPositionForSource(languageInsertion)) ===
            placeholderDocument,
        "an empty fence has no visible language placeholder caret: " +
          JSON.stringify({plainText: display.documentPlainText,
            caret: placeholderCaret, document: display.documentPositionForSource(
              languageInsertion)}))
      if (validRect(placeholderCaret)) {
        var placeholderCenter = rectCenter(placeholderCaret)
        check(Number(display.sourcePositionForPoint(
            placeholderCenter.x, placeholderCenter.y)) === languageInsertion,
          "clicking an empty fence language slot does not return its source " +
            "insertion point")
      }
    }
    if (currentCase().name === "empty-code-row-after-language") {
      var languageRowCaret = display.cursorRectangleForSource(languageEnd)
      var emptyCodeRowCaret = display.cursorRectangleForSource(codeStart)
      check(validRect(languageRowCaret) && validRect(emptyCodeRowCaret) &&
          Number(emptyCodeRowCaret.y) > Number(languageRowCaret.y),
        "one Enter after a fence language has no visible empty code row: " +
          JSON.stringify({language: languageRowCaret, code: emptyCodeRowCaret,
            codeStart: codeStart, document: display.documentPositionForSource(
              codeStart), plainText: display.documentPlainText}))
    }
    if (currentCase().name === "fenced-code-last-line-caret") {
      var firstCodeRow = display.cursorRectangleForSource(source.indexOf("st\n"))
      var finalCodeRow = display.cursorRectangleForSource(source.indexOf("fvff"))
      check(validRect(firstCodeRow) && validRect(finalCodeRow) &&
          Number(finalCodeRow.y) > Number(firstCodeRow.y),
        "final fenced-code source row did not retain later caret geometry")
    }
    if (currentCase().name === "fenced-code-escape-row") {
      var codeCaret = display.cursorRectangleForSource(source.indexOf("code"))
      var escapeCaret = display.cursorRectangleForSource(source.length)
      check(validRect(codeCaret) && validRect(escapeCaret) &&
          Number(escapeCaret.y) > Number(codeCaret.y),
        "source row after a closing fence is not independently editable")
    }
    if (currentCase().name === "fenced-code-trailing-space-row") {
      var priorRow = display.cursorRectangleForSource(source.indexOf("fvff"))
      var spaceRow = display.cursorRectangleForSource(
        source.indexOf("\n \n") + 2)
      check(validRect(priorRow) && validRect(spaceRow) &&
          Number(spaceRow.y) > Number(priorRow.y),
        "trailing whitespace-only code row has no distinct caret row: " +
        JSON.stringify({priorRow: priorRow, spaceRow: spaceRow,
          priorDocument: display.documentPositionForSource(
            source.indexOf("fvff")),
          spaceDocument: display.documentPositionForSource(
            source.indexOf("\n \n") + 2),
          plainText: String(display.documentPlainText || "")}))
      if (validRect(spaceRow)) check(Number(display.sourcePositionForPoint(
          Number(spaceRow.x), Number(spaceRow.y) + Number(spaceRow.height) / 2))
          === source.indexOf("\n \n") + 2,
        "whitespace-only code row does not map back to its source column")
    }
  }

  function checkLanguageContract() {
    var source = String(activeSource || "")
    var opening = source.indexOf("```")
    if (opening < 0) return
    var lineEnd = source.indexOf("\n", opening)
    if (lineEnd < 0) lineEnd = source.length
    var line = source.slice(opening, lineEnd)
    var match = /^ {0,3}`{3,}([^\r\n]*)/.exec(line)
    if (!match || String(match[1]).trim() === "") return
    var token = String(match[1]).trim().split(/\s+/)[0]
    var start = opening + line.indexOf(token)
    var previousX = -1
    var mappedFailures = []
    for (var offset = 0; offset <= token.length; offset++) {
      var caret = display.cursorRectangleForSource(start + offset)
      if (!validRect(caret)) {
        mappedFailures.push({offset: offset, reason: "missing-caret"})
        continue
      }
      if (previousX >= 0 && Number(caret.x) <= previousX)
        mappedFailures.push({offset: offset, reason: "non-increasing-x", caret: caret})
      previousX = Number(caret.x)
      if (offset < token.length) {
        var center = rectCenter(caret)
        var mapped = Number(display.sourcePositionForPoint(center.x, center.y))
        if (!finite(mapped) || mapped < start || mapped > start + token.length)
          mappedFailures.push({offset: offset, mapped: mapped})
      }
    }
    check(mappedFailures.length === 0,
      "rendered language label does not map to every source token column: " +
      JSON.stringify(mappedFailures.slice(0, 8)))
  }

  function checkListContract() {
    var source = String(activeSource || "")
    if (!/^\s*(?:[-+*]|\d+[.)])\s/m.test(source)) return
    var html = String(display.renderedHtml || "")
    check(html.indexOf("jotpin-list") >= 0, "list fixture did not render list content")
    var firstText = source.match(/(?:[-+*]|\d+[.)])\s+(?:\[[ xX]\]\s+)?([^\n]*)/)
    if (firstText && firstText[1]) checkSourceRange(firstText[1].split(/\s+/)[0], 0)
    var target = display.cursorTargetForSource(0)
    check(String(target.blockType || "") === "list" ||
      source.indexOf("text\n-") >= 0,
      "list source position did not resolve to a list block")
    if (currentCase().name === "new-empty-bullet-caret") {
      var preceding = display.cursorRectangleForSource(
        source.indexOf("item") + 4)
      var emptyBullet = display.cursorRectangleForSource(source.length)
      check(validRect(preceding) && validRect(emptyBullet) &&
          Number(emptyBullet.y) > Number(preceding.y),
        "a newly completed empty bullet keeps its caret below the preceding line: " +
          JSON.stringify({preceding: preceding, bullet: emptyBullet}))
    }
    if (currentCase().emptyBulletBeforeExisting === true) {
      var markerStart = source.indexOf("\n- ") + 1
      var prior = display.cursorRectangleForSource(markerStart - 1)
      var inserted = display.cursorRectangleForSource(markerStart + 2)
      var existingToken = String(currentCase().existingToken || "existing")
      var existing = display.cursorRectangleForSource(
        source.indexOf(existingToken))
      check(validRect(prior) && validRect(inserted) && validRect(existing) &&
          Number(inserted.y) > Number(prior.y) &&
          Number(inserted.y) < Number(existing.y),
        "an inserted empty bullet keeps its own caret row before an existing item: " +
          JSON.stringify({prior: prior, inserted: inserted, existing: existing}))
    }
    if (Number(currentCase().expectedBulletCount) > 0) {
      var plain = String(display.documentPlainText || "")
      var bulletCount = (plain.match(/• /g) || []).length
      check(bulletCount === Number(currentCase().expectedBulletCount),
        "the authoritative document lost an empty list marker: " +
          JSON.stringify({document: plain, count: bulletCount,
            expected: currentCase().expectedBulletCount,
            html: display.renderedHtml}))
    }
    if (currentCase().wrappedListEndBeforeExisting === true) {
      var firstLineEnd = source.indexOf("\n")
      var endCaret = display.cursorRectangleForSource(firstLineEnd)
      var mappedEnd = validRect(endCaret)
        ? display.sourcePositionForPoint(Number(endCaret.x) + 0.25,
            Number(endCaret.y) + Number(endCaret.height) / 2)
        : -1
      check(validRect(endCaret) && Number(mappedEnd) === firstLineEnd,
        "clicking the visible end of a wrapped item maps before the next item: " +
          JSON.stringify({lineEnd: firstLineEnd, caret: endCaret,
            mapped: mappedEnd}))
    }
    if (String(currentCase().wrappedListToken || "")) {
      var itemStart = source.indexOf(String(currentCase().wrappedListToken))
      var firstCaret = itemStart >= 0
        ? display.cursorRectangleForSource(itemStart) : null
      var wrappedCaret = null
      if (validRect(firstCaret)) {
        for (var sourcePosition = itemStart + 1;
            sourcePosition <= source.length; sourcePosition++) {
          var candidate = display.cursorRectangleForSource(sourcePosition)
          if (validRect(candidate) &&
              Number(candidate.y) > Number(firstCaret.y) + 1) {
            wrappedCaret = candidate
            break
          }
        }
      }
      check(validRect(firstCaret) && validRect(wrappedCaret) &&
          Math.abs(Number(wrappedCaret.x) - Number(firstCaret.x)) <= 2,
        "a wrapped list continuation aligns with the first item text column: " +
          JSON.stringify({first: firstCaret, wrapped: wrappedCaret}))
    }
    if (/\[[ xX]\]/.test(source)) {
      check(html.indexOf("☐") >= 0 || html.indexOf("☑") >= 0,
        "task fixture lost checkbox glyph")
      check(html.indexOf("jotpin-task-list-item") >= 0,
        "task fixture lost task-list class")
      check(Array.isArray(display.taskCheckboxRects) &&
          display.taskCheckboxRects.length > 0,
        "task fixture lost native checkbox control geometry")
      var taskLineStart = source.search(/^[ \t]*(?:[-+*]|\d+[.)])[ \t]+\[[ xX]\]/m)
      if (taskLineStart >= 0) {
        var content = source.indexOf("]", taskLineStart) + 1
        while (content < source.length && /[ \t]/.test(source.charAt(content))) content++
        var caret = display.cursorRectangleForSource(content)
        var control = display.taskCheckboxRects.length > 0
          ? display.taskCheckboxRects[0] : null
        if (validRect(caret) && control) {
          var markerLeft = Number(control.hitX)
          var markerRight = markerLeft + Number(control.hitWidth)
          var markerY = Number(control.hitY) + Number(control.hitHeight) / 2
          var marker = display.taskSourceAtPoint(
            (markerLeft + markerRight) / 2, markerY, content)
          check(Number(marker) === taskLineStart,
            "task marker hit did not resolve to its source line: " + marker)
          check(Number(display.taskCheckboxSourceAtPoint(
              markerLeft - 1, markerY)) === -1 &&
            Number(display.taskCheckboxSourceAtPoint(
              markerRight + 1, markerY)) === -1,
            "task marker hit boundary leaked outside its checkbox column")
        }
      }
    }
  }

  function checkTableContract() {
    var source = String(activeSource || "")
    if (source.indexOf("|") < 0) return
    var html = String(display.renderedHtml || "")
    check(html.indexOf("<table") >= 0, "table fixture did not render a table")
    if (source.indexOf(":---") >= 0 || source.indexOf("---:") >= 0)
      check(html.indexOf("align=") >= 0 || html.indexOf("text-align") >= 0,
        "table alignment markers were not represented")
    var tokens = ["A", "B", "column-a", "cell-alpha", "wrapped"]
    for (var index = 0; index < tokens.length; index++)
      if (source.indexOf(tokens[index]) >= 0) checkSourceRange(tokens[index], 0)
  }

  function checkWhitespaceAndSpecialContract() {
    var source = String(activeSource || "")
    if (/ {2,}|\t|\r\n|^\s*$/m.test(source)) checkCaretCoverage()
    if (source.indexOf("<tag>") >= 0)
      check(String(display.renderedHtml || "").indexOf("<tag>") < 0 &&
          String(display.documentPlainText || "").indexOf("<tag>") >= 0,
        "HTML-looking source text was not escaped")
    if (source.indexOf("\r\n") >= 0)
      check(display.layoutSourceText === source,
        "CRLF source was normalized instead of preserved")
  }

  function checkBlankAndWhitespaceRows() {
    var name = currentCase().name
    var source = String(activeSource || "")
    if (name === "trailing-newline") {
      var textRow = display.cursorRectangleForSource(0)
      var trailingRow = display.cursorRectangleForSource(source.length)
      check(validRect(textRow) && validRect(trailingRow) &&
          Number(trailingRow.y) > Number(textRow.y),
        "trailing newline does not expose a later editable row")
    }
    if (name === "leading-and-multiple-blank-lines") {
      var starts = [0, 1, 7, 8, 13, 14]
      var previousY = -1
      for (var index = 0; index < starts.length; index++) {
        var caret = display.cursorRectangleForSource(starts[index])
        check(validRect(caret) &&
            (previousY < 0 || Number(caret.y) > previousY),
          "consecutive blank/source rows collapse at position " +
            starts[index] + ": " + JSON.stringify(caret))
        if (validRect(caret)) previousY = Number(caret.y)
      }
    }
    if (name === "whitespace-only-row") {
      var whitespace = display.cursorRectangleForSource(source.indexOf("    "))
      var following = display.cursorRectangleForSource(source.indexOf("its better"))
      check(validRect(whitespace) && validRect(following) &&
          Number(following.y) > Number(whitespace.y),
        "whitespace-only source row is not independently editable")
    }
    if (name === "heading-trailing-empty-row") {
      var firstBlank = display.cursorRectangleForSource(source.indexOf("\n") + 1)
      var finalBlank = display.cursorRectangleForSource(source.length)
      check(validRect(firstBlank) && validRect(finalBlank) &&
          Number(finalBlank.y) > Number(firstBlank.y),
        "multiple blank rows after a heading collapse together")
    }
    if (name === "final-line-bottom-padding") {
      var firstLineCaret = display.cursorRectangleForSource(
        source.indexOf("Inline code"))
      var finalLineCaret = display.cursorRectangleForSource(source.length)
      var bottomGap = Number(display.implicitHeight) -
        (Number(finalLineCaret.y) + Number(finalLineCaret.height))
      check(validRect(firstLineCaret) && validRect(finalLineCaret) &&
          Number(firstLineCaret.y) >= Number(display.verticalPadding) - 1 &&
          bottomGap >= Number(display.verticalPadding) - 1,
        "the final rendered line has the same full edge padding as the first: " +
          JSON.stringify({first: firstLineCaret, final: finalLineCaret,
            implicitHeight: display.implicitHeight, bottomGap: bottomGap,
            padding: display.verticalPadding}))
    }
    if (name === "blank-lines-before-fenced-code-selection") {
      var firstBlankStart = source.indexOf("\n") + 1
      var secondBlankStart = firstBlankStart + 1
      var codeStart = source.indexOf("```")
      var firstBlankCaret = display.cursorRectangleForSource(firstBlankStart)
      var secondBlankCaret = display.cursorRectangleForSource(secondBlankStart)
      var codeCaret = display.cursorRectangleForSource(codeStart)
      check(validRect(firstBlankCaret) && validRect(secondBlankCaret) &&
          validRect(codeCaret) &&
          Number(firstBlankCaret.y) < Number(secondBlankCaret.y) &&
          Number(secondBlankCaret.y) < Number(codeCaret.y),
        "both blank rows retain distinct caret geometry before the code card")
      var firstBlankSelection = display.sourceRangeRectangles(
        firstBlankStart, secondBlankStart)
      var secondBlankSelection = display.sourceRangeRectangles(
        secondBlankStart, codeStart)
      var visibleBreakWidth = Math.max(4,
        Number(display.cursorWidth(" ", display.fontFamily)) * 0.75)
      check(firstBlankSelection.length === 1 &&
          secondBlankSelection.length === 1 &&
          Number(firstBlankSelection[0].width) >= visibleBreakWidth &&
          Number(secondBlankSelection[0].width) >= visibleBreakWidth &&
          Number(firstBlankSelection[0].y) <
            Number(secondBlankSelection[0].y),
        "each selected blank newline paints a visible character-width block: " +
          JSON.stringify({first: firstBlankSelection,
            second: secondBlankSelection,
            minimumWidth: visibleBreakWidth}))
    }
    if (name === "trailing-whitespace-columns") {
      var rowStart = source.lastIndexOf("ba") + 2
      var beforeSpaces = display.cursorRectangleForSource(rowStart)
      var afterSpaces = display.cursorRectangleForSource(source.length)
      check(validRect(beforeSpaces) && validRect(afterSpaces) &&
          Number(afterSpaces.x) > Number(beforeSpaces.x),
        "trailing spaces do not retain editable horizontal columns")
      if (validRect(afterSpaces)) check(Number(display.sourcePositionForPoint(
          Number(afterSpaces.x), Number(afterSpaces.y) +
            Number(afterSpaces.height) / 2)) === source.length,
        "trailing-space caret does not map back to the final source column")
    }
    if (name === "internal-tab-spaces" ||
        name === "empty-bullet-whitespace" ||
        name === "empty-bullet-more-whitespace") {
      var leftPosition = name === "internal-tab-spaces" ? 2 : 1
      var rightPosition = source.length
      var left = display.cursorRectangleForSource(leftPosition)
      var right = display.cursorRectangleForSource(rightPosition)
      check(validRect(left) && validRect(right) && Number(right.x) > Number(left.x),
        "internal separator spaces do not retain editable columns")
      if (validRect(right)) check(Number(display.sourcePositionForPoint(
          Number(right.x), Number(right.y) + Number(right.height) / 2)) ===
            rightPosition,
        "separator-space caret does not map back to its source column")
    }
  }

  function checkFocusedContracts() {
    var name = currentCase().name
    if (name.indexOf("inline") >= 0 || name === "matched-emphasis-caret" ||
        name === "commonmark-inline-basics" || name === "html5-entities")
      checkInlineContract()
    if (name.indexOf("link") >= 0 || name.indexOf("reference") >= 0)
      checkLinkContract()
    if (name.indexOf("image") >= 0) checkImageContract()
    if (name.indexOf("heading") >= 0 || name.indexOf("atx") >= 0 ||
        name.indexOf("setext") >= 0 || name === "preview-heading-separator-completed")
      checkHeadingContract()
    if (name.indexOf("quote") >= 0) checkQuoteContract()
    if (name.indexOf("code") >= 0 || name.indexOf("fenced") >= 0 ||
        name.indexOf("dart") >= 0 || name.indexOf("language") >= 0)
      checkFenceContract()
    if (name.indexOf("language") >= 0) checkLanguageContract()
    if (name.indexOf("list") >= 0 || name.indexOf("bullet") >= 0 ||
        name === "ordered-list" || name === "nested-list")
      checkListContract()
    if (name.indexOf("table") >= 0) checkTableContract()
    if (name.indexOf("wrapped") >= 0 || name.indexOf("selection") >= 0 ||
        name.indexOf("whitespace") >= 0 || name.indexOf("crlf") >= 0 ||
        name.indexOf("special") >= 0)
    checkWhitespaceAndSpecialContract()
    checkBlankAndWhitespaceRows()
    if (name === "inline-markdown" || name === "quote-mouse-hit" ||
        name === "wrapped-paragraph-mouse-hit" || name === "code-language-mouse-hit")
      checkClickContract()
  }

  function checkCase() {
    var spec = currentCase()
    var metrics = display.layoutMetricsForTests()
    var expected = phase === 1 && spec.editedExpectedTypes
      ? spec.editedExpectedTypes : spec.expectedTypes
    check(display.sourceText === activeSource,
      "canonical sourceText changed during rendering")
    check(display.layoutSourceText === activeSource,
      "layoutSourceText is stale")
    check(display.layoutReady && display.layoutMatchesCurrentInput(),
      "layout did not settle on the current source")
    check(display.sourceToDocument.length === activeSource.length + 1,
      "source/document mapping does not cover every source boundary")
    checkMetrics(metrics, expected)
    checkCaretCoverage()
    checkPointRoundTrips()
    checkSelectionGeometry()
    checkSourceNavigation()
      if (phase === 0) checkFocusedContracts()

    if (phase === 0 && spec.editedSource !== undefined) {
      beforeMetrics = metrics.map(function(metric) {
        return {y: Number(metric.y), height: Number(metric.height)}
      })
      beforeSource = activeSource
      beforeCursor = activeCursor
      beforeOptimisticEditCount = Number(display.optimisticEditCount)
      phase = 1
      activeSource = String(spec.editedSource)
      activeCursor = spec.editedCursor !== undefined
        ? Number(spec.editedCursor) : activeSource.length
      activeSelectionStart = 0
      activeSelectionEnd = 0
      settleAttempts = 0
      settleTimer.restart()
      return
    }

    if (phase === 1 && spec.editedSource !== undefined) {
      check(activeSource === String(spec.editedSource),
        "edited source was not installed")
      var changed = Number(spec.changedBlockIndex)
      if (!finite(changed)) changed = 0
      for (var index = 0; index < metrics.length && index < beforeMetrics.length;
           index++) {
        if (index === changed) continue
        check(Math.abs(Number(metrics[index].y) - beforeMetrics[index].y) < 2.5,
          "unaffected block moved after edit: " + index)
      }
      check(validRect(display.cursorRectangleForSource(activeCursor)),
        "edited source cursor has no geometry")
      if (spec.noOptimisticEdit === true)
        check(Number(display.optimisticEditCount) ===
            beforeOptimisticEditCount,
          "a structural list marker was painted as optimistic plain text: " +
            JSON.stringify({before: beforeOptimisticEditCount,
              after: display.optimisticEditCount}))
    }

    ranCases.push(spec.name)
    console.log("NATIVE_PARITY_CASE: " + JSON.stringify({
      name: spec.name, phase: phase, sourceLength: activeSource.length,
      metrics: metrics.length, layoutRevision: display.layoutRevision,
      parseDispatches: display.parseDispatchCount,
      parseCompletions: display.parseCompletionCount,
      failures: failures.filter(function(value) {
        return value.indexOf("case " + spec.name + ":") === 0
      }).length
    }))
    phase = 0
    advanceCase()
  }

  function loadCase() {
    var spec = currentCase()
    var source = String(spec.source || "")
    var cursor = spec.cursor !== undefined ? Number(spec.cursor) : source.length
    if (!finite(cursor) || cursor < 0) cursor = source.length
    if (spec.cursorToken !== undefined) {
      var tokenPosition = source.indexOf(String(spec.cursorToken))
      if (tokenPosition >= 0) cursor = tokenPosition
    }
    if (spec.cursorTokenEnd !== undefined) {
      var tokenEnd = source.indexOf(String(spec.cursorTokenEnd))
      if (tokenEnd >= 0) cursor = tokenEnd + String(spec.cursorTokenEnd).length
    }
    activeSource = source
    activeCursor = Math.max(0, Math.min(source.length,
      spec.editedCursor !== undefined && phase === 1 ? Number(spec.editedCursor) : cursor))
    activeSelectionStart = spec.selectAll ? 0 : Number(spec.selectionStart || 0)
    activeSelectionEnd = spec.selectAll ? source.length : Number(spec.selectionEnd || 0)
    activeWidth = Number(spec.width || 720)
    settleAttempts = 0
    settleTimer.restart()
  }

  function advanceCase() {
    caseIndex++
    if (caseIndex >= cases.length) {
      var expectedNames = cases.map(function(spec) { return spec.name })
      var missingNames = expectedNames.filter(function(name) {
        return ranCases.indexOf(name) < 0
      })
      check(missingNames.length === 0,
        "expected cases did not run: " + JSON.stringify(missingNames))
      console.log("NATIVE_PARITY_SUMMARY: " + JSON.stringify({
        schemaVersion: 1, expectedCaseCount: expectedNames.length,
        ranCaseCount: ranCases.length, missingCases: missingNames,
        failures: failures
      }))
      finalExitCode = failures.length === 0 && missingNames.length === 0
        ? 0 : 1
      // Destroy asynchronous image probes before the disposable QML engine
      // exits; otherwise Qt may tear down an image job after QCoreApplication.
      displayLoader.active = false
      cleanExitTimer.start()
      return
    }
    loadCase()
  }

  Timer {
    id: settleTimer
    interval: 2
    repeat: true
    onTriggered: {
      shell.settleAttempts++
      var current = shell.currentCase()
      var expectedSource = shell.activeSource
      if (display.layoutReady && display.layoutSourceText === expectedSource &&
          Number(display.layoutCursorPosition) === Number(shell.activeCursor) &&
          !display.parseInFlight && !display.parsePending &&
          Number(display.pendingStyledReconcileRequestId) < 0 &&
          Number(display.codeHighlightPendingCount) === 0) {
        stop()
        shell.checkCase()
      } else if (shell.settleAttempts >= 500) {
        stop()
        shell.fail("layout did not settle: " + JSON.stringify({
          expected: expectedSource.length,
          actual: String(display.layoutSourceText || "").length,
          ready: display.layoutReady, parseInFlight: display.parseInFlight,
          parsePending: display.parsePending,
          pendingStyledReconcileRequestId:
            display.pendingStyledReconcileRequestId,
          codeHighlightPendingCount: display.codeHighlightPendingCount,
          case: current.name
        }))
        shell.phase = 0
        shell.advanceCase()
      }
    }
  }

  Component.onCompleted: {
    cases = buildCases()
    advanceCase()
  }
}
