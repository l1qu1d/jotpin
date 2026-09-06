import QtQuick
import Quickshell

ShellRoot {
  id: test
  property int highlightPassCount: 0
  property bool spellingPassed: false
  property int spellingHeartbeatCount: 0
  property double spellingStartedAt: 0
  property string spellingSource: ""
  property int spellingPhase: 0
  property int initialCandidateCount: 0
  property int initialMisspellingCount: 0

  function spellingPerformanceSource() {
    var line = "garbanzo garble zymurgy server mispelled Omarchy JotPin Quickshell Hyprland " +
      "Wayland CommonMark GFM QML JSON YAML GDScript autosaves " +
      "callouts strikethrough Todos `codewurd` " +
      "https://example.test/badwurd\n"
    var source = ""
    while (source.length < 25 * 1024) source += line
    return source
  }

  Component.onCompleted: {
    highlightWorker.sendMessage({type: "highlight", key: "smoke",
      code: "if (true) {\n    const answer = 42\n}", language: "js",
      dark: true})
    highlightWorker.sendMessage({type: "highlight", key: "python",
      code: "messafe = \"Markdown stays simple.\"\nprint(message)",
      language: "python", dark: true})
    spellWorker.sendMessage({type: "init", personalWords: []})
  }

  WorkerScript {
    id: highlightWorker
    source: Qt.resolvedUrl("syntax/HighlightWorker.js")
    onMessage: function(message) {
      var javascriptValid = message.key === "smoke" &&
        message.markup.indexOf("<font color=") >= 0 &&
        message.markup.indexOf("&nbsp;&nbsp;&nbsp;&nbsp;") >= 0 &&
        message.markup.indexOf("const") >= 0
      var pythonValid = message.key === "python" &&
        message.markup.indexOf("<font color=") >= 0 &&
        message.markup.indexOf("messafe") >= 0 &&
        message.markup.indexOf("Markdown stays simple.") >= 0 &&
        message.markup.indexOf("print") >= 0
      if (message.type !== "highlighted" ||
          (!javascriptValid && !pythonValid)) {
        console.error("VENDOR_FAIL: Highlight.js bundle returned an unexpected result: " +
          JSON.stringify(message))
        Qt.quit()
        return
      }
      highlightPassCount++
      if (highlightPassCount === 2 && spellingPassed) {
        console.log("VENDOR_PASS: offline language bundles initialized")
        Qt.quit()
      }
    }
  }

  WorkerScript {
    id: spellWorker
    source: Qt.resolvedUrl("spellcheck/SpellcheckWorker.mjs")
    onMessage: function(message) {
      if (message.type === "ready") {
        spellingSource = spellingPerformanceSource()
        spellingHeartbeatCount = 0
        spellingStartedAt = Date.now()
        spellHeartbeatTimer.start()
        spellWorker.sendMessage({
          type: "check",
          requestId: 1,
          sourceRevision: 7,
          full: true,
          source: spellingSource
        })
      } else if (message.type === "checked") {
        var elapsed = Date.now() - spellingStartedAt
        var wrongMisspelling = message.misspellings.some(function(range) {
          return range.word !== "mispelled"
        })
        var invalidCandidate = message.candidates.some(function(candidate) {
          return spellingSource.slice(candidate.start, candidate.end) !==
            candidate.sourceWord
        })
        if (spellingPhase === 0 &&
            (message.requestId !== 1 || message.sourceRevision !== 7 ||
            message.misspellings.length < 100 || wrongMisspelling ||
            message.candidates.some(function(candidate) {
              return candidate.word === "codewurd" ||
                candidate.word === "fencedwurd" ||
                candidate.word === "badwurd"
            }) || invalidCandidate || !message.metrics.fullScan ||
            elapsed > 5000)) {
          console.error("VENDOR_FAIL: nspell bundle returned an unexpected result")
          Qt.quit()
          return
        }
        if (spellingPhase === 0) {
          initialCandidateCount = message.candidates.length
          initialMisspellingCount = message.misspellings.length
          console.log("VENDOR_SPELLCHECK_PERF: " + JSON.stringify({
            sourceBytes: spellingSource.length,
            candidates: initialCandidateCount,
            misspellings: initialMisspellingCount,
            elapsedMs: elapsed,
            uiHeartbeats: spellingHeartbeatCount
          }))
          var start = spellingSource.indexOf("mispelled")
          spellingSource = spellingSource.slice(0, start) + "misspelled" +
            spellingSource.slice(start + "mispelled".length)
          spellingPhase = 1
          spellingHeartbeatCount = 0
          spellingStartedAt = Date.now()
          spellWorker.sendMessage({type: "check", requestId: 2,
            sourceRevision: 8, edits: [{start: start,
              removed: "mispelled", inserted: "misspelled"}]})
          return
        }
        var metrics = message.metrics || {}
        if (spellingPhase === 1 &&
            (message.requestId !== 2 || message.sourceRevision !== 8 ||
            message.candidates.length !== initialCandidateCount ||
            message.misspellings.length !== initialMisspellingCount - 1 ||
            wrongMisspelling || invalidCandidate || metrics.fullScan ||
            metrics.parsedLineCount > 2 || metrics.reusedLineCount < 100 ||
            metrics.checkedCandidateCount > 20 || elapsed > 1000)) {
          console.error("VENDOR_FAIL: incremental spellcheck did not reuse " +
            "the unchanged document: " + JSON.stringify(message))
          Qt.quit()
          return
        }
        if (spellingPhase === 1) {
          console.log("VENDOR_SPELLCHECK_INCREMENTAL: " + JSON.stringify({
            parsedLines: metrics.parsedLineCount,
            reusedLines: metrics.reusedLineCount,
            checkedCandidates: metrics.checkedCandidateCount,
            elapsedMs: elapsed,
            uiHeartbeats: spellingHeartbeatCount
          }))
          spellingSource = "Before prose.\n```js\nfencedwurd\n```\n" +
            "After mispelled."
          spellingPhase = 2
          spellWorker.sendMessage({type: "check", requestId: 3,
            sourceRevision: 9, full: true, source: spellingSource})
          return
        }
        if (spellingPhase === 2) {
          if (message.requestId !== 3 || !metrics.fullScan ||
              message.candidates.some(function(candidate) {
                return candidate.word === "fencedwurd"
              })) {
            console.error("VENDOR_FAIL: fenced spellcheck setup was invalid")
            Qt.quit()
            return
          }
          var fenceStart = spellingSource.indexOf("```js")
          spellingSource = spellingSource.slice(0, fenceStart) + "js" +
            spellingSource.slice(fenceStart + 5)
          spellingPhase = 3
          spellWorker.sendMessage({type: "check", requestId: 4,
            sourceRevision: 10, edits: [{start: fenceStart,
              removed: "```js", inserted: "js"}]})
          return
        }
        if (message.requestId !== 4 || metrics.fullScan ||
            !message.candidates.some(function(candidate) {
              return candidate.word === "fencedwurd"
            }) || message.candidates.some(function(candidate) {
              return candidate.word === "After" || candidate.word === "mispelled"
            }) || metrics.parsedLineCount < 3) {
          console.error("VENDOR_FAIL: fence-state invalidation did not propagate: " +
            JSON.stringify(message))
          Qt.quit()
          return
        }
        spellHeartbeatTimer.stop()
        spellingPassed = true
        if (highlightPassCount === 2) {
          console.log("VENDOR_PASS: offline language bundles initialized")
          Qt.quit()
        }
      }
    }
  }

  Timer {
    id: spellHeartbeatTimer
    interval: 1
    repeat: true
    onTriggered: spellingHeartbeatCount++
  }

  Timer {
    interval: 15000
    running: true
    onTriggered: {
      console.error("VENDOR_FAIL: offline language bundle smoke test timed out")
      Qt.quit()
    }
  }
}
