import QtQuick
import Quickshell
import Quickshell.Io
import "./jotpin" as JotPin

// Both native windows can be instantiated by the offscreen backend, so this
// runs the production component unchanged in a private HOME and XDG_STATE_HOME.
ShellRoot {
  id: test

  property string mode: Quickshell.env("JOTPIN_PERSIST_MODE")
  property string notePath: Quickshell.env("JOTPIN_TEST_NOTE")
  property string openTargetPath: Quickshell.env("JOTPIN_TEST_OPEN_NOTE")
  property string missingRecentPath:
    Quickshell.env("JOTPIN_TEST_MISSING_RECENT")
  property string unreadableRecentPath:
    Quickshell.env("JOTPIN_TEST_UNREADABLE_RECENT")
  property string sessionPath: Quickshell.env("JOTPIN_TEST_SESSION_PATH")
  property string nonMarkdownPath: Quickshell.env("JOTPIN_TEST_NON_MD")
  property string renameTargetPath: Quickshell.env("JOTPIN_TEST_RENAME_TARGET")
  property string saveAsTargetPath: Quickshell.env("JOTPIN_TEST_SAVE_AS_TARGET")
  property string saveAsOverwritePath:
    Quickshell.env("JOTPIN_TEST_SAVE_AS_OVERWRITE")
  property string saveAsRacePath:
    Quickshell.env("JOTPIN_TEST_SAVE_AS_RACE_TARGET")
  property string renameRaceTargetPath:
    Quickshell.env("JOTPIN_TEST_RENAME_RACE_TARGET")
  property string blankUntitledPath: Quickshell.env("JOTPIN_TEST_BLANK_UNTITLED")
  property string defaultFirstPath: Quickshell.env("JOTPIN_TEST_DEFAULT_FIRST")
  property string defaultSecondPath: Quickshell.env("JOTPIN_TEST_DEFAULT_SECOND")
  property string settingsDirectory: Quickshell.env("JOTPIN_TEST_SETTINGS_DIR")
  property string tabStateSecondPath:
    Quickshell.env("JOTPIN_TEST_TAB_STATE_SECOND")
  property var queuedSettingsSavedValues: []
  property var queuedSettingsFile: null
  property string queuedDictionaryFirstWord: "jotpinalpha"
  property string queuedDictionarySecondWord: "jotpinbeta"
  property var queuedDictionarySavedValues: []
  property var queuedDictionaryFile: null
  property var queuedRecoverySavedValues: []
  property var queuedRecoveryFile: null
  property int queuedRecoveryFailures: 0
  property bool cleanupReleased: false
  property bool completed: false
  property int phase: 0
  property double phaseStartedAt: 0
  property string diskText: ""
  property string promptSource: ""
  property string noteBeforeDiscard: ""
  property int editCount: 0
  property bool inflightSaveAsEditInjected: false
  property int externalWriteCount: 0
  property string generatedClosePath: ""
  property string lastCloseNewPath: ""
  property bool observedDirtyDuringSave: false
  property int spellcheckRequestBeforeViewSwitch: -1
  property string spellcheckInitialView: ""
  property int spellcheckDispatchBeforeRapidEdits: -1
  property int spellcheckDispatchBeforeCodeEdit: -1
  property int spellcheckIncrementalDispatchBeforeCodeEdit: -1
  property int spellcheckFullDispatchBeforeCodeEdit: -1
  property int spellingPublishBeforeCodeEdit: -1
  property int spellingModelCountBeforeCodeEdit: -1
  property int spellingDelegateCreateBeforeCodeEdit: -1
  property int spellcheckDispatchBeforeCorrection: -1
  property int spellingPublishBeforeCorrection: -1
  property int spellingDelegateCreateBeforeCorrection: -1
  property string spellcheckOnColor: ""
  property real viewToggleCaretViewportY: -1
  property real secondLiveAlignedScroll: -1
  property bool startupNoteLoadWasGated: false

  function fail(message) {
    test.completed = true
    continuousEdit.stop()
    diskReload.stop()
    console.log("PERSIST_FAIL: " + message)
    Qt.exit(1)
  }

  function pass(message) {
    console.log("PERSIST_PASS: " + message)
  }

  function enterPhase(next) {
    test.phase = next
    test.phaseStartedAt = Date.now()
  }

  function elapsed() {
    return Date.now() - test.phaseStartedAt
  }

  function pad() {
    return padLoader.item
  }

  function saveState() {
    return JSON.parse(test.pad().persistenceState())
  }

  function diskTargetPath() {
    if (test.mode === "save-as-inflight") return test.saveAsTargetPath
    if (test.mode === "save-as-overwrite") return test.saveAsOverwritePath
    if (test.mode === "save-as-race") return test.saveAsRacePath
    if (test.mode === "rename-race") return test.renameRaceTargetPath
    return test.notePath
  }

  function editTo(source) {
    test.pad().setEditorText(source)
    test.pad().noteEdited()
  }

  function editorState() {
    return JSON.parse(test.pad().editorBehaviorState())
  }

  function tabStateSource(prefix) {
    var lines = []
    for (var index = 0; index < 100; index++)
      lines.push(prefix + " editor-state line " + index)
    return lines.join("\n")
  }

  function closeEnough(actual, expected) {
    return Math.abs(Number(actual) - Number(expected)) <= 2
  }

  function currentCaretViewportY() {
    var caret = JSON.parse(test.pad().caretState())
    var view = JSON.parse(test.pad().editorTabStateForTests(
      test.pad().notePath))
    var caretY = test.pad().rawMode
      ? Number(caret.nativeCursorY) : Number(caret.renderedCursorY)
    if (!isFinite(caretY) || caretY < 0) return NaN
    return caretY - Number(view.contentY)
  }

  function verifyUndoRoundTrip(label, before, after) {
    var state = test.editorState()
    if (state.text !== after || !state.canUndo) {
      test.fail(label + " did not create one undoable edit: " +
        JSON.stringify(state))
      return false
    }
    if (!test.pad().undoEditorForTests()) {
      test.fail(label + " could not undo")
      return false
    }
    state = test.editorState()
    if (state.text !== before || !state.canRedo) {
      test.fail(label + " did not undo in one step: " + JSON.stringify(state))
      return false
    }
    if (!test.pad().redoEditorForTests()) {
      test.fail(label + " could not redo")
      return false
    }
    state = test.editorState()
    if (state.text !== after || !state.canUndo || state.canRedo) {
      test.fail(label + " did not redo in one step: " + JSON.stringify(state))
      return false
    }
    test.pass(label + " preserves one-step undo and redo")
    return true
  }

  function startContinuousEdit(prefix) {
    test.editCount = 0
    test.editTo(prefix + "0")
    continuousEdit.prefix = prefix
    continuousEdit.start()
  }

  function finish() {
    if (test.completed) return
    test.completed = true
    continuousEdit.stop()
    diskReload.stop()
    console.log("PERSIST_RESULT: " + test.mode)
    Qt.exit(0)
  }

  QtObject {
    id: fakeShell
    property var barConfig: ({ position: "top" })
    property var bar: null
    function firstPartyServiceFor(pluginId) { return null }
    function hide(pluginId) {}
  }

  QtObject {
    id: portableHost
    property string pluginId: "test.portable-jotpin"
    property string barPosition: "left"
    property int liveBarSize: 37
    property bool screensaverActive: false
    property int hideCount: 0
    function hidePanel() { portableHost.hideCount++ }
  }

  Component {
    id: padComponent
    JotPin.JotPin {
      shell: fakeShell
      manifest: ({ id: "dev.jotpin" })
      hostIntegration: test.mode === "host-integration"
        ? portableHost : null
      saveDelayMs: 180
      recoveryIntervalMs: 300
    }
  }

  Loader {
    id: padLoader
    active: true
    sourceComponent: padComponent
    onLoaded: {
      if (test.mode === "load-stall") {
        var initialLoadState = JSON.parse(item.noteLoadStateForTests())
        test.startupNoteLoadWasGated =
          !initialLoadState.settingsLoaded &&
          initialLoadState.fileViewPath === ""
      }
      if (test.mode === "spellcheck-hydration") {
        // Reproduce two quick header clicks before a stored disabled setting
        // finishes loading. The last click (On) must win hydration.
        item.activateSpellcheckButtonForTests()
        item.activateSpellcheckButtonForTests()
      }
      var payload = ({})
      if (test.mode !== "settings-restore") payload.mode = "center"
      if (test.mode !== "session-restore" &&
          test.mode !== "recent-restore" &&
          test.mode !== "recent-clear-restore" &&
          test.mode !== "tab-state-restore") payload.path = test.notePath
      item.open(JSON.stringify(payload))
      test.enterPhase(1)
    }
  }

  Connections {
    target: padLoader.item

    function onSavingAsChanged() {
      var pad = test.pad()
      if (!pad || test.mode !== "save-as-inflight" || !pad.savingAs ||
          test.inflightSaveAsEditInjected) return
      test.inflightSaveAsEditInjected = true
      pad.setEditorText("save-as-newer")
      pad.noteEdited()
    }

    function onNoteSaveInFlightChanged() {
      var pad = test.pad()
      if (!pad || !pad.noteSaveInFlight) return
      var state = JSON.parse(pad.persistenceState())
      if (state.dirty) test.observedDirtyDuringSave = true
    }
  }

  Process {
    id: diskReadProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: test.diskText = String(text || "")
    }
  }

  Process {
    id: releaseRecoveryCleanup
    command: ["touch", "--", Quickshell.env("JOTPIN_TEST_RECOVERY_RELEASE")]
    onExited: function(exitCode) {
      if (exitCode !== 0) test.fail("could not release recovery cleanup barrier")
      else test.cleanupReleased = true
    }
  }

  FileView {
    id: externalWriter
    path: test.mode === "external-change" ? test.notePath : ""
    atomicWrites: true
    printErrors: false
    onSaved: test.externalWriteCount++
    onSaveFailed: test.fail("external test writer failed")
  }

  Timer {
    id: diskReload
    interval: 40
    repeat: true
    running: true
    onTriggered: {
      if (test.mode === "missing-load" || test.mode === "unreadable-load") return
      if (diskReadProcess.running) return
      diskReadProcess.command = ["cat", "--", test.diskTargetPath()]
      diskReadProcess.running = true
    }
  }

  Timer {
    id: continuousEdit
    property string prefix: ""
    interval: 55
    repeat: true
    onTriggered: {
      test.editCount++
      test.editTo(prefix + test.editCount)
    }
  }

  Timer {
    id: persistenceDriver
    interval: 15
    repeat: true
    running: !test.completed
    onTriggered: {
      if (test.completed || !test.pad()) return
      var pad = test.pad()
      var state = test.saveState()

      if (test.mode === "terminal-reentry") {
        if (test.phase === 1 && !pad.loadingFromFile) {
          test.enterPhase(999)
          test.pass("terminal persistence stage completed")
          test.finish()
          // Qt.exit is asynchronous. Reproduce another already queued tick
          // before process exit rather than hoping a slow runner delivers one.
          persistenceDriver.triggered()
        } else if (test.phase === 999) {
          test.fail("completed persistence stage executed again before exit")
        }
        return
      }

      if (test.mode === "close-save-completion" ||
          test.mode === "close-load-completion") {
        if (test.phase === 1 && !pad.loadingFromFile &&
            pad.noteLoadedPath === test.notePath) {
          // A retry must not hide a dropped completion. Allow ordinary runner
          // latency while keeping the watchdog outside this test's timeout.
          pad.noteLoadWatchdogIntervalMs = 60000
          test.promptSource = String(pad.markdownSource || "")
          pad.addOpenFile(test.openTargetPath, false)
          if (test.mode === "close-save-completion") {
            test.editTo("close completion saved content")
            pad.closeFile(test.notePath)
          } else {
            pad.switchToFile(test.openTargetPath)
            pad.closeFile(test.openTargetPath)
          }
          test.enterPhase(990)
        } else if (test.phase === 990) {
          var expectedPath = test.mode === "close-save-completion"
            ? test.openTargetPath : test.notePath
          if (pad.notePath === expectedPath && !pad.loadingFromFile) {
            if (pad.noteLoadRetryCount !== 0 || pad.pendingClosePath !== "" ||
                pad.noteSaveInFlight || pad.dirty || pad.openFiles.length !== 1 ||
                String(pad.markdownSource || "") !== test.promptSource)
              return test.fail("close completion left unfinished state")
            test.pass("replacement note loaded without retry after " + test.mode)
            test.finish()
          } else if (test.elapsed() > 5000) {
            test.fail("close replacement completion stalled: " +
              pad.noteLoadStateForTests())
          }
        }
        return
      }

      if (test.phase === 1) {
        if (test.mode === "host-integration") {
          if (pad.pluginId() !== "test.portable-jotpin" ||
              pad.barPosition !== "left" || pad.liveBarSize !== 37 ||
              pad.sideLeftMargin !== 37 || pad.sideTopMargin !== 0 ||
              pad.sideRightMargin !== 0 || pad.sideBottomMargin !== 0 ||
              pad.screensaverActive) {
            test.fail("the injected host contract was not applied: " +
              JSON.stringify({
                pluginId: pad.pluginId(),
                barPosition: pad.barPosition,
                liveBarSize: pad.liveBarSize,
                sideMargins: [pad.sideTopMargin, pad.sideRightMargin,
                  pad.sideBottomMargin, pad.sideLeftMargin],
                screensaverActive: pad.screensaverActive
              }))
            return
          }
          pad.dismiss()
          if (portableHost.hideCount !== 1) {
            test.fail("dismiss did not use the injected host contract")
            return
          }
          test.pass("injected host controls identity, bar inset, security state, and hide")
          test.finish()
          return
        }

        if (test.mode === "tab-state-restore") {
          if (pad.loadingFromFile || !pad.editorStatesLoaded ||
              pad.noteLoadedPath !== pad.notePath ||
              pad.notePath !== test.tabStateSecondPath) return
          test.enterPhase(210)
          return
        }
        if (test.mode === "session-restore") {
          if (pad.loadingFromFile || pad.noteLoadedPath !== pad.notePath) return
          if (pad.notePath !== test.sessionPath || pad.openFiles.length < 2) {
            test.fail("session restore did not recover the active untitled file: " +
              JSON.stringify({ notePath: pad.notePath, openFiles: pad.openFiles }))
            return
          }
          for (var invalidIndex = 0; invalidIndex < pad.openFiles.length;
               invalidIndex++) {
            if (pad.openFiles[invalidIndex].path === test.nonMarkdownPath) {
              test.fail("session restore kept a non-Markdown tab")
              return
            }
          }
          var restoredUntitled = false
          for (var restoredIndex = 0;
               restoredIndex < pad.openFiles.length; restoredIndex++) {
            if (pad.openFiles[restoredIndex].path === test.sessionPath) {
              restoredUntitled = true
              break
            }
          }
          if (!restoredUntitled) {
            test.fail("session restore did not recover the untitled tab")
            return
          }
          if (!pad.isGeneratedUntitledPath(test.sessionPath)) {
            test.fail("session restore lost generated-note provenance")
            return
          }
          test.pass("session restore recovered the active untitled file and tab")
          test.finish()
          return
        }

        if (test.mode === "spellcheck-hydration") {
          if (!pad.presentationSettingsLoaded || pad.loadingFromFile ||
              pad.noteLoadedPath !== test.notePath) return
          var hydratedButton = JSON.parse(
            pad.spellcheckButtonStateForTests())
          if (!pad.spellcheckEnabled || !hydratedButton.enabled ||
              hydratedButton.selected || hydratedButton.icon !== "󰓆" ||
              hydratedButton.foreground !== hydratedButton.defaultForeground ||
              hydratedButton.tooltip !== "Turn spellcheck off") {
            test.fail("the final pre-hydration spellcheck click was lost: " +
              JSON.stringify(hydratedButton))
            return
          }
          test.spellcheckOnColor = hydratedButton.foreground
          if (!pad.focusSpellcheckButtonForTests()) {
            test.fail("the spellcheck button could not receive keyboard focus")
            return
          }
          pad.activateSpellcheckButtonForTests()
          test.enterPhase(1495)
          return
        }

        var restoredRecentMode = test.mode === "recent-restore" ||
          test.mode === "recent-clear-restore"
        var expectedInitialPath = restoredRecentMode
          ? pad.notePath : test.notePath
        if (pad.loadingFromFile ||
            pad.noteLoadedPath !== expectedInitialPath) return
        // Exercise commands only after the same first reveal and focus that
        // make them available to a person. Error/recovery UI has its own gates.
        if (pad.noteLoadError === "" &&
            (!pad.startupContentRevealed ||
             (!pad.recoveryPromptOpen &&
              !pad.editorItemForTests().activeFocus))) return

        if (test.mode === "prepare") {
          test.editTo("idle-save")
          test.enterPhase(10)
        } else if (test.mode.indexOf("recovery-cleanup-") === 0) {
          if (!pad.recoveryDirectoryReady) {
            pad.ensureRecoveryDirectory()
            return
          }
          pad.saveDelayMs = 60000
          pad.recoveryIntervalMs = 60000
          test.editTo("cleanup-before")
          pad.writeRecoverySnapshot()
          test.enterPhase(136)
        } else if (test.mode === "recovery-queued" ||
                   test.mode === "recovery-failure") {
          if (!pad.recoveryDirectoryReady) {
            pad.ensureRecoveryDirectory()
            return
          }
          pad.saveDelayMs = 60000
          pad.recoveryIntervalMs = 60000
          for (var recoveryIndex = 0; recoveryIndex < pad.data.length;
               recoveryIndex++) {
            var recoveryCandidate = pad.data[recoveryIndex]
            if (recoveryCandidate.path === pad.recoveryPath &&
                typeof recoveryCandidate.setText === "function") {
              test.queuedRecoveryFile = recoveryCandidate
              break
            }
          }
          if (!test.queuedRecoveryFile) {
            test.fail("could not observe the production recovery FileView")
            return
          }
          test.queuedRecoveryFile.saved.connect(function() {
            test.queuedRecoverySavedValues.push(JSON.parse(
              String(test.queuedRecoveryFile.text())).source)
          })
          test.queuedRecoveryFile.saveFailed.connect(function() {
            test.queuedRecoveryFailures++
          })
          test.editTo("recovery-first")
          pad.writeRecoverySnapshot()
          test.editTo("recovery-final")
          pad.writeRecoverySnapshot()
          if (!pad.recoveryWriteInFlight || !pad.recoveryWritePending) {
            test.fail("recovery fixture did not queue a second snapshot")
            return
          }
          test.enterPhase(132)
        } else if (test.mode === "spellcheck-close") {
          if (!pad.spellcheckReady) return
          var responseWorker = null
          for (var responseIndex = 0; responseIndex < pad.data.length;
               responseIndex++) {
            var responseCandidate = pad.data[responseIndex]
            if (String(responseCandidate.source || "").indexOf(
                "spellcheck/SpellcheckWorker.mjs") >= 0) {
              responseWorker = responseCandidate
              break
            }
          }
          if (!responseWorker || typeof responseWorker.message !== "function") {
            test.fail("could not deliver a delayed spellcheck response")
            return
          }
          var checkedReply = {
            type: "checked", requestId: pad.spellcheckRequestId,
            sourceRevision: pad.spellcheckSourceRevision,
            candidates: [{start: 0, end: 4, word: "base", sourceWord: "base"}],
            misspellings: [{candidateIndex: 0, start: 0, end: 4,
              word: "base", checkWord: "base"}]
          }
          var suggestionsReply = {
            type: "suggestions", requestId: pad.spellcheckSuggestionRequestId,
            suggestions: ["basis"]
          }
          responseWorker.message(checkedReply)
          responseWorker.message(suggestionsReply)
          if (pad.misspellings.length !== 1 ||
              pad.spellingContextSuggestions.length !== 1) {
            test.fail("current spellcheck replies were not accepted")
            return
          }
          pad.close()
          responseWorker.message(checkedReply)
          responseWorker.message(suggestionsReply)
          if (pad.misspellings.length !== 0 ||
              pad.spellingUnderlineModel.length !== 0 ||
              pad.spellingContextSuggestions.length !== 0 ||
              pad.spellcheckHasCheckedCandidates) {
            test.fail("delayed spellcheck replies repopulated a closed editor")
            return
          }
          pad.opened = true
          responseWorker.message(checkedReply)
          responseWorker.message(suggestionsReply)
          if (pad.misspellings.length !== 0 ||
              pad.spellingContextSuggestions.length !== 0 ||
              pad.spellcheckHasCheckedCandidates) {
            test.fail("old spellcheck replies were accepted after reopening")
            return
          }
          test.pass("spellcheck replies from before close stay stale after reopen")
          test.finish()
        } else if (test.mode === "dictionary-queued") {
          if (!pad.personalDictionaryLoaded ||
              !pad.presentationSettingsDirectoryReady ||
              pad.personalDictionaryWriteInFlight ||
              pad.personalDictionaryWritePending) return
          for (var dictionaryIndex = 0; dictionaryIndex < pad.data.length;
               dictionaryIndex++) {
            var dictionaryCandidate = pad.data[dictionaryIndex]
            if (dictionaryCandidate.path === pad.personalDictionaryPath &&
                typeof dictionaryCandidate.setText === "function") {
              test.queuedDictionaryFile = dictionaryCandidate
              break
            }
          }
          if (!test.queuedDictionaryFile) {
            test.fail("could not observe the production dictionary FileView")
            return
          }
          test.queuedDictionaryFile.saved.connect(function() {
            test.queuedDictionarySavedValues.push(JSON.parse(
              String(test.queuedDictionaryFile.text())).words)
          })
          if (!pad.addPersonalDictionaryWord(test.queuedDictionaryFirstWord) ||
              !pad.addPersonalDictionaryWord(test.queuedDictionarySecondWord)) {
            test.fail("dictionary fixture could not queue two unique words")
            return
          }
          if (!pad.personalDictionaryWriteInFlight ||
              !pad.personalDictionaryWritePending) {
            test.fail("dictionary fixture did not queue a second write")
            return
          }
          test.enterPhase(134)
        } else if (test.mode === "alignment") {
          pad.setEditorText("")
          test.enterPhase(5)
        } else if (test.mode === "recover") {
          test.enterPhase(40)
        } else if (test.mode === "discard-prepare") {
          test.startContinuousEdit("discard-recovery-")
          test.enterPhase(30)
        } else if (test.mode === "discard") {
          test.enterPhase(60)
        } else if (test.mode === "open") {
          test.enterPhase(80)
        } else if (test.mode === "open-list") {
          pad.openFileChooser()
          test.enterPhase(110)
        } else if (test.mode === "untitled-close") {
          pad.openFileSelected(test.blankUntitledPath)
          test.enterPhase(120)
        } else if (test.mode === "generated-close") {
          pad.openNewFile()
          test.enterPhase(125)
        } else if (test.mode === "last-close") {
          pad.openFiles = [{
            path: test.notePath,
            name: pad.fileNameForPath(test.notePath)
          }]
          test.editTo("saved-before-last-close")
          pad.closeFile(test.notePath)
          if (pad.pendingClosePath !== test.notePath) {
            test.fail("last-tab close did not wait for its dirty save")
            return
          }
          test.enterPhase(127)
        } else if (test.mode === "policy") {
          test.enterPhase(100)
        } else if (test.mode === "settings-queued") {
          if (pad.presentationSettingsWriteInFlight ||
              pad.presentationSettingsWritePending) return
          for (var dataIndex = 0; dataIndex < pad.data.length; dataIndex++) {
            var candidate = pad.data[dataIndex]
            if (candidate.path === pad.presentationSettingsPath &&
                typeof candidate.setText === "function") {
              test.queuedSettingsFile = candidate
              break
            }
          }
          if (!test.queuedSettingsFile) {
            test.fail("could not observe the production settings FileView")
            return
          }
          test.queuedSettingsFile.saved.connect(function() {
            test.queuedSettingsSavedValues.push(JSON.parse(
              String(test.queuedSettingsFile.text())).editorTextScale)
          })
          pad.setEditorTextScale(125)
          pad.setEditorTextScale(150)
          if (!pad.presentationSettingsWriteInFlight ||
              !pad.presentationSettingsWritePending) {
            test.fail("settings fixture did not queue a second write")
            return
          }
          test.enterPhase(131)
        } else if (test.mode === "settings") {
          pad.openSettings()
          if (!pad.settingsOpen) {
            test.fail("settings icon action did not open the settings surface")
            return
          }
          pad.setPresentationMode("side")
          if (!pad.sideMode) {
            test.fail("settings surface could not select Side presentation")
            return
          }
          pad.setSidePlacement("left")
          if (!pad.sideLeftMode) {
            test.fail("settings surface could not select the left Side edge")
            return
          }
          if (!pad.applyShortcut("save", "Alt+S") ||
              pad.shortcutSave !== "Alt+S") {
            test.fail("settings surface could not change the Save shortcut")
            return
          }
          if (!pad.applyShortcut("maximize", "Alt+M") ||
              pad.shortcutMaximize !== "Alt+M" ||
              pad.shortcutIds().length !== 24) {
            test.fail("settings surface could not configure the complete shortcut model")
            return
          }
          if (!pad.applyShortcut("openRecent", "Alt+R") ||
              !pad.applyShortcut("clearRecent", "Alt+Shift+R") ||
              pad.shortcutOpenRecent !== "Alt+R" ||
              pad.shortcutClearRecent !== "Alt+Shift+R") {
            test.fail("settings surface could not configure Recent Files shortcuts")
            return
          }
          if (!pad.applyShortcut("find", "Alt+Shift+F") ||
              pad.shortcutFind !== "Alt+Shift+F") {
            test.fail("settings surface could not configure Find")
            return
          }
          if (pad.applyShortcut("open", "Alt+S")) {
            test.fail("settings surface allowed duplicate shortcuts")
            return
          }
          if (pad.applyShortcut("open", "Ctrl+Z") ||
              pad.applyShortcut("open", "Ctrl+C")) {
            test.fail("settings surface allowed a fixed editor shortcut collision")
            return
          }
          if (!pad.applyDefaultNotesDirectory(test.settingsDirectory)) {
            test.fail("settings surface rejected the test notes folder")
            return
          }
          pad.setFileTabRows(9)
          if (pad.fileTabRows !== pad.maximumFileTabRows) {
            test.fail("settings surface did not cap file-tab rows at five")
            return
          }
          pad.setFileTabRows(4)
          pad.setEditorTextScale(999)
          if (pad.editorTextScale !== 200) { test.fail("text size maximum"); return }
          pad.setEditorTextScale(1)
          if (pad.editorTextScale !== 75) { test.fail("text size minimum"); return }
          pad.setEditorTextScale(150)
          pad.setEditorTextScale(NaN)
          if (pad.editorTextScale !== 150) { test.fail("invalid text size"); return }
          test.enterPhase(130)
        } else if (test.mode === "settings-restore") {
          if (pad.sidePlacement !== "left" || !pad.sideLeftMode ||
              pad.shortcutSave !== "Alt+S" ||
              pad.shortcutMaximize !== "Alt+M" ||
              pad.shortcutFind !== "Alt+Shift+F" ||
              pad.shortcutOpenRecent !== "Alt+R" ||
              pad.shortcutClearRecent !== "Alt+Shift+R" ||
              pad.fileTabRows !== 4 || pad.editorTextScale !== 150) {
            test.fail("settings did not restore the Side edge and shortcut")
            return
          }
          test.pass("settings restored the Side edge, shortcut, and file-tab rows")
          test.finish()
        } else if (test.mode === "shortcut-migrate") {
          if (pad.shortcutMaximize !== "Ctrl+F") {
            test.fail("legacy F11 Expand/Restore shortcut did not migrate")
            return
          }
          test.enterPhase(135)
        } else if (test.mode === "session-prepare") {
          pad.openNewFile()
          test.enterPhase(90)
        } else if (test.mode === "tab-state-prepare") {
          var firstSource = test.tabStateSource("A")
          if (!pad.replaceEditorText(firstSource, firstSource.length)) {
            test.fail("first tab did not create an undoable editor-state edit")
            return
          }
          pad.noteEdited()
          test.enterPhase(200)
        } else if (test.mode === "tab-state-stale") {
          if (!pad.editorStatesLoaded) return
          var staleState = JSON.parse(pad.editorTabStateForTests(pad.notePath))
          if (String(pad.markdownSource || "") !== test.tabStateSource("A") ||
              staleState.canUndo || staleState.pastCount !== 0) {
            test.fail("stale persisted history was not rejected safely: " +
              JSON.stringify(staleState))
            return
          }
          test.pass("stale persisted history is discarded without changing note bytes")
          test.finish()
        } else if (test.mode === "recent-prepare") {
          var recentPrepareState = JSON.parse(pad.recentFilesState())
          if (recentPrepareState.validationRunning) return
          pad.clearRecentFiles()
          var oversizedRecent = []
          for (var recentIndex = 0; recentIndex < 12; recentIndex++) {
            oversizedRecent.push(pad.joinPath(
              pad.directoryForPath(test.notePath),
              "recent-" + recentIndex + ".md"))
          }
          oversizedRecent.push(oversizedRecent[0])
          if (pad.recentFilePathsFromValue(oversizedRecent).length !== 10) {
            test.fail("Recent Files did not cap and deduplicate stored history")
            return
          }
          pad.registerRecentFile(test.notePath)
          pad.registerRecentFile(test.openTargetPath)
          pad.registerRecentFile(test.missingRecentPath)
          pad.registerRecentFile(test.missingRecentPath)
          recentPrepareState = JSON.parse(pad.recentFilesState())
          if (recentPrepareState.files.length !== 3 ||
              recentPrepareState.files[0] !== test.missingRecentPath ||
              recentPrepareState.files[1] !== test.openTargetPath ||
              recentPrepareState.files[2] !== test.notePath) {
            test.fail("Recent Files ordering or deduplication was incorrect: " +
              JSON.stringify(recentPrepareState))
            return
          }
          pad.validateRecentFiles()
          test.enterPhase(190)
        } else if (test.mode === "recent-restore") {
          var recentRestoreState = JSON.parse(pad.recentFilesState())
          if (recentRestoreState.validationRunning) return
          if (recentRestoreState.files.length !== 2 ||
              recentRestoreState.files[0] !== test.openTargetPath ||
              recentRestoreState.files[1] !== test.notePath) {
            test.fail("Recent Files did not restore in MRU order: " +
              JSON.stringify(recentRestoreState))
            return
          }
          pad.toggleFileMenu()
          if (!pad.fileMenuOpenForTests() ||
              !pad.openRecentFile(test.notePath) ||
              pad.fileMenuOpenForTests()) {
            test.fail("File-menu recent action did not start opening and close")
            return
          }
          test.enterPhase(192)
        } else if (test.mode === "recent-clear-restore") {
          var recentClearRestoreState = JSON.parse(pad.recentFilesState())
          if (recentClearRestoreState.validationRunning) return
          if (recentClearRestoreState.files.length !== 0 ||
              pad.shortcutOpenRecent !== "Alt+R" ||
              pad.shortcutClearRecent !== "Alt+Shift+R") {
            test.fail("cleared Recent Files or its shortcuts did not persist: " +
              JSON.stringify(recentClearRestoreState))
            return
          }
          test.pass("cleared Recent Files remained empty after restart")
          test.finish()
        } else if (test.mode === "editor-undo") {
          test.enterPhase(140)
        } else if (test.mode === "load-stall") {
          if (!test.startupNoteLoadWasGated) {
            test.fail("the note FileView started before session settings hydrated")
            return
          }
          pad.loadingFromFile = true
          pad.noteLoadWatchdogPath = pad.notePath
          pad.noteLoadRetryCount = pad.noteLoadMaxRetries
          pad.handleNoteLoadWatchdog()
          var stalledState = JSON.parse(pad.noteLoadStateForTests())
          if (stalledState.loading || stalledState.error !== "stalled") {
            test.fail("terminal note-load watchdog did not unlock the editor: " +
              JSON.stringify(stalledState))
            return
          }
          pad.switchToFile(test.openTargetPath)
          test.enterPhase(139)
        } else if (test.mode === "task-toggle-scroll") {
          var taskLines = []
          for (var taskIndex = 0; taskIndex < 120; taskIndex++)
            taskLines.push("- [ ] Task row " + taskIndex)
          pad.setEditorText(taskLines.join("\n"))
          test.enterPhase(141)
        } else if (test.mode === "table-helper") {
          var tableSource =
            "## Blockquotes\n\n" +
            "```javascript\n" +
            "test\n" +
            "```\n\n" +
            "> Markdown is a lightweight markup language.\n\n" +
            "## Tables\n\n" +
            "| JotPin handles | Great for |\n" +
            "| --- | --- |\n" +
            "| Lists and tasks | Todos and planning |\n" +
            "| Tables and links | Research and reference |"
          pad.setEditorText(tableSource)
          var tableCursor = tableSource.indexOf("Todos and planning")
          pad.selectEditorRange(tableCursor, tableCursor)
          test.enterPhase(143)
        } else if (test.mode === "editor-commands") {
          pad.setEditorText("Alpha beta alpha\nline two\nfinal alpha")
          pad.selectEditorRange(0, 0)
          if (!pad.openEditorCommand("find")) {
            test.fail("Find command did not open")
            return
          }
          test.enterPhase(145)
        } else if (test.mode === "editor-indent") {
          test.enterPhase(146)
        } else if (test.mode === "editor-context") {
          pad.setEditorText("copy me")
          pad.selectEditorRange(0, 4)
          if (!pad.openEditorContextMenuForKeyboard()) {
            test.fail("keyboard context-menu command did not open")
            return
          }
          test.enterPhase(147)
        } else if (test.mode === "spellcheck") {
          pad.setEditorText(
            "mispelled **mispelled** *mispelled* ~~mispelled~~ " +
            "Omarchy JotPin Quickshell Hyprland Wayland CommonMark " +
            "GFM QML JSON YAML GDScript autosaves callouts " +
            "strikethrough Todos " +
            "`codewurd` https://example.test/badwurd\n\n" +
            "```javascript\nconst fencedwurd = mispelled\n```")
          test.enterPhase(149)
        } else if (test.mode === "file-menu-save") {
          test.editTo("file-menu-save")
          pad.toggleFileMenu()
          if (!pad.fileMenuOpenForTests()) {
            test.fail("File menu did not open before Save")
            return
          }
          pad.saveFromFileMenu()
          if (pad.fileMenuOpenForTests()) {
            test.fail("File-menu Save did not close the menu")
            return
          }
          test.enterPhase(148)
        } else if (test.mode === "save-as-inflight") {
          pad.setEditorText("save-as-snapshot")
          pad.noteEdited()
          pad.saveAsSelected(test.saveAsTargetPath)
          test.enterPhase(150)
        } else if (test.mode === "save-as-overwrite") {
          if (!pad.replaceEditorText("save-as-overwrite", 17)) {
            test.fail("Save As overwrite setup did not create edit history")
            return
          }
          pad.noteEdited()
          pad.saveAsSelected(test.saveAsOverwritePath)
          test.enterPhase(160)
        } else if (test.mode === "save-as-race") {
          test.editTo("save-as-must-not-clobber")
          pad.saveAsSelected(test.saveAsRacePath)
          test.enterPhase(165)
        } else if (test.mode === "rename-race") {
          pad.beginRenameFile(test.notePath)
          pad.commitRenameFile(pad.markdownStemForPath(
            test.renameRaceTargetPath))
          test.enterPhase(166)
        } else if (test.mode === "save-failure-switch") {
          test.editTo("unsaved-on-original-tab")
          pad.switchToFile(test.openTargetPath)
          if (pad.notePath !== test.notePath ||
              pad.pendingSwitchPath !== test.openTargetPath ||
              String(pad.markdownSource || "") !== "unsaved-on-original-tab") {
            test.fail("dirty tab switched before its save completed: " +
              JSON.stringify({ notePath: pad.notePath,
                pendingSwitchPath: pad.pendingSwitchPath,
                source: pad.markdownSource }))
            return
          }
          test.enterPhase(170)
        } else if (test.mode === "save-failure-close") {
          pad.addOpenFile(test.openTargetPath, false)
          test.editTo("unsaved-before-close")
          pad.closeFile(test.notePath)
          if (pad.pendingClosePath !== test.notePath ||
              pad.openFiles.length < 2) {
            test.fail("dirty close did not wait for its save")
            return
          }
          test.enterPhase(175)
        } else if (test.mode === "missing-load") {
          if (!pad.noteMissing || pad.noteLoadError !== "missing" ||
              String(pad.markdownSource || "") !== "" || state.dirty ||
              state.statusText.indexOf("File missing") !== 0) {
            test.fail("missing note was not kept as a blocked missing state: " +
              JSON.stringify({ noteMissing: pad.noteMissing,
                noteLoadError: pad.noteLoadError,
                source: pad.markdownSource, state: state }))
            return
          }
          test.pass("missing note requires an explicit create action")
          test.finish()
        } else if (test.mode === "unreadable-load") {
          if (pad.noteMissing || pad.noteLoadError !== "unreadable" ||
              String(pad.markdownSource || "") !== "" || state.dirty ||
              state.statusText !== "Could not read note") {
            test.fail("unreadable note was not kept distinct from missing: " +
              JSON.stringify({ noteMissing: pad.noteMissing,
                noteLoadError: pad.noteLoadError,
                source: pad.markdownSource, state: state }))
            return
          }
          test.pass("unreadable note is blocked without being treated as new")
          test.finish()
        } else if (test.mode === "external-change") {
          // Establish the external-change event before testing autosave's
          // conflict guard. Filesystem notification latency is not bounded by
          // this fixture's usual 180 ms save debounce on a shared CI runner.
          pad.saveDelayMs = 60000
          externalWriter.setText("external-clean")
          test.enterPhase(180)
        } else {
          test.fail("unknown mode " + test.mode)
        }
        return
      }

      if (test.phase === 139 && test.mode === "load-stall") {
        if (pad.loadingFromFile || pad.notePath !== test.openTargetPath ||
            pad.noteLoadedPath !== test.openTargetPath) return
        var recoveredLoadState = JSON.parse(pad.noteLoadStateForTests())
        if (recoveredLoadState.error !== "" ||
            String(pad.markdownSource || "").trim() !== "base") {
          test.fail("switching after a stalled load did not recover: " +
            JSON.stringify({load: recoveredLoadState,
              source: pad.markdownSource}))
          return
        }
        test.pass("startup load is gated and a dropped load cannot lock every tab")
        test.finish()
        return
      }

      if (test.phase === 140 && test.mode === "editor-undo") {
        pad.setEditorText("alpha")
        pad.selectEditorRange(5, 5)
        if (!pad.handlePlainReturn() ||
            !test.verifyUndoRoundTrip("plain Return", "alpha", "alpha\n")) {
          return
        }

        pad.setEditorText("```javascript\n\n```\n")
        pad.selectEditorRange(13, 13)
        if (!pad.handleFenceHeaderReturn()) {
          test.fail("one Return did not leave the projected language row")
          return
        }
        var fenceState = test.editorState()
        if (fenceState.text !== "```javascript\n\n```\n" ||
            fenceState.cursorPosition !== 14) {
          test.fail("fence-language Return inserted source or missed the " +
            "first code row: " + JSON.stringify(fenceState))
          return
        }
        test.pass("one Return moves from a fence language into its code row")

        pad.setEditorText("```js\n\n```\n")
        pad.autoFencePending = true
        pad.autoFenceCloseStart = 7
        pad.autoFenceCloseText = "```\n"
        pad.selectEditorRange(6, 6)
        if (!pad.handleBackspace()) {
          test.fail("Backspace did not cross from the empty code row")
          return
        }
        fenceState = test.editorState()
        if (fenceState.text !== "```js\n\n```\n" ||
            fenceState.cursorPosition !== 5 || !pad.autoFencePending) {
          test.fail("code-row Backspace damaged the structural newline: " +
            JSON.stringify(fenceState))
          return
        }
        var expectedHeldFenceDeletes = [
          {text: "```j\n\n```\n", cursor: 4, closeStart: 6},
          {text: "```\n\n```\n", cursor: 3, closeStart: 5},
          {text: "", cursor: 0, closeStart: -1}
        ]
        for (var heldFenceIndex = 0;
             heldFenceIndex < expectedHeldFenceDeletes.length;
             heldFenceIndex++) {
          if (!pad.handleBackspace()) {
            test.fail("held fence Backspace stopped at step " + heldFenceIndex)
            return
          }
          fenceState = test.editorState()
          var expectedHeldFence = expectedHeldFenceDeletes[heldFenceIndex]
          if (fenceState.text !== expectedHeldFence.text ||
              fenceState.cursorPosition !== expectedHeldFence.cursor ||
              pad.autoFenceCloseStart !== expectedHeldFence.closeStart) {
            test.fail("held fence deletion diverged at step " +
              heldFenceIndex + ": " + JSON.stringify({state: fenceState,
                closeStart: pad.autoFenceCloseStart}))
            return
          }
        }
        if (pad.autoFencePending || pad.autoFenceCloseText !== "") {
          test.fail("held fence deletion left generated-pair tracking active")
          return
        }
        test.pass("held Backspace removes a language and its complete generated fence")

        pad.setEditorText("```\n\n```\n")
        pad.autoFencePending = true
        pad.autoFenceCloseStart = 5
        pad.autoFenceCloseText = "```\n"
        pad.selectEditorRange(3, 3)
        var expectedFenceDeletes = [
          {text: "", cursor: 0, closeStart: -1}
        ]
        for (var fenceDeleteIndex = 0;
             fenceDeleteIndex < expectedFenceDeletes.length;
             fenceDeleteIndex++) {
          if (!pad.handleBackspace()) {
            test.fail("generated fence Backspace was not handled at step " +
              fenceDeleteIndex)
            return
          }
          fenceState = test.editorState()
          var expectedFenceDelete = expectedFenceDeletes[fenceDeleteIndex]
          if (fenceState.text !== expectedFenceDelete.text ||
              fenceState.cursorPosition !== expectedFenceDelete.cursor ||
              pad.autoFenceCloseStart !== expectedFenceDelete.closeStart) {
            test.fail("generated fence deletion diverged at step " +
              fenceDeleteIndex + ": " + JSON.stringify({state: fenceState,
                closeStart: pad.autoFenceCloseStart}))
            return
          }
        }
        if (pad.autoFencePending || pad.autoFenceCloseText !== "") {
          test.fail("generated fence tracking survived complete deletion")
          return
        }
        test.pass("one Backspace removes the complete generated fence opener")

        pad.setEditorText("```js\nfunction hello() {\n}\n```\n")
        pad.autoCodePairs = []
        pad.resetAutoFence()
        pad.selectEditorRange(24, 24)
        if (!pad.handleBackspace()) {
          test.fail("untracked empty brace Backspace was not handled")
          return
        }
        fenceState = test.editorState()
        if (fenceState.text !==
              "```js\nfunction hello() \n\n```\n" ||
            fenceState.cursorPosition !== 23) {
          test.fail("untracked empty brace left its closer behind: " +
            JSON.stringify(fenceState))
          return
        }
        test.pass("Backspace removes an empty code pair after tab tracking is lost")

        pad.setEditorText("\n\n```\n")
        pad.autoCodePairs = []
        pad.resetAutoFence()
        pad.selectEditorRange(0, 0)
        if (!pad.handleBackspace()) {
          test.fail("orphaned untracked fence Backspace was not handled")
          return
        }
        fenceState = test.editorState()
        if (fenceState.text !== "" || fenceState.cursorPosition !== 0) {
          test.fail("orphaned untracked fence closer survived Backspace: " +
            JSON.stringify(fenceState))
          return
        }
        test.pass("Backspace removes the orphaned bottom fence after tracking is lost")

        pad.setEditorText("```javascript\n\n```\n")
        pad.autoFencePending = true
        pad.autoFenceCloseStart = 15
        pad.autoFenceCloseText = "```\n"
        pad.selectEditorRange(0, 13)
        if (!pad.handleBackspace()) {
          test.fail("selected generated fence opener was not deleted")
          return
        }
        fenceState = test.editorState()
        if (fenceState.text !== "" || fenceState.cursorPosition !== 0 ||
            pad.autoFencePending) {
          test.fail("selected opener left its generated closer behind: " +
            JSON.stringify(fenceState))
          return
        }
        test.pass("deleting a selected generated opener removes its paired closer")

        pad.setEditorText("- item")
        pad.selectEditorRange(6, 6)
        if (!pad.handleListReturn() ||
            !test.verifyUndoRoundTrip(
              "list Return", "- item", "- item\n- ")) {
          return
        }

        pad.setEditorText("- item\n- ")
        pad.selectEditorRange(9, 9)
        if (!pad.handleBackspace() ||
            !test.verifyUndoRoundTrip(
              "list Backspace", "- item\n- ", "- item\n")) {
          return
        }

        pad.setEditorText("####Watching movies and shows")
        pad.selectEditorRange(4, 4)
        if (!pad.handleHeadingSpace() ||
            !test.verifyUndoRoundTrip(
              "heading separator Space", "####Watching movies and shows",
              "#### Watching movies and shows")) {
          return
        }

        pad.setEditorText("#### Watching movies and shows")
        pad.selectEditorRange(5, 5)
        if (!pad.handleBackspace() ||
            !test.verifyUndoRoundTrip(
              "Preview heading Backspace",
              "#### Watching movies and shows",
              "Watching movies and shows")) {
          return
        }

        pad.toggleRaw()
        pad.setEditorText("#### Watching movies and shows")
        pad.selectEditorRange(5, 5)
        if (pad.handleHeadingSpace() || !pad.handleBackspace() ||
            !test.verifyUndoRoundTrip(
              "Raw heading Backspace",
              "#### Watching movies and shows",
              "####Watching movies and shows")) {
          return
        }
        pad.toggleRaw()

        pad.setEditorText("- [ ] task")
        pad.selectEditorRange(10, 10)
        pad.toggleTask(0)
        if (!test.verifyUndoRoundTrip(
            "task toggle", "- [ ] task", "- [x] task")) {
          return
        }


        pad.setEditorText("![photo](photo.png)")
        pad.selectEditorRange(0, 0)
        if (!pad.resizeMarkdownImage(0, 19, 320) ||
            !test.verifyUndoRoundTrip(
              "image corner resize", "![photo](photo.png)",
              "![photo](photo.png)<!-- jotpin:image width=320 -->")) {
          return
        }

        test.finish()
        return
      }

      if (test.phase === 141 && test.mode === "task-toggle-scroll") {
        var taskState = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (taskState.maximumContentY < 600) return
        pad.selectEditorRange(0, 0)
        var anchoredScroll = pad.setEditorScrollForTests(300)
        if (!test.closeEnough(anchoredScroll, 300)) {
          test.fail("task-toggle setup could not establish its Live scroll: " +
            JSON.stringify(taskState))
          return
        }
        var taskSource = String(JSON.parse(pad.editorBehaviorState()).text || "")
        var taskPosition = taskSource.indexOf("- [ ] Task row 15")
        if (taskPosition < 0) {
          test.fail("task-toggle setup could not find its target task")
          return
        }
        pad.toggleTask(taskPosition)
        test.enterPhase(142)
        return
      }

      if (test.phase === 142 && test.mode === "task-toggle-scroll") {
        if (test.elapsed() < 250) return
        var toggledState = JSON.parse(
          pad.editorTabStateForTests(pad.notePath))
        if (!test.closeEnough(toggledState.contentY, 300) ||
            toggledState.cursorPosition !== 0 ||
            String(JSON.parse(pad.editorBehaviorState()).text || "").indexOf(
              "- [x] Task row 15") < 0) {
          test.fail("task toggle moved the Live viewport or caret: " +
            JSON.stringify(toggledState))
          return
        }
        test.pass("task toggles preserve the Live viewport and caret")
        test.finish()
        return
      }

      if (test.phase === 143 && test.mode === "table-helper") {
        var helper = JSON.parse(pad.tableHelperStateForTests())
        if (!helper.rendererReady || !helper.rendererMatches) {
          if (test.elapsed() > 3000) {
            test.fail("table helper renderer did not settle: " +
              JSON.stringify(helper))
          }
          return
        }
        if (helper.contentClearance < 1.5) {
          if (test.elapsed() > 3000) {
            test.fail("table helper did not clear the preceding content: " +
              JSON.stringify(helper))
          }
          return
        }
        if (!helper.visible || !helper.contentFits || !helper.slotBacked ||
            !helper.leftAligned ||
            helper.slotHeight < helper.height || helper.rowIndex !== 1 ||
            helper.columnIndex !== 1 || !helper.canDeleteRow ||
            !helper.canDeleteColumn || !helper.repairVisible ||
            helper.repairEnabled ||
            !helper.documentAnchored ||
            helper.tableTopY <= helper.documentY + helper.height ||
            !test.closeEnough(helper.gapBelow, 4) ||
            helper.height > 24) {
          test.fail("table helper did not follow the active body cell: " +
            JSON.stringify(helper))
          return
        }
        var beforeTableEdit = String(test.editorState().text || "")
        if (!pad.performTableAction("columnAfter")) {
          test.fail("table helper could not add a column")
          return
        }
        var afterTableEdit = String(test.editorState().text || "")
        if (afterTableEdit.indexOf(
            "| JotPin handles | Great for |  |") < 0 ||
            afterTableEdit.indexOf("| --- | --- | --- |") < 0 ||
            afterTableEdit.indexOf(
              "| Lists and tasks | Todos and planning |  |") < 0) {
          test.fail("table helper did not expand every row: " + afterTableEdit)
          return
        }
        if (!test.verifyUndoRoundTrip(
            "table helper structural edit", beforeTableEdit, afterTableEdit))
          return
        var outsideTable = beforeTableEdit.indexOf("## Tables\n") +
          String("## Tables\n").length
        pad.selectEditorRange(outsideTable, outsideTable)
        test.enterPhase(144)
        return
      }

      if (test.phase === 144 && test.mode === "table-helper") {
        if (test.elapsed() < 100) return
        var hiddenHelper = JSON.parse(pad.tableHelperStateForTests())
        if (hiddenHelper.visible) {
          test.fail("table helper remained visible on the blank line before " +
            "the table: " + JSON.stringify(hiddenHelper))
          return
        }
        var restoredSource = String(test.editorState().text || "")
        var insideTable = restoredSource.indexOf("Todos and planning")
        pad.selectEditorRange(insideTable, insideTable)
        test.enterPhase(1441)
        return
      }

      if (test.phase === 1441 && test.mode === "table-helper") {
        var restoredHelper = JSON.parse(pad.tableHelperStateForTests())
        if (!restoredHelper.visible) {
          if (test.elapsed() > 3000) {
            test.fail("table helper did not return with the caret in a cell: " +
              JSON.stringify(restoredHelper))
          }
          return
        }
        var paddingSource = String(test.editorState().text || "")
        var headerPadding = paddingSource.indexOf("JotPin handles") +
          String("JotPin handles").length + 1
        pad.selectEditorRange(headerPadding, headerPadding)
        test.enterPhase(1442)
        return
      }

      if (test.phase === 1442 && test.mode === "table-helper") {
        var paddingHelper = JSON.parse(pad.tableHelperStateForTests())
        if (!paddingHelper.visible || paddingHelper.rowIndex !== 0 ||
            paddingHelper.columnIndex !== 0) {
          if (test.elapsed() > 3000) {
            test.fail("table helper disappeared in trailing cell padding: " +
              JSON.stringify(paddingHelper))
          }
          return
        }
        pad.toggleRaw()
        paddingHelper = JSON.parse(pad.tableHelperStateForTests())
        if (!pad.rawMode || paddingHelper.visible) {
          test.fail("Raw mode retained the visual table helper: " +
            JSON.stringify(paddingHelper))
          return
        }
        pad.toggleRaw()
        var malformedTable =
          "## Tables\n\n" +
          "| JotPin handles | Great for |\n" +
          "| --- | --- |\n" +
          "| Lists and tasks | Todos and planning | stray | separators |"
        pad.setEditorText(malformedTable)
        var malformedCursor = malformedTable.indexOf("Todos and planning")
        pad.selectEditorRange(malformedCursor, malformedCursor)
        test.enterPhase(1443)
        return
      }

      if (test.phase === 1443 && test.mode === "table-helper") {
        var malformedHelper = JSON.parse(pad.tableHelperStateForTests())
        if (!malformedHelper.rendererReady ||
            !malformedHelper.rendererMatches || !malformedHelper.visible) {
          if (test.elapsed() > 3000) {
            test.fail("repairable table helper did not settle: " +
              JSON.stringify(malformedHelper))
          }
          return
        }
        if (!malformedHelper.repairVisible ||
            !malformedHelper.repairEnabled) {
          test.fail("repair button was not enabled for an overflow row: " +
            JSON.stringify(malformedHelper))
          return
        }
        var beforeRepair = String(test.editorState().text || "")
        if (!pad.performTableAction("tableRepair")) {
          test.fail("repair button could not normalize a malformed table")
          return
        }
        var afterRepair = String(test.editorState().text || "")
        if (afterRepair.indexOf(
            "| Lists and tasks | Todos and planning \\| stray \\| separators |") < 0 ||
            !test.verifyUndoRoundTrip(
              "table repair", beforeRepair, afterRepair)) return
        test.enterPhase(1444)
        return
      }

      if (test.phase === 1444 && test.mode === "table-helper") {
        var repairedHelper = JSON.parse(pad.tableHelperStateForTests())
        if (!repairedHelper.rendererReady ||
            !repairedHelper.rendererMatches) return
        if (!repairedHelper.repairVisible || repairedHelper.repairEnabled) {
          test.fail("repair button did not disable after normalization: " +
            JSON.stringify(repairedHelper))
          return
        }
        test.pass("contextual table helper follows only a caret inside its table")
        test.pass("table repair is visible, undoable, and enabled only when needed")
        test.finish()
        return
      }

      if (test.phase === 145 && test.mode === "editor-commands") {
        var command = JSON.parse(pad.editorCommandState())
        if (!command.open || command.mode !== "find" || command.dirty ||
            !command.commandInputActiveFocus) {
          test.fail("Find changed editor state while opening: " +
            JSON.stringify(command))
          return
        }

        if (!pad.updateFindQuery("Al")) {
          test.fail("incremental Find did not select while typing")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.query !== "Al" || command.selectionStart !== 0 ||
            command.selectionEnd !== 2 || command.anchorPosition !== 0 ||
            command.matchIndex !== 1 || command.matchCount !== 4 ||
            command.dirty || !command.commandInputActiveFocus) {
          test.fail("incremental Find moved from its original anchor: " +
            JSON.stringify(command))
          return
        }
        if (!pad.updateFindQuery("Alp")) {
          test.fail("incremental Find stopped highlighting a longer prefix")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.selectionStart !== 0 || command.selectionEnd !== 3 ||
            command.anchorPosition !== 0 || command.matchIndex !== 1 ||
            command.matchCount !== 3) {
          test.fail("incremental Find jumped while the query grew: " +
            JSON.stringify(command))
          return
        }
        test.pass("Find highlights from its original anchor as the query is typed")

        pad.selectEditorRange(0, 0)
        pad.findQuery = "alpha"
        pad.findCaseSensitive = false
        if (!pad.findInEditor(false)) {
          test.fail("Find did not select the first match")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.selectionStart !== 0 || command.selectionEnd !== 5 ||
            command.matchIndex !== 1 || command.matchCount !== 3 ||
            command.dirty || !command.commandInputActiveFocus) {
          test.fail("Find did not select without dirtying: " +
            JSON.stringify(command))
          return
        }
        pad.findInEditor(false)
        command = JSON.parse(pad.editorCommandState())
        if (command.selectionStart !== 11 || command.selectionEnd !== 16 ||
            command.matchIndex !== 2 || command.matchCount !== 3) {
          test.fail("Find Next selected the wrong match: " +
            JSON.stringify(command))
          return
        }
        pad.findInEditor(true)
        command = JSON.parse(pad.editorCommandState())
        if (command.selectionStart !== 0 || command.selectionEnd !== 5 ||
            command.matchIndex !== 1 || command.matchCount !== 3) {
          test.fail("Find Previous selected the wrong match: " +
            JSON.stringify(command))
          return
        }
        pad.findCaseSensitive = true
        pad.selectEditorRange(0, 0)
        pad.findInEditor(false)
        command = JSON.parse(pad.editorCommandState())
        if (command.selectionStart !== 11 || command.selectionEnd !== 16) {
          test.fail("case-sensitive Find selected the wrong match: " +
            JSON.stringify(command))
          return
        }
        pad.findQuery = "missing"
        if (pad.findInEditor(false)) {
          test.fail("Find reported a missing literal as a match")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.selectionStart !== 11 || command.selectionEnd !== 16 ||
            command.matchIndex !== 0 || command.matchCount !== 0 ||
            command.message !== "No matches" || command.dirty) {
          test.fail("a missing Find changed selection or dirty state: " +
            JSON.stringify(command))
          return
        }
        test.pass("Find reports current and total matches while navigating without dirtying")

        pad.openEditorCommand("replace")
        pad.findCaseSensitive = false
        pad.findQuery = "alpha"
        pad.replaceValue = "omega"
        pad.selectEditorRange(0, 5)
        if (!pad.replaceCurrentMatch()) {
          test.fail("Replace did not change the selected match")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.text !== "omega beta alpha\nline two\nfinal alpha" ||
            command.selectionStart !== 11 || command.selectionEnd !== 16 ||
            !command.dirty || !command.canUndo) {
          test.fail("Replace lost source, selection, or undo state: " +
            JSON.stringify(command))
          return
        }
        if (!pad.undoEditorForTests()) {
          test.fail("Replace could not be undone")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.text !== "Alpha beta alpha\nline two\nfinal alpha" ||
            !command.canRedo) {
          test.fail("Replace undo did not restore exact source: " +
            JSON.stringify(command))
          return
        }
        pad.redoEditorForTests()
        pad.findQuery = "alpha"
        pad.replaceValue = "X"
        if (!pad.replaceAllMatches()) {
          test.fail("Replace All did not change remaining matches")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.text !== "omega beta X\nline two\nfinal X" ||
            command.message !== "Replaced 2 matches") {
          test.fail("Replace All produced the wrong source or count: " +
            JSON.stringify(command))
          return
        }
        if (!pad.undoEditorForTests()) {
          test.fail("Replace All could not be undone")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.text !== "omega beta alpha\nline two\nfinal alpha") {
          test.fail("Replace All undo did not restore exact source: " +
            JSON.stringify(command))
          return
        }
        test.pass("Replace and Replace All preserve exact source and native undo")

        pad.openEditorCommand("line")
        pad.goToLineValue = "3"
        if (!pad.goToSourceLine()) {
          test.fail("Go to Line rejected a valid source row")
          return
        }
        command = JSON.parse(pad.editorCommandState())
        if (command.cursorPosition !== 26 ||
            command.message !== "Moved to line 3") {
          test.fail("Go to Line targeted the wrong source row: " +
            JSON.stringify(command))
          return
        }
        pad.goToLineValue = "99"
        pad.goToSourceLine()
        command = JSON.parse(pad.editorCommandState())
        if (command.cursorPosition !== 26 ||
            command.message !== "Moved to final line 3") {
          test.fail("Go to Line did not clamp to the final row: " +
            JSON.stringify(command))
          return
        }
        pad.goToLineValue = "0"
        if (pad.goToSourceLine()) {
          test.fail("Go to Line accepted a non-positive row")
          return
        }
        test.pass("Go to Line targets and clamps rows without changing text")
        test.finish()
        return
      }

      if (test.phase === 146 && test.mode === "editor-indent") {
        pad.setEditorText("plain")
        pad.selectEditorRange(2, 2)
        if (!pad.handleIndent(-1)) {
          test.fail("Shift Tab was not handled by the editor")
          return
        }
        var indentState = test.editorState()
        if (indentState.text !== "plain" || pad.dirty || indentState.canUndo) {
          test.fail("no-op outdent changed or dirtied an unindented row: " +
            JSON.stringify(indentState))
          return
        }

        if (!pad.handleIndent(1) ||
            !test.verifyUndoRoundTrip(
              "plain Tab", "plain", "pl  ain")) {
          return
        }

        pad.setEditorText("1. parent\n- [ ] child")
        pad.selectEditorRange(21, 21)
        if (!pad.handleIndent(1) ||
            !test.verifyUndoRoundTrip("list Tab",
              "1. parent\n- [ ] child", "1. parent\n  - [ ] child")) {
          return
        }
        if (!pad.handleIndent(-1) ||
            !test.verifyUndoRoundTrip("list Shift Tab",
              "1. parent\n  - [ ] child", "1. parent\n- [ ] child")) {
          return
        }

        pad.setEditorText("one\ntwo\nthree")
        pad.selectEditorRange(1, 8)
        if (!pad.handleIndent(1)) {
          test.fail("Tab did not indent a multiline selection")
          return
        }
        indentState = test.editorState()
        if (indentState.text !== "    one\n    two\nthree" ||
            indentState.selectionStart !== 5 ||
            indentState.selectionEnd !== 16 || !indentState.canUndo) {
          test.fail("multiline Tab changed source or selection geometry: " +
            JSON.stringify(indentState))
          return
        }
        if (!pad.undoEditorForTests()) {
          test.fail("multiline Tab could not be undone")
          return
        }
        indentState = test.editorState()
        if (indentState.text !== "one\ntwo\nthree") {
          test.fail("multiline Tab undo did not restore exact source: " +
            JSON.stringify(indentState))
          return
        }
        pad.toggleRaw()
        pad.setEditorText("raw")
        pad.selectEditorRange(1, 1)
        if (!pad.handleIndent(1)) {
          test.fail("Raw mode did not handle Tab")
          return
        }
        indentState = test.editorState()
        if (!pad.rawMode || indentState.text !== "r   aw") {
          test.fail("Raw mode did not apply the same Tab source transition: " +
            JSON.stringify(indentState))
          return
        }
        pad.toggleRaw()

        pad.setEditorText("```\ncode\n```\n")
        pad.autoFencePending = true
        pad.autoFenceCloseStart = 9
        pad.autoFenceCloseText = "```\n"
        pad.selectEditorRange(8, 8)
        if (!pad.handleIndent(1) || !pad.autoFencePending ||
            pad.autoFenceCloseStart !== 13) {
          test.fail("Tab discarded or misaligned generated-fence tracking: " +
            JSON.stringify({ state: test.editorState(),
              autoFencePending: pad.autoFencePending,
              autoFenceCloseStart: pad.autoFenceCloseStart }))
          return
        }
        test.pass("Tab and Shift Tab preserve source, selections, undo, and generated pairs")
        test.finish()
        return
      }

      if (test.phase === 147 && test.mode === "editor-context") {
        var context = JSON.parse(pad.editorContextState())
        if (!context.open || context.text !== "copy me" ||
            context.selectionStart !== 0 || context.selectionEnd !== 4 ||
            context.dirty) {
          test.fail("opening the context menu changed editor state: " +
            JSON.stringify(context))
          return
        }
        if (!pad.performEditorContextAction("copy")) {
          test.fail("context Copy rejected a source selection")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (context.open || context.text !== "copy me" || context.dirty) {
          test.fail("context Copy changed source or dirty state: " +
            JSON.stringify(context))
          return
        }

        pad.selectEditorRange(0, 4)
        pad.openEditorContextMenuAt(10, 10, 2)
        context = JSON.parse(pad.editorContextState())
        if (context.selectionStart !== 0 || context.selectionEnd !== 4) {
          test.fail("right-click inside a selection collapsed it: " +
            JSON.stringify(context))
          return
        }
        pad.closeEditorContextMenu()
        pad.openEditorContextMenuAt(10, 10, 6)
        context = JSON.parse(pad.editorContextState())
        if (context.cursorPosition !== 6 ||
            context.selectionStart !== context.selectionEnd) {
          test.fail("right-click outside a selection did not move the caret: " +
            JSON.stringify(context))
          return
        }
        pad.closeEditorContextMenu()

        pad.selectEditorRange(0, 4)
        if (!pad.performEditorContextAction("cut")) {
          test.fail("context Cut rejected a source selection")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (context.text !== " me" || !context.canUndo || !context.dirty) {
          test.fail("context Cut did not use the native undoable edit path: " +
            JSON.stringify(context))
          return
        }
        if (!pad.performEditorContextAction("undo")) {
          test.fail("context Undo rejected the Cut edit")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (context.text !== "copy me" || !context.canRedo) {
          test.fail("context Undo did not restore exact source: " +
            JSON.stringify(context))
          return
        }

        pad.selectEditorRange(7, 7)
        if (!pad.performEditorContextAction("paste")) {
          test.fail("context Paste could not use copied text")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (context.text !== "copy mecopy" || !context.canUndo) {
          test.fail("context Paste produced the wrong source: " +
            JSON.stringify(context))
          return
        }
        pad.performEditorContextAction("undo")
        if (!pad.performEditorContextAction("redo")) {
          test.fail("context Redo rejected the Paste edit")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (context.text !== "copy mecopy") {
          test.fail("context Redo did not restore the Paste edit: " +
            JSON.stringify(context))
          return
        }
        pad.performEditorContextAction("undo")

        if (!pad.performEditorContextAction("selectAll")) {
          test.fail("context Select All did not run")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (context.text !== "copy me" || context.selectionStart !== 0 ||
            context.selectionEnd !== 7) {
          test.fail("context Select All changed source or missed text: " +
            JSON.stringify(context))
          return
        }
        pad.selectEditorRange(7, 7)
        if (pad.performEditorContextAction("copy") ||
            pad.performEditorContextAction("cut")) {
          test.fail("context clipboard actions accepted an empty selection")
          return
        }

        pad.toggleRaw()
        if (!pad.openEditorContextMenuForKeyboard()) {
          test.fail("Raw mode could not open the context menu")
          return
        }
        context = JSON.parse(pad.editorContextState())
        if (!pad.rawMode || !context.open || context.text !== "copy me") {
          test.fail("Raw context menu changed source or failed to open: " +
            JSON.stringify(context))
          return
        }
        pad.closeEditorContextMenu()
        test.pass("Live and Raw context menus preserve selection, clipboard, and undo behavior")
        test.finish()
        return
      }

      if (test.phase === 149 && test.mode === "spellcheck") {
        if (!pad.spellcheckReady || pad.misspellings.length === 0 ||
            pad.spellingUnderlineModel.length === 0) return
        var unexpectedSpellingRange = pad.misspellings.length !== 4
        for (var spellingIndex = 0;
             spellingIndex < pad.misspellings.length; spellingIndex++) {
          if (pad.misspellings[spellingIndex].word !== "mispelled")
            unexpectedSpellingRange = true
        }
        if (unexpectedSpellingRange) {
          test.fail("spellcheck did not exclude inline code and URLs: " +
            JSON.stringify(pad.misspellings))
          return
        }
        var styledSegments = pad.spellingUnderlineSegments()
        if (styledSegments.length !== 4) {
          test.fail("spellcheck did not map its source range to an underline")
          return
        }
        var styledGeometryAligned = true
        var firstStep = Number(styledSegments[1].x) -
          Number(styledSegments[0].x)
        for (var styledIndex = 0;
             styledIndex < styledSegments.length; styledIndex++) {
          var segment = styledSegments[styledIndex]
          if (Number(segment.rangeStart) !==
                Number(pad.misspellings[styledIndex].start) ||
              !isFinite(Number(segment.x)) || Number(segment.width) <= 0 ||
              !isFinite(Number(segment.y)) ||
              Number(segment.sourceY) + Number(segment.sourceHeight) -
                Number(segment.y) < 1.5 ||
              Number(segment.sourceY) + Number(segment.sourceHeight) -
                Number(segment.y) > 3.5 ||
              Math.abs(Number(segment.width) -
                Number(styledSegments[0].width)) > 2 ||
              styledIndex > 1 && Math.abs(
                (Number(segment.x) -
                  Number(styledSegments[styledIndex - 1].x)) - firstStep) > 2) {
            styledGeometryAligned = false
            break
          }
        }
        if (!styledGeometryAligned) {
          test.fail("plain, bold, italic, and strikethrough underlines drifted: " +
            JSON.stringify(styledSegments))
          return
        }
        if (pad.dirty) {
          test.fail("spellcheck results dirtied the note")
          return
        }
        var codeEditBehavior = JSON.parse(pad.persistenceState())
        test.spellcheckDispatchBeforeCodeEdit =
          Number(codeEditBehavior.spellcheckDispatchCount)
        test.spellcheckIncrementalDispatchBeforeCodeEdit =
          Number(codeEditBehavior.spellcheckIncrementalDispatchCount)
        test.spellcheckFullDispatchBeforeCodeEdit =
          Number(codeEditBehavior.spellcheckFullDispatchCount)
        test.spellingPublishBeforeCodeEdit =
          Number(codeEditBehavior.spellingUnderlinePublishCount)
        test.spellingModelCountBeforeCodeEdit =
          pad.spellingUnderlineModel.length
        test.spellingDelegateCreateBeforeCodeEdit = Number(
          codeEditBehavior.spellingUnderlineDelegateCreateCount)
        var codeEditSource = String(test.editorState().text).replace(
          "const fencedwurd = mispelled",
          "const fencedwurd = mispelled + v")
        pad.setEditorText(codeEditSource)
        codeEditSource += "a"
        pad.setEditorText(codeEditSource)
        codeEditSource += "lue"
        pad.setEditorText(codeEditSource)
        var immediateCodeEditBehavior = JSON.parse(pad.persistenceState())
        if (pad.misspellings.length !== 4 ||
            pad.spellingUnderlineModel.length !== 4 ||
            !immediateCodeEditBehavior.spellcheckTimerRunning ||
            !pad.spellingGeometryDeferred ||
            Number(immediateCodeEditBehavior.spellcheckPendingEditCount) !== 3 ||
            Number(immediateCodeEditBehavior.spellingUnderlinePublishCount) !==
              test.spellingPublishBeforeCodeEdit ||
            Number(immediateCodeEditBehavior.spellingUnderlineDelegateCreateCount) !==
              test.spellingDelegateCreateBeforeCodeEdit ||
            Number(immediateCodeEditBehavior.spellcheckDispatchCount) !==
              test.spellcheckDispatchBeforeCodeEdit) {
          test.fail("per-character code edits republished cached prose marks: " +
            JSON.stringify(immediateCodeEditBehavior))
          return
        }
        test.enterPhase(14901)
        return
      }

      if (test.phase === 1495 && test.mode === "spellcheck-hydration") {
        var disabledButton = JSON.parse(
          pad.spellcheckButtonStateForTests())
        if (disabledButton.activeFocus) return
        if (pad.spellcheckEnabled || disabledButton.enabled ||
            disabledButton.selected || disabledButton.icon !== "󰓆" ||
            disabledButton.foreground === test.spellcheckOnColor ||
            disabledButton.tooltip !== "Turn spellcheck on") {
          test.fail("disabled spellcheck did not dim or release focus: " +
            JSON.stringify(disabledButton))
          return
        }
        test.pass("button activation releases focus and spellcheck dims when off")
        pad.activateSpellcheckButtonForTests()
        pad.setEditorText("mispelled")
        test.enterPhase(1496)
        return
      }

      if (test.phase === 1496 && test.mode === "spellcheck-hydration") {
        var hydrationBehavior = JSON.parse(pad.persistenceState())
        if (!pad.spellcheckReady || pad.misspellings.length !== 1 ||
            pad.misspellings[0].word !== "mispelled" ||
            hydrationBehavior.presentationSettingsWritePending ||
            hydrationBehavior.presentationSettingsWriteInFlight) return
        test.pass("pre-hydration spellcheck toggle stays on and checks the note")
        test.finish()
        return
      }

      if (test.phase === 14901 && test.mode === "spellcheck") {
        if (!pad.spellcheckReady || pad.misspellings.length === 0 ||
            pad.spellingUnderlineModel.length === 0) return
        var settledCodeEditBehavior = JSON.parse(pad.persistenceState())
        if (Number(settledCodeEditBehavior.spellcheckDispatchCount) !==
            test.spellcheckDispatchBeforeCodeEdit + 1) {
          if (Number(settledCodeEditBehavior.spellingUnderlinePublishCount) !==
              test.spellingPublishBeforeCodeEdit ||
              Number(settledCodeEditBehavior.spellingUnderlineDelegateCreateCount) !==
                test.spellingDelegateCreateBeforeCodeEdit ||
              !pad.spellingGeometryDeferred) {
            test.fail("typing republished every cached underline before debounce: " +
              JSON.stringify(settledCodeEditBehavior))
          }
          return
        }
        if (pad.misspellings.length !== 4 ||
            pad.spellingUnderlineModel.length !== 4 ||
            Number(settledCodeEditBehavior.spellingUnderlineVisualCount) !== 4 ||
            Number(settledCodeEditBehavior.spellingUnderlineDelegateCreateCount) !==
              test.spellingDelegateCreateBeforeCodeEdit ||
            pad.spellingGeometryDeferred ||
            settledCodeEditBehavior.spellcheckTimerRunning ||
            Number(settledCodeEditBehavior.spellcheckDispatchCount) !==
              test.spellcheckDispatchBeforeCodeEdit + 1 ||
            Number(settledCodeEditBehavior.spellcheckIncrementalDispatchCount) !==
              test.spellcheckIncrementalDispatchBeforeCodeEdit + 1 ||
            Number(settledCodeEditBehavior.spellcheckFullDispatchCount) !==
              test.spellcheckFullDispatchBeforeCodeEdit ||
            settledCodeEditBehavior.spellcheckLastMetrics.fullScan ||
            Number(settledCodeEditBehavior.spellcheckLastMetrics.parsedLineCount) > 3 ||
            Number(settledCodeEditBehavior.spellcheckLastMetrics.reusedLineCount) < 1) {
          test.fail("a settled code-only edit did not reuse the worker cache: " +
            JSON.stringify(settledCodeEditBehavior))
          return
        }
        test.spellcheckDispatchBeforeCorrection = Number(
          settledCodeEditBehavior.spellcheckDispatchCount)
        test.spellingPublishBeforeCorrection = Number(
          settledCodeEditBehavior.spellingUnderlinePublishCount)
        test.spellingDelegateCreateBeforeCorrection = Number(
          settledCodeEditBehavior.spellingUnderlineDelegateCreateCount)
        var correctionSource = String(test.editorState().text)
        pad.setEditorText("misspelled" +
          correctionSource.slice("mispelled".length))
        var immediateCorrectionBehavior = JSON.parse(pad.persistenceState())
        if (!pad.spellingGeometryDeferred ||
            Number(immediateCorrectionBehavior.spellingUnderlineVisualCount) !== 4 ||
            Number(immediateCorrectionBehavior.spellingUnderlineDelegateCreateCount) !==
              test.spellingDelegateCreateBeforeCorrection ||
            Number(immediateCorrectionBehavior.spellingUnderlinePublishCount) !==
              test.spellingPublishBeforeCorrection) {
          test.fail("correcting one word rebuilt unrelated spelling delegates: " +
            JSON.stringify(immediateCorrectionBehavior))
          return
        }
        test.enterPhase(14902)
        return
      }

      if (test.phase === 14902 && test.mode === "spellcheck") {
        var correctionBehavior = JSON.parse(pad.persistenceState())
        if (Number(correctionBehavior.spellcheckDispatchCount) !==
            test.spellcheckDispatchBeforeCorrection + 1) return
        if (Number(correctionBehavior.spellingUnderlineVisualCount) !== 3 ||
            Number(correctionBehavior.spellingUnderlinePublishCount) !==
              test.spellingPublishBeforeCorrection + 1) {
          if (Number(correctionBehavior.spellingUnderlineDelegateCreateCount) !==
              test.spellingDelegateCreateBeforeCorrection) {
            test.fail("a transient spelling rebuild recreated untouched delegates: " +
              JSON.stringify(correctionBehavior))
          }
          return
        }
        if (pad.misspellings.length !== 3 ||
            pad.spellingUnderlineModel.length !== 3 ||
            Number(correctionBehavior.spellingUnderlineVisualCount) !== 3 ||
            Number(correctionBehavior.spellingUnderlineDelegateCreateCount) !==
              test.spellingDelegateCreateBeforeCorrection ||
            Number(correctionBehavior.spellingUnderlinePublishCount) !==
              test.spellingPublishBeforeCorrection + 1 ||
            pad.spellingGeometryDeferred) {
          test.fail("one correction recreated untouched spelling delegates: " +
            JSON.stringify(correctionBehavior))
          return
        }
        var previewBehavior = correctionBehavior
        test.spellcheckRequestBeforeViewSwitch =
          Number(previewBehavior.spellcheckRequestId)
        test.spellcheckInitialView = pad.rawMode ? "raw" : "preview"
        if (previewBehavior.spellingUnderlineView !==
            test.spellcheckInitialView) {
          test.fail("spellcheck did not target the active editor view")
          return
        }
        pad.toggleRaw()
        test.enterPhase(14890)
        return
      }

      if (test.phase === 14890 && test.mode === "spellcheck") {
        var rawBehavior = JSON.parse(pad.persistenceState())
        var toggledView = test.spellcheckInitialView === "raw"
          ? "preview" : "raw"
        var toggledSegments = pad.spellingUnderlineSegments()
        var toggledSegment = toggledSegments.length > 0
          ? toggledSegments[0] : null
        var toggledUnderlineLift = toggledSegment
          ? Number(toggledSegment.sourceY) +
            Number(toggledSegment.sourceHeight) - Number(toggledSegment.y)
          : 0
        if (rawBehavior.spellingUnderlineView !== toggledView ||
            Number(rawBehavior.spellcheckRequestId) !==
              test.spellcheckRequestBeforeViewSwitch ||
            toggledSegments.length < 1 || toggledUnderlineLift < 1.5 ||
            toggledUnderlineLift > 3.5) {
          test.fail("Raw view duplicated or lost the shared spellcheck result: " +
            JSON.stringify(rawBehavior))
          return
        }
        pad.toggleRaw()
        test.enterPhase(14891)
        return
      }

      if (test.phase === 14891 && test.mode === "spellcheck") {
        var restoredPreviewBehavior = JSON.parse(pad.persistenceState())
        if (restoredPreviewBehavior.spellingUnderlineView !==
              test.spellcheckInitialView ||
            Number(restoredPreviewBehavior.spellcheckRequestId) !==
              test.spellcheckRequestBeforeViewSwitch ||
            pad.spellingUnderlineSegments().length < 1) {
          test.fail("Preview view reran or lost the shared spellcheck result: " +
            JSON.stringify(restoredPreviewBehavior))
          return
        }
        pad.switchToFile(test.openTargetPath)
        var switchBehavior = JSON.parse(pad.persistenceState())
        if (pad.notePath !== test.openTargetPath ||
            pad.misspellings.length !== 0 ||
            pad.spellingUnderlineModel.length !== 0 ||
            switchBehavior.spellcheckTimerRunning) {
          test.fail("file switch retained stale spelling state: " +
            JSON.stringify({ notePath: pad.notePath,
              misspellings: pad.misspellings,
              underlineCount: pad.spellingUnderlineModel.length,
              behavior: switchBehavior }))
          return
        }
        test.enterPhase(1490)
        return
      }

      if (test.phase === 1490 && test.mode === "spellcheck") {
        if (pad.loadingFromFile || pad.noteLoadedPath !== test.openTargetPath)
          return
        if (pad.misspellings.length !== 0 ||
            pad.spellingUnderlineModel.length !== 0) {
          test.fail("new file displayed spelling marks from the previous file")
          return
        }
        test.spellcheckDispatchBeforeRapidEdits = Number(
          JSON.parse(pad.persistenceState()).spellcheckDispatchCount)
        pad.setEditorText("server misp")
        pad.setEditorText("server mispell")
        pad.setEditorText(
          "server mispelled `codewurd` https://example.test/badwurd")
        var rapidEditBehavior = JSON.parse(pad.persistenceState())
        if (!rapidEditBehavior.spellcheckTimerRunning ||
            Number(rapidEditBehavior.spellcheckDelayMs) < 700 ||
            Number(rapidEditBehavior.spellcheckDispatchCount) !==
              test.spellcheckDispatchBeforeRapidEdits ||
            pad.misspellings.length !== 0 ||
            pad.spellingUnderlineModel.length !== 0) {
          test.fail("rapid edits were checked or painted before the idle delay: " +
            JSON.stringify(rapidEditBehavior))
          return
        }
        test.enterPhase(14905)
        return
      }

      if (test.phase === 14905 && test.mode === "spellcheck") {
        if (!pad.spellcheckReady || pad.misspellings.length === 0) return
        var settledSpellBehavior = JSON.parse(pad.persistenceState())
        if (Number(settledSpellBehavior.spellcheckDispatchCount) !==
            test.spellcheckDispatchBeforeRapidEdits + 1) {
          test.fail("rapid edits dispatched more than one spellcheck: " +
            JSON.stringify(settledSpellBehavior))
          return
        }
        if (pad.misspellings.length !== 1 ||
            pad.misspellings[0].word !== "mispelled") {
          test.fail("spellcheck did not refresh for the new file: " +
            JSON.stringify(pad.misspellings))
          return
        }
        if (!pad.openEditorContextMenuAt(
            10, 10, pad.misspellings[0].start + 1)) {
          test.fail("spellcheck context menu did not open")
          return
        }
        var spellingContext = JSON.parse(pad.editorContextState())
        if (!spellingContext.open ||
            spellingContext.spellingWord !== "mispelled") {
          test.fail("right-click did not expose spelling actions: " +
            JSON.stringify(spellingContext))
          return
        }
        test.enterPhase(1491)
        return
      }

      if (test.phase === 1491 && test.mode === "spellcheck") {
        if (pad.spellingSuggestionsPending) return
        if (!pad.spellingContextRange ||
            pad.spellingContextSuggestions.length === 0) {
          test.fail("spellcheck context action did not return suggestions")
          return
        }
        var suggestionContext = JSON.parse(pad.editorContextState())
        if (!suggestionContext.open ||
            suggestionContext.spellingSuggestionCount < 1) {
          test.fail("spellcheck suggestions were not exposed in the context menu: " +
            JSON.stringify(suggestionContext))
          return
        }
        if (!pad.addPersonalDictionaryWord("mispelled")) {
          test.fail("spellcheck could not add a personal dictionary word")
          return
        }
        test.enterPhase(1492)
        return
      }

      if (test.phase === 1492 && test.mode === "spellcheck") {
        if (pad.personalDictionaryWritePending ||
            pad.personalDictionaryWriteInFlight ||
            pad.misspellings.length > 0) return
        if (pad.dirty) {
          test.fail("personal dictionary activity dirtied the note")
          return
        }
        test.pass("bundled spellcheck underlines prose and persists personal words")
        test.finish()
        return
      }

      if (test.phase === 148 && test.mode === "file-menu-save") {
        if (test.diskText === "file-menu-save" &&
            state.statusText === "Saved" && !state.dirty &&
            !state.noteSaveInFlight) {
          test.pass("File-menu Save wrote exact source and completed cleanly")
          test.finish()
        }
        return
      }

      if (test.phase === 190 && test.mode === "recent-prepare") {
        var recentValidated = JSON.parse(pad.recentFilesState())
        if (recentValidated.validationRunning) return
        if (recentValidated.files.length !== 2 ||
            recentValidated.files[0] !== test.openTargetPath ||
            recentValidated.files[1] !== test.notePath ||
            recentValidated.files.indexOf(test.missingRecentPath) >= 0) {
          test.fail("Recent Files did not prune its missing entry: " +
            JSON.stringify(recentValidated))
          return
        }
        pad.registerRecentFile(test.missingRecentPath)
        pad.registerRecentFile(test.unreadableRecentPath)
        if (!pad.openMostRecentFile()) {
          test.fail("Open Most Recent did not start the file-open path")
          return
        }
        test.enterPhase(191)
        return
      }

      if (test.phase === 191 && test.mode === "recent-prepare") {
        var recentOpened = JSON.parse(pad.recentFilesState())
        if (pad.openingFile || pad.loadingFromFile ||
            pad.noteLoadedPath !== test.openTargetPath ||
            recentOpened.settingsWritePending ||
            recentOpened.settingsWriteInFlight) return
        if (pad.notePath !== test.openTargetPath ||
            recentOpened.files.length !== 2 ||
            recentOpened.files[0] !== test.openTargetPath ||
            recentOpened.files[1] !== test.notePath ||
            recentOpened.files.indexOf(test.missingRecentPath) >= 0 ||
            recentOpened.files.indexOf(test.unreadableRecentPath) >= 0 ||
            recentOpened.openingMostRecent) {
          test.fail("Open Most Recent did not preserve MRU order: " +
            JSON.stringify({notePath: pad.notePath, recent: recentOpened}))
          return
        }
        test.pass("Open Most Recent skipped missing and unreadable paths and opened the next usable note")
        test.finish()
        return
      }

      if (test.phase === 192 && test.mode === "recent-restore") {
        var recentReopened = JSON.parse(pad.recentFilesState())
        if (pad.openingFile || pad.loadingFromFile ||
            pad.noteLoadedPath !== test.notePath) return
        if (recentReopened.files.length !== 2 ||
            recentReopened.files[0] !== test.notePath ||
            recentReopened.files[1] !== test.openTargetPath) {
          test.fail("opening a persisted recent note did not promote it: " +
            JSON.stringify(recentReopened))
          return
        }
        pad.toggleFileMenu()
        if (!pad.fileMenuOpenForTests()) {
          test.fail("File menu did not open before Clear Recent Files")
          return
        }
        pad.clearRecentFiles()
        recentReopened = JSON.parse(pad.recentFilesState())
        if (recentReopened.files.length !== 0 ||
            recentReopened.fileMenuOpen) {
          test.fail("Clear Recent Files did not empty and close the menu: " +
            JSON.stringify(recentReopened))
          return
        }
        test.enterPhase(193)
        return
      }

      if (test.phase === 193 && test.mode === "recent-restore") {
        var recentCleared = JSON.parse(pad.recentFilesState())
        if (recentCleared.settingsWritePending ||
            recentCleared.settingsWriteInFlight) return
        test.pass("Recent Files restored, promoted an opened note, and cleared cleanly")
        test.finish()
        return
      }

      if (test.phase === 150 && test.mode === "save-as-inflight") {
        if (pad.savingAs || pad.loadingFromFile || pad.noteSaveInFlight ||
            test.diskText !== "save-as-newer") return
        state = test.saveState()
        if (pad.notePath !== test.saveAsTargetPath ||
            String(pad.markdownSource || "") !== "save-as-newer" ||
            state.dirty || state.statusText !== "Saved") {
          test.fail("Save As lost or misreported the newer edit: " +
            JSON.stringify({ notePath: pad.notePath,
              source: pad.markdownSource, state: state,
              diskText: test.diskText }))
          return
        }
        test.pass("Save As retained and persisted the in-flight editor change")
        test.finish()
        return
      }

      if (test.phase === 160 && test.mode === "save-as-overwrite") {
        if (pad.saveAsChecking || test.diskText === "") return
        if (pad.saveAsOverwritePath !== test.saveAsOverwritePath) {
          test.fail("Save As did not enter overwrite confirmation: " +
            JSON.stringify({ overwritePath: pad.saveAsOverwritePath,
              message: pad.fileChooserMessage }))
          return
        }
        if (pad.savingAs || pad.notePath !== test.notePath ||
            test.diskText !== "base\n") {
          test.fail("Save As changed the existing file before confirmation: " +
            JSON.stringify({ savingAs: pad.savingAs,
              notePath: pad.notePath, diskText: test.diskText }))
          return
        }
        test.pass("Save As left the existing destination unchanged before confirmation")
        if (!pad.confirmSaveAsOverwrite()) {
          test.fail("Save As overwrite confirmation was rejected")
          return
        }
        test.enterPhase(161)
        return
      }

      if (test.phase === 161 && test.mode === "save-as-overwrite") {
        if (pad.savingAs || pad.loadingFromFile || pad.noteSaveInFlight ||
            test.diskText !== "save-as-overwrite") return
        state = test.saveState()
        if (pad.notePath !== test.saveAsOverwritePath || state.dirty ||
            state.statusText !== "Saved" ||
            JSON.parse(pad.editorTabStateForTests(
              test.saveAsOverwritePath)).pastCount < 1 ||
            JSON.parse(pad.editorTabStateForTests(
              test.notePath)).pastCount < 1) {
          test.fail("confirmed Save As overwrite did not complete cleanly: " +
            JSON.stringify({ notePath: pad.notePath, state: state,
              diskText: test.diskText }))
          return
        }
        test.pass("explicit Save As confirmation replaced the destination")
        test.finish()
        return
      }

      if (test.phase === 165 && test.mode === "save-as-race") {
        if (pad.saveAsChecking || pad.savingAs ||
            pad.saveAsCleanupPath !== "" || pad.saveAsTempPath !== "") return
        state = test.saveState()
        if (pad.notePath !== test.notePath ||
            String(pad.markdownSource || "") !== "save-as-must-not-clobber" ||
            !state.dirty ||
            state.statusText !==
              "Could not save copy: destination already exists") {
          test.fail("Save As race did not preserve the original buffer: " +
            JSON.stringify({ notePath: pad.notePath,
              source: pad.markdownSource, state: state,
              saveAsTempPath: pad.saveAsTempPath }))
          return
        }
        test.pass("Save As rejected a destination created after its check")
        test.finish()
        return
      }

      if (test.phase === 166 && test.mode === "rename-race") {
        if (pad.renameInProgress || pad.renameTargetChecking ||
            pad.loadingFromFile) return
        if (pad.notePath !== test.notePath ||
            pad.renamingPath !== test.notePath ||
            String(pad.markdownSource || "") !== "base\n" ||
            state.dirty ||
            state.statusText !==
              "Rename stopped: destination already exists") {
          test.fail("rename race did not preserve its source context: " +
            JSON.stringify({ notePath: pad.notePath,
              renamingPath: pad.renamingPath,
              source: pad.markdownSource, state: state }))
          return
        }
        test.pass("rename rejected a destination created after its check")
        test.finish()
        return
      }

      if (test.phase === 170 && test.mode === "save-failure-switch") {
        if (pad.noteSaveInFlight || state.statusText !== "Could not save note") {
          return
        }
        if (pad.notePath !== test.notePath ||
            pad.pendingSwitchPath !== test.openTargetPath || !state.dirty ||
            String(pad.markdownSource || "") !== "unsaved-on-original-tab") {
          test.fail("failed save lost its original tab or source context: " +
            JSON.stringify({ notePath: pad.notePath,
              pendingSwitchPath: pad.pendingSwitchPath,
              source: pad.markdownSource, state: state }))
          return
        }
        test.pass("failed save retained its original path, source, and queued switch")
        test.finish()
        return
      }

      if (test.phase === 175 && test.mode === "save-failure-close") {
        if (pad.noteSaveInFlight || state.statusText !== "Could not save note")
          return
        var originalStillOpen = false
        for (var closeIndex = 0; closeIndex < pad.openFiles.length; closeIndex++) {
          if (pad.openFiles[closeIndex].path === test.notePath)
            originalStillOpen = true
        }
        if (!originalStillOpen || pad.notePath !== test.notePath ||
            pad.pendingClosePath !== "" || !state.dirty ||
            String(pad.markdownSource || "") !== "unsaved-before-close") {
          test.fail("failed close abandoned its unsaved tab: " +
            JSON.stringify({ openFiles: pad.openFiles,
              notePath: pad.notePath, pendingClosePath: pad.pendingClosePath,
              source: pad.markdownSource, state: state }))
          return
        }
        test.pass("failed close retained the tab and unsaved source")
        test.finish()
        return
      }

      if (test.phase === 180 && test.mode === "external-change") {
        if (test.externalWriteCount < 1 ||
            String(pad.markdownSource || "") !== "external-clean") return
        if (pad.externalConflict || state.dirty ||
            state.statusText !== "Reloaded external change") {
          test.fail("clean external edit did not reload safely: " +
            JSON.stringify({ source: pad.markdownSource,
              conflict: pad.externalConflict, state: state }))
          return
        }
        test.editTo("local-dirty")
        externalWriter.setText("external-disk")
        test.enterPhase(181)
        return
      }

      if (test.phase === 181 && test.mode === "external-change") {
        if (test.externalWriteCount < 2 || !pad.externalConflict ||
            test.diskText !== "external-disk") return
        if (String(pad.markdownSource || "") !== "local-dirty" ||
            !state.dirty || pad.noteSaveInFlight) {
          test.fail("dirty external conflict did not preserve local source: " +
            JSON.stringify({ source: pad.markdownSource, state: state }))
          return
        }
        pad.saveDelayMs = 180
        pad.noteEdited()
        test.enterPhase(1811)
        return
      }

      if (test.phase === 1811 && test.mode === "external-change") {
        // The status proves the real save timer called saveNow and hit its
        // conflict guard, rather than merely observing no write for a while.
        if (state.statusText !== "Resolve the external change before saving")
          return
        if (!pad.externalConflict || !state.dirty || pad.noteSaveInFlight ||
            test.diskText !== "external-disk") {
          test.fail("autosave changed bytes despite the external conflict")
          return
        }
        test.pass("dirty buffer blocked autosave after an external change")
        if (!pad.keepMineAfterExternalChange()) {
          test.fail("Keep Mine did not resolve the external conflict")
          return
        }
        test.enterPhase(182)
        return
      }

      if (test.phase === 182 && test.mode === "external-change") {
        if (pad.externalConflict || pad.noteSaveInFlight || state.dirty ||
            test.diskText !== "local-dirty" || state.statusText !== "Saved") {
          return
        }
        test.pass("Keep Mine explicitly replaced the external version")
        test.enterPhase(184)
        return
      }

      if (test.phase === 184 && test.mode === "external-change") {
        if (test.elapsed() < 250 || pad.externalReloadPending) return
        pad.saveDelayMs = 60000
        test.editTo("local-to-discard")
        externalWriter.setText("external-to-reload")
        test.enterPhase(183)
        return
      }

      if (test.phase === 183 && test.mode === "external-change") {
        if (test.externalWriteCount < 3 || !pad.externalConflict ||
            test.diskText !== "external-to-reload") return
        if (!pad.reloadAfterExternalChange()) {
          test.fail("Reload disk version did not resolve the conflict")
          return
        }
        state = test.saveState()
        if (String(pad.markdownSource || "") !== "external-to-reload" ||
            state.dirty || pad.externalConflict ||
            state.statusText !== "Reloaded external change") {
          test.fail("Reload disk version did not adopt external bytes: " +
            JSON.stringify({ source: pad.markdownSource, state: state }))
          return
        }
        test.pass("Reload disk version explicitly discarded local edits")
        test.finish()
        return
      }

      if (test.phase === 80 && test.mode === "open") {
        if (pad.fileChooserMode !== "open") {
          pad.openFileChooser()
          return
        }
        if (pad.rawMode) {
          test.fail("Open stage did not start in Preview mode")
          return
        }
        pad.toggleRaw()
        if (!pad.rawMode) {
          test.fail("Preview control did not switch to Raw mode")
          return
        }
        pad.toggleRaw()
        if (pad.rawMode) {
          test.fail("Preview control did not return from Raw mode")
          return
        }
        pad.toggleMaximized()
        if (!pad.activeWindowMaximized) {
          test.fail("expand control did not maximize the native window")
          return
        }
        pad.toggleMaximized()
        if (pad.activeWindowMaximized) {
          test.fail("expand control did not restore the native window")
          return
        }
        pad.openFileSelected(test.openTargetPath)
        test.enterPhase(81)
        return
      }

      if (test.phase === 81 && test.mode === "open") {
        if (pad.openingFile || pad.loadingFromFile ||
            pad.notePath !== test.openTargetPath ||
            pad.noteLoadedPath !== test.openTargetPath) return
        if (String(pad.markdownSource || "") !== "base\n") {
          test.fail("Open did not load the selected Markdown source")
          return
        }
        test.pass("Open loads an existing Markdown file and preserves its source")
        test.finish()
        return
      }

      if (test.phase === 110 && test.mode === "open-list") {
        if (pad.fileChooserMode !== "open" || pad.openNoteFilesLoading) {
          return
        }
        if (pad.saveAsDirectory !== pad.defaultNotesDirectory) {
          test.fail("Open did not start in the configured default notes folder")
          return
        }
        var foundFirst = false
        var foundSecond = false
        var foundNonMarkdown = false
        for (var noteIndex = 0; noteIndex < pad.openNoteFiles.length;
             noteIndex++) {
          var listed = pad.openNoteFiles[noteIndex]
          if (listed.path === test.defaultFirstPath) foundFirst = true
          if (listed.path === test.defaultSecondPath) foundSecond = true
          if (String(listed.path || "").indexOf("default-ignore.txt") >= 0) {
            foundNonMarkdown = true
          }
        }
        if (!foundFirst || !foundSecond || foundNonMarkdown) {
          test.fail("Open did not list the default folder Markdown files: " +
            JSON.stringify(pad.openNoteFiles))
          return
        }
        test.pass("Open lists Markdown notes from the configured default folder")
        pad.cancelSaveAs()
        test.finish()
        return
      }

      if (test.phase === 120 && test.mode === "untitled-close") {
        if (pad.loadingFromFile || pad.notePath !== test.blankUntitledPath) {
          return
        }
        pad.switchToFile(test.notePath)
        test.enterPhase(122)
        return
      }

      if (test.phase === 122 && test.mode === "untitled-close") {
        if (pad.loadingFromFile || pad.notePath !== test.notePath) return
        pad.closeFile(test.blankUntitledPath)
        test.enterPhase(121)
        return
      }

      if (test.phase === 121 && test.mode === "untitled-close") {
        if (pad.pendingClosePath !== "" || pad.untitledBlankCheckInFlight ||
            pad.untitledDeleteInFlight || pad.loadingFromFile) return
        var blankTabRemaining = false
        for (var blankIndex = 0; blankIndex < pad.openFiles.length;
             blankIndex++) {
          if (pad.openFiles[blankIndex].path === test.blankUntitledPath) {
            blankTabRemaining = true
            break
          }
        }
        if (blankTabRemaining || pad.notePath === test.blankUntitledPath) {
          test.fail("closing a blank untitled note did not remove its tab")
          return
        }
        test.pass("closing a user-created untitled-like note only removes its tab")
        test.finish()
        return
      }

      if (test.phase === 125 && test.mode === "generated-close") {
        if (pad.quickCreating || pad.loadingFromFile) return
        var generatedPath = pad.notePath
        if (generatedPath.indexOf("/untitled-") < 0 ||
            pad.generatedUntitledPaths.indexOf(generatedPath) < 0) {
          test.fail("New did not register generated-note provenance: " +
            JSON.stringify({ notePath: generatedPath,
              generated: pad.generatedUntitledPaths }))
          return
        }
        console.log("PERSIST_GENERATED_CLOSE_PATH: " + generatedPath)
        test.generatedClosePath = generatedPath
        pad.closeFile(generatedPath)
        test.enterPhase(126)
        return
      }

      if (test.phase === 126 && test.mode === "generated-close") {
        if (pad.pendingClosePath !== "" || pad.untitledDeleteInFlight ||
            pad.loadingFromFile) return
        if (pad.generatedUntitledPaths.indexOf(test.generatedClosePath) >= 0) {
          test.fail("closing generated note retained its provenance")
          return
        }
        test.pass("closing a blank generated note removes only that generated file")
        test.finish()
        return
      }

      if (test.phase === 127 && test.mode === "last-close") {
        if (pad.quickCreating || pad.loadingFromFile ||
            pad.pendingClosePath !== "" || pad.noteSaveInFlight ||
            pad.pendingSave || pad.dirty ||
            pad.presentationSettingsWriteInFlight ||
            pad.presentationSettingsWritePending) return
        var newPath = pad.notePath
        if (newPath === test.notePath || newPath.indexOf("/untitled-") < 0 ||
            pad.openFiles.length !== 1 ||
            pad.openFiles[0].path !== newPath ||
            pad.generatedUntitledPaths.indexOf(newPath) < 0 ||
            String(pad.markdownSource || "") !== "") {
          test.fail("closing the last tab did not replace it with one blank note: " +
            JSON.stringify({ notePath: newPath, openFiles: pad.openFiles,
              generated: pad.generatedUntitledPaths,
              source: pad.markdownSource }))
          return
        }
        console.log("PERSIST_LAST_CLOSE_NEW_PATH: " + newPath)
        test.pass("closing the last tab saves it and opens one blank note")
        test.finish()
        return
      }

      if (test.phase === 132 && (test.mode === "recovery-queued" ||
          test.mode === "recovery-failure")) {
        if (pad.recoveryWriteInFlight || pad.recoveryWritePending ||
            test.elapsed() < 100) return
        if (test.mode === "recovery-failure") {
          if (test.queuedRecoveryFailures !== 2 ||
              test.queuedRecoverySavedValues.length !== 0 ||
              pad.recoveryHasSnapshot || !pad.dirty ||
              pad.markdownSource !== "recovery-final") {
            test.fail("failed queued recovery lost its dirty source or reported success")
            return
          }
          test.pass("failed queued snapshots retain unsaved source without claiming recovery")
          test.finish()
          return
        }
        if (JSON.stringify(test.queuedRecoverySavedValues) !==
            '["recovery-first","recovery-final"]' ||
            pad.recoverySnapshotSource !== "recovery-final" || !pad.dirty) {
          test.fail("queued recovery completion values were " +
            JSON.stringify(test.queuedRecoverySavedValues))
          return
        }
        console.log("PERSIST_RECOVERY_PATH: " + pad.recoveryPath)
        test.pass("queued recovery snapshots complete with their own source")
        test.finish()
        return
      }

      if (test.mode.indexOf("recovery-cleanup-") === 0) {
        if (test.phase === 136) {
          if (pad.recoveryWriteInFlight || !pad.recoveryHasSnapshot) return
          pad.saveNow()
          test.enterPhase(137)
        } else if (test.phase === 137) {
          if (pad.noteSaveInFlight || pad.dirty ||
              pad.recoveryDeletePath !== pad.recoveryPath) return
          test.editTo("cleanup-after")
          pad.writeRecoverySnapshot()
          test.enterPhase(138)
        } else if (test.phase === 138) {
          if (pad.recoveryWriteInFlight) return
          if (test.mode === "recovery-cleanup-save") {
            if (pad.noteSaveInFlight) return
            if (pad.dirty) {
              pad.saveNow()
              return
            }
          }
          releaseRecoveryCleanup.running = true
          test.enterPhase(139)
        } else if (test.phase === 139) {
          if (!test.cleanupReleased || pad.recoveryDeletePath !== "" ||
              pad.recoveryWriteInFlight || pad.recoveryWritePending) return
          if (test.mode === "recovery-cleanup-save") {
            if (pad.dirty || pad.recoveryHasSnapshot) {
              test.fail("cleanup recreated a snapshot for an already saved edit")
              return
            }
            console.log("PERSIST_RECOVERY_PATH: " + pad.recoveryPath)
            test.pass("saving during cleanup does not recreate a recovery snapshot")
            test.finish()
            return
          }
          if (!pad.dirty || !pad.recoveryHasSnapshot ||
              pad.recoverySnapshotSource !== "cleanup-after") {
            test.fail("old recovery cleanup removed the newer snapshot")
            return
          }
          console.log("PERSIST_RECOVERY_PATH: " + pad.recoveryPath)
          test.pass("cleanup preserves the recovery snapshot for a newer edit")
          test.finish()
        }
        return
      }

      if (test.phase === 134 && test.mode === "dictionary-queued") {
        if (pad.personalDictionaryWriteInFlight ||
            pad.personalDictionaryWritePending) {
          if (test.elapsed() > 5000)
            test.fail("queued dictionary writes did not complete")
          return
        }
        if (test.queuedDictionarySavedValues.length !== 2) {
          test.fail("queued dictionary writes completed " +
            test.queuedDictionarySavedValues.length + " times")
          return
        }
        var firstDictionaryWords = test.queuedDictionarySavedValues[0]
        var secondDictionaryWords = test.queuedDictionarySavedValues[1]
        if (!Array.isArray(firstDictionaryWords) ||
            !Array.isArray(secondDictionaryWords) ||
            firstDictionaryWords.indexOf(test.queuedDictionaryFirstWord) < 0 ||
            firstDictionaryWords.indexOf(test.queuedDictionarySecondWord) >= 0 ||
            secondDictionaryWords.indexOf(test.queuedDictionaryFirstWord) < 0 ||
            secondDictionaryWords.indexOf(test.queuedDictionarySecondWord) < 0 ||
            secondDictionaryWords.length !== firstDictionaryWords.length + 1 ||
            pad.dirty) {
          test.fail("queued dictionary completion values were " +
            JSON.stringify(test.queuedDictionarySavedValues))
          return
        }
        test.pass("two queued personal dictionary writes each complete once")
        test.finish()
        return
      }

      if (test.phase === 131 && test.mode === "settings-queued") {
        if (pad.presentationSettingsWriteInFlight ||
            pad.presentationSettingsWritePending || test.elapsed() < 100) return
        if (JSON.stringify(test.queuedSettingsSavedValues) !== "[125,150]") {
          test.fail("queued settings completion values were " +
            JSON.stringify(test.queuedSettingsSavedValues))
          return
        }
        test.pass("two queued settings writes each complete once")
        test.finish()
        return
      }

      if (test.phase === 130 && test.mode === "settings") {
        if (pad.settingsDirectoryChangeInFlight ||
            pad.presentationSettingsWriteInFlight ||
            pad.presentationSettingsWritePending) return
        if (pad.defaultNotesDirectory !== test.settingsDirectory ||
            pad.settingsDefaultNotesDirectory !== test.settingsDirectory) {
          test.fail("settings surface did not apply the default notes folder: " +
            JSON.stringify({ defaultNotesDirectory: pad.defaultNotesDirectory,
              settingsDefaultNotesDirectory: pad.settingsDefaultNotesDirectory }))
          return
        }
        if (pad.sidePlacement !== "left" || !pad.sideLeftMode ||
            pad.shortcutSave !== "Alt+S" ||
            pad.shortcutMaximize !== "Alt+M" ||
            pad.shortcutOpenRecent !== "Alt+R" ||
            pad.shortcutClearRecent !== "Alt+Shift+R" ||
            pad.fileTabRows !== 4) {
          test.fail("settings surface did not apply the Side edge and shortcut")
          return
        }
        if (!pad.settingsOpen || !pad.sideMode) {
          test.fail("settings surface lost its applied presentation state")
          return
        }
        pad.closeSettings()
        test.pass("settings surface applies and persists JotPin preferences")
        test.finish()
        return
      }

      if (test.phase === 135 && test.mode === "shortcut-migrate") {
        if (pad.presentationSettingsWriteInFlight ||
            pad.presentationSettingsWritePending) return
        if (pad.shortcutMaximize !== "Ctrl+F") {
          test.fail("migrated Expand/Restore shortcut changed during persistence")
          return
        }
        test.pass("legacy F11 Expand/Restore shortcut migrates and persists")
        test.finish()
        return
      }

      if (test.phase === 100 && test.mode === "policy") {
        var initialPath = pad.notePath
        if (pad.normalizedFilePath(test.nonMarkdownPath) !== "" ||
            pad.normalizedMarkdownPath(test.nonMarkdownPath, true) !== "") {
          test.fail("non-Markdown paths passed the central path policy")
          return
        }

        pad.openFileSelected(test.nonMarkdownPath)
        if (pad.openingFile || pad.notePath !== initialPath ||
            pad.fileChooserMessage !== "Markdown files must end in .md") {
          test.fail("Open accepted a non-Markdown file")
          return
        }

        pad.applyPayload(JSON.stringify({ path: test.nonMarkdownPath }))
        if (pad.notePath !== initialPath || pad.pendingSessionPath !== "") {
          test.fail("a non-Markdown summon path changed the active note")
          return
        }

        pad.saveAsSelected(test.nonMarkdownPath)
        if (pad.savingAs || pad.saveAsOpen ||
            pad.fileChooserMessage !== "Markdown files must end in .md") {
          test.fail("Save As accepted a non-Markdown filename")
          return
        }

        pad.beginRenameFile(initialPath)
        if (pad.renameValue !== "policy-note") {
          test.fail("rename did not expose the filename stem")
          return
        }
        pad.commitRenameFile("blocked.txt")
        if (pad.renameInProgress || pad.renamingPath !== initialPath) {
          test.fail("rename accepted a non-Markdown extension")
          return
        }
        if (pad.markdownFileNameForInput("policy-renamed") !==
              "policy-renamed.md" ||
            pad.markdownFileNameForInput("policy-renamed.md") !==
              "policy-renamed.md") {
          test.fail("Markdown filename normalization did not keep .md")
          return
        }

        pad.cancelRenameFile()
        if (!pad.replaceEditorText("dirty-rename-source", 19)) {
          test.fail("rename setup did not create an undoable source edit")
          return
        }
        pad.noteEdited()
        pad.beginRenameFile(initialPath)
        pad.commitRenameFile("policy-renamed")
        if (!pad.pendingRenameCommit || pad.notePath !== initialPath) {
          test.fail("dirty rename did not wait for a confirmed save")
          return
        }
        test.enterPhase(101)
        return
      }

      if (test.phase === 101 && test.mode === "policy") {
        if (pad.renameInProgress || pad.loadingFromFile) return
        var renamedTab = false
        for (var renamedIndex = 0; renamedIndex < pad.openFiles.length;
             renamedIndex++) {
          if (pad.openFiles[renamedIndex].path === test.renameTargetPath) {
            renamedTab = true
            break
          }
        }
        if (pad.notePath !== test.renameTargetPath ||
            !renamedTab ||
            String(pad.markdownSource || "") !== "dirty-rename-source" ||
            pad.fileEditorStates[initialPath] !== undefined ||
            JSON.parse(pad.editorTabStateForTests(
              test.renameTargetPath)).pastCount < 1) {
          test.fail("valid stem rename did not produce the expected .md note: " +
            JSON.stringify({ notePath: pad.notePath,
              openFiles: pad.openFiles, source: pad.markdownSource,
              state: JSON.parse(pad.editorTabStateForTests(
                test.renameTargetPath)) }))
          return
        }
        test.pass("Open, Save As, summon, restore, and rename enforce Markdown-only paths")
        test.finish()
        return
      }

      if (test.phase === 90 && test.mode === "session-prepare") {
        if (pad.quickCreating || pad.loadingFromFile) return
        var emptyProjection = JSON.parse(
          pad.renderedDocumentStateForTests())
        if (!emptyProjection.layoutReady || !emptyProjection.layoutMatches) {
          if (test.elapsed() > 3000) {
            test.fail("new empty note projection did not settle: " +
              JSON.stringify(emptyProjection))
          }
          return
        }
        if (pad.notePath.indexOf("/Documents/Notes/untitled-") < 0 ||
            pad.openFiles.length < 2 || emptyProjection.editorText !== "" ||
            emptyProjection.documentSourceText !== "" ||
            emptyProjection.layoutSourceText !== "" ||
            emptyProjection.documentPlainText.trim() !== "") {
          test.fail("New did not create and open an untitled note: " +
            JSON.stringify({ notePath: pad.notePath, openFiles: pad.openFiles,
              projection: emptyProjection }))
          return
        }
        console.log("PERSIST_SESSION_PATH: " + pad.notePath)
        test.pass("New created a visually clear untitled file in the persisted session")
        pad.close()
        test.enterPhase(91)
        return
      }

      if (test.phase === 91 && test.mode === "session-prepare") {
        if (pad.pendingSave || pad.noteSaveInFlight ||
            pad.presentationSettingsWritePending ||
            pad.presentationSettingsWriteInFlight ||
            pad.editorStatesWritePending || pad.editorStatesWriteInFlight) return
        test.pass("closing JotPin completed note, settings, and editor-state writes")
        test.finish()
        return
      }

      if (test.phase === 200 && test.mode === "tab-state-prepare") {
        if (pad.loadingFromFile || pad.dirty || pad.noteSaveInFlight ||
            pad.editorStatesWriteInFlight) return
        pad.selectEditorRange(300, 310)
        var firstScroll = pad.setEditorScrollForTests(120)
        var firstState = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (!test.closeEnough(firstScroll, 120) ||
            firstState.maximumContentY < 260 || !firstState.canUndo) {
          test.fail("first tab could not establish selection scroll and undo: " +
            JSON.stringify(firstState))
          return
        }
        pad.switchToFile(test.tabStateSecondPath)
        test.enterPhase(201)
        return
      }

      if (test.phase === 201 && test.mode === "tab-state-prepare") {
        if (pad.loadingFromFile || pad.notePath !== test.tabStateSecondPath ||
            pad.noteLoadedPath !== test.tabStateSecondPath ||
            !pad.startupContentRevealed || !pad.editorCommandAllowed()) return
        var secondSource = test.tabStateSource("B")
        if (!pad.replaceEditorText(secondSource, secondSource.length)) {
          test.fail("second tab did not create an independent undoable edit")
          return
        }
        if (test.editorState().text !== secondSource || !pad.editorCanUndo) {
          test.fail("second tab replacement did not apply source and history: " +
            pad.editorBehaviorState())
          return
        }
        pad.noteEdited()
        test.enterPhase(202)
        return
      }

      if (test.phase === 202 && test.mode === "tab-state-prepare") {
        if (pad.dirty || pad.noteSaveInFlight || pad.loadingFromFile) return
        pad.selectEditorRange(500, 512)
        var secondScroll = pad.setEditorScrollForTests(180)
        if (!test.closeEnough(secondScroll, 180)) {
          test.fail("second tab could not establish its Live scroll position")
          return
        }
        test.viewToggleCaretViewportY = test.currentCaretViewportY()
        if (!isFinite(test.viewToggleCaretViewportY)) return
        pad.toggleRaw()
        test.enterPhase(203)
        return
      }

      if (test.phase === 203 && test.mode === "tab-state-prepare") {
        var rawAligned = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (!pad.rawMode || rawAligned.viewCaretAlignmentPending) return
        if (!test.closeEnough(test.currentCaretViewportY(),
            test.viewToggleCaretViewportY)) {
          test.fail("Preview to Raw did not preserve the caret viewport position: " +
            JSON.stringify(rawAligned))
          return
        }
        var rawScroll = pad.setEditorScrollForTests(260)
        if (!test.closeEnough(rawScroll, 260)) {
          test.fail("second tab could not establish its Raw scroll position")
          return
        }
        test.viewToggleCaretViewportY = test.currentCaretViewportY()
        pad.toggleRaw()
        test.enterPhase(204)
        return
      }

      if (test.phase === 204 && test.mode === "tab-state-prepare") {
        var liveAligned = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (pad.rawMode || liveAligned.viewCaretAlignmentPending) return
        var secondLive = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (!test.closeEnough(test.currentCaretViewportY(),
              test.viewToggleCaretViewportY) ||
            !test.closeEnough(secondLive.rawScrollY, 260)) {
          test.fail("Raw to Preview did not preserve the caret viewport position: " +
            JSON.stringify(secondLive))
          return
        }
        test.secondLiveAlignedScroll = Number(secondLive.contentY)
        pad.switchToFile(test.notePath)
        test.enterPhase(205)
        return
      }

      if (test.phase === 205 && test.mode === "tab-state-prepare") {
        if (pad.loadingFromFile || pad.notePath !== test.notePath ||
            pad.pendingEditorStateRestorePath !== "") return
        var firstProjection = JSON.parse(pad.renderedDocumentStateForTests())
        if (!firstProjection.layoutMatches) return
        if (!pad.editorCommandAllowed()) {
          if (test.elapsed() > 3000) {
            test.fail("Ctrl+Z remained disabled after switching notes")
          }
          return
        }
        var firstRestored = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (firstRestored.selectionStart !== 300 ||
            firstRestored.selectionEnd !== 310 ||
            !test.closeEnough(firstRestored.contentY, 120) ||
            !firstRestored.canUndo || !pad.undoEditor() ||
            String(pad.markdownSource || "") !== "base\n" ||
            !pad.redoEditorForTests() ||
            String(pad.markdownSource || "") !== test.tabStateSource("A") ||
            firstProjection.documentPlainText.indexOf(
              "A editor-state line 0") < 0 ||
            firstProjection.documentPlainText.indexOf(
              "B editor-state line 0") >= 0) {
          test.fail("first tab did not restore independent view and history: " +
            JSON.stringify(firstRestored))
          return
        }
        test.enterPhase(2052)
        return
      }

      if (test.phase === 2052 && test.mode === "tab-state-prepare") {
        pad.selectEditorRange(300, 310)
        pad.setEditorScrollForTests(120)
        pad.saveNow()
        test.enterPhase(2055)
        return
      }

      if (test.phase === 2055 && test.mode === "tab-state-prepare") {
        if (pad.dirty || pad.pendingSave || pad.noteSaveInFlight) return
        pad.switchToFile(test.tabStateSecondPath)
        test.enterPhase(206)
        return
      }

      if (test.phase === 206 && test.mode === "tab-state-prepare") {
        if (pad.loadingFromFile || pad.notePath !== test.tabStateSecondPath ||
            pad.pendingEditorStateRestorePath !== "") return
        var secondProjection = JSON.parse(pad.renderedDocumentStateForTests())
        if (!secondProjection.layoutMatches) return
        var secondRestored = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (secondRestored.selectionStart !== 500 ||
            secondRestored.selectionEnd !== 512 ||
            !test.closeEnough(secondRestored.contentY,
              test.secondLiveAlignedScroll) ||
            !test.closeEnough(secondRestored.rawScrollY, 260) ||
            !secondRestored.canUndo ||
            secondProjection.documentPlainText.indexOf(
              "B editor-state line 0") < 0 ||
            secondProjection.documentPlainText.indexOf(
              "A editor-state line 0") >= 0) {
          test.fail("second tab did not retain its independent state: " +
            JSON.stringify(secondRestored))
          return
        }
        pad.switchToFile(test.notePath)
        pad.switchToFile(test.tabStateSecondPath)
        test.enterPhase(2065)
        return
      }

      if (test.phase === 2065 && test.mode === "tab-state-prepare") {
        if (pad.loadingFromFile || pad.pendingSwitchPath !== "" ||
            pad.notePath !== test.tabStateSecondPath ||
            pad.pendingEditorStateRestorePath !== "") return
        var finalProjection = JSON.parse(pad.renderedDocumentStateForTests())
        if (!finalProjection.layoutMatches) return
        var finalFirstState = JSON.parse(
          pad.editorTabStateForTests(test.notePath))
        var finalSecondState = JSON.parse(
          pad.editorTabStateForTests(test.tabStateSecondPath))
        if (finalProjection.documentPlainText.indexOf(
              "B editor-state line 0") < 0 ||
            finalProjection.documentPlainText.indexOf(
              "A editor-state line 0") >= 0 ||
            finalFirstState.selectionStart !== 300 ||
            finalFirstState.selectionEnd !== 310 ||
            !test.closeEnough(finalFirstState.liveScrollY, 120) ||
            finalFirstState.pastCount < 1 ||
            finalSecondState.pastCount < 1 || !finalSecondState.canUndo) {
          test.fail("rapid note toggling mixed projections or histories: " +
            JSON.stringify({projection: finalProjection,
              first: finalFirstState, second: finalSecondState}))
          return
        }
        test.pass("Raw and Preview toggles keep the caret at the same viewport position")
        test.pass("rapid tab switches keep projections and per-note undo histories isolated")
        pad.close()
        test.enterPhase(207)
        return
      }

      if (test.phase === 207 && test.mode === "tab-state-prepare") {
        if (pad.noteSaveInFlight || pad.editorStatesWriteInFlight ||
            pad.editorStatesWritePending || test.elapsed() < 400) return
        test.pass("per-tab editor state finished its atomic persistence write")
        test.finish()
        return
      }

      if (test.phase === 210 && test.mode === "tab-state-restore") {
        if (pad.pendingEditorStateRestorePath !== "") return
        var restoredSecond = JSON.parse(
          pad.editorTabStateForTests(test.tabStateSecondPath))
        if (restoredSecond.selectionStart !== 500 ||
            restoredSecond.selectionEnd !== 512 ||
            !test.closeEnough(restoredSecond.contentY,
              restoredSecond.liveScrollY) ||
            !test.closeEnough(restoredSecond.rawScrollY, 260) ||
            !restoredSecond.canUndo || !pad.undoEditorForTests() ||
            String(pad.markdownSource || "") !== "base\n" ||
            !pad.redoEditorForTests() ||
            String(pad.markdownSource || "") !== test.tabStateSource("B")) {
          test.fail("restart did not restore the second tab state and history: " +
            JSON.stringify(restoredSecond))
          return
        }
        test.enterPhase(2102)
        return
      }

      if (test.phase === 2102 && test.mode === "tab-state-restore") {
        pad.selectEditorRange(500, 512)
        pad.setEditorScrollForTests(180)
        test.viewToggleCaretViewportY = test.currentCaretViewportY()
        if (!isFinite(test.viewToggleCaretViewportY)) return
        pad.toggleRaw()
        test.enterPhase(211)
        return
      }

      if (test.phase === 211 && test.mode === "tab-state-restore") {
        if (!pad.rawMode || JSON.parse(pad.editorTabStateForTests(
            pad.notePath)).viewCaretAlignmentPending) return
        var rawRestored = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        var restoredRawCaretY = test.currentCaretViewportY()
        if (!test.closeEnough(restoredRawCaretY,
            test.viewToggleCaretViewportY)) {
          test.fail("restored Preview to Raw toggle moved the caret onscreen: " +
            JSON.stringify({state: rawRestored,
              expectedCaretY: test.viewToggleCaretViewportY,
              actualCaretY: restoredRawCaretY}))
          return
        }
        test.viewToggleCaretViewportY = test.currentCaretViewportY()
        pad.toggleRaw()
        test.enterPhase(212)
        return
      }

      if (test.phase === 212 && test.mode === "tab-state-restore") {
        if (pad.rawMode || JSON.parse(pad.editorTabStateForTests(
            pad.notePath)).viewCaretAlignmentPending) return
        var liveRestored = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (!test.closeEnough(test.currentCaretViewportY(),
            test.viewToggleCaretViewportY)) {
          test.fail("restored Raw to Preview toggle moved the caret onscreen: " +
            JSON.stringify(liveRestored))
          return
        }
        pad.switchToFile(test.notePath)
        test.enterPhase(213)
        return
      }

      if (test.phase === 213 && test.mode === "tab-state-restore") {
        if (pad.loadingFromFile || pad.notePath !== test.notePath ||
            pad.pendingEditorStateRestorePath !== "") return
        var restoredFirst = JSON.parse(pad.editorTabStateForTests(pad.notePath))
        if (restoredFirst.selectionStart !== 300 ||
            restoredFirst.selectionEnd !== 310 ||
            !test.closeEnough(restoredFirst.contentY, 120) ||
            !restoredFirst.canUndo || !pad.undoEditorForTests() ||
            String(pad.markdownSource || "") !== "base\n" ||
            !pad.redoEditorForTests() ||
            String(pad.markdownSource || "") !== test.tabStateSource("A")) {
          test.fail("restart did not restore the first tab independently: " +
            JSON.stringify(restoredFirst))
          return
        }
        test.pass("restart restores every tab's caret selection scroll and undo")
        test.finish()
        return
      }

      if (test.phase === 5) {
        var caret = JSON.parse(pad.caretState())
        if (caret.sourceLength !== 0 || !caret.placeholderVisible) {
          test.fail("empty editor helper was not visible: " + JSON.stringify(caret))
          return
        }
        if (Math.abs(caret.placeholderX - caret.nativeCursorX) > 0.01 ||
            Math.abs(caret.placeholderY - caret.nativeCursorY) > 0.01) {
          test.fail("empty editor helper did not share the caret origin: " +
            JSON.stringify(caret))
          return
        }
        if (!caret.liveCursorVisible || !caret.layoutReady) return
        test.pass("empty editor helper shares the editable caret origin")
        if (!pad.replaceEditorText("a", 1)) {
          test.fail("typing-caret continuity fixture could not insert text")
          return
        }
        pad.noteEdited()
        var typingCaret = JSON.parse(pad.caretState())
        if (!typingCaret.liveCursorVisible) {
          test.fail("ordinary typing flashed the Live caret off: " +
            JSON.stringify(typingCaret))
          return
        }
        pad.setEditorText("")
        pad.noteEdited()
        test.pass("ordinary typing keeps the Live caret continuously visible")
        pad.toggleShortcutHelp()
        test.enterPhase(6)
        return
      }

      if (test.phase === 6) {
        if (!pad.shortcutHelpOpen || pad.shortcutHelpEntries.length !== 28 ||
            pad.shortcutIds().length !== 24) {
          test.fail("shortcut help did not open with every JotPin shortcut")
          return
        }
        var shortcutLayout = JSON.parse(pad.shortcutHelpLayoutState())
        if (!shortcutLayout.separated ||
            shortcutLayout.rows !== pad.shortcutHelpEntries.length ||
            shortcutLayout.maximumOverflow > 0.5) {
          test.fail("shortcut help labels overlap: " +
            JSON.stringify(shortcutLayout))
          return
        }
        test.pass("shortcut help keeps key and action labels separated")
        var shortcutValues = ({})
        var shortcutIds = pad.shortcutIds()
        for (var shortcutIndex = 0; shortcutIndex < shortcutIds.length;
             shortcutIndex++) {
          var shortcutValue = pad.shortcutValue(shortcutIds[shortcutIndex])
          if (shortcutValue === "" || shortcutValues[shortcutValue]) {
            test.fail("shortcut model contains an empty or duplicate command: " +
              JSON.stringify({id: shortcutIds[shortcutIndex],
                value: shortcutValue}))
            return
          }
          shortcutValues[shortcutValue] = true
        }
        pad.hydrateShortcuts({save: "Ctrl+F", open: "Ctrl+Z"})
        if (pad.shortcutSave !== "Ctrl+S" ||
            pad.shortcutOpen !== "Ctrl+O" ||
            pad.shortcutMaximize !== "Ctrl+F") {
          test.fail("stored shortcuts displaced a new default or fixed editor key")
          return
        }
        pad.hydrateShortcuts({save: "Alt+S", open: "Alt+S"})
        if (pad.shortcutSave !== "Alt+S" || pad.shortcutOpen !== "Ctrl+O") {
          test.fail("stored duplicate shortcuts were not resolved deterministically")
          return
        }
        if (pad.shortcutNextFile !== "Ctrl+Right" ||
            pad.shortcutPreviousFile !== "Ctrl+Left" ||
            pad.editorFileNavigationOffset({key: Qt.Key_Right,
              modifiers: Qt.ControlModifier}) !== 1 ||
            pad.editorFileNavigationOffset({key: Qt.Key_Left,
              modifiers: Qt.ControlModifier}) !== -1 ||
            pad.editorFileNavigationOffset({key: Qt.Key_Right,
              modifiers: Qt.NoModifier}) !== 0) {
          test.fail("Ctrl+Arrow note navigation defaults or routing are incorrect")
          return
        }
        var migratedShortcuts = pad.migratedShortcutSettings(6,
          {maximize: "F11", save: "F11", nextFile: "Ctrl+Tab",
            previousFile: "Ctrl+Shift+Tab"})
        var preservedCustomShortcuts = pad.migratedShortcutSettings(6,
          {maximize: "Alt+M", nextFile: "Alt+Right",
            previousFile: "Alt+Left"})
        var currentShortcuts = pad.migratedShortcutSettings(9,
          {maximize: "F11", nextFile: "Ctrl+Tab",
            previousFile: "Ctrl+Shift+Tab"})
        if (migratedShortcuts.maximize !== "Ctrl+F" ||
            migratedShortcuts.save !== "F11" ||
            migratedShortcuts.nextFile !== "Ctrl+Right" ||
            migratedShortcuts.previousFile !== "Ctrl+Left" ||
            preservedCustomShortcuts.maximize !== "Alt+M" ||
            preservedCustomShortcuts.nextFile !== "Alt+Right" ||
            preservedCustomShortcuts.previousFile !== "Alt+Left" ||
            currentShortcuts.maximize !== "F11" ||
            currentShortcuts.nextFile !== "Ctrl+Tab" ||
            currentShortcuts.previousFile !== "Ctrl+Shift+Tab") {
          test.fail("shortcut settings migration changed the wrong command")
          return
        }
        test.pass("shortcut help opens with the complete shortcut list")
        var footerShortcuts = JSON.parse(pad.footerShortcutState())
        if (!pad.windowMode || footerShortcuts.presentationMode !== "window" ||
            !footerShortcuts.shortcutRowVisible ||
            !footerShortcuts.shortcutHintVisible ||
            !footerShortcuts.shortcutButtonVisible ||
            footerShortcuts.shortcutHint.indexOf("Autosaves") >= 0 ||
            footerShortcuts.shortcutHint.indexOf(pad.shortcutHelp +
              " shortcuts") < 0) {
          test.fail("center view did not expose the shortcut footer: " +
            JSON.stringify(footerShortcuts))
          return
        }
        test.pass("center view exposes the Side-style shortcut footer")
        pad.toggleShortcutHelp()
        test.enterPhase(7)
        return
      }

      if (test.phase === 7) {
        if (pad.shortcutHelpOpen) {
          test.fail("shortcut help did not close from its toggle")
          return
        }
        test.pass("shortcut help closes from the same toggle")
        test.finish()
        return
      }

      if (test.phase === 10) {
        if (test.elapsed() < 130 && state.statusText === "Saved") {
          test.fail("idle save completed before the debounce interval")
          return
        }
        if (test.elapsed() < 130 && test.diskText === "idle-save") {
          test.fail("idle save reached disk before the debounce interval")
          return
        }
        if (test.diskText === "idle-save" && state.statusText === "Saved" &&
            !state.dirty && !state.noteSaveInFlight) {
          test.pass("idle-debounced save wrote bytes and completed")
          test.editTo("manual-save")
          pad.saveNow()
          test.enterPhase(20)
        }
        return
      }

      if (test.phase === 20) {
        if (test.diskText === "manual-save" && state.statusText === "Saved" &&
            !state.dirty && !state.noteSaveInFlight) {
          test.pass("manual save wrote immediately and completed")
          test.editTo("coalesce-first")
          pad.saveNow()
          test.editTo("coalesced-save")
          test.enterPhase(25)
        }
        return
      }

      if (test.phase === 25) {
        if (test.diskText === "coalesced-save" &&
            state.statusText === "Saved" && !state.dirty &&
            !state.noteSaveInFlight) {
          test.pass("an edit during an in-flight save was not lost")
          pad.selectEditorRange(0, 3)
          test.enterPhase(27)
        }
        return
      }

      if (test.phase === 27) {
        if (test.elapsed() < 140) return
        if (state.statusText !== "Saved" || state.dirty ||
            state.noteSaveInFlight || test.diskText !== "coalesced-save") {
          test.fail("selection-only activity dirtied or rewrote the note")
          return
        }
        test.pass("selection-only activity did not trigger a save")
        pad.setPresentationMode("side")
        test.enterPhase(28)
        return
      }

      if (test.phase === 28) {
        if (!pad.sideMode) return
        if (state.sourceLength !== String("coalesced-save").length ||
            state.statusText !== "Saved" || state.dirty) {
          test.fail("switching to the drawer changed editor or save state")
          return
        }
        pad.setPresentationMode("window")
        test.enterPhase(29)
        return
      }

      if (test.phase === 29) {
        if (!pad.windowMode) return
        if (state.sourceLength !== String("coalesced-save").length ||
            state.statusText !== "Saved" || state.dirty) {
          test.fail("switching back to the window changed editor or save state")
          return
        }
        test.pass("drawer/window switching preserved the shared editor state")
        test.startContinuousEdit("crash-recovery-")
        test.enterPhase(30)
        return
      }

      if (test.phase === 30) {
        if (pad.recoveryHasSnapshot &&
            String(pad.recoverySnapshotSource || "").indexOf(
              test.mode === "prepare"
                ? "crash-recovery-"
                : "discard-recovery-") === 0) {
          continuousEdit.stop()
          if (test.mode === "prepare" && !test.observedDirtyDuringSave) {
            test.fail("normal save cleared dirty state before confirmation")
            return
          }
          test.pass("periodic recovery snapshot completed while continuously dirty")
          console.log("PERSIST_RECOVERY_PATH: " + pad.recoveryPath)
          test.finish()
        }
        return
      }

      if (test.phase === 40) {
        if (!pad.recoveryPromptOpen) return
        test.promptSource = String(pad.recoveryPromptSource || "")
        if (test.promptSource.indexOf("crash-recovery-") !== 0) {
          test.fail("startup prompt did not load the expected recovery source")
          return
        }
        test.pass("startup detected the recovery snapshot")
        pad.recoverSnapshot()
        test.enterPhase(50)
        return
      }

      if (test.phase === 50) {
        if (test.diskText === test.promptSource &&
            state.statusText === "Saved" && !state.dirty &&
            !state.noteSaveInFlight && !pad.recoveryHasSnapshot) {
          test.pass("Recover restored, saved, and cleaned up the snapshot")
          test.finish()
        }
        return
      }

      if (test.phase === 60) {
        if (!pad.recoveryPromptOpen) return
        if (String(pad.recoveryPromptSource || "").indexOf(
            "discard-recovery-") !== 0) {
          test.fail("discard prompt did not load the expected recovery source")
          return
        }
        test.noteBeforeDiscard = test.diskText
        test.pass("startup detected the discard candidate")
        pad.discardRecovery()
        test.enterPhase(70)
        return
      }

      if (test.phase === 70 && !pad.recoveryPromptOpen &&
          !pad.recoveryHasSnapshot) {
        if (test.diskText !== test.noteBeforeDiscard) {
          test.fail("Discard changed the saved note")
          return
        }
        test.pass("Discard preserved the note and cleaned up the snapshot")
        test.finish()
      }
    }
  }

  Timer {
    interval: 6000
    repeat: false
    running: true
    onTriggered: test.fail("timed out in phase " + test.phase + " with " +
      (test.pad() ? test.pad().persistenceState() + " renderer " +
        test.pad().renderedDocumentStateForTests() : "no component"))
  }
}
