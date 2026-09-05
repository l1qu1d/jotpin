# JotPin Development Guidance

## Project scope

JotPin is an on-demand Omarchy shell panel plugin. Its plugin id is
`dev.jotpin`, and it runs as unsandboxed QML inside the single long-running
`omarchy-shell` Quickshell process.

This checkout is the source of truth. The installed copy at `~/.config/omarchy/plugins/dev.jotpin` is a deployment
artifact. Never develop in the installed copy, and never modify packaged files
under `/usr/share/omarchy`; reading packaged Omarchy QML and modules is allowed.

JotPin is intentionally on-demand (`keepLoaded: false`). Do not change it into
a permanently loaded plugin without an explicit design decision and runtime
impact review.

Window and Side use native floating toplevels; their placement and shared-editor
invariants are defined in [docs/editor-contracts.md](docs/editor-contracts.md).

## Repository map

- `manifest.json`: Omarchy plugin metadata and panel entry point.
- `JotPin.qml`: panel lifecycle, editor input, files/tabs, autosave, recovery,
  shortcuts, and presentation state.
- `NativeMarkdownDisplay.qml`: production micromark/mdast source mapping,
  Qt rich-text layout, caret/selection geometry, fenced-code rendering, and
  syntax highlighting.
- `MarkdownDisplay.qml`: retired hand-written renderer retained only as a
  historical visual/performance oracle; it is not deployed.
- `EditorModel.js`: pure text-edit transitions such as fences, code pairs,
  lists, tags, and navigation boundaries.
- `install_safe.sh`: guarded deployment with timestamped backups.
- `hypr/jotpin.lua`: narrowly matched presentation-specific Hyprland
  map-time floating and placement integration.
- `tests/run.sh`: production test entrypoint; headless by default.
- `tests/README.md`: test coverage, fixtures, and focused commands. Read it
  before selecting regression checks; use the current runner as the suite list.
- `docs/deployment.md`: required deployment and failure-recovery procedure;
  read before any installation or shell interruption.

Runtime data belongs to the user, not the repository:

- default note: `~/Documents/Notes/welcome.md`
- presentation settings: `~/.local/state/jotpin/settings.json`
- recovery snapshots: `~/.local/state/jotpin/recovery/`
- deployment backups: `~/.local/state/jotpin/deploy-backups/`
- native window rule: `~/.config/hypr/jotpin.lua`, loaded once from the user's
  `~/.config/hypr/hyprland.lua`

Never use those real paths in automated tests. Tests must provide a private
HOME, note path, runtime directory, and recovery directory under a disposable
temporary directory.

## Task routing and essential contracts

Read only the references relevant to the change; reuse current contents already
loaded in context.

- Editor, rendering, source mapping, image resize, input, presentation, saving,
  or recovery changes: read [docs/editor-contracts.md](docs/editor-contracts.md).
  Preserve source Markdown, one shared editor, atomic writes, and confirmation
  of save completion. Selection or cursor movement must not dirty the note.
- Executable plugin, installer, or test-harness changes: read
  [docs/verification.md](docs/verification.md), then the relevant parts of
  [tests/README.md](tests/README.md) to select checks. The default is isolated
  headless testing; the coordinator owns the final integrated suite.
- Compositor-only behavior: read the desktop-interactive policy in
  [docs/verification.md](docs/verification.md). The smallest necessary live
  test is pre-authorized under that policy; warn before it and restore state.
  Do not use live tests as a generic smoke test or an edit-and-retry loop.
- Installation or shell interruption: read
  [docs/deployment.md](docs/deployment.md) before acting.
- Documentation-only work: verify paths, commands, links, and consistency.
  Do not run runtime suites or deploy solely because guidance changed.

## Deployment and shell safety

For user-requested JotPin implementation changes, the workflow automatically
deploys the tested checkout and restarts the Omarchy shell after validation so
the user can exercise the new build. Do not ask for a separate deployment
confirmation. Announce the brief shell interruption immediately before it
happens. Skip deployment for read-only diagnosis, reviews, documentation-only
work, or when the user explicitly says not to install/restart.

Passing tests alone is not enough to deploy an unrequested experiment. The
Omarchy shell owns the bar, notifications, settings, and plugins, so keep the
deployment scoped to completed user-requested changes and perform only one
stop/deploy/restart cycle after validation.

Never copy files directly into `~/.config/omarchy/plugins/dev.jotpin` while
Quickshell is running. Plugin writes trigger hot reloads inside the shared shell
process. Do not use `rescanPlugins` as a development loop.

The coordinating agent alone owns deployment and shell restarts. Workers must
not infer permission to deploy from these project instructions.

Before deployment, read [the deployment procedure](docs/deployment.md), including
preflight, backup identification, failure recovery, and installed-file checks.
The installer must remain fail-closed while Quickshell runs, create timestamped
backups, install only declared artifacts, preserve user configuration without
explicit integration consent, and never restart or rescan the shell itself.

## Completion criteria

After a successful merge, complete the branch cleanup procedure in
[docs/maintenance.md](docs/maintenance.md#branch-cleanup) without another prompt.
Cleanup is part of the task, including merges performed by direct push.

Complete the applicable checks in [docs/verification.md](docs/verification.md),
clean up temporary artifacts, and preserve unrelated edits and user notes/state.
One passing full headless suite on unchanged final source satisfies runtime,
deployment, and completion requirements. Repeat only for relevant changes,
failures, or new concerns. Required deployments must match the tested source;
follow [docs/deployment.md](docs/deployment.md). Report unavailable compositor
evidence as unverified; do not substitute headless evidence for it.
