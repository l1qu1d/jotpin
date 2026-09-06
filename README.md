# JotPin

**A place for your thoughts, right where you work.**

Capture ideas, keep checklists, and save code snippets in a Markdown scratchpad
that stays close at hand. Edit formatted notes directly, switch to source when
you need it, and let autosave take care of the rest. Your notes stay in ordinary
`.md` files, ready to use with your other tools.

Built for Omarchy today, with other desktop environments in mind.

## See it in action

Take a two-minute tour of editing, checklists, code, tables, image resizing,
search, tabs, settings, and recovery. Captioned, with no audio.

https://github.com/user-attachments/assets/d3ba3142-e2c8-46e7-9582-c86a615016ac

<details>
<summary>View a screenshot</summary>

![JotPin preview](preview.png)

</details>

## Get started

JotPin currently requires Omarchy with Quickshell shell-plugin support.
Install and enable it, then open the scratchpad:

```bash
omarchy plugin add https://github.com/l1qu1d/jotpin.git --enable
omarchy-shell shell summon dev.jotpin
```

JotPin opens as a Side drawer on the right. Press `Ctrl+N` to create a note,
`Ctrl+O` to open one, or `Ctrl+P` to switch between Preview and Raw Markdown.
Use `F1` for shortcut help and `Ctrl+,` for settings. In settings, choose your
notes folder, drawer edge, text size, and keyboard shortcuts.

The standard installation adds the plugin but does not configure a global
shortcut, Apps entry, or floating-window rules. For those integrations, follow
[desktop integration and deployment](docs/deployment.md). `SUPER + N` is the
suggested global shortcut; it is added only when available. After installing
the desktop integration, press `SUPER + A`, search for `JotPin`, and open it
from the Apps list.

## In this guide

