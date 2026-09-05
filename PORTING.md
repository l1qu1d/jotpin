# Porting JotPin to another Quickshell host

JotPin is Omarchy-first, with shell-agnostic support as its long-term goal.
Omarchy is the only supported host today. This document records the boundaries
a future port should use so the editor is not forked for every desktop shell.

## Reusable core

Keep these components shared across hosts:

- `EditorModel.js` and `SpellcheckModel.js` own source-preserving edit and
  spellcheck transitions.
- `NativeMarkdownDisplay.qml` owns Markdown parsing, rendered layout, source
  mapping, caret and selection geometry, tables, tasks, and images.
- `markdown/`, `spellcheck/`, `syntax/`, and `vendor/` contain the offline
  worker bundles and their pinned data.
- JotPin's note, tab, autosave, recovery, and settings formats are host-neutral
  unless a port documents a concrete incompatibility.

## Host integration contract

`JotPin.qml` accepts an optional `hostIntegration` object. Without one, the
built-in `HostIntegration.qml` adapter uses the Omarchy-injected `shell` and
`manifest` objects. A future host wrapper can inject an object with the same
small interface:

| Member | Meaning |
| --- | --- |
| `pluginId` | Stable identifier used when asking the host to hide JotPin. |
| `barPosition` | `top`, `right`, `bottom`, or `left`. |
| `liveBarSize` | Visible bar thickness in logical pixels, or `0`. |
| `screensaverActive` | Whether secure or idle UI should prevent focus. |
| `hidePanel()` | Requests that the host remove JotPin from its open-panel state. |

This contract is deliberately about lifecycle and work-area state. Editor
logic must not call a host shell object directly.

## Remaining port boundaries

A real port still needs deliberate integration work in three places:

1. Theme and controls: `JotPin.qml` currently imports Omarchy's `qs.Commons`
   and `qs.Ui`. Prefer a thin compatibility layer that maps the target shell's
   tokens and controls; do not fork the editor core for visual differences.
2. Presentation and compositor behavior: the current `FloatingWindow` titles,
   Hyprland event handling, and `hypr/jotpin*.lua` helpers preserve Omarchy's
   Side and Center behavior. A port must provide equivalent map, move, focus,
   fullscreen, and restore semantics using APIs native to its host.
3. Packaging: `manifest.json`, `omarchy-menu.jsonc`, and `install_safe.sh` are
   Omarchy distribution assets. Keep another host's packaging outside the
   shared runtime files when an actual port begins.

## Port acceptance checklist

- Reuse the shared editor, renderer, workers, and persisted note formats.
- Supply the host integration contract without adding target-shell checks
  throughout `JotPin.qml`.
- Preserve one editor instance while switching presentations.
- Keep both normal and special-workspace behavior explicit and testable.
- Run the existing headless suite unchanged, then add narrowly scoped host
  lifecycle tests for behavior that genuinely requires a compositor.
- Do not add an environment directory or compatibility claim until there is a
  maintained, tested port.
