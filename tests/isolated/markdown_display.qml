import QtQuick
import QtQuick.Window
import Quickshell
import "./jotpin" as JotPin

// This is intentionally a Quickshell process, not qmlscene. The test runner
// starts it with QT_QPA_PLATFORM=offscreen, so no Wayland surface or desktop
// focus is involved. Each case exercises the actual MarkdownDisplay QML
// component against a different source shape instead of a one-off screenshot.
ShellRoot {
  id: shell

  property var failures: []
  property int caseIndex: 0
  property int settleAttempts: 0
  property string activeSource: ""
  property int activeCursor: 0
  property int activeSelectionStart: 0
  property int activeSelectionEnd: 0
  property int activeWidth: 720
  property string captureDirectory: Quickshell.env("JOTPIN_CAPTURE_DIR")
  property string imageBaseUrl: Quickshell.env("JOTPIN_TEST_IMAGE_DIR") === ""
    ? ""
    : "file://" + Quickshell.env("JOTPIN_TEST_IMAGE_DIR") + "/"
  property var headingTrailingCaret: null
  property var headingTrailingMetrics: []
  property real previousEmptyBulletCaretX: -1
  property int selectionRequestCount: 0
  property int lastSelectionAnchor: -1
  property int lastSelectionPosition: -1
  property int previousInspectedSourceRevision: -1
  property int taskToggleStabilityPhase: 0
  property int taskToggleStableLayoutRevision: -1
  property var taskToggleStableMetrics: []
  property int editStabilityPhase: 0
  property int editStableLayoutRevision: -1
  property var editStableMetrics: []
  property var editStableCaret: null
  property string selectionPerformanceSource: {
    var paragraphs = []
    for (var index = 0; index < 40; index++) {
      paragraphs.push("Paragraph " + index +
        " has **bold Markdown** and enough ordinary words to wrap across " +
        "the editor while selection follows the pointer without delay.")
    }
    return paragraphs.join("\n\n")
  }
  property var selectionPerformanceTypes: {
    var types = []
    for (var index = 0; index < 40; index++) {
      if (index > 0) types.push("blank")
      types.push("paragraph")
    }
    return types
  }

  // Keep these fixtures small but deliberately awkward. They cover the
  // source boundaries that tend to expose stale layouts, missing caret rows,
  // incorrect list offsets, and selection rectangles that skip newlines.
  property var cases: [
    {
      name: "empty",
      source: "",
      expectedTypes: ["blank"]
    },
    {
      name: "trailing-newline",
      source: "alpha\n",
      expectedTypes: ["paragraph", "blank"]
    },
    {
      name: "leading-and-multiple-blank-lines",
      source: "\nalpha\n\nbeta\n\n",
      expectedTypes: ["blank", "paragraph", "blank", "paragraph", "blank", "blank"]
    },
    {
      name: "inline-markdown",
      source: "# Heading\n\n**bold** *italic* ~~del~~ `code` [link](https://example.com)\n",
      selectionStart: 11,
      selectionEnd: 41,
      expectedTypes: ["heading", "blank", "paragraph", "blank"]
    },
    {
      name: "literal-inline-markers",
      source: "alpha *\nfoo_bar_baz\nomega ~",
      expectedTypes: ["paragraph"]
    },
    {
      name: "matched-emphasis-caret",
      source: "**bold** tail",
      expectedTypes: ["paragraph"]
    },
    {
      name: "nested-multiline-emphasis",
      source: "***both*** and **bold *inner***\n*across\nlines*",
      expectedTypes: ["paragraph"]
    },
    {
      name: "commonmark-inline-basics",
      source: "\\*literal\\* &amp; &#x41; <https://example.com> <person@example.com> [relative](other.md)",
      expectedTypes: ["paragraph"]
    },
    {
      name: "html5-entities",
      source: "&copy; &eacute; &larr; &NotEqualTilde; &AMP; &#x1F600; &#0; &#xD800; &notanentity;",
      expectedTypes: ["paragraph"]
    },
    {
      name: "commonmark-link-compatibility",
      source: "[nested](docs/a_(b).md \"title\") [full][guide] [collapsed][] [shortcut] [**bold**](bold.md)\n\n[guide]: guide.md 'Guide title'\n[collapsed]: collapsed.md\n[shortcut]: shortcut.md",
      expectedTypes: ["paragraph", "blank", "blank", "blank", "blank"]
    },
    {
      name: "reference-projection-with-definition",
      source: "[label][id]\n\n[id]: target.md",
      expectedTypes: ["paragraph", "blank", "blank"]
    },
    {
      name: "reference-projection-without-definition",
      source: "[label][id]\n\n[other]: target.md",
      expectedTypes: ["paragraph", "blank", "blank"]
    },
    {
      name: "fenced-reference-definition",
      source: "```text\n[bad]: bad.md\n```\n[bad]",
      expectedTypes: ["code", "paragraph"]
    },
    {
      name: "reference-image",
      source: "![fixture][asset]\n[asset]: markdown-image.svg",
      expectedTypes: ["image", "blank"]
    },
    {
      name: "relative-image",
      source: "![fixture image](markdown-image.svg)",
      expectedTypes: ["image"]
    },
    {
      name: "image-caption-following-blocks",
      source: "![fixture image](markdown-image.svg)\n\n## Below image\nnext line",
      expectedTypes: ["image", "blank", "heading", "paragraph"]
    },
    {
      name: "inline-code-caret",
      source: "code `alpha` tail",
      expectedTypes: ["paragraph"]
    },
    {
      name: "setext-headings",
      source: "Title\n=====\n\nSubtitle\n-----",
      expectedTypes: ["heading", "blank", "heading"]
    },
    {
      name: "closing-atx-heading",
      source: "# Title #",
      expectedTypes: ["heading"]
    },
    {
      name: "preview-heading-backspace-literal",
      source: "####Watching movies and shows",
      cursor: 4,
      expectedTypes: ["paragraph"]
    },
    {
      name: "preview-heading-separator-completed",
      source: "#### Watching movies and shows",
      cursor: 5,
      expectedTypes: ["heading"]
    },
    {
      name: "quote-rule-code",
      source: "> quote\n> second\n\n---\n\n```dart\ncode\nsecond\n```",
      expectedTypes: ["quote", "blank", "rule", "blank", "code"]
    },
    {
      name: "quote-following-blank-heading",
      source: "> A fast, local Markdown scratchpad.\n\n## Make it yours",
      expectedTypes: ["quote", "blank", "heading"]
    },
    {
      name: "nested-quote-list-structure",
      source: "> - item\n>   - nested\n>\n> > deep quote",
      expectedTypes: ["quote"]
    },
    {
      name: "quote-mouse-hit",
      source: "> Markdown is a lightweight markup language\n> text-formatting syntax, created in 2004\n> with Aaron Swartz.\n>\n> > Markdown is often used to format readme files\n> writing messages in online discussion forums,\n> create rich text using a plain text editor.",
      width: 610,
      expectedTypes: ["quote"]
    },
    {
      name: "fenced-code-selection",
      source: "before\n\n```\ncode line\nsecond line\n```\n\nafter",
      selectAll: true,
      expectedTypes: ["paragraph", "blank", "code", "blank", "paragraph"]
    },
    {
      name: "dart-code-highlighting",
      source: "```dart\nvoid main() {\n  final answer = 42;\n  print(answer);\n}\n```",
      cursorTokenEnd: "answer",
      expectedTypes: ["code"]
    },
    {
      name: "adjacent-highlighted-code-blocks",
      source: "```javascript\nfunction test() {\n    return 'ahello';\n}\n```\n```python\nmessafe = \"Markdown stays simple.\"\nprint(message)\n```",
      expectedTypes: ["code", "code"]
    },
    {
      name: "code-language-mouse-hit",
      source: "```javascript\nfunction test() {\n    reutrn hello;\n}\n```",
      expectedTypes: ["code"]
    },
    {
      name: "partial-fence-language-caret",
      source: "```b\n```",
      cursorTokenEnd: "b",
      expectedTypes: ["code"]
    },
    {
      name: "fenced-code-last-line-caret",
      source: "```testtsets\n\nst\nststttt\nfvff\n```",
      cursorTokenEnd: "fvff",
      expectedTypes: ["code"]
    },
    {
      name: "unclosed-fenced-code",
      source: "```text\ncode to eof",
      expectedTypes: ["code"]
    },
    {
      name: "indented-fenced-code",
      source: "  ```text\n  alpha\n x\n    y\n  ```",
      expectedTypes: ["code"]
    },
    {
      name: "fenced-code-escape-row",
      source: "```text\ncode\n```\n",
      cursorTokenEnd: "code",
      expectedTypes: ["code", "blank"]
    },
    {
      name: "fenced-code-trailing-space-row",
      source: "```testtsets\nst\nststttt\nfsdfs\nfvff\n \n```",
      cursorTokenEnd: "fvff\n ",
      expectedTypes: ["code"]
    },
    {
      name: "wrapped-quote",
      source: "> one two three four five six seven eight nine ten eleven twelve",
      width: 230,
      expectedTypes: ["quote"]
    },
    {
      name: "wrapped-code",
      source: "```text\none two three four five six seven eight nine ten eleven twelve\n```",
      width: 230,
      expectedTypes: ["code"]
    },
    {
      name: "ordered-list",
      source: "1. first\n2. second",
      expectedTypes: ["list"]
    },
    {
      name: "task-list",
      source: "- [x] test\n- [ ] test\n- [ ] fsdaf",
      expectedTypes: ["list"]
    },
    {
      name: "task-list-toggle-stability",
      source: "- [x] first task\n- [ ] second task\n\nText below the tasks",
      expectedTypes: ["list", "blank", "paragraph"]
    },
    {
      name: "heading-edit-stability",
      source: "# Titl\n\nBody below the heading",
      editedSource: "# Title\n\nBody below the heading",
      changedBlockIndex: 0,
      expectedTypes: ["heading", "blank", "paragraph"]
    },
    {
      name: "paragraph-edit-stability",
      source: "Paragrap\n\nBody below the paragraph",
      editedSource: "Paragraph\n\nBody below the paragraph",
      changedBlockIndex: 0,
      expectedTypes: ["paragraph", "blank", "paragraph"]
    },
    {
      name: "blank-to-paragraph-edit-stability",
      source: "\n\nWatching movies",
      cursor: 0,
      editedSource: "test\n\nWatching movies",
      editedCursor: 4,
      changedBlockIndex: 0,
      expectedTypes: ["blank", "blank", "paragraph"],
      editedExpectedTypes: ["paragraph", "blank", "paragraph"]
    },
    {
      name: "inline-markdown-edit-stability",
      source: "Text with **bol** and `code`\n\nBody below the inline text",
      editedSource: "Text with **bold** and `code`\n\nBody below the inline text",
      changedBlockIndex: 0,
      expectedTypes: ["paragraph", "blank", "paragraph"]
    },
    {
      name: "list-edit-stability",
      source: "- Ite\n\nBody below the list",
      editedSource: "- Item\n\nBody below the list",
      changedBlockIndex: 0,
      expectedTypes: ["list", "blank", "paragraph"]
    },
    {
      name: "quote-edit-stability",
      source: "> Quot\n\nBody below the quote",
      editedSource: "> Quote\n\nBody below the quote",
      changedBlockIndex: 0,
      expectedTypes: ["quote", "blank", "paragraph"]
    },
    {
      name: "code-edit-stability",
      source: "```text\nprin\n```\n\nBody below the code",
      editedSource: "```text\nprint\n```\n\nBody below the code",
      changedBlockIndex: 0,
      expectedTypes: ["code", "blank", "paragraph"]
    },
    {
      name: "table-edit-stability",
      source: "| A | B |\n| --- | --- |\n| x | y |\n\nBody below the table",
      editedSource: "| A | B |\n| --- | --- |\n| z | y |\n\nBody below the table",
      changedBlockIndex: 0,
      expectedTypes: ["table", "blank", "paragraph"]
    },
    {
      name: "image-caption-edit-stability",
      source: "![captio](markdown-image.svg)\n\nBody below the image",
      editedSource: "![caption](markdown-image.svg)\n\nBody below the image",
      changedBlockIndex: 0,
      expectedTypes: ["image", "blank", "paragraph"]
    },
    {
      name: "nested-list",
      source: "- parent\n    - child\n      - deep\n- sibling",
      cursorToken: "child",
      expectedTypes: ["list"]
    },
    {
      name: "list-container-continuations",
      source: "- parent\n  continuation paragraph\n    > nested quote\n\n- sibling",
      expectedTypes: ["list"]
    },
    {
      name: "wrapped-list-item",
      source: "- one two three four five six seven eight nine ten eleven twelve",
      width: 230,
      expectedTypes: ["list"]
    },
    {
      name: "wrapped-list-test-note",
      source: "- We should create a welcome note for new users that explains what it is, what it does, what you can do. it should be concise and pretty and use markdown",
      width: 560,
      expectedTypes: ["list"]
    },
    {
      name: "table",
      source: "| Col | Value |\n| --- | --- |\n| A | B |",
      selectAll: true,
      expectedTypes: ["table"]
    },
    {
      name: "wrapped-table-cell",
      source: "| Col | Description |\n| --- | --- |\n| A | one two three four five six seven eight nine ten eleven twelve |",
      width: 230,
      expectedTypes: ["table"]
    },
    {
      name: "gfm-table-compatibility",
      source: "| Only\n| :---:\nvalue\n\n| Left | Right |\n| :--- | ---: |\n| \\| | `a|b` |\n| x | [go](https://a|b) |",
      expectedTypes: ["table", "blank", "table"]
    },
    {
      name: "wrapped-paragraph",
      source: "Hey! I created an account for you on my private media server.",
      width: 560,
      expectedTypes: ["paragraph"]
    },
    {
      name: "wrapped-inline-range",
      source: "prefix supercalifragilisticmispeling suffix",
      width: 150,
      expectedTypes: ["paragraph"]
    },
    {
      name: "wrapped-paragraph-mouse-hit",
      source: "This paragraph explains how clicking text should place the caret on the word should instead of keeping it on explains.",
      width: 260,
      expectedTypes: ["paragraph"]
    },
    {
      name: "explicit-paragraph-lines",
      source: "line one\nline two\nline three",
      selectionStart: 0,
      selectionEnd: 28,
      expectedTypes: ["paragraph"]
    },
    {
      name: "partial-selection-across-lines",
      source: "one two\nthree four\nfive six",
      selectionStart: 4,
      selectionEnd: 15,
      expectedTypes: ["paragraph"]
    },
    {
      name: "partial-selection-across-blocks",
      source: "one line\n\nsecond line\n\nthird line",
      selectionStart: 13,
      selectionEnd: 28,
      expectedTypes: ["paragraph", "blank", "paragraph", "blank", "paragraph"]
    },
    {
      name: "trailing-whitespace-columns",
      source: "asdf\nasdf    \nits better than ba                     ",
      expectedTypes: ["paragraph"]
    },
    {
      name: "internal-tab-spaces",
      source: "Em  phasis",
      cursor: 4,
      expectedTypes: ["paragraph"]
    },
    {
      name: "whitespace-only-row",
      source: "asdf\n    \nits better than ba",
      expectedTypes: ["paragraph", "blank", "paragraph"]
    },
    {
      name: "heading-trailing-empty-row",
      source: "# this is a header:\n\n",
      expectedTypes: ["heading", "blank", "blank"]
    },
    {
      name: "heading-paragraph-gap",
      source: "# this is a header:\n\ntyping",
      expectedTypes: ["heading", "blank", "paragraph"]
    },
    {
      name: "empty-bullet-whitespace",
      source: "-  ",
      cursor: 3,
      expectedTypes: ["list"]
    },
    {
      name: "empty-bullet-more-whitespace",
      source: "-     ",
      cursor: 6,
      expectedTypes: ["list"]
    },
    {
      name: "active-incomplete-list-marker",
      source: "text\n-",
      expectedTypes: ["paragraph", "list"]
    },
    {
      name: "special-characters",
      source: "<tag> & value _under_",
      expectedTypes: ["paragraph"]
    },
    {
      name: "crlf-source",
      source: "alpha\r\n- item\r\nsecond",
      expectedTypes: ["paragraph", "list", "paragraph"]
    },
    {
      name: "crlf-quote-table",
      source: "> one\r\n> two\r\n\r\n| A | B |\r\n| --- | --- |\r\n| x | y |",
      expectedTypes: ["quote", "blank", "table"]
    },
    {
      name: "selection-across-rows",
      source: "alpha\n\n- one\n- two\n\nbeta",
      selectAll: true,
      expectedTypes: ["paragraph", "blank", "list", "blank", "paragraph"]
    },
    {
      name: "partial-selection",
      source: "alpha\nbeta\ngamma",
      selectionStart: 1,
      selectionEnd: 3,
      expectedTypes: ["paragraph"]
    },
    {
      name: "selection-performance",
      source: shell.selectionPerformanceSource,
      expectedTypes: shell.selectionPerformanceTypes
    }
  ]

  Window {
    id: testWindow
    width: shell.activeWidth
    height: 900
    visible: true
    color: "#101322"

    Item {
      id: captureSurface
      width: testWindow.width
      height: Math.max(1, display.implicitHeight)

      Rectangle {
        anchors.fill: parent
        color: "#101322"
      }

      JotPin.MarkdownDisplay {
        id: display
        anchors.fill: parent
        foreground: "#f0d0b0"
        background: "#101322"
        accent: "#b5a3ff"
        fontFamily: "monospace"
        bodyPixelSize: 16
        bodyCaretHeight: 16
        sourceText: shell.activeSource
        cursorPosition: shell.activeCursor
        selectionStart: shell.activeSelectionStart
        selectionEnd: shell.activeSelectionEnd
        selectionFill: "#806c78"
        baseUrl: shell.imageBaseUrl
        onSourceSelectionRequested: function(anchorPosition, sourcePosition) {
          shell.selectionRequestCount++
          shell.lastSelectionAnchor = anchorPosition
          shell.lastSelectionPosition = sourcePosition
        }
      }
    }
  }

  Timer {
    id: settleTimer
    interval: 120
    repeat: false
    onTriggered: shell.inspectCase()
  }

  function currentCase() {
    return cases[caseIndex]
  }

  function check(condition, message) {
    if (condition) return
    failures.push("case " + currentCase().name + ": " + message)
    console.log("ISOLATED_FAIL: case " + currentCase().name + ": " + message)
  }

  function linearSourceOffsetForColumn(source, target, quoteMode) {
    var best = 0
    for (var offset = 0; offset <= source.length; offset++) {
      var length = quoteMode
        ? display.quotePlainPrefix(source, offset).length
        : display.plainInlinePrefix(source, offset).length
      if (length > target) break
      best = offset
    }
    return best
  }

  function fastSourceMappingsMatchLinear() {
    var samples = [
      "plain  text with repeated spaces",
      "**bold** and _italic_ plus `code span`",
      "[link label](https://example.test) after",
      "> quoted **text**\n> second line"
    ]
    for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
      var source = samples[sampleIndex]
      for (var quoteMode = 0; quoteMode <= 1; quoteMode++) {
        var visibleLength = quoteMode
          ? display.quotePlainPrefix(source, source.length).length
          : display.plainInlinePrefix(source, source.length).length
        for (var column = 0; column <= visibleLength; column++) {
          if (display.sourceOffsetForVisibleColumn(
              source, column, Boolean(quoteMode)) !==
              linearSourceOffsetForColumn(
                source, column, Boolean(quoteMode))) return false
        }
      }
    }
    return true
  }

  function cachedProjectionsMatchCold() {
    var samples = [
      "plain text",
      "**bold** and _italic_ plus ~~strike~~",
      "[link](https://example.test) after",
      "` code ` and ``two``",
      "\\*escaped\\* &amp; &#x41;",
      "hard break  \nnext",
      "crlf\r\nsource"
    ]
    for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
      var source = samples[sampleIndex]
      var cold = []
      for (var position = 0; position <= source.length; position++) {
        display.resetPlainInlineProjectionCache()
        cold.push(display.plainInlinePrefix(source, position))
      }
      display.resetPlainInlineProjectionCache()
      for (position = source.length; position >= 0; position--) {
        if (display.plainInlinePrefix(source, position) !== cold[position])
          return false
      }
    }

    var quote = "> quoted **text**\r\n> second `row`"
    var coldQuote = []
    for (var quotePosition = 0; quotePosition <= quote.length;
         quotePosition++) {
      display.resetPlainInlineProjectionCache()
      coldQuote.push(display.quotePlainPrefix(quote, quotePosition))
    }
    display.resetPlainInlineProjectionCache()
    for (quotePosition = quote.length; quotePosition >= 0; quotePosition--) {
      if (display.quotePlainPrefix(quote, quotePosition) !==
          coldQuote[quotePosition]) return false
    }
    return true
  }

  function validRect(rect) {
    return rect !== null && rect !== undefined &&
      isFinite(Number(rect.x)) && isFinite(Number(rect.y)) &&
      isFinite(Number(rect.width)) && isFinite(Number(rect.height)) &&
      Number(rect.width) > 0 && Number(rect.height) > 0
  }

  function actualTypes(metrics) {
    var types = []
    for (var index = 0; index < metrics.length; index++) {
      types.push(String(metrics[index].type || ""))
    }
    return types
  }

  function checkFiniteMetrics(metrics) {
    var previous = null
    var previousCaretY = -1
    for (var index = 0; index < metrics.length; index++) {
      var metric = metrics[index]
      var finite = isFinite(Number(metric.y)) && isFinite(Number(metric.height)) &&
        Number(metric.y) >= 0 && Number(metric.height) >= 0
      check(finite, "block " + index + " has finite non-negative geometry")
      if (previous) {
        check(Number(metric.y) >= Number(previous.y + previous.height) - 0.5,
          "block " + index + " does not overlap the preceding block")
        var previousBottom = Number(previous.y) + Number(previous.height)
        var currentTop = Number(metric.y)
        if (currentTop > previousBottom + 1) {
          var nearPreviousY = display.verticalPadding + previousBottom +
            (currentTop - previousBottom) * 0.25
          var nearCurrentY = display.verticalPadding + previousBottom +
            (currentTop - previousBottom) * 0.75
          check(display.blockIndexForPointY(nearPreviousY) ===
              (String(metric.type) === "blank" ? index : index - 1),
            String(metric.type) === "blank"
              ? "the complete gap before a blank row belongs to that row"
              : "pointer gaps stay with the nearer preceding block")
          check(display.blockIndexForPointY(nearCurrentY) === index,
            "pointer gaps move to the nearer following block")
        }
      }
      var pointBlockIndex = display.blockIndexForPointY(
        display.verticalPadding + Number(metric.y) +
          Math.max(0.5, Number(metric.height) / 2))
      check(pointBlockIndex === index,
        "vertical block lookup resolves block " + index +
          " without scanning every block; got " + pointBlockIndex)
      var expectedSourceBlock = -1
      for (var sourceBlock = 0; sourceBlock < display.blocks.length;
           sourceBlock++) {
        if (Number(metric.sourceStart) >=
              Number(display.blocks[sourceBlock].sourceStart) &&
            Number(metric.sourceStart) <=
              Number(display.blocks[sourceBlock].sourceEnd)) {
          expectedSourceBlock = sourceBlock
          break
        }
      }
      check(display.blockIndexForSourcePosition(metric.sourceStart) ===
          expectedSourceBlock,
        "source block lookup preserves first-boundary behavior for block " +
          index)
      var blockCaret = display.cursorRectangleForSource(metric.sourceStart)
      check(validRect(blockCaret),
        "block " + index + " has a visible caret at its source start")
      if (validRect(blockCaret)) {
        check(Number(blockCaret.y) >= previousCaretY - 0.5,
          "block " + index + " caret does not move backwards vertically")
        previousCaretY = Number(blockCaret.y)
      }
      previous = metric
    }
  }

  function checkRevisionedBlockModel(metrics) {
    var stats = display.projectionCacheStatsForTests()
    check(Number(stats.cacheRevision) === Number(stats.sourceRevision),
      "inline projection cache matches the authoritative source revision")
    check(Number(stats.entries) <= Number(display.projectionCacheEntryLimit) &&
        Number(stats.sourceCharacters) <=
          Number(display.projectionCacheSourceLimit) &&
        Number(stats.prefixCharacters) <=
          Number(display.projectionCachePrefixLimit),
      "inline projection cache stays inside every configured bound: " +
        JSON.stringify(stats))
    if (previousInspectedSourceRevision >= 0) {
      check(Number(stats.sourceRevision) > previousInspectedSourceRevision,
        "loading the next fixture advances the source revision")
    }
    previousInspectedSourceRevision = Number(stats.sourceRevision)

    var modelIds = ({})
    for (var index = 0; index < display.blocks.length; index++) {
      var block = display.blocks[index]
      var modelId = String(block.modelId || "")
      check(Number(block.modelIndex) === index &&
          Number(block.modelRevision) === Number(display.sourceRevision) &&
          Number(block.layoutRevision) === Number(display.layoutRevision),
        "block " + index + " carries the current model and layout revision")
      check(modelId !== "" && modelIds["$" + modelId] !== true,
        "block " + index + " has a unique revisioned model identity")
      modelIds["$" + modelId] = true
    }
  }

  function checkMouseSelectionCoalescing(metrics) {
    if (!metrics || metrics.length === 0) return
    shell.selectionRequestCount = 0
    shell.lastSelectionAnchor = -1
    shell.lastSelectionPosition = -1
    var targetY = display.verticalPadding + Number(metrics[0].y) + 2
    display.beginMouseSelection()
    display.requestMouseSelection(0, display.horizontalPadding + 2, targetY)
    display.requestMouseSelection(0, display.horizontalPadding + 12, targetY)
    display.requestMouseSelection(0, display.horizontalPadding + 24, targetY)
    check(shell.selectionRequestCount === 0,
      "rapid pointer events wait for one frame-coalesced hit test")
    display.endMouseSelection()
    check(shell.selectionRequestCount === 1 &&
        shell.lastSelectionAnchor === 0,
      "release flushes only the newest pending pointer selection")
  }

  function checkSelectionLookupPerformance(metrics) {
    var started = Date.now()
    var invalid = 0
    for (var sample = 0; sample < 240; sample++) {
      var metricIndex = sample % metrics.length
      var metric = metrics[metricIndex]
      var position = display.sourcePositionForPoint(
        display.horizontalPadding + 8 + sample % 180,
        display.verticalPadding + Number(metric.y) +
          Math.max(1, Number(metric.height) / 2))
      if (position < Number(metric.sourceStart) ||
          position > Number(metric.sourceEnd)) invalid++
    }
    var elapsed = Date.now() - started
    console.log("ISOLATED_SELECTION_LOOKUP_MS: " + elapsed)
    check(invalid === 0,
      "frame hit testing stays inside the vertically selected block")
    check(elapsed < 1000,
      "240 long-note pointer lookups complete within 1000ms; got " + elapsed)
  }

  function checkSourceColumnLookupPerformance() {
    function linearSourceColumnForX(value, targetX) {
      var bestColumn = 0
      var bestDistance = Math.abs(display.cursorWidth(
        "", display.bodyPixelSize) - targetX)
      for (var column = 1; column <= value.length; column++) {
        var distance = Math.abs(display.cursorWidth(
          value.slice(0, column), display.bodyPixelSize) - targetX)
        if (distance < bestDistance) {
          bestColumn = column
          bestDistance = distance
        }
      }
      return bestColumn
    }

    var samples = [
      "iiii WWWW mixed spacing",
      "café naïve — 日本語",
      "á combining and emoji 🙂"
    ]
    var mismatches = 0
    var firstMismatch = null
    for (var sampleIndex = 0; sampleIndex < samples.length; sampleIndex++) {
      var sampleText = samples[sampleIndex]
      var sampleWidth = display.cursorWidth(
        sampleText, display.bodyPixelSize)
      for (var point = 0; point <= sampleText.length * 2; point++) {
        var targetX = sampleWidth * point /
          Math.max(1, sampleText.length * 2)
        var fastColumn = display.sourceColumnForX(sampleText, targetX)
        var exactColumn = linearSourceColumnForX(sampleText, targetX)
        if (fastColumn !== exactColumn) {
          mismatches++
          if (!firstMismatch) firstMismatch = {
            text: sampleText,
            targetX: targetX,
            fast: fastColumn,
            exact: exactColumn
          }
        }
      }
    }
    check(mismatches === 0,
      "logarithmic source-column lookup matches the former exact mapping: " +
        JSON.stringify(firstMismatch))

    var longRow = ""
    for (var index = 0; index < 2048; index++) longRow += "x"
    var rowWidth = display.cursorWidth(longRow, display.bodyPixelSize)
    var invalid = 0
    var started = Date.now()
    for (var sample = 0; sample < 240; sample++) {
      var column = display.sourceColumnForX(
        longRow, rowWidth * sample / 239)
      if (column < 0 || column > longRow.length) invalid++
    }
    var elapsed = Date.now() - started
    console.log("ISOLATED_SOURCE_COLUMN_LOOKUP_MS: " + elapsed)
    check(invalid === 0,
      "long-row hit testing always returns a valid source column")
    check(elapsed < 1000,
      "240 long-row column lookups complete within 1000ms; got " + elapsed)
  }

  function checkCaretCoverage(source) {
    var missing = []
    for (var position = 0; position <= source.length; position++) {
      if (!validRect(display.cursorRectangleForSource(position))) {
        missing.push(position)
      }
    }
    check(missing.length === 0,
      "caret geometry covers every source position; missing " +
      JSON.stringify(missing.slice(0, 12)))
  }

  function checkSelectionGeometry(source, selectAll) {
    display.rebuildSelection()
    var rects = display.selectionRects || []
    var targets = display.selectionTargets || []
    var activeTargets = 0
    var activeTargetY = []
    for (var targetIndex = 0; targetIndex < targets.length; targetIndex++) {
      var targetRange = display.selectionRangeForTarget(targets[targetIndex])
      if (Number(targetRange.end) > Number(targetRange.start)) {
        activeTargets++
        activeTargetY.push(Number(targets[targetIndex].y) || 0)
      }
    }
    if (selectAll) {
      check(activeTargets >= 3,
        "select-all activates native selection ranges across rows")
    } else {
      check(activeTargets > 0,
        "partial selection activates a native selection range")
    }

    var invalid = []
    var hasLaterRow = false
    for (var index = 0; index < rects.length; index++) {
      if (!validRect(rects[index])) invalid.push(index)
      if (Number(rects[index].y) > 30) hasLaterRow = true
    }
    if (activeTargetY.length > 1) {
      var firstTargetY = activeTargetY[0]
      for (var targetYIndex = 1; targetYIndex < activeTargetY.length;
           targetYIndex++) {
        if (activeTargetY[targetYIndex] > firstTargetY + 1) {
          hasLaterRow = true
          break
        }
      }
    }
    check(invalid.length === 0, "selection rectangles have valid geometry")
    if (selectAll) {
      check(hasLaterRow, "selection highlighting reaches rows below the first line")
      check(source.indexOf("\n") >= 0, "selection fixture contains newline boundaries")
    }
  }

  function checkedSourceRangeRectangles(tokenValue, occurrenceValue) {
    var token = String(tokenValue || "")
    var occurrence = Math.max(0, Number(occurrenceValue) || 0)
    var start = -1
    var searchFrom = 0
    for (var index = 0; index <= occurrence; index++) {
      start = currentCase().source.indexOf(token, searchFrom)
      if (start < 0) break
      searchFrom = start + token.length
    }
    var end = start + token.length
    var rects = start >= 0
      ? display.sourceRangeRectangles(start, end) : []
    var failures = []
    for (var rectIndex = 0; rectIndex < rects.length; rectIndex++) {
      var rect = rects[rectIndex]
      var hit = display.sourcePositionForPoint(
        Number(rect.x) + Number(rect.width) / 2,
        Number(rect.y) + Number(rect.height) / 2)
      if (!validRect(rect) || !isFinite(Number(rect.underlineY)) ||
          Number(rect.underlineY) <= Number(rect.y) ||
          Number(rect.underlineY) >= Number(rect.y) + Number(rect.height) ||
          hit < start || hit > end) {
        failures.push({rect: rect, hit: hit})
      }
    }
    check(start >= 0 && rects.length > 0 && failures.length === 0,
      "source range geometry stays on " + token + ": " +
        JSON.stringify({start: start, end: end, rects: rects,
          failures: failures}))
    return rects
  }

  function checkCaseSpecific(spec, metrics) {
    if (spec.name === "leading-and-multiple-blank-lines") {
      var uniformAdvance = display.bodyLineAdvance()
      var unevenRows = []
      for (var uniformIndex = 0;
           uniformIndex < metrics.length; uniformIndex++) {
        var uniformMetric = metrics[uniformIndex]
        if (Math.abs(Number(uniformMetric.height) - uniformAdvance) > 1.5) {
          unevenRows.push({index: uniformIndex,
            type: uniformMetric.type, height: uniformMetric.height})
        }
        if (uniformIndex > 0) {
          var previousMetric = metrics[uniformIndex - 1]
          var rowStep = Number(uniformMetric.y) - Number(previousMetric.y)
          if (Math.abs(rowStep - Number(previousMetric.height)) > 1.5) {
            unevenRows.push({index: uniformIndex, step: rowStep,
              previousHeight: previousMetric.height})
          }
        }
      }
      check(unevenRows.length === 0,
        "plain text and explicit blank rows share one line height: " +
          JSON.stringify({advance: uniformAdvance, failures: unevenRows,
            metrics: metrics}))
    }

    if (spec.name === "inline-markdown") {
      var cacheStatsBefore = display.projectionCacheStatsForTests()
      var repeatedProjectionSource = "**bold** and `code`"
      var repeatedProjectionPosition = repeatedProjectionSource.length
      var repeatedProjectionFirst = display.plainInlinePrefix(
        repeatedProjectionSource, repeatedProjectionPosition)
      var repeatedProjectionSecond = display.plainInlinePrefix(
        repeatedProjectionSource, repeatedProjectionPosition)
      var cacheStatsAfter = display.projectionCacheStatsForTests()
      check(repeatedProjectionFirst === repeatedProjectionSecond &&
          Number(cacheStatsAfter.prefixHits) >
            Number(cacheStatsBefore.prefixHits),
        "repeated inline projections reuse the revisioned prefix cache")
      check(cachedProjectionsMatchCold(),
        "cached inline and quote projections match cold results at every " +
        "source boundary")
      check(fastSourceMappingsMatchLinear(),
        "fast drag hit testing matches the former linear source mapping")
      var inlineHtml = String(display.inlineHtml(
        "**bold** *italic* `alpha` ~~gone~~"))
      check(inlineHtml.indexOf(
        "<code style=\"background-color:rgba(") >= 0 &&
        inlineHtml.indexOf("; color:rgba(") >= 0,
        "inline code has an explicit accent color and background")
      check(String(display.inlineHtml("code `alpha"))
        .indexOf("code `alpha") >= 0,
        "an unmatched backtick remains literal while editing")
      check(display.plainInline("`alpha") === "`alpha",
        "an unmatched backtick keeps its source width")
      check(String(display.inlineHtml("``alpha``"))
        .indexOf("<code style=\"background-color:rgba(") >= 0 &&
        display.plainInline("``alpha``") === "alpha",
        "matching multi-backtick runs render as one code span")
      var linkHtml = String(display.inlineHtml("[link](https://example.com)"))
      check(linkHtml.indexOf("<font color=\"" + display.linkCssColor() + "\">") >= 0 &&
        linkHtml.indexOf("<u>link</u>") >= 0,
        "links use the readable theme color and underline")
      var fakeLinkText = ({
        linkAt: function(x, y) { return "https://example.com" }
      })
      check(display.linkForPointer(fakeLinkText, 1, 1, Qt.NoModifier) === "" &&
        display.linkForPointer(fakeLinkText, 1, 1, Qt.ControlModifier) ===
          "https://example.com",
        "links require Ctrl-click before opening the browser")
      display.controlKeyHeld = false
      check(display.linkCursorShape(fakeLinkText, 1, 1) === Qt.IBeamCursor,
        "link hover keeps the I-beam cursor until Ctrl is held")
      var styledRanges = [
        {word: "bold", prefix: ""},
        {word: "italic", prefix: "bold "},
        {word: "del", prefix: "bold italic "}
      ]
      check(display.paragraphPlainPrefix("**bold** *italic* ~~del~~",
          "**bold** *italic* ".length) === "bold italic ",
        "adjacent bold and italic delimiters do not leak into later geometry")
      for (var styledIndex = 0;
           styledIndex < styledRanges.length; styledIndex++) {
        var styled = styledRanges[styledIndex]
        var styledRects = checkedSourceRangeRectangles(styled.word, 0)
        var expectedStyledX = display.horizontalPadding +
          display.cursorWidth(styled.prefix, display.bodyPixelSize)
        var expectedStyledWidth = display.cursorWidth(
          styled.word, display.bodyPixelSize)
        var styledCaret = display.cursorRectangleForSource(
          spec.source.indexOf(styled.word))
        var expectedUnderlineY = Number(styledCaret.y) +
          Number(styledCaret.height) -
          Math.max(0.5, Number(styledCaret.height) * 0.04)
        check(styledRects.length === 1 &&
            Math.abs(Number(styledRects[0].x) - expectedStyledX) < 1.5 &&
            Math.abs(Number(styledRects[0].width) - expectedStyledWidth) < 1.5 &&
            Math.abs(Number(styledRects[0].underlineY) -
              expectedUnderlineY) < 1.5,
          "bold italic and strikethrough ranges ignore hidden delimiters: " +
            JSON.stringify({styled: styled, rects: styledRects,
              expectedX: expectedStyledX,
              expectedWidth: expectedStyledWidth,
              sourceStartCaret: display.cursorRectangleForSource(
                spec.source.indexOf(styled.word)),
              sourceEndCaret: display.cursorRectangleForSource(
                spec.source.indexOf(styled.word) + styled.word.length),
              projectedPrefix: display.paragraphPlainPrefix(
                spec.source.slice(metrics[2].sourceStart,
                  metrics[2].sourceEnd),
                spec.source.indexOf(styled.word) - metrics[2].sourceStart)}))
      }
      display.controlKeyHeld = true
      check(display.linkCursorShape(fakeLinkText, 1, 1) ===
        Qt.PointingHandCursor,
        "Ctrl-hover over a link uses the pointing-hand cursor")
      display.controlKeyHeld = false

      var inlineWordStart = spec.source.indexOf("bold")
      var inlineWordRange = display.sourceWordSelectionRange(inlineWordStart)
      var inlineWordEndRange = display.sourceWordSelectionRange(
        inlineWordStart + "bold".length)
      check(Number(inlineWordRange.start) === inlineWordStart &&
        Number(inlineWordRange.end) === inlineWordStart + "bold".length &&
        Number(inlineWordEndRange.start) === inlineWordStart &&
        Number(inlineWordEndRange.end) === inlineWordStart + "bold".length,
        "double-clicking rendered text selects one source word without its " +
        "Markdown delimiters: " + JSON.stringify({start: inlineWordRange,
          end: inlineWordEndRange}))
      var inlineLineRange = display.sourceLineSelectionRange(inlineWordStart)
      check(Number(inlineLineRange.start) === spec.source.indexOf("**bold**") &&
        Number(inlineLineRange.end) === spec.source.length - 1,
        "triple-clicking rendered text selects its complete source row: " +
        JSON.stringify(inlineLineRange))
      display.mouseClickCount = 0
      display.mouseClickKey = ""
      var firstRenderedClick = display.registerRenderedMousePress(
        inlineWordStart)
      var secondRenderedClick = display.registerRenderedMousePress(
        inlineWordStart)
      var thirdRenderedClick = display.registerRenderedMousePress(
        inlineWordStart)
      check(firstRenderedClick === 1 && secondRenderedClick === 2 &&
        thirdRenderedClick === 3,
        "three clicks on one rendered word form a triple-click sequence")

      var headingHitRect = display.cursorRectangleForSource(
        spec.source.indexOf("Heading"))
      var paragraphHitRect = display.cursorRectangleForSource(
        spec.source.indexOf("bold"))
      var headingHit = display.sourcePositionForBlockPoint(
        display.blocks[0],
        headingHitRect.x - display.horizontalPadding,
        headingHitRect.y - display.verticalPadding - metrics[0].y)
      var paragraphHit = display.sourcePositionForBlockPoint(
        display.blocks[2],
        paragraphHitRect.x - display.horizontalPadding,
        paragraphHitRect.y - display.verticalPadding - metrics[2].y)
      check(headingHit >= spec.source.indexOf("Heading") &&
        headingHit <= spec.source.indexOf("Heading") + "Heading".length &&
        paragraphHit >= spec.source.indexOf("bold") &&
        paragraphHit <= spec.source.indexOf("bold") + "bold".length,
        "heading and paragraph clicks resolve to nearby source columns: " +
        JSON.stringify({heading: headingHit, paragraph: paragraphHit}))

      var crossBlockTarget = display.sourcePositionForPoint(
        paragraphHitRect.x + paragraphHitRect.width / 2,
        paragraphHitRect.y + paragraphHitRect.height / 2)
      check(crossBlockTarget >= spec.source.indexOf("bold") &&
        crossBlockTarget <= spec.source.indexOf("bold") + "bold".length,
        "a drag target resolves against the whole Markdown layout: " +
        JSON.stringify({target: crossBlockTarget}))
    }

    if (spec.name === "relative-image") {
      check(String(display.blocks[0].imageSource).indexOf("file://") === 0,
        "relative Markdown images resolve against the note base URL")
      check(Math.abs(Number(metrics[0].imageWidth) - 96) <= 1 &&
        Math.abs(Number(metrics[0].imageHeight) - 48) <= 1 &&
        Number(metrics[0].imageContentHeight) >
          Number(metrics[0].imageHeight),
        "relative image keeps its intrinsic logical size at every scale: " +
        JSON.stringify(metrics[0]))
      check(Boolean(metrics[0].imageAltVisible) &&
        String(metrics[0].imageAltText).indexOf(
          display.inlineCodeHtml("fixture image")) >= 0,
        "loaded standalone images render their alt text with inline-code styling")
      check(Number(metrics[0].imageAltY) > Number(metrics[0].imageHeight) &&
        Number(metrics[0].imageAltHeight) > 0 &&
        Math.abs(Number(metrics[0].imageContentHeight) -
          (Number(metrics[0].imageAltY) +
            Number(metrics[0].imageAltHeight))) <= 1,
        "image alt text sits below the image and contributes to block height: " +
        JSON.stringify(metrics[0]))
    }

    if (spec.name === "image-caption-following-blocks") {
      var imageBlock = display.blocks[0]
      var imageMetric = metrics[0]
      var captionHit = display.sourcePositionForPoint(
        display.horizontalPadding + Math.min(20,
          Number(imageMetric.imageWidth) / 2),
        display.verticalPadding + Number(imageMetric.y) +
          Number(imageMetric.imageAltY) +
          Number(imageMetric.imageAltHeight) / 2)
      check(captionHit >= Number(imageBlock.altSourceStart) &&
        captionHit <= Number(imageBlock.altSourceEnd),
        "clicking the rendered alt caption maps into its source label: " +
        JSON.stringify({hit: captionHit, start: imageBlock.altSourceStart,
          end: imageBlock.altSourceEnd}))
      var imageItem = display.blockItemForValue(imageBlock)
      var imageSurface = imageItem ? imageItem.imageContentReference : null
      var directCaptionHit = imageSurface ? display.imageSourcePositionForPoint(
        imageBlock, imageSurface, Math.min(20,
          Number(imageMetric.imageWidth) / 2),
        Number(imageMetric.imageAltY) +
          Number(imageMetric.imageAltHeight) / 2) : -1
      check(directCaptionHit >= Number(imageBlock.altSourceStart) &&
        directCaptionHit <= Number(imageBlock.altSourceEnd),
        "the image hit surface maps a direct alt-caption click into its label: " +
        JSON.stringify({hit: directCaptionHit,
          start: imageBlock.altSourceStart, end: imageBlock.altSourceEnd}))
      var altCaret = display.cursorRectangleForSource(
        Math.floor((Number(imageBlock.altSourceStart) +
          Number(imageBlock.altSourceEnd)) / 2))
      var captionTop = display.verticalPadding + Number(imageMetric.y) +
        Number(imageMetric.imageAltY)
      check(validRect(altCaret) &&
        Number(altCaret.y) >= captionTop - 1 &&
        Number(altCaret.y) <= captionTop +
          Number(imageMetric.imageAltHeight) + 1,
        "the Live caret follows a source position inside the alt caption: " +
        JSON.stringify({caret: altCaret, top: captionTop,
          height: imageMetric.imageAltHeight}))

      var blankMetric = metrics[1]
      var blankCaret = display.cursorRectangleForSource(
        Number(blankMetric.sourceStart))
      var captionBottom = display.verticalPadding + Number(imageMetric.y) +
        Number(imageMetric.imageAltY) + Number(imageMetric.imageAltHeight)
      var headingTop = display.verticalPadding + Number(metrics[2].y)
      var blankCaretCenter = validRect(blankCaret)
        ? Number(blankCaret.y) + Number(blankCaret.height) / 2 : -1
      check(validRect(blankCaret) && blankCaretCenter >= captionBottom - 1 &&
        blankCaretCenter <= headingTop + 1,
        "the blank-row caret appears between the image caption and following " +
        "heading: " + JSON.stringify({caret: blankCaret,
          center: blankCaretCenter, captionBottom: captionBottom,
          headingTop: headingTop}))
      var blankHit = display.sourcePositionForPoint(
        display.horizontalPadding + 4,
        display.verticalPadding + Number(blankMetric.y) +
          Number(blankMetric.height) / 2)
      check(blankHit >= Number(blankMetric.sourceStart) &&
        blankHit <= Number(blankMetric.sourceEnd),
        "the source row directly below the alt caption remains clickable: " +
        JSON.stringify({hit: blankHit, start: blankMetric.sourceStart,
          end: blankMetric.sourceEnd}))
      check(Number(blankMetric.y) >= Number(imageMetric.y) +
          Number(imageMetric.height) - 1,
        "the following source row starts after the complete image caption " +
        "surface: " + JSON.stringify({image: imageMetric, blank: blankMetric}))
      var imageBottom = Number(imageMetric.y) + Number(imageMetric.height)
      var blankHitTop = Number(blankMetric.y) +
        Number(blankMetric.blankHitAreaY)
      var blankHitBottom = blankHitTop +
        Number(blankMetric.blankHitAreaHeight)
      check(Math.abs(blankHitTop - imageBottom) <= 1 &&
        blankHitBottom >= Number(blankMetric.y) +
          Number(blankMetric.height) - 1,
        "the blank row hit surface includes the gap immediately below the " +
        "image caption: " + JSON.stringify({imageBottom: imageBottom,
          blank: blankMetric, hitTop: blankHitTop, hitBottom: blankHitBottom}))
      var immediatelyBelowHit = display.sourcePositionForPoint(
        display.horizontalPadding + 4,
        display.verticalPadding + imageBottom + 0.5)
      check(immediatelyBelowHit >= Number(blankMetric.sourceStart) &&
        immediatelyBelowHit <= Number(blankMetric.sourceEnd),
        "a document-level click immediately below the caption targets the " +
        "following blank source row: " + JSON.stringify({
          hit: immediatelyBelowHit, start: blankMetric.sourceStart,
          end: blankMetric.sourceEnd}))

      var headingStart = Number(display.blocks[2].contentSourceStart)
      var headingCaret = display.cursorRectangleForSource(headingStart)
      var headingHit = validRect(headingCaret) ? display.sourcePositionForPoint(
        Number(headingCaret.x) + Number(headingCaret.width) / 2,
        Number(headingCaret.y) + Number(headingCaret.height) / 2) : -1
      check(headingHit >= Number(metrics[2].sourceStart) &&
        headingHit <= Number(metrics[2].sourceEnd),
        "the Markdown block after the alt caption remains clickable: " +
        JSON.stringify({hit: headingHit, start: metrics[2].sourceStart,
          end: metrics[2].sourceEnd}))
    }

    if (spec.name === "quote-following-blank-heading") {
      var quoteMetric = metrics[0]
      var quoteBlankMetric = metrics[1]
      var quoteHeadingMetric = metrics[2]
      var quoteBlankCaret = display.cursorRectangleForSource(
        Number(quoteBlankMetric.sourceStart))
      var quoteBottom = display.verticalPadding + Number(quoteMetric.y) +
        Number(quoteMetric.height)
      var quoteHeadingTop = display.verticalPadding +
        Number(quoteHeadingMetric.y)
      var quoteBlankCenter = validRect(quoteBlankCaret)
        ? Number(quoteBlankCaret.y) + Number(quoteBlankCaret.height) / 2 : -1
      check(validRect(quoteBlankCaret) &&
        quoteBlankCenter >= quoteBottom - 1 &&
        quoteBlankCenter <= quoteHeadingTop + 1,
        "the blank-row caret appears between the quote and following heading: " +
          JSON.stringify({ caret: quoteBlankCaret, center: quoteBlankCenter,
            quoteBottom: quoteBottom, headingTop: quoteHeadingTop }))
      var quoteGapHit = display.sourcePositionForPoint(
        display.horizontalPadding + 2,
        Math.max(quoteBottom + 1,
          Number(quoteBlankCaret.y) + Number(quoteBlankCaret.height) / 2))
      check(quoteGapHit >= Number(quoteBlankMetric.sourceStart) &&
        quoteGapHit <= Number(quoteBlankMetric.sourceEnd),
        "clicking below the quote targets the following blank source row: " +
          JSON.stringify({ hit: quoteGapHit,
            start: quoteBlankMetric.sourceStart,
            end: quoteBlankMetric.sourceEnd }))
    }

    if (spec.name === "commonmark-link-compatibility") {
      var compatibilityHtml = String(display.blocks[0].html || "")
      check(compatibilityHtml.indexOf("docs/a_(b).md") >= 0 &&
        compatibilityHtml.indexOf("guide.md") >= 0 &&
        compatibilityHtml.indexOf("collapsed.md") >= 0 &&
        compatibilityHtml.indexOf("shortcut.md") >= 0 &&
        compatibilityHtml.indexOf("<strong>bold</strong>") >= 0,
        "balanced destinations and full, collapsed, or shortcut references resolve: " +
          compatibilityHtml)
      check(compatibilityHtml.indexOf("title=\"title\"") >= 0 &&
        compatibilityHtml.indexOf("title=\"Guide title\"") >= 0 &&
        String(display.inlineHtml(
          "![alt](img.png (Image title))")).indexOf(
            "title=\"Image title\"") >= 0,
        "inline and reference links or images preserve optional titles: " +
          compatibilityHtml)
      check(display.blocks.slice(2).every(function(block) {
        return block.type === "blank"
      }), "reference definitions do not render as paragraph text")
    }

    if (spec.name === "fenced-reference-definition") {
      check(display.referenceDefinitions.bad === undefined &&
        String(display.blocks[1].html || "").indexOf("href=") < 0 &&
        String(display.blocks[1].html || "").indexOf("[bad]") >= 0,
        "reference-looking code fence content never defines an outer link")
    }

    if (spec.name === "reference-image") {
      check(String(display.blocks[0].imageSource).indexOf(
        "markdown-image.svg") >= 0,
        "reference-style images use their resolved destination")
    }

    if (spec.name === "inline-code-caret") {
      var codeOpen = spec.source.indexOf("`")
      var beforeCode = display.cursorRectangleForSource(codeOpen)
      var afterOpen = display.cursorRectangleForSource(codeOpen + 1)
      var afterFirstCodeCharacter = display.cursorRectangleForSource(codeOpen + 2)
      var beforeClose = display.cursorRectangleForSource(
        spec.source.lastIndexOf("`"))
      var afterClose = display.cursorRectangleForSource(
        spec.source.lastIndexOf("`") + 1)
      check(validRect(beforeCode) && validRect(afterOpen) &&
        validRect(afterFirstCodeCharacter) && validRect(beforeClose) &&
        validRect(afterClose),
        "inline-code source positions all have caret geometry")
      check(Math.abs(afterOpen.x - beforeCode.x) < 1.5 &&
        afterFirstCodeCharacter.x > afterOpen.x + 1 &&
        Math.abs(afterClose.x - beforeClose.x) < 1.5,
        "code delimiters do not move the caret while code content does: " +
        JSON.stringify({before: beforeCode, afterOpen: afterOpen,
          afterFirst: afterFirstCodeCharacter, beforeClose: beforeClose,
          afterClose: afterClose}))
    }

    if (spec.name === "nested-multiline-emphasis") {
      var emphasisHtml = String(display.blocks[0].html || "")
      check(emphasisHtml.indexOf("<em><strong>both</strong></em>") >= 0 &&
        emphasisHtml.indexOf("<strong>bold <em>inner</em></strong>") >= 0 &&
        emphasisHtml.indexOf("<em>across<br>lines</em>") >= 0,
        "nested and multiline emphasis render with the expected hierarchy: " +
          emphasisHtml)
      var tripleStart = display.cursorRectangleForSource(0)
      var tripleContent = display.cursorRectangleForSource(3)
      var acrossOpen = spec.source.indexOf("*across")
      var acrossText = display.cursorRectangleForSource(acrossOpen + 1)
      check(validRect(tripleStart) && validRect(tripleContent) &&
        validRect(acrossText) &&
        Math.abs(tripleStart.x - tripleContent.x) < 1.5 &&
        Math.abs(display.cursorRectangleForSource(acrossOpen).x -
          acrossText.x) < 1.5,
        "nested and multiline delimiters collapse to source-editable boundaries")
    }

    if (spec.name === "reference-projection-with-definition" ||
        spec.name === "reference-projection-without-definition") {
      var referenceLineEnd = spec.source.indexOf("\n")
      var referenceSource = spec.source.slice(0, referenceLineEnd)
      var referenceProjection = display.paragraphPlainPrefix(
        referenceSource, referenceSource.length)
      var expectedReferenceProjection =
        spec.name === "reference-projection-with-definition"
          ? "label" : "[label][id]"
      check(referenceProjection === expectedReferenceProjection,
        "reference projection follows the current definition context: " +
          JSON.stringify({actual: referenceProjection,
            expected: expectedReferenceProjection,
            cache: display.projectionCacheStatsForTests()}))
    }

    if (spec.name === "wrapped-paragraph") {
      var wrapStart = display.cursorRectangleForSource(0)
      var wrapEnd = display.cursorRectangleForSource(spec.source.length)
      check(validRect(wrapStart) && validRect(wrapEnd) &&
        wrapEnd.y > wrapStart.y,
        "caret follows a paragraph's soft-wrapped visual line")
      var privatePosition = spec.source.indexOf("private")
      var serverPosition = spec.source.indexOf("server")
      var privateCaret = display.cursorRectangleForSource(privatePosition)
      var preferredX = privateCaret.x + privateCaret.width / 2
      var downTarget = display.verticalNavigationTarget(
        privatePosition, preferredX, 1)
      var downCaret = display.cursorRectangleForSource(downTarget)
      var upTarget = display.verticalNavigationTarget(
        downTarget, preferredX, -1)
      var upCaret = display.cursorRectangleForSource(upTarget)
      var downAgainTarget = display.verticalNavigationTarget(
        upTarget, preferredX, 1)
      check(downTarget >= serverPosition &&
          downTarget <= spec.source.length && validRect(downCaret) &&
          downCaret.y > privateCaret.y,
        "Down reaches the wrapped server row in the reported note: " +
          JSON.stringify({downTarget: downTarget,
            serverPosition: serverPosition, downCaret: downCaret}))
      check(upTarget >= 0 && validRect(upCaret) &&
          upCaret.y === privateCaret.y &&
          Math.abs(upCaret.x - privateCaret.x) <=
            display.cursorWidth("M", display.bodyPixelSize) &&
          downAgainTarget === downTarget,
        "Up and Down preserve the preferred visual column across a short " +
          "wrapped row: " + JSON.stringify({upTarget: upTarget,
            downTarget: downTarget, downAgainTarget: downAgainTarget,
            privateCaret: privateCaret, upCaret: upCaret}))
      var serverRects = checkedSourceRangeRectangles("server", 0)
      check(serverRects.length === 1 &&
          Math.abs(Number(serverRects[0].x) - display.horizontalPadding) < 1.5,
        "a misspelling on the short wrapped server row starts at its glyph row")
    }

    if (spec.name === "wrapped-inline-range") {
      var longWordRects = checkedSourceRangeRectangles(
        "supercalifragilisticmispeling", 0)
      check(longWordRects.length >= 2 &&
          Number(longWordRects[longWordRects.length - 1].y) >
            Number(longWordRects[0].y),
        "one long misspelling produces one aligned segment per visual row: " +
          JSON.stringify(longWordRects))
    }

    if (spec.name === "closing-atx-heading")
      checkedSourceRangeRectangles("Title", 0)
    if (spec.name === "nested-multiline-emphasis") {
      checkedSourceRangeRectangles("both", 0)
      checkedSourceRangeRectangles("inner", 0)
      checkedSourceRangeRectangles("across", 0)
    }
    if (spec.name === "commonmark-inline-basics") {
      checkedSourceRangeRectangles("literal", 0)
      checkedSourceRangeRectangles("relative", 0)
    }
    if (spec.name === "commonmark-link-compatibility") {
      checkedSourceRangeRectangles("nested", 0)
      checkedSourceRangeRectangles("bold", 0)
    }
    if (spec.name === "wrapped-quote")
      checkedSourceRangeRectangles("eleven", 0)
    if (spec.name === "wrapped-list-item")
      checkedSourceRangeRectangles("eleven", 0)
    if (spec.name === "wrapped-table-cell") {
      var tableWordStart = spec.source.indexOf("eleven")
      var tableWordRects = display.sourceRangeRectangles(
        tableWordStart, tableWordStart + "eleven".length)
      check(tableWordRects.length === 1 && validRect(tableWordRects[0]),
        "wrapped table cell exposes one valid spelling range: " +
          JSON.stringify(tableWordRects))
    }
    if (spec.name === "relative-image")
      checkedSourceRangeRectangles("fixture", 0)

    if (spec.name === "wrapped-paragraph-mouse-hit") {
      var shouldStarts = [spec.source.indexOf("should")]
      shouldStarts.push(spec.source.indexOf(
        "should", shouldStarts[0] + "should".length))
      var characterOffsets = [0, Math.floor("should".length / 2),
        "should".length - 1]
      var wrappedWordFailures = []
      for (var occurrence = 0; occurrence < shouldStarts.length;
           occurrence++) {
        var shouldStart = shouldStarts[occurrence]
        var shouldEnd = shouldStart + "should".length
        for (var sampleIndex = 0; sampleIndex < characterOffsets.length;
             sampleIndex++) {
          var characterStart = shouldStart + characterOffsets[sampleIndex]
          var leftRect = display.cursorRectangleForSource(characterStart)
          var rightRect = display.cursorRectangleForSource(characterStart + 1)
          var sampleValid = validRect(leftRect) && validRect(rightRect)
          var clickX = sampleValid
            ? (Number(leftRect.x) + Number(rightRect.x)) / 2 : -1
          var clickY = sampleValid
            ? (Number(leftRect.y) + Number(leftRect.height) / 2 +
                Number(rightRect.y) + Number(rightRect.height) / 2) / 2
            : -1
          var blockHit = sampleValid
            ? display.sourcePositionForBlockPoint(
                display.blocks[0],
                clickX - display.horizontalPadding,
                clickY - display.verticalPadding - metrics[0].y)
            : -1
          var fullHit = sampleValid
            ? display.sourcePositionForPoint(clickX, clickY) : -1
          if (!sampleValid || blockHit < shouldStart ||
              blockHit > shouldEnd || fullHit < shouldStart ||
              fullHit > shouldEnd) {
            wrappedWordFailures.push({
              occurrence: occurrence,
              offset: characterOffsets[sampleIndex],
              blockHit: blockHit,
              fullHit: fullHit,
              expectedStart: shouldStart,
              expectedEnd: shouldEnd,
              left: leftRect,
              right: rightRect
            })
          }
        }
      }
      check(wrappedWordFailures.length === 0,
        "wrapped paragraph clicks target the start middle and end of both " +
          "should occurrences through block and full-layout hit testing: " +
          JSON.stringify(wrappedWordFailures))
    }

    if (spec.name === "wrapped-list-test-note") {
      var listMetric = metrics[0].listItems &&
        metrics[0].listItems.length > 0 ? metrics[0].listItems[0] : null
      check(listMetric && Number(listMetric.lineCount) === 3,
        "the exact test.md list item wraps to three editable rows: " +
          JSON.stringify(listMetric))
      var listWords = [
        {start: spec.source.indexOf("We"), length: "We".length, row: 0},
        {start: spec.source.indexOf("explains"),
          length: "explains".length, row: 1},
        {start: spec.source.lastIndexOf("should"),
          length: "should".length, row: 2},
        {start: spec.source.indexOf("pretty"),
          length: "pretty".length, row: 2}
      ]
      var listFailures = []
      for (var listWordIndex = 0; listWordIndex < listWords.length;
           listWordIndex++) {
        var listWord = listWords[listWordIndex]
        var listCharacter = listWord.start +
          Math.floor(listWord.length / 2)
        var listLeft = display.cursorRectangleForSource(listCharacter)
        var listRight = display.cursorRectangleForSource(listCharacter + 1)
        var listRectsValid = validRect(listLeft) && validRect(listRight)
        var listClickX = listRectsValid
          ? (Number(listLeft.x) + Number(listRight.x)) / 2 : -1
        var listClickY = listRectsValid
          ? (display.caretCenterY(listLeft) +
              display.caretCenterY(listRight)) / 2 : -1
        var listBlockHit = listRectsValid
          ? display.listSourcePositionForBlockPoint(
              display.blocks[0], null,
              listClickX - display.horizontalPadding,
              listClickY - display.verticalPadding - metrics[0].y)
          : -1
        var listFullHit = listRectsValid
          ? display.sourcePositionForPoint(listClickX, listClickY) : -1
        var expectedCenter = listMetric
          ? display.verticalPadding + Number(metrics[0].y) +
              Number(listMetric.itemY) + Number(listMetric.textY) +
              Number(listMetric.textBaseline) +
              listWord.row * Number(listMetric.lineAdvance) +
              Number(listMetric.fontCaretTop) +
              Number(listMetric.fontCaretHeight) / 2
          : -1
        // Keyboard navigation can land at the start, middle, or end of a
        // wrapped word. Check all three boundaries; the original regression
        // was visible specifically before the final "should".
        var listCaretPositions = [
          listWord.start,
          listCharacter,
          listWord.start + listWord.length
        ]
        var listCaretCenters = []
        var caretCentered = true
        for (var listCaretIndex = 0;
             listCaretIndex < listCaretPositions.length; listCaretIndex++) {
          var boundaryRect = display.cursorRectangleForSource(
            listCaretPositions[listCaretIndex])
          var boundaryCenter = validRect(boundaryRect)
            ? display.caretCenterY(boundaryRect) : -1
          listCaretCenters.push(boundaryCenter)
          if (!validRect(boundaryRect) ||
              Math.abs(boundaryCenter - expectedCenter) > 1) {
            caretCentered = false
          }
        }
        if (!listRectsValid || listBlockHit < listWord.start ||
            listBlockHit > listWord.start + listWord.length ||
            listFullHit < listWord.start ||
            listFullHit > listWord.start + listWord.length ||
            !caretCentered) {
          listFailures.push({word: listWord, blockHit: listBlockHit,
            fullHit: listFullHit, expectedCenter: expectedCenter,
            actualCenters: listCaretCenters,
            left: listLeft, right: listRight})
        }
      }
      check(listFailures.length === 0,
        "all test.md list rows accept mouse targets and center the keyboard " +
          "caret, including before the final pretty: " +
          JSON.stringify(listFailures))
    }

    if (spec.name === "wrapped-quote" || spec.name === "wrapped-code" ||
        spec.name === "wrapped-list-item") {
      var wrappedStart = display.cursorRectangleForSource(0)
      var wrappedEnd = display.cursorRectangleForSource(spec.source.length)
      check(validRect(wrappedStart) && validRect(wrappedEnd) &&
        wrappedEnd.y > wrappedStart.y,
        "caret follows a soft-wrapped " + spec.name + ": " +
        JSON.stringify({start: wrappedStart, end: wrappedEnd}))
    }

    if (spec.name === "explicit-paragraph-lines") {
      check(Number(metrics[0].sourceLineCount) === 3,
        "explicit paragraph line count is preserved")
      var first = display.cursorRectangleForSource(0)
      var secondStart = spec.source.indexOf("line two")
      var second = display.cursorRectangleForSource(secondStart)
      var third = display.cursorRectangleForSource(spec.source.indexOf("line three"))
      var explicitFirstStep = display.caretCenterY(second) -
        display.caretCenterY(first)
      var explicitSecondStep = display.caretCenterY(third) -
        display.caretCenterY(second)
      check(validRect(first) && validRect(second) && validRect(third) &&
        second.y > first.y && third.y > second.y &&
        Math.abs(explicitFirstStep - display.bodyLineAdvance()) < 1.5 &&
        Math.abs(explicitSecondStep - display.bodyLineAdvance()) < 1.5,
        "caret advances through each explicit paragraph line: " +
        JSON.stringify({first: first, second: second, third: third,
          firstStep: explicitFirstStep, secondStep: explicitSecondStep,
          expectedStep: display.bodyLineAdvance()}))
      var secondDragTarget = display.sourcePositionForPoint(
        second.x + second.width / 2, second.y + second.height / 2)
      check(secondDragTarget >= secondStart &&
        secondDragTarget <= secondStart + "line two".length,
        "dragging to a later paragraph line resolves its source row: " +
        JSON.stringify({target: secondDragTarget, expected: secondStart}))
      var explicitHit = display.sourcePositionForBlockPoint(
        display.blocks[0],
        second.x - display.horizontalPadding,
        second.y - display.verticalPadding - metrics[0].y)
      check(explicitHit >= secondStart &&
        explicitHit <= secondStart + "line two".length,
        "clicking an explicit paragraph line resolves to that source line: " +
        JSON.stringify({hit: explicitHit, expected: secondStart}))
    }

    if (spec.name === "wrapped-paragraph") {
      check(Math.abs(Number(metrics[0].lineAdvance) -
          display.bodyLineAdvance()) < 1.5,
        "soft-wrapped prose uses the shared body line height: " +
          JSON.stringify({actual: metrics[0].lineAdvance,
            expected: display.bodyLineAdvance()}))
    }

    if (spec.name === "ordered-list") {
      var listRows = metrics[0].listItems || []
      var listHeightFailures = []
      for (var listHeightIndex = 0;
           listHeightIndex < listRows.length; listHeightIndex++) {
        if (Math.abs(Number(listRows[listHeightIndex].lineAdvance) -
            display.bodyLineAdvance()) > 1.5) {
          listHeightFailures.push(listRows[listHeightIndex])
        }
        if (listHeightIndex > 0) {
          var listStep = Number(listRows[listHeightIndex].itemY) -
            Number(listRows[listHeightIndex - 1].itemY)
          if (Math.abs(listStep -
              Number(listRows[listHeightIndex - 1].glyphHeight)) > 1.5) {
            listHeightFailures.push({step: listStep,
              previous: listRows[listHeightIndex - 1]})
          }
        }
      }
      check(listHeightFailures.length === 0,
        "list source rows use the shared body line height without extra gaps: " +
          JSON.stringify(listHeightFailures))
    }

    if (spec.name === "quote-rule-code") {
      check(Math.abs(Number(metrics[4].codeLineAdvance) -
          display.bodyLineAdvance()) < 1.5,
        "code source rows use the shared body line height: " +
          JSON.stringify({actual: metrics[4].codeLineAdvance,
            expected: display.bodyLineAdvance()}))
    }

    if (spec.name === "partial-selection-across-lines") {
      var lineStarts = [0, spec.source.indexOf("three"),
        spec.source.indexOf("five")]
      var lineTargets = []
      for (var lineIndex = 0; lineIndex < lineStarts.length; lineIndex++) {
        var lineRect = display.cursorRectangleForSource(lineStarts[lineIndex])
        var lineTarget = display.sourcePositionForPoint(
          lineRect.x + lineRect.width / 2,
          lineRect.y + lineRect.height / 2)
        lineTargets.push(lineTarget)
      }
      check(lineTargets[0] <= spec.source.indexOf("three") &&
        lineTargets[1] >= spec.source.indexOf("three") &&
        lineTargets[1] < spec.source.indexOf("five") &&
        lineTargets[2] >= spec.source.indexOf("five"),
        "drag targets stay on the line under the pointer: " +
        JSON.stringify({starts: lineStarts, targets: lineTargets}))
    }

    if (spec.name === "partial-selection-across-blocks") {
      var blankPosition = spec.source.indexOf("\n") + 1
      display.beginMouseSelection()
      display.cursorPosition = blankPosition
      check(display.layoutReady,
        "entering a blank row during a drag keeps the settled hit-test layout")
      var blankRect = display.cursorRectangleForSource(blankPosition)
      var blankTarget = validRect(blankRect) ? display.sourcePositionForPoint(
        blankRect.x + blankRect.width / 2,
        blankRect.y + blankRect.height / 2) : -1
      check(validRect(blankRect) && blankTarget > 0 &&
        blankTarget < spec.source.length,
        "dragging across a blank row keeps a nearby source target: " +
        JSON.stringify({target: blankTarget, expected: blankPosition}))
      display.endMouseSelection()
      display.cursorPosition = Qt.binding(function() { return shell.activeCursor })

      var blockTargets = display.selectionTargets || []
      var firstBlockRange = blockTargets.length > 0
        ? display.selectionRangeForTarget(blockTargets[0]) : {start: 0, end: 0}
      check(Number(firstBlockRange.end) <= Number(firstBlockRange.start),
        "a partial selection across blocks does not select the preceding block")
    }

    if (spec.name === "trailing-whitespace-columns") {
      var secondTextEnd = spec.source.indexOf("asdf", 5) + 4
      var secondLineEnd = spec.source.indexOf("\n", secondTextEnd)
      var thirdLineStart = secondLineEnd + 1
      var secondTextCaret = display.cursorRectangleForSource(secondTextEnd)
      var secondSpaceCaret = display.cursorRectangleForSource(secondLineEnd)
      var thirdLineCaret = display.cursorRectangleForSource(thirdLineStart)
      check(validRect(secondTextCaret) && validRect(secondSpaceCaret) &&
        validRect(thirdLineCaret) &&
        secondSpaceCaret.x > secondTextCaret.x + 1 &&
        thirdLineCaret.y > secondSpaceCaret.y,
        "caret advances through trailing spaces and then to the next line: " +
        JSON.stringify({text: secondTextCaret, spaces: secondSpaceCaret,
          next: thirdLineCaret}))
    }

    if (spec.name === "internal-tab-spaces") {
      var beforeTabSpaces = display.cursorRectangleForSource(2)
      var afterTabSpaces = display.cursorRectangleForSource(4)
      var internalBlocks = display.parseMarkdown(spec.source)
      check(validRect(beforeTabSpaces) && validRect(afterTabSpaces) &&
        afterTabSpaces.x > beforeTabSpaces.x + 1 &&
        internalBlocks[0].html.indexOf("Em &#160;phasis") >= 0,
        "Tab after m keeps both inserted space columns visible before p: " +
          JSON.stringify({before: beforeTabSpaces, after: afterTabSpaces,
            html: internalBlocks[0].html}))
    }

    if (spec.name === "whitespace-only-row") {
      var blankStart = spec.source.indexOf("\n") + 1
      var blankEnd = spec.source.indexOf("\n", blankStart)
      var blankLeft = display.cursorRectangleForSource(blankStart)
      var blankRight = display.cursorRectangleForSource(blankEnd)
      check(validRect(blankLeft) && validRect(blankRight) &&
        blankRight.x > blankLeft.x + 1,
        "caret advances through spaces on a whitespace-only row: " +
        JSON.stringify({start: blankLeft, end: blankRight}))
    }

    if (spec.name === "heading-paragraph-gap") {
      var headingBlankStart = spec.source.indexOf("\n") + 1
      var headingParagraphStart = spec.source.lastIndexOf("\n") + 1
      var headingBlankCaret = display.cursorRectangleForSource(
        headingBlankStart)
      var headingParagraphCaret = display.cursorRectangleForSource(
        headingParagraphStart)
      var expectedBlankParagraphAdvance =
        Number(metrics[1].height) + Number(display.blockSpacing)
      check(validRect(headingBlankCaret) && validRect(headingParagraphCaret) &&
        Math.abs((headingParagraphCaret.y - headingBlankCaret.y) -
          expectedBlankParagraphAdvance) < 1.5,
        "heading blank row reserves a complete paragraph row before the " +
          "following paragraph: " +
        JSON.stringify({blank: headingBlankCaret,
          paragraph: headingParagraphCaret,
          expectedBlankParagraphAdvance: expectedBlankParagraphAdvance}))
      check(validRect(shell.headingTrailingCaret) &&
        validRect(headingParagraphCaret) &&
        Math.abs(headingParagraphCaret.y - shell.headingTrailingCaret.y) < 1.5,
        "typing into the heading's active blank row does not move the caret: " +
        JSON.stringify({before: shell.headingTrailingCaret,
          beforeMetrics: shell.headingTrailingMetrics,
          after: headingParagraphCaret, metrics: metrics}))
    }

    if (spec.name === "heading-trailing-empty-row") {
      shell.headingTrailingCaret = display.cursorRectangleForSource(
        spec.source.length)
      shell.headingTrailingMetrics = display.layoutMetricsForTests()
      check(validRect(shell.headingTrailingCaret),
        "heading trailing blank row has a visible caret")
    }

    if (spec.name === "literal-inline-markers") {
      var starPosition = spec.source.indexOf("*")
      var starBefore = display.cursorRectangleForSource(starPosition)
      var starAfter = display.cursorRectangleForSource(starPosition + 1)
      var tildePosition = spec.source.lastIndexOf("~")
      var tildeBefore = display.cursorRectangleForSource(tildePosition)
      var tildeAfter = display.cursorRectangleForSource(tildePosition + 1)
      check(validRect(starBefore) && validRect(starAfter) &&
        starAfter.x > starBefore.x + 1 &&
        validRect(tildeBefore) && validRect(tildeAfter) &&
        tildeAfter.x > tildeBefore.x + 1,
        "unmatched emphasis markers retain visible caret width")
      check(display.plainInlinePrefix("foo_bar_baz", 4) === "foo_" &&
        display.plainInlinePrefix("foo_bar_baz", 8) === "foo_bar_" &&
        display.inlineHtml("foo_bar_baz").indexOf("<em>") < 0,
        "intraword underscores remain literal in render and geometry")
    }

    if (spec.name === "matched-emphasis-caret") {
      var beforeStrong = display.cursorRectangleForSource(0)
      var afterStrongOpen = display.cursorRectangleForSource(2)
      var afterStrongLetter = display.cursorRectangleForSource(3)
      check(display.plainInlinePrefix(spec.source, 2) === "" &&
        display.plainInlinePrefix(spec.source, 3) === "b" &&
        validRect(beforeStrong) && validRect(afterStrongOpen) &&
        validRect(afterStrongLetter) &&
        Math.abs(afterStrongOpen.x - beforeStrong.x) < 0.5 &&
        afterStrongLetter.x > afterStrongOpen.x + 1,
        "matched emphasis delimiters never shift the Live caret")
    }

    if (spec.name === "commonmark-inline-basics") {
      var inlineHtml = display.inlineHtml(spec.source)
      var relativeTarget = shell.imageBaseUrl + "other.md"
      check(inlineHtml.indexOf("<em>") < 0 &&
        display.plainInline("\\*literal\\*") === "*literal*",
        "backslash escapes keep punctuation literal in render and geometry")
      check(display.plainInline("&amp; &#x41;") === "& A" &&
        inlineHtml.indexOf("&amp;") >= 0 && inlineHtml.indexOf(" A ") >= 0,
        "named and numeric character references render as decoded text")
      check(inlineHtml.indexOf("href=\"https://example.com\"") >= 0 &&
        inlineHtml.indexOf("href=\"mailto:person@example.com\"") >= 0,
        "URI and email autolinks become actionable links")
      check(inlineHtml.indexOf("href=\"" + relativeTarget + "\"") >= 0,
        "relative Markdown links resolve beside the active note")
    }

    if (spec.name === "html5-entities") {
      var entityPlain = display.plainInline(spec.source)
      var entityHtml = display.inlineHtml(spec.source)
      check(entityPlain ===
        "© é ← ≂̸ & 😀 � � &notanentity;",
        "the complete HTML5 entity table and numeric replacement rules decode: " +
          entityPlain)
      check(entityHtml.indexOf("©") >= 0 && entityHtml.indexOf("é") >= 0 &&
        entityHtml.indexOf("←") >= 0 && entityHtml.indexOf("≂̸") >= 0 &&
        entityHtml.indexOf("😀") >= 0 &&
        entityHtml.indexOf("&amp;notanentity;") >= 0,
        "rendered HTML uses decoded entities while preserving unknown names: " +
          entityHtml)
    }

    if (spec.name === "closing-atx-heading") {
      var titleEnd = spec.source.indexOf("Title") + "Title".length
      var visibleHeadingEnd = display.cursorRectangleForSource(titleEnd)
      var sourceHeadingEnd = display.cursorRectangleForSource(spec.source.length)
      check(validRect(visibleHeadingEnd) && validRect(sourceHeadingEnd) &&
        Math.abs(visibleHeadingEnd.x - sourceHeadingEnd.x) < 0.5,
        "closing ATX hashes collapse to the visible heading end")
    }

    if (spec.name === "preview-heading-backspace-literal") {
      var literalHeadingCaret = display.cursorRectangleForSource(4)
      check(Number(display.blocks[0].sourceStart) === 0 &&
          validRect(literalHeadingCaret) &&
          Number(literalHeadingCaret.x) > Number(display.horizontalPadding),
        "Preview renders ####W as literal text with the caret after the hashes: " +
          JSON.stringify({
            block: display.blocks[0], caret: literalHeadingCaret }))
    }

    if (spec.name === "preview-heading-separator-completed") {
      var expectedContentStart = 5
      var headingBoundaryCaret = display.cursorRectangleForSource(
        expectedContentStart)
      check(Number(display.blocks[0].contentSourceStart) ===
          expectedContentStart && validRect(headingBoundaryCaret) &&
          Math.abs(Number(headingBoundaryCaret.x) -
            Number(display.horizontalPadding)) < 1.5,
        "Preview hides the valid #### heading prefix while keeping the source " +
          "caret at the visible W boundary: " + JSON.stringify({
            block: display.blocks[0], caret: headingBoundaryCaret }))
    }

    if (spec.name === "crlf-quote-table") {
      var secondQuote = display.cursorRectangleForSource(
        spec.source.indexOf("two") + 3)
      var tableLast = display.cursorRectangleForSource(
        spec.source.lastIndexOf("y") + 1)
      check(validRect(secondQuote) && validRect(tableLast) &&
        tableLast.y > secondQuote.y,
        "CRLF quote and table carets retain original source offsets")
    }

    if (spec.name === "quote-mouse-hit") {
      var quoteBlock = display.blocks[0]
      var quoteBlockItem = display.blockItemForValue(quoteBlock)
      var nestedMarker = spec.source.indexOf("> > Markdown") + 2
      var nestedMarkdown = spec.source.indexOf("Markdown", nestedMarker)
      var markdownInside = nestedMarkdown + 4
      var markdownCaret = display.cursorRectangleForSource(markdownInside)
      var quotePoint = quoteBlockItem.quoteTextReference.mapFromItem(
        display, markdownCaret.x + markdownCaret.width / 2,
        markdownCaret.y + markdownCaret.height / 2)
      var quoteLocalX = quotePoint.x
      var quoteLocalY = quotePoint.y
      var quoteMapped = display.quoteSourcePosition(
        quoteBlock, quoteBlockItem.quoteHitProbeReference,
        quoteLocalX, quoteLocalY)
      var quoteWord = display.sourceWordSelectionRange(quoteMapped)
      check(quoteMapped >= nestedMarkdown &&
        quoteMapped <= nestedMarkdown + "Markdown".length &&
        spec.source.slice(quoteWord.start, quoteWord.end) === "Markdown",
        "quote clicks and double-click selection map to the visible word: " +
          JSON.stringify({mapped: quoteMapped, word: quoteWord}))

      var richStart = spec.source.indexOf("rich")
      var richEnd = richStart + "rich".length
      var richCaret = display.cursorRectangleForSource(richEnd)
      var dragTarget = display.sourcePositionForPoint(
        richCaret.x + richCaret.width / 2,
        richCaret.y + richCaret.height / 2)
      var nestedMarkerCaret = display.cursorRectangleForSource(nestedMarker)
      var markerTarget = display.sourcePositionForPoint(
        nestedMarkerCaret.x + nestedMarkerCaret.width / 2,
        nestedMarkerCaret.y + nestedMarkerCaret.height / 2)
      check(dragTarget >= richStart && dragTarget <= richEnd &&
        markerTarget >= nestedMarker && markerTarget <= nestedMarker + 1,
        "quote drag selection resolves the visible nested marker and target word: " +
          JSON.stringify({marker: markerTarget, target: dragTarget,
            expectedMarker: nestedMarker, expectedTarget: richEnd}))
    }

    if (spec.name === "code-language-mouse-hit") {
      var languageBlock = display.blocks[0]
      var languageBlockItem = display.blockItemForValue(languageBlock)
      var languageStart = spec.source.indexOf("javascript")
      var languagePosition = languageStart + 5
      var languageCaret = display.cursorRectangleForSource(languagePosition)
      var languageLocalX = languageCaret.x - display.horizontalPadding -
        languageBlockItem.codeReference.x + languageCaret.width / 2
      var languageLocalY = languageCaret.y - display.verticalPadding -
        metrics[0].y - languageBlockItem.codeReference.y +
        languageCaret.height / 2
      var languageMapped = display.codeSourcePosition(
        languageBlock, languageLocalX, languageLocalY)
      check(languageMapped >= spec.source.indexOf("javascript") &&
        languageMapped <= spec.source.indexOf("javascript") +
          "javascript".length,
        "clicking the rendered code language maps into its source token: " +
          JSON.stringify({mapped: languageMapped,
            expected: languagePosition}))
      var languageColumnsIncrease = true
      var previousLanguageX = -1
      for (var languageOffset = 0;
           languageOffset <= "javascript".length; languageOffset++) {
        var columnCaret = display.cursorRectangleForSource(
          languageStart + languageOffset)
        if (!validRect(columnCaret) ||
            previousLanguageX >= 0 && columnCaret.x <= previousLanguageX) {
          languageColumnsIncrease = false
          break
        }
        previousLanguageX = columnCaret.x
      }
      check(languageColumnsIncrease,
        "arrowing through a code language advances one stable caret column")
      var indentationStart = spec.source.indexOf("    reutrn")
      var indentationLeft = display.cursorRectangleForSource(indentationStart)
      var indentationRight = display.cursorRectangleForSource(
        indentationStart + 4)
      check(validRect(indentationLeft) && validRect(indentationRight) &&
        indentationRight.x > indentationLeft.x + 1,
        "highlighted welcome-note code preserves four-space caret geometry: " +
          JSON.stringify({left: indentationLeft, right: indentationRight}))
    }

    if (spec.name === "empty-bullet-whitespace") {
      var bulletMarkerCaret = display.cursorRectangleForSource(0)
      var bulletAfterMarkerCaret = display.cursorRectangleForSource(1)
      var bulletAfterFirstSpaceCaret = display.cursorRectangleForSource(2)
      var bulletAfterSecondSpaceCaret = display.cursorRectangleForSource(3)
      check(validRect(bulletMarkerCaret) &&
        validRect(bulletAfterMarkerCaret) &&
        validRect(bulletAfterFirstSpaceCaret) &&
        validRect(bulletAfterSecondSpaceCaret) &&
        bulletAfterFirstSpaceCaret.x > bulletAfterMarkerCaret.x + 1 &&
        bulletAfterSecondSpaceCaret.x > bulletAfterFirstSpaceCaret.x + 1,
        "empty-bullet separator spaces receive distinct caret columns: " +
        JSON.stringify({marker: bulletMarkerCaret,
          afterMarker: bulletAfterMarkerCaret,
          firstSpace: bulletAfterFirstSpaceCaret,
          secondSpace: bulletAfterSecondSpaceCaret}))
    }

    if (spec.name === "empty-bullet-whitespace" ||
        spec.name === "empty-bullet-more-whitespace") {
      var emptyBulletCaret = display.cursorRectangleForSource(
        spec.source.length)
      check(validRect(emptyBulletCaret),
        "empty bullet keeps a visible caret after separator spaces")
      if (shell.previousEmptyBulletCaretX >= 0) {
        check(emptyBulletCaret.x > shell.previousEmptyBulletCaretX + 1,
          "caret moves right when the live empty bullet gains spaces: " +
          JSON.stringify({previousX: shell.previousEmptyBulletCaretX,
            currentX: emptyBulletCaret.x, source: spec.source}))
      }
      shell.previousEmptyBulletCaretX = Number(emptyBulletCaret.x)
    }

    if (spec.name === "nested-list") {
      var parent = display.cursorRectangleForSource(spec.source.indexOf("parent"))
      var child = display.cursorRectangleForSource(spec.source.indexOf("child"))
      var deep = display.cursorRectangleForSource(spec.source.indexOf("deep"))
      check(validRect(parent) && validRect(child) && validRect(deep) &&
        child.x > parent.x && deep.x > child.x,
        "nested list caret columns increase with indentation")

      var nestedListRows = metrics[0].listItems || []
      var firstNestedItem = display.blocks[0].items[0]
      var firstSelectable = display.listItemFirstSelectablePosition(
        firstNestedItem)
      check(firstSelectable === spec.source.indexOf("parent") &&
        validRect(display.cursorRectangleForSource(firstSelectable)) &&
        nestedListRows.length > 0 &&
        Number(nestedListRows[0].markerCursorShape) ===
          Number(Qt.IBeamCursor) &&
        Boolean(nestedListRows[0].markerHitEnabled),
        "clicking a bullet marker targets the left edge of its first text: " +
        JSON.stringify({firstSelectable: firstSelectable,
          expected: spec.source.indexOf("parent"),
          firstRow: nestedListRows[0]}))
    }

    if (spec.name === "list-container-continuations") {
      check(display.blocks[0].items.length === 2 &&
        String(display.blocks[0].items[0].html).indexOf(
          "continuation paragraph") >= 0 &&
        String(display.blocks[0].items[0].html).indexOf(
          "│ nested quote") >= 0 &&
        String(display.blocks[0].items[0].html).slice(-4) === "<br>",
        "list items retain continuation paragraphs, nested quotes, and loose spacing: " +
          JSON.stringify(display.blocks[0].items))
      var parentCaret = display.cursorRectangleForSource(
        spec.source.indexOf("parent"))
      var continuationCaret = display.cursorRectangleForSource(
        spec.source.indexOf("continuation"))
      var quoteCaret = display.cursorRectangleForSource(
        spec.source.indexOf("nested quote"))
      check(validRect(parentCaret) && validRect(continuationCaret) &&
        validRect(quoteCaret) && continuationCaret.y > parentCaret.y &&
        quoteCaret.y > continuationCaret.y,
        "list container caret geometry follows each nested source row")
    }

    if (spec.name === "table") {
      check(display.blocks.length === 1 && display.blocks[0].columnWidths.length === 2,
        "table retains both columns")
      check(display.blocks[0].rowHeights.length === 2 &&
        Number(metrics[0].height) > 0,
        "table header and body rows have rendered height")
      var tableRows = metrics[0].tableRows || []
      var shortRowsFit = true
      for (var shortRow = 0; shortRow < tableRows.length; shortRow++) {
        if (Number(tableRows[shortRow].height) + 0.5 <
            Number(tableRows[shortRow].requiredHeight)) shortRowsFit = false
      }
      check(shortRowsFit, "table rows contain their rendered cell text: " +
        JSON.stringify(tableRows))
      var tableA = display.cursorRectangleForSource(spec.source.indexOf("A"))
      var tableB = display.cursorRectangleForSource(spec.source.indexOf("B"))
      check(validRect(tableA) && validRect(tableB) && tableB.x > tableA.x,
        "table caret follows the active cell column")
    }

    if (spec.name === "wrapped-table-cell") {
      var wrappedTableRows = metrics[0].tableRows || []
      var wrappedRowsFit = true
      for (var wrappedRow = 0; wrappedRow < wrappedTableRows.length; wrappedRow++) {
        if (Number(wrappedTableRows[wrappedRow].height) + 0.5 <
            Number(wrappedTableRows[wrappedRow].requiredHeight)) wrappedRowsFit = false
      }
      check(wrappedRowsFit, "wrapped table cell stays inside its row: " +
        JSON.stringify(wrappedTableRows))
      var tableCellStart = display.cursorRectangleForSource(
        spec.source.indexOf("one"))
      var tableCellEnd = display.cursorRectangleForSource(
        spec.source.indexOf("twelve") + "twelve".length)
      check(validRect(tableCellStart) && validRect(tableCellEnd) &&
        tableCellEnd.y > tableCellStart.y,
        "caret follows a soft-wrapped table cell")
    }

    if (spec.name === "gfm-table-compatibility") {
      check(display.blocks[0].columnWidths.length === 1 &&
        display.blocks[0].alignments.toString() === "center",
        "one-column GFM tables render and retain centered alignment")
      check(display.blocks[2].alignments.toString() === "left,right" &&
        display.blocks[2].rows.length === 3 &&
        display.blocks[2].rows[1].length === 2 &&
        display.blocks[2].rows[1][0].plain === "\\|" &&
        display.blocks[2].rows[1][1].plain === "`a|b`" &&
        display.blocks[2].rows[2][1].plain === "[go](https://a|b)",
        "table alignment and escaped, code-span, or link pipes preserve cell boundaries")
    }

    if (spec.name === "unclosed-fenced-code") {
      check(display.blocks.length === 1 && display.blocks[0].type === "code" &&
        display.blocks[0].text === "code to eof" &&
        display.blocks[0].sourceEnd === spec.source.length,
        "an unclosed CommonMark fence continues through end-of-document")
    }

    if (spec.name === "indented-fenced-code") {
      check(display.blocks.length === 1 &&
        display.blocks[0].codeIndent === 2 &&
        display.blocks[0].text === "alpha\nx\n  y",
        "fenced code removes up to the opening fence indentation: " +
          JSON.stringify(display.blocks[0]))
      var hiddenIndentStart = display.cursorRectangleForSource(
        spec.source.indexOf("  alpha"))
      var hiddenIndentEnd = display.cursorRectangleForSource(
        spec.source.indexOf("alpha"))
      check(validRect(hiddenIndentStart) && validRect(hiddenIndentEnd) &&
        Math.abs(hiddenIndentStart.x - hiddenIndentEnd.x) < 1.5,
        "removed fenced-code indentation collapses to one editable boundary")
    }

    if (spec.name === "task-list") {
      var taskMarker = display.cursorRectangleForSource(spec.source.indexOf("-"))
      var taskText = display.cursorRectangleForSource(spec.source.indexOf("test"))
      check(validRect(taskMarker) && validRect(taskText) &&
        taskText.x > taskMarker.x,
        "task text starts after its checkbox marker")
      var taskRows = metrics[0].listItems || []
      check(taskRows.length === 3,
        "all checked and unchecked task rows expose checkbox geometry")
      for (var taskRowIndex = 0; taskRowIndex < taskRows.length; taskRowIndex++) {
        var taskRow = taskRows[taskRowIndex]
        var expectedCheckboxY = Math.max(0,
          taskRow.textBaseline + taskRow.fontCapTop +
            (taskRow.fontCapHeight - taskRow.checkboxHeight) / 2)
        check(Math.abs(taskRow.checkboxY - expectedCheckboxY) <= 0.5,
          "task checkbox " + taskRowIndex +
            " is centered on the font cap-height at the text baseline: " +
            JSON.stringify(taskRow))
      }
      var fsdafStart = spec.source.indexOf("fsdaf")
      check(Number(taskRows[2].hitAfterTwoPosition) === fsdafStart + 2,
        "clicking between fs and daf maps to the exact source column: " +
          JSON.stringify(taskRows[2]))
      check(Number(taskRows[2].hitAfterFourPosition) === fsdafStart + 4 &&
        Number(taskRows[2].hitAfterFourPosition) -
          Number(taskRows[2].hitAfterTwoPosition) === 2,
        "dragging from fs to fsda maps to the exact source selection: " +
          JSON.stringify(taskRows[2]))
      check(Number(taskRows[2].textCursorShape) === Number(Qt.IBeamCursor),
        "task text exposes the standard I-beam mouse cursor: " +
          JSON.stringify(taskRows[2]))
      var availableListWidth = Math.max(1,
        display.width - display.horizontalPadding * 2)
      var checkedListKey = display.measuredBlockHeightCacheKeyForSource(
        "list", spec.source, availableListWidth)
      var uncheckedListKey = display.measuredBlockHeightCacheKeyForSource(
        "list", spec.source.replace("- [x] test", "- [ ] test"),
        availableListWidth)
      check(checkedListKey === uncheckedListKey &&
          display.measuredBlockHeightSource(display.blocks[0]).indexOf(
            "- [x]") < 0,
        "checking a task reuses identical measured list geometry instead of " +
          "moving neighboring text")
    }

    if (spec.name === "quote-rule-code") {
      var quoteCaret = display.cursorRectangleForSource(metrics[0].sourceStart)
      var ruleCaret = display.cursorRectangleForSource(metrics[2].sourceStart)
      var codeCaret = display.cursorRectangleForSource(metrics[4].sourceStart)
      check(validRect(quoteCaret) && validRect(ruleCaret) && validRect(codeCaret) &&
        ruleCaret.y > quoteCaret.y && codeCaret.y > ruleCaret.y,
        "quote, rule, and code blocks have ordered caret rows")

      var codeGapBlock = display.blocks[3]
      var codeGapCaret = display.cursorRectangleForSource(
        codeGapBlock.sourceStart)
      var codeTop = Number(display.verticalPadding) + Number(metrics[4].y) +
        Number(metrics[4].codeContentY)
      var codeLabelTop = codeTop + Number(metrics[4].codeLabelY)
      var followingCodeCaret = display.followingCursorRectangleForSource(
        codeGapBlock.sourceStart)
      check(validRect(codeGapCaret) && metrics[4].codeLabel === "Dart" &&
        Number(codeGapCaret.y + codeGapCaret.height) <= codeLabelTop + 1.5 &&
        validRect(followingCodeCaret) &&
        Math.abs(Number(followingCodeCaret.y) - codeTop) < 1.5,
        "a blank row before a labeled code block stays above its code surface: " +
        JSON.stringify({blank: codeGapCaret, following: followingCodeCaret,
          codeTop: codeTop, codeLabelTop: codeLabelTop,
          metrics: metrics[4]}))
    }

    if (spec.name === "nested-quote-list-structure") {
      var structuralQuoteHtml = String(display.blocks[0].html || "")
      check(structuralQuoteHtml.indexOf("• item") >= 0 &&
        structuralQuoteHtml.indexOf("• nested") >= 0 &&
        structuralQuoteHtml.indexOf("│ deep quote") >= 0 &&
        structuralQuoteHtml.indexOf("<br><br>") >= 0,
        "quote-contained lists, nested quotes, and paragraph breaks retain structure: " +
          structuralQuoteHtml)
    }

    if (spec.name === "fenced-code-selection") {
      var codeBlock = display.blocks[2]
      var codeStart = spec.source.indexOf("code line")
      var codeHit = display.codeSourcePosition(
        codeBlock, 10, 10)
      check(codeHit === codeStart,
        "clicking the code surface maps to the first code source column: " +
        JSON.stringify({hit: codeHit, expected: codeStart}))
      check(Number(metrics[2].codeLineCount) >= 2,
        "fenced code preserves each literal source line: " +
        JSON.stringify(metrics[2]))

      var codeSelectionVisible = false
      for (var codeRectIndex = 0;
           codeRectIndex < display.selectionRects.length; codeRectIndex++) {
        var codeRect = display.selectionRects[codeRectIndex]
        if (Number(codeRect.y) >= Number(metrics[2].y) &&
            Number(codeRect.height) >= 20 &&
            Number(codeRect.width) > Number(display.width) * 0.8) {
          codeSelectionVisible = true
          break
        }
      }
      check(codeSelectionVisible,
        "select-all keeps the fenced code surface visibly highlighted")
    }

    if (spec.name === "dart-code-highlighting") {
      check(display.blocks[0].language === "dart" &&
        metrics[0].codeLanguage === "dart" &&
        metrics[0].codeLabel === "Dart" &&
        metrics[0].codeDefinitionName === "Dart",
        "Dart fences show their language label and resolve to the bundled " +
        "native syntax definition: " +
        JSON.stringify({block: display.blocks[0], metrics: metrics[0]}))
      check(display.codeLanguageFromInfo("js title=demo") === "javascript" &&
        display.codeLanguageFromInfo("not-a-real-language") === "",
        "language aliases resolve while unknown fences stay unhighlighted")
      check(validRect(display.cursorRectangleForSource(
        spec.source.indexOf("answer") + "answer".length)),
        "highlighted Dart code retains source caret geometry")
      var pendingBlock = Object.assign({}, display.blocks[0], {
        text: "final    value\n\tnewest"
      })
      var pendingMarkup = display.codeHighlightMarkup(pendingBlock)
      check(pendingMarkup.indexOf("final&nbsp;&nbsp;&nbsp;&nbsp;value") >= 0 &&
        pendingMarkup.indexOf("<br/>&nbsp;&nbsp;&nbsp;&nbsp;newest") >= 0,
        "pending syntax highlighting keeps the newest code and whitespace " +
        "painted without swapping visible layers: " + pendingMarkup)

      display.codeHighlightDeferred = ({})
      var firstPendingBlock = Object.assign({}, display.blocks[0], {
        text: "final first"
      })
      var latestPendingBlock = Object.assign({}, display.blocks[0], {
        text: "final latest"
      })
      display.requestCodeHighlight(firstPendingBlock)
      display.requestCodeHighlight(latestPendingBlock)
      var deferredSlots = Object.keys(display.codeHighlightDeferred)
      check(display.codeHighlightDelayMs >= 400 && deferredSlots.length === 1 &&
        display.codeHighlightDeferred[deferredSlots[0]].key ===
          display.codeHighlightKey(latestPendingBlock),
        "rapid code edits coalesce into one delayed highlight request: " +
        JSON.stringify(display.codeHighlightDeferred))
    }

    if (spec.name === "adjacent-highlighted-code-blocks") {
      var firstCodeItem = display.blockItemForValue(display.blocks[0])
      var secondCodeItem = display.blockItemForValue(display.blocks[1])
      var firstCodePaint = firstCodeItem
        ? firstCodeItem.codePaintReference : null
      var secondCodePaint = secondCodeItem
        ? secondCodeItem.codePaintReference : null
      check(display.blocks[0].language === "javascript" &&
        display.blocks[1].language === "python" &&
        metrics[0].codeLabel === "JavaScript" &&
        metrics[1].codeLabel === "Python",
        "adjacent fences retain independent language definitions: " +
          JSON.stringify({blocks: display.blocks, metrics: metrics}))
      check(firstCodePaint && secondCodePaint &&
        String(firstCodePaint.text).indexOf("function test") >= 0 &&
        String(secondCodePaint.text).indexOf("messafe") >= 0 &&
        String(secondCodePaint.text).indexOf("print(message)") >= 0 &&
        Number(firstCodePaint.height) > 0 && Number(secondCodePaint.height) > 0,
        "both adjacent highlighted code bodies remain painted: " +
          JSON.stringify({firstText: firstCodePaint ? firstCodePaint.text : "",
            secondText: secondCodePaint ? secondCodePaint.text : "",
            firstHeight: firstCodePaint ? firstCodePaint.height : 0,
            secondHeight: secondCodePaint ? secondCodePaint.height : 0}))
      check(validRect(display.cursorRectangleForSource(
          spec.source.indexOf("messafe"))) &&
        validRect(display.cursorRectangleForSource(
          spec.source.indexOf("print(message)"))),
        "the Python body keeps caret geometry on every source row")
    }

    if (spec.name === "partial-fence-language-caret") {
      var languageCaret = display.cursorRectangleForSource(
        spec.source.indexOf("b") + 1)
      var codeTop = Number(display.verticalPadding) + Number(metrics[0].y) +
        Number(metrics[0].codeContentY)
      var labelTop = codeTop + Number(metrics[0].codeLabelY)
      var labelCenter = labelTop + Number(metrics[0].codeLabelHeight) / 2
      check(metrics[0].codeLabel === "b" &&
        Number(metrics[0].codeLabelHeight) > 0 && validRect(languageCaret) &&
        Math.abs(Number(languageCaret.y + languageCaret.height / 2) -
          labelCenter) < 1.5 &&
        Number(languageCaret.y) < codeTop + Number(metrics[0].codeTextY),
        "caret stays on the partially typed language label: " +
        JSON.stringify({caret: languageCaret, metrics: metrics[0]}))
    }

    if (spec.name === "fenced-code-last-line-caret") {
      var firstCodeLine = display.cursorRectangleForSource(
        spec.source.indexOf("st\n"))
      var middleCodeLine = display.cursorRectangleForSource(
        spec.source.indexOf("ststttt"))
      var lastCodeLine = display.cursorRectangleForSource(
        spec.source.indexOf("fvff"))
      var codeAdvance = Number(metrics[0].codeLineAdvance)
      check(Number(metrics[0].codeLineCount) >= 4 &&
        validRect(firstCodeLine) && validRect(middleCodeLine) &&
        validRect(lastCodeLine),
        "fenced code exposes caret geometry for every literal line: " +
        JSON.stringify({metrics: metrics[0], first: firstCodeLine,
          middle: middleCodeLine, last: lastCodeLine}))
      check(lastCodeLine.y > middleCodeLine.y &&
        Math.abs((lastCodeLine.y - middleCodeLine.y) - codeAdvance) < 1.5,
        "caret on the final fenced-code line follows the measured row: " +
        JSON.stringify({middle: middleCodeLine, last: lastCodeLine,
          codeAdvance: codeAdvance}))
    }

    if (spec.name === "fenced-code-escape-row") {
      var codeEnd = display.cursorRectangleForSource(
        spec.source.indexOf("code") + "code".length)
      var afterFence = display.cursorRectangleForSource(spec.source.length)
      var escapeTarget = display.cursorTargetForSource(spec.source.length)
      check(validRect(codeEnd) && validRect(afterFence) &&
        escapeTarget.blockType === "blank" &&
        afterFence.y > codeEnd.y,
        "a trailing source row exposes a caret outside the fenced code block: " +
        JSON.stringify({codeEnd: codeEnd, afterFence: afterFence,
          target: escapeTarget}))
    }

    if (spec.name === "fenced-code-trailing-space-row") {
      var trailingCodeCaret = display.cursorRectangleForSource(
        spec.source.indexOf("fvff\n ") + "fvff\n ".length)
      var trailingCodeBottom = Number(display.verticalPadding) +
        Number(metrics[0].y) + Number(metrics[0].height)
      check(Number(metrics[0].codeSourceLineCount) >= 5 &&
        validRect(trailingCodeCaret),
        "trailing whitespace code row has source and caret geometry: " +
        JSON.stringify({metrics: metrics[0], caret: trailingCodeCaret}))
      check(Number(trailingCodeCaret.y + trailingCodeCaret.height) <=
        trailingCodeBottom + 1.5,
        "caret on a trailing code row stays inside the fenced surface: " +
        JSON.stringify({caret: trailingCodeCaret, codeBottom: trailingCodeBottom,
          metrics: metrics[0]}))
    }

    if (spec.name === "special-characters") {
      check(String(display.blocks[0].html).indexOf("&lt;tag&gt;") >= 0,
        "HTML-looking text is escaped before rich-text rendering")
    }

    if (spec.name === "crlf-source") {
      check(display.layoutSourceText === spec.source,
        "CRLF source is retained as the layout input")
      var crlfNewline = display.cursorRectangleForSource(6)
      var crlfList = display.cursorRectangleForSource(spec.source.indexOf("-"))
      check(validRect(crlfNewline) && validRect(crlfList) &&
        crlfList.y > crlfNewline.y,
        "CRLF newline positions and following blocks retain caret order")
    }

    if (spec.name === "active-incomplete-list-marker") {
      var marker = display.cursorRectangleForSource(spec.source.length)
      check(validRect(marker), "bare list marker keeps a visible caret")
    }
  }

  function inspectCase() {
    var spec = currentCase()
    var metrics = display.layoutMetricsForTests()
    if (!display.layoutReady || !display.layoutMatchesCurrentInput()) {
      settleAttempts++
      if (settleAttempts > 20) {
        check(false, "layout did not settle after " + settleAttempts + " attempts")
        advanceCase()
      } else {
        settleTimer.restart()
      }
      return
    }

    console.log("ISOLATED_CASE: " + spec.name + " " + JSON.stringify({
      types: actualTypes(metrics),
      sourceLength: spec.source.length,
      selectionRectCount: display.selectionRects.length
    }))
    var expectedTypes = spec.editedExpectedTypes && editStabilityPhase === 1
      ? spec.editedExpectedTypes : spec.expectedTypes
    check(actualTypes(metrics).toString() === expectedTypes.toString(),
      "block types match expected Markdown structure: " +
      JSON.stringify(actualTypes(metrics)))
    checkFiniteMetrics(metrics)
    checkRevisionedBlockModel(metrics)
    // The dedicated long-note fixture samples every rendered block and its
    // live hit-test path below; walking all 5,000 source positions would test
    // the same caret mapping while obscuring the interactive latency budget.
    if (spec.name !== "selection-performance")
      checkCaretCoverage(spec.source)
    if (spec.selectAll || spec.selectionEnd > spec.selectionStart) {
      checkSelectionGeometry(spec.source, Boolean(spec.selectAll))
    }
    if (spec.name === "inline-markdown")
      checkMouseSelectionCoalescing(metrics)
    if (spec.name === "selection-performance") {
      checkSelectionLookupPerformance(metrics)
      checkSourceColumnLookupPerformance()
    }
    checkCaseSpecific(spec, metrics)
    if (spec.name === "task-list-toggle-stability") {
      if (taskToggleStabilityPhase === 0) {
        taskToggleStableLayoutRevision = Number(display.layoutRevision)
        taskToggleStableMetrics = metrics
        taskToggleStabilityPhase = 1
        activeSource = spec.source.replace("- [x] first task",
          "- [ ] first task")
        settleAttempts = 0
        settleTimer.restart()
        return
      }

      var beforeList = taskToggleStableMetrics[0]
      var afterList = metrics[0]
      var beforeFollowing = taskToggleStableMetrics[2]
      var afterFollowing = metrics[2]
      check(Number(display.layoutRevision) ===
          taskToggleStableLayoutRevision &&
          Number(afterList.geometryHeight) ===
            Number(beforeList.geometryHeight) &&
          Number(afterList.listItems[0].itemY) ===
            Number(beforeList.listItems[0].itemY) &&
          Number(afterList.listItems[1].itemY) ===
            Number(beforeList.listItems[1].itemY) &&
          Number(afterFollowing.y) === Number(beforeFollowing.y) &&
          afterList.listItems[0].checked === false,
        "task state repaints without rebuilding or moving list and following text: " +
          JSON.stringify({before: taskToggleStableMetrics, after: metrics,
            beforeRevision: taskToggleStableLayoutRevision,
            afterRevision: display.layoutRevision}))
      taskToggleStabilityPhase = 0
    }
    if (spec.editedSource) {
      if (editStabilityPhase === 0) {
        editStableLayoutRevision = Number(display.layoutRevision)
        editStableMetrics = metrics
        editStableCaret = display.cursorRectangleForSource(activeCursor)
        editStabilityPhase = 1
        activeSource = String(spec.editedSource)
        if (spec.editedCursor !== undefined)
          activeCursor = Number(spec.editedCursor)
        settleAttempts = 0
        settleTimer.restart()
        return
      }

      var geometryStable = metrics.length === editStableMetrics.length
      for (var stableIndex = 0;
           geometryStable && stableIndex < metrics.length; stableIndex++) {
        geometryStable = Number(metrics[stableIndex].y) ===
            Number(editStableMetrics[stableIndex].y) &&
          Number(metrics[stableIndex].height) ===
            Number(editStableMetrics[stableIndex].height)
      }
      var changedIndex = Number(spec.changedBlockIndex) || 0
      var changedBlockSettledAtSameHeight = spec.editedExpectedTypes
        ? Number(metrics[changedIndex].geometryHeight) ===
            Number(editStableMetrics[changedIndex].geometryHeight)
        : Number(metrics[changedIndex].provisionalHeight) ===
            Number(editStableMetrics[changedIndex].geometryHeight)
      var editedCaret = display.cursorRectangleForSource(activeCursor)
      var caretStable = !spec.editedExpectedTypes ||
        (validRect(editStableCaret) && validRect(editedCaret) &&
          Math.abs(Number(editedCaret.y) - Number(editStableCaret.y)) < 0.5)
      check(Number(display.layoutRevision) ===
          editStableLayoutRevision + 1 && geometryStable &&
          changedBlockSettledAtSameHeight && caretStable,
        spec.name + " keeps every unaffected block fixed while the changed " +
          "block reuses its settled height: " + JSON.stringify({
            before: editStableMetrics, after: metrics,
            beforeCaret: editStableCaret, afterCaret: editedCaret,
            beforeRevision: editStableLayoutRevision,
            afterRevision: display.layoutRevision}))
      editStabilityPhase = 0
      editStableCaret = null
    }
    console.log("ISOLATED_PASS: " + spec.name)
    captureOrAdvance(spec)
  }

  function captureOrAdvance(spec) {
    if (!captureDirectory) {
      advanceCase()
      return
    }
    captureSurface.grabToImage(function(result) {
      var path = captureDirectory + "/" + spec.name + ".png"
      if (!result.saveToFile(path)) {
        failures.push("case " + spec.name + ": could not save " + path)
        console.log("ISOLATED_FAIL: case " + spec.name +
          ": could not save " + path)
      }
      advanceCase()
    })
  }

  function advanceCase() {
    caseIndex++
    if (caseIndex >= cases.length) {
      console.log("ISOLATED_RESULT: " + JSON.stringify({
        caseCount: cases.length,
        failures: failures
      }))
      Qt.exit(failures.length === 0 ? 0 : 1)
      return
    }
    loadCase()
  }

  function loadCase() {
    var spec = currentCase()
    var source = String(spec.source || "")
    var cursor = Number(spec.cursor)
    if (!isFinite(cursor) || cursor < 0) cursor = source.length
    if (spec.cursorToken) {
      var tokenPosition = source.indexOf(spec.cursorToken)
      if (tokenPosition >= 0) cursor = tokenPosition
    }
    if (spec.cursorTokenEnd) {
      var tokenEndPosition = source.indexOf(spec.cursorTokenEnd)
      if (tokenEndPosition >= 0) {
        cursor = tokenEndPosition + String(spec.cursorTokenEnd).length
      }
    }
    activeSource = source
    activeCursor = Math.max(0, Math.min(cursor, source.length))
    activeSelectionStart = spec.selectAll ? 0 : Number(spec.selectionStart || 0)
    activeSelectionEnd = spec.selectAll ? source.length :
      Number(spec.selectionEnd || 0)
    activeWidth = Number(spec.width || 720)
    editStabilityPhase = 0
    settleAttempts = 0
    settleTimer.restart()
  }

  Component.onCompleted: loadCase()
}