- [See it in action](#see-it-in-action)
- [Features](#features)
- [Using JotPin](#using-jotpin)
- [Default keyboard shortcuts](#default-keyboard-shortcuts)
- [Data and settings](#data-and-settings)
- [Requirements](#requirements)
- [Update and remove](#update-and-remove)
- [Supported code languages](#supported-fenced-code-languages)
- [Platform support](#platform-support)
- [Development](#development)
- [Repository layout](#repository-layout)
- [License](#license)

## Features

### Markdown editing

- Edit rendered Markdown directly in `Preview`, or switch to `Raw` whenever
  you want the complete source. Both views save the original Markdown rather
  than generated HTML.
- Render CommonMark and GFM headings, emphasis, links, quotes, lists, task
  lists, tables, images, thematic breaks, inline code, and fenced code while
  preserving source-mapped caret and selection behavior.
- Open a link with `Ctrl+click` in Preview. A plain click places the caret
  so you can edit the link text.
- Toggle a task by clicking its checkbox in Preview or pressing `Ctrl+Enter`
  on its source row.
- Use the contextual table controls to insert or remove rows and columns,
  repair malformed tables without dropping cell text, or delete a table as one
  undoable edit.
- Resize Preview images from any corner without changing their aspect ratio.
  Images stay on their own display row with their alt text beneath them, even
  when the Markdown places them beside prose. Relative image paths resolve from the active note, and failed
  images remain visible as editable text instead of disappearing.
- Highlight fenced code locally with 31 bundled grammars, including Dart; the
  complete canonical names and accepted aliases are listed under
  [Supported fenced-code languages](#supported-fenced-code-languages).
  Unknown languages remain readable as plain code.
- Auto-pair triple-backtick fenced-code closers, common brackets and quotes,
  and HTML/XML-style tags in matching code blocks. The editable language header
  and trailing escape line stay reachable from the keyboard.
- Check English (US) spelling locally in Preview and Raw, apply right-click
  corrections, ignore a word for the session, or add it to a persistent
  personal dictionary. Code, URLs, paths, tags, and other technical tokens are
  skipped.
- Find literal text with an optional `Match case` toggle, replace one or every
  match, move between matches with `F3` / `Shift+F3`, and jump to a source line
  with `Ctrl+G`.
- Keep familiar editor behavior: mouse selection, word wrapping, clipboard
  commands, `Tab` / `Shift+Tab` indentation, a keyboard-accessible context
  menu, and per-note undo/redo with `Ctrl+Z`, `Ctrl+Y`, or `Ctrl+Shift+Z`.

### Notes and recovery

- Create, open, reopen from `Recent Files`, save, and `Save As` ordinary `.md`
  files from the grouped `File` menu. Non-Markdown extensions are rejected.
- Work across a horizontally scrollable tab strip with one to five configured
  rows. Tab labels hide `.md`, and a double-click or `F2` renames the filename
  stem without replacing an existing file.
- Restore the active note, open tabs, newly created notes, presentation, and
  settings after the panel or shell restarts.
- Autosave after 1.5 seconds of inactivity, save immediately with `Ctrl+S`,
  and keep atomic recovery snapshots during continuous editing. A surviving
  snapshot is offered with explicit `Recover` and `Discard` choices.
- Detect changes made to an open note by another program. Clean notes reload
  automatically; a note with local edits offers `Keep Mine` or
  `Reload disk version` instead of silently overwriting either copy. If the
  file was deleted, JotPin offers `Recreate with mine` instead of reload.
- Remove an untouched generated `untitled-XXXXXX.md` file when its tab closes.
  Closing the last tab first opens a fresh blank note so JotPin is always ready.

### Presentations and desktop integration

- Switch between a centered native window and a left- or right-anchored Side
  drawer without creating a second editor or losing caret, selection, undo, or
  scroll state.
- Resize the centered window normally or drag the Side drawer's exposed outer
  edge horizontally. JotPin's `Full Screen` action provides a maximized,
  full-width work-area view while keeping the Omarchy bar visible.
- Let Hyprland manage both native windows, so compositor fullscreen, maximize,
  move, resize, and restore controls continue to work.
- Adjust note text from 75% to 200% in Settings, with a Reset to the default.
  The size applies to Preview and Raw and is remembered across restarts.
  Click outside Settings to dismiss it.
- Configure the default notes folder, Side edge, file-tab row count, and JotPin
  command shortcuts. Header controls toggle Preview, spellcheck, presentation,
  Full Screen, and settings; the footer's `Show more` control or `F1` opens the
  complete shortcut card.
- Optionally add JotPin to the Apps list and Omarchy menu, with its own icon
  and a workspace-aware `SUPER + N` toggle.
  The guarded installer preserves unrelated menu entries and refuses to take
  an occupied binding.
- Summon an absolute or `~/` Markdown path and choose `side` or `window` from the
  command line; an open JotPin can be moved to the visible normal or special
  workspace without duplicating its editor.

## Using JotPin

Open JotPin directly with:

```bash
omarchy-shell shell summon dev.jotpin
```

For a different note file, pass a JSON payload when summoning:

```bash
omarchy-shell shell summon dev.jotpin '{"path":"~/Documents/Notes/project.md"}'
```

Choose **Side** for an edge drawer or **Center** for a resizable window.
You can switch in the header or with `Ctrl+Shift+M`. To choose from the
command line, use `side` or `window`:

```bash
omarchy-shell shell summon dev.jotpin '{"mode":"window"}'
omarchy-shell shell summon dev.jotpin '{"mode":"side"}'
```

The legacy `"center"` value remains accepted as an alias for `"window"`.
By default, `Ctrl+F` triggers JotPin's Full Screen action, which selects a
maximized, full-width work-area view while keeping the bar visible; this
shortcut can be changed in Settings. Compositor fullscreen, move, and resize
shortcuts remain external and continue to apply like they do to every other
managed window.

An explicit `mode` or `path` in a summon payload takes precedence for that open
and updates the stored session. Changing the default folder affects new notes
and the Open list; existing notes are not moved. The settings panel rejects
empty, invalid, duplicate, and reserved Esc/undo/clipboard shortcuts.

The menu and desktop entry issue the same plain summon command shown above. If
JotPin is already open on the focused workspace, a plain summon hides it;
otherwise it opens JotPin or moves the existing surface to the focused
workspace. A summon with an explicit nonempty `mode` or `path` always opens it.

The optional `SUPER + N` shortcut brings JotPin to your current workspace,
including special workspaces, while keeping your editing session intact.

## Default keyboard shortcuts

The settings panel can change every command shortcut in this table and reset
it to the listed default.

| Default | Action |
| --- | --- |
| `Ctrl+S` | Save now |
| `Ctrl+Shift+S` | Save As |
| `Ctrl+O` | Open a Markdown note |
| `Ctrl+Shift+O` | Open the most recent usable note |
| `Ctrl+Alt+O` | Clear Recent Files |
| `Ctrl+N` | Create a note in the default folder |
| `Ctrl+P` | Toggle Preview / Raw |
| `Alt+F` | Open or close the File menu |
| `Ctrl+Shift+M` | Toggle Side / Center |
| `Ctrl+F` | Toggle JotPin Full Screen |
| `Ctrl+,` | Open or close Settings |
| `F1` | Open or close shortcut help |
| `Ctrl+Right` | Next open note |
| `Ctrl+Left` | Previous open note |
| `Ctrl+Shift+W` | Close the active note while keeping JotPin open |
| `F2` | Rename the active note |
| `Ctrl+Enter` | Toggle the task on the caret's source row |
| `Ctrl+Shift+F` | Find literal text |
| `Ctrl+H` | Find and replace literal text |
| `Ctrl+G` | Go to a source line |
| `F3` | Next match |
| `Shift+F3` | Previous match |
| `Shift+F10` | Open the editor context menu |
| `Ctrl+W` | Close JotPin while preserving its session |

These editor and accessibility bindings are reserved: `Esc` closes JotPin;
`Ctrl+Z`, `Ctrl+Y`, and `Ctrl+Shift+Z` provide undo/redo; and `Ctrl+A`, `Ctrl+C`,
`Ctrl+X`, and `Ctrl+V` provide selection and clipboard commands. `Tab`,
`Shift+Tab`, and `Enter` are built-in editor/control bindings but are not
reserved by the shortcut validator, so avoid assigning them to commands. The
optional system-level `SUPER + N` binding is separate from these in-app
shortcuts.

## Data and settings

JotPin keeps notes in ordinary Markdown files and stores its own state under
the user's local state directory. It does not upload notes, account data, or
telemetry.

| Data | Default location | Contents and lifecycle |
| --- | --- | --- |
| Notes | `~/Documents/Notes/*.md` | User-owned Markdown files. The default folder is configurable; existing notes are never moved automatically. |
| Session and preferences | `~/.local/state/jotpin/settings.json` | Presentation, Side edge, text size, tab-row count, default folder, recent files (up to 10), open tabs, active note, spellcheck state, and configurable shortcuts. |
| Per-note editor state | `~/.local/state/jotpin/editor-states.json` | Caret, selection, Preview and Raw scroll positions, and bounded undo/redo history for open notes. |
| Personal dictionary | `~/.local/state/jotpin/personal-dictionary.json` | Words explicitly added through the spelling menu. |
| Recovery snapshots | `~/.local/state/jotpin/recovery/` | Per-note atomic snapshots while edits remain unsaved; successful normal saves and explicit recovery decisions clean them up. |
| Deployment backups | `~/.local/state/jotpin/deploy-backups/` | Backups made by `install_safe.sh`; the normal Omarchy plugin installer does not create them. |

Removing the plugin leaves notes and state in place. Delete those paths only
when you intentionally want to remove the corresponding user data.

## Requirements

JotPin runs inside Omarchy's Quickshell process and uses the packaged
`qs.Commons` and `qs.Ui` QML modules. Local file operations use GNU coreutils
and findutils, which are included with Omarchy.

No account or cloud service is needed. Markdown parsing, syntax highlighting,
and English (US) spellcheck run locally with bundled workers and dictionaries.
Normal use does not require Node.js, npm, or a separate spellcheck service.
See [test dependencies](tests/README.md) for development requirements and
[third-party notices](THIRD_PARTY_NOTICES.md) for bundled components.

## Update and remove

For a standard Git-based installation, update with:

```bash
omarchy plugin update dev.jotpin
```

If you use the guarded installer, update your source checkout and repeat the
[deployment procedure](docs/deployment.md) instead.

To uninstall:

```bash
omarchy plugin remove dev.jotpin
```

Removal preserves your notes and JotPin state. If you installed the optional
desktop integration, remove its `require("hypr.jotpin")` and
`require("hypr.jotpin_binding")` lines from your Hyprland configuration and
remove the JotPin row from `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
Then remove the corresponding integration files:

- `~/.config/hypr/jotpin.lua`
- `~/.config/hypr/jotpin_binding.lua`
- `~/.local/share/applications/dev.jotpin.desktop`
- `~/.local/share/icons/hicolor/256x256/apps/dev.jotpin.png`

Reload Hyprland after removing its integration. Preserve unrelated menu entries
and configuration. The normal plugin removal command does not remove these
optional files.

## Supported fenced-code languages

Put a canonical name or alias immediately after the opening fence:

~~~~markdown
```dart
void main() => print('Hello');
```
~~~~

Names are case-insensitive; only the first whitespace-delimited token is used.
`none`, `plain`, `text`, and `txt` deliberately select uncolored plain code.

| Language | Canonical fence name | Accepted aliases |
| --- | --- | --- |
| Bash | `bash` | `fish`, `shell`, `sh`, `zsh` |
| C | `c` | None |
| C++ | `cpp` | `c++`, `h`, `h++` |
| C# | `csharp` | `c#`, `cs` |
| Clojure | `clojure` | None |
| CSS | `css` | None |
| Dart | `dart` | None |
| GDScript | `gdscript` | `gd` |
| Go | `go` | `golang` |
| GraphQL | `graphql` | None |
| Java | `java` | None |
| JavaScript | `javascript` | `js`, `jsx` |
| JSON | `json` | `jsonc` |
| Kotlin | `kotlin` | `kt` |
| Lua | `lua` | None |
| Markdown | `markdown` | `md` |
| Objective-C | `objectivec` | `objective-c`, `objc` |
| Perl | `perl` | None |
| PHP | `php` | None |
| PowerShell | `powershell` | `ps` |
| Python | `python` | `py` |
| QML | `qml` | None |
| R | `r` | None |
| Ruby | `ruby` | `rb` |
| Rust | `rust` | `rs` |
| SCSS | `scss` | None |
| SQL | `sql` | None |
| Swift | `swift` | None |
| TypeScript | `typescript` | `ts`, `tsx` |
| XML | `xml` | `html`, `svg` |
| YAML | `yaml` | `yml` |

This is the complete curated set registered by `SyntaxHighlight.js` and the
bundled Highlight.js worker. A leading dot is also ignored, so `.dart` resolves
to `dart`.

## Platform support

Omarchy is the only supported host today. The goal is to bring JotPin to other
desktop environments while keeping the same editor and portable Markdown files.
Support for additional hosts will be documented as tested integrations become
available. See [Porting JotPin](PORTING.md) for the current architecture and
requirements for a port.

## Development

Start with [Contributing](CONTRIBUTING.md) for setup and review expectations.
Run the default isolated checks from the repository root:

```bash
bash tests/run.sh headless
```

Documentation-only changes need path, command, link, and consistency checks.
They do not require runtime tests or a shell restart.

- [Tests](tests/README.md): dependencies, focused commands, and coverage.
- [Verification](docs/verification.md): required checks and live-test boundaries.
- [Deployment](docs/deployment.md): desktop integration, backups, installation,
  and failure recovery. Read this before stopping the shell or deploying.
- [Editor contracts](docs/editor-contracts.md): source, rendering, and saving rules.
- [Maintenance](docs/maintenance.md): CI, dependencies, and release procedures.
- [Security](SECURITY.md): private vulnerability reporting.
- [Changelog](CHANGELOG.md): changes awaiting release.

## Repository layout

- [`manifest.json`](manifest.json) and [`JotPin.qml`](JotPin.qml) define the
  plugin metadata, lifecycle, editor UI, files, tabs, persistence, and commands.
- [`NativeMarkdownDisplay.qml`](NativeMarkdownDisplay.qml) is the production
  Markdown renderer and owns source mapping, caret and selection geometry,
  tables, images, and fenced-code layout. [`MarkdownDisplay.qml`](MarkdownDisplay.qml)
  is retained only as the retired renderer oracle.
- [`EditorModel.js`](EditorModel.js), [`SpellcheckModel.js`](SpellcheckModel.js),
  [`SyntaxHighlight.js`](SyntaxHighlight.js), and [`HtmlEntities.js`](HtmlEntities.js)
  contain pure editing, spelling, language-normalization, and entity helpers.
- [`markdown/`](markdown/), [`syntax/`](syntax/), and [`spellcheck/`](spellcheck/)
  contain the committed offline parser, highlighting, and spelling workers.
- [`HostIntegration.qml`](HostIntegration.qml), [`hypr/`](hypr/),
  [`desktop/`](desktop/), [`omarchy-menu.jsonc`](omarchy-menu.jsonc), and
  [`install_safe.sh`](install_safe.sh) provide shell, compositor, desktop-entry,
  menu, and guarded deployment integration.
- [`tests/`](tests/), [`scripts/`](scripts/), and [`vendor/`](vendor/) contain the
  regression suites, bundle-generation tools, pinned dependency metadata, and
  bundled licenses.

## License

Copyright (c) 2026 JotPin contributors.

JotPin is released under the [GNU General Public License, version 3 only](LICENSE)
(`GPL-3.0-only`). You may redistribute and modify it under those terms.
It is provided without any warranty; see the license for details.

Bundled third-party components retain their own licenses and copyright notices;
see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
