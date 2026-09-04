# Contributing to JotPin

Thanks for helping improve JotPin. It is an on-demand Omarchy shell plugin
whose editor keeps Markdown source intact while rendering it in a native
Quickshell view. Small, focused changes are easiest to review and maintain.

## Before you start

Use the issue forms for bug reports and feature requests. Search existing
issues first, and remove private note content, credentials, and unrelated
logs before sharing a reproduction. For a security problem, follow
[`SECURITY.md`](SECURITY.md) instead of opening a public issue.

## Development setup

Work from the repository root. JotPin runs on Omarchy with Quickshell; the
headless test suite also uses the tools listed in
[`tests/README.md`](tests/README.md). Normal runtime use does not need Node.js
or npm, but contributors need Node.js for the pure editor tests and the
bundled worker checks.

Use the narrowest check while iterating:

```bash
bash tests/run.sh model
bash tests/run.sh render
```

Before opening a pull request, run the complete isolated suite:

```bash
bash tests/run.sh headless
```

The headless suite uses disposable files and an offscreen Qt backend. It does
not summon JotPin, inject input, capture the desktop, or change your active
notes. Live compositor checks are required only for assertions that
need real window placement, focus, or other desktop behavior; say which live
behavior remains unverified when you cannot run one.

## Project structure

Start with the guide that matches your change:

- [`docs/editor-contracts.md`](docs/editor-contracts.md) defines the source,
  editor, rendering, persistence, and presentation invariants.
- [`docs/verification.md`](docs/verification.md) explains which checks cover
  executable and compositor behavior.
- [`tests/README.md`](tests/README.md) describes the fixtures and focused test
  commands.
- [`PORTING.md`](PORTING.md) documents the boundary for a future non-Omarchy
  host.

The main ownership boundaries are:

- [`JotPin.qml`](JotPin.qml) owns lifecycle, notes, tabs, persistence,
  settings, and presentation state.
- [`NativeMarkdownDisplay.qml`](NativeMarkdownDisplay.qml) owns the production
  Markdown document, source mapping, and rendered geometry.
- [`EditorModel.js`](EditorModel.js) owns pure source transitions such as
  lists, fences, tables, and image-size hints.

Preserve the user's Markdown source exactly. Keep source transitions in the
pure model when possible, keep one shared editor across presentations, and
make selection or cursor movement leave the note clean. Add or update an
isolated regression when a bug changes behavior.

## Pull requests

Use the pull request template. Describe the user-visible behavior, the files or
boundaries involved, the exact checks you ran, and any remaining uncertainty.
Include before-and-after screenshots or a short recording for visual changes
when that evidence helps review the result. Keep generated worker or
third-party files out of unrelated changes; when a dependency update requires
regeneration, explain it and update [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
as needed.

Contributions are distributed with JotPin under the
[GNU General Public License, version 3 only](LICENSE) (`GPL-3.0-only`). Keep
third-party code under its original license and preserve its notices.
