import QtQuick
import QtTest

Item {
  id: scene
  width: 420
  height: 300

  NativeMarkdownDisplay {
    id: display
    anchors.fill: parent
    bodyPixelSize: 16
    fontFamily: "monospace"
    foreground: "white"
    background: "black"
    surfaceBackground: "black"
    accent: "#00ffff"
  }

  // Hand-authored expected HTML, laid out independently of the production
  // parser and source map. Share typography only, never hit-test coordinates.
  TextEdit {
    id: reference
    visible: false
    width: display.width
    textFormat: TextEdit.RichText
    wrapMode: TextEdit.Wrap
    font.family: display.fontFamily
    font.pixelSize: display.bodyPixelSize
    leftPadding: display.horizontalPadding
    rightPadding: display.horizontalPadding
    topPadding: display.verticalPadding
    bottomPadding: display.verticalPadding
  }

  TestCase {
    name: "NativeLinkContract"
    when: windowShown
    SignalSpy { id: activated; target: display; signalName: "linkActivated" }

    function test_link_contract_data() {
      return [
        {tag: "inline", source: "Open [test](https://example.com) end.",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test"},
        {tag: "repeated-label", source: "test before [test](https://example.com) end.",
          html: 'test before <a href="https://example.com">test</a> end.', label: "test"},
        {tag: "bold-label", source: "Open [**test**](https://example.com) end.",
          html: 'Open <a href="https://example.com"><strong>test</strong></a> end.', label: "test"},
        {tag: "reference", source: "Open [test][target] end.\n\n[target]: https://example.com",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test"},
        {tag: "autolink", source: "Open <https://example.com> end.",
          html: 'Open <a href="https://example.com">https://example.com</a> end.', label: "https://example.com"},
        {tag: "wrapped", source: "Open [a long link label with several words that wraps around](https://example.com) end.",
          html: 'Open <a href="https://example.com">a long link label with several words that wraps around</a> end.',
          label: "a long link label with several words that wraps around"},
        {tag: "padded", source: "Open [test](https://example.com) end.",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test", padding: 37},
        {tag: "asymmetric-padding", source: "Open [test](https://example.com) end.",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test", padding: 37, top: 9},
        {tag: "zero-padding", source: "Open [test](https://example.com) end.",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test", padding: 0},
        {tag: "word-wrap", source: "Open [abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz](https://example.com) end.",
          html: 'Open <a href="https://example.com">abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz</a> end.',
          label: "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"},
        {tag: "proportional-font", source: "Open [wide and thin letters](https://example.com) end.",
          html: 'Open <a href="https://example.com">wide and thin letters</a> end.',
          label: "wide and thin letters", font: "sans-serif"},
        {tag: "collapsed-reference", source: "Open [test][] end.\n\n[test]: https://example.com",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test"},
        {tag: "shortcut-reference", source: "Open [test] end.\n\n[test]: https://example.com",
          html: 'Open <a href="https://example.com">test</a> end.', label: "test"}
      ]
    }

    function test_link_contract(data) {
      display.horizontalPadding = data.padding === undefined ? 16 : data.padding
      display.verticalPadding = data.top === undefined ? display.horizontalPadding : data.top
      display.fontFamily = data.font || "monospace"
      display.sourceText = data.source
      reference.text = display.styledDocumentHtml("<p>" + data.html + "</p>")
      tryVerify(function() {
        return display.layoutMatchesCurrentInput() && !display.parsePending &&
          !display.parseInFlight && display.pendingStyledReconcileRequestId < 0
      }, 15000)
      var plain = reference.getText(0, reference.length)
      var start = plain.lastIndexOf(data.label)
      verify(start >= 0)
      activated.clear()
      var clicks = 0
      var rows = []
      for (var i = 0; i < data.label.length; i++) {
        var a = reference.positionToRectangle(start + i)
        var b = reference.positionToRectangle(start + i + 1)
        // A line-ending whitespace has no painted glyph to click.
        if (a.y !== b.y && /\s/.test(data.label[i])) continue
        var x = a.y === b.y ? (a.x + b.x) / 2 : a.x + 2
        var y = a.y + a.height / 2
        if (a.y === b.y) {
          var row = rows.filter(function(r) { return r.y === a.y })[0]
          if (!row) {
            row = {y: a.y, height: a.height, left: a.x, right: b.x}
            rows.push(row)
          } else {
            row.left = Math.min(row.left, a.x, b.x)
            row.right = Math.max(row.right, a.x, b.x)
          }
        }
        compare(String(display.linkTargetForPoint(x, y)), "https://example.com",
          "independently laid-out label glyph " + i + " at " + x + "," + y)
        mouseClick(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
        compare(activated.count, ++clicks)
      }
      // Probe just outside a single-line label using only the independent
      // reference geometry; these are the points caret snapping can swallow.
      if (rows.length === 1) {
        var row = rows[0]
        var empty = [
          {x: row.left - 3, y: row.y + row.height / 2},
          {x: row.right + 3, y: row.y + row.height / 2},
          {x: (row.left + row.right) / 2, y: row.y - 3},
          {x: (row.left + row.right) / 2, y: row.y + row.height + 3}
        ]
        for (var e = 0; e < empty.length; e++) {
          if (empty[e].x < 0 || empty[e].y < 0) continue
          compare(String(display.linkTargetForPoint(empty[e].x, empty[e].y)), "",
            "independent label exterior " + JSON.stringify(empty[e]))
          mouseClick(scene, empty[e].x, empty[e].y, Qt.LeftButton, Qt.ControlModifier)
          compare(activated.count, clicks)
        }
      }
      // Sample the empty strip outside all rendered rows, without asking the
      // production source map where its supposed blank area is.
      for (var blankX = 2; blankX < scene.width; blankX += 23) {
        compare(String(display.linkTargetForPoint(blankX, scene.height - 8)), "")
        mouseClick(scene, blankX, scene.height - 8, Qt.LeftButton, Qt.ControlModifier)
        compare(activated.count, clicks)
      }
    }

    function test_marker_pixels() {
      display.fontFamily = "monospace"
      display.horizontalPadding = 16
      display.verticalPadding = 16
      display.sourceText = "Open [test](https://example.com) end."
      reference.text = display.styledDocumentHtml('<p>Open <a href="https://example.com">test</a> end.</p>')
      tryVerify(function() {
        return display.layoutMatchesCurrentInput() && !display.parsePending &&
          !display.parseInFlight && display.pendingStyledReconcileRequestId < 0
      }, 15000)
      var a = reference.positionToRectangle(6)
      var b = reference.positionToRectangle(7)
      var x = Math.round((a.x + b.x) / 2)
      var y = Math.round(a.y + a.height / 2)
      mouseMove(scene, x, y)
      display.controlKeyHeld = true
      tryCompare(display, "linkPointerMarkerVisible", true)
      waitForRendering(display)
      var painted = grabImage(scene)
      verify(painted.green(x, y) > 200 && painted.blue(x, y) > 200 && painted.red(x, y) < 40,
        "the application marker must actually paint cyan at the independent link point")
      display.controlKeyHeld = false
      waitForRendering(display)
      var released = grabImage(scene)
      verify(!painted.equals(released), "releasing Ctrl removes the painted marker")
    }

    function test_modifier_and_drag_boundaries() {
      display.fontFamily = "monospace"
      display.horizontalPadding = 16
      display.verticalPadding = 16
      display.sourceText = "[first](https://example.com/one) gap [second](https://example.com/two)"
      reference.text = display.styledDocumentHtml('<p><a href="https://example.com/one">first</a> gap <a href="https://example.com/two">second</a></p>')
      tryVerify(function() {
        return display.layoutMatchesCurrentInput() && !display.parsePending &&
          !display.parseInFlight && display.pendingStyledReconcileRequestId < 0
      }, 15000)
      var a = reference.positionToRectangle(2)
      var b = reference.positionToRectangle(12)
      var x = a.x + 2, y = a.y + a.height / 2
      var otherX = b.x + 2, otherY = b.y + b.height / 2
      activated.clear()
      // Releasing Ctrl before mouse-up cancels activation.
      mousePress(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
      mouseRelease(scene, x, y, Qt.LeftButton, Qt.NoModifier)
      compare(activated.count, 0)
      // Pressing Ctrl after an ordinary mouse-down cannot create activation.
      mousePress(scene, x, y, Qt.LeftButton, Qt.NoModifier)
      mouseRelease(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
      compare(activated.count, 0)
      // A second link is not the original gesture target.
      mousePress(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
      mouseMove(scene, otherX, otherY, 20, Qt.LeftButton, Qt.ControlModifier)
      mouseRelease(scene, otherX, otherY, Qt.LeftButton, Qt.ControlModifier)
      compare(activated.count, 0)
      // Returning to the initial label after a drag must not turn it into a click.
      mousePress(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
      mouseMove(scene, otherX, otherY, 20, Qt.LeftButton, Qt.ControlModifier)
      mouseMove(scene, x, y, 20, Qt.LeftButton, Qt.ControlModifier)
      mouseRelease(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
      compare(activated.count, 0)
      mouseClick(scene, x, y, Qt.LeftButton, Qt.ControlModifier)
      compare(activated.count, 1)
      compare(activated.signalArguments[0][0], "https://example.com/one")
    }

    function test_unresolved_reference_is_plain_text() {
      display.sourceText = "Open [test][missing] end."
      tryVerify(function() {
        return display.layoutMatchesCurrentInput() && !display.parsePending &&
          !display.parseInFlight && display.pendingStyledReconcileRequestId < 0
      }, 15000)
      activated.clear()
      display.controlKeyHeld = true
      for (var y = 5; y < 70; y += 9) {
        for (var x = 5; x < scene.width; x += 11) {
          compare(String(display.linkTargetForPoint(x, y)), "")
          mouseMove(scene, x, y, 0)
          compare(display.linkPointerMarkerVisible, false)
        }
      }
      display.controlKeyHeld = false
      compare(activated.count, 0)
    }
  }
}
