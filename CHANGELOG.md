# Changelog

## [Unreleased]

## [1.0.1] - 2026-11-22

- Keep Side and Window presentations floating with bundled Hyprland rules.
- Wrap file tabs and improve horizontal wheel scrolling and scrollbar dragging.
- Keep the Live Preview caret on the intended row during typing, Enter,
  Backspace, and Markdown layout changes.
- Preserve literal Markdown markers while typing, align empty quote and table
  rows, and make empty checklist items clickable.
- Reduce editing latency and preserve complete emoji during Backspace.
- Refresh bundled Markdown dependencies and add editor and packaging regressions.
- Initialize private recovery storage at startup so recovery snapshots can be
  saved on fresh installations and after upgrades.

## [1.0.0] - 2026-09-05

- Initial release of JotPin, an on-demand Markdown scratchpad for Omarchy.
- Native Window and Side presentations with one shared editor, file tabs,
  autosave, recovery snapshots, and per-note undo and view state.
- Editable Markdown preview with syntax highlighting, checklists, tables,
  links, image resizing, spellcheck, and adjustable text size.
- Stable startup presentation with a loading fallback for slow content.
- Isolated regression tests, GitHub CI, contributor documentation, and
  security reporting guidance.
