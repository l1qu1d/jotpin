import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "EditorModel.js" as EditorModel
import "SpellcheckModel.js" as SpellcheckModel

Item {
  id: root

  // Injected by omarchy-shell when the panel Loader resolves.
  property var shell: null
  property var manifest: null
  // Other Quickshell hosts can inject the contract documented in PORTING.md.
  property var hostIntegration: null

  HostIntegration {
    id: builtinHostIntegration
    shell: root.shell
    manifest: root.manifest
    fallbackBarSize: root.defaultBarSize
  }

  readonly property var activeHostIntegration:
    root.hostIntegration || builtinHostIntegration

  property bool opened: false
  property bool controlKeyHeld: false
  property var externalUrlOpener: function(target) {
    return Qt.openUrlExternally(target)
  }
  property bool rawMode: false
  property bool loadingFromFile: true
  property bool startupContentRevealed: false
  property bool startupImageWaitExpired: false
  property bool startupMessageVisible: false
  property bool startupRecoveryVisible: false
  readonly property bool startupContentReady: !loadingFromFile &&
    noteLoadError === "" && presentationSettingsLoaded && editorStatesLoaded &&
    pendingEditorStateRestorePath === "" &&
    (rawMode || (renderedEditor.initialLayoutReady &&
      (renderedEditor.imagesReady || startupImageWaitExpired)))

  function revealStartupContent() {
    // Image/highlight completion can notify before rebuilding geometry. The
    // deferred call rechecks the current document after those handlers return.
    if (startupContentRevealed || !startupContentReady) return
    startupContentRevealed = true
    root.focusEditorAfterFileLoad(root.notePath)
  }

  onStartupContentReadyChanged: {
    if (startupContentReady) Qt.callLater(root.revealStartupContent)
  }

  Timer {
    interval: 150
    running: !root.startupContentRevealed && !root.startupMessageVisible
    onTriggered: root.startupMessageVisible = true
  }
  Timer {
    interval: 750
    running: !root.loadingFromFile && !root.startupContentRevealed &&
      !root.startupImageWaitExpired
    onTriggered: root.startupImageWaitExpired = true
  }
  Timer {
    interval: 3000
    running: !root.loadingFromFile && !root.startupContentRevealed &&
      !root.startupRecoveryVisible
    onTriggered: root.startupRecoveryVisible = true
  }
  property string noteLoadWatchdogPath: ""
  property int noteLoadRetryCount: 0
  property int noteLoadWatchdogIntervalMs: 3000
  readonly property int noteLoadMaxRetries: 2
  property bool editorUpdating: false
  property bool editorAutoFormatting: false
  property bool taskToggleViewportRestorePending: false
  property real taskToggleViewportY: 0
  property int taskToggleViewportSettledFrames: 0
  property bool autoFencePending: false
  property int autoFenceCloseStart: -1
  property string autoFenceCloseText: ""
  property var autoCodePairs: []
  property string editorPreviousText: ""
  property bool noteMissing: false
  property string noteLoadError: ""
  property string knownDiskPath: ""
  property string knownDiskSource: ""
  property bool externalReloadPending: false
  property string externalReloadPath: ""
  property bool externalConflict: false
  property bool externalConflictMissing: false
  property string externalConflictPath: ""
  property string externalConflictSource: ""
  property bool directoryReady: false
  property bool pendingSave: false
  property bool dirty: false
  property string statusText: "Ready"
  property string markdownSource: ""
  property rect liveCursorRect: Qt.rect(0, 0, 1, 0)
  property bool liveCursorVisible: true
  property int liveCursorSourcePosition: -1
  property real liveVerticalNavigationX: -1
  // Both presentations are native compositor-managed toplevels so current
  // system window shortcuts keep their meanings without being duplicated in
  // JotPin. Separate windows let Hyprland apply each static map-time rule.
  property string presentationMode: "side"
  property string sidePlacement: "right"
  property bool sidePlacementRemapping: false
  property bool presentationSettingsLoaded: false
  property bool presentationSettingsHydrating: false
  property string pendingPresentationMode: ""
  property string pendingSidePlacement: ""
  property int pendingFileTabRows: 0
  property string pendingSessionPath: ""
  property string pendingNotesDirectory: ""
  property var pendingShortcuts: ({})
  property bool recentFilesMutatedBeforeSettingsLoaded: false
  property bool recentFilesClearedBeforeSettingsLoaded: false
  property var fileEditorStates: ({})
  property bool editorStatesLoaded: false
  property bool editorStatesHydrating: false
  property bool editorStatesWritePending: false
  property bool editorStatesWriteInFlight: false
  property bool restoringEditorState: false
  property bool applyingEditorHistory: false
  property bool historyInputStateValid: false
  property string historyInputBeforeSource: ""
  property int historyInputBeforeCursor: 0
  property int historyInputBeforeSelectionStart: 0
  property int historyInputBeforeSelectionEnd: 0
  property int historyInputKey: 0
  property int historyInputModifiers: 0
  property string pendingEditorStateRestorePath: ""
  property real pendingEditorStateScrollY: 0
  property bool viewCaretAlignmentPending: false
  property bool pendingViewCaretRawMode: false
  property int pendingViewCaretPosition: -1
  property real pendingViewCaretViewportY: 0
  property int pendingViewCaretAlignmentAttempts: 0
  property int editorHistoryRevision: 0
  readonly property int editorHistoryMaxTransactions: 100
  readonly property int editorHistoryMaxTextBytes: 131072
  readonly property bool editorCanUndo: {
    var revision = root.editorHistoryRevision
    var state = root.fileEditorStates[root.notePath]
    return Boolean(state && Array.isArray(state.past) &&
      state.past.length > 0)
  }
  readonly property bool editorCanRedo: {
    var revision = root.editorHistoryRevision
    var state = root.fileEditorStates[root.notePath]
    return Boolean(state && Array.isArray(state.future) &&
      state.future.length > 0)
  }
  readonly property var activeTableToolbarState:
    EditorModel.tableToolbarState(
      String(editor.text || ""), editor.cursorPosition, root.rawMode)
  property string pendingWorkspaceName: ""
  property bool presentationSettingsDirectoryReady: false
  property bool presentationSettingsWritePending: false
  property bool presentationSettingsWriteInFlight: false
  property int hyprlandWindowStateRevision: 0
  property bool maximizeStatePending: false
  property bool maximizeStateRequested: false
  property bool maximizeStateObserved: false
  property double maximizeStateRequestedAt: 0
  readonly property bool sideMode: root.presentationMode === "side"
  readonly property bool windowMode: root.presentationMode === "window"
  readonly property bool sideLeftMode: root.sideMode &&
    root.sidePlacement === "left"
  readonly property bool sideRightMode: root.sideMode &&
    root.sidePlacement === "right"
  readonly property bool activeWindowMaximized: {
    // The Hyprland model updates asynchronously after dispatch(). Reading the
    // revision keeps this binding live even when the model mutates a nested
    // IPC map without changing the toplevel list itself.
    var stateRevision = root.hyprlandWindowStateRevision
    return root.maximizeStatePending
      ? root.maximizeStateRequested : root.maximizeStateObserved
  }
  readonly property string fullScreenIconText:
    root.activeWindowMaximized ? "󰘕" : "󰘖"
  readonly property bool sideExpanded: root.sideMode &&
    root.activeWindowMaximized
  readonly property bool windowExpanded: root.windowMode &&
    root.activeWindowMaximized

  // Side is a monitor-height native window. Keep its drawer surface clear of
  // the live bar strip while preserving compositor fullscreen behavior.
  readonly property string barPosition: root.activeHostIntegration
    ? String(root.activeHostIntegration.barPosition || "top") : "top"
  readonly property bool screensaverActive: Boolean(
    root.activeHostIntegration &&
      root.activeHostIntegration.screensaverActive)
  readonly property bool barVertical: root.barPosition === "left" ||
    root.barPosition === "right"
  readonly property int defaultBarSize: root.barVertical
    ? Style.bar.sizeVertical
    : Style.bar.sizeHorizontal
  readonly property int liveBarSize: root.activeHostIntegration
    ? Math.max(0, Number(root.activeHostIntegration.liveBarSize) || 0)
    : root.defaultBarSize
  readonly property int barClearance: root.liveBarSize
  // The side window fills the output. Its only inner inset is the live bar
  // strip, wherever the configured bar is placed.
  readonly property int sideTopMargin: root.barPosition === "top"
    ? root.barClearance
    : 0
  readonly property int sideRightMargin: root.barPosition === "right"
    ? root.barClearance
    : 0
  readonly property int sideBottomMargin: root.barPosition === "bottom"
    ? root.barClearance
    : 0
  readonly property int sideLeftMargin: root.barPosition === "left"
    ? root.barClearance
    : 0
  readonly property int sideOuterMargin: root.sidePlacement === "left"
    ? root.sideLeftMargin
    : root.sideRightMargin

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string builtinNotesDirectory: home + "/Documents/Notes"
  property string defaultNotesDirectory: builtinNotesDirectory
  readonly property string defaultNotePath: defaultNotesDirectory + "/welcome.md"
  readonly property string stateDirectory: home + "/.local/state/jotpin"
  readonly property string presentationSettingsPath:
    stateDirectory + "/settings.json"
  readonly property string editorStatesPath:
    stateDirectory + "/editor-states.json"
  // Version 10 enables spellcheck once for existing profiles while retaining
  // any choice made after migration. Version 9 migrated note navigation.
  readonly property int presentationSettingsVersion: 10
  readonly property string recoveryDirectory:
    stateDirectory + "/recovery"
  property string notePath: defaultNotePath
  property var openFiles: []
  property var recentFiles: []
  readonly property int recentFilesLimit: 10
  property var recentFileValidationQueue: []
  property string recentFileValidationPath: ""
  property bool openingMostRecent: false
  property var recentOpenFallbackQueue: []
  property string recentOpenCandidatePath: ""
  property var generatedUntitledPaths: []
  property int editorTextScale: 100
  property int pendingEditorTextScale: 0
  readonly property int editorPixelSize:
    Math.max(1, Math.round(Style.font.body * editorTextScale / 100))
  property int fileTabRows: 2
  readonly property int minimumFileTabRows: 1
  readonly property int maximumFileTabRows: 5
  property bool shortcutHelpOpen: false
  property bool settingsOpen: false
  property string settingsDefaultNotesDirectory: ""
  property string settingsMessage: ""
  property bool settingsDirectoryChangeInFlight: false
  property string settingsDirectoryChangePath: ""
  property bool spellcheckEnabled: true
  // A header/settings click can arrive before settings.json finishes loading.
  // Keep that choice separate from the optimistic default so hydration cannot
  // replace it with the older stored value.
  property int pendingSpellcheckEnabled: -1
  readonly property string spellcheckLanguage: "en-US"
  readonly property int spellcheckDelayMs: 800
  property bool spellcheckReady: false
  property bool spellcheckInitializationPending: false
  property bool personalDictionaryLoaded: false
  property var personalDictionaryWords: []
  readonly property string personalDictionaryPath:
    stateDirectory + "/personal-dictionary.json"
  property bool personalDictionaryWritePending: false
  property bool personalDictionaryWriteInFlight: false
  property int spellcheckSourceRevision: 0
  property int spellcheckRequestId: 0
  property int spellcheckDispatchCount: 0
  property int spellcheckFullDispatchCount: 0
  property int spellcheckIncrementalDispatchCount: 0
  property bool spellcheckNeedsFullCheck: true
  property var spellcheckPendingEdits: []
  property var spellcheckLastMetrics: ({})
  property bool spellcheckHasCheckedCandidates: false
  property var spellcheckCheckedCandidates: []
  property var spellcheckPendingCandidates: []
  property int spellcheckSuggestionRequestId: 0
  property var misspellings: []
  property var spellingContextRange: null
  property var spellingContextSuggestions: []
  property bool spellingSuggestionsPending: false
  property int spellingGeometryRevision: 0
  property var spellingUnderlineModel: []
  property int spellingUnderlinePublishCount: 0
  property bool spellingGeometryDeferred: false
  property int spellingUnderlineDelegateCreateCount: 0
  property bool editorCommandOpen: false
  property string editorCommandMode: "find"
  property string findQuery: ""
  property int findAnchorPosition: 0
  property int findMatchIndex: 0
  property int findMatchCount: 0
  property string replaceValue: ""
  property string goToLineValue: ""
  property bool findCaseSensitive: false
  property string editorCommandMessage: ""
  property string shortcutSave: "Ctrl+S"
  property string shortcutSaveAs: "Ctrl+Shift+S"
  property string shortcutOpen: "Ctrl+O"
  property string shortcutOpenRecent: "Ctrl+Shift+O"
  property string shortcutClearRecent: "Ctrl+Alt+O"
  property string shortcutNew: "Ctrl+N"
  property string shortcutPreview: "Ctrl+P"
  property string shortcutFileMenu: "Alt+F"
  property string shortcutPresentation: "Ctrl+Shift+M"
  property string shortcutMaximize: "Ctrl+F"
  property string shortcutSettings: "Ctrl+,"
  property string shortcutHelp: "F1"
  property string shortcutNextFile: "Ctrl+Right"
  property string shortcutPreviousFile: "Ctrl+Left"
  property string shortcutCloseFile: "Ctrl+Shift+W"
  property string shortcutRenameFile: "F2"
  property string shortcutToggleTask: "Ctrl+Enter"
  property string shortcutFind: "Ctrl+Shift+F"
  property string shortcutReplace: "Ctrl+H"
  property string shortcutGoToLine: "Ctrl+G"
  property string shortcutFindNext: "F3"
  property string shortcutFindPrevious: "Shift+F3"
  property string shortcutContextMenu: "Shift+F10"
  property string shortcutClose: "Ctrl+W"
  property int shortcutRevision: 0
  readonly property var fixedShortcutValues: [
    "Esc", "Ctrl+Z", "Ctrl+Y", "Ctrl+Shift+Z",
    "Ctrl+A", "Ctrl+C", "Ctrl+X", "Ctrl+V"
  ]
  readonly property var shortcutSettingEntries: [
    { id: "save", label: "Save now", defaultValue: "Ctrl+S",
      description: "Write the current note immediately." },
    { id: "saveAs", label: "Save As", defaultValue: "Ctrl+Shift+S",
      description: "Open the filename and folder chooser." },
    { id: "open", label: "Open note", defaultValue: "Ctrl+O",
      description: "Open the Markdown note chooser." },
    { id: "openRecent", label: "Open most recent note",
      defaultValue: "Ctrl+Shift+O",
      description: "Open the newest usable entry in Recent Files." },
    { id: "clearRecent", label: "Clear Recent Files",
      defaultValue: "Ctrl+Alt+O",
      description: "Remove every entry from Recent Files." },
    { id: "new", label: "New note", defaultValue: "Ctrl+N",
      description: "Create a blank note in the default folder." },
    { id: "preview", label: "Toggle Preview / Raw", defaultValue: "Ctrl+P",
      description: "Switch between rendered and source views." },
    { id: "fileMenu", label: "File menu", defaultValue: "Alt+F",
      description: "Open or close the File menu." },
    { id: "presentation", label: "Toggle Side / Center", defaultValue: "Ctrl+Shift+M",
      description: "Switch between the side drawer and centered window." },
    { id: "maximize", label: "Full Screen", defaultValue: "Ctrl+F",
      description: "Toggle the full available workspace view." },
    { id: "settings", label: "Settings", defaultValue: "Ctrl+,",
      description: "Open or close JotPin settings." },
    { id: "help", label: "Shortcut help", defaultValue: "F1",
      description: "Show or hide the keyboard shortcut card." },
    { id: "nextFile", label: "Next file tab", defaultValue: "Ctrl+Right",
      description: "Switch to the next open note." },
    { id: "previousFile", label: "Previous file tab", defaultValue: "Ctrl+Left",
      description: "Switch to the previous open note." },
    { id: "closeFile", label: "Close active file tab", defaultValue: "Ctrl+Shift+W",
      description: "Close the active note while keeping JotPin open." },
    { id: "renameFile", label: "Rename active file", defaultValue: "F2",
      description: "Rename the active Markdown note." },
    { id: "toggleTask", label: "Toggle task at caret", defaultValue: "Ctrl+Enter",
      description: "Check or uncheck the task on the active source row." },
    { id: "find", label: "Find", defaultValue: "Ctrl+Shift+F",
      description: "Find literal text in the active note." },
    { id: "replace", label: "Find and Replace", defaultValue: "Ctrl+H",
      description: "Find and replace literal text in the active note." },
    { id: "goToLine", label: "Go to Line", defaultValue: "Ctrl+G",
      description: "Move the caret to a source line number." },
    { id: "findNext", label: "Find next", defaultValue: "F3",
      description: "Select the next match, wrapping at the end." },
    { id: "findPrevious", label: "Find previous", defaultValue: "Shift+F3",
      description: "Select the previous match, wrapping at the start." },
    { id: "contextMenu", label: "Editor context menu",
      defaultValue: "Shift+F10",
      description: "Open Undo, clipboard, and selection commands." },
    { id: "close", label: "Close JotPin", defaultValue: "Ctrl+W",
      description: "Close JotPin while keeping its session state." }
  ]
  readonly property var shortcutHelpEntries: [
    { keys: root.shortcutSave, action: "Save now" },
    { keys: root.shortcutSaveAs, action: "Save As" },
    { keys: root.shortcutOpen, action: "Open note" },
    { keys: root.shortcutOpenRecent, action: "Open most recent note" },
    { keys: root.shortcutClearRecent, action: "Clear Recent Files" },
    { keys: root.shortcutNew, action: "New note" },
    { keys: root.shortcutPreview, action: "Toggle Preview / Raw" },
    { keys: root.shortcutFileMenu, action: "File menu" },
    { keys: root.shortcutPresentation, action: "Toggle Side / Center" },
    { keys: root.shortcutMaximize, action: "Full Screen" },
    { keys: root.shortcutSettings, action: "Settings" },
    { keys: root.shortcutHelp, action: "Shortcut help" },
    { keys: root.shortcutNextFile, action: "Next file tab" },
    { keys: root.shortcutPreviousFile, action: "Previous file tab" },
    { keys: root.shortcutCloseFile, action: "Close active file tab" },
    { keys: root.shortcutRenameFile, action: "Rename active file" },
    { keys: root.shortcutToggleTask, action: "Toggle task at caret" },
    { keys: root.shortcutFind, action: "Find" },
    { keys: root.shortcutReplace, action: "Find and Replace" },
    { keys: root.shortcutGoToLine, action: "Go to Line" },
    { keys: root.shortcutFindNext + " / " + root.shortcutFindPrevious,
      action: "Find next / previous" },
    { keys: root.shortcutContextMenu, action: "Editor context menu" },
    { keys: "Ctrl+Z", action: "Undo" },
    { keys: "Ctrl+Y / Ctrl+Shift+Z", action: "Redo" },
    { keys: "Ctrl+A / Ctrl+C / Ctrl+X / Ctrl+V",
      action: "Select all / Copy / Cut / Paste" },
    { keys: "Tab / Shift+Tab", action: "Indent / outdent source rows" },
    { keys: "Enter", action: "Activate the focused control" },
    { keys: "Esc / " + root.shortcutClose, action: "Close JotPin" }
  ]
  property bool saveAsOpen: false
  property string fileChooserMode: ""
  property string fileChooserMessage: ""
  property bool openingFile: false
  property string openingPath: ""
  property string pendingRecentPromotionPath: ""
  property string saveAsDirectory: ""
  property string saveAsName: ""
  property var saveAsFolders: []
  property var openNoteFiles: []
  property string openNoteFilesDirectory: ""
  property bool openNoteFilesLoading: false
  property bool savingAs: false
  property bool saveAsChecking: false
  property string saveAsCheckPath: ""
  property string saveAsOverwritePath: ""
  property string saveAsPath: ""
  // A new Save As destination is first written to a unique file in the same
  // directory, then linked into place with an exclusive create.  Confirmed
  // overwrites keep the destination as the write path because the user has
  // explicitly authorized replacing that exact file.
  property string saveAsWritePath: ""
  property string saveAsTempPath: ""
  property string saveAsOverwriteConfirmedPath: ""
  property string saveAsCleanupPath: ""
  property bool saveAsCleanupAfterSuccess: false
  property string saveAsText: ""
  property string adoptedSaveAsPath: ""
  property bool quickCreating: false
  property string quickCreatedPath: ""
  property string replaceLastFilePath: ""
  property string renamingPath: ""
  property string renameValue: ""
  property bool renameInProgress: false
  property bool renameTargetChecking: false
  property bool pendingRenameCommit: false
  property string renameOldPath: ""
  property string renameNewPath: ""
  property string pendingNoteSavePath: ""
  property string pendingNoteSaveSource: ""
  property string pendingSwitchPath: ""
  property bool pendingSwitchContinuationQueued: false
  property string noteLoadedPath: ""
  property string recoveryLoadedPath: ""
  property bool recoveryHasSnapshot: false
  property string recoverySnapshotNotePath: ""
  property string recoverySnapshotSource: ""
  property string recoveryPromptPath: ""
  property string recoveryPromptSource: ""
  property bool recoveryPromptOpen: false
  property bool recoveryDirectoryReady: false
  property bool recoveryWritePending: false
  property bool recoveryWriteInFlight: false
  property string recoveryWritePath: ""
  property string recoveryWriteNotePath: ""
  property string recoveryWriteSource: ""
  property var recoveryDeleteQueue: []
  property var recoveryDeletesAfterWrite: []
  property string recoveryDeletePath: ""
  property bool noteSaveInFlight: false
  property string pendingClosePath: ""
  property bool untitledBlankCheckInFlight: false
  property string untitledBlankCheckPath: ""
  property bool untitledDeleteInFlight: false
  property string untitledDeletePath: ""
  property int saveDelayMs: 1500
  property int recoveryIntervalMs: 10000

  readonly property string recoveryPath:
    root.recoveryPathFor(root.notePath)

  readonly property string displayPath: {
    var prefix = root.home + "/"
    return root.notePath.indexOf(prefix) === 0
      ? "~/" + root.notePath.slice(prefix.length)
      : root.notePath
  }

  readonly property string noteDirectory: {
    var slash = root.notePath.lastIndexOf("/")
    return slash > 0 ? root.notePath.slice(0, slash) : "."
  }

  readonly property color foreground: Color.popups.text
  readonly property color background: Color.popups.background
  readonly property color border: Color.popups.border
  readonly property color editorBackground: Qt.rgba(
    root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
  readonly property color scrim: Qt.rgba(
    Color.background.r, Color.background.g, Color.background.b, 0.48)
  readonly property var surfaceBorder: Border.surfaceSpec(
    "popups", "border", root.border, Math.max(1, Style.space(1)))

  function pluginId() {
    var host = root.activeHostIntegration
    return host && host.pluginId ? String(host.pluginId) : "dev.jotpin"
  }

  function normalizedPresentationMode(value) {
    var mode = String(value || "").trim().toLowerCase()
    if (mode === "center") mode = "window"
    return mode === "side" || mode === "window" ? mode : ""
  }

  function normalizedSidePlacement(value) {
    var placement = String(value || "").trim().toLowerCase()
    return placement === "left" || placement === "right" ? placement : ""
  }

  function normalizedFileTabRows(value) {
    var rows = Number(value)
    if (!isFinite(rows)) return root.minimumFileTabRows
    return Math.max(root.minimumFileTabRows,
      Math.min(root.maximumFileTabRows, Math.round(rows)))
  }

  function setEditorTextScale(value) {
    var scale = Number(value)
    if (!isFinite(scale)) return
    scale = Math.max(75, Math.min(200, Math.round(scale)))
    if (!root.presentationSettingsLoaded) root.pendingEditorTextScale = scale
    root.editorTextScale = scale
  }

  function setFileTabRows(value) {
    var rows = root.normalizedFileTabRows(value)
    if (!root.presentationSettingsLoaded) root.pendingFileTabRows = rows
    root.fileTabRows = rows
  }

  function setSidePlacement(value) {
    var placement = root.normalizedSidePlacement(value)
    if (placement === "") return
    var shouldRemap = root.opened && root.sideMode &&
      root.sidePlacement !== placement
    if (shouldRemap) root.sidePlacementRemapping = true
    if (!root.presentationSettingsLoaded)
      root.pendingSidePlacement = placement
    root.sidePlacement = placement
    if (shouldRemap) {
      // Hyprland's placement rules run when the native toplevel maps. Hide
      // and remap it so a live settings change moves the drawer immediately.
      Qt.callLater(function() { root.sidePlacementRemapping = false })
    }
  }

  function normalizedShortcut(value) {
    var raw = String(value || "").trim()
    if (raw === "") return ""

    var parts = raw.split("+")
    var key = String(parts.pop() || "").trim()
    if (key === "") return ""

    var modifiers = []
    var seenModifiers = ({})
    var modifierAliases = ({
      "control": "Ctrl",
      "ctrl": "Ctrl",
      "alt": "Alt",
      "option": "Alt",
      "shift": "Shift",
      "meta": "Meta",
      "super": "Meta",
      "command": "Meta",
      "cmd": "Meta"
    })
    for (var index = 0; index < parts.length; index++) {
      var modifierName = String(parts[index] || "").trim().toLowerCase()
      var modifier = modifierAliases[modifierName]
      if (!modifier || seenModifiers[modifier]) return ""
      seenModifiers[modifier] = true
      modifiers.push(modifier)
    }

    var keyAliases = ({
      "escape": "Esc",
      "return": "Enter",
      "spacebar": "Space",
      "page-up": "PageUp",
      "page-down": "PageDown",
      "pageup": "PageUp",
      "pagedown": "PageDown",
      "del": "Delete"
    })
    var keyName = keyAliases[key.toLowerCase()] || key
    var namedKeys = [
      "Esc", "Tab", "Enter", "Space", "Backspace", "Delete", "Insert",
      "Home", "End", "PageUp", "PageDown", "Left", "Right", "Up", "Down",
      "Plus", "Minus", "Equal", "Comma", "Period", "Slash", "Semicolon",
      "Apostrophe", "BracketLeft", "BracketRight", ","
    ]
    var isFunctionKey = /^F([1-9]|[12][0-9]|3[0-5])$/i.test(keyName)
    var isSingleKey = /^[A-Za-z0-9]$/.test(keyName)
    if (!isSingleKey && namedKeys.indexOf(keyName) < 0 && !isFunctionKey)
      return ""
    if (isSingleKey) keyName = keyName.toUpperCase()

    var modifierOrder = ["Ctrl", "Alt", "Shift", "Meta"]
    var orderedModifiers = []
    for (var orderIndex = 0; orderIndex < modifierOrder.length; orderIndex++) {
      if (seenModifiers[modifierOrder[orderIndex]])
        orderedModifiers.push(modifierOrder[orderIndex])
    }
    return orderedModifiers.length > 0
      ? orderedModifiers.join("+") + "+" + keyName
      : keyName
  }

  function shortcutIds() {
    return ["save", "saveAs", "open", "openRecent", "clearRecent", "new",
      "preview", "fileMenu", "presentation", "maximize", "settings",
      "help", "nextFile", "previousFile", "closeFile", "renameFile",
      "toggleTask", "find", "replace", "goToLine", "findNext",
      "findPrevious", "contextMenu", "close"]
  }

  function shortcutValue(id) {
    switch (String(id || "")) {
    case "save": return root.shortcutSave
    case "saveAs": return root.shortcutSaveAs
    case "open": return root.shortcutOpen
    case "openRecent": return root.shortcutOpenRecent
    case "clearRecent": return root.shortcutClearRecent
    case "new": return root.shortcutNew
    case "preview": return root.shortcutPreview
    case "fileMenu": return root.shortcutFileMenu
    case "presentation": return root.shortcutPresentation
    case "maximize": return root.shortcutMaximize
    case "settings": return root.shortcutSettings
    case "help": return root.shortcutHelp
    case "nextFile": return root.shortcutNextFile
    case "previousFile": return root.shortcutPreviousFile
    case "closeFile": return root.shortcutCloseFile
    case "renameFile": return root.shortcutRenameFile
    case "toggleTask": return root.shortcutToggleTask
    case "find": return root.shortcutFind
    case "replace": return root.shortcutReplace
    case "goToLine": return root.shortcutGoToLine
    case "findNext": return root.shortcutFindNext
    case "findPrevious": return root.shortcutFindPrevious
    case "contextMenu": return root.shortcutContextMenu
    case "close": return root.shortcutClose
    }
    return ""
  }

  function defaultShortcutValue(id) {
    switch (String(id || "")) {
    case "save": return "Ctrl+S"
    case "saveAs": return "Ctrl+Shift+S"
    case "open": return "Ctrl+O"
    case "openRecent": return "Ctrl+Shift+O"
    case "clearRecent": return "Ctrl+Alt+O"
    case "new": return "Ctrl+N"
    case "preview": return "Ctrl+P"
    case "fileMenu": return "Alt+F"
    case "presentation": return "Ctrl+Shift+M"
    case "maximize": return "Ctrl+F"
    case "settings": return "Ctrl+,"
    case "help": return "F1"
    case "nextFile": return "Ctrl+Right"
    case "previousFile": return "Ctrl+Left"
    case "closeFile": return "Ctrl+Shift+W"
    case "renameFile": return "F2"
    case "toggleTask": return "Ctrl+Enter"
    case "find": return "Ctrl+Shift+F"
    case "replace": return "Ctrl+H"
    case "goToLine": return "Ctrl+G"
    case "findNext": return "F3"
    case "findPrevious": return "Shift+F3"
    case "contextMenu": return "Shift+F10"
    case "close": return "Ctrl+W"
    }
    return ""
  }

  function assignShortcutValue(id, value) {
    switch (String(id || "")) {
    case "save": root.shortcutSave = value; break
    case "saveAs": root.shortcutSaveAs = value; break
    case "open": root.shortcutOpen = value; break
    case "openRecent": root.shortcutOpenRecent = value; break
    case "clearRecent": root.shortcutClearRecent = value; break
    case "new": root.shortcutNew = value; break
    case "preview": root.shortcutPreview = value; break
    case "fileMenu": root.shortcutFileMenu = value; break
    case "presentation": root.shortcutPresentation = value; break
    case "maximize": root.shortcutMaximize = value; break
    case "settings": root.shortcutSettings = value; break
    case "help": root.shortcutHelp = value; break
    case "nextFile": root.shortcutNextFile = value; break
    case "previousFile": root.shortcutPreviousFile = value; break
    case "closeFile": root.shortcutCloseFile = value; break
    case "renameFile": root.shortcutRenameFile = value; break
    case "toggleTask": root.shortcutToggleTask = value; break
    case "find": root.shortcutFind = value; break
    case "replace": root.shortcutReplace = value; break
    case "goToLine": root.shortcutGoToLine = value; break
    case "findNext": root.shortcutFindNext = value; break
    case "findPrevious": root.shortcutFindPrevious = value; break
    case "contextMenu": root.shortcutContextMenu = value; break
    case "close": root.shortcutClose = value; break
    }
  }

  function shortcutIsAvailable(id, value) {
    if (root.fixedShortcutValues.indexOf(value) >= 0) return false
    var ids = root.shortcutIds()
    for (var index = 0; index < ids.length; index++) {
      if (ids[index] !== id && root.shortcutValue(ids[index]) === value)
        return false
    }
    return true
  }

  function applyShortcut(id, value) {
    var shortcutId = String(id || "")
    if (root.shortcutIds().indexOf(shortcutId) < 0) return false
    var next = root.normalizedShortcut(value)
    if (next === "") {
      root.settingsMessage = "Use a shortcut such as Ctrl+Shift+S"
      return false
    }
    if (!root.shortcutIsAvailable(shortcutId, next)) {
      root.settingsMessage = "That keyboard shortcut is already assigned"
      return false
    }

    root.assignShortcutValue(shortcutId, next)
    if (!root.presentationSettingsLoaded) {
      var pending = root.pendingShortcuts
      pending[shortcutId] = next
      root.pendingShortcuts = pending
    }
    root.settingsMessage = "Keyboard shortcut updated"
    root.schedulePersistedSettingsSave()
    return true
  }

  function resetShortcut(id) {
    return root.applyShortcut(id, root.defaultShortcutValue(id))
  }

  function resetShortcuts() {
    var ids = root.shortcutIds()
    for (var index = 0; index < ids.length; index++)
      root.assignShortcutValue(ids[index], root.defaultShortcutValue(ids[index]))
    root.shortcutRevision++
    root.pendingShortcuts = ({})
    root.settingsMessage = "Keyboard shortcuts reset"
    root.schedulePersistedSettingsSave()
  }

  function hydrateShortcuts(stored) {
    if (!stored || typeof stored !== "object") return
    var ids = root.shortcutIds()
    var candidate = ({})
    for (var index = 0; index < ids.length; index++) {
      var id = ids[index]
      candidate[id] = root.shortcutValue(id)
    }

    for (var storedIndex = 0; storedIndex < ids.length; storedIndex++) {
      var storedId = ids[storedIndex]
      var next = root.normalizedShortcut(stored[storedId])
      if (next === "") continue
      if (root.fixedShortcutValues.indexOf(next) >= 0) continue
      var conflict = false
      // Do not let an older customized command take a default now assigned
      // to another command. Otherwise an upgrade can create two active
      // Shortcuts even though the settings UI rejects the same collision.
      for (var defaultIndex = 0; defaultIndex < ids.length; defaultIndex++) {
        if (ids[defaultIndex] !== storedId &&
            root.defaultShortcutValue(ids[defaultIndex]) === next) {
          conflict = true
          break
        }
      }
      for (var candidateIndex = 0; candidateIndex < storedIndex;
           candidateIndex++) {
        if (candidate[ids[candidateIndex]] === next) {
          conflict = true
          break
        }
      }
      if (!conflict) candidate[storedId] = next
    }

    for (var assignIndex = 0; assignIndex < ids.length; assignIndex++)
      root.assignShortcutValue(ids[assignIndex], candidate[ids[assignIndex]])
  }

  function migratedShortcutSettings(storedVersion, stored) {
    if (!stored || typeof stored !== "object") return stored
    var migrated = ({})
    var storedIds = Object.keys(stored)
    for (var index = 0; index < storedIds.length; index++)
      migrated[storedIds[index]] = stored[storedIds[index]]

    var version = Number(storedVersion)
    if (!isFinite(version)) version = 0
    if (version < 7 &&
        root.normalizedShortcut(migrated.maximize) === "F11") {
      migrated.maximize = "Ctrl+F"
    }
    if (version < 9 &&
        root.normalizedShortcut(migrated.nextFile) === "Ctrl+Tab") {
      migrated.nextFile = "Ctrl+Right"
    }
    if (version < 9 &&
        root.normalizedShortcut(migrated.previousFile) === "Ctrl+Shift+Tab") {
      migrated.previousFile = "Ctrl+Left"
    }
    return migrated
  }

  function setPresentationMode(value) {
    var mode = root.normalizedPresentationMode(value)
    if (mode === "") return
    // A summon payload or a header click that arrives before the settings
    // file has finished loading must win over the stored value.
    if (!root.presentationSettingsLoaded) root.pendingPresentationMode = mode
    root.presentationMode = mode
  }

  function closeFileMenu() {
    if (fileMenuPopup.opened) fileMenuPopup.close()
  }

  function toggleFileMenu() {
    if (fileMenuPopup.opened) root.closeFileMenu()
    else {
      root.closeEditorContextMenu()
      fileMenuPopup.open()
    }
  }

  function saveFromFileMenu() {
    root.closeFileMenu()
    root.saveNow()
  }

  function fileMenuOpenForTests() {
    return Boolean(fileMenuPopup.opened)
  }

  function activateSpellcheckButtonForTests() {
    spellcheckButton.clicked()
    return root.spellcheckEnabled
  }

  function focusSpellcheckButtonForTests() {
    spellcheckButton.forceActiveFocus()
    return Boolean(spellcheckButton.activeFocus)
  }

  function spellcheckButtonStateForTests() {
    return JSON.stringify({
      enabled: root.spellcheckEnabled,
      selected: spellcheckButton.selected,
      icon: spellcheckButton.iconText,
      foreground: String(spellcheckButton.foreground),
      defaultForeground: String(root.foreground),
      activeFocus: Boolean(spellcheckButton.activeFocus),
      tooltip: spellcheckButton.tooltipText
    })
  }

  function normalizedDirectoryPath(value) {
    var nextPath = root.expandedPath(value).trim()
    if (nextPath === "" || nextPath.charAt(0) !== "/") return ""
    nextPath = nextPath.replace(/\/+$/, "")
    return nextPath === "" ? "/" : nextPath
  }

  function openSettings() {
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.editorCommandOpen = false
    root.settingsDefaultNotesDirectory = root.defaultNotesDirectory
    root.settingsMessage = ""
    root.settingsOpen = true
    root.shortcutHelpOpen = false
    root.saveAsOpen = false
    root.fileChooserMode = ""
    root.openingFile = false
    root.openingPath = ""
  }

  function closeSettings() {
    root.settingsOpen = false
    root.settingsMessage = ""
  }

  function toggleSettings() {
    if (root.settingsOpen) root.closeSettings()
    else root.openSettings()
  }

  function applyDefaultNotesDirectory(value) {
    var nextPath = root.normalizedDirectoryPath(value)
    if (nextPath === "") {
      root.settingsMessage = "Use an absolute folder path"
      return false
    }
    if (root.settingsDirectoryChangeInFlight) return false
    if (nextPath === root.defaultNotesDirectory) {
      root.settingsDefaultNotesDirectory = nextPath
      root.settingsMessage = "Default notes folder is unchanged"
      return true
    }

    root.settingsDirectoryChangePath = nextPath
    root.settingsDirectoryChangeInFlight = true
    root.settingsMessage = "Creating default notes folder…"
    defaultNotesDirectoryProcess.command = ["mkdir", "-p", nextPath]
    defaultNotesDirectoryProcess.running = true
    return true
  }

  function resetDefaultNotesDirectory() {
    root.applyDefaultNotesDirectory(root.builtinNotesDirectory)
  }

  function normalizedFilePath(value) {
    return root.normalizedMarkdownPath(value, false)
  }

  function isMarkdownPath(value) {
    return /\.md$/i.test(root.fileNameForPath(value))
  }

  function normalizedMarkdownPath(value, appendMissingExtension) {
    var nextPath = root.expandedPath(value).trim()
    if (nextPath === "" || nextPath.charAt(0) !== "/") return ""

    var fileName = root.fileNameForPath(nextPath)
    if (fileName === "") return ""
    if (root.isMarkdownPath(nextPath)) return nextPath
    if (appendMissingExtension && fileName.indexOf(".") < 0)
      return nextPath + ".md"
    return ""
  }

  function markdownFileNameForInput(value) {
    var nextName = String(value || "").trim()
    if (nextName === "" || nextName === "." || nextName === ".." ||
        nextName.indexOf("/") >= 0 || nextName.indexOf("\\") >= 0) {
      return ""
    }

    if (/\.md$/i.test(nextName)) {
      nextName = nextName.slice(0, -3)
    } else if (nextName.indexOf(".") >= 0) {
      return ""
    }

    return nextName === "" ? "" : nextName + ".md"
  }

  function markdownStemForPath(path) {
    var fileName = root.fileNameForPath(path)
    return /\.md$/i.test(fileName) ? fileName.slice(0, -3) : fileName
  }

  function persistedOpenFilePaths() {
    var paths = []
    for (var index = 0; index < root.openFiles.length; index++) {
      var path = root.normalizedFilePath(root.openFiles[index].path)
      if (path !== "" && paths.indexOf(path) < 0) paths.push(path)
    }

    var activePath = root.normalizedFilePath(root.notePath)
    if (activePath !== "" && paths.indexOf(activePath) < 0)
      paths.push(activePath)
    return paths
  }

  function emptyFileEditorState(path) {
    return {
      path: root.normalizedFilePath(path),
      cursorPosition: 0,
      selectionStart: 0,
      selectionEnd: 0,
      liveScrollY: 0,
      rawScrollY: 0,
      past: [],
      future: []
    }
  }

  function nonNegativeEditorStateNumber(value) {
    var number = Number(value)
    return isFinite(number) && number >= 0 ? number : 0
  }

  function sanitizedEditorHistoryTransaction(value) {
    if (!value || typeof value !== "object") return null
    var start = Number(value.start)
    if (!isFinite(start) || start < 0 || Math.floor(start) !== start ||
        typeof value.removed !== "string" ||
        typeof value.inserted !== "string") return null
    if (value.removed.length + value.inserted.length >
        root.editorHistoryMaxTextBytes) return null
    var kind = ["insert", "backspace", "delete", "replace"].indexOf(
      String(value.kind || "replace")) >= 0
      ? String(value.kind || "replace") : "replace"
    return {
      start: start,
      removed: value.removed,
      inserted: value.inserted,
      beforeCursor: root.nonNegativeEditorStateNumber(value.beforeCursor),
      beforeSelectionStart: root.nonNegativeEditorStateNumber(
        value.beforeSelectionStart),
      beforeSelectionEnd: root.nonNegativeEditorStateNumber(
        value.beforeSelectionEnd),
      afterCursor: root.nonNegativeEditorStateNumber(value.afterCursor),
      afterSelectionStart: root.nonNegativeEditorStateNumber(
        value.afterSelectionStart),
      afterSelectionEnd: root.nonNegativeEditorStateNumber(
        value.afterSelectionEnd),
      kind: kind,
      coalescible: value.coalescible === true,
      timestamp: root.nonNegativeEditorStateNumber(value.timestamp)
    }
  }

  function trimEditorHistory(pastValue, futureValue) {
    var past = Array.isArray(pastValue) ? pastValue.slice() : []
    var future = Array.isArray(futureValue) ? futureValue.slice() : []
    var bytes = 0
    function transactionBytes(transaction) {
      return String(transaction.removed || "").length +
        String(transaction.inserted || "").length
    }
    for (var pastIndex = 0; pastIndex < past.length; pastIndex++)
      bytes += transactionBytes(past[pastIndex])
    for (var futureIndex = 0; futureIndex < future.length; futureIndex++)
      bytes += transactionBytes(future[futureIndex])

    while (past.length + future.length >
        root.editorHistoryMaxTransactions ||
        bytes > root.editorHistoryMaxTextBytes) {
      var removed = past.length > 0 ? past.shift() : future.pop()
      if (!removed) break
      bytes -= transactionBytes(removed)
    }
    return { past: past, future: future, bytes: Math.max(0, bytes) }
  }

  function sanitizedEditorHistory(value) {
    var next = []
    if (!Array.isArray(value)) return next
    for (var index = 0; index < value.length; index++) {
      var transaction = root.sanitizedEditorHistoryTransaction(value[index])
      if (transaction) next.push(transaction)
    }
    return next
  }

  function normalizedFileEditorState(path, value) {
    var target = root.normalizedFilePath(path)
    var raw = value && typeof value === "object" ? value : ({})
    var trimmed = root.trimEditorHistory(
      root.sanitizedEditorHistory(raw.past),
      root.sanitizedEditorHistory(raw.future))
    return {
      path: target,
      cursorPosition: root.nonNegativeEditorStateNumber(raw.cursorPosition),
      selectionStart: root.nonNegativeEditorStateNumber(raw.selectionStart),
      selectionEnd: root.nonNegativeEditorStateNumber(raw.selectionEnd),
      liveScrollY: root.nonNegativeEditorStateNumber(raw.liveScrollY),
      rawScrollY: root.nonNegativeEditorStateNumber(raw.rawScrollY),
      past: trimmed.past,
      future: trimmed.future
    }
  }

  function fileEditorStateForPath(path) {
    var target = root.normalizedFilePath(path)
    if (target === "") return root.emptyFileEditorState("")
    var stored = root.fileEditorStates[target]
    return root.normalizedFileEditorState(target, stored)
  }

  function storeFileEditorState(path, value, scheduleWrite) {
    var target = root.normalizedFilePath(path)
    if (target === "") return false
    var states = Object.assign({}, root.fileEditorStates)
    states[target] = root.normalizedFileEditorState(target, value)
    root.fileEditorStates = states
    root.editorHistoryRevision++
    if (scheduleWrite !== false) editorStateSaveTimer.restart()
    return true
  }

  function storeTrustedFileEditorState(path, state, scheduleWrite) {
    var target = root.normalizedFilePath(path)
    if (target === "") return false
    var states = Object.assign({}, root.fileEditorStates)
    states[target] = state
    root.fileEditorStates = states
    root.editorHistoryRevision++
    if (scheduleWrite !== false) editorStateSaveTimer.restart()
    return true
  }

  function removeFileEditorState(path) {
    var target = root.normalizedFilePath(path)
    if (target === "" || root.fileEditorStates[target] === undefined)
      return false
    var states = Object.assign({}, root.fileEditorStates)
    delete states[target]
    root.fileEditorStates = states
    root.editorHistoryRevision++
    editorStateSaveTimer.restart()
    return true
  }

  function moveFileEditorState(oldPath, newPath) {
    var oldTarget = root.normalizedFilePath(oldPath)
    var nextTarget = root.normalizedFilePath(newPath)
    if (oldTarget === "" || nextTarget === "") return false
    var states = Object.assign({}, root.fileEditorStates)
    var state = root.normalizedFileEditorState(nextTarget, states[oldTarget])
    delete states[oldTarget]
    states[nextTarget] = state
    root.fileEditorStates = states
    root.editorHistoryRevision++
    editorStateSaveTimer.restart()
    return true
  }

  function copyFileEditorState(oldPath, newPath) {
    var oldTarget = root.normalizedFilePath(oldPath)
    var nextTarget = root.normalizedFilePath(newPath)
    if (oldTarget === "" || nextTarget === "") return false
    var source = root.fileEditorStateForPath(oldTarget)
    return root.storeFileEditorState(nextTarget, source)
  }

  function captureActiveEditorState(scheduleWrite) {
    var path = root.normalizedFilePath(root.notePath)
    if (path === "" || root.loadingFromFile || root.restoringEditorState ||
        root.editorUpdating || root.editorAutoFormatting ||
        root.applyingEditorHistory)
      return false
    var state = root.fileEditorStateForPath(path)
    state.cursorPosition = Math.max(0, Number(editor.cursorPosition) || 0)
    state.selectionStart = Math.max(0, Number(editor.selectionStart) || 0)
    state.selectionEnd = Math.max(0, Number(editor.selectionEnd) || 0)
    if (root.rawMode)
      state.rawScrollY = Math.max(0, Number(editorViewport.contentY) || 0)
    else state.liveScrollY = Math.max(0,
      Number(editorViewport.contentY) || 0)
    return root.storeTrustedFileEditorState(path, state, scheduleWrite)
  }

  function recordEditorHistory(beforeSourceValue, beforeCursor,
      beforeSelectionStart, beforeSelectionEnd, allowCoalescing) {
    if (root.loadingFromFile || root.applyingEditorHistory) return false
    var path = root.normalizedFilePath(root.notePath)
    var beforeSource = String(beforeSourceValue || "")
    var afterSource = String(editor.text || "")
    if (path === "" || beforeSource === afterSource) return false
    var transaction = EditorModel.makeEditTransaction(
      beforeSource, afterSource,
      beforeCursor, editor.cursorPosition,
      beforeSelectionStart, beforeSelectionEnd,
      editor.selectionStart, editor.selectionEnd,
      Date.now())
    if (!transaction) return false

    var state = root.fileEditorStateForPath(path)
    var past = state.past.slice()
    if (allowCoalescing === true && past.length > 0) {
      var merged = EditorModel.coalesceEditTransactions(
        past[past.length - 1], transaction, 750)
      if (merged) past[past.length - 1] = merged
      else past.push(transaction)
    } else past.push(transaction)
    var trimmed = root.trimEditorHistory(past, [])
    state.past = trimmed.past
    state.future = []
    state.cursorPosition = Math.max(0, Number(editor.cursorPosition) || 0)
    state.selectionStart = Math.max(0, Number(editor.selectionStart) || 0)
    state.selectionEnd = Math.max(0, Number(editor.selectionEnd) || 0)
    return root.storeTrustedFileEditorState(path, state)
  }

  function captureHistoryInputState(key, modifiers) {
    if (root.loadingFromFile || root.editorUpdating ||
        root.applyingEditorHistory) return
    root.historyInputBeforeSource = String(editor.text || "")
    root.historyInputBeforeCursor = Number(editor.cursorPosition) || 0
    root.historyInputBeforeSelectionStart = Number(editor.selectionStart) || 0
    root.historyInputBeforeSelectionEnd = Number(editor.selectionEnd) || 0
    root.historyInputKey = Number(key) || 0
    root.historyInputModifiers = Number(modifiers) || 0
    root.historyInputStateValid = true
  }

  function clearHistoryInputState() {
    root.historyInputStateValid = false
    root.historyInputBeforeSource = ""
    root.historyInputKey = 0
    root.historyInputModifiers = 0
  }

  function clearEditorHistoryForPath(path, scheduleWrite) {
    var target = root.normalizedFilePath(path)
    if (target === "") return false
    var state = root.fileEditorStateForPath(target)
    if (state.past.length === 0 && state.future.length === 0) return false
    state.past = []
    state.future = []
    return root.storeTrustedFileEditorState(target, state, scheduleWrite)
  }

  function applyEditorHistory(direction) {
    if (root.loadingFromFile || root.recoveryPromptOpen ||
        root.noteLoadError !== "") return false
    var path = root.normalizedFilePath(root.notePath)
    var state = root.fileEditorStateForPath(path)
    var undoing = direction === "undo"
    var transaction = undoing
      ? (state.past.length > 0 ? state.past[state.past.length - 1] : null)
      : (state.future.length > 0 ? state.future[0] : null)
    if (!transaction) return false
    var result = EditorModel.applyEditTransaction(
      String(editor.text || ""), transaction, direction)
    if (!result.valid) {
      state.past = []
      state.future = []
      root.storeTrustedFileEditorState(path, state)
      root.statusText = "Undo history reset after an external change"
      return false
    }

    root.applyingEditorHistory = true
    root.replaceEditorDocumentText(result.source, result.cursor)
    root.restoringEditorState = true
    root.restoreSelectionFromEditorState({
      cursorPosition: result.cursor,
      selectionStart: result.selectionStart,
      selectionEnd: result.selectionEnd
    }, result.source.length)
    root.restoringEditorState = false
    root.applyingEditorHistory = false

    if (undoing) {
      state.past = state.past.slice(0, state.past.length - 1)
      state.future = [transaction].concat(state.future)
    } else {
      state.future = state.future.slice(1)
      state.past = state.past.concat([transaction])
    }
    state.cursorPosition = result.cursor
    state.selectionStart = result.selectionStart
    state.selectionEnd = result.selectionEnd
    var trimmed = root.trimEditorHistory(state.past, state.future)
    state.past = trimmed.past
    state.future = trimmed.future
    root.storeTrustedFileEditorState(path, state)
    root.resetAutoFence()
    root.resetAutoCodePairs()
    root.noteEdited()
    Qt.callLater(function() {
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function restoreSelectionFromEditorState(state, sourceLength) {
    var length = Math.max(0, Number(sourceLength) || 0)
    var cursor = Math.max(0, Math.min(
      Number(state.cursorPosition) || 0, length))
    var start = Math.max(0, Math.min(
      Number(state.selectionStart) || 0, length))
    var end = Math.max(0, Math.min(
      Number(state.selectionEnd) || 0, length))
    if (start > end) {
      var swap = start
      start = end
      end = swap
    }
    if (start !== end) {
      var anchor = cursor === start ? end : start
      if (cursor !== start && cursor !== end) cursor = end
      editor.select(anchor, cursor)
    } else editor.cursorPosition = cursor
  }

  function finishPendingEditorStateRestore() {
    var path = root.pendingEditorStateRestorePath
    if (path === "" || path !== root.notePath || root.loadingFromFile) return
    if (!root.rawMode && String(editor.text || "") !== "" &&
        (!renderedEditor.layoutReady ||
         !renderedEditor.layoutMatchesCurrentInput())) return
    var maximumContentY = Math.max(0,
      editorViewport.contentHeight - editorViewport.height)
    root.restoringEditorState = true
    editorViewport.contentY = Math.max(0, Math.min(
      maximumContentY, root.pendingEditorStateScrollY))
    root.restoringEditorState = false
    if (!root.rawMode && String(editor.text || "") !== "") {
      editorStateRestoreSettleTimer.restart()
      return
    }
    root.pendingEditorStateRestorePath = ""
    root.pendingEditorStateScrollY = 0
  }

  function settlePendingEditorStateRestore() {
    var path = root.pendingEditorStateRestorePath
    if (path === "" || path !== root.notePath || root.loadingFromFile) return
    if (!renderedEditor.layoutReady ||
        !renderedEditor.layoutMatchesCurrentInput() ||
        !renderedEditor.viewportGeometrySettled ||
        (!root.startupContentRevealed && !root.rawMode &&
         (!renderedEditor.initialLayoutReady ||
          (!renderedEditor.imagesReady && !root.startupImageWaitExpired)))) {
      editorStateRestoreSettleTimer.restart()
      return
    }
    var maximumContentY = Math.max(0,
      editorViewport.contentHeight - editorViewport.height)
    root.restoringEditorState = true
    editorViewport.contentY = Math.max(0, Math.min(
      maximumContentY, root.pendingEditorStateScrollY))
    root.restoringEditorState = false
    root.pendingEditorStateRestorePath = ""
    root.pendingEditorStateScrollY = 0
  }

  function restoreEditorStateForSource(path, sourceValue) {
    var target = root.normalizedFilePath(path)
    if (target === "") return false
    var source = String(sourceValue || "")
    var state = root.fileEditorStateForPath(target)
    if (!EditorModel.validateEditTransactionChain(
        source, state.past, state.future).valid) {
      state.past = []
      state.future = []
      root.storeTrustedFileEditorState(target, state)
    }
    root.restoringEditorState = true
    root.restoreSelectionFromEditorState(state, source.length)
    root.restoringEditorState = false
    root.pendingEditorStateRestorePath = target
    root.pendingEditorStateScrollY = root.rawMode
      ? state.rawScrollY : state.liveScrollY
    Qt.callLater(root.finishPendingEditorStateRestore)
    return true
  }

  function persistedFileEditorStates() {
    var files = []
    var paths = root.persistedOpenFilePaths()
    for (var index = 0; index < paths.length; index++) {
      var state = root.fileEditorStateForPath(paths[index])
      files.push(state)
    }
    return files
  }

  function loadEditorStates(rawValue) {
    if (root.editorStatesLoaded) return
    var states = ({})
    root.editorStatesHydrating = true
    try {
      var parsed = JSON.parse(String(rawValue || ""))
      var files = parsed && Array.isArray(parsed.files) ? parsed.files : []
      for (var index = 0; index < files.length; index++) {
        var path = root.normalizedFilePath(files[index].path)
        if (path === "" || states[path] !== undefined) continue
        states[path] = root.normalizedFileEditorState(path, files[index])
      }
    } catch (error) {
      states = ({})
    }
    root.fileEditorStates = states
    root.editorStatesHydrating = false
    root.editorStatesLoaded = true
    root.editorHistoryRevision++
    if (!root.loadingFromFile && root.noteLoadedPath === root.notePath)
      root.restoreEditorStateForSource(root.notePath, editor.text)
  }

  function scheduleEditorStatesWrite() {
    root.editorStatesWritePending = true
    if (!root.editorStatesLoaded || root.editorStatesHydrating) return
    if (!root.presentationSettingsDirectoryReady) {
      root.ensurePresentationSettingsDirectory()
      return
    }
    root.writeEditorStates()
  }

  function writeEditorStates() {
    if (!root.editorStatesLoaded || !root.editorStatesWritePending ||
        root.editorStatesWriteInFlight) return
    if (!root.presentationSettingsDirectoryReady) {
      root.ensurePresentationSettingsDirectory()
      return
    }
    var desired = JSON.stringify({
      version: 1,
      files: root.persistedFileEditorStates()
    }, null, 2) + "\n"
    if (String(editorStatesFile.text() || "") === desired) {
      root.editorStatesWritePending = false
      return
    }
    root.editorStatesWritePending = false
    root.editorStatesWriteInFlight = true
    editorStatesFile.setText(desired)
  }

  function recentFilePathsFromValue(value) {
    var paths = []
    if (!Array.isArray(value)) return paths
    for (var index = 0; index < value.length; index++) {
      var item = value[index]
      var rawPath = typeof item === "string"
        ? item
        : (item && typeof item.path === "string" ? item.path : "")
      var path = root.normalizedFilePath(rawPath)
      if (path !== "" && paths.indexOf(path) < 0) paths.push(path)
      if (paths.length >= root.recentFilesLimit) break
    }
    return paths
  }

  function mergedRecentFilePaths(primary, secondary) {
    var paths = []
    var values = [primary, secondary]
    for (var group = 0; group < values.length; group++) {
      var normalized = root.recentFilePathsFromValue(values[group])
      for (var index = 0; index < normalized.length; index++) {
        if (paths.indexOf(normalized[index]) < 0) paths.push(normalized[index])
        if (paths.length >= root.recentFilesLimit) return paths
      }
    }
    return paths
  }

  function registerRecentFile(path) {
    var nextPath = root.normalizedFilePath(path)
    if (nextPath === "") return false
    var next = [nextPath]
    for (var index = 0; index < root.recentFiles.length; index++) {
      var existing = root.normalizedFilePath(root.recentFiles[index])
      if (existing !== "" && existing !== nextPath &&
          next.indexOf(existing) < 0) next.push(existing)
      if (next.length >= root.recentFilesLimit) break
    }
    if (JSON.stringify(next) === JSON.stringify(root.recentFiles)) return true
    root.recentFiles = next
    if (!root.presentationSettingsLoaded)
      root.recentFilesMutatedBeforeSettingsLoaded = true
    root.schedulePersistedSettingsSave()
    return true
  }

  function forgetRecentFile(path) {
    var target = root.normalizedFilePath(path)
    if (target === "") return false
    var next = []
    for (var index = 0; index < root.recentFiles.length; index++) {
      var existing = root.normalizedFilePath(root.recentFiles[index])
      if (existing !== "" && existing !== target && next.indexOf(existing) < 0)
        next.push(existing)
    }
    if (next.length === root.recentFiles.length) return false
    root.recentFiles = next
    if (!root.presentationSettingsLoaded)
      root.recentFilesMutatedBeforeSettingsLoaded = true
    root.schedulePersistedSettingsSave()
    return true
  }

  function replaceRecentFilePath(oldPath, newPath) {
    var oldTarget = root.normalizedFilePath(oldPath)
    var nextTarget = root.normalizedFilePath(newPath)
    if (nextTarget === "") return false
    var hadOldPath = root.recentFiles.indexOf(oldTarget) >= 0
    if (!hadOldPath) return false
    var next = [nextTarget]
    for (var index = 0; index < root.recentFiles.length; index++) {
      var existing = root.recentFiles[index]
      if (existing !== oldTarget && existing !== nextTarget)
        next.push(existing)
      if (next.length >= root.recentFilesLimit) break
    }
    root.recentFiles = next
    if (!root.presentationSettingsLoaded)
      root.recentFilesMutatedBeforeSettingsLoaded = true
    root.schedulePersistedSettingsSave()
    return true
  }

  function clearRecentFiles() {
    root.closeFileMenu()
    root.cancelMostRecentOpen()
    root.recentFiles = []
    root.recentFileValidationQueue = []
    root.pendingRecentPromotionPath = ""
    if (!root.presentationSettingsLoaded) {
      root.recentFilesMutatedBeforeSettingsLoaded = true
      root.recentFilesClearedBeforeSettingsLoaded = true
    }
    root.schedulePersistedSettingsSave()
    return true
  }

  function startNextRecentFileValidation() {
    if (recentFileValidationProcess.running ||
        root.recentFileValidationPath !== "" ||
        root.recentFileValidationQueue.length === 0) return
    var queue = root.recentFileValidationQueue.slice()
    var nextPath = queue.shift()
    root.recentFileValidationQueue = queue
    root.recentFileValidationPath = nextPath
    recentFileValidationProcess.command = ["test", "-f", nextPath]
    recentFileValidationProcess.running = true
  }

  function validateRecentFiles() {
    if (recentFileValidationProcess.running ||
        root.recentFileValidationPath !== "") return false
    root.recentFileValidationQueue = root.recentFiles.slice()
    root.startNextRecentFileValidation()
    return true
  }

  function openRecentFile(path) {
    var target = root.normalizedFilePath(path)
    root.closeFileMenu()
    if (target === "") return false
    root.cancelMostRecentOpen()
    root.openFileSelected(target)
    return root.openingFile && root.openingPath === target
  }

  function openMostRecentFile() {
    if (root.recentFiles.length === 0) {
      root.statusText = "No recent files"
      return false
    }
    if (root.openingFile || root.openingMostRecent) {
      root.statusText = "Finish opening the current file first"
      return false
    }
    root.closeFileMenu()
    root.openingMostRecent = true
    root.recentOpenFallbackQueue = root.recentFiles.slice()
    root.recentOpenCandidatePath = ""
    return root.tryNextMostRecentFile()
  }

  function tryNextMostRecentFile() {
    if (!root.openingMostRecent) return false
    if (root.openingFile || root.loadingFromFile) return true
    if (root.recentOpenFallbackQueue.length === 0) {
      root.cancelMostRecentOpen()
      root.statusText = "No usable recent files"
      return false
    }
    var queue = root.recentOpenFallbackQueue.slice()
    var target = root.normalizedFilePath(queue.shift())
    root.recentOpenFallbackQueue = queue
    if (target === "") {
      Qt.callLater(root.tryNextMostRecentFile)
      return true
    }
    root.recentOpenCandidatePath = target
    root.openFileSelected(target)
    if (!root.openingFile)
      Qt.callLater(root.tryNextMostRecentFile)
    return true
  }

  function continueMostRecentAfterFailure(path) {
    if (!root.openingMostRecent ||
        root.recentOpenCandidatePath !== root.normalizedFilePath(path)) return
    root.recentOpenCandidatePath = ""
    Qt.callLater(root.tryNextMostRecentFile)
  }

  function finishMostRecentOpen(path) {
    if (!root.openingMostRecent ||
        root.recentOpenCandidatePath !== root.normalizedFilePath(path)) return
    root.cancelMostRecentOpen()
  }

  function cancelMostRecentOpen() {
    root.openingMostRecent = false
    root.recentOpenFallbackQueue = []
    root.recentOpenCandidatePath = ""
  }

  function recentFilesState() {
    return JSON.stringify({
      files: root.recentFiles,
      validationRunning: recentFileValidationProcess.running ||
        root.recentFileValidationPath !== "" ||
        root.recentFileValidationQueue.length > 0,
      openingMostRecent: root.openingMostRecent,
      settingsLoaded: root.presentationSettingsLoaded,
      settingsWritePending: root.presentationSettingsWritePending,
      settingsWriteInFlight: root.presentationSettingsWriteInFlight,
      fileMenuOpen: fileMenuPopup.opened
    })
  }

  function persistedGeneratedUntitledPaths() {
    var openPaths = root.persistedOpenFilePaths()
    var generated = []
    for (var index = 0; index < root.generatedUntitledPaths.length; index++) {
      var path = root.normalizedFilePath(root.generatedUntitledPaths[index])
      if (path !== "" && openPaths.indexOf(path) >= 0 &&
          generated.indexOf(path) < 0) generated.push(path)
    }
    return generated
  }

  function generatedUntitledPathsFromValue(value) {
    var generated = []
    if (!Array.isArray(value)) return generated
    for (var index = 0; index < value.length; index++) {
      var path = root.normalizedFilePath(value[index])
      if (path !== "" && /^untitled-[A-Za-z0-9]{6}\.md$/i.test(
          root.fileNameForPath(path)) && generated.indexOf(path) < 0) {
        generated.push(path)
      }
    }
    return generated
  }

  function registerGeneratedUntitledPath(path) {
    var nextPath = root.normalizedFilePath(path)
    if (nextPath === "" || root.generatedUntitledPaths.indexOf(nextPath) >= 0)
      return
    var generated = root.generatedUntitledPaths.slice()
    generated.push(nextPath)
    root.generatedUntitledPaths = generated
    root.schedulePersistedSettingsSave()
  }

  function forgetGeneratedUntitledPath(path) {
    var target = root.normalizedFilePath(path)
    var generated = root.generatedUntitledPaths.slice()
    var index = generated.indexOf(target)
    if (index < 0) return
    generated.splice(index, 1)
    root.generatedUntitledPaths = generated
    root.schedulePersistedSettingsSave()
  }

  function openFileEntriesFromValue(value) {
    var entries = []
    if (!Array.isArray(value)) return entries

    for (var index = 0; index < value.length; index++) {
      var item = value[index]
      var rawPath = typeof item === "string"
        ? item
        : (item && typeof item.path === "string" ? item.path : "")
      var path = root.normalizedFilePath(rawPath)
      if (path === "") continue

      var exists = false
      for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        if (entries[entryIndex].path === path) {
          exists = true
          break
        }
      }
      if (!exists) entries.push({
        path: path,
        name: root.fileNameForPath(path)
      })
    }
    return entries
  }

  function restoreFileSession(storedOpenFiles, storedNotePath) {
    var restored = root.openFileEntriesFromValue(storedOpenFiles)
    var activePath = root.normalizedFilePath(root.pendingSessionPath)
    if (activePath === "") activePath = root.normalizedFilePath(storedNotePath)
    if (activePath === "" && restored.length > 0)
      activePath = restored[0].path
    if (activePath === "") activePath = root.normalizedFilePath(root.notePath)
    if (activePath === "") activePath = root.normalizedFilePath(root.defaultNotePath)

    var activeIncluded = false
    for (var index = 0; index < restored.length; index++) {
      if (restored[index].path === activePath) {
        activeIncluded = true
        break
      }
    }
    if (!activeIncluded) restored.push({
      path: activePath,
      name: root.fileNameForPath(activePath)
    })
    root.openFiles = restored
    root.pendingSessionPath = ""

    if (activePath !== root.notePath) {
      root.resetRecoveryLoadState()
      root.notePath = activePath
      root.loadingFromFile = true
      root.noteMissing = false
      root.directoryReady = false
      root.pendingSave = false
      root.dirty = false
      root.statusText = "Loading…"
    }
  }

  function armNoteLoadWatchdog(pathValue, resetAttempts) {
    var target = root.normalizedFilePath(pathValue)
    if (!root.loadingFromFile || !root.presentationSettingsLoaded ||
        target === "") {
      noteLoadWatchdog.stop()
      return false
    }
    if (resetAttempts || root.noteLoadWatchdogPath !== target)
      root.noteLoadRetryCount = 0
    root.noteLoadWatchdogPath = target
    noteLoadWatchdog.interval = Math.max(250,
      Number(root.noteLoadWatchdogIntervalMs) || 3000)
    noteLoadWatchdog.restart()
    return true
  }

  function clearNoteLoadWatchdog() {
    noteLoadWatchdog.stop()
    root.noteLoadWatchdogPath = ""
    root.noteLoadRetryCount = 0
  }

  function handleNoteLoadWatchdog() {
    var target = root.noteLoadWatchdogPath
    if (!root.loadingFromFile || target === "" ||
        target !== root.notePath || !root.presentationSettingsLoaded) {
      root.clearNoteLoadWatchdog()
      return false
    }
    if (root.noteLoadRetryCount < root.noteLoadMaxRetries) {
      root.noteLoadRetryCount++
      root.statusText = "Retrying note load…"
      noteFile.reload()
      noteLoadWatchdog.restart()
      return true
    }

    // A dropped Quickshell FileView operation may emit neither Loaded nor
    // LoadFailed. Never leave the entire tab bar locked behind Loading note.
    noteLoadWatchdog.stop()
    root.loadingFromFile = false
    root.noteMissing = false
    root.noteLoadError = "stalled"
    root.statusText = "Note load stalled — retry or choose another note"
    root.maybeContinuePendingSwitch()
    return false
  }

  function retryNoteLoad() {
    if (root.loadingFromFile || root.notePath === "") return false
    root.noteLoadError = ""
    root.noteMissing = false
    root.noteLoadedPath = ""
    root.statusText = "Loading…"
    root.loadingFromFile = true
    noteFile.reload()
    return true
  }

  function noteLoadStateForTests() {
    return JSON.stringify({
      settingsLoaded: root.presentationSettingsLoaded,
      notePath: root.notePath,
      fileViewPath: String(noteFile.path || ""),
      loading: root.loadingFromFile,
      error: root.noteLoadError,
      watchdogPath: root.noteLoadWatchdogPath,
      retryCount: root.noteLoadRetryCount
    })
  }

  function loadPresentationSettings(rawValue) {
    if (root.presentationSettingsLoaded) return

    var storedMode = ""
    var storedOpenFiles = []
    var storedNotePath = ""
    var storedNotesDirectory = ""
    var storedSidePlacement = ""
    var storedFileTabRows = 0
    var storedEditorTextScale = 100
    var storedSettingsVersion = 0
    var storedSettingsParsed = false
    var storedShortcuts = null
    var storedRecentFiles = []
    var storedGeneratedUntitledPaths = []
    var storedSpellcheckEnabled = true
    try {
      var parsed = JSON.parse(String(rawValue || ""))
      if (parsed) {
        storedSettingsParsed = true
        storedSettingsVersion = Number(parsed.version)
        if (!isFinite(storedSettingsVersion)) storedSettingsVersion = 0
        storedMode = root.normalizedPresentationMode(
          parsed.mode !== undefined ? parsed.mode : parsed.presentationMode)
        storedOpenFiles = parsed.openFiles
        storedNotePath = parsed.notePath !== undefined
          ? parsed.notePath
          : parsed.activePath
        storedNotesDirectory = root.normalizedDirectoryPath(
          parsed.notesDirectory !== undefined
            ? parsed.notesDirectory : parsed.defaultNotesDirectory)
        storedSidePlacement = root.normalizedSidePlacement(
          parsed.sidePlacement !== undefined ? parsed.sidePlacement :
            parsed.side)
        if (parsed.fileTabRows !== undefined)
          storedFileTabRows = root.normalizedFileTabRows(parsed.fileTabRows)
        if (typeof parsed.editorTextScale === "number" && isFinite(parsed.editorTextScale))
          storedEditorTextScale = Math.max(75, Math.min(200, Math.round(parsed.editorTextScale)))
        storedShortcuts = root.migratedShortcutSettings(
          storedSettingsVersion, parsed.shortcuts)
        storedRecentFiles = root.recentFilePathsFromValue(parsed.recentFiles)
        storedGeneratedUntitledPaths =
          root.generatedUntitledPathsFromValue(parsed.generatedUntitledPaths)
        if (parsed.spellcheck && parsed.spellcheck.enabled !== undefined)
          storedSpellcheckEnabled = storedSettingsVersion < 10
            ? true : Boolean(parsed.spellcheck.enabled)
      }
    } catch (error) {
      // An absent or malformed preference falls back to the side drawer.
    }

    var hadPendingMode = root.pendingPresentationMode !== ""
    var hadPendingSidePlacement = root.pendingSidePlacement !== ""
    var hadPendingSessionPath = root.pendingSessionPath !== ""
    var hadPendingNotesDirectory = root.pendingNotesDirectory !== ""
    var hadPendingFileTabRows = root.pendingFileTabRows > 0
    var hadPendingEditorTextScale = root.pendingEditorTextScale > 0
    var hadPendingShortcuts = Object.keys(root.pendingShortcuts).length > 0
    var hadPendingRecentFiles = root.recentFilesMutatedBeforeSettingsLoaded
    var hadPendingSpellcheck = root.pendingSpellcheckEnabled >= 0
    var hadPendingSettingsWrite = root.presentationSettingsWritePending
    var settingsMigrationNeeded = storedSettingsParsed &&
      storedSettingsVersion < root.presentationSettingsVersion
    root.presentationSettingsHydrating = true
    if (root.pendingPresentationMode !== "")
      root.presentationMode = root.pendingPresentationMode
    else if (storedMode !== "") root.presentationMode = storedMode
    if (root.pendingNotesDirectory !== "")
      root.defaultNotesDirectory = root.pendingNotesDirectory
    else if (storedNotesDirectory !== "")
      root.defaultNotesDirectory = storedNotesDirectory
    if (root.pendingSidePlacement !== "")
      root.sidePlacement = root.pendingSidePlacement
    else if (storedSidePlacement !== "")
      root.sidePlacement = storedSidePlacement
    root.editorTextScale = root.pendingEditorTextScale > 0
      ? root.pendingEditorTextScale : storedEditorTextScale
    if (root.pendingFileTabRows > 0)
      root.fileTabRows = root.normalizedFileTabRows(root.pendingFileTabRows)
    else if (storedFileTabRows > 0)
      root.fileTabRows = storedFileTabRows
    root.hydrateShortcuts(storedShortcuts)
    root.spellcheckEnabled = hadPendingSpellcheck
      ? root.pendingSpellcheckEnabled === 1 : storedSpellcheckEnabled
    var pendingShortcutIds = root.shortcutIds()
    for (var pendingIndex = 0; pendingIndex < pendingShortcutIds.length;
         pendingIndex++) {
      var pendingId = pendingShortcutIds[pendingIndex]
      if (root.pendingShortcuts[pendingId] !== undefined)
        root.assignShortcutValue(pendingId, root.pendingShortcuts[pendingId])
    }
    root.recentFiles = root.mergedRecentFilePaths(
      root.recentFiles,
      root.recentFilesClearedBeforeSettingsLoaded ? [] : storedRecentFiles)
    root.restoreFileSession(storedOpenFiles, storedNotePath)
    var restoredPaths = root.persistedOpenFilePaths()
    var restoredGenerated = []
    for (var generatedIndex = 0;
         generatedIndex < storedGeneratedUntitledPaths.length;
         generatedIndex++) {
      if (restoredPaths.indexOf(storedGeneratedUntitledPaths[generatedIndex]) >= 0)
        restoredGenerated.push(storedGeneratedUntitledPaths[generatedIndex])
    }
    root.generatedUntitledPaths = restoredGenerated
    root.presentationSettingsHydrating = false

    root.pendingPresentationMode = ""
    root.pendingSidePlacement = ""
    root.pendingFileTabRows = 0
    root.pendingEditorTextScale = 0
    root.pendingNotesDirectory = ""
    root.pendingShortcuts = ({})
    root.pendingSpellcheckEnabled = -1
    root.recentFilesMutatedBeforeSettingsLoaded = false
    root.recentFilesClearedBeforeSettingsLoaded = false
    root.settingsDefaultNotesDirectory = root.defaultNotesDirectory
    root.presentationSettingsLoaded = true
    if (root.spellcheckEnabled) {
      if (root.personalDictionaryLoaded && !root.spellcheckReady)
        root.initializeSpellcheck()
    } else {
      root.spellcheckInitializationPending = false
      root.spellcheckReady = false
      spellcheckTimer.stop()
      root.clearSpellingVisualState()
      root.clearSpellcheckCandidateState()
    }
    if (hadPendingMode || hadPendingSidePlacement || hadPendingSessionPath ||
        hadPendingNotesDirectory || hadPendingFileTabRows || hadPendingEditorTextScale ||
        hadPendingShortcuts || hadPendingRecentFiles || hadPendingSpellcheck ||
        hadPendingSettingsWrite || settingsMigrationNeeded) {
      root.presentationSettingsWritePending = true
      Qt.callLater(function() { root.writePresentationSettings() })
    } else root.presentationSettingsWritePending = false
    root.validateRecentFiles()
  }

  function ensurePresentationSettingsDirectory() {
    if (root.presentationSettingsDirectoryReady ||
        presentationSettingsDirectoryProcess.running) return
    presentationSettingsDirectoryProcess.command = [
      "mkdir", "-p", root.stateDirectory
    ]
    presentationSettingsDirectoryProcess.running = true
  }

  function schedulePersistedSettingsSave() {
    if (root.presentationSettingsHydrating) return
    root.presentationSettingsWritePending = true
    if (!root.presentationSettingsLoaded) return
    root.ensurePresentationSettingsDirectory()
    root.writePresentationSettings()
  }

  function schedulePresentationModeSave() {
    root.schedulePersistedSettingsSave()
  }

  function writePresentationSettings() {
    if (!root.presentationSettingsLoaded ||
        !root.presentationSettingsWritePending) return
    if (root.presentationSettingsWriteInFlight) return
    if (!root.presentationSettingsDirectoryReady) {
      root.ensurePresentationSettingsDirectory()
      return
    }

    var currentSettingsText = String(presentationSettingsFile.text() || "")
    var desiredSettingsText = JSON.stringify({
      version: root.presentationSettingsVersion,
      mode: root.presentationMode,
      sidePlacement: root.sidePlacement,
      fileTabRows: root.fileTabRows,
      editorTextScale: root.editorTextScale,
      notesDirectory: root.defaultNotesDirectory,
      notePath: root.notePath,
      openFiles: root.persistedOpenFilePaths(),
      recentFiles: root.recentFiles,
      generatedUntitledPaths: root.persistedGeneratedUntitledPaths(),
      spellcheck: {
        enabled: root.spellcheckEnabled,
        language: root.spellcheckLanguage
      },
      shortcuts: {
        save: root.shortcutSave,
        saveAs: root.shortcutSaveAs,
        open: root.shortcutOpen,
        openRecent: root.shortcutOpenRecent,
        clearRecent: root.shortcutClearRecent,
        new: root.shortcutNew,
        preview: root.shortcutPreview,
        fileMenu: root.shortcutFileMenu,
        presentation: root.shortcutPresentation,
        maximize: root.shortcutMaximize,
        settings: root.shortcutSettings,
        help: root.shortcutHelp,
        nextFile: root.shortcutNextFile,
        previousFile: root.shortcutPreviousFile,
        closeFile: root.shortcutCloseFile,
        renameFile: root.shortcutRenameFile,
        toggleTask: root.shortcutToggleTask,
        find: root.shortcutFind,
        replace: root.shortcutReplace,
        goToLine: root.shortcutGoToLine,
        findNext: root.shortcutFindNext,
        findPrevious: root.shortcutFindPrevious,
        contextMenu: root.shortcutContextMenu,
        close: root.shortcutClose
      }
    }, null, 2) + "\n"
    if (currentSettingsText === desiredSettingsText) {
      root.presentationSettingsWritePending = false
      root.presentationSettingsWriteInFlight = false
      return
    }

    root.presentationSettingsWritePending = false
    root.presentationSettingsWriteInFlight = true
    presentationSettingsFile.setText(desiredSettingsText)
  }

  function caretState() {
    var source = String(editor.text || "")
    var position = Number(editor.cursorPosition)
    var sourceLine = source.slice(0,
      Math.max(0, Math.min(position, source.length))).split("\n").length - 1
    var target = renderedEditor.cursorTargetForSource(position)
    var renderedRect = renderedEditor.cursorRectangleForSource(position)
    var followingRect =
      renderedEditor.followingCursorRectangleForSource(position)
    return JSON.stringify({
      cursorPosition: position,
      sourceLength: source.length,
      sourceLine: sourceLine,
      liveCursorVisible: Boolean(root.liveCursorVisible),
      liveCursorSourcePosition: Number(root.liveCursorSourcePosition),
      liveCursorX: Number(root.liveCursorRect.x),
      liveCursorY: Number(root.liveCursorRect.y),
      liveCursorHeight: Number(root.liveCursorRect.height),
      renderedCursorX: renderedRect ? Number(renderedRect.x) : -1,
      renderedCursorY: renderedRect ? Number(renderedRect.y) : -1,
      nativeCursorX: Number(editor.cursorRectangle.x),
      nativeCursorY: Number(editor.cursorRectangle.y),
      placeholderVisible: Boolean(editorPlaceholder.visible),
      placeholderX: Number(editorPlaceholder.x - renderedEditor.x),
      placeholderY: Number(editorPlaceholder.y - renderedEditor.y),
      followingCursorY: followingRect ? Number(followingRect.y) : -1,
      nativeCursorHeight: Number(editor.cursorRectangle.height),
      layoutMetrics: renderedEditor.layoutMetricsForTests(),
      targetBlockType: String(target.blockType || "none"),
      targetItemIndex: Number(target.itemIndex),
      layoutReady: Boolean(renderedEditor.layoutReady),
      layoutSourceMatches: renderedEditor.layoutSourceText === String(editor.text || ""),
      layoutCursorMatches:
        Number(renderedEditor.layoutCursorPosition) === Number(editor.cursorPosition),
      codePaintState: String(renderedEditor.codePaintState || "none"),
      codeFallbackPaintCount: Number(renderedEditor.codeFallbackPaintCount),
      codeHighlightedPaintCount:
        Number(renderedEditor.codeHighlightedPaintCount),
      codeHighlightPendingCount:
        Number(renderedEditor.codeHighlightPendingCount)
    })
  }

  function shortcutHelpLayoutState() {
    var rows = shortcutHelpRepeater.count
    var separated = rows === root.shortcutHelpEntries.length
    var maximumOverflow = 0
    for (var index = 0; index < rows; index++) {
      var row = shortcutHelpRepeater.itemAt(index)
      if (!row) {
        separated = false
        continue
      }
      maximumOverflow = Math.max(maximumOverflow,
        Number(row.keyPaintedOverflow), Number(row.actionPaintedOverflow))
      if (!row.labelsSeparated) separated = false
    }
    return JSON.stringify({
      rows: rows,
      separated: separated,
      maximumOverflow: maximumOverflow
    })
  }

  function footerShortcutState() {
    return JSON.stringify({
      presentationMode: root.presentationMode,
      footerHeight: Number(footer.height),
      shortcutRowVisible: Boolean(footerShortcutRow.visible),
      shortcutHintVisible: Boolean(shortcutHint.visible),
      shortcutButtonVisible: Boolean(shortcutMoreButton.visible),
      shortcutHint: String(shortcutHint.text || "")
    })
  }

  function tableHelperStateForTests() {
    return JSON.stringify({
      visible: Boolean(tableHelperBar.visible),
      width: Number(tableHelperBar.width),
      height: Number(tableHelperBar.height),
      documentAnchored: tableHelperBar.parent === editorViewport.contentItem,
      documentY: Number(tableHelperBar.y),
      documentX: Number(tableHelperBar.x),
      viewportY: Number(tableHelperBar.mapToItem(
        editorViewport, 0, 0).y),
      tableTopY: Number(tableHelperBar.tableTopY),
      slotY: tableHelperBar.tableSlotGeometry
        ? Number(tableHelperBar.tableSlotGeometry.y) : -1,
      slotX: tableHelperBar.tableSlotGeometry
        ? Number(tableHelperBar.tableSlotGeometry.x) : -1,
      slotHeight: tableHelperBar.tableSlotGeometry
        ? Number(tableHelperBar.tableSlotGeometry.height) : -1,
      slotBacked: Boolean(tableHelperBar.tableSlotGeometry) &&
        Number(tableHelperBar.y) + 0.5 >=
          Number(tableHelperBar.tableSlotGeometry.y) &&
        Number(tableHelperBar.y) + Number(tableHelperBar.height) <=
          Number(tableHelperBar.tableSlotGeometry.y) +
            Number(tableHelperBar.tableSlotGeometry.height) + 0.5,
      leftAligned: Boolean(tableHelperBar.tableSlotGeometry) &&
        Math.abs(Number(tableHelperBar.x) -
          Number(tableHelperBar.tableSlotGeometry.x)) <= 0.5,
      previousContentBottom: Number(tableHelperBar.previousContentBottom),
      contentClearance: Number(tableHelperBar.y) -
        Number(tableHelperBar.previousContentBottom),
      gapBelow: Number(tableHelperBar.tableTopY) -
        (Number(tableHelperBar.y) + Number(tableHelperBar.height)),
      requiredTableGap: Number(tableHelperBar.baseTableGap),
      rendererReady: Boolean(renderedEditor.layoutReady),
      rendererMatches: Boolean(renderedEditor.layoutMatchesCurrentInput()),
      rendererLayoutRevision: Number(renderedEditor.layoutRevision),
      rendererToolbarStart: Number(renderedEditor.tableToolbarSourceStart),
      rendererToolbarGap: Number(renderedEditor.tableToolbarGap),
      rendererTableOrdinal: Number(renderedEditor.tableOrdinalForSourceStart(
        Number(root.activeTableToolbarState.tableStart))),
      contentFits: Boolean(tableHelperBar.contentFitsForTests()),
      rowIndex: Number(root.activeTableToolbarState.rowIndex),
      columnIndex: Number(root.activeTableToolbarState.columnIndex),
      canDeleteRow: Boolean(deleteTableRowButton.enabled),
      canDeleteColumn: Boolean(deleteTableColumnButton.enabled),
      repairVisible: Boolean(repairTableButton.visible),
      repairEnabled: Boolean(repairTableButton.enabled)
    })
  }

  function editorBehaviorState() {
    return JSON.stringify({
      text: String(editor.text || ""),
      cursorPosition: Number(editor.cursorPosition),
      selectionStart: Number(editor.selectionStart),
      selectionEnd: Number(editor.selectionEnd),
      canUndo: Boolean(root.editorCanUndo),
      canRedo: Boolean(root.editorCanRedo)
    })
  }

  function editorTabStateForTests(pathValue) {
    var path = root.normalizedFilePath(pathValue || root.notePath)
    if (path === root.notePath && !root.loadingFromFile)
      root.captureActiveEditorState(false)
    var state = root.fileEditorStateForPath(path)
    return JSON.stringify({
      path: path,
      active: path === root.notePath,
      cursorPosition: state.cursorPosition,
      selectionStart: state.selectionStart,
      selectionEnd: state.selectionEnd,
      liveScrollY: state.liveScrollY,
      rawScrollY: state.rawScrollY,
      contentY: path === root.notePath ? Number(editorViewport.contentY) : -1,
      maximumContentY: path === root.notePath
        ? Math.max(0, editorViewport.contentHeight - editorViewport.height)
        : -1,
      pastCount: state.past.length,
      futureCount: state.future.length,
      canUndo: path === root.notePath && root.editorCanUndo,
      canRedo: path === root.notePath && root.editorCanRedo,
      rawMode: root.rawMode,
      viewCaretAlignmentPending: root.viewCaretAlignmentPending,
      statesLoaded: root.editorStatesLoaded,
      writePending: root.editorStatesWritePending,
      writeInFlight: root.editorStatesWriteInFlight
    })
  }

  function renderedDocumentStateForTests() {
    return JSON.stringify({
      editorText: String(editor.text || ""),
      documentPlainText: String(renderedEditor.documentPlainText || ""),
      documentSourceText: String(renderedEditor.documentSourceText || ""),
      layoutSourceText: String(renderedEditor.layoutSourceText || ""),
      layoutReady: Boolean(renderedEditor.layoutReady),
      layoutMatches: Boolean(renderedEditor.layoutMatchesCurrentInput()),
      initialLayoutReady: renderedEditor.initialLayoutReady,
      imagesReady: renderedEditor.imagesReady,
      startupContentRevealed: root.startupContentRevealed,
      pendingRestore: root.pendingEditorStateRestorePath,
      pendingHighlights: renderedEditor.codeHighlightPendingCount,
      highlightDispatchPending: renderedEditor.codeHighlightDispatchPending,
      parsePending: Boolean(renderedEditor.parsePending),
      parseInFlight: Boolean(renderedEditor.parseInFlight)
    })
  }

  function setEditorScrollForTests(value) {
    var maximumContentY = Math.max(0,
      editorViewport.contentHeight - editorViewport.height)
    editorViewport.contentY = Math.max(0, Math.min(
      maximumContentY, Number(value) || 0))
    root.captureActiveEditorState()
    return Number(editorViewport.contentY)
  }

  function undoEditorForTests() {
    return root.applyEditorHistory("undo")
  }

  function redoEditorForTests() {
    return root.applyEditorHistory("redo")
  }

  function selectEditorRange(start, end) {
    editor.select(
      Math.max(0, Math.min(Number(start) || 0, editor.length)),
      Math.max(0, Math.min(Number(end) || 0, editor.length)))
  }

  function editorItemForTests() {
    return editor
  }

  function recoverNativeListReturn(sourceBefore, sourceAfter,
      beforeCursor, beforeSelectionStart, beforeSelectionEnd) {
    if (!root.historyInputStateValid || root.rawMode ||
        (root.historyInputKey !== Qt.Key_Return &&
          root.historyInputKey !== Qt.Key_Enter) ||
        (root.historyInputModifiers & (Qt.ShiftModifier |
          Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return false

    var plain = EditorModel.plainReturn(sourceBefore, beforeCursor,
      beforeSelectionStart, beforeSelectionEnd)
    if (!plain.handled || String(plain.source || "") !== sourceAfter)
      return false
    var list = EditorModel.listReturn(sourceBefore, beforeCursor,
      beforeSelectionStart, beforeSelectionEnd, true)
    if (!list.handled || String(list.source || "") === sourceAfter)
      return false

    root.editorAutoFormatting = true
    root.replaceEditorDocumentText(list.source, list.cursor)
    root.editorAutoFormatting = false
    return true
  }

  function normalizeLiveReturnCursor() {
    if (root.rawMode || editor.selectionStart !== editor.selectionEnd ||
        !renderedEditor.layoutMatchesCurrentInput()) return false

    var visiblePosition = Number(root.liveCursorSourcePosition)
    var nativePosition = Number(editor.cursorPosition)
    var source = String(editor.text || "")
    var correctedPosition = EditorModel.liveReturnSourcePosition(
      source, nativePosition, visiblePosition, root.rawMode,
      editor.selectionStart, editor.selectionEnd)
    if (correctedPosition === nativePosition) return false

    // Qt may advance the hidden TextEdit across a visually collapsed blank
    // source row before the attached Return handler runs. Restore the source
    // position represented by the still-visible Preview caret so list
    // continuation acts where the user actually sees the insertion point.
    editor.cursorPosition = correctedPosition
    return true
  }

  function openEditorCommand(mode) {
    if (!root.opened || root.loadingFromFile || root.noteLoadError !== "")
      return false
    var nextMode = String(mode || "find")
    if (["find", "replace", "line"].indexOf(nextMode) < 0)
      nextMode = "find"
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.shortcutHelpOpen = false
    root.settingsOpen = false
    root.saveAsOpen = false
    root.editorCommandMode = nextMode
    root.editorCommandOpen = true
    root.editorCommandMessage = ""
    root.findAnchorPosition = editor.selectionStart !== editor.selectionEnd
      ? editor.selectionStart : editor.cursorPosition

    if ((nextMode === "find" || nextMode === "replace") &&
        editor.selectionStart !== editor.selectionEnd) {
      root.findQuery = String(editor.text || "").slice(
        editor.selectionStart, editor.selectionEnd)
    }

    Qt.callLater(function() {
      if (!root.editorCommandOpen) return
      if (root.editorCommandMode === "line") {
        goToLineField.forceActiveFocus()
        goToLineField.selectAll()
      } else if (root.editorCommandMode === "replace") {
        replaceQueryField.forceActiveFocus()
        replaceQueryField.selectAll()
      } else {
        findQueryField.forceActiveFocus()
        findQueryField.selectAll()
      }
      if ((root.editorCommandMode === "find" ||
          root.editorCommandMode === "replace") && root.findQuery !== "") {
        root.findInEditor(false, root.findAnchorPosition)
      }
    })
    return true
  }

  function closeEditorCommand() {
    root.editorCommandOpen = false
    root.editorCommandMessage = ""
    Qt.callLater(function() {
      if (root.opened && !root.settingsOpen && !root.saveAsOpen)
        editor.forceActiveFocus()
    })
  }

  function editorSelectionMatchesQuery() {
    var query = String(root.findQuery || "")
    if (query === "" || editor.selectionStart === editor.selectionEnd)
      return false
    var selected = String(editor.text || "").slice(
      editor.selectionStart, editor.selectionEnd)
    return root.findCaseSensitive
      ? selected === query
      : selected.toLocaleLowerCase() === query.toLocaleLowerCase()
  }

  function updateFindQuery(value) {
    root.findQuery = String(value || "")
    root.editorCommandMessage = ""
    if (root.findQuery === "") {
      root.findMatchIndex = 0
      root.findMatchCount = 0
      editor.cursorPosition = Math.max(0,
        Math.min(root.findAnchorPosition, editor.length))
      Qt.callLater(root.syncLiveCursor)
      return false
    }
    return root.findInEditor(false, root.findAnchorPosition)
  }

  function toggleFindCaseSensitive() {
    root.findCaseSensitive = !root.findCaseSensitive
    if (root.findQuery !== "")
      root.findInEditor(false, root.findAnchorPosition)
  }

  function selectFindMatch(match) {
    if (!match || !match.found) return false
    if (!root.editorCommandOpen) editor.forceActiveFocus()
    editor.select(match.start, match.end)
    root.findMatchIndex = Number(match.index) || 0
    root.findMatchCount = Number(match.count) || 0
    root.editorCommandMessage = match.wrapped ? "Wrapped" : ""
    Qt.callLater(function() {
      root.ensureEditorCursorVisible(true)
      root.syncLiveCursor()
    })
    return true
  }

  function findInEditor(backwards, fromOverride) {
    var query = String(root.findQuery || "")
    if (query === "") {
      root.findMatchIndex = 0
      root.findMatchCount = 0
      root.editorCommandMessage = "Enter text to find"
      return false
    }

    var from = Number(fromOverride)
    if (!isFinite(from)) {
      from = root.editorSelectionMatchesQuery()
        ? (backwards ? editor.selectionStart : editor.selectionEnd)
        : editor.cursorPosition
    }
    var match = EditorModel.findText(String(editor.text || ""), query,
      from, Boolean(backwards), root.findCaseSensitive)
    if (!match.found) {
      root.findMatchIndex = 0
      root.findMatchCount = 0
      root.editorCommandMessage = "No matches"
      return false
    }
    return root.selectFindMatch(match)
  }

  function replaceCurrentMatch() {
    var query = String(root.findQuery || "")
    if (query === "") {
      root.editorCommandMessage = "Enter text to find"
      return false
    }
    if (!root.editorSelectionMatchesQuery() && !root.findInEditor(false))
      return false

    var source = String(editor.text || "")
    var start = Number(editor.selectionStart)
    var end = Number(editor.selectionEnd)
    var replacement = String(root.replaceValue || "")
    var nextSource = source.slice(0, start) + replacement + source.slice(end)
    var nextCursor = start + replacement.length
    if (!root.replaceEditorText(nextSource, nextCursor)) return false
    root.noteEdited()
    if (!root.findInEditor(false, nextCursor)) {
      root.editorCommandMessage = "Replaced final match"
      editor.cursorPosition = nextCursor
      Qt.callLater(function() { root.ensureEditorCursorVisible(true) })
    }
    return true
  }

  function replaceAllMatches() {
    var result = EditorModel.replaceAllText(String(editor.text || ""),
      root.findQuery, root.replaceValue, root.findCaseSensitive)
    if (result.count <= 0) {
      root.editorCommandMessage = root.findQuery === ""
        ? "Enter text to find" : "No matches"
      return false
    }
    if (!root.replaceEditorText(result.source, result.cursor)) return false
    root.noteEdited()
    root.editorCommandMessage = "Replaced " + result.count +
      (result.count === 1 ? " match" : " matches")
    Qt.callLater(function() { root.ensureEditorCursorVisible(true) })
    return true
  }

  function goToSourceLine() {
    var result = EditorModel.linePosition(String(editor.text || ""),
      root.goToLineValue)
    if (!result.valid) {
      root.editorCommandMessage = "Enter a line number from 1 to " +
        result.lineCount
      return false
    }
    editor.cursorPosition = result.position
    root.editorCommandMessage = result.clamped
      ? "Moved to final line " + result.line
      : "Moved to line " + result.line
    Qt.callLater(function() {
      root.ensureEditorCursorVisible(true)
      root.syncLiveCursor()
    })
    return true
  }

  function editorCommandState() {
    return JSON.stringify({
      open: root.editorCommandOpen,
      mode: root.editorCommandMode,
      query: root.findQuery,
      replacement: root.replaceValue,
      anchorPosition: root.findAnchorPosition,
      matchIndex: root.findMatchIndex,
      matchCount: root.findMatchCount,
      message: root.editorCommandMessage,
      caseSensitive: root.findCaseSensitive,
      text: String(editor.text || ""),
      cursorPosition: Number(editor.cursorPosition),
      selectionStart: Number(editor.selectionStart),
      selectionEnd: Number(editor.selectionEnd),
      dirty: root.dirty,
      canUndo: Boolean(root.editorCanUndo),
      canRedo: Boolean(root.editorCanRedo),
      autoFencePending: Boolean(root.autoFencePending),
      autoCodePairCount: root.autoCodePairs.length,
      editorActiveFocus: Boolean(editor.activeFocus),
      commandInputActiveFocus: Boolean(root.editorCommandMode === "line"
        ? goToLineField.activeFocus
        : (root.editorCommandMode === "replace"
          ? replaceQueryField.activeFocus : findQueryField.activeFocus))
    })
  }

  function editorCommandAllowed() {
    return root.opened && !root.loadingFromFile &&
      !root.recoveryPromptOpen && !root.settingsOpen &&
      !root.saveAsOpen && editor.activeFocus
  }

  function undoEditor() {
    if (!root.editorCommandAllowed() || !root.editorCanUndo) return false
    if (!root.applyEditorHistory("undo")) return false
    Qt.callLater(root.syncLiveCursor)
    return true
  }

  function redoEditor() {
    if (!root.editorCommandAllowed() || !root.editorCanRedo) return false
    if (!root.applyEditorHistory("redo")) return false
    Qt.callLater(root.syncLiveCursor)
    return true
  }

  function handleEditorHistoryKey(event) {
    var control = Boolean(event.modifiers & Qt.ControlModifier)
    var altOrMeta = Boolean(event.modifiers &
      (Qt.AltModifier | Qt.MetaModifier))
    var shift = Boolean(event.modifiers & Qt.ShiftModifier)
    var undoKey = event.key === Qt.Key_Z && !shift
    var redoKey = (event.key === Qt.Key_Z && shift) ||
      (event.key === Qt.Key_Y && !shift)
    if (!control || altOrMeta || (!undoKey && !redoKey)) return false

    // QTextEdit consumes its native undo shortcuts before a sibling Shortcut
    // can reliably activate. The native stack is intentionally replaced when
    // a note loads, so intercept these keys on the focused editor itself and
    // route them to the persistent per-note transaction history.
    if (redoKey) root.redoEditor()
    else root.undoEditor()
    event.accepted = true
    return true
  }

  function editorFileNavigationOffset(event) {
    if (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right) return 0
    var sequenceParts = []
    if (event.modifiers & Qt.ControlModifier) sequenceParts.push("Ctrl")
    if (event.modifiers & Qt.AltModifier) sequenceParts.push("Alt")
    if (event.modifiers & Qt.ShiftModifier) sequenceParts.push("Shift")
    if (event.modifiers & Qt.MetaModifier) sequenceParts.push("Meta")
    sequenceParts.push(event.key === Qt.Key_Right ? "Right" : "Left")
    var sequence = sequenceParts.join("+")
    if (sequence === root.shortcutNextFile) return 1
    if (sequence === root.shortcutPreviousFile) return -1
    return 0
  }

  function handleEditorFileNavigationKey(event) {
    var offset = root.editorFileNavigationOffset(event)
    if (offset === 0 || !root.switchRelativeFile(offset)) return false

    // QTextEdit normally consumes Ctrl+Left/Right for word movement before a
    // sibling Shortcut can activate. Intercept configured arrow navigation at
    // the focused editor so note switching works while typing in either view.
    event.accepted = true
    return true
  }

  function handleIndent(direction) {
    if (root.loadingFromFile || root.recoveryPromptOpen ||
        root.noteLoadError !== "") return false
    var result = EditorModel.indentEdit(String(editor.text || ""),
      editor.selectionStart, editor.selectionEnd, direction, 4)
    if (!result.handled) return false
    if (result.changed) {
      root.replaceEditorText(result.source, result.cursor,
        root.autoFencePending, root.autoCodePairs.length > 0)
      if (result.selectionStart !== result.selectionEnd) {
        editor.select(result.selectionStart, result.selectionEnd)
      }
      root.noteEdited()
    }
    Qt.callLater(function() {
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function normalizedPersonalDictionaryWords(value) {
    var words = Array.isArray(value) ? value : []
    var unique = ({})
    var result = []
    for (var index = 0; index < words.length; index++) {
      var word = String(words[index] || "").trim()
      var key = word.toLowerCase()
      if (!word || unique[key]) continue
      unique[key] = true
      result.push(word)
    }
    result.sort(function(a, b) {
      return a.toLowerCase().localeCompare(b.toLowerCase())
    })
    return result
  }

  function loadPersonalDictionary(rawValue) {
    if (root.personalDictionaryLoaded) return
    var words = []
    try {
      var parsed = JSON.parse(String(rawValue || ""))
      if (parsed && Number(parsed.version) === 1) words = parsed.words
    } catch (_) {
      // A missing or malformed personal dictionary starts empty.
    }
    root.personalDictionaryWords = root.normalizedPersonalDictionaryWords(words)
    root.personalDictionaryLoaded = true
    if (root.spellcheckEnabled) root.initializeSpellcheck()
  }

  function initializeSpellcheck() {
    if (!root.spellcheckEnabled || !root.personalDictionaryLoaded) return
    root.spellcheckReady = false
    root.spellcheckInitializationPending = true
    root.flushSpellcheckInitialization()
  }

  function flushSpellcheckInitialization() {
    if (!root.spellcheckInitializationPending ||
        !spellcheckWorker.ready) return
    root.spellcheckInitializationPending = false
    spellcheckWorker.sendMessage({
      type: "init",
      personalWords: root.personalDictionaryWords
    })
  }

  function setSpellcheckEnabled(value) {
    var enabled = Boolean(value)
    var settingsPending = !root.presentationSettingsLoaded
    if (settingsPending) {
      root.pendingSpellcheckEnabled = enabled ? 1 : 0
      root.presentationSettingsWritePending = true
    }
    if (root.spellcheckEnabled === enabled) return settingsPending
    root.spellcheckEnabled = enabled
    root.spellcheckSourceRevision++
    root.spellcheckRequestId++
    root.spellcheckSuggestionRequestId++
    spellcheckTimer.stop()
    root.clearSpellingVisualState()
    root.clearSpellcheckCandidateState()
    root.spellcheckNeedsFullCheck = true
    root.spellcheckPendingEdits = []
    root.schedulePersistedSettingsSave()
    if (enabled) root.initializeSpellcheck()
    else {
      root.spellcheckInitializationPending = false
      root.spellcheckReady = false
      spellcheckTimer.stop()
    }
    return true
  }

  function clearSpellingVisualState() {
    root.spellingGeometryDeferred = false
    root.misspellings = []
    root.spellingContextRange = null
    root.spellingContextSuggestions = []
    root.spellingSuggestionsPending = false
    root.spellingUnderlineModel = []
    spellingUnderlineVisualModel.clear()
    spellingGeometryTimer.stop()
  }

  function clearSpellcheckCandidateState() {
    root.spellcheckHasCheckedCandidates = false
    root.spellcheckCheckedCandidates = []
    root.spellcheckPendingCandidates = []
  }

  function spellingLineStart(sourceValue, positionValue) {
    var source = String(sourceValue || "")
    var position = Math.max(0, Math.min(source.length,
      Number(positionValue) || 0))
    var newline = source.lastIndexOf("\n", Math.max(0, position - 1))
    return newline < 0 ? 0 : newline + 1
  }

  function spellingLineEnd(sourceValue, positionValue) {
    var source = String(sourceValue || "")
    var position = Math.max(0, Math.min(source.length,
      Number(positionValue) || 0))
    var newline = source.indexOf("\n", position)
    return newline < 0 ? source.length : newline + 1
  }

  function rebaseVisibleMisspellingsForEdit(previousSourceValue,
      nextSourceValue, editValue) {
    var previousSource = String(previousSourceValue || "")
    var nextSource = String(nextSourceValue || "")
    var edit = editValue || {}
    var start = Number(edit.start) || 0
    var oldEnd = Number(edit.oldEnd)
    if (!isFinite(oldEnd)) oldEnd = start
    var oldLineStart = root.spellingLineStart(previousSource, start)
    var oldLineEnd = root.spellingLineEnd(previousSource, oldEnd)
    var delta = nextSource.length - previousSource.length
    var retained = []
    for (var index = 0; index < root.misspellings.length; index++) {
      var range = root.misspellings[index] || {}
      var rangeStart = Number(range.start)
      var rangeEnd = Number(range.end)
      if (rangeEnd <= oldLineStart) {
        retained.push(range)
      } else if (rangeStart >= oldLineEnd) {
        retained.push({
          word: String(range.word || ""),
          checkWord: String(range.checkWord || range.word || ""),
          start: rangeStart + delta,
          end: rangeEnd + delta,
          candidateIndex: Number(range.candidateIndex) || 0
        })
      }
    }
    root.misspellings = retained
    // Keep the existing underline delegates stable during the edit burst.
    // The accepted worker result publishes authoritative geometry once.
    root.spellingGeometryDeferred =
      root.spellingUnderlineModel.length > 0
    if (root.spellingGeometryDeferred) spellingGeometryTimer.stop()
  }

  function queueSpellcheckEdit(previousSourceValue, nextSourceValue) {
    var previousSource = String(previousSourceValue || "")
    var nextSource = String(nextSourceValue || "")
    if (previousSource === nextSource) return
    var edit = SpellcheckModel.deriveSpellcheckEdit(
      previousSource, nextSource)
    if (!edit || !isFinite(Number(edit.start)) ||
        !isFinite(Number(edit.oldEnd))) {
      root.spellcheckNeedsFullCheck = true
      root.spellcheckPendingEdits = []
      return
    }
    root.rebaseVisibleMisspellingsForEdit(previousSource, nextSource, edit)
    if (root.spellcheckNeedsFullCheck) return
    var pending = root.spellcheckPendingEdits.slice()
    pending.push({
      start: Number(edit.start),
      removed: previousSource.slice(Number(edit.start), Number(edit.oldEnd)),
      inserted: String(edit.insertedText || "")
    })
    // A very long burst is cheaper and safer to resynchronize as one full
    // document than to retain an unbounded sequence of intermediate edits.
    if (pending.length > 128) {
      root.spellcheckNeedsFullCheck = true
      root.spellcheckPendingEdits = []
    } else {
      root.spellcheckPendingEdits = pending
    }
  }

  function invalidateSpellcheckForSourceChange(previousSourceValue,
      nextSourceValue) {
    root.spellcheckSourceRevision++
    root.spellcheckRequestId++
    root.spellcheckSuggestionRequestId++
    spellcheckTimer.stop()
    root.spellingContextRange = null
    root.spellingContextSuggestions = []
    root.spellingSuggestionsPending = false
    root.queueSpellcheckEdit(previousSourceValue, nextSourceValue)
    root.scheduleSpellcheck()
  }

  function resetSpellcheckForDocumentChange() {
    root.spellcheckSourceRevision++
    root.spellcheckRequestId++
    root.spellcheckSuggestionRequestId++
    spellcheckTimer.stop()
    root.clearSpellingVisualState()
    root.clearSpellcheckCandidateState()
    root.spellcheckNeedsFullCheck = true
    root.spellcheckPendingEdits = []
  }

  function scheduleSpellcheck() {
    if (!root.spellcheckEnabled || !root.spellcheckReady ||
        !root.opened || root.loadingFromFile || root.noteLoadError !== "") {
      if (!root.spellcheckEnabled && root.misspellings.length > 0) {
        root.misspellings = []
        root.queueSpellingGeometryUpdate()
      }
      return
    }
    spellcheckTimer.restart()
  }

  function runSpellcheck() {
    if (!root.spellcheckEnabled || !root.spellcheckReady ||
        !root.opened || root.loadingFromFile || root.noteLoadError !== "") return
    root.spellcheckRequestId++
    root.spellcheckDispatchCount++
    root.spellcheckPendingCandidates = []
    var full = root.spellcheckNeedsFullCheck
    var pendingEdits = root.spellcheckPendingEdits.slice()
    root.spellcheckNeedsFullCheck = false
    root.spellcheckPendingEdits = []
    if (full) root.spellcheckFullDispatchCount++
    else root.spellcheckIncrementalDispatchCount++
    var request = {
      type: "check",
      requestId: root.spellcheckRequestId,
      sourceRevision: root.spellcheckSourceRevision,
      full: full
    }
    if (full) request.source = String(editor.text || "")
    else request.edits = pendingEdits
    spellcheckWorker.sendMessage(request)
  }

  function prepareSpellingContext(sourcePosition) {
    root.spellingContextRange = root.spellcheckEnabled
      ? SpellcheckModel.rangeAtPosition(root.misspellings, sourcePosition)
      : null
    root.spellingContextSuggestions = []
    root.spellingSuggestionsPending = false
    if (!root.spellingContextRange) return
    root.spellcheckSuggestionRequestId++
    root.spellingSuggestionsPending = true
    spellcheckWorker.sendMessage({
      type: "suggest",
      requestId: root.spellcheckSuggestionRequestId,
      word: String(root.spellingContextRange.checkWord ||
        root.spellingContextRange.word || "")
    })
  }

  function replaceSpellingContext(replacementValue) {
    var range = root.spellingContextRange
    var replacement = String(replacementValue || "")
    if (!range || !replacement) return false
    var source = String(editor.text || "")
    var start = Math.max(0, Math.min(Number(range.start) || 0, source.length))
    var end = Math.max(start, Math.min(Number(range.end) || start, source.length))
    var nextSource = source.slice(0, start) + replacement + source.slice(end)
    if (!root.replaceEditorText(nextSource, start + replacement.length,
        false, false)) return false
    root.noteEdited()
    root.closeEditorContextMenu()
    Qt.callLater(root.syncLiveCursor)
    return true
  }

  function ignoreSpellingContext() {
    var range = root.spellingContextRange
    if (!range) return false
    spellcheckWorker.sendMessage({type: "ignore", word: range.checkWord || range.word})
    root.closeEditorContextMenu()
    return true
  }

  function addPersonalDictionaryWord(wordValue) {
    var word = String(wordValue || "").trim()
    if (!word) return false
    var words = root.normalizedPersonalDictionaryWords(
      root.personalDictionaryWords.concat([word]))
    if (words.length === root.personalDictionaryWords.length) return false
    root.personalDictionaryWords = words
    root.personalDictionaryWritePending = true
    root.ensurePresentationSettingsDirectory()
    root.writePersonalDictionary()
    spellcheckWorker.sendMessage({type: "add", word: word})
    return true
  }

  function addSpellingContextToDictionary() {
    var range = root.spellingContextRange
    if (!range || !root.addPersonalDictionaryWord(range.word)) return false
    root.closeEditorContextMenu()
    return true
  }

  function writePersonalDictionary() {
    if (!root.personalDictionaryLoaded ||
        !root.personalDictionaryWritePending ||
        root.personalDictionaryWriteInFlight) return
    if (!root.presentationSettingsDirectoryReady) {
      root.ensurePresentationSettingsDirectory()
      return
    }
    var desired = JSON.stringify({
      version: 1,
      language: root.spellcheckLanguage,
      words: root.personalDictionaryWords
    }, null, 2) + "\n"
    if (String(personalDictionaryFile.text() || "") === desired) {
      root.personalDictionaryWritePending = false
      return
    }
    root.personalDictionaryWritePending = false
    root.personalDictionaryWriteInFlight = true
    personalDictionaryFile.setText(desired)
  }

  function appendSpellingRangeRectangle(rects, xValue, yValue,
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

  function rawSourceRangeRectangles(startValue, endValue) {
    var source = String(editor.text || "")
    var start = Math.max(0, Math.min(source.length,
      Math.min(Number(startValue), Number(endValue))))
    var end = Math.max(start, Math.min(source.length,
      Math.max(Number(startValue), Number(endValue))))
    var rects = []
    for (var position = start; position < end; position++) {
      var rect = editor.positionToRectangle(position)
      var nextRect = editor.positionToRectangle(position + 1)
      if (!rect || !nextRect || Number(rect.height) <= 0) continue
      var nextSameLine = Math.abs(
        Number(nextRect.y) - Number(rect.y)) < 0.75 &&
        Number(nextRect.x) >= Number(rect.x)
      var endX = nextSameLine ? Number(nextRect.x) :
        Number(rect.x) + Math.max(2, renderedEditor.cursorWidth(
          source.slice(position, position + 1), Style.font.body))
      root.appendSpellingRangeRectangle(rects,
        Number(rect.x), Number(rect.y), endX, Number(rect.height))
    }
    for (var baselinePosition = start;
         baselinePosition < end; baselinePosition++) {
      var baselineCaret = editor.positionToRectangle(baselinePosition)
      if (!baselineCaret || Number(baselineCaret.height) <= 0) continue
      var baselineCenterY = Number(baselineCaret.y) +
        Number(baselineCaret.height) / 2
      var baselineCenterX = Number(baselineCaret.x) +
        Number(baselineCaret.width) / 2
      for (var baselineRow = 0; baselineRow < rects.length; baselineRow++) {
        var row = rects[baselineRow]
        if (baselineCenterY < Number(row.y) - 1 ||
            baselineCenterY > Number(row.y) + Number(row.height) + 1 ||
            baselineCenterX < Number(row.x) - 1 ||
            baselineCenterX > Number(row.x) + Number(row.width) + 1) continue
        row.underlineY = Number(baselineCaret.y) +
          Number(baselineCaret.height) -
          Math.max(0.5, Number(baselineCaret.height) * 0.04)
        break
      }
    }
    return rects
  }

  function spellingUnderlineLift(heightValue) {
    var height = Math.max(1, Number(heightValue) || Style.font.body)
    return Math.max(1, Math.min(2, height * 0.08))
  }

  function visibleEditorSourceRange() {
    if (!root.rawMode) return renderedEditor.viewportSourceRange()
    var source = String(editor.text || "")
    var viewportTop = Math.max(0, Number(editorViewport.contentY) || 0)
    var viewportBottom = viewportTop +
      Math.max(0, Number(editorViewport.height) || 0)
    var start = Math.max(0, Math.min(source.length,
      Number(editor.positionAt(editor.leftPadding, viewportTop)) || 0))
    var end = Math.max(start, Math.min(source.length,
      Number(editor.positionAt(editor.leftPadding, viewportBottom)) || 0))
    var lineStart = start > 0 ? source.lastIndexOf("\n", start - 1) + 1 : 0
    var lineEnd = source.indexOf("\n", end)
    if (lineEnd < 0) lineEnd = source.length
    else lineEnd++
    return {start: lineStart, end: lineEnd}
  }

  function spellingUnderlineSegments() {
    var revision = root.spellingGeometryRevision
    var layoutRevision = renderedEditor.layoutRevision
    var viewportTop = Number(editorViewport.contentY) || 0
    var viewportBottom = viewportTop + Number(editorViewport.height || 0)
    var ranges = root.opened && root.spellcheckEnabled
      ? root.misspellings : []
    var visibleSource = root.visibleEditorSourceRange()
    var segments = []
    var raw = root.rawMode
    for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
      var range = ranges[rangeIndex]
      if (Number(range.end) <= Number(visibleSource.start)) continue
      if (Number(range.start) >= Number(visibleSource.end)) break
      var rowRects = raw
        ? root.rawSourceRangeRectangles(range.start, range.end)
        : renderedEditor.sourceRangeRectangles(range.start, range.end)
      for (var rowIndex = 0; rowIndex < rowRects.length; rowIndex++) {
        var row = rowRects[rowIndex]
        // Raw and Live rectangles originate in different Items. Normalize
        // both into the spelling overlay's parent coordinate system instead
        // of relying on their current coincident x/y origins. This keeps the
        // underline attached if either editor gains padding or is reparented.
        var sourceItem = raw ? editor : renderedEditor
        var overlayParent = spellingUnderlineRepeater.parent
        var mapped = overlayParent && overlayParent.mapFromItem
          ? overlayParent.mapFromItem(sourceItem,
              Number(row.x) || 0, Number(row.y) || 0)
          : Qt.point(Number(row.x) || 0, Number(row.y) || 0)
        var mappedUnderline = overlayParent && overlayParent.mapFromItem &&
            isFinite(Number(row.underlineY))
          ? overlayParent.mapFromItem(sourceItem,
              Number(row.x) || 0, Number(row.underlineY)).y
          : Number(row.underlineY)
        var y = Number(mapped.y)
        var height = Math.max(1, Number(row.height) || 1)
        if (y + height < viewportTop || y > viewportBottom) continue
        var underlineBaseY = isFinite(Number(mappedUnderline))
          ? Number(mappedUnderline) : y + height - Style.space(2)
        segments.push({
          x: Number(mapped.x),
          width: Math.max(2, Number(row.width) || 0),
          sourceY: y,
          sourceHeight: height,
          y: underlineBaseY - root.spellingUnderlineLift(height),
          rangeStart: Number(range.start),
          rangeEnd: Number(range.end),
          word: String(range.word || ""),
          segmentOrdinal: rowIndex
        })
      }
    }
    return segments
  }

  function queueSpellingGeometryUpdate(forceValue) {
    if (root.spellingGeometryDeferred && forceValue !== true) return
    root.spellingGeometryRevision++
    spellingGeometryTimer.restart()
  }

  function spellingSegmentsSameIdentity(firstValue, secondValue) {
    var first = firstValue || {}
    var second = secondValue || {}
    return String(first.word || "") === String(second.word || "") &&
      Number(first.segmentOrdinal) === Number(second.segmentOrdinal)
  }

  function spellingUnderlineVisualRecord(segmentValue) {
    var segment = segmentValue || {}
    return {
      segmentX: Number(segment.x) || 0,
      segmentY: Number(segment.y) || 0,
      segmentWidth: Math.max(2, Number(segment.width) || 0),
      rangeStart: Number(segment.rangeStart) || 0,
      rangeEnd: Number(segment.rangeEnd) || 0,
      word: String(segment.word || ""),
      segmentOrdinal: Number(segment.segmentOrdinal) || 0
    }
  }

  function updateSpellingUnderlineVisualRow(indexValue, segmentValue) {
    var index = Number(indexValue) || 0
    var next = root.spellingUnderlineVisualRecord(segmentValue)
    var current = spellingUnderlineVisualModel.get(index)
    var numericRoles = ["segmentX", "segmentY", "segmentWidth",
      "rangeStart", "rangeEnd", "segmentOrdinal"]
    for (var roleIndex = 0; roleIndex < numericRoles.length; roleIndex++) {
      var role = numericRoles[roleIndex]
      if (Math.abs(Number(current[role]) - Number(next[role])) > 0.01)
        spellingUnderlineVisualModel.setProperty(index, role, next[role])
    }
    if (String(current.word || "") !== next.word)
      spellingUnderlineVisualModel.setProperty(index, "word", next.word)
  }

  function syncSpellingUnderlineVisualModel(previousValue, nextValue) {
    var previous = Array.isArray(previousValue) ? previousValue : []
    var next = Array.isArray(nextValue) ? nextValue : []
    if (spellingUnderlineVisualModel.count !== previous.length) {
      spellingUnderlineVisualModel.clear()
      for (var resetIndex = 0; resetIndex < next.length; resetIndex++)
        spellingUnderlineVisualModel.append(
          root.spellingUnderlineVisualRecord(next[resetIndex]))
      return
    }

    var prefix = 0
    var commonLimit = Math.min(previous.length, next.length)
    while (prefix < commonLimit && root.spellingSegmentsSameIdentity(
        previous[prefix], next[prefix])) prefix++
    var oldTail = previous.length - 1
    var newTail = next.length - 1
    while (oldTail >= prefix && newTail >= prefix &&
        root.spellingSegmentsSameIdentity(previous[oldTail], next[newTail])) {
      oldTail--
      newTail--
    }
    var oldMiddleCount = Math.max(0, oldTail - prefix + 1)
    var newMiddleCount = Math.max(0, newTail - prefix + 1)
    var sharedMiddleCount = Math.min(oldMiddleCount, newMiddleCount)
    if (oldMiddleCount > newMiddleCount)
      spellingUnderlineVisualModel.remove(prefix + sharedMiddleCount,
        oldMiddleCount - newMiddleCount)
    else if (newMiddleCount > oldMiddleCount) {
      for (var insertIndex = sharedMiddleCount;
          insertIndex < newMiddleCount; insertIndex++) {
        spellingUnderlineVisualModel.insert(prefix + insertIndex,
          root.spellingUnderlineVisualRecord(next[prefix + insertIndex]))
      }
    }
    for (var updateIndex = 0; updateIndex < next.length; updateIndex++)
      root.updateSpellingUnderlineVisualRow(updateIndex, next[updateIndex])
  }

  function rebuildSpellingUnderlineModel() {
    // A renderer layout signal can be delivered before TextEdit.onTextChanged
    // freezes spellcheck geometry. Never let an already-queued timer publish
    // the partially rebased range set during that race.
    if (root.spellingGeometryDeferred) return
    var next = root.spellingUnderlineSegments()
    var previous = Array.isArray(root.spellingUnderlineModel)
      ? root.spellingUnderlineModel : []
    if (previous.length === next.length) {
      var unchanged = true
      for (var index = 0; index < next.length; index++) {
        var before = previous[index] || {}
        var after = next[index] || {}
        if (Number(before.rangeStart) !== Number(after.rangeStart) ||
            Number(before.rangeEnd) !== Number(after.rangeEnd) ||
            String(before.word || "") !== String(after.word || "") ||
            Number(before.segmentOrdinal) !== Number(after.segmentOrdinal) ||
            Math.abs(Number(before.x) - Number(after.x)) > 0.01 ||
            Math.abs(Number(before.y) - Number(after.y)) > 0.01 ||
            Math.abs(Number(before.width) - Number(after.width)) > 0.01 ||
            Math.abs(Number(before.sourceY) - Number(after.sourceY)) > 0.01 ||
            Math.abs(Number(before.sourceHeight) -
              Number(after.sourceHeight)) > 0.01) {
          unchanged = false
          break
        }
      }
      if (unchanged) return
    }
    root.syncSpellingUnderlineVisualModel(previous, next)
    root.spellingUnderlineModel = next
    root.spellingUnderlinePublishCount++
  }

  function closeEditorContextMenu() {
    if (editorContextMenu.opened) editorContextMenu.close()
  }

  function openEditorContextMenuAt(frameX, frameY, sourcePosition) {
    if (!root.opened || root.loadingFromFile || root.noteLoadError !== "" ||
        root.recoveryPromptOpen) return false
    var position = Number(sourcePosition)
    if (isFinite(position)) {
      position = Math.max(0, Math.min(position, editor.length))
      var insideSelection = editor.selectionStart !== editor.selectionEnd &&
        position >= editor.selectionStart && position < editor.selectionEnd
      editor.forceActiveFocus()
      if (!insideSelection) editor.cursorPosition = position
    } else position = Number(editor.cursorPosition) || 0
    root.prepareSpellingContext(position)
    root.closeFileMenu()
    editorContextMenu.x = Math.max(0, Math.min(Number(frameX) || 0,
      editorFrame.width - editorContextMenu.width))
    editorContextMenu.y = Math.max(0, Math.min(Number(frameY) || 0,
      editorFrame.height - editorContextMenu.implicitHeight))
    editorContextMenu.open()
    return true
  }

  function openEditorContextMenuForKeyboard() {
    var caret = root.rawMode
      ? editor.cursorRectangle
      : renderedEditor.cursorRectangleForSource(editor.cursorPosition)
    if (!caret) caret = editor.cursorRectangle
    var target = root.rawMode ? editor : renderedEditor
    var point = target.mapToItem(editorFrame,
      caret.x, caret.y + Math.max(1, caret.height))
    return root.openEditorContextMenuAt(point.x, point.y, NaN)
  }

  function performEditorContextAction(actionValue) {
    var action = String(actionValue || "")
    var performed = false
    if (action === "cut" || action === "paste")
      root.captureHistoryInputState()
    if (action === "undo" && root.editorCanUndo) {
      performed = root.applyEditorHistory("undo")
    } else if (action === "redo" && root.editorCanRedo) {
      performed = root.applyEditorHistory("redo")
    } else if (action === "cut" &&
        editor.selectionStart !== editor.selectionEnd) {
      editor.cut()
      performed = true
    } else if (action === "copy" &&
        editor.selectionStart !== editor.selectionEnd) {
      editor.copy()
      performed = true
    } else if (action === "paste" && editor.canPaste) {
      editor.paste()
      performed = true
    } else if (action === "selectAll") {
      editor.selectAll()
      performed = true
    }
    if (!performed) return false
    root.closeEditorContextMenu()
    editor.forceActiveFocus()
    Qt.callLater(function() {
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function editorContextState() {
    return JSON.stringify({
      open: Boolean(editorContextMenu.opened),
      text: String(editor.text || ""),
      cursorPosition: Number(editor.cursorPosition),
      selectionStart: Number(editor.selectionStart),
      selectionEnd: Number(editor.selectionEnd),
      canUndo: Boolean(root.editorCanUndo),
      canRedo: Boolean(root.editorCanRedo),
      canPaste: Boolean(editor.canPaste),
      spellingWord: root.spellingContextRange
        ? String(root.spellingContextRange.word || "") : "",
      spellingSuggestionCount: root.spellingContextSuggestions.length,
      spellingSuggestionsPending: root.spellingSuggestionsPending,
      dirty: root.dirty
    })
  }

  function expandedPath(value) {
    var next = String(value || "").trim()
    if (next.indexOf("~/") === 0) next = root.home + next.slice(1)
    return next
  }

  function fileNameForPath(path) {
    var clean = String(path || "").replace(/\/+$/, "")
    var slash = clean.lastIndexOf("/")
    return slash >= 0 ? clean.slice(slash + 1) : clean
  }

  function recoveryPathFor(path) {
    var source = String(path || "")
    var hash = 2166136261
    for (var index = 0; index < source.length; index++) {
      hash ^= source.charCodeAt(index)
      hash = ((hash << 1) + (hash << 4) + (hash << 7) +
        (hash << 8) + (hash << 24)) >>> 0
    }
    return root.recoveryDirectory + "/" + hash.toString(16) + "-" +
      source.length + ".json"
  }

  function currentNotePath() {
    return root.notePath
  }

  function persistenceState() {
    return JSON.stringify({
      notePath: root.notePath,
      defaultNotesDirectory: root.defaultNotesDirectory,
      sidePlacement: root.sidePlacement,
      fileTabRows: root.fileTabRows,
      editorTextScale: root.editorTextScale,
      spellcheckEnabled: root.spellcheckEnabled,
      spellcheckReady: root.spellcheckReady,
      spellcheckDelayMs: root.spellcheckDelayMs,
      spellcheckTimerRunning: spellcheckTimer.running,
      spellcheckRequestId: root.spellcheckRequestId,
      spellcheckDispatchCount: root.spellcheckDispatchCount,
      spellcheckFullDispatchCount: root.spellcheckFullDispatchCount,
      spellcheckIncrementalDispatchCount:
        root.spellcheckIncrementalDispatchCount,
      spellcheckPendingEditCount: root.spellcheckPendingEdits.length,
      spellcheckNeedsFullCheck: root.spellcheckNeedsFullCheck,
      spellcheckLastMetrics: root.spellcheckLastMetrics,
      spellingUnderlinePublishCount: root.spellingUnderlinePublishCount,
      spellingUnderlineVisualCount: spellingUnderlineVisualModel.count,
      spellingUnderlineDelegateCreateCount:
        root.spellingUnderlineDelegateCreateCount,
      spellingGeometryDeferred: root.spellingGeometryDeferred,
      spellingUnderlineView: root.rawMode ? "raw" : "preview",
      misspellingCount: root.misspellings.length,
      personalDictionaryWords: root.personalDictionaryWords,
      personalDictionaryWritePending: root.personalDictionaryWritePending,
      personalDictionaryWriteInFlight: root.personalDictionaryWriteInFlight,
      shortcuts: {
        save: root.shortcutSave,
        saveAs: root.shortcutSaveAs,
        open: root.shortcutOpen,
        new: root.shortcutNew,
        preview: root.shortcutPreview,
        close: root.shortcutClose
      },
      openFiles: root.persistedOpenFilePaths(),
      openNoteFiles: root.openNoteFiles,
      sourceLength: String(editor.text || "").length,
      statusText: root.statusText,
      loadingFromFile: root.loadingFromFile,
      directoryReady: root.directoryReady,
      dirty: root.dirty,
      pendingSave: root.pendingSave,
      noteSaveInFlight: root.noteSaveInFlight,
      pendingNoteSavePath: root.pendingNoteSavePath,
      presentationSettingsLoaded: root.presentationSettingsLoaded,
      presentationSettingsWritePending:
        root.presentationSettingsWritePending,
      presentationSettingsWriteInFlight:
        root.presentationSettingsWriteInFlight,
      settingsOpen: root.settingsOpen,
      settingsDirectoryChangeInFlight:
        root.settingsDirectoryChangeInFlight,
      recoveryPath: root.recoveryPath,
      recoveryWritePending: root.recoveryWritePending,
      recoveryWriteInFlight: root.recoveryWriteInFlight,
      recoveryPromptOpen: root.recoveryPromptOpen
    })
  }

  function directoryForPath(path) {
    var slash = String(path || "").lastIndexOf("/")
    return slash > 0 ? String(path).slice(0, slash) : "."
  }

  function joinPath(directory, name) {
    var base = String(directory || "").replace(/\/+$/, "")
    var child = String(name || "").replace(/^\/+/, "")
    if (base === "") return "/" + child
    if (base === "/") return "/" + child
    return base + "/" + child
  }

  function parentPath(path) {
    var clean = String(path || "/").replace(/\/+$/, "")
    if (clean === "") return "/"
    var slash = clean.lastIndexOf("/")
    return slash <= 0 ? "/" : clean.slice(0, slash)
  }

  function fileUrlForPath(path) {
    return "file://" + encodeURI(String(path || ""))
  }

  function pathFromUrl(value) {
    if (value && typeof value.toLocalFile === "function") {
      var localPath = value.toLocalFile()
      if (localPath) return localPath
    }

    var raw = String(value || "")
    if (raw.indexOf("file://") === 0) raw = raw.slice(7)
    try {
      raw = decodeURIComponent(raw)
    } catch (error) {
      // Keep the undecoded path if the dialog returned an unusual URL.
    }
    if (raw.charAt(0) !== "/") raw = "/" + raw
    return raw
  }

  function addOpenFile(path, persistChanges) {
    var nextPath = root.normalizedFilePath(path)
    if (nextPath === "") return false

    for (var index = 0; index < root.openFiles.length; index++) {
      if (root.openFiles[index].path === nextPath) return false
    }

    var next = root.openFiles.slice()
    next.push({
      path: nextPath,
      name: root.fileNameForPath(nextPath)
    })
    root.openFiles = next
    if (persistChanges !== false) root.schedulePersistedSettingsSave()
    return true
  }

  function loadSaveFolders() {
    var directory = root.expandedPath(root.saveAsDirectory)
    if (directory === "" || directory.charAt(0) !== "/") return
    root.saveAsDirectory = directory
    if (folderListProcess.running) return
    folderListProcess.command = [
      "find", directory,
      "-mindepth", "1",
      "-maxdepth", "1",
      "-type", "d",
      "-printf", "%f\\n"
    ]
    folderListProcess.running = true
  }

  function setOpenNoteFiles(value) {
    var directory = root.openNoteFilesDirectory
    var files = []
    var lines = String(value || "").split(/\r?\n/)
    for (var index = 0; index < lines.length; index++) {
      var name = lines[index].trim()
      if (name === "" || !/\.md$/i.test(name)) continue
      var path = root.normalizedFilePath(root.joinPath(directory, name))
      if (path === "") continue
      var exists = false
      for (var fileIndex = 0; fileIndex < files.length; fileIndex++) {
        if (files[fileIndex].path === path) {
          exists = true
          break
        }
      }
      if (!exists) files.push({
        name: name,
        path: path
      })
    }
    files.sort(function(left, right) {
      return left.name.localeCompare(right.name)
    })
    root.openNoteFiles = files
    root.openNoteFilesLoading = false
  }

  function loadOpenNoteFiles() {
    var directory = root.normalizedDirectoryPath(root.defaultNotesDirectory)
    if (directory === "") {
      root.openNoteFiles = []
      root.openNoteFilesLoading = false
      return
    }
    root.openNoteFilesDirectory = directory
    root.openNoteFilesLoading = true
    if (openNoteListProcess.running) return
    openNoteListProcess.command = [
      "find", directory,
      "-mindepth", "1",
      "-maxdepth", "1",
      "-type", "f",
      "-iname", "*.md",
      "-printf", "%f\\n"
    ]
    openNoteListProcess.running = true
  }

  function setSaveAsFolders(value) {
    var directory = root.saveAsDirectory
    var folders = []
    var parent = root.parentPath(directory)
    if (parent !== directory) folders.push({ name: "..", path: parent })

    var lines = String(value || "").split(/\r?\n/)
    for (var index = 0; index < lines.length; index++) {
      var name = lines[index].trim()
      if (name === "") continue
      folders.push({ name: name, path: root.joinPath(directory, name) })
    }
    folders.sort(function(left, right) {
      if (left.name === "..") return -1
      if (right.name === "..") return 1
      return left.name.localeCompare(right.name)
    })
    root.saveAsFolders = folders
  }

  function performSwitchToFile(nextPath) {
    // A queued switch can pass through a note before its asynchronous scroll
    // restoration settles. Its previously stored state is authoritative;
    // capturing the temporary contentY here would overwrite it with zero.
    if (root.pendingEditorStateRestorePath === "") {
      root.captureActiveEditorState(false)
    } else {
      editorStateRestoreSettleTimer.stop()
      root.pendingEditorStateRestorePath = ""
      root.pendingEditorStateScrollY = 0
    }
    root.scheduleEditorStatesWrite()
    root.resetRecoveryLoadState()
    root.loadingFromFile = true
    root.setEditorText("", false, false, true)
    root.markdownSource = ""
    root.noteLoadedPath = ""
    root.notePath = nextPath
    root.noteMissing = false
    root.noteLoadError = ""
    root.knownDiskPath = ""
    root.knownDiskSource = ""
    root.externalConflict = false
    root.externalConflictMissing = false
    root.externalConflictPath = ""
    root.externalConflictSource = ""
    root.directoryReady = false
    root.pendingSave = false
    root.dirty = false
    root.statusText = "Loading…"
    root.schedulePersistedSettingsSave()
  }

  function focusEditorAfterFileLoad(loadedPathValue) {
    var loadedPath = root.normalizedFilePath(loadedPathValue)
    Qt.callLater(function() {
      if (!root.opened || root.loadingFromFile ||
          root.notePath !== loadedPath || root.pendingSwitchPath !== "" ||
          root.pendingSwitchContinuationQueued || root.screensaverActive)
        return
      editor.forceActiveFocus()
      root.syncLiveCursor()
    })
  }

  function maybeContinuePendingSwitch() {
    if (root.pendingSwitchPath === "" || root.loadingFromFile ||
        root.noteSaveInFlight || root.pendingSave || root.dirty ||
        root.pendingSwitchContinuationQueued) return
    root.pendingSwitchContinuationQueued = true
    Qt.callLater(function() {
      root.pendingSwitchContinuationQueued = false
      var nextPath = root.pendingSwitchPath
      if (nextPath === "" || root.loadingFromFile ||
          root.noteSaveInFlight || root.pendingSave || root.dirty) return
      root.pendingSwitchPath = ""
      if (nextPath !== root.notePath) root.performSwitchToFile(nextPath)
    })
  }

  function switchToFile(path) {
    var nextPath = root.normalizedFilePath(path)
    if (nextPath === "") return
    var added = root.addOpenFile(nextPath, false)
    if (nextPath === root.notePath) {
      root.pendingSwitchPath = ""
      if (added) root.schedulePersistedSettingsSave()
      return
    }

    if (root.loadingFromFile || root.noteSaveInFlight || root.pendingSave ||
        root.dirty || root.pendingSwitchPath !== "" ||
        root.pendingSwitchContinuationQueued) {
      root.pendingSwitchPath = nextPath
      root.statusText = "Saving before switching…"
      root.saveNow()
      root.maybeContinuePendingSwitch()
      root.schedulePersistedSettingsSave()
      return
    }
    root.performSwitchToFile(nextPath)
  }

  function activeFileIndex() {
    for (var index = 0; index < root.openFiles.length; index++) {
      if (root.openFiles[index].path === root.notePath) return index
    }
    return -1
  }

  function switchRelativeFile(offset) {
    if (root.openFiles.length < 2 || root.pendingSwitchPath !== "") return false
    var current = root.activeFileIndex()
    if (current < 0) current = 0
    var delta = Number(offset)
    if (!isFinite(delta) || delta === 0) return false
    var next = (current + (delta > 0 ? 1 : -1) +
      root.openFiles.length) % root.openFiles.length
    root.switchToFile(root.openFiles[next].path)
    return true
  }

  function closeActiveFile() {
    if (root.notePath === "") return false
    root.closeFile(root.notePath)
    return true
  }

  function renameActiveFile() {
    if (root.notePath === "") return false
    root.beginRenameFile(root.notePath)
    return root.renamingPath === root.notePath
  }

  function isGeneratedUntitledPath(path) {
    var target = root.normalizedFilePath(path)
    return target !== "" && root.generatedUntitledPaths.indexOf(target) >= 0
  }

  function finishCloseFile(closingPath) {
    var closingIndex = -1
    for (var index = 0; index < root.openFiles.length; index++) {
      if (root.openFiles[index].path === closingPath) {
        closingIndex = index
        break
      }
    }
    if (closingIndex < 0) return

    if (root.openFiles.length <= 1) {
      root.statusText = "Keep one file open"
      return
    }

    var wasActive = closingPath === root.notePath
    if (wasActive) root.captureActiveEditorState(false)

    var remaining = root.openFiles.slice()
    remaining.splice(closingIndex, 1)
    root.openFiles = remaining
    root.forgetGeneratedUntitledPath(closingPath)

    if (wasActive) {
      var nextIndex = Math.min(closingIndex, remaining.length - 1)
      root.switchToFile(remaining[nextIndex].path)
    }
    root.removeFileEditorState(closingPath)
    root.schedulePersistedSettingsSave()
  }

  function deleteEmptyUntitledFile(path) {
    var target = root.normalizedFilePath(path)
    if (!root.isGeneratedUntitledPath(target)) {
      root.pendingClosePath = ""
      root.finishCloseFile(target)
      return
    }
    if (root.untitledDeleteInFlight) return

    root.untitledDeletePath = target
    root.untitledDeleteInFlight = true
    root.statusText = "Removing empty note…"
    untitledDeleteProcess.command = ["rm", "-f", "--", target]
    untitledDeleteProcess.running = true
  }

  function maybeContinuePendingClose() {
    var target = root.pendingClosePath
    if (target === "" || target !== root.notePath ||
        root.loadingFromFile || root.noteSaveInFlight || root.pendingSave ||
        root.dirty) return

    // Closing can switch noteFile's path. Wait until its loaded/saved signal
    // returns so FileView cannot discard the replacement read's completion.
    Qt.callLater(function() {
      if (root.pendingClosePath !== target || target !== root.notePath ||
          root.loadingFromFile || root.noteSaveInFlight || root.pendingSave ||
          root.dirty) return
      root.pendingClosePath = ""
      if (root.openFiles.length === 1) {
        root.beginLastFileReplacement(target)
        return
      }
      if (root.isGeneratedUntitledPath(target) &&
          String(root.markdownSource || editor.text || "") === "") {
        root.deleteEmptyUntitledFile(target)
      } else {
        root.finishCloseFile(target)
      }
    })
  }

  function checkUntitledFileForClose(path) {
    if (root.untitledBlankCheckInFlight || root.untitledDeleteInFlight) return
    root.untitledBlankCheckPath = path
    root.untitledBlankCheckInFlight = true
    untitledBlankCheckProcess.command = ["test", "-s", path]
    untitledBlankCheckProcess.running = true
  }

  function closeFile(path) {
    var closingPath = root.normalizedFilePath(path)
    var closingIndex = -1
    for (var index = 0; index < root.openFiles.length; index++) {
      if (root.openFiles[index].path === closingPath) {
        closingIndex = index
        break
      }
    }
    if (closingIndex < 0) return

    if (root.pendingClosePath !== "" || root.untitledBlankCheckInFlight ||
        root.untitledDeleteInFlight || root.replaceLastFilePath !== "") return

    if (closingPath === root.notePath) {
      root.pendingClosePath = closingPath
      if (root.loadingFromFile || root.noteSaveInFlight || root.pendingSave ||
          root.dirty) {
        root.saveNow()
        root.maybeContinuePendingClose()
      } else if (root.openFiles.length === 1) {
        root.pendingClosePath = ""
        root.beginLastFileReplacement(closingPath)
      } else if (String(root.markdownSource || editor.text || "") === "") {
        if (root.isGeneratedUntitledPath(closingPath))
          root.deleteEmptyUntitledFile(closingPath)
        else {
          root.pendingClosePath = ""
          root.finishCloseFile(closingPath)
        }
      } else {
        root.pendingClosePath = ""
        root.finishCloseFile(closingPath)
      }
    } else if (root.isGeneratedUntitledPath(closingPath)) {
      root.pendingClosePath = closingPath
      root.checkUntitledFileForClose(closingPath)
    } else {
      root.finishCloseFile(closingPath)
    }
  }

  function applyPayload(payloadJson) {
    var payload = ({})
    try {
      payload = JSON.parse(String(payloadJson || "{}")) || ({})
    } catch (e) {
      payload = ({})
    }

    if (typeof payload.mode === "string") {
      var mode = payload.mode.trim().toLowerCase()
      root.setPresentationMode(mode)
    }

    if (typeof payload.path !== "string" || payload.path.trim() === "") return

    var nextPath = root.normalizedMarkdownPath(payload.path, true)
    if (nextPath === "") {
      root.statusText = "Markdown files must end in .md"
      return
    }
    if (root.presentationSettingsLoaded && nextPath === root.notePath &&
        !root.loadingFromFile && root.noteLoadError === "") {
      root.pendingRecentPromotionPath = ""
      root.registerRecentFile(nextPath)
    } else {
      root.pendingRecentPromotionPath = nextPath
      if (root.presentationSettingsLoaded) root.switchToFile(nextPath)
      else root.pendingSessionPath = nextPath
    }
  }

  function hasSummonArguments(payloadJson) {
    var payload = ({})
    try {
      payload = JSON.parse(String(payloadJson || "{}")) || ({})
    } catch (e) {
      return false
    }

    return (typeof payload.mode === "string" &&
      payload.mode.trim() !== "") ||
      (typeof payload.path === "string" && payload.path.trim() !== "")
  }

  function focusedHyprlandWorkspace() {
    try {
      var activeToplevel = Hyprland.activeToplevel
      var activeWorkspace = activeToplevel ? activeToplevel.workspace : null
      var activeWorkspaceName = root.hyprlandWorkspaceName(activeWorkspace)
      if (activeWorkspaceName.indexOf("special:") === 0) {
        return activeWorkspace
      }
      return Hyprland.focusedWorkspace
    } catch (e) {
      return null
    }
  }

  function hyprlandWorkspaceName(workspace) {
    var name = workspace ? String(workspace.name || "") : ""
    if (name === "" && workspace) name = String(workspace.id)
    return name
  }

  function jotpinHyprlandToplevel() {
    try {
      var values = Hyprland.toplevels.values || []
      var expectedPrefix = root.sideMode
        ? "JotPin Side "
        : "JotPin Window — "

      for (var index = 0; index < values.length; index++) {
        var candidate = values[index]
        if (!candidate) continue
        var title = String(candidate.title || "")
        if (title.indexOf(expectedPrefix) === 0) return candidate
      }
      return null
    } catch (e) {
      return null
    }
  }

  function activeHyprlandFullscreenMode() {
    var toplevel = root.jotpinHyprlandToplevel()
    if (!toplevel) return -1

    var ipcObject = toplevel.lastIpcObject
    if (!ipcObject || ipcObject.fullscreen === undefined) return -1

    var mode = Number(ipcObject.fullscreen)
    return isNaN(mode) ? -1 : mode
  }

  function fullscreenStateForHyprlandEvent(event) {
    if (String(event && event.name ? event.name : "") !== "fullscreen")
      return -1
    var parts = []
    try {
      if (event && event.parse) parts = event.parse(1)
    } catch (e) {
    }
    if (!parts || parts.length === 0) {
      parts = String(event && event.data ? event.data : "").split(",")
    }
    var state = Number(parts[0])
    return isFinite(state) ? (state === 0 ? 0 : 1) : -1
  }

  function activeToplevelIsJotPin() {
    try {
      var title = String(Hyprland.activeToplevel
        ? Hyprland.activeToplevel.title || "" : "")
      return title.indexOf("JotPin Side ") === 0 ||
        title.indexOf("JotPin Window — ") === 0
    } catch (e) {
      return false
    }
  }

  function observeHyprlandFullscreenEvent(event) {
    var state = root.fullscreenStateForHyprlandEvent(event)
    if (state < 0 || !root.activeToplevelIsJotPin()) return false
    root.maximizeStateObserved = state === 1
    root.maximizeStatePending = false
    root.hyprlandWindowStateRevision++
    maximizeStateTimer.stop()
    return true
  }

  function syncMaximizeState() {
    root.hyprlandWindowStateRevision++
    if (!root.maximizeStatePending) {
      maximizeStateTimer.stop()
      return
    }

    var compositorMode = root.activeHyprlandFullscreenMode()
    if (compositorMode >= 0)
      root.maximizeStateObserved = compositorMode === 1
    var hasSettled = root.maximizeStateObserved === root.maximizeStateRequested
    var timedOut = Date.now() - root.maximizeStateRequestedAt >= 1500
    if (hasSettled || timedOut) {
      if (timedOut) root.maximizeStateObserved = root.maximizeStateRequested
      root.maximizeStatePending = false
      maximizeStateTimer.stop()
    }
  }

  function hyprlandWindowAddress(toplevel) {
    var address = toplevel ? String(toplevel.address || "") : ""
    if (address === "") return ""
    if (address.indexOf("0x") === 0 || address.indexOf("0X") === 0) {
      return address
    }
    return "0x" + address
  }

  function sameHyprlandWorkspace(left, right) {
    if (!left || !right) return false

    var leftId = Number(left.id)
    var rightId = Number(right.id)
    if (!isNaN(leftId) && !isNaN(rightId)) return leftId === rightId

    var leftName = String(left.name || "")
    var rightName = String(right.name || "")
    return leftName !== "" && leftName === rightName
  }

  function isJotPinOnFocusedWorkspace() {
    var workspace = root.focusedHyprlandWorkspace()
    var toplevel = root.jotpinHyprlandToplevel()
    return !!(workspace && toplevel) &&
      root.sameHyprlandWorkspace(toplevel.workspace, workspace)
  }

  function luaString(value) {
    return "\"" + String(value).replace(/\\/g, "\\\\")
      .replace(/\"/g, "\\\"") + "\""
  }

  function moveJotPinToFocusedWorkspace() {
    var toplevel = root.jotpinHyprlandToplevel()
    var address = root.hyprlandWindowAddress(toplevel)
    var workspace = root.focusedHyprlandWorkspace()
    var workspaceName = root.pendingWorkspaceName
    if (workspaceName === "") {
      workspaceName = root.hyprlandWorkspaceName(workspace)
    }
    if (!toplevel || address === "" || workspaceName === "") {
      return false
    }

    var windowSelector = "address:" + address
    var currentWorkspaceName = root.hyprlandWorkspaceName(toplevel.workspace)
    try {
      if (currentWorkspaceName !== workspaceName) {
        Hyprland.dispatch("hl.dsp.window.move({ workspace = " +
          root.luaString(workspaceName) + ", follow = false, window = " +
          root.luaString(windowSelector) + " })")
      }
      Hyprland.dispatch("hl.dsp.focus({ window = " +
        root.luaString(windowSelector) + " })")
      root.pendingWorkspaceName = ""
      return true
    } catch (e) {
      return false
    }
  }

  function resetAutoFence() {
    root.autoFencePending = false
    root.autoFenceCloseStart = -1
    root.autoFenceCloseText = ""
  }

  function resetAutoCodePairs() {
    root.autoCodePairs = []
  }

  function trackAutoFenceEdit(value) {
    return root.trackAutoFenceTransition(value)
  }

  function trackAutoFenceTransition(value, previousValue) {
    if (!root.autoFencePending) return true

    var previous = previousValue === undefined
      ? String(root.editorPreviousText || "")
      : String(previousValue || "")

    var result = EditorModel.trackAutoCodeFenceEdit(
      previous, String(value || ""),
      root.autoFenceCloseStart, root.autoFenceCloseText)
    if (!result.valid) {
      root.resetAutoFence()
      return false
    }
    root.autoFenceCloseStart = result.closeStart
    return true
  }

  function trackAutoCodePairsEdit(value, previousValue) {
    if (!root.autoCodePairs || root.autoCodePairs.length === 0) return

    var previous = previousValue === undefined
      ? String(root.editorPreviousText || "")
      : String(previousValue || "")
    var current = String(value || "")
    var nextPairs = []
    for (var index = 0; index < root.autoCodePairs.length; index++) {
      var pair = root.autoCodePairs[index]
      var tracked = EditorModel.trackAutoCodePairEdit(
        previous, current, pair.closeStart, pair.closeText)
      if (!tracked.valid) continue
      nextPairs.push({
        closeStart: tracked.closeStart,
        closeText: pair.closeText,
        openText: pair.openText
      })
    }
    root.autoCodePairs = nextPairs
  }

  function setEditorText(value, preserveAutoFence, preserveAutoCodePairs,
      preserveHistory) {
    var nextSource = String(value || "")
    root.trackAutoFenceEdit(nextSource)
    root.trackAutoCodePairsEdit(nextSource)
    root.editorUpdating = true
    editor.text = nextSource
    root.editorPreviousText = String(editor.text || "")
    root.editorUpdating = false
    root.clearHistoryInputState()
    if (!preserveHistory)
      root.clearEditorHistoryForPath(root.notePath, false)
    if (!preserveAutoFence) root.resetAutoFence()
    if (!preserveAutoCodePairs) root.resetAutoCodePairs()
  }

  function replaceEditorDocumentText(value, cursorPosition) {
    var current = String(editor.text || "")
    var nextSource = String(value || "")
    var nextCursor = Math.max(0, Math.min(Number(cursorPosition),
      nextSource.length))
    if (!isFinite(nextCursor)) nextCursor = nextSource.length

    if (current === nextSource) {
      editor.cursorPosition = nextCursor
      return false
    }

    var prefix = 0
    var sharedLength = Math.min(current.length, nextSource.length)
    while (prefix < sharedLength && current[prefix] === nextSource[prefix]) {
      prefix++
    }

    var currentEnd = current.length
    var nextEnd = nextSource.length
    while (currentEnd > prefix && nextEnd > prefix &&
        current[currentEnd - 1] === nextSource[nextEnd - 1]) {
      currentEnd--
      nextEnd--
    }

    // Replacing the selected document range keeps Qt's native undo stack.
    // Assigning TextEdit.text calls setPlainText(), which clears that stack.
    root.editorUpdating = true
    editor.select(prefix, currentEnd)
    editor.cursorSelection.text = nextSource.slice(prefix, nextEnd)
    editor.cursorPosition = nextCursor
    root.editorPreviousText = String(editor.text || "")
    root.editorUpdating = false

    return true
  }

  function replaceEditorText(value, cursorPosition, preserveAutoFence,
      preserveAutoCodePairs) {
    var current = String(editor.text || "")
    var nextSource = String(value || "")
    var beforeCursor = Number(editor.cursorPosition)
    var beforeSelectionStart = Number(editor.selectionStart)
    var beforeSelectionEnd = Number(editor.selectionEnd)
    root.trackAutoFenceTransition(nextSource, current)
    root.trackAutoCodePairsEdit(nextSource, current)
    var changed = root.replaceEditorDocumentText(nextSource, cursorPosition)
    if (changed) root.recordEditorHistory(
      current, beforeCursor, beforeSelectionStart, beforeSelectionEnd, false)
    root.clearHistoryInputState()
    if (!preserveAutoFence) root.resetAutoFence()
    if (!preserveAutoCodePairs) root.resetAutoCodePairs()
    return changed
  }

  function resizeMarkdownImage(sourceStart, sourceEnd, width) {
    if (root.rawMode || root.loadingFromFile) return false
    var result = EditorModel.resizeMarkdownImage(
      String(editor.text || ""), sourceStart, sourceEnd, width,
      editor.cursorPosition)
    if (!result.changed ||
        !root.replaceEditorText(result.source, result.cursor)) return false
    root.noteEdited()
    Qt.callLater(root.syncLiveCursor)
    return true
  }

  function applyTableEditResult(resultValue) {
    var result = resultValue || {}
    if (!result.handled || !result.changed) return false
    if (!root.replaceEditorText(result.source, result.cursor,
        root.autoFencePending, root.autoCodePairs.length > 0)) return false
    root.noteEdited()
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.ensureEditorCursorVisible(true)
      root.syncLiveCursor()
    })
    return true
  }

  function performTableAction(actionValue) {
    if (root.rawMode || root.editorUpdating || root.loadingFromFile)
      return false
    return root.applyTableEditResult(EditorModel.tableStructuralEdit(
      String(editor.text || ""), editor.cursorPosition,
      actionValue, root.rawMode))
  }

  function completeCodeFence() {
    if (root.editorAutoFormatting || root.editorUpdating ||
        root.loadingFromFile) return false

    var current = String(editor.text || "")
    var previous = String(root.editorPreviousText || "")
    var result = EditorModel.completeCodeFence(
      current, previous, editor.cursorPosition)
    if (!result.changed) return false

    root.editorAutoFormatting = true
    root.replaceEditorDocumentText(result.source, result.cursor)
    root.editorAutoFormatting = false
    root.autoFenceCloseStart = Number(result.closeStart)
    root.autoFenceCloseText = String(result.closeText || "")
    root.autoFencePending = true
    return true
  }

  function completeCodePair() {
    if (root.editorAutoFormatting || root.editorUpdating ||
        root.loadingFromFile) return false

    var current = String(editor.text || "")
    var previous = String(root.editorPreviousText || "")
    var result = EditorModel.completeCodePair(
      current, previous, editor.cursorPosition, root.autoCodePairs)
    if (!result.changed) {
      root.trackAutoCodePairsEdit(current)
      return false
    }

    if (result.action === "skip") {
      var remainingPairs = []
      for (var pairIndex = 0; pairIndex < root.autoCodePairs.length;
           pairIndex++) {
        if (pairIndex === result.pairIndex) continue
        remainingPairs.push(root.autoCodePairs[pairIndex])
      }
      root.autoCodePairs = remainingPairs
      root.trackAutoFenceTransition(result.source, current)
    } else {
      root.trackAutoCodePairsEdit(current)
      var shiftedPairs = []
      for (var shiftedIndex = 0;
           shiftedIndex < root.autoCodePairs.length; shiftedIndex++) {
        var shiftedPair = root.autoCodePairs[shiftedIndex]
        shiftedPairs.push({
          closeStart: Number(shiftedPair.closeStart) >= result.cursor
            ? Number(shiftedPair.closeStart) + result.closeText.length
            : Number(shiftedPair.closeStart),
          closeText: shiftedPair.closeText,
          openText: shiftedPair.openText
        })
      }
      shiftedPairs.push({
        closeStart: result.closeStart,
        closeText: result.closeText,
        openText: result.openText
      })
      root.autoCodePairs = shiftedPairs
      root.trackAutoFenceTransition(result.source, current)
    }

    root.editorAutoFormatting = true
    root.replaceEditorDocumentText(result.source, result.cursor)
    root.editorAutoFormatting = false
    return true
  }

  function completeListMarker() {
    if (root.editorAutoFormatting || root.editorUpdating ||
        root.loadingFromFile) return false

    var current = String(editor.text || "")
    var previous = String(root.editorPreviousText || "")
    root.editorPreviousText = current
    var result = EditorModel.completeListMarker(
      current, previous, editor.cursorPosition)
    if (!result.changed) return false

    root.trackAutoFenceEdit(result.source)
    root.trackAutoCodePairsEdit(result.source)
    root.editorAutoFormatting = true
    root.replaceEditorDocumentText(result.source, result.cursor)
    root.editorAutoFormatting = false
    return true
  }

  function handleListReturn() {
    if (root.editorUpdating || root.loadingFromFile ||
        editor.selectionStart !== editor.selectionEnd) return false

    var source = String(editor.text || "")
    var result = EditorModel.listReturn(
      source, editor.cursorPosition, editor.selectionStart,
      editor.selectionEnd, !root.rawMode)
    if (!result.handled) return false

    root.replaceEditorText(result.source, result.cursor,
      root.autoFencePending, root.autoCodePairs.length > 0)
    root.noteEdited()
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function handlePlainReturn() {
    if (root.editorUpdating || root.loadingFromFile) return false

    var source = String(editor.text || "")
    var result = EditorModel.plainReturn(
      source, editor.cursorPosition, editor.selectionStart,
      editor.selectionEnd)
    if (!result.handled) return false

    // Handle ordinary Return explicitly instead of leaving it to the native
    // TextEdit event path. This preserves consecutive newlines as real source
    // bytes, including an empty line at the end of a note.
    root.replaceEditorText(result.source, result.cursor,
      root.autoFencePending, root.autoCodePairs.length > 0)
    root.noteEdited()
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function handleFenceHeaderReturn() {
    if (root.rawMode || root.editorUpdating || root.loadingFromFile)
      return false

    var result = EditorModel.fenceHeaderReturn(
      String(editor.text || ""), editor.cursorPosition,
      editor.selectionStart, editor.selectionEnd)
    if (!result.handled) return false

    editor.cursorPosition = Number(result.cursor)
    root.clearHistoryInputState()
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function handleHeadingSpace() {
    if (root.rawMode || root.editorUpdating || root.loadingFromFile)
      return false

    var source = String(editor.text || "")
    var result = EditorModel.headingSpace(
      source, editor.cursorPosition, editor.selectionStart,
      editor.selectionEnd)
    if (!result.handled) return false

    root.replaceEditorText(result.source, result.cursor,
      root.autoFencePending, root.autoCodePairs.length > 0)
    root.noteEdited()
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function handleBackspace() {
    if (root.editorUpdating || root.loadingFromFile) return false

    var source = String(editor.text || "")
    var selectionStart = editor.selectionStart
    var selectionEnd = editor.selectionEnd
    if (!root.rawMode && root.autoFencePending) {
      var fenceBoundary = EditorModel.fenceBodyBackspace(
        source, editor.cursorPosition, selectionStart, selectionEnd,
        root.autoFenceCloseStart, root.autoFenceCloseText)
      if (fenceBoundary.handled) {
        editor.cursorPosition = Number(fenceBoundary.cursor)
        root.clearHistoryInputState()
        Qt.callLater(function() {
          if (!root.opened) return
          editor.forceActiveFocus()
          root.ensureEditorCursorVisible()
          root.syncLiveCursor()
        })
        return true
      }
    }
    var result = EditorModel.listBackspace(
      source, editor.cursorPosition, selectionStart, selectionEnd,
      !root.rawMode)
    if (!result.handled) result = EditorModel.plainBackspace(
      source, editor.cursorPosition, selectionStart, selectionEnd)
    if (!result.handled && !root.rawMode) {
      result = EditorModel.backspaceOrphanCodeFence(
        source, editor.cursorPosition, selectionStart, selectionEnd)
    }
    if (!result.handled) return false

    var preserveAutoCodePairs = root.autoCodePairs.length > 0
    var trackedCodePairHandled = false
    if (preserveAutoCodePairs && selectionStart === selectionEnd) {
      var pairIndex = -1
      var cursor = Number(editor.cursorPosition)
      for (var index = root.autoCodePairs.length - 1;
           index >= 0; index--) {
        var pair = root.autoCodePairs[index]
        var openText = String(pair.openText || "")
        var closeStart = Number(pair.closeStart)
        if (openText !== "" && isFinite(closeStart) &&
            source.slice(Math.max(0, cursor - openText.length), cursor) ===
              openText) {
          pairIndex = index
          break
        }
      }
      if (pairIndex >= 0) {
        var pair = root.autoCodePairs[pairIndex]
        var pairResult = EditorModel.backspaceAutoCodePair(
          source, editor.cursorPosition, selectionStart, selectionEnd,
          result.source, result.cursor, pair.closeStart, pair.closeText,
          pair.openText)
        if (pairResult.handled) {
          result = pairResult
          trackedCodePairHandled = true
        }
      }
    }
    if (!trackedCodePairHandled) {
      var emptyPairResult = EditorModel.backspaceEmptyCodePair(
        source, editor.cursorPosition, selectionStart, selectionEnd)
      if (emptyPairResult.handled) result = emptyPairResult
    }

    var preserveAutoFence = false
    if (root.autoFencePending) {
      var autoFenceResult = EditorModel.backspaceAutoCodeFence(
        source, editor.cursorPosition, selectionStart, selectionEnd,
        result.source, result.cursor, root.autoFenceCloseStart,
        root.autoFenceCloseText)
      if (autoFenceResult.handled) {
        result = autoFenceResult
        preserveAutoFence = Boolean(autoFenceResult.keepPair)
      } else {
        preserveAutoFence = EditorModel.trackAutoCodeFenceEdit(
          source, result.source, root.autoFenceCloseStart,
          root.autoFenceCloseText).valid
        if (!preserveAutoFence) root.resetAutoFence()
      }
    }

    root.replaceEditorText(result.source, result.cursor, preserveAutoFence,
      preserveAutoCodePairs)
    root.noteEdited()
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.ensureEditorCursorVisible()
      root.syncLiveCursor()
    })
    return true
  }

  function toggleTask(sourcePosition) {
    if (root.loadingFromFile) return

    var source = String(editor.text || "")
    var requested = Number(sourcePosition)
    if (!isFinite(requested)) return
    var anchor = Math.max(0, Math.min(requested, source.length))
    var lineStart = source.lastIndexOf("\n", Math.max(0, anchor - 1)) + 1
    var lineEnd = source.indexOf("\n", anchor)
    if (lineEnd < 0) lineEnd = source.length

    var line = source.slice(lineStart, lineEnd)
    var task = /^(\s*)([-+*]|\d+[.)])([ \t]+)\[([ xX])\]([ \t]+)/.exec(line)
    if (!task) return

    var statePosition = lineStart + task[1].length + task[2].length +
      task[3].length + 1
    var nextState = task[4].toLowerCase() === "x" ? " " : "x"
    var cursorPosition = editor.cursorPosition
    var selectionStart = editor.selectionStart
    var selectionEnd = editor.selectionEnd
    var preserveLiveViewport = !root.rawMode
    var liveViewportY = preserveLiveViewport
      ? Number(editorViewport.contentY) || 0 : 0
    if (preserveLiveViewport) {
      root.taskToggleViewportY = liveViewportY
      root.taskToggleViewportRestorePending = true
      root.taskToggleViewportSettledFrames = 0
    }
    var nextSource = source.slice(0, statePosition) + nextState +
      source.slice(statePosition + 1)

    root.replaceEditorText(nextSource, cursorPosition)
    if (preserveLiveViewport) root.restoreTaskToggleViewport()
    root.noteEdited()

    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      if (selectionStart !== selectionEnd) {
        editor.select(selectionStart, selectionEnd)
      } else {
        editor.cursorPosition = Math.min(cursorPosition, editor.length)
      }
      if (preserveLiveViewport) root.restoreTaskToggleViewport()
      root.syncLiveCursor()
    })
  }

  function restoreTaskToggleViewport() {
    if (!root.taskToggleViewportRestorePending) return
    if (!root.opened || root.rawMode) {
      root.taskToggleViewportRestorePending = false
      root.taskToggleViewportSettledFrames = 0
      taskToggleViewportRestoreTimer.stop()
      return
    }

    editorViewport.contentY = Math.max(0, Math.min(
      Math.max(0, editorViewport.contentHeight - editorViewport.height),
      root.taskToggleViewportY))
    if (!renderedEditor.layoutReady ||
        !renderedEditor.layoutMatchesCurrentInput() ||
        !renderedEditor.viewportGeometrySettled) {
      root.taskToggleViewportSettledFrames = 0
      taskToggleViewportRestoreTimer.restart()
      return
    }

    // TextEdit can publish its final cursor rectangle a frame after the
    // rendered Markdown layout reports settled. Hold the viewport through a
    // few stable frames so that late geometry cannot reveal the old caret.
    if (root.taskToggleViewportSettledFrames < 3) {
      root.taskToggleViewportSettledFrames++
      taskToggleViewportRestoreTimer.restart()
      return
    }
    root.taskToggleViewportRestorePending = false
    root.taskToggleViewportSettledFrames = 0
  }

  function openSaveAs() {
    root.cancelMostRecentOpen()
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.editorCommandOpen = false
    root.fileChooserMode = "saveAs"
    root.fileChooserMessage = ""
    root.saveAsOverwritePath = ""
    root.saveAsOpen = true
    root.saveAsDirectory = root.noteDirectory
    root.saveAsName = root.markdownStemForPath(root.notePath)
    root.loadSaveFolders()
    Qt.callLater(function() {
      if (root.saveAsOpen) saveAsNameField.forceActiveFocus()
    })
  }

  function openFileChooser() {
    root.cancelMostRecentOpen()
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.editorCommandOpen = false
    if (root.openingFile || root.savingAs || root.quickCreating ||
        root.renameInProgress) {
      root.statusText = "Finish the current file operation first"
      return
    }
    root.fileChooserMode = "open"
    root.fileChooserMessage = ""
    root.saveAsOpen = true
    root.saveAsDirectory = root.defaultNotesDirectory
    root.saveAsName = ""
    root.loadOpenNoteFiles()
    root.loadSaveFolders()
    Qt.callLater(function() {
      if (root.saveAsOpen && root.fileChooserMode === "open")
        saveAsNameField.forceActiveFocus()
    })
  }

  function openNewFile() {
    root.cancelMostRecentOpen()
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.editorCommandOpen = false
    root.saveNow()
    if (root.quickCreating || root.savingAs || root.renameInProgress) {
      root.statusText = "Finish the current file operation first"
      return
    }
    root.startQuickCreate()
  }

  function startQuickCreate() {
    root.quickCreating = true
    root.quickCreatedPath = ""
    root.statusText = "Creating note…"
    quickCreateDirectoryProcess.command = ["mkdir", "-p", root.defaultNotesDirectory]
    quickCreateDirectoryProcess.running = true
  }

  function beginLastFileReplacement(path) {
    var closingPath = root.normalizedFilePath(path)
    if (closingPath === "" || closingPath !== root.notePath ||
        root.openFiles.length !== 1 || root.quickCreating || root.savingAs ||
        root.renameInProgress) {
      root.statusText = "Finish the current file operation first"
      return false
    }
    root.replaceLastFilePath = closingPath
    root.startQuickCreate()
    return true
  }

  function failQuickCreate(message) {
    root.quickCreating = false
    root.quickCreatedPath = ""
    root.replaceLastFilePath = ""
    root.statusText = message
  }

  function finishQuickCreate(path) {
    if (!root.quickCreating) return
    var nextPath = root.normalizedFilePath(path)
    if (nextPath === "" || nextPath.charAt(0) !== "/") {
      root.failQuickCreate("Could not create note")
      return
    }

    var closingPath = root.replaceLastFilePath
    root.quickCreating = false
    root.quickCreatedPath = ""
    root.replaceLastFilePath = ""
    root.registerGeneratedUntitledPath(nextPath)
    root.registerRecentFile(nextPath)
    root.switchToFile(nextPath)
    if (closingPath !== "") root.closeFile(closingPath)
    root.statusText = "New note"
  }

  function beginRenameFile(path) {
    var nextPath = root.normalizedFilePath(path)
    if (nextPath === "" ||
        root.renameInProgress || root.quickCreating || root.savingAs) return
    root.renamingPath = nextPath
    root.renameValue = root.markdownStemForPath(nextPath)
  }

  function cancelRenameFile() {
    root.renamingPath = ""
    root.renameValue = ""
  }

  function restoreRename(message) {
    root.pendingRenameCommit = false
    root.renameTargetChecking = false
    root.renameInProgress = false
    root.renamingPath = root.renameOldPath
    root.renameValue = root.markdownStemForPath(root.renameOldPath)
    root.statusText = message
  }

  function startRenameTargetCheck() {
    root.pendingRenameCommit = false
    root.renamingPath = ""
    root.renameTargetChecking = true
    root.statusText = "Renaming…"
    renameTargetCheckProcess.command = ["test", "-e", root.renameNewPath]
    renameTargetCheckProcess.running = true
  }

  function maybeContinuePendingRename() {
    if (!root.pendingRenameCommit || root.renameOldPath !== root.notePath ||
        root.loadingFromFile || root.noteSaveInFlight || root.pendingSave ||
        root.dirty) return
    root.startRenameTargetCheck()
  }

  function commitRenameFile(value) {
    var oldPath = root.normalizedFilePath(root.renamingPath)
    if (oldPath === "" || root.renameInProgress) return

    var nextName = root.markdownFileNameForInput(value)
    if (nextName === "") {
      root.statusText = "Use a Markdown filename ending in .md"
      return
    }

    var nextPath = root.joinPath(root.directoryForPath(oldPath), nextName)
    if (nextPath === oldPath) {
      root.cancelRenameFile()
      return
    }

    root.renameOldPath = oldPath
    root.renameNewPath = nextPath
    root.renameInProgress = true
    if (oldPath === root.notePath && (root.loadingFromFile ||
        root.noteSaveInFlight || root.pendingSave || root.dirty)) {
      root.pendingRenameCommit = true
      root.statusText = "Saving before rename…"
      root.saveNow()
      return
    }
    root.startRenameTargetCheck()
  }

  function finishRenameFile() {
    var oldPath = root.renameOldPath
    var nextPath = root.renameNewPath
    var wasActive = oldPath === root.notePath
    var updated = []

    for (var index = 0; index < root.openFiles.length; index++) {
      var file = root.openFiles[index]
      if (file.path === oldPath) {
        updated.push({ path: nextPath, name: root.fileNameForPath(nextPath) })
      } else {
        updated.push(file)
      }
    }
    root.openFiles = updated
    root.forgetGeneratedUntitledPath(oldPath)
    root.replaceRecentFilePath(oldPath, nextPath)
    root.moveFileEditorState(oldPath, nextPath)
    root.renameInProgress = false
    root.renamingPath = ""
    root.renameValue = ""

    if (wasActive) {
      root.resetRecoveryLoadState()
      root.notePath = nextPath
      root.loadingFromFile = true
      root.noteMissing = false
      root.directoryReady = true
      root.pendingSave = false
      root.dirty = false
      root.statusText = "Loading…"
    } else {
      root.statusText = "Renamed"
    }
    root.schedulePersistedSettingsSave()
  }

  function cancelSaveAs() {
    root.saveAsOpen = false
    root.fileChooserMode = ""
    root.fileChooserMessage = ""
    root.openingFile = false
    root.openingPath = ""
    root.saveAsOverwritePath = ""
    if (!root.savingAs) {
      root.saveAsWritePath = ""
      root.saveAsTempPath = ""
      root.saveAsOverwriteConfirmedPath = ""
    }
  }

  function submitFileChooser(value) {
    var fileName = root.markdownFileNameForInput(value)
    if (fileName === "") {
      root.fileChooserMessage = String(value || "").trim() === ""
        ? "Enter a filename"
        : "Use a Markdown filename ending in .md"
      return
    }

    var selectedPath = root.joinPath(
      root.expandedPath(root.saveAsDirectory), fileName)
    if (root.fileChooserMode === "open")
      root.openFileSelected(selectedPath)
    else root.saveAsSelected(selectedPath)
  }

  function openFileSelected(value) {
    var rawPath = root.expandedPath(root.pathFromUrl(value)).trim()
    var nextPath = root.normalizedMarkdownPath(rawPath, true)
    if (rawPath === "" || rawPath.charAt(0) !== "/") {
      root.fileChooserMessage = "Choose a local Markdown file"
      return
    }
    var lastSlash = rawPath.lastIndexOf("/")
    if (lastSlash < 0 || lastSlash === rawPath.length - 1) {
      root.fileChooserMessage = "Enter a filename"
      return
    }
    if (nextPath === "") {
      root.fileChooserMessage = "Markdown files must end in .md"
      return
    }
    if (openFileCheckProcess.running || root.openingFile) return

    root.openingFile = true
    root.openingPath = nextPath
    root.fileChooserMessage = "Checking file…"
    openFileCheckProcess.command = ["test", "-f", nextPath]
    openFileCheckProcess.running = true
  }

  function beginSaveAs(nextPath, allowOverwrite) {
    root.saveAsOverwritePath = ""
    root.saveAsPath = nextPath
    root.saveAsOverwriteConfirmedPath = allowOverwrite ? nextPath : ""
    root.saveAsWritePath = allowOverwrite ? nextPath : ""
    root.saveAsTempPath = ""
    root.saveAsText = String(editor.text || "")
    root.savingAs = true
    root.saveAsOpen = false
    root.fileChooserMode = ""
    root.statusText = "Saving copy…"
    mkdirProcess.command = ["mkdir", "-p", root.directoryForPath(nextPath)]
    mkdirProcess.running = true
  }

  function confirmSaveAsOverwrite() {
    var nextPath = root.saveAsOverwritePath
    if (nextPath === "" || root.saveAsChecking || root.savingAs) return false
    root.beginSaveAs(nextPath, true)
    return true
  }

  function saveAsSelected(value) {
    root.fileChooserMessage = ""
    var rawPath = root.expandedPath(root.pathFromUrl(value)).trim()
    var nextPath = root.normalizedMarkdownPath(rawPath, true)
    if (rawPath === "" || rawPath.charAt(0) !== "/") {
      root.fileChooserMessage = "Choose a local Markdown file"
      return
    }
    var lastSlash = rawPath.lastIndexOf("/")
    if (lastSlash < 0 || lastSlash === rawPath.length - 1) {
      root.fileChooserMessage = "Enter a filename"
      return
    }
    if (nextPath === "") {
      root.fileChooserMessage = "Markdown files must end in .md"
      return
    }
    if (nextPath === root.notePath) {
      root.saveAsOpen = false
      root.fileChooserMode = ""
      root.saveNow()
      return
    }
    if (mkdirProcess.running || root.savingAs || root.saveAsChecking) {
      root.statusText = "Finish the current save first"
      return
    }
    if (nextPath === root.saveAsOverwritePath) {
      root.fileChooserMessage = "This file already exists. Use Overwrite to replace it."
      return
    }

    root.saveAsOverwritePath = ""
    root.saveAsChecking = true
    root.saveAsCheckPath = nextPath
    root.fileChooserMessage = "Checking destination…"
    saveAsTargetCheckProcess.command = ["test", "-e", nextPath]
    saveAsTargetCheckProcess.running = true
  }

  function finishSaveAs() {
    if (!root.savingAs) return
    var nextPath = root.saveAsPath
    var nextText = root.saveAsText
    var currentText = String(editor.text || "")
    var oldPath = root.notePath
    root.captureActiveEditorState(false)
    root.savingAs = false
    root.addOpenFile(nextPath, false)
    root.registerRecentFile(nextPath)
    root.resetRecoveryLoadState()
    root.adoptedSaveAsPath = nextPath
    root.copyFileEditorState(oldPath, nextPath)
    root.notePath = nextPath
    root.loadingFromFile = true
    root.noteMissing = false
    root.directoryReady = true
    root.pendingSave = false
    root.dirty = currentText !== nextText
    root.markdownSource = currentText
    root.statusText = root.dirty ? "Saving newer edits…" : "Saved"
    root.saveAsWritePath = ""
    root.saveAsTempPath = ""
    root.saveAsOverwriteConfirmedPath = ""
    root.saveAsCleanupPath = ""
    root.saveAsCleanupAfterSuccess = false
    root.schedulePersistedSettingsSave()
    Qt.callLater(function() {
      if (!root.opened || root.notePath !== nextPath) return
      editor.forceActiveFocus()
      root.syncLiveCursor()
    })
  }

  function finishAdoptedSaveAsLoad(loadedPath, loadedSource) {
    if (root.adoptedSaveAsPath === "" ||
        loadedPath !== root.adoptedSaveAsPath) return false

    root.adoptedSaveAsPath = ""
    root.noteMissing = false
    root.directoryReady = true
    root.loadingFromFile = false
    root.noteLoadedPath = loadedPath
    root.restoreEditorStateForSource(loadedPath, editor.text)

    var currentSource = String(editor.text || "")
    root.markdownSource = currentSource
    root.pendingSave = false
    if (currentSource !== loadedSource) {
      root.dirty = true
      root.statusText = "Saving newer edits…"
      Qt.callLater(function() {
        if (root.notePath !== loadedPath || !root.dirty) return
        root.saveNow()
      })
    } else {
      root.dirty = false
      root.statusText = "Saved"
      root.requestRecoveryDelete(loadedPath)
    }
    root.maybeContinuePendingClose()
    root.focusEditorAfterFileLoad(loadedPath)
    return true
  }

  function open(payloadJson) {
    var alreadyOpened = root.opened
    var hasArguments = root.hasSummonArguments(payloadJson)
    if (alreadyOpened && !hasArguments &&
        root.isJotPinOnFocusedWorkspace()) {
      root.pendingWorkspaceName = ""
      root.dismiss()
      return
    }

    root.pendingWorkspaceName = root.hyprlandWorkspaceName(
      root.focusedHyprlandWorkspace())
    root.applyPayload(payloadJson)
    if (root.presentationSettingsLoaded) root.addOpenFile(root.notePath)
    root.opened = true

    // A missing file is created after both the note and its recovery snapshot
    // have been checked, so a crash recovery is never overwritten first.
    if (root.noteMissing) root.checkRecoveryCandidate()

    workspaceRelocationTimer.restart()
    Qt.callLater(function() {
      if (!root.opened) return
      var relocated = root.moveJotPinToFocusedWorkspace()
      if (relocated || root.pendingWorkspaceName === "") {
        editor.forceActiveFocus()
      }
    })
  }

  // Called by the shell when the openPanelIds entry is removed. Do not request
  // another hide here: the host already owns that state transition.
  function close() {
    root.captureActiveEditorState(false)
    root.saveNow()
    root.schedulePersistedSettingsSave()
    root.scheduleEditorStatesWrite()
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.shortcutHelpOpen = false
    root.editorCommandOpen = false
    root.settingsOpen = false
    root.opened = false
    root.pendingWorkspaceName = ""
  }

  function dismiss() {
    root.captureActiveEditorState(false)
    root.saveNow()
    root.schedulePersistedSettingsSave()
    root.scheduleEditorStatesWrite()
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.shortcutHelpOpen = false
    root.editorCommandOpen = false
    root.settingsOpen = false
    root.opened = false
    root.pendingWorkspaceName = ""
    var host = root.activeHostIntegration
    if (host && typeof host.hidePanel === "function") host.hidePanel()
  }

  function toggle() {
    root.open("{}")
  }

  function toggleShortcutHelp() {
    root.closeFileMenu()
    root.closeEditorContextMenu()
    root.editorCommandOpen = false
    root.shortcutHelpOpen = !root.shortcutHelpOpen
  }

  function toggleRaw() {
    root.captureActiveEditorState(false)
    root.resetLiveVerticalNavigation()
    renderedEditor.clearImageSelection()
    var sourceCaret = root.caretRectangleForView(
      root.rawMode, editor.cursorPosition)
    var viewportCaretY = sourceCaret
      ? Number(sourceCaret.y) - Number(editorViewport.contentY) : NaN
    if (!isFinite(viewportCaretY) || viewportCaretY < 0 ||
        viewportCaretY + Number(sourceCaret ? sourceCaret.height : 0) >
          Number(editorViewport.height)) {
      viewportCaretY = Math.max(0, (Number(editorViewport.height) -
        Number(sourceCaret ? sourceCaret.height : 0)) / 2)
    }
    root.rawMode = !root.rawMode
    root.pendingViewCaretRawMode = root.rawMode
    root.pendingViewCaretPosition = Number(editor.cursorPosition) || 0
    root.pendingViewCaretViewportY = viewportCaretY
    root.pendingViewCaretAlignmentAttempts = 0
    root.viewCaretAlignmentPending = true
    Qt.callLater(function() {
      if (!root.opened) return
      editor.forceActiveFocus()
      root.finishPendingViewCaretAlignment()
    })
  }

  function caretRectangleForView(rawView, sourcePosition) {
    if (rawView) return editor.cursorRectangle
    if (String(editor.text || "") === "") return editor.cursorRectangle
    if (!renderedEditor.layoutReady ||
        !renderedEditor.layoutMatchesCurrentInput()) return null
    return renderedEditor.cursorRectangleForSource(sourcePosition)
  }

  function finishPendingViewCaretAlignment() {
    if (!root.viewCaretAlignmentPending) return
    if (!root.opened || root.loadingFromFile ||
        root.rawMode !== root.pendingViewCaretRawMode) {
      root.viewCaretAlignmentPending = false
      return
    }
    var caret = root.caretRectangleForView(
      root.rawMode, root.pendingViewCaretPosition)
    if (!caret) {
      root.pendingViewCaretAlignmentAttempts++
      if (root.pendingViewCaretAlignmentAttempts < 120)
        viewCaretAlignmentTimer.restart()
      else root.viewCaretAlignmentPending = false
      return
    }
    var maximumContentY = Math.max(0,
      editorViewport.contentHeight - editorViewport.height)
    editorViewport.contentY = Math.max(0, Math.min(maximumContentY,
      Number(caret.y) - root.pendingViewCaretViewportY))
    root.viewCaretAlignmentPending = false
    root.pendingViewCaretPosition = -1
    root.pendingViewCaretAlignmentAttempts = 0
    root.captureActiveEditorState(false)
    editorStateSaveTimer.restart()
    root.syncLiveCursor()
  }

  function ensureEditorCursorVisible(force) {
    if (!root.opened || root.taskToggleViewportRestorePending ||
        (!editor.activeFocus && !force)) return
    var cursor = editor.cursorRectangle
    if (!root.rawMode && String(editor.text || "") !== "" &&
        renderedEditor.layoutReady &&
        renderedEditor.layoutMatchesCurrentInput()) {
      // Live Markdown hides source markers and uses its own line metrics. A
      // click is already positioned in this rendered coordinate space, so do
      // not let the transparent plain-text editor move the viewport to its
      // different source-layout Y position.
      var renderedCursor = renderedEditor.cursorRectangleForSource(
        editor.cursorPosition)
      if (renderedCursor) cursor = renderedCursor
    }
    var top = editorViewport.contentY
    var bottom = top + editorViewport.height
    if (cursor.y < top) editorViewport.contentY = Math.max(0, cursor.y)
    else if (cursor.y + cursor.height > bottom) {
      editorViewport.contentY = Math.min(
        Math.max(0, editorViewport.contentHeight - editorViewport.height),
        cursor.y + cursor.height - editorViewport.height)
    }
  }

  function failSaveAs(message) {
    if (root.saveAsTempPath !== "") {
      root.saveAsCleanupPath = root.saveAsTempPath
      root.saveAsCleanupAfterSuccess = false
      saveAsTempCleanupProcess.command = ["rm", "-f", "--",
        root.saveAsTempPath]
      saveAsTempCleanupProcess.running = true
    }
    root.savingAs = false
    root.saveAsWritePath = ""
    root.saveAsTempPath = ""
    root.saveAsOverwriteConfirmedPath = ""
    root.statusText = message
  }

  function createSaveAsTempFile() {
    if (!root.savingAs || root.saveAsPath === "") return
    saveAsTempCreateProcess.command = [
      "mktemp", "--tmpdir=" + root.directoryForPath(root.saveAsPath),
      ".jotpin-save-XXXXXX"
    ]
    saveAsTempCreateProcess.running = true
  }

  readonly property real editorWheelScrollFactor: 2.5

  function scrollEditorByWheel(delta) {
    var maximumContentY = Math.max(0,
      editorViewport.contentHeight - editorViewport.height)
    var amount = Number(delta)
    if (!isFinite(amount) || amount === 0) return
    editorViewport.contentY = Math.max(0, Math.min(maximumContentY,
      editorViewport.contentY - amount * root.editorWheelScrollFactor))
  }

  function markdownGapTarget(direction) {
    if (root.rawMode || direction === 0) return -1

    var source = String(editor.text || "")
    var position = Math.max(0,
      Math.min(Number(editor.cursorPosition) || 0, source.length))
    var lineStart = source.lastIndexOf("\n", Math.max(0, position - 1)) + 1
    var lineEnd = source.indexOf("\n", position)
    if (lineEnd < 0) lineEnd = source.length
    var column = Math.max(0, position - lineStart)
    var candidateStart = -1
    var candidateEnd = -1

    if (direction > 0) {
      if (lineEnd >= source.length) return -1
      candidateStart = lineEnd + 1
      candidateEnd = source.indexOf("\n", candidateStart)
      if (candidateEnd < 0) candidateEnd = source.length
    } else {
      if (lineStart <= 0) return -1
      candidateEnd = lineStart - 1
      candidateStart = source.lastIndexOf("\n",
        Math.max(0, candidateEnd - 1)) + 1
    }

    // A blank source line is an editable row. Stop on the adjacent row so
    // Up/Down can enter it instead of skipping over it to the next paragraph.
    if (!/^\s*$/.test(source.slice(candidateStart, candidateEnd))) return -1
    return candidateStart + Math.min(column, candidateEnd - candidateStart)
  }

  function horizontalListBoundaryTarget(direction) {
    var source = String(editor.text || "")
    return EditorModel.horizontalListBoundaryTarget(
      source, editor.cursorPosition, direction, root.rawMode,
      editor.selectionStart, editor.selectionEnd)
  }

  function moveAcrossMarkdownGap(direction, extendSelection) {
    var target = root.markdownGapTarget(direction)
    if (target < 0) return false

    if (extendSelection) {
      editor.moveCursorSelection(target, TextEdit.SelectCharacters)
    } else {
      editor.cursorPosition = target
    }
    return true
  }

  function resetLiveVerticalNavigation() {
    root.liveVerticalNavigationX = -1
  }

  function moveLiveCursorVertically(direction, extendSelection) {
    if (root.rawMode || !renderedEditor.layoutReady ||
        !renderedEditor.layoutMatchesCurrentInput()) return false

    var currentPosition = Number(editor.cursorPosition) || 0
    var currentCaret = renderedEditor.cursorRectangleForSource(currentPosition)
    if (!currentCaret) return false
    if (root.liveVerticalNavigationX < 0) {
      root.liveVerticalNavigationX = Number(currentCaret.x) +
        Number(currentCaret.width) / 2
    }
    var target = renderedEditor.verticalNavigationTarget(
      currentPosition, root.liveVerticalNavigationX, direction)
    if (target < 0 || target === currentPosition) return false

    if (extendSelection) {
      editor.moveCursorSelection(target, TextEdit.SelectCharacters)
    } else {
      editor.cursorPosition = target
    }
    return true
  }

  function syncLiveCursor() {
    if (!root.opened || root.screensaverActive || root.rawMode ||
        !editor.activeFocus) {
      root.liveCursorRect = Qt.rect(0, 0, 1, 0)
      root.liveCursorVisible = false
      root.liveCursorSourcePosition = -1
      liveCursorBlink.stop()
      return
    }

    var requestedPosition = Number(editor.cursorPosition)
    if (!renderedEditor.layoutReady ||
        renderedEditor.layoutSourceText !== String(editor.text || "") ||
        Number(renderedEditor.layoutCursorPosition) !== requestedPosition) {
      // An optimistic edit or authoritative Markdown reconciliation can make
      // geometry unavailable for part of one frame. Keep the last valid caret
      // painted until the matching layout arrives instead of flashing it off.
      return
    }

    var emptySource = String(editor.text || "").length === 0
    var next = emptySource
      ? editor.cursorRectangle
      : renderedEditor.cursorRectangleForSource(requestedPosition)
    if (!next) {
      // Retain the last valid rectangle across a transient Qt layout miss.
      // A later layoutUpdated signal or settle timer retries synchronization.
      return
    }
    root.liveCursorRect = Qt.rect(
      next.x,
      next.y,
      Math.max(1, next.width),
      Math.max(1, next.height))
    root.liveCursorVisible = true
    root.liveCursorSourcePosition = requestedPosition
    liveCursorBlink.restart()
  }

  function togglePresentation() {
    root.setPresentationMode(root.sideMode ? "window" : "side")
  }

  function toggleMaximized() {
    var target = root.sideMode ? sideWindow : centerWindow
    if (!target) return

    var nextState = !root.activeWindowMaximized
    root.maximizeStateRequested = nextState
    root.maximizeStatePending = true
    root.maximizeStateRequestedAt = Date.now()
    root.hyprlandWindowStateRevision++
    maximizeStateTimer.restart()

    var toplevel = root.jotpinHyprlandToplevel()
    var address = root.hyprlandWindowAddress(toplevel)
    if (address === "") {
      var hasLiveToplevels = false
      try {
        hasLiveToplevels = (Hyprland.toplevels.values || []).length > 0
      } catch (e) {
      }
      // Keep the offscreen harness usable when there is no compositor model,
      // but do not claim success for a live window that is not ready yet.
      if (hasLiveToplevels) {
        root.maximizeStatePending = false
        root.statusText = "Full Screen is not ready yet"
        maximizeStateTimer.stop()
        return
      }
      target.maximized = nextState
      root.maximizeStateObserved = nextState
      root.maximizeStatePending = false
      root.hyprlandWindowStateRevision++
      maximizeStateTimer.stop()
      Qt.callLater(root.syncFocusMode)
      return
    }

    try {
      Hyprland.dispatch("hl.dsp.window.fullscreen({ mode = " +
        root.luaString("maximized") + ", window = " +
        root.luaString("address:" + address) + " })")
    } catch (e) {
      root.maximizeStatePending = false
      maximizeStateTimer.stop()
      root.statusText = "Could not change window size"
      return
    }
    Qt.callLater(root.syncFocusMode)
  }

  function syncFocusMode() {
    if (!root.opened || root.screensaverActive) return
    if (root.pendingWorkspaceName !== "") return
    Qt.callLater(function() {
      if (root.opened && !root.screensaverActive) editor.forceActiveFocus()
    })
  }

  function resetRecoveryLoadState() {
    root.noteLoadedPath = ""
    root.recoveryLoadedPath = ""
    root.recoveryHasSnapshot = false
    root.recoverySnapshotNotePath = ""
    root.recoverySnapshotSource = ""
    root.recoveryPromptPath = ""
    root.recoveryPromptSource = ""
    root.recoveryPromptOpen = false
  }

  function checkRecoveryCandidate() {
    if (root.loadingFromFile || root.noteLoadedPath !== root.notePath ||
        root.recoveryLoadedPath !== root.recoveryPath) return

    var currentSource = String(root.markdownSource || "")
    var validSnapshot = root.recoveryHasSnapshot &&
      root.recoverySnapshotNotePath === root.notePath
    if (!validSnapshot || root.recoverySnapshotSource === currentSource) {
      var shouldDelete = validSnapshot
      root.recoveryPromptOpen = false
      root.recoveryPromptPath = ""
      root.recoveryPromptSource = ""
      if (shouldDelete) root.requestRecoveryDelete(root.notePath)
      return
    }

    root.recoveryPromptPath = root.notePath
    root.recoveryPromptSource = root.recoverySnapshotSource
    root.recoveryPromptOpen = true
    root.statusText = "Recovery available"
  }

  function loadRecoverySnapshot(rawValue) {
    var loadedPath = String(recoveryFile.path || "")
    root.recoveryLoadedPath = loadedPath
    root.recoveryHasSnapshot = false
    root.recoverySnapshotNotePath = ""
    root.recoverySnapshotSource = ""

    var raw = String(rawValue || "")
    if (raw !== "") {
      try {
        var snapshot = JSON.parse(raw)
        if (snapshot && Number(snapshot.version) === 1 &&
            typeof snapshot.notePath === "string" &&
            typeof snapshot.source === "string") {
          root.recoveryHasSnapshot = true
          root.recoverySnapshotNotePath = snapshot.notePath
          root.recoverySnapshotSource = snapshot.source
        }
      } catch (error) {
        // A partial recovery file is not offered as editable note content.
      }
    }
    root.checkRecoveryCandidate()
  }

  function ensureRecoveryDirectory() {
    if (root.recoveryDirectoryReady || recoveryDirectoryProcess.running) return
    recoveryDirectoryProcess.command = ["mkdir", "-p", root.recoveryDirectory]
    recoveryDirectoryProcess.running = true
  }

  function writeRecoverySnapshot() {
    if (!root.dirty || root.loadingFromFile || !root.opened) {
      root.recoveryWritePending = false
      return
    }

    root.recoveryWritePending = true
    if (root.recoveryWriteInFlight) return
    // An already running rm cannot be cancelled by removing its queue entry.
    // Finish that deletion before writing a newer snapshot to the same path.
    if (root.recoveryDeletePath === root.recoveryPath &&
        recoveryCleanupProcess.running) return

    root.recoveryWritePath = root.recoveryPath
    root.recoveryWriteNotePath = root.notePath
    root.recoveryWriteSource = String(root.markdownSource || editor.text || "")
    if (!root.recoveryDirectoryReady) {
      root.ensureRecoveryDirectory()
      return
    }

    root.recoveryWritePending = false
    root.recoveryWriteInFlight = true
    recoveryFile.setText(JSON.stringify({
      version: 1,
      notePath: root.recoveryWriteNotePath,
      capturedAt: Date.now(),
      source: root.recoveryWriteSource
    }))
  }

  function enqueueRecoveryDeletePath(path) {
    var target = String(path || "")
    if (target === "") return
    var queue = root.recoveryDeleteQueue.slice()
    if (queue.indexOf(target) < 0) queue.push(target)
    root.recoveryDeleteQueue = queue
    root.startRecoveryDelete()
  }

  function requestRecoveryDelete(path) {
    var target = root.recoveryPathFor(path)
    if (root.recoveryWriteInFlight && root.recoveryWritePath === target) {
      var deferred = root.recoveryDeletesAfterWrite.slice()
      if (deferred.indexOf(target) < 0) deferred.push(target)
      root.recoveryDeletesAfterWrite = deferred
      return
    }
    root.enqueueRecoveryDeletePath(target)
  }

  function cancelRecoveryDelete(path) {
    var target = root.recoveryPathFor(path)
    var queue = root.recoveryDeleteQueue.slice()
    var filteredQueue = []
    for (var index = 0; index < queue.length; index++) {
      if (queue[index] !== target) filteredQueue.push(queue[index])
    }
    root.recoveryDeleteQueue = filteredQueue

    var deferred = root.recoveryDeletesAfterWrite.slice()
    var filteredDeferred = []
    for (var deferredIndex = 0; deferredIndex < deferred.length;
         deferredIndex++) {
      if (deferred[deferredIndex] !== target) {
        filteredDeferred.push(deferred[deferredIndex])
      }
    }
    root.recoveryDeletesAfterWrite = filteredDeferred
  }

  function startRecoveryDelete() {
    if (recoveryCleanupProcess.running ||
        root.recoveryDeleteQueue.length === 0) return
    root.recoveryDeletePath = root.recoveryDeleteQueue[0]
    recoveryCleanupProcess.command = ["rm", "-f", "--",
      root.recoveryDeletePath]
    recoveryCleanupProcess.running = true
  }

  function recoverSnapshot() {
    if (!root.recoveryPromptOpen || root.recoveryPromptPath !== root.notePath) return
    var recoveredSource = root.recoveryPromptSource
    root.recoveryPromptOpen = false
    root.recoveryPromptPath = ""
    root.recoveryPromptSource = ""
    root.noteMissing = false
    root.replaceEditorText(recoveredSource, recoveredSource.length)
    root.noteEdited()
    root.saveNow()
  }

  function discardRecovery() {
    if (!root.recoveryPromptOpen) return
    var discardedPath = root.recoveryPromptPath
    var wasMissing = root.noteMissing
    root.recoveryPromptOpen = false
    root.recoveryPromptPath = ""
    root.recoveryPromptSource = ""
    root.recoveryHasSnapshot = false
    root.recoverySnapshotNotePath = ""
    root.recoverySnapshotSource = ""
    root.requestRecoveryDelete(discardedPath)
    if (!root.dirty) root.statusText = wasMissing ? "File missing" : "Saved"
  }

  function noteSaveCompleted() {
    var savedPath = root.pendingNoteSavePath
    var savedSource = root.pendingNoteSaveSource
    root.pendingNoteSavePath = ""
    root.pendingNoteSaveSource = ""
    root.noteSaveInFlight = false
    if (savedPath === "") return
    root.knownDiskPath = savedPath
    root.knownDiskSource = savedSource

    var currentSource = String(editor.text || "")
    var isCurrentSave = savedPath === root.notePath && !root.loadingFromFile
    if (isCurrentSave && currentSource === savedSource) {
      root.pendingSave = false
      root.dirty = false
      root.statusText = "Saved"
      root.requestRecoveryDelete(savedPath)
    } else if (isCurrentSave) {
      root.dirty = true
      root.statusText = "Saving…"
      saveTimer.restart()
    } else {
      root.requestRecoveryDelete(savedPath)
      if (!root.loadingFromFile && (root.pendingSave || root.dirty)) {
        saveTimer.restart()
      }
    }
    root.maybeContinuePendingClose()
    root.maybeContinuePendingSwitch()
    root.maybeContinuePendingRename()
  }

  function noteEdited() {
    if (root.editorUpdating || root.loadingFromFile) return
    root.cancelRecoveryDelete(root.notePath)
    root.markdownSource = String(editor.text || "")
    if (!root.noteSaveInFlight && root.notePath === root.knownDiskPath &&
        root.markdownSource === root.knownDiskSource) {
      root.pendingSave = false
      root.dirty = false
      root.statusText = "Saved"
      saveTimer.stop()
      recoveryTimer.stop()
      root.requestRecoveryDelete(root.notePath)
      return
    }
    root.dirty = true
    root.statusText = "Saving…"
    saveTimer.restart()
    if (!recoveryTimer.running) recoveryTimer.start()
  }

  function saveNow() {
    if (saveTimer) saveTimer.stop()
    if (root.externalConflict) {
      root.statusText = "Resolve the external change before saving"
      return
    }
    if (root.loadingFromFile) return
    if (!root.dirty && !root.pendingSave) {
      if (recoveryTimer) recoveryTimer.stop()
      return
    }
    root.ensureDirectory()
  }

  function ensureDirectory() {
    root.pendingSave = true
    if (root.directoryReady) {
      root.writeNote()
      return
    }
    if (mkdirProcess.running) return

    mkdirProcess.command = ["mkdir", "-p", root.noteDirectory]
    mkdirProcess.running = true
  }

  function writeNote() {
    if (!root.pendingSave && !root.dirty) return
    if (root.noteSaveInFlight) {
      root.pendingSave = true
      return
    }
    var savedPath = root.notePath
    var savedSource = String(root.markdownSource || "")
    root.pendingSave = false
    root.noteSaveInFlight = true
    root.pendingNoteSavePath = savedPath
    root.pendingNoteSaveSource = savedSource
    noteFile.setText(savedSource)
    root.noteMissing = false
    root.statusText = "Saving…"

    // Saving updates the FileView, not the editor. Reapplying a captured
    // cursor on the next event-loop turn can overwrite a newer selection.

  }

  function createNewNote() {
    if (!root.noteMissing || root.loadingFromFile) return
    root.noteLoadError = ""
    root.statusText = "New note"
    root.pendingSave = true
    root.ensureDirectory()
  }

  function finishNoteLoadFailure(failedPath, error) {
    if (failedPath === "" || failedPath !== root.notePath) return

    root.markdownSource = ""
    root.setEditorText("")
    root.dirty = false
    root.pendingSave = false
    root.directoryReady = false
    root.noteLoadedPath = failedPath
    root.noteMissing = error === FileViewError.FileNotFound
    root.noteLoadError = root.noteMissing ? "missing" : "unreadable"
    root.statusText = root.noteMissing
      ? "File missing — create it or Save As"
      : "Could not read note"
    if (root.pendingRecentPromotionPath === failedPath)
      root.pendingRecentPromotionPath = ""
    root.forgetRecentFile(failedPath)
    root.loadingFromFile = false
    root.restoreEditorStateForSource(failedPath, "")
    root.continueMostRecentAfterFailure(failedPath)
    root.checkRecoveryCandidate()
    root.maybeContinuePendingClose()
    root.maybeContinuePendingSwitch()
  }

  function observeExternalFileChange() {
    if (root.notePath === "" || root.externalReloadPending ||
        root.loadingFromFile || root.noteLoadError !== "") return
    root.externalReloadPending = true
    root.externalReloadPath = root.notePath
    noteFile.reload()
  }

  function handleExternalReload(loadedPath, loadedSource) {
    if (!root.externalReloadPending ||
        loadedPath !== root.externalReloadPath) return false
    root.externalReloadPending = false
    root.externalReloadPath = ""

    var expectedInFlight = root.noteSaveInFlight &&
      loadedPath === root.pendingNoteSavePath &&
      loadedSource === root.pendingNoteSaveSource
    if ((loadedPath === root.knownDiskPath &&
         loadedSource === root.knownDiskSource) || expectedInFlight) {
      root.knownDiskPath = loadedPath
      root.knownDiskSource = loadedSource
      return true
    }

    var currentSource = String(editor.text || "")
    if (currentSource === loadedSource) {
      root.knownDiskPath = loadedPath
      root.knownDiskSource = loadedSource
      root.externalConflict = false
      return true
    }

    if (root.dirty || root.pendingSave || root.noteSaveInFlight) {
      saveTimer.stop()
      root.externalConflict = true
      root.externalConflictMissing = false
      root.externalConflictPath = loadedPath
      root.externalConflictSource = loadedSource
      root.statusText = "External change conflict"
      return true
    }

    root.knownDiskPath = loadedPath
    root.knownDiskSource = loadedSource
    root.markdownSource = loadedSource
    root.clearEditorHistoryForPath(loadedPath, false)
    root.setEditorText(loadedSource)
    root.restoreEditorStateForSource(loadedPath, loadedSource)
    root.dirty = false
    root.pendingSave = false
    root.statusText = "Reloaded external change"
    return true
  }

  function keepMineAfterExternalChange() {
    if (!root.externalConflict || root.externalConflictPath !== root.notePath)
      return false
    root.knownDiskPath = root.notePath
    root.knownDiskSource = root.externalConflictSource
    root.externalConflict = false
    root.externalConflictMissing = false
    root.externalConflictPath = ""
    root.externalConflictSource = ""
    root.dirty = true
    root.statusText = "Saving…"
    root.saveNow()
    return true
  }

  function reloadAfterExternalChange() {
    if (!root.externalConflict || root.externalConflictMissing ||
        root.externalConflictPath !== root.notePath) return false
    var diskSource = root.externalConflictSource
    root.externalConflict = false
    root.externalConflictPath = ""
    root.externalConflictSource = ""
    root.knownDiskPath = root.notePath
    root.knownDiskSource = diskSource
    root.markdownSource = diskSource
    root.clearEditorHistoryForPath(root.notePath, false)
    root.setEditorText(diskSource)
    root.restoreEditorStateForSource(root.notePath, diskSource)
    root.dirty = false
    root.pendingSave = false
    root.statusText = "Reloaded external change"
    root.requestRecoveryDelete(root.notePath)
    return true
  }

  FileView {
    id: noteFile
    // Session settings own the initial active tab. Starting the default-note
    // read before they hydrate can replace its path mid-operation, which may
    // make Quickshell drop the operation without a completion signal.
    path: root.presentationSettingsLoaded ? root.notePath : ""
    atomicWrites: true
    watchChanges: true
    printErrors: false

    onLoaded: {
      if (!root.presentationSettingsLoaded || noteFile.path === "") return
      var loadedPath = String(noteFile.path || root.notePath)
      var loadedSource = String(text() || "")
      if (root.handleExternalReload(loadedPath, loadedSource)) return
      if (root.finishAdoptedSaveAsLoad(loadedPath, loadedSource)) return
      root.loadingFromFile = true
      root.noteMissing = false
      root.noteLoadError = ""
      root.directoryReady = true
      root.knownDiskPath = loadedPath
      root.knownDiskSource = loadedSource
      root.markdownSource = loadedSource
      root.setEditorText(root.markdownSource, false, false, true)
      root.dirty = false
      root.pendingSave = false
      root.statusText = "Saved"
      root.loadingFromFile = false
      root.noteLoadedPath = loadedPath
      root.restoreEditorStateForSource(loadedPath, loadedSource)
      if (root.pendingRecentPromotionPath === loadedPath) {
        root.pendingRecentPromotionPath = ""
        root.registerRecentFile(loadedPath)
      }
      root.finishMostRecentOpen(loadedPath)
      root.checkRecoveryCandidate()
      root.maybeContinuePendingClose()
      root.maybeContinuePendingSwitch()
      root.focusEditorAfterFileLoad(loadedPath)
    }

    onLoadFailed: function(error) {
      if (!root.presentationSettingsLoaded || noteFile.path === "") return
      if (root.externalReloadPending) {
        var changedPath = root.externalReloadPath
        root.externalReloadPending = false
        root.externalReloadPath = ""
        if (changedPath === root.notePath) {
          saveTimer.stop()
          root.forgetRecentFile(changedPath)
          root.externalConflict = true
          root.externalConflictMissing = true
          root.externalConflictPath = changedPath
          root.externalConflictSource = ""
          root.statusText = "Note changed or was removed on disk"
        }
        return
      }
      root.finishNoteLoadFailure(
        String(noteFile.path || root.notePath), error)
    }

    onSaved: root.noteSaveCompleted()

    onFileChanged: externalFileChangeTimer.restart()

    onSaveFailed: {
      var failedPath = root.pendingNoteSavePath
      root.noteSaveInFlight = false
      root.pendingNoteSavePath = ""
      root.pendingNoteSaveSource = ""
      if (failedPath === root.notePath) {
        if (root.pendingRenameCommit && root.renameOldPath === failedPath)
          root.restoreRename("Could not save before rename")
        if (root.pendingClosePath === failedPath) root.pendingClosePath = ""
        root.dirty = true
        root.statusText = "Could not save note"
        if (!recoveryTimer.running) recoveryTimer.start()
      }
    }
  }

  FileView {
    id: presentationSettingsFile
    path: root.presentationSettingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false

    onLoaded: root.loadPresentationSettings(String(text() || ""))
    onLoadFailed: root.loadPresentationSettings("")

    // FileView emits saved before clearing its active operation. Starting
    // another write inside that signal can reenter the completed operation.
    onSaved: Qt.callLater(function() {
      root.presentationSettingsWriteInFlight = false
      if (root.presentationSettingsWritePending) root.writePresentationSettings()
    })

    onSaveFailed: {
      root.presentationSettingsWriteInFlight = false
      root.presentationSettingsWritePending = true
    }
  }

  FileView {
    id: personalDictionaryFile
    path: root.personalDictionaryPath
    watchChanges: false
    atomicWrites: true
    printErrors: false

    onLoaded: root.loadPersonalDictionary(String(text() || ""))
    onLoadFailed: root.loadPersonalDictionary("")

    // FileView emits saved before clearing its active operation. Starting
    // another write inside that signal can reenter the completed operation.
    onSaved: Qt.callLater(function() {
      root.personalDictionaryWriteInFlight = false
      if (root.personalDictionaryWritePending) root.writePersonalDictionary()
    })

    onSaveFailed: {
      root.personalDictionaryWriteInFlight = false
      root.personalDictionaryWritePending = true
    }
  }

  WorkerScript {
    id: spellcheckWorker
    source: Qt.resolvedUrl("spellcheck/SpellcheckWorker.js")

    onReadyChanged: root.flushSpellcheckInitialization()

    onMessage: function(message) {
      var type = String(message.type || "")
      if (type === "ready") {
        if (!root.spellcheckEnabled) return
        root.spellcheckReady = true
        root.scheduleSpellcheck()
      } else if (type === "checked") {
        if (!root.spellcheckEnabled ||
            Number(message.requestId) !== root.spellcheckRequestId ||
            Number(message.sourceRevision) !== root.spellcheckSourceRevision)
          return
        var checkedCandidates = Array.isArray(message.candidates)
          ? message.candidates : []
        // Accept only ranges tied exactly to the worker's extracted candidate
        // sequence. Candidate extraction and dictionary checks both stay off
        // the UI thread, while malformed ranges still cannot reach geometry.
        root.misspellings = SpellcheckModel.validatedMisspellings(
          checkedCandidates, message.misspellings)
        root.spellcheckCheckedCandidates = checkedCandidates
        root.spellcheckPendingCandidates = []
        root.spellcheckHasCheckedCandidates = true
        root.spellcheckLastMetrics = message.metrics || ({})
        root.spellingGeometryDeferred = false
        root.queueSpellingGeometryUpdate(true)
      } else if (type === "resync") {
        if (!root.spellcheckEnabled ||
            Number(message.requestId) !== root.spellcheckRequestId ||
            Number(message.sourceRevision) !== root.spellcheckSourceRevision)
          return
        root.spellcheckNeedsFullCheck = true
        root.spellcheckPendingEdits = []
        root.scheduleSpellcheck()
      } else if (type === "suggestions") {
        if (Number(message.requestId) !== root.spellcheckSuggestionRequestId)
          return
        root.spellingContextSuggestions = Array.isArray(message.suggestions)
          ? message.suggestions : []
        root.spellingSuggestionsPending = false
      } else if (type === "wordChanged") {
        root.clearSpellcheckCandidateState()
        root.scheduleSpellcheck()
      }
    }
  }

  FileView {
    id: editorStatesFile
    path: root.editorStatesPath
    watchChanges: false
    atomicWrites: true
    printErrors: false

    onLoaded: root.loadEditorStates(String(text() || ""))
    onLoadFailed: root.loadEditorStates("")

    // FileView emits saved before clearing its active operation. Starting
    // another write inside that signal can reenter the completed operation.
    onSaved: Qt.callLater(function() {
      root.editorStatesWriteInFlight = false
      if (root.editorStatesWritePending) root.writeEditorStates()
    })

    onSaveFailed: {
      root.editorStatesWriteInFlight = false
      root.editorStatesWritePending = true
    }
  }

  FileView {
    id: recoveryFile
    path: root.recoveryPath
    atomicWrites: true
    printErrors: false

    onLoaded: root.loadRecoverySnapshot(String(text() || ""))

    onLoadFailed: root.loadRecoverySnapshot("")

    // Keep queued snapshots outside FileView's completion signal stack.
    onSaved: Qt.callLater(function() {
      var savedPath = root.recoveryWritePath
      var savedNotePath = root.recoveryWriteNotePath
      var savedSource = root.recoveryWriteSource
      root.recoveryWriteInFlight = false
      if (savedPath === root.recoveryPath &&
          savedNotePath === root.notePath) {
        root.recoveryLoadedPath = savedPath
        root.recoveryHasSnapshot = true
        root.recoverySnapshotNotePath = savedNotePath
        root.recoverySnapshotSource = savedSource
      }

      var deferred = root.recoveryDeletesAfterWrite.slice()
      var deleteAfterWrite = deferred.indexOf(savedPath) >= 0
      if (deleteAfterWrite) {
        deferred.splice(deferred.indexOf(savedPath), 1)
        root.recoveryDeletesAfterWrite = deferred
        root.enqueueRecoveryDeletePath(savedPath)
      }
      if (root.recoveryWritePending && root.dirty && root.opened) {
        root.writeRecoverySnapshot()
      }
    })

    onSaveFailed: Qt.callLater(function() {
      root.recoveryWriteInFlight = false
      if (root.recoveryWritePending && root.dirty && root.opened) {
        root.writeRecoverySnapshot()
      }
    })
  }

  Process {
    id: presentationSettingsDirectoryProcess

    onExited: function(exitCode) {
      root.presentationSettingsDirectoryReady = exitCode === 0
      if (root.presentationSettingsDirectoryReady) {
        root.writePresentationSettings()
        root.writeEditorStates()
        root.writePersonalDictionary()
      }
    }
  }

  Process {
    id: defaultNotesDirectoryProcess

    onExited: function(exitCode) {
      if (!root.settingsDirectoryChangeInFlight) return
      var nextPath = root.settingsDirectoryChangePath
      root.settingsDirectoryChangePath = ""
      root.settingsDirectoryChangeInFlight = false
      if (exitCode !== 0) {
        root.settingsMessage = "Could not create the default notes folder"
        return
      }

      root.defaultNotesDirectory = nextPath
      if (!root.presentationSettingsLoaded)
        root.pendingNotesDirectory = nextPath
      root.settingsDefaultNotesDirectory = nextPath
      root.settingsMessage = "Default notes folder updated"
      root.schedulePersistedSettingsSave()
      if (root.saveAsOpen && root.fileChooserMode === "open") {
        root.saveAsDirectory = nextPath
        root.loadOpenNoteFiles()
        root.loadSaveFolders()
      }
    }
  }

  Process {
    id: recoveryDirectoryProcess

    onExited: function(exitCode) {
      root.recoveryDirectoryReady = exitCode === 0
      if (root.recoveryDirectoryReady && root.recoveryWritePending) {
        root.writeRecoverySnapshot()
      }
    }
  }

  Process {
    id: recoveryCleanupProcess

    onExited: function(exitCode) {
      var completedPath = root.recoveryDeletePath
      var queue = root.recoveryDeleteQueue.slice()
      if (queue.length > 0 && queue[0] === completedPath) queue.shift()
      root.recoveryDeleteQueue = queue
      if (exitCode === 0 && completedPath === root.recoveryPath &&
          !root.recoveryWriteInFlight) {
        root.recoveryHasSnapshot = false
        root.recoverySnapshotNotePath = ""
        root.recoverySnapshotSource = ""
      }
      root.recoveryDeletePath = ""
      root.startRecoveryDelete()
      if (root.recoveryWritePending)
        Qt.callLater(root.writeRecoverySnapshot)
    }
  }

  Process {
    id: recentFileValidationProcess

    onExited: function(exitCode) {
      var checkedPath = root.recentFileValidationPath
      root.recentFileValidationPath = ""
      if (exitCode !== 0) root.forgetRecentFile(checkedPath)
      Qt.callLater(root.startNextRecentFileValidation)
    }
  }

  Process {
    id: openFileCheckProcess

    onExited: function(exitCode) {
      if (!root.openingFile) return
      var nextPath = root.openingPath
      root.openingFile = false
      root.openingPath = ""
      if (exitCode === 0) {
        root.saveAsOpen = false
        root.fileChooserMode = ""
        root.fileChooserMessage = ""
        root.registerRecentFile(nextPath)
        root.switchToFile(nextPath)
        if (nextPath === root.notePath && !root.loadingFromFile &&
            root.noteLoadError === "") root.finishMostRecentOpen(nextPath)
      } else if (exitCode === 1) {
        root.forgetRecentFile(nextPath)
        root.fileChooserMessage = "File not found: " +
          root.fileNameForPath(nextPath)
        root.statusText = "File not found"
        root.continueMostRecentAfterFailure(nextPath)
      } else {
        root.forgetRecentFile(nextPath)
        root.fileChooserMessage = "Could not check the selected file"
        root.statusText = "Could not open file"
        root.continueMostRecentAfterFailure(nextPath)
      }
    }
  }

  Process {
    id: saveAsTargetCheckProcess

    onExited: function(exitCode) {
      if (!root.saveAsChecking) return
      var nextPath = root.saveAsCheckPath
      root.saveAsChecking = false
      root.saveAsCheckPath = ""
      if (exitCode === 0) {
        root.saveAsOverwritePath = nextPath
        root.fileChooserMessage = "A file with this name already exists."
      } else if (exitCode === 1) {
        root.beginSaveAs(nextPath, false)
      } else {
        root.fileChooserMessage = "Could not check the save destination"
        root.statusText = "Could not save copy"
      }
    }
  }

  Process {
    id: saveAsTempCreateProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.saveAsTempPath = String(text || "").trim()
    }

    onExited: function(exitCode) {
      if (!root.savingAs) return
      var tempPath = root.saveAsTempPath
      if (exitCode !== 0 || tempPath === "") {
        root.saveAsTempPath = ""
        root.failSaveAs("Could not prepare save copy")
        return
      }
      root.saveAsWritePath = tempPath
      saveCopyFile.setText(root.saveAsText)
    }
  }

  Process {
    id: saveAsInstallProcess

    onExited: function(exitCode) {
      if (!root.savingAs) return
      if (exitCode === 0) {
        root.saveAsCleanupPath = root.saveAsTempPath
        root.saveAsCleanupAfterSuccess = true
        if (root.saveAsCleanupPath === "") {
          root.finishSaveAs()
          return
        }
        saveAsTempCleanupProcess.command = ["rm", "-f", "--",
          root.saveAsCleanupPath]
        saveAsTempCleanupProcess.running = true
      } else {
        root.saveAsCleanupPath = root.saveAsTempPath
        root.saveAsCleanupAfterSuccess = false
        if (root.saveAsCleanupPath === "") {
          root.failSaveAs("Could not save copy: destination already exists")
          return
        }
        saveAsTempCleanupProcess.command = ["rm", "-f", "--",
          root.saveAsCleanupPath]
        saveAsTempCleanupProcess.running = true
      }
    }
  }

  Process {
    id: saveAsTempCleanupProcess

    onExited: function(exitCode) {
      var cleanupPath = root.saveAsCleanupPath
      var completedSuccessfully = root.saveAsCleanupAfterSuccess
      root.saveAsCleanupPath = ""
      root.saveAsCleanupAfterSuccess = false
      if (completedSuccessfully && root.savingAs) {
        root.saveAsTempPath = ""
        root.finishSaveAs()
      } else if (!completedSuccessfully && root.savingAs) {
        root.saveAsTempPath = ""
        root.failSaveAs("Could not save copy: destination already exists")
      }
    }
  }

  Process {
    id: untitledBlankCheckProcess

    onExited: function(exitCode) {
      if (!root.untitledBlankCheckInFlight) return
      var target = root.untitledBlankCheckPath
      root.untitledBlankCheckPath = ""
      root.untitledBlankCheckInFlight = false
      if (exitCode === 1) {
        root.deleteEmptyUntitledFile(target)
      } else if (exitCode === 0) {
        root.pendingClosePath = ""
        root.finishCloseFile(target)
      } else {
        root.pendingClosePath = ""
        root.statusText = "Could not inspect the untitled note"
      }
    }
  }

  Process {
    id: untitledDeleteProcess

    onExited: function(exitCode) {
      if (!root.untitledDeleteInFlight) return
      var target = root.untitledDeletePath
      root.untitledDeletePath = ""
      root.untitledDeleteInFlight = false
      if (exitCode === 0) {
        root.forgetRecentFile(target)
        root.pendingClosePath = ""
        root.finishCloseFile(target)
      } else {
        root.pendingClosePath = ""
        root.statusText = "Could not remove the empty note"
      }
    }
  }

  Process {
    id: mkdirProcess

    onExited: function(exitCode) {
      if (root.savingAs) {
        if (exitCode === 0) {
          if (root.saveAsOverwriteConfirmedPath === root.saveAsPath) {
            root.saveAsWritePath = root.saveAsPath
            saveCopyFile.setText(root.saveAsText)
          } else {
            root.createSaveAsTempFile()
          }
        } else {
          root.failSaveAs("Could not create save folder")
        }
        return
      }
      root.directoryReady = exitCode === 0
      if (root.directoryReady) root.writeNote()
      else {
        root.pendingSave = false
        root.statusText = "Could not create note folder"
      }
    }
  }

  Process {
    id: quickCreateDirectoryProcess

    onExited: function(exitCode) {
      if (!root.quickCreating) return
      if (exitCode === 0) {
        quickCreateFileProcess.command = [
          "mktemp",
          "--tmpdir=" + root.defaultNotesDirectory,
          "untitled-XXXXXX.md"
        ]
        quickCreateFileProcess.running = true
      } else {
        root.failQuickCreate("Could not create note folder")
      }
    }
  }

  Process {
    id: quickCreateFileProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.quickCreatedPath = String(text || "").trim()
    }

    onExited: function(exitCode) {
      if (!root.quickCreating) return
      if (exitCode === 0) {
        root.finishQuickCreate(root.quickCreatedPath)
      } else {
        root.failQuickCreate("Could not create note")
      }
    }
  }

  Process {
    id: renameTargetCheckProcess

    onExited: function(exitCode) {
      if (!root.renameInProgress) return
      root.renameTargetChecking = false
      if (exitCode === 0) {
        root.restoreRename("A file with that name already exists")
      } else if (exitCode === 1) {
        renameFileProcess.command = [
          "mv", "--no-clobber", "--", root.renameOldPath,
          root.renameNewPath
        ]
        renameFileProcess.running = true
      } else {
        root.restoreRename("Could not check the new filename")
      }
    }
  }

  Process {
    id: renameFileProcess

    onExited: function(exitCode) {
      if (!root.renameInProgress) return
      if (exitCode === 0) {
        renameVerifyProcess.command = ["test", "!", "-e",
          root.renameOldPath]
        renameVerifyProcess.running = true
      } else root.restoreRename("Could not rename file")
    }
  }

  Process {
    id: renameVerifyProcess

    onExited: function(exitCode) {
      if (!root.renameInProgress) return
      if (exitCode === 0) root.finishRenameFile()
      else root.restoreRename("Rename stopped: destination already exists")
    }
  }

  FileView {
    id: saveCopyFile
    path: root.saveAsWritePath
    atomicWrites: true
    printErrors: false

    onSaveFailed: {
      root.failSaveAs("Could not save copy")
    }
    onSaved: {
      if (!root.savingAs) return
      if (root.saveAsOverwriteConfirmedPath === root.saveAsPath) {
        root.finishSaveAs()
      } else {
        saveAsInstallProcess.command = ["ln", "-T", "--",
          root.saveAsTempPath, root.saveAsPath]
        saveAsInstallProcess.running = true
      }
    }
  }

  Process {
    id: folderListProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.setSaveAsFolders(String(text || ""))
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) root.saveAsFolders = []
    }
  }

  Process {
    id: openNoteListProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.setOpenNoteFiles(String(text || ""))
    }

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.openNoteFiles = []
        root.openNoteFilesLoading = false
      }
    }
  }

  Timer {
    id: saveTimer
    interval: root.saveDelayMs
    repeat: false
    onTriggered: root.saveNow()
  }

  Timer {
    id: editorStateSaveTimer
    interval: 350
    repeat: false
    onTriggered: {
      root.captureActiveEditorState(false)
      root.scheduleEditorStatesWrite()
    }
  }

  Timer {
    id: spellcheckTimer
    interval: root.spellcheckDelayMs
    repeat: false
    onTriggered: root.runSpellcheck()
  }

  Timer {
    id: spellingGeometryTimer
    interval: 16
    repeat: false
    onTriggered: root.rebuildSpellingUnderlineModel()
  }

  ListModel {
    id: spellingUnderlineVisualModel
  }

  Timer {
    id: externalFileChangeTimer
    interval: 80
    repeat: false
    onTriggered: {
      if (root.noteSaveInFlight) {
        externalFileChangeTimer.restart()
        return
      }
      root.observeExternalFileChange()
    }
  }

  Timer {
    id: recoveryTimer
    interval: root.recoveryIntervalMs
    repeat: true
    onTriggered: root.writeRecoverySnapshot()
  }

  Timer {
    id: liveCursorBlink
    interval: 500
    repeat: true
    running: root.opened && !root.screensaverActive && !root.rawMode &&
      editor.activeFocus
    onTriggered: root.liveCursorVisible = !root.liveCursorVisible
  }

  Timer {
    id: liveCursorGeometrySettle
    interval: 16
    repeat: false
    onTriggered: root.syncLiveCursor()
  }

  Timer {
    id: viewCaretAlignmentTimer
    interval: 16
    repeat: false
    onTriggered: root.finishPendingViewCaretAlignment()
  }

  Timer {
    id: taskToggleViewportRestoreTimer
    interval: 16
    repeat: false
    onTriggered: root.restoreTaskToggleViewport()
  }

  Timer {
    id: editorStateRestoreSettleTimer
    interval: 32
    repeat: false
    onTriggered: root.settlePendingEditorStateRestore()
  }

  Timer {
    id: noteLoadWatchdog
    interval: Math.max(250, Number(root.noteLoadWatchdogIntervalMs) || 3000)
    repeat: false
    onTriggered: root.handleNoteLoadWatchdog()
  }

  Timer {
    id: maximizeStateTimer
    interval: 50
    repeat: true
    onTriggered: root.syncMaximizeState()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // Refresh the icon when a compositor action changes a nested toplevel
      // IPC map. The timer also gives the model a beat to publish the new map.
      root.hyprlandWindowStateRevision++
      if (!root.observeHyprlandFullscreenEvent(event) &&
          root.maximizeStatePending) root.syncMaximizeState()
    }
  }

  Timer {
    id: workspaceRelocationTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (root.opened && root.moveJotPinToFocusedWorkspace()) {
        root.syncFocusMode()
      }
    }
  }

  FontMetrics {
    id: footerFontMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  onOpenedChanged: {
    if (!root.opened) root.controlKeyHeld = false
    if (!root.opened) workspaceRelocationTimer.stop()
    if (!root.opened) root.maximizeStateObserved = false
    if (root.opened) root.scheduleSpellcheck()
    else root.resetSpellcheckForDocumentChange()
    root.syncFocusMode()
  }
  onLoadingFromFileChanged: {
    if (root.loadingFromFile) {
      root.startupContentRevealed = false
      root.startupImageWaitExpired = false
      root.startupMessageVisible = false
      root.startupRecoveryVisible = false
      root.resetSpellcheckForDocumentChange()
      if (root.presentationSettingsLoaded)
        root.armNoteLoadWatchdog(root.notePath, true)
    } else {
      root.clearNoteLoadWatchdog()
      root.scheduleSpellcheck()
    }
  }
  onNotePathChanged: {
    root.resetSpellcheckForDocumentChange()
    if (root.loadingFromFile && root.presentationSettingsLoaded)
      root.armNoteLoadWatchdog(root.notePath, true)
  }
  onPresentationSettingsLoadedChanged: {
    if (root.presentationSettingsLoaded && root.loadingFromFile)
      root.armNoteLoadWatchdog(root.notePath, true)
  }
  onRawModeChanged: root.queueSpellingGeometryUpdate(true)
  onPresentationModeChanged: {
    root.maximizeStatePending = false
    root.maximizeStateObserved = false
    maximizeStateTimer.stop()
    root.syncFocusMode()
    root.schedulePresentationModeSave()
  }
  onSidePlacementChanged: root.schedulePersistedSettingsSave()
  onEditorTextScaleChanged: {
    root.schedulePersistedSettingsSave()
    root.queueSpellingGeometryUpdate(true)
  }
  onFileTabRowsChanged: root.schedulePersistedSettingsSave()
  onScreensaverActiveChanged: {
    root.syncFocusMode()
    root.syncLiveCursor()
  }
  Component.onCompleted: {
    root.ensurePresentationSettingsDirectory()
  }

  FloatingWindow {
    id: sideWindow
    visible: root.opened && root.sideMode && !root.screensaverActive &&
      !root.sidePlacementRemapping
    title: "JotPin Side " + root.barPosition + " " + root.sidePlacement + " — " +
      root.fileNameForPath(root.notePath)
    color: "transparent"
    implicitWidth: Style.space(480) + root.sideOuterMargin
    implicitHeight: screen
      ? Math.max(Style.space(360), screen.height - root.sideTopMargin -
        root.sideBottomMargin)
      : Style.space(900)
    minimumSize: Qt.size(
      Style.space(360) + root.sideOuterMargin,
      implicitHeight)
    maximumSize: Qt.size(
      16777215,
      implicitHeight)

    // Keep only the visible drawer interactive when a bar occupies the
    // transparent strip included in this native window.
    mask: Region { item: card }

    onVisibleChanged: {
      if (!visible && root.opened && root.sideMode &&
          !root.screensaverActive && !root.sidePlacementRemapping) {
        root.dismiss()
      } else if (visible) {
        root.syncFocusMode()
      }
    }
  }

  FloatingWindow {
    id: centerWindow
    visible: root.opened && root.windowMode && !root.screensaverActive
    title: "JotPin Window — " + root.fileNameForPath(root.notePath)
    color: root.background
    implicitWidth: Style.space(900)
    implicitHeight: Style.space(700)
    minimumSize: Qt.size(Style.space(480), Style.space(360))

    // A compositor close is the same logical action as JotPin's Close button.
    // Hiding for a presentation change or screensaver must not close the note.
    onVisibleChanged: {
      if (!visible && root.opened && root.windowMode &&
          !root.screensaverActive) {
        root.dismiss()
      } else if (visible) {
        Qt.callLater(function() {
          if (root.opened && root.windowMode) editor.forceActiveFocus()
        })
      }
    }
  }

  // Keep one editor instance while switching between the two native windows.
  // Reparenting preserves text, undo history, caret, selection, and any
  // in-flight persistence state.
  FocusScope {
    id: focusScope
    parent: root.sideMode ? sideWindow.contentItem : centerWindow.contentItem
    anchors.fill: parent
    focus: root.opened && !root.screensaverActive
    onActiveFocusChanged: {
      if (!activeFocus) root.controlKeyHeld = false
    }

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Control) root.controlKeyHeld = true
        if (event.key === Qt.Key_Escape) {
          if (root.recoveryPromptOpen) {
            event.accepted = true
            return
          }
          if (editorContextMenu.opened) {
            root.closeEditorContextMenu()
            event.accepted = true
          } else if (fileMenuPopup.opened) {
            root.closeFileMenu()
            event.accepted = true
          } else if (root.editorCommandOpen) {
            root.closeEditorCommand()
          } else if (root.shortcutHelpOpen) {
            root.shortcutHelpOpen = false
            editor.forceActiveFocus()
          } else if (root.settingsOpen) {
            root.closeSettings()
            editor.forceActiveFocus()
          } else if (root.saveAsOpen) root.cancelSaveAs()
          else root.dismiss()
          event.accepted = true
        }
      }
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Control) root.controlKeyHeld = false
      }
      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutSave
        onActivated: root.saveNow()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutSaveAs
        onActivated: root.openSaveAs()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutOpen
        onActivated: root.openFileChooser()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutOpenRecent
        onActivated: root.openMostRecentFile()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutClearRecent
        onActivated: root.clearRecentFiles()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutNew
        onActivated: root.openNewFile()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutPreview
        onActivated: root.toggleRaw()
      }

      Shortcut {
        id: fileMenuShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutFileMenu
        onActivated: root.toggleFileMenu()
      }

      Shortcut {
        id: presentationShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutPresentation
        onActivated: root.togglePresentation()
      }

      Shortcut {
        id: maximizeShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutMaximize
        onActivated: root.toggleMaximized()
      }

      Shortcut {
        id: settingsShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutSettings
        onActivated: root.toggleSettings()
      }

      Shortcut {
        id: shortcutHelpShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutHelp
        onActivated: root.toggleShortcutHelp()
      }

      Shortcut {
        id: nextFileShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutNextFile
        onActivated: root.switchRelativeFile(1)
      }

      Shortcut {
        id: previousFileShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutPreviousFile
        onActivated: root.switchRelativeFile(-1)
      }

      Shortcut {
        id: closeFileShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutCloseFile
        onActivated: root.closeActiveFile()
      }

      Shortcut {
        id: renameFileShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutRenameFile
        onActivated: root.renameActiveFile()
      }

      Shortcut {
        id: toggleTaskShortcut
        enabled: root.editorCommandAllowed()
        sequence: root.shortcutToggleTask
        onActivated: root.toggleTask(editor.cursorPosition)
      }

      Shortcut {
        id: findShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutFind
        onActivated: root.openEditorCommand("find")
      }

      Shortcut {
        id: replaceShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutReplace
        onActivated: root.openEditorCommand("replace")
      }

      Shortcut {
        id: goToLineShortcut
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutGoToLine
        onActivated: root.openEditorCommand("line")
      }

      Shortcut {
        id: findNextShortcut
        enabled: root.opened && !root.screensaverActive &&
          root.findQuery !== ""
        sequence: root.shortcutFindNext
        onActivated: root.findInEditor(false)
      }

      Shortcut {
        id: findPreviousShortcut
        enabled: root.opened && !root.screensaverActive &&
          root.findQuery !== ""
        sequence: root.shortcutFindPrevious
        onActivated: root.findInEditor(true)
      }

      Shortcut {
        id: editorContextMenuShortcut
        enabled: root.opened && !root.screensaverActive &&
          !root.loadingFromFile && root.noteLoadError === ""
        sequence: root.shortcutContextMenu
        onActivated: root.openEditorContextMenuForKeyboard()
      }

      Shortcut {
        enabled: root.opened && !root.screensaverActive
        sequence: root.shortcutClose
        onActivated: root.dismiss()
      }

      Rectangle {
        anchors.fill: parent
        color: root.sideMode ? "transparent" : root.scrim

        MouseArea {
          anchors.fill: parent
          onClicked: if (!root.sideMode) root.dismiss()
        }
      }

      BorderSurface {
        id: card
        // Keep the colored frame off the buffer edge. During native resize
        // animations the compositor can clamp/stretch the last texture pixel;
        // a border at that edge becomes a wide colored strip until the next
        // buffer arrives. One logical pixel leaves a neutral guard on all sides.
        readonly property real edgeGuard: 1
        width: root.sideMode
          ? Math.max(0, parent.width -
            (root.sideExpanded ? 0 : root.sideOuterMargin) - edgeGuard * 2)
          : Math.max(0, parent.width - edgeGuard * 2)
        height: Math.max(0, parent.height - edgeGuard * 2)
        anchors.top: root.sideMode ? parent.top : undefined
        anchors.left: root.sideLeftMode ? parent.left : undefined
        anchors.right: root.sideRightMode ? parent.right : undefined
        anchors.topMargin: edgeGuard
        anchors.leftMargin: root.sideLeftMode && !root.sideExpanded
          ? root.sideLeftMargin + edgeGuard
          : edgeGuard
        anchors.rightMargin: root.sideRightMode && !root.sideExpanded
          ? root.sideRightMargin + edgeGuard
          : edgeGuard
        anchors.centerIn: root.sideMode ? undefined : parent
        color: root.background
        radius: root.sideExpanded || root.windowExpanded
          ? 0
          : Style.cornerRadius
        borderSpec: root.surfaceBorder
        padding: Style.spacing.panelPadding

        MouseArea {
          anchors.fill: parent
          onClicked: function(mouse) { mouse.accepted = true }
        }

        MouseArea {
          id: sideResizeHandle
          visible: root.sideMode && !root.sideExpanded
          anchors.left: root.sideRightMode ? parent.left : undefined
          anchors.right: root.sideLeftMode ? parent.right : undefined
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Math.max(Style.space(8), 8)
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.SizeHorCursor
          z: 10
          onPressed: function(mouse) {
            mouse.accepted = sideWindow.startSystemResize(
              root.sideLeftMode ? Qt.RightEdge : Qt.LeftEdge)
          }
        }

        Item {
          id: content
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset

          Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: headerTopRow.height + headerPath.implicitHeight +
              Style.space(9)

            Item {
              id: headerTopRow
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: Math.max(Style.space(42), actionRow.implicitHeight,
                brandRow.implicitHeight)

              Row {
                id: brandRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Image {
                  id: appIcon
                  width: Style.space(32)
                  height: width
                  source: Qt.resolvedUrl("assets/jotpin-icon.png")
                  sourceSize: Qt.size(width * 2, height * 2)
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  mipmap: true
                }

                Text {
                  id: headerTitle
                  anchors.verticalCenter: parent.verticalCenter
                  text: "JotPin"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.display
                  font.bold: true
                }
              }

              Row {
                id: actionRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                JotPinButton {
                  id: fileMenuButton
                  text: "File"
                  selected: fileMenuPopup.opened
                  focusable: true
                  tooltipText: "New, Save, Open, or Recent Files (" +
                    root.shortcutFileMenu + ")"
                  onClicked: root.toggleFileMenu()
                }

                Rectangle {
                  id: actionSeparator
                  width: Style.space(1)
                  height: Style.space(22)
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.foreground.r, root.foreground.g,
                    root.foreground.b, 0.28)
                }

                JotPinButton {
                  id: presentationButton
                  text: root.sideMode ? "Center" : "Side"
                  focusable: true
                  tooltipText: root.sideMode
                    ? "Use a centered window (" + root.shortcutPresentation + ")"
                    : "Use right-side drawer (" + root.shortcutPresentation + ")"
                  onClicked: root.togglePresentation()
                }

                JotPinButton {
                  id: previewButton
                  width: Style.space(30)
                  height: fileMenuButton.implicitHeight
                  iconText: root.rawMode ? "󰈉" : "󰈈"
                  iconSize: Style.font.icon
                  focusable: true
                  tooltipText: root.rawMode
                    ? "Show rendered Markdown (" + root.shortcutPreview + ")"
                    : "Show raw Markdown (" + root.shortcutPreview + ")"
                  onClicked: root.toggleRaw()
                }

                JotPinButton {
                  id: spellcheckButton
                  width: Style.space(30)
                  height: fileMenuButton.implicitHeight
                  iconText: "󰓆"
                  iconSize: Style.font.icon
                  foreground: root.spellcheckEnabled ? root.foreground
                    : Qt.rgba(root.foreground.r, root.foreground.g,
                        root.foreground.b, 0.38)
                  selected: false
                  focusable: true
                  tooltipText: root.spellcheckEnabled
                    ? "Turn spellcheck off"
                    : "Turn spellcheck on"
                  onClicked: root.setSpellcheckEnabled(!root.spellcheckEnabled)
                }

                JotPinButton {
                  id: fullscreenButton
                  width: Style.space(30)
                  height: fileMenuButton.implicitHeight
                  iconText: root.fullScreenIconText
                  iconSize: Style.font.icon
                  focusable: true
                  tooltipText: "Full Screen (" + root.shortcutMaximize + ")"
                  onClicked: root.toggleMaximized()
                }

                JotPinButton {
                  id: settingsButton
                  width: Style.space(30)
                  height: fileMenuButton.implicitHeight
                  iconText: "󰒓"
                  iconSize: Style.font.icon
                  selected: root.settingsOpen
                  focusable: true
                  tooltipText: "JotPin settings (" + root.shortcutSettings + ")"
                  onClicked: root.toggleSettings()
                }

                JotPinButton {
                  id: closeButton
                  width: Style.space(30)
                  height: fileMenuButton.implicitHeight
                  text: "✕"
                  fontFamily: Style.font.family
                  fontSize: Style.font.heading
                  focusable: true
                  tooltipText: "Close JotPin (" + root.shortcutClose + ")"
                  onClicked: root.dismiss()
                }
              }
            }

            Popup {
              id: fileMenuPopup
              parent: header
              x: Math.max(0, Math.min(
                actionRow.x + fileMenuButton.x,
                header.width - width))
              y: actionRow.y + actionRow.height + Style.space(4)
              width: Style.space(260)
              padding: Style.space(4)
              modal: false
              focus: true
              z: 20
              closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

              onOpenedChanged: {
                if (opened) {
                  Qt.callLater(function() { fileMenuNewButton.forceActiveFocus() })
                } else if (root.opened && !root.settingsOpen &&
                    !root.saveAsOpen && !root.shortcutHelpOpen) {
                  Qt.callLater(function() { editor.forceActiveFocus() })
                }
              }

              background: BorderSurface {
                color: root.background
                borderSpec: root.surfaceBorder
                radius: Style.cornerRadius
              }

              contentItem: Column {
                id: fileMenuContent
                width: parent.width
                spacing: Style.spacing.controlGap

                JotPinButton {
                  id: fileMenuNewButton
                  width: parent.width
                  text: "New"
                  leftAlign: true
                  focusable: true
                  tooltipText: "Create a blank Markdown file (" +
                    root.shortcutNew + ")"
                  onClicked: root.openNewFile()
                }

                JotPinButton {
                  id: fileMenuSaveButton
                  width: parent.width
                  text: "Save"
                  leftAlign: true
                  focusable: true
                  tooltipText: "Save this note (" + root.shortcutSave + ")"
                  onClicked: root.saveFromFileMenu()
                }

                JotPinButton {
                  id: fileMenuSaveAsButton
                  width: parent.width
                  text: "Save As"
                  leftAlign: true
                  focusable: true
                  tooltipText: "Choose a filename and folder for this note (" +
                    root.shortcutSaveAs + ")"
                  onClicked: root.openSaveAs()
                }

                JotPinButton {
                  id: fileMenuOpenButton
                  width: parent.width
                  text: "Open"
                  leftAlign: true
                  focusable: true
                  tooltipText: "Open an existing Markdown file (" +
                    root.shortcutOpen + ")"
                  onClicked: root.openFileChooser()
                }

                Text {
                  width: parent.width
                  text: "Recent Files"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  visible: root.recentFiles.length === 0
                  text: "No recent files"
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                ScrollView {
                  id: recentFilesScroll
                  width: parent.width
                  height: Math.min(recentFilesColumn.implicitHeight,
                    Math.max(Style.space(72), Math.min(Style.space(240),
                      focusScope.height - Style.space(280))))
                  visible: root.recentFiles.length > 0
                  clip: true
                  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                  Column {
                    id: recentFilesColumn
                    width: recentFilesScroll.availableWidth
                    spacing: Style.spacing.controlGap

                    Repeater {
                      model: root.recentFiles

                      delegate: JotPinButton {
                        width: recentFilesColumn.width
                        text: root.markdownStemForPath(modelData)
                        leftAlign: true
                        focusable: true
                        tooltipText: String(modelData) + (index === 0
                          ? " (" + root.shortcutOpenRecent + ")" : "")
                        onClicked: root.openRecentFile(modelData)
                      }
                    }
                  }
                }

                JotPinButton {
                  id: fileMenuClearRecentButton
                  width: parent.width
                  visible: root.recentFiles.length > 0
                  text: "Clear Recent Files"
                  leftAlign: true
                  focusable: true
                  tooltipText: "Clear Recent Files (" +
                    root.shortcutClearRecent + ")"
                  onClicked: root.clearRecentFiles()
                }
              }
            }

            Text {
              id: headerPath
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: headerTopRow.bottom
              anchors.topMargin: Style.space(4)
              text: root.displayPath
              color: Qt.darker(root.foreground, 1.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              elide: Text.ElideNone
            }
          }

          Item {
            id: fileTabs
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Style.space(8)
            readonly property int singleRowHeight: Math.max(Style.space(34),
              Style.font.bodySmall + Style.spacing.panelPadding)
            readonly property int tabRowHeight: Math.max(Style.space(20),
              singleRowHeight - Style.space(12))
            property int neededTabRows: 1
            property bool tabRowsUpdatePending: false
            readonly property int visibleTabRows: Math.max(
              root.minimumFileTabRows,
              Math.min(root.maximumFileTabRows,
                Math.min(root.fileTabRows, neededTabRows)))
            readonly property real occupiedRowsHeight: Math.max(
              tabRowHeight, tabGrid.childrenRect.height)

            function updateNeededTabRows() {
              var availableWidth = Number(fileTabsViewport.width)
              if (!isFinite(availableWidth) || availableWidth <= 0) {
                fileTabs.neededTabRows = root.minimumFileTabRows
                return
              }

              var rows = root.minimumFileTabRows
              var rowWidth = 0
              var gap = Number(Style.spacing.controlGap)
              for (var index = 0; index < fileTabRepeater.count; index++) {
                var tab = fileTabRepeater.itemAt(index)
                if (!tab || !tab.visible) continue
                var tabWidth = Number(tab.width)
                if (!isFinite(tabWidth) || tabWidth <= 0) continue
                if (rowWidth > 0 && rowWidth + gap + tabWidth >
                    availableWidth) {
                  rows++
                  rowWidth = tabWidth
                } else {
                  rowWidth += (rowWidth > 0 ? gap : 0) + tabWidth
                }
              }
              fileTabs.neededTabRows = rows
            }

            function scheduleNeededTabRowsUpdate() {
              if (fileTabs.tabRowsUpdatePending) return
              fileTabs.tabRowsUpdatePending = true
              Qt.callLater(function() {
                fileTabs.tabRowsUpdatePending = false
                fileTabs.updateNeededTabRows()
              })
            }

            Component.onCompleted: fileTabs.scheduleNeededTabRowsUpdate()
            height: Math.max(singleRowHeight,
              occupiedRowsHeight + Style.space(12))

            Flickable {
              id: fileTabsViewport
              anchors.left: parent.left
              anchors.right: addFileButton.left
              anchors.rightMargin: Style.spacing.controlGap
              anchors.top: parent.top
              anchors.bottom: tabScrollRail.top
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.HorizontalFlick
              contentWidth: Math.max(width, tabGrid.width)
              contentHeight: Math.max(height, tabGrid.childrenRect.height)
              onWidthChanged: fileTabs.scheduleNeededTabRowsUpdate()

              Grid {
                id: tabGrid
                rows: fileTabs.visibleTabRows
                columns: 0
                flow: Grid.LeftToRight
                width: implicitWidth
                rowSpacing: Style.spacing.controlGap
                columnSpacing: Style.spacing.controlGap

                Repeater {
                  id: fileTabRepeater
                  model: root.openFiles

                  onItemAdded: function(index, item) {
                    fileTabs.scheduleNeededTabRowsUpdate()
                  }
                  onItemRemoved: function(index, item) {
                    fileTabs.scheduleNeededTabRowsUpdate()
                  }

                  delegate: Item {
                    id: fileTab
                    readonly property bool activeTab:
                      modelData.path === root.notePath
                    width: tabName.width + Style.space(2) + closeTabButton.width
                    height: fileTabs.tabRowHeight
                    onWidthChanged: fileTabs.scheduleNeededTabRowsUpdate()

                    Row {
                      width: parent.width
                      height: parent.height
                      spacing: Style.space(2)

                      Item {
                        id: tabName
                        width: renameField.visible
                          ? renameField.width
                          : tabButton.implicitWidth
                        height: fileTab.height

                        JotPinButton {
                          id: tabButton
                          anchors.fill: parent
                          visible: !renameField.visible
                          text: root.markdownStemForPath(modelData.path)
                          selected: fileTab.activeTab
                          hasCursor: tabNameMouseArea.containsMouse
                          focusable: true
                          tooltipText: modelData.path +
                            "\nRename active file: " + root.shortcutRenameFile
                          onClicked: root.switchToFile(modelData.path)
                        }

                        Rectangle {
                          id: dirtyIndicator
                          visible: fileTab.activeTab && root.dirty &&
                            !renameField.visible
                          anchors.top: parent.top
                          anchors.right: parent.right
                          anchors.topMargin: Style.space(3)
                          anchors.rightMargin: Style.space(3)
                          width: Math.max(Style.space(4), 3)
                          height: width
                          radius: width / 2
                          color: tabButton.selected
                            ? tabButton._selectedColor
                            : tabButton.foreground
                          z: 3
                        }

                        MouseArea {
                          id: tabNameMouseArea
                          visible: tabButton.visible
                          anchors.fill: parent
                          z: 2
                          hoverEnabled: true
                          acceptedButtons: Qt.LeftButton

                          onClicked: {
                            tabButton.forceActiveFocus()
                            root.switchToFile(modelData.path)
                          }

                          onDoubleClicked: root.beginRenameFile(modelData.path)
                        }

                        TextField {
                          id: renameField
                          visible: root.renamingPath === modelData.path
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          width: Math.max(Style.space(64),
                            tabButton.implicitWidth)
                          height: parent.height
                          z: 3
                          text: root.renameValue
                          selectByMouse: true
                          verticalAlignment: TextInput.AlignVCenter
                          verticalPadding: 0
                          color: root.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body

                          onVisibleChanged: {
                            if (visible) {
                              forceActiveFocus()
                              selectAll()
                            }
                          }
                          onTextChanged: if (activeFocus) root.renameValue = text
                          onAccepted: root.commitRenameFile(text)
                          onEditingFinished: {
                            if (root.renamingPath === modelData.path) {
                              root.commitRenameFile(text)
                            }
                          }

                          background: Rectangle {
                            color: root.editorBackground
                            radius: Style.cornerRadius
                            border.color: Color.accent
                            border.width: Math.max(1, Style.space(1))
                          }
                        }

                      }

                      JotPinButton {
                        id: closeTabButton
                        width: Style.space(24)
                        height: fileTab.height
                        text: "✕"
                        fontFamily: Style.font.family
                        fontSize: Style.font.heading
                        enabled: true
                        focusable: true
                          tooltipText: "Close " +
                            root.markdownStemForPath(modelData.path) +
                          (fileTab.activeTab
                            ? " (" + root.shortcutCloseFile + ")" : "")
                        onClicked: root.closeFile(modelData.path)
                      }
                    }
                  }
                }
              }

            }

            Rectangle {
              id: tabScrollRail
              anchors.left: parent.left
              anchors.right: addFileButton.left
              anchors.rightMargin: Style.spacing.controlGap
              anchors.bottom: parent.bottom
              height: visible ? Style.space(2) : 0
              visible: contentRange > 0
              z: 2
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.22)

              readonly property real contentRange: Math.max(
                0, fileTabsViewport.contentWidth - fileTabsViewport.width)
              readonly property real thumbWidth: Math.max(
                Style.space(44),
                Math.min(width, width * fileTabsViewport.width /
                  Math.max(fileTabsViewport.contentWidth, width)))
              readonly property real thumbTravel: Math.max(
                0, width - thumbWidth)
              readonly property real thumbX: contentRange > 0 && thumbTravel > 0
                ? thumbTravel * fileTabsViewport.contentX / contentRange
                : 0

              function setScrollFromThumb(left) {
                var boundedLeft = Math.max(0, Math.min(thumbTravel, left))
                fileTabsViewport.contentX = thumbTravel > 0
                  ? boundedLeft / thumbTravel * contentRange
                  : 0
              }

              Rectangle {
                id: tabScrollThumb
                x: tabScrollRail.thumbX
                width: tabScrollRail.thumbWidth
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g,
                  root.foreground.b, 0.78)
              }

              MouseArea {
                anchors.fill: parent
                property bool draggingThumb: false
                property real pointerOffset: 0

                onPressed: function(mouse) {
                  draggingThumb = mouse.x >= tabScrollThumb.x &&
                    mouse.x <= tabScrollThumb.x + tabScrollThumb.width
                  pointerOffset = draggingThumb
                    ? mouse.x - tabScrollThumb.x
                    : tabScrollThumb.width / 2
                  if (!draggingThumb) {
                    tabScrollRail.setScrollFromThumb(mouse.x - pointerOffset)
                  }
                }

                onPositionChanged: function(mouse) {
                  if (pressed && draggingThumb) {
                    tabScrollRail.setScrollFromThumb(mouse.x - pointerOffset)
                  }
                }

                onReleased: draggingThumb = false
                onCanceled: draggingThumb = false
              }
            }

            JotPinButton {
              id: addFileButton
              anchors.right: parent.right
              anchors.top: parent.top
              height: fileTabs.tabRowHeight
              width: Style.space(32)
              text: "+"
              fontFamily: Style.font.family
              fontSize: Style.font.heading
              focusable: true
              tooltipText: "New note (" + root.shortcutNew + ")"
              onClicked: root.openNewFile()
            }

          }

          Rectangle {
            id: editorFrame
            anchors.top: fileTabs.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(12)
            color: root.editorBackground
            radius: Style.cornerRadius
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            border.width: Math.max(1, Style.space(1))

            Rectangle {
              id: editorCommandBar
              visible: root.editorCommandOpen
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(5)
              height: root.editorCommandMode === "replace"
                ? Style.space(94) : Style.space(56)
              color: root.background
              radius: Style.cornerRadius
              border.color: root.border
              border.width: Math.max(1, Style.space(1))
              z: 4

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                spacing: Style.space(3)

                Row {
                  id: editorCommandPrimaryRow
                  width: parent.width
                  height: Style.space(28)
                  spacing: Style.space(4)

                  Text {
                    width: Style.space(52)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.editorCommandMode === "replace" ? "Find" :
                      (root.editorCommandMode === "line" ? "Line" : "Find")
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  TextField {
                    id: findQueryField
                    visible: root.editorCommandMode !== "replace" &&
                      root.editorCommandMode !== "line"
                    width: Math.max(Style.space(80), parent.width -
                      Style.space(52 + 34 + 34 + 34 + 30) -
                      parent.spacing * 5)
                    height: parent.height
                    text: root.findQuery
                    placeholderText: "Find text"
                    selectByMouse: true
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    onTextEdited: {
                      root.updateFindQuery(text)
                    }
                    onAccepted: root.findInEditor(false)
                    Keys.onPressed: function(event) {
                      if ((event.key === Qt.Key_Return ||
                          event.key === Qt.Key_Enter) &&
                          (event.modifiers & Qt.ShiftModifier)) {
                        root.findInEditor(true)
                        event.accepted = true
                      }
                    }
                  }

                  TextField {
                    id: replaceQueryField
                    visible: root.editorCommandMode === "replace"
                    width: findQueryField.width
                    height: parent.height
                    text: root.findQuery
                    placeholderText: "Find text"
                    selectByMouse: true
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    onTextEdited: {
                      root.updateFindQuery(text)
                    }
                    onAccepted: root.findInEditor(false)
                    Keys.onPressed: function(event) {
                      if ((event.key === Qt.Key_Return ||
                          event.key === Qt.Key_Enter) &&
                          (event.modifiers & Qt.ShiftModifier)) {
                        root.findInEditor(true)
                        event.accepted = true
                      }
                    }
                  }

                  TextField {
                    id: goToLineField
                    visible: root.editorCommandMode === "line"
                    width: Math.max(Style.space(80), parent.width -
                      Style.space(52 + 48 + 30) - parent.spacing * 3)
                    height: parent.height
                    text: root.goToLineValue
                    placeholderText: "Line number"
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1 }
                    selectByMouse: true
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    onTextEdited: {
                      root.goToLineValue = text
                      root.editorCommandMessage = ""
                    }
                    onAccepted: root.goToSourceLine()
                  }

                  JotPinButton {
                    visible: root.editorCommandMode !== "line"
                    width: Style.space(34)
                    height: parent.height
                    text: "Aa"
                    selected: root.findCaseSensitive
                    focusable: true
                    tooltipText: "Match case"
                    onClicked: root.toggleFindCaseSensitive()
                  }

                  JotPinButton {
                    visible: root.editorCommandMode !== "line"
                    width: Style.space(34)
                    height: parent.height
                    text: "↑"
                    focusable: true
                    tooltipText: "Previous match (" +
                      root.shortcutFindPrevious + ")"
                    onClicked: root.findInEditor(true)
                  }

                  JotPinButton {
                    visible: root.editorCommandMode !== "line"
                    width: Style.space(34)
                    height: parent.height
                    text: "↓"
                    focusable: true
                    tooltipText: "Next match (" + root.shortcutFindNext + ")"
                    onClicked: root.findInEditor(false)
                  }

                  JotPinButton {
                    visible: root.editorCommandMode === "line"
                    width: Style.space(48)
                    height: parent.height
                    text: "Go"
                    focusable: true
                    tooltipText: "Go to the requested source line (Enter)"
                    onClicked: root.goToSourceLine()
                  }

                  JotPinButton {
                    width: Style.space(30)
                    height: parent.height
                    text: "✕"
                    focusable: true
                    tooltipText: "Close (Esc)"
                    onClicked: root.closeEditorCommand()
                  }
                }

                Row {
                  visible: root.editorCommandMode === "replace"
                  width: parent.width
                  height: visible ? Style.space(28) : 0
                  spacing: Style.space(4)

                  Text {
                    width: Style.space(52)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "With"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  TextField {
                    id: replaceValueField
                    width: Math.max(Style.space(80), parent.width -
                      Style.space(52 + 68 + 68) - parent.spacing * 3)
                    height: parent.height
                    text: root.replaceValue
                    placeholderText: "Replacement text"
                    selectByMouse: true
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    onTextEdited: root.replaceValue = text
                    onAccepted: root.replaceCurrentMatch()
                  }

                  JotPinButton {
                    width: Style.space(68)
                    height: parent.height
                    text: "Replace"
                    fontSize: Style.font.bodySmall
                    focusable: true
                    tooltipText: "Replace this match (Enter in With)"
                    onClicked: root.replaceCurrentMatch()
                  }

                  JotPinButton {
                    width: Style.space(68)
                    height: parent.height
                    text: "All"
                    fontSize: Style.font.bodySmall
                    focusable: true
                    tooltipText: "Replace every match"
                    onClicked: root.replaceAllMatches()
                  }
                }

                Text {
                  width: parent.width
                  height: Style.space(15)
                  text: {
                    if (root.editorCommandMode === "line")
                      return root.editorCommandMessage
                    var count = root.findQuery === "" ? "" :
                      (root.findMatchIndex > 0
                        ? root.findMatchIndex + " of " + root.findMatchCount
                        : "0 of 0")
                    return count !== "" && root.editorCommandMessage !== ""
                      ? count + " · " + root.editorCommandMessage
                      : count !== "" ? count : root.editorCommandMessage
                  }
                  color: root.editorCommandMessage === "No matches"
                    ? Color.accent : Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            Popup {
              id: editorContextMenu
              parent: editorFrame
              width: Style.space(220)
              padding: Style.space(4)
              modal: false
              focus: true
              z: 30
              closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

              onOpenedChanged: if (!opened && root.opened &&
                  !root.editorCommandOpen && !root.settingsOpen &&
                  !root.saveAsOpen) {
                Qt.callLater(function() { editor.forceActiveFocus() })
              }

              background: BorderSurface {
                color: root.background
                borderSpec: root.surfaceBorder
                radius: Style.cornerRadius
              }

              contentItem: Column {
                width: parent.width
                spacing: Style.spacing.controlGap

                Text {
                  visible: root.spellingContextRange !== null
                  width: parent.width
                  text: root.spellingContextRange
                    ? "Spelling: " + root.spellingContextRange.word : ""
                  color: Qt.darker(root.foreground, 1.3)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }

                JotPinButton {
                  visible: root.spellingContextRange !== null &&
                    root.spellingSuggestionsPending
                  width: parent.width
                  text: "Finding suggestions…"
                  leftAlign: true
                  enabled: false
                }

                Repeater {
                  model: root.spellingContextRange
                    ? root.spellingContextSuggestions : []

                  delegate: JotPinButton {
                    required property string modelData
                    width: editorContextMenu.contentItem.width
                    text: modelData
                    leftAlign: true
                    focusable: true
                    tooltipText: "Replace with “" + modelData + "”"
                    onClicked: root.replaceSpellingContext(modelData)
                  }
                }

                JotPinButton {
                  visible: root.spellingContextRange !== null
                  width: parent.width
                  text: "Ignore this session"
                  leftAlign: true
                  focusable: true
                  onClicked: root.ignoreSpellingContext()
                }

                JotPinButton {
                  visible: root.spellingContextRange !== null
                  width: parent.width
                  text: "Add to dictionary"
                  leftAlign: true
                  focusable: true
                  onClicked: root.addSpellingContextToDictionary()
                }

                Rectangle {
                  visible: root.spellingContextRange !== null
                  width: parent.width
                  height: Math.max(1, Style.space(1))
                  color: root.border
                }

                JotPinButton {
                  width: parent.width
                  text: "Undo"
                  leftAlign: true
                  enabled: root.editorCanUndo
                  focusable: true
                  tooltipText: "Undo (Ctrl+Z)"
                  onClicked: root.performEditorContextAction("undo")
                }

                JotPinButton {
                  width: parent.width
                  text: "Redo"
                  leftAlign: true
                  enabled: root.editorCanRedo
                  focusable: true
                  tooltipText: "Redo (Ctrl+Y / Ctrl+Shift+Z)"
                  onClicked: root.performEditorContextAction("redo")
                }

                Rectangle {
                  width: parent.width
                  height: Math.max(1, Style.space(1))
                  color: root.border
                }

                JotPinButton {
                  width: parent.width
                  text: "Cut"
                  leftAlign: true
                  enabled: editor.selectionStart !== editor.selectionEnd
                  focusable: true
                  tooltipText: "Cut (Ctrl+X)"
                  onClicked: root.performEditorContextAction("cut")
                }

                JotPinButton {
                  width: parent.width
                  text: "Copy"
                  leftAlign: true
                  enabled: editor.selectionStart !== editor.selectionEnd
                  focusable: true
                  tooltipText: "Copy (Ctrl+C)"
                  onClicked: root.performEditorContextAction("copy")
                }

                JotPinButton {
                  width: parent.width
                  text: "Paste"
                  leftAlign: true
                  enabled: editor.canPaste
                  focusable: true
                  tooltipText: "Paste (Ctrl+V)"
                  onClicked: root.performEditorContextAction("paste")
                }

                Rectangle {
                  width: parent.width
                  height: Math.max(1, Style.space(1))
                  color: root.border
                }

                JotPinButton {
                  width: parent.width
                  text: "Select All"
                  leftAlign: true
                  focusable: true
                  tooltipText: "Select All (Ctrl+A)"
                  onClicked: root.performEditorContextAction("selectAll")
                }
              }
            }

            Rectangle {
              id: tableHelperBar
              parent: editorViewport.contentItem
              readonly property bool helperActive: Boolean(
                root.activeTableToolbarState.active) &&
                !root.rawMode && !root.loadingFromFile
              readonly property bool repairNeeded: Boolean(
                root.activeTableToolbarState.needsRepair)
              readonly property real tableGap: 4
              readonly property real buttonHeight: 18
              readonly property real oneRowWidth: Style.space(8) +
                Style.space(30) * 8 +
                Math.max(1, Style.space(1)) * 2 +
                Style.space(3) * 9
              readonly property real desiredWidth: Math.min(
                Math.max(0, editorViewport.width - Style.space(10)),
                oneRowWidth)
              readonly property real desiredHeight:
                desiredWidth + 0.5 >= oneRowWidth
                  ? 22 : buttonHeight * 2 + Style.space(3) + 4
              readonly property int geometryRevision:
                renderedEditor.layoutRevision
              readonly property var tableSlotGeometry: {
                var revision = geometryRevision
                if (!helperActive || !renderedEditor.layoutMatchesCurrentInput())
                  return null
                return renderedEditor.tableToolbarSlotRectangle()
              }
              readonly property var tableGeometry: {
                var revision = geometryRevision
                if (!helperActive || !renderedEditor.layoutMatchesCurrentInput())
                  return null
                return renderedEditor.cursorRectangleForSource(
                  Number(root.activeTableToolbarState.tableContentStart))
              }
              readonly property real tableCellTopInset: Math.max(4,
                Math.round(renderedEditor.bodyPixelSize * 0.35)) + 1
              readonly property real tableTopY: tableGeometry
                ? Number(tableGeometry.y) - tableCellTopInset : -1
              readonly property real previousContentBottom: tableGeometry
                ? Number(renderedEditor.previousBlockBottomForSource(
                    Number(root.activeTableToolbarState.tableStart))) : -1
              readonly property real baseTableGap: helperActive
                ? desiredHeight + tableGap : 0
              readonly property int tableSourceStart: helperActive
                ? Number(root.activeTableToolbarState.tableStart) : -1
              function contentFitsForTests() {
                return !visible ||
                  (tableHelperFlow.x + tableHelperFlow.childrenRect.x +
                    tableHelperFlow.childrenRect.width <= width + 0.5 &&
                   tableHelperFlow.y + tableHelperFlow.childrenRect.y +
                    tableHelperFlow.childrenRect.height <= height + 0.5)
              }
              visible: helperActive && tableSlotGeometry !== null &&
                tableGeometry !== null &&
                Math.abs(Number(renderedEditor.tableToolbarGap) -
                  baseTableGap) <= 0.5
              x: visible ? Number(tableSlotGeometry.x) : 0
              y: visible ? Math.max(0, tableTopY - height - tableGap) : 0
              width: helperActive ? desiredWidth : 0
              height: helperActive ? desiredHeight : 0
              radius: Style.space(4)
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.07)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.28)
              border.width: visible ? Math.max(1, Style.space(1)) : 0
              z: 5

              Flow {
                id: tableHelperFlow
                x: Style.space(4)
                y: 2
                width: Math.max(0, parent.width - Style.space(8))
                spacing: Style.space(3)

                JotPinButton {
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "↑＋"
                  iconSize: Style.font.body
                  focusable: true
                  tooltipText: "Insert row above"
                  onClicked: root.performTableAction("rowBefore")
                }

                JotPinButton {
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "↓＋"
                  iconSize: Style.font.body
                  focusable: true
                  tooltipText: "Insert row below"
                  onClicked: root.performTableAction("rowAfter")
                }

                JotPinButton {
                  id: deleteTableRowButton
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "↕−"
                  iconSize: Style.font.body
                  enabled: Boolean(
                    root.activeTableToolbarState.canDeleteRow)
                  focusable: true
                  tooltipText: enabled
                    ? "Delete current row"
                    : "The header row cannot be deleted"
                  onClicked: root.performTableAction("rowDelete")
                }

                Rectangle {
                  width: Math.max(1, Style.space(1))
                  height: 14
                  color: Qt.rgba(root.foreground.r, root.foreground.g,
                    root.foreground.b, 0.24)
                }

                JotPinButton {
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "←＋"
                  iconSize: Style.font.body
                  focusable: true
                  tooltipText: "Insert column to the left"
                  onClicked: root.performTableAction("columnBefore")
                }

                JotPinButton {
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "→＋"
                  iconSize: Style.font.body
                  focusable: true
                  tooltipText: "Insert column to the right"
                  onClicked: root.performTableAction("columnAfter")
                }

                JotPinButton {
                  id: deleteTableColumnButton
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "↔−"
                  iconSize: Style.font.body
                  enabled: Boolean(
                    root.activeTableToolbarState.canDeleteColumn)
                  focusable: true
                  tooltipText: enabled
                    ? "Delete current column"
                    : "A table needs at least one column"
                  onClicked: root.performTableAction("columnDelete")
                }

                JotPinButton {
                  id: repairTableButton
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "↻"
                  iconSize: Style.font.body
                  enabled: tableHelperBar.repairNeeded
                  focusable: true
                  tooltipText: enabled
                    ? "Repair table structure and preserve cell text"
                    : "Table structure is valid"
                  onClicked: root.performTableAction("tableRepair")
                }

                Rectangle {
                  width: Math.max(1, Style.space(1))
                  height: 14
                  color: Qt.rgba(root.foreground.r, root.foreground.g,
                    root.foreground.b, 0.24)
                }

                JotPinButton {
                  width: Style.space(30)
                  height: tableHelperBar.buttonHeight
                  iconText: "󰆴"
                  iconSize: Style.font.body
                  focusable: true
                  tooltipText: "Delete the entire table"
                  onClicked: root.performTableAction("tableDelete")
                }
              }
            }

            Flickable {
              id: editorViewport
              objectName: "startupEditorViewport"
              opacity: root.startupContentRevealed ? 1 : 0
              enabled: root.startupContentRevealed
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: editorCommandBar.visible
                ? editorCommandBar.bottom : parent.top
              anchors.bottom: parent.bottom
              anchors.topMargin: editorCommandBar.visible ? Style.space(5) : 0
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              // Keep normal touch/flick interaction, but do not let physical
              // mouse buttons pan the viewport and steal text selection.
              acceptedButtons: Qt.NoButton
              contentWidth: width
              contentHeight: Math.max(
                height,
                editor.contentHeight,
                renderedEditor.implicitHeight)
              onContentYChanged: {
                root.queueSpellingGeometryUpdate()
                if (!root.loadingFromFile && !root.restoringEditorState)
                  editorStateSaveTimer.restart()
              }
              onWidthChanged: root.queueSpellingGeometryUpdate()

              WheelHandler {
                id: editorWheelHandler
                target: null

                onWheel: function(event) {
                  var delta = Number(event.pixelDelta.y)
                  if (!delta) delta = Number(event.angleDelta.y) / 8
                  if (!isFinite(delta) || delta === 0) return
                  root.scrollEditorByWheel(delta)
                  event.accepted = true
                }
              }

              MouseArea {
                id: editorCursorArea
                anchors.fill: parent
                z: -1
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
                cursorShape: Qt.IBeamCursor
              }

              ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
              }

              NativeMarkdownDisplay {
                id: renderedEditor
                objectName: "startupRenderer"
                visible: !root.rawMode
                z: 1
                x: 0
                y: 0
                width: editorViewport.width
                height: Math.max(editorViewport.height, implicitHeight)
                viewportRenderingEnabled: true
                viewportY: editorViewport.contentY
                viewportHeight: editorViewport.height
                viewportOverscan: Math.max(
                  editorViewport.height, Style.space(320))
                tableToolbarSourceStart: tableHelperBar.helperActive
                  ? Number(root.activeTableToolbarState.tableStart) : -1
                tableToolbarGap: tableHelperBar.helperActive
                  ? tableHelperBar.baseTableGap : 0
                sourceText: editor.text
                cursorPosition: editor.cursorPosition
                selectionStart: editor.selectionStart
                selectionEnd: editor.selectionEnd
                selectionRenderingEnabled: !root.rawMode
                selectionFill: Style.selectionFillFor(root.foreground, Color.accent)
                foreground: root.foreground
                background: root.editorBackground
                surfaceBackground: root.background
                accent: Color.accent
                baseUrl: root.fileUrlForPath(root.noteDirectory + "/")
                homePath: root.home
                fontFamily: Style.font.family
                bodyPixelSize: root.editorPixelSize
                bodyCaretHeight: editor.cursorRectangle.height
                taskCheckboxSize: Style.space(11)
                controlKeyHeld: root.controlKeyHeld
                interactiveEditsEnabled: !root.loadingFromFile &&
                  root.pendingEditorStateRestorePath === ""
                onTaskToggled: function(sourcePosition) {
                  root.toggleTask(sourcePosition)
                }
                onImageResizeRequested: function(sourceStart, sourceEnd, width) {
                  root.resizeMarkdownImage(sourceStart, sourceEnd, width)
                }
                onLinkActivated: function(target) {
                  root.externalUrlOpener(target)
                }
                onSourcePositionRequested: function(sourcePosition) {
                  if (root.rawMode || root.loadingFromFile) return
                  root.resetLiveVerticalNavigation()
                  editor.forceActiveFocus()
                  editor.cursorPosition = Math.max(0,
                    Math.min(Number(sourcePosition) || 0, editor.length))
                  Qt.callLater(root.syncLiveCursor)
                }
                onSourceSelectionRequested: function(anchorPosition,
                    sourcePosition) {
                  if (root.rawMode || root.loadingFromFile) return
                  root.resetLiveVerticalNavigation()
                  var anchor = Math.max(0, Math.min(
                    Number(anchorPosition) || 0, editor.length))
                  var target = Math.max(0, Math.min(
                    Number(sourcePosition) || 0, editor.length))
                  editor.forceActiveFocus()
                  editor.select(anchor, target)
                }
                onHeightIndexAdjusted: function(delta, blockTop) {
                  if (root.rawMode || root.restoringEditorState ||
                      root.pendingEditorStateRestorePath !== "" ||
                      Number(blockTop) + renderedEditor.verticalPadding >=
                        editorViewport.contentY) return
                  var anchoredY = Math.max(0,
                    Number(editorViewport.contentY) + Number(delta))
                  Qt.callLater(function() {
                    editorViewport.contentY = Math.max(0, Math.min(
                      Math.max(0, editorViewport.contentHeight -
                        editorViewport.height), anchoredY))
                  })
                }
              }

              Connections {
                target: renderedEditor
                function onLayoutUpdated() {
                  // Native document geometry is already queryable here. Move
                  // the caret immediately and retain one polish-frame retry
                  // for table/overlay geometry that settles asynchronously.
                  root.syncLiveCursor()
                  if (!liveCursorGeometrySettle.running)
                    liveCursorGeometrySettle.start()
                  root.queueSpellingGeometryUpdate()
                  Qt.callLater(root.finishPendingEditorStateRestore)
                }
              }

              TextEdit {
                id: editor
                x: 0
                y: 0
                width: editorViewport.width
                height: Math.max(editorViewport.height, contentHeight)
                enabled: !root.loadingFromFile && !root.recoveryPromptOpen &&
                  root.noteLoadError === ""
                color: root.rawMode ? root.foreground : "transparent"
                selectionColor: root.rawMode
                  ? Style.selectionFillFor(root.foreground, Color.accent)
                  : "transparent"
                selectedTextColor: root.rawMode ? root.foreground : "transparent"
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: root.rawMode
                activeFocusOnPress: root.rawMode
                persistentSelection: true
                cursorVisible: root.rawMode && activeFocus
                cursorDelegate: Rectangle {
                  visible: root.rawMode
                  width: Math.max(1, Style.space(1))
                  height: editor.cursorRectangle.height
                  color: root.rawMode ? root.foreground : "transparent"
                }
                font.family: Style.font.family
                font.pixelSize: root.editorPixelSize
                leftPadding: Style.spacing.panelPadding
                rightPadding: Style.spacing.panelPadding
                topPadding: Style.spacing.panelPadding
                bottomPadding: Style.spacing.panelPadding
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  if (root.handleEditorFileNavigationKey(event)) {
                    root.clearHistoryInputState()
                    return
                  }
                  if (root.handleEditorHistoryKey(event)) {
                    root.clearHistoryInputState()
                    return
                  }
                  if ((event.key === Qt.Key_Return ||
                      event.key === Qt.Key_Enter) &&
                      !(event.modifiers & (Qt.ShiftModifier |
                        Qt.ControlModifier | Qt.AltModifier |
                        Qt.MetaModifier))) {
                    root.normalizeLiveReturnCursor()
                  }
                  root.captureHistoryInputState(event.key, event.modifiers)
                  if (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down)
                    root.resetLiveVerticalNavigation()
                  if (event.key === Qt.Key_Control) {
                    root.controlKeyHeld = true
                  }
                  if ((event.key === Qt.Key_Tab ||
                      event.key === Qt.Key_Backtab) &&
                      !(event.modifiers & (Qt.ControlModifier |
                        Qt.AltModifier | Qt.MetaModifier))) {
                    var indentDirection = event.key === Qt.Key_Backtab ||
                      (event.modifiers & Qt.ShiftModifier) ? -1 : 1
                    if (root.handleIndent(indentDirection))
                      event.accepted = true
                    return
                  }
                  if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) &&
                      !(event.modifiers & (Qt.ShiftModifier |
                        Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    if (root.handleFenceHeaderReturn() ||
                        root.handleListReturn() || root.handlePlainReturn()) {
                      event.accepted = true
                    }
                    return
                  }
                  if (event.key === Qt.Key_Space &&
                      !(event.modifiers & (Qt.ShiftModifier |
                        Qt.ControlModifier | Qt.AltModifier |
                        Qt.MetaModifier))) {
                    if (root.handleHeadingSpace()) event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Backspace &&
                      !(event.modifiers & (Qt.ShiftModifier |
                        Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    if (root.handleBackspace()) event.accepted = true
                    return
                  }
                  if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) &&
                      !(event.modifiers & (Qt.ShiftModifier |
                        Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    var horizontalDirection = event.key === Qt.Key_Right ? 1 : -1
                    var horizontalTarget = root.horizontalListBoundaryTarget(
                      horizontalDirection)
                    if (horizontalTarget >= 0) {
                      editor.cursorPosition = horizontalTarget
                      event.accepted = true
                      return
                    }
                  }
                  if (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down) return
                  if (event.modifiers & (Qt.ControlModifier |
                      Qt.AltModifier | Qt.MetaModifier)) return
                  var direction = event.key === Qt.Key_Down ? 1 : -1
                  var extendSelection = Boolean(
                    event.modifiers & Qt.ShiftModifier)
                  if (root.moveLiveCursorVertically(direction,
                      extendSelection) ||
                      root.moveAcrossMarkdownGap(direction,
                        extendSelection)) {
                    event.accepted = true
                  }
                }
                Keys.onReleased: function(event) {
                  if (event.key === Qt.Key_Control) {
                    root.controlKeyHeld = false
                  }
                }
                onTextChanged: {
                  var sourceBefore = String(root.editorPreviousText || "")
                  root.invalidateSpellcheckForSourceChange(
                    sourceBefore, String(text || ""))
                  root.resetLiveVerticalNavigation()
                  if (root.editorUpdating || root.editorAutoFormatting) {
                    root.editorPreviousText = String(text || "")
                    return
                  }
                  var historyBefore = root.fileEditorStateForPath(root.notePath)
                  var historyCursor = root.historyInputStateValid &&
                    root.historyInputBeforeSource === sourceBefore
                    ? root.historyInputBeforeCursor
                    : historyBefore.cursorPosition
                  var historySelectionStart = root.historyInputStateValid &&
                    root.historyInputBeforeSource === sourceBefore
                    ? root.historyInputBeforeSelectionStart
                    : historyBefore.selectionStart
                  var historySelectionEnd = root.historyInputStateValid &&
                    root.historyInputBeforeSource === sourceBefore
                    ? root.historyInputBeforeSelectionEnd
                    : historyBefore.selectionEnd
                  root.recoverNativeListReturn(sourceBefore,
                    String(text || ""), historyCursor,
                    historySelectionStart, historySelectionEnd)
                  root.trackAutoFenceEdit(String(text || ""))
                  if (!root.completeCodeFence()) {
                    if (!root.completeCodePair()) root.completeListMarker()
                  }
                  if (String(editor.text || "") !== sourceBefore) {
                    root.recordEditorHistory(sourceBefore,
                      historyCursor, historySelectionStart,
                      historySelectionEnd, true)
                    root.noteEdited()
                  }
                  root.clearHistoryInputState()
                }
                onCursorRectangleChanged: {
                  // A source-preserving programmatic replacement briefly
                  // moves the hidden TextEdit cursor through the replaced
                  // range. Do not let that transient geometry pull the Live
                  // viewport away from the checkbox or control the user
                  // clicked. Explicit edit actions scroll after settling when
                  // they actually intend to reveal a new caret position.
                  if (root.editorUpdating || root.editorAutoFormatting) return
                  Qt.callLater(root.ensureEditorCursorVisible)
                }
                onCursorPositionChanged: {
                  // Preserve the last valid caret until the renderer's bound
                  // cursor position and source layout have caught up.
                  Qt.callLater(root.syncLiveCursor)
                  if (!root.loadingFromFile && !root.restoringEditorState)
                    editorStateSaveTimer.restart()
                }
                onSelectionStartChanged: if (!root.loadingFromFile &&
                    !root.restoringEditorState) editorStateSaveTimer.restart()
                onSelectionEndChanged: if (!root.loadingFromFile &&
                    !root.restoringEditorState) editorStateSaveTimer.restart()
                onActiveFocusChanged: Qt.callLater(root.syncLiveCursor)
              }

              Repeater {
                id: spellingUnderlineRepeater
                model: spellingUnderlineVisualModel

                delegate: Canvas {
                  required property real segmentX
                  required property real segmentY
                  required property real segmentWidth
                  x: segmentX
                  y: segmentY
                  width: segmentWidth
                  height: Style.space(4)
                  z: 2
                  renderTarget: Canvas.Image

                  onPaint: {
                    var context = getContext("2d")
                    context.clearRect(0, 0, width, height)
                    context.beginPath()
                    context.strokeStyle = "#e06c75"
                    context.lineWidth = Math.max(1, Style.space(1))
                    context.moveTo(0, 1)
                    for (var waveX = 0; waveX <= width; waveX += 2)
                      context.lineTo(waveX, waveX % 4 === 0 ? 1 : 3)
                    context.stroke()
                  }

                  Component.onCompleted: {
                    root.spellingUnderlineDelegateCreateCount++
                    requestPaint()
                  }
                  onWidthChanged: requestPaint()
                }
              }

              MouseArea {
                id: liveEditorMouseShield
                anchors.fill: parent
                z: 0
                enabled: !root.rawMode
                acceptedButtons: Qt.LeftButton

                // Rendered Markdown owns Live-mode mouse placement. Keep the
                // transparent source editor from interpreting an unhandled
                // pixel with its different plain-text layout.
                onPressed: mouse.accepted = true
              }

              MouseArea {
                id: editorContextMouseArea
                anchors.fill: parent
                z: 3
                acceptedButtons: Qt.RightButton

                onPressed: function(mouse) {
                  var sourcePoint = root.rawMode
                    ? editorContextMouseArea.mapToItem(
                      editor, mouse.x, mouse.y)
                    : editorContextMouseArea.mapToItem(
                      renderedEditor, mouse.x, mouse.y)
                  var sourcePosition = root.rawMode
                    ? editor.positionAt(sourcePoint.x, sourcePoint.y)
                    : renderedEditor.sourcePositionForPoint(
                      sourcePoint.x, sourcePoint.y)
                  var framePoint = editorContextMouseArea.mapToItem(
                    editorFrame, mouse.x, mouse.y)
                  root.openEditorContextMenuAt(
                    framePoint.x, framePoint.y, sourcePosition)
                  mouse.accepted = true
                }
              }

              Rectangle {
                id: liveCursor
                objectName: "liveCursor"
                x: renderedEditor.x + root.liveCursorRect.x
                y: renderedEditor.y + root.liveCursorRect.y
                width: Math.max(1, Style.space(1))
                height: Math.max(1, root.liveCursorRect.height)
                color: Color.accent
                visible: !root.rawMode
                  && renderedEditor.selectedImageIndex < 0
                  && editor.activeFocus
                  && root.liveCursorVisible
                  && root.liveCursorRect.height > 0
                z: 2
              }

              Text {
                id: editorPlaceholder
                visible: !root.loadingFromFile && root.noteLoadError === "" &&
                  editor.text.length === 0
                x: renderedEditor.x + editor.cursorRectangle.x
                y: renderedEditor.y + editor.cursorRectangle.y
                text: "Start writing your note…"
                color: Qt.darker(root.foreground, 1.6)
                font.family: Style.font.family
                font.pixelSize: root.editorPixelSize
                enabled: false
                z: 1
              }
            }

            Rectangle {
              visible: !root.startupContentRevealed && root.noteLoadError === ""
              anchors.fill: parent
              color: root.editorBackground

              Column {
                anchors.centerIn: parent
                spacing: Style.spacing.controlGap
                visible: root.startupMessageVisible
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Loading note…"
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                JotPinButton {
                  objectName: "startupSourceRecovery"
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.startupRecoveryVisible && !root.loadingFromFile
                  text: "Show source"
                  focusable: true
                  onClicked: {
                    root.rawMode = true
                    root.finishPendingEditorStateRestore()
                  }
                }
              }
            }

            Rectangle {
              visible: !root.loadingFromFile && root.noteLoadError !== ""
              anchors.fill: parent
              color: root.editorBackground
              z: 5

              Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.space(32), Style.space(420))
                spacing: Style.space(10)

                Text {
                  width: parent.width
                  text: root.noteLoadError === "missing"
                    ? "This note no longer exists on disk."
                    : root.noteLoadError === "stalled"
                      ? "JotPin could not finish loading this note."
                      : "This note exists, but JotPin could not read it."
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: parent.width
                  text: root.noteLoadError === "missing"
                    ? "Create an empty file explicitly, or choose Save As."
                    : root.noteLoadError === "stalled"
                      ? "Retry it or choose another note. The file was not changed."
                      : "Check its permissions or choose another note. JotPin will not overwrite it."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  horizontalAlignment: Text.AlignHCenter
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.spacing.controlGap

                  JotPinButton {
                    visible: root.noteLoadError === "missing"
                    text: "Create empty file"
                    focusable: true
                    onClicked: root.createNewNote()
                  }

                  JotPinButton {
                    visible: root.noteLoadError === "stalled"
                    text: "Retry"
                    focusable: true
                    onClicked: root.retryNoteLoad()
                  }

                  JotPinButton {
                    text: "Save As…"
                    focusable: true
                    onClicked: root.openSaveAs()
                  }
                }
              }
            }


            Rectangle {
              visible: !root.loadingFromFile && root.externalConflict
              anchors.fill: parent
              color: root.editorBackground
              z: 6

              Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.space(32), Style.space(440))
                spacing: Style.space(10)

                Text {
                  width: parent.width
                  text: root.externalConflictMissing
                    ? "This note was removed or became unreadable on disk."
                    : "This note changed in another editor."
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: parent.width
                  text: "Your JotPin edits are still in memory. Choose which version to keep."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  horizontalAlignment: Text.AlignHCenter
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.spacing.controlGap

                  JotPinButton {
                    visible: !root.externalConflictMissing
                    text: "Reload disk version"
                    focusable: true
                    onClicked: root.reloadAfterExternalChange()
                  }

                  JotPinButton {
                    text: root.externalConflictMissing
                      ? "Recreate with mine" : "Keep mine"
                    focusable: true
                    onClicked: root.keepMineAfterExternalChange()
                  }
                }
              }
            }
          }

          Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.ceil(footerFontMetrics.height * 2 + Style.space(4))

            Column {
              id: footerSideColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: Style.space(4)

              Text {
                id: footerStatus
                width: parent.width
                text: root.statusText
                color: root.dirty ? Color.accent : Qt.darker(root.foreground, 1.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Row {
                id: footerShortcutRow
                width: parent.width
                height: Math.ceil(footerFontMetrics.height)
                spacing: Style.space(6)

                Text {
                  id: shortcutHint
                  width: Math.max(0, parent.width - shortcutMoreButton.width -
                    parent.spacing)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.shortcutSave + " save · " + root.shortcutNew +
                    " new · " + root.shortcutHelp + " shortcuts"
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                JotPinButton {
                  id: shortcutMoreButton
                  height: parent.height
                  text: root.shortcutHelpOpen ? "Show less" : "Show more"
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(5)
                  verticalPadding: 0
                  focusable: true
                  selected: root.shortcutHelpOpen
                  tooltipText: "Show all JotPin keyboard shortcuts (" +
                    root.shortcutHelp + ")"
                  onClicked: root.toggleShortcutHelp()
                }
              }
            }
          }

          Rectangle {
            id: shortcutHelpCard
            visible: root.shortcutHelpOpen
            z: 10
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.bottomMargin: Style.space(8)
            width: Math.min(parent.width, Style.space(430))
            height: shortcutHelpColumn.implicitHeight +
              Style.spacing.panelPadding * 2
            color: root.background
            radius: Style.cornerRadius
            border.color: root.border
            border.width: Math.max(1, Style.space(1))

            MouseArea {
              anchors.fill: parent
              onClicked: function(mouse) { mouse.accepted = true }
            }

            Column {
              id: shortcutHelpColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.spacing.panelPadding
              spacing: Style.space(7)

              Text {
                text: "Keyboard shortcuts"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Repeater {
                id: shortcutHelpRepeater
                model: root.shortcutHelpEntries

                delegate: Row {
                  readonly property real keyColumnWidth: Math.min(
                    Style.space(210), Math.max(Style.space(150), width * 0.52))
                  readonly property real keyPaintedOverflow: Math.max(0,
                    keyLabel.paintedWidth - keyLabel.width)
                  readonly property real actionPaintedOverflow: Math.max(0,
                    actionLabel.paintedWidth - actionLabel.width)
                  readonly property bool labelsSeparated:
                    keyPaintedOverflow <= 0.5 &&
                    actionPaintedOverflow <= 0.5 &&
                    keyLabel.x + keyLabel.width + spacing <=
                      actionLabel.x + 0.5
                  width: shortcutHelpColumn.width
                  spacing: Style.space(12)

                  Text {
                    id: keyLabel
                    width: parent.keyColumnWidth
                    text: modelData.keys
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    verticalAlignment: Text.AlignTop
                  }

                  Text {
                    id: actionLabel
                    width: Math.max(0, parent.width - parent.keyColumnWidth -
                      parent.spacing)
                    text: modelData.action
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    verticalAlignment: Text.AlignTop
                  }
                }
              }
            }
          }

          Item {
            id: settingsOverlay
            objectName: "settingsOverlay"
            visible: root.settingsOpen
            z: 25
            anchors.fill: parent

            Rectangle {
              anchors.fill: parent
              color: root.scrim

              MouseArea {
                anchors.fill: parent
                onClicked: root.closeSettings()
              }
            }

            Rectangle {
              id: settingsCard
              objectName: "settingsCard"
              width: Math.min(Style.space(560), parent.width - Style.space(24))
              height: Math.min(Style.space(620), parent.height - Style.space(24))
              anchors.centerIn: parent
              color: root.background
              radius: Style.cornerRadius
              border.color: root.border
              border.width: Math.max(1, Style.space(1))
              clip: true

              // Consume clicks on padding and blank areas inside the popup.
              MouseArea {
                anchors.fill: parent
                onClicked: mouse.accepted = true
              }

              Item {
                id: settingsHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.panelPadding
                height: Math.max(settingsTitle.implicitHeight,
                  settingsVersion.implicitHeight)

                Text {
                  id: settingsTitle
                  anchors.left: parent.left
                  anchors.right: settingsVersion.left
                  anchors.rightMargin: Style.spacing.controlGap
                  anchors.verticalCenter: parent.verticalCenter
                  text: "JotPin settings"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  id: settingsVersion
                  objectName: "settingsVersion"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.manifest && root.manifest.version
                    ? "v" + String(root.manifest.version) : ""
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              ScrollView {
                id: settingsScrollView
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: settingsHeader.bottom
                anchors.bottom: settingsActions.top
                anchors.margins: Style.spacing.panelPadding
                clip: true
                contentWidth: availableWidth

                Column {
                id: settingsColumn
                  width: settingsScrollView.availableWidth
                  spacing: Style.space(9)

                Text {
                  width: parent.width
                  text: "Choose where Side opens, where new notes are created, " +
                    "how many file-tab rows to show, and how JotPin commands " +
                    "are invoked."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: root.sideMode
                  text: "Side drawer edge"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Row {
                  visible: root.sideMode
                  spacing: Style.spacing.controlGap

                  JotPinButton {
                    text: "Left"
                    selected: root.sideLeftMode
                    focusable: true
                    tooltipText: "Mount the Side drawer to the left edge"
                    onClicked: root.setSidePlacement("left")
                  }

                  JotPinButton {
                    text: "Right"
                    selected: root.sideRightMode
                    focusable: true
                    tooltipText: "Mount the Side drawer to the right edge"
                    onClicked: root.setSidePlacement("right")
                  }
                }

                Text {
                  text: "Default notes folder"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                TextField {
                  id: settingsDefaultNotesDirectoryField
                  width: parent.width
                  height: Style.space(36)
                  text: root.settingsDefaultNotesDirectory
                  placeholderText: root.builtinNotesDirectory
                  selectByMouse: true
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  enabled: !root.settingsDirectoryChangeInFlight
                  onTextChanged: if (activeFocus) {
                    root.settingsDefaultNotesDirectory = text
                    root.settingsMessage = ""
                  }
                  onAccepted: root.applyDefaultNotesDirectory(text)
                }

                Row {
                  spacing: Style.spacing.controlGap

                  JotPinButton {
                    text: root.settingsDirectoryChangeInFlight
                      ? "Applying…" : "Apply folder"
                    enabled: !root.settingsDirectoryChangeInFlight
                    focusable: true
                    onClicked: root.applyDefaultNotesDirectory(
                      settingsDefaultNotesDirectoryField.text)
                  }

                  JotPinButton {
                    text: "Reset"
                    enabled: !root.settingsDirectoryChangeInFlight
                    focusable: true
                    onClicked: root.resetDefaultNotesDirectory()
                  }
                }

                Text {
                  visible: root.settingsMessage !== ""
                  text: root.settingsMessage
                  color: root.settingsMessage.indexOf("Could not") === 0
                    ? Color.accent : Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  width: parent.width
                  text: "New notes and the Open list use this folder. Existing " +
                    "notes are not moved."
                  color: Qt.darker(root.foreground, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  text: "Text size"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: "Adjust note text in Preview and Raw. Menus stay the same size."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Row {
                  spacing: Style.spacing.controlGap
                  JotPinButton {
                    objectName: "textSizeDecrease"
                    iconText: "−"
                    tooltipText: "Decrease text size"
                    Accessible.name: tooltipText
                    enabled: root.editorTextScale > 75
                    focusable: true
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.setEditorTextScale(root.editorTextScale - 10)
                  }
                  Text {
                    objectName: "textSizeLabel"
                    text: root.editorTextScale + "%"
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  JotPinButton {
                    objectName: "textSizeIncrease"
                    iconText: "+"
                    tooltipText: "Increase text size"
                    Accessible.name: tooltipText
                    enabled: root.editorTextScale < 200
                    focusable: true
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.setEditorTextScale(root.editorTextScale + 10)
                  }
                  JotPinButton {
                    objectName: "textSizeReset"
                    text: "Reset"
                    enabled: root.editorTextScale !== 100
                    focusable: true
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.setEditorTextScale(100)
                  }
                }

                Text {
                  id: fileTabRowsHeading
                  text: "File tab rows"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: "Show open notes across 1 to 5 rows. Additional rows " +
                    "reduce horizontal scrolling when several notes are open."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Row {
                  id: fileTabRowsSelector
                  spacing: Style.spacing.controlGap

                  Repeater {
                    model: root.maximumFileTabRows

                    delegate: JotPinButton {
                      required property int index
                      text: String(index + 1)
                      selected: root.fileTabRows === index + 1
                      focusable: true
                      tooltipText: "Use " + (index + 1) + " file-tab row" +
                        (index === 0 ? "" : "s")
                      onClicked: root.setFileTabRows(index + 1)
                    }
                  }
                }

                Text {
                  text: "Keyboard shortcuts"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: "Change the shortcuts for JotPin commands. Use a key " +
                    "with optional Ctrl, Alt, Shift, or Meta modifiers. " +
                    "Escape and editor undo/redo remain fixed."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                JotPinButton {
                  text: "Reset keyboard shortcuts"
                  focusable: true
                  onClicked: root.resetShortcuts()
                }

                Repeater {
                  model: root.shortcutSettingEntries

                  delegate: Column {
                    width: settingsColumn.width
                    spacing: Style.space(4)

                    Text {
                      width: parent.width
                      text: modelData.label
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      width: parent.width
                      text: modelData.description
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      wrapMode: Text.WordWrap
                    }

                    Row {
                      width: parent.width
                      spacing: Style.spacing.controlGap

                      TextField {
                        id: shortcutField
                        property int appliedRevision: root.shortcutRevision
                        width: Math.max(
                          Style.space(150),
                          parent.width - resetShortcutButton.implicitWidth -
                            Style.spacing.controlGap)
                        height: Style.space(36)
                        text: root.shortcutValue(modelData.id)
                        placeholderText: modelData.defaultValue
                        selectByMouse: true
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        onAppliedRevisionChanged: {
                          text = root.shortcutValue(modelData.id)
                        }
                        onAccepted: {
                          if (root.applyShortcut(modelData.id, text))
                            text = root.shortcutValue(modelData.id)
                        }
                        onEditingFinished: {
                          if (root.applyShortcut(modelData.id, text))
                            text = root.shortcutValue(modelData.id)
                        }
                      }

                      JotPinButton {
                        id: resetShortcutButton
                        text: "Reset"
                        focusable: true
                        onClicked: {
                          root.resetShortcut(modelData.id)
                          shortcutField.text = root.shortcutValue(modelData.id)
                        }
                      }
                    }
                  }
                }
              }
              }

              Row {
                id: settingsActions
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.spacing.panelPadding
                spacing: Style.spacing.controlGap

                JotPinButton {
                  text: "Done"
                  focusable: true
                  onClicked: root.closeSettings()
                }
              }
            }
          }

          Item {
            id: saveAsOverlay
            visible: root.saveAsOpen
            z: 20
            anchors.fill: parent

            Rectangle {
              anchors.fill: parent
              color: root.scrim

              MouseArea {
                anchors.fill: parent
                onClicked: mouse.accepted = true
              }
            }

            Rectangle {
              id: saveAsCard
              width: Math.min(Style.space(640), parent.width - Style.space(24))
              height: Math.min(Style.space(640), parent.height - Style.space(24))
              anchors.centerIn: parent
              color: root.background
              radius: Style.cornerRadius
              border.color: root.border
              border.width: Math.max(1, Style.space(1))

              Column {
                id: saveAsBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: saveAsActions.top
                anchors.margins: Style.spacing.panelPadding
                spacing: Style.space(8)

                Text {
                  text: root.fileChooserMode === "open"
                    ? "Open Markdown note"
                    : "Save Markdown note"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  text: root.fileChooserMode === "open"
                    ? "Choose an existing filename and folder."
                    : "Choose a filename and folder."
                  color: Qt.darker(root.foreground, 1.35)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Row {
                  visible: root.fileChooserMode === "open"
                  width: parent.width
                  height: visible ? Style.space(24) : 0
                  spacing: Style.spacing.controlGap

                  Text {
                    width: Math.max(0, parent.width - refreshOpenNotesButton.width -
                      parent.spacing)
                    text: "Notes in the default folder"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  JotPinButton {
                    id: refreshOpenNotesButton
                    text: "Refresh"
                    height: parent.height
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(6)
                    verticalPadding: 0
                    focusable: true
                    tooltipText: "Refresh Markdown notes in the default folder"
                    onClicked: root.loadOpenNoteFiles()
                  }
                }

                Rectangle {
                  id: openNoteListFrame
                  visible: root.fileChooserMode === "open"
                  width: parent.width
                  height: visible ? Style.space(132) : 0
                  color: root.editorBackground
                  radius: Style.cornerRadius
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                    root.foreground.b, 0.14)
                  border.width: Math.max(1, Style.space(1))

                  ListView {
                    id: openNoteList
                    anchors.fill: parent
                    anchors.margins: Style.space(4)
                    clip: true
                    model: root.openNoteFiles
                    spacing: Style.space(2)

                    delegate: JotPinButton {
                      width: openNoteList.width
                      height: Style.space(28)
                      text: modelData.name
                      leftAlign: true
                      focusable: true
                      tooltipText: modelData.path
                      onClicked: root.openFileSelected(modelData.path)
                    }

                    ScrollBar.vertical: ScrollBar {
                      policy: ScrollBar.AsNeeded
                    }
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: root.openNoteFilesLoading
                    text: "Loading notes…"
                    color: Qt.darker(root.foreground, 1.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    anchors.centerIn: parent
                    width: parent.width - Style.space(20)
                    visible: !root.openNoteFilesLoading &&
                      root.openNoteFiles.length === 0
                    text: "No Markdown notes found in " +
                      root.defaultNotesDirectory
                    color: Qt.darker(root.foreground, 1.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

                Text {
                  text: "Filename"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Row {
                  id: fileNameInputRow
                  width: parent.width
                  height: Style.space(34)
                  spacing: Style.space(2)

                  TextField {
                    id: saveAsNameField
                    width: Math.max(Style.space(64),
                      fileNameInputRow.width - markdownExtension.implicitWidth -
                        fileNameInputRow.spacing)
                    height: fileNameInputRow.height
                    text: root.saveAsName
                    placeholderText: "note"
                    selectByMouse: true
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    onTextChanged: if (activeFocus) {
                      root.saveAsName = text
                      root.fileChooserMessage = ""
                      root.saveAsOverwritePath = ""
                    }
                    onAccepted: root.submitFileChooser(text)
                    background: Rectangle {
                      color: root.editorBackground
                      radius: Style.cornerRadius
                      border.color: Qt.rgba(root.foreground.r,
                        root.foreground.g, root.foreground.b, 0.22)
                      border.width: Math.max(1, Style.space(1))
                    }
                  }

                  Text {
                    id: markdownExtension
                    text: ".md"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Text {
                  visible: root.fileChooserMessage !== ""
                  text: root.fileChooserMessage
                  color: Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Text {
                  text: "Folder"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Row {
                  id: folderPathRow
                  width: parent.width
                  spacing: Style.spacing.controlGap

                  TextField {
                    id: saveAsFolderField
                    width: folderPathRow.width - refreshFoldersButton.width -
                      folderPathRow.spacing
                    height: Style.space(34)
                    text: root.saveAsDirectory
                    selectByMouse: true
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    onTextChanged: if (activeFocus) {
                      root.saveAsDirectory = text
                      root.fileChooserMessage = ""
                      root.saveAsOverwritePath = ""
                    }
                    onEditingFinished: root.loadSaveFolders()
                    background: Rectangle {
                      color: root.editorBackground
                      radius: Style.cornerRadius
                      border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                        root.foreground.b, 0.22)
                      border.width: Math.max(1, Style.space(1))
                    }
                  }

                  JotPinButton {
                    id: refreshFoldersButton
                    height: folderPathRow.height
                    text: "Refresh"
                    focusable: true
                    onClicked: root.loadSaveFolders()
                  }
                }

                Text {
                  text: "Folders"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  id: folderListFrame
                  width: parent.width
                  height: Style.space(150)
                  color: root.editorBackground
                  radius: Style.cornerRadius
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                    root.foreground.b, 0.14)
                  border.width: Math.max(1, Style.space(1))

                  ListView {
                    id: folderList
                    anchors.fill: parent
                    anchors.margins: Style.space(4)
                    clip: true
                    model: root.saveAsFolders
                    spacing: Style.space(2)

                    delegate: JotPinButton {
                      width: folderList.width
                      height: Style.space(28)
                      text: modelData.name
                      focusable: true
                      onClicked: {
                        root.saveAsDirectory = modelData.path
                        root.saveAsOverwritePath = ""
                        root.fileChooserMessage = ""
                        root.loadSaveFolders()
                      }
                    }

                    ScrollBar.vertical: ScrollBar {
                      policy: ScrollBar.AsNeeded
                    }
                  }
                }
              }

              Row {
                id: saveAsActions
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.spacing.panelPadding
                spacing: Style.spacing.controlGap

                JotPinButton {
                  text: "Cancel"
                  focusable: true
                  onClicked: root.cancelSaveAs()
                }

                JotPinButton {
                  visible: root.fileChooserMode !== "open"
                  text: root.saveAsOverwritePath !== "" ? "Overwrite" : "Save"
                  focusable: true
                  onClicked: {
                    if (root.saveAsOverwritePath !== "")
                      root.confirmSaveAsOverwrite()
                    else
                      root.submitFileChooser(saveAsNameField.text)
                  }
                }

                JotPinButton {
                  visible: root.fileChooserMode === "open"
                  text: "Open"
                  focusable: true
                  onClicked: root.submitFileChooser(saveAsNameField.text)
                }
              }
            }
          }

          Item {
            id: recoveryOverlay
            visible: root.recoveryPromptOpen
            z: 30
            anchors.fill: parent

            Rectangle {
              anchors.fill: parent
              color: root.scrim

              MouseArea {
                anchors.fill: parent
                onClicked: mouse.accepted = true
              }
            }

            Rectangle {
              width: Math.min(Style.space(520), parent.width - Style.space(24))
              height: recoveryPromptColumn.implicitHeight +
                Style.spacing.panelPadding * 2
              anchors.centerIn: parent
              color: root.background
              radius: Style.cornerRadius
              border.color: root.border
              border.width: Math.max(1, Style.space(1))

              Column {
                id: recoveryPromptColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.panelPadding
                spacing: Style.space(10)

                Text {
                  text: "Recover unsaved changes?"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: "JotPin found an unsaved recovery snapshot for " +
                    root.fileNameForPath(root.recoveryPromptPath) +
                    ". Recovering it will replace the current note content."
                  color: Qt.darker(root.foreground, 1.25)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                Row {
                  anchors.right: parent.right
                  spacing: Style.spacing.controlGap

                  JotPinButton {
                    text: "Discard"
                    focusable: true
                    onClicked: root.discardRecovery()
                  }

                  JotPinButton {
                    text: "Recover"
                    focusable: true
                    onClicked: root.recoverSnapshot()
                  }
                }
              }
            }
          }
        }
      }
    }
}
