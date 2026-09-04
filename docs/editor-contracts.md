# JotPin editor contracts

Read before changing editor, presentation, input, rendering, or persistence
behavior. These are the implementation requirements routed from
[AGENTS.md](../AGENTS.md); user notes and active sessions remain protected.

## Architecture and implementation rules

- Preserve the user's Markdown source exactly. The rendered Live view must not
  become the saved source.
- Keep source-transition logic in `EditorModel.js` when it can be expressed as
  a pure operation; cover it with the Node test before wiring it into QML.
- Keep production source-to-layout behavior in `NativeMarkdownDisplay.qml`.
  Caret and selection geometry must be derived from the same parser result and
  source revision as the visible native document.
- Standalone Preview images use the native rich-text image object for their
  selection frame and expose four aspect-preserving corner handles. A drag may
  repaint the native document at most once per frame, but it must not change
  Markdown until release; release records one undoable
  `<!-- jotpin:image width=N -->` source transition through `EditorModel.js`.
- Do not add WebEngine or a second production Markdown renderer. JotPin uses
  one bundled micromark/mdast worker and one Qt rich-text document to avoid
  shell instability and stale caret layouts.
- Do not hardcode compositor window-management shortcuts in JotPin. Both
  presentations must remain native Quickshell `FloatingWindow` xdg toplevels so
  current and future system/user fullscreen, maximize, move, resize, and
  restore bindings apply automatically.
- Do not allow either presentation to enter the tiled layout. Keep the
  JotPin-specific Hyprland rules narrow and presentation-specific, with
  distinct initial titles because static rules apply at map time. `Window`
  starts centered at the former theme-scaled `Style.space(900)` x
  `Style.space(700)` size; `Side` starts as a borderless, right-anchored floating
  drawer at its former theme-scaled width, occupies the bar-reserved work area,
  and exposes only an explicit left-edge horizontal resize affordance. Include
  Side's bar position in its initial title so top and bottom placement can be
  resolved at map time. Never apply the rules to every `org.quickshell` window.
- Keep one editor instance when switching between Side and Window. Reparent
  the shared content between the two native surfaces rather than creating a
  second editor that can diverge in text, undo history, caret, selection, or
  persistence state.
- Fenced-code highlighting uses JotPin's pinned, curated Highlight.js worker.
  Spellcheck uses the bundled `nspell` worker and English (US) dictionary.
  Keep both operations off the UI thread, and keep unknown language names
  readable as plain code.
- QML object ids are lexical references, not properties of `root`. Refer to
  `saveTimer`, `recoveryTimer`, and similar ids directly; never write
  `root.saveTimer` or `root.recoveryTimer`.
- A selection or cursor movement must not dirty the note. Only a real source
  change may call `noteEdited()`.
- Switching between Raw and Live Preview must preserve the source caret and
  scroll the destination so that caret remains visible at the same viewport Y
  position whenever bounds allow. Wait for current rendered geometry instead
  of restoring an unrelated saved per-view scroll offset during the toggle.
- Normal note and recovery writes must remain atomic. Do not report `Saved`
  optimistically: transition to it only after `FileView.onSaved` confirms the
  write.
- Preserve edits made while a write is in flight. The completion callback must
  compare the saved path/source with the current path/source and schedule the
  newer write when they differ.
- Production persistence defaults are a 1.5-second idle debounce and a
  recovery snapshot at most every 10 seconds while continuously dirty. A
  successful normal save removes its recovery snapshot.
- Recovery must wait for both the note and its per-note snapshot to load, then
  offer Recover or Discard only when the sources differ. Recover saves the
  recovered source; Discard leaves the normal note unchanged; both remove the
  snapshot after completion.
- Do not launch external processes per keystroke. Directory creation, explicit
  file operations, and serialized recovery cleanup are acceptable.
