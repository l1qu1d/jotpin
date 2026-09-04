# JotPin test suite

The suite keeps the Markdown examples in version control so future editor and
renderer changes are checked against the same input instead of one-off scratch
files.

## Test dependencies

The complete headless suite uses Bash, Node.js, ripgrep, Perl, the Lua compiler
(`luac`), GNU coreutils/findutils, Omarchy's `omarchy` validator, Quickshell's
offscreen Qt backend, and `md2html` from `md4c`. Syntax highlighting and
spellcheck use the generated assets committed to the repository; the suite
does not fetch npm packages or depend on system spelling or highlighting
services.
The opt-in live tests additionally use `jq`, `grim`, `wtype`, `hyprctl`, and an
active Omarchy Wayland session. None of these live-only tools are required to
run JotPin normally.

From the plugin directory, run the headless checks with:

```bash
bash tests/run.sh
```

`tests/run.sh` is the headless-first safe default. It runs the pure editor
model, headless plugin/Markdown checks, guarded plugin/window-rule installation
in a private
HOME, a complete save/recovery lifecycle, and the real-QML renderer in
disposable offscreen Quickshell processes. It does not summon the live JotPin,
inject desktop input, capture the desktop, or change the active file session.
Pure editor-model performance checks run here too, independently of the
retired renderer benchmark.

The isolated installer regression also uses a private menu extension and
Hyprland binding configuration. It first proves that deployment without the
separate configuration-consent flag leaves those files byte-for-byte
unchanged. With consent enabled, it verifies that `Apps > JotPin` and
`Personal > JotPin` are merged without replacing existing rows, including the
upgrade from a Personal-only installation, that repeated deployment does not
duplicate either row or binding require, that a free `SUPER + N` receives the
default workspace-aware binding, and that an already-occupied or unverifiable
binding is left unchanged.

## Development test order

### Acceptance rules after the link regression audit

The final `complete production headless suite` line is emitted only after every
stage succeeds. `test_plugin.sh` checks structure, source invariants, model
transitions and Markdown fixtures; its success alone is not interaction or
visual acceptance. The headless runner also provides a disposable HOME and all
XDG directories, with DISPLAY and WAYLAND_DISPLAY removed, for child tests.

For user-visible regressions, include a failing reproduction and its negative
boundaries (for example: link label opens, surrounding blank space does not).
Expected click positions must come from an independent reference or known
fixture geometry, not exclusively from the source-map function being tested.
Wait for the specific lifecycle under test: parser completion is not equivalent
to the completion of a deferred styled-document repaint. When testing settled
appearance, wait for that repaint too; rapid-edit tests intentionally exercise
the intermediate state separately.

The pointer suite runs Qt's offscreen software renderer, so pixel assertions
can prove that a visible property actually produces a visible marker. Its
hand-authored HTML reference is independent of the Markdown parser and source
map. It covers inline, bold, repeated, reference, collapsed-reference,
shortcut-reference and autolink labels, wrapping, proportional fonts, zero and
asymmetric padding, plus blank-space and modifier/drag cancellation boundaries.
An unresolved reference must remain ordinary text.

`qt_contracts.json` is the explicit inventory of required QtTest cases and data
rows. `check_qt_contracts.cjs` requires every case exactly once, a matching
summary, and no skips, expected failures, or unregistered results. Its own
negative tests reject incomplete and misleading logs.

`native_parity_contracts.json` independently lists all 88 required renderer
fixtures. The parity and performance gates validate every result record, not
just a clean summary or one matching success line. Missing, duplicate, or
failed workloads are rejected; synthetic negative tests enforce that behavior.

`jotpin_link_keys_regression.sh` hosts the actual product with a disposable note
and delivers Qt key and mouse events to its focused editor. It verifies Ctrl
press/release, focus-loss cleanup, blank-space hover, and delivery of exactly
one target through the injected URL opener. The callback boundary is tested;
the suite does not launch the user's browser.

`link_mutation_regression.cjs` deliberately breaks eight disposable source copies:
links disabled, coordinate drift, links active in blank space, plain-click
activation, an unpainted marker, drag-out-and-back activation, dropped Ctrl
key handling, and dropped product URL dispatch. Each copy
must fail the relevant behavioral assertion. These checks run in the default
headless suite and never change the checkout or installed plugin.

These tests establish specific contracts; they do not prove every possible
interaction or compositor behavior. Keep physical desktop observations distinct
from offscreen input and rendering evidence, and add new independent fixtures
when an uncovered interaction is reported.

Use the smallest isolated test that covers the behavior while making a change:

```bash
bash tests/run.sh model
bash tests/run.sh performance
bash tests/run.sh render
bash tests/run.sh
```

The model test remains the fast edit-and-retry loop for source transitions and
caret movement. The renderer command now exercises the production path: the
vendored micromark/mdast GFM stack produces sanitized structural HTML and
canonical source offsets, Highlight.js renders fenced code off the UI thread,
and Qt's native `RichText` document performs layout. It verifies headings,
emphasis, links and autolinks, hard breaks, nested/ordered/task lists,
strikethrough, quotes, thematic breaks, fenced code, tables, images, four-corner
image resizing, caret and selection geometry, and source preservation.

All 76 fixtures from the former hand-written `MarkdownDisplay.qml` matrix plus
the empty language-slot, empty code-row, pre-fence blank-line selection,
final-line bottom-padding, empty continued-list caret, wrapped unordered,
ordered, task, and nested-list items, wrapped-item boundaries before an
existing bullet, the same edit with stranded blank rows, and raw-marker flash
prevention are in the 88-case production-native parity gate. The retired
matrix and benchmark
remain available as `legacy-render` and `legacy-performance` for historical
comparison, but the default suite now enforces their relevant user-visible
contracts against `NativeMarkdownDisplay.qml` instead of executing the retired
renderer.

## Production Markdown renderer checks

Seven isolated, offscreen checks gate the production Live editor:

```bash
bash tests/markdown_parser_regression.sh
bash tests/native_markdown_display_regression.sh
bash tests/native_markdown_caret_matrix.sh
bash tests/native_markdown_mouse_regression.sh
bash tests/jotpin_list_return_regression.sh
bash tests/native_markdown_parity.sh
bash tests/native_markdown_performance.sh
```

The first runs the committed micromark/mdast GFM parser bundle in a real QML
`WorkerScript`. It requires every compact AST node to retain a valid source
range and checks its generated HTML structures. The second loads the production
component, parser worker, and Highlight.js worker together, then validates the
actual Qt document text plus source-aligned caret, hit-test, navigation, and
selection geometry. Its image fixture loads one real SVG and one missing SVG,
requiring the valid image to retain its resize geometry while the failed image
becomes an explicit textual fallback with editable alt-text source mapping.
It also types six consecutive characters into a highlighted fenced-code body,
waiting for each parser/highlighter revision, and requires zero intermediate
fallback paints so syntax colors cannot flash off and back on per character.
The caret matrix performs 312 rapid insertion/deletion assertions without
waiting between edits. It covers paragraphs, headings, bullets, multiline
bullets, ordered lists, tasks, quotes, emphasis, inline code, link labels,
fence languages, fence bodies, and table cells, requiring every intermediate
source revision to remain rendered with its caret on the same visual row.
Its table fixture also requires every hidden padding and
internal-delimiter offset between adjacent cells to advance visibly and map
back to that exact source position. The parity gate then runs every one of the
76 former
renderer fixtures through that production component, covering blank and
whitespace-only rows, inline and reference forms, headings, quotes, fences,
lists and tasks, tables, images, wrapping, pointer/source round trips,
selections, and edit stability. Exact assertions about the retired renderer's
private caches, delegate identities, block ids, and revision-counter increments
are intentionally replaced by their visible behavior contracts.
List coverage includes rendered geometry: continuation rows must align with
their own item text rather than the bullet column, and an empty item created by
Enter must retain a caret row below the completed item and above an existing
following bullet. The focused JotPin regression also reproduces Qt inserting a
plain newline at the end of a wrapped list item and requires the editor to
recover it as the intended list continuation.

One former quirk is deliberately not preserved: a reference-image definition
immediately adjacent to the image with no separating blank line remains literal
text, matching CommonMark/GFM. The fixture still runs and asserts that compliant
result rather than teaching the new parser the retired nonstandard behavior.

The pointer regression places the welcome-note table/fenced-code/table shape
inside a real clipped viewport, including a malformed GFM row whose surplus
cell is omitted from the rendered table. Its fenced-code section mirrors the
reported scratchpad ordering: a resized image is followed by a `tes` language
label whose first code row is `test`. It clicks the label and code separately,
drag-selects the language, confirms shortening it leaves the styled document
untouched until an immediate authoritative render settles, repeats the drag,
then selects across post-fence blocks.
This prevents a label prefix from being mistaken for the same text at the
start of the code body. The test also clicks the standalone image, requires
its four-corner resize frame, and drags a real corner through Qt's pointer
stack. The drag must leave source unchanged until release and emit exactly one
resize request. The test also requires strictly advancing rendered geometry
after the fence so a dropped table cell cannot corrupt every later source
coordinate. The viewport must remain stationary during that drag:
physical mouse-button movement is reserved for selection. The Flickable stays
interactive for normal touch gestures, and scrolling remains available through
the scrollbar and wheel/touchpad handler.
It also clicks a rendered Markdown link without modifiers, then with a real
Ctrl modifier, requiring exactly one activation carrying the resolved target;
dragging away from the link while holding Ctrl must remain inert. The hovered
link must expose the pointing-hand cursor before, during, and after Ctrl+click.
While Ctrl is held, JotPin also draws its own target marker at the link so the
gesture remains visible even when a compositor hides its native pointer after
keyboard input.
The link regression also checks blank space on both sides, above, below, and
far from a standalone link. Those points must show no marker and emit no
activation, while every character of the label remains clickable.

The persistence harness also restores the contextual Preview table helper from
the retired renderer architecture. Its fixture puts a fenced code block,
blockquote, and heading before the table and requires the compact 22-pixel row
to clear that content, align with the table's left edge, sit four pixels above
the table, and scroll with it. It then adds a column across the header,
separator, and every body row and verifies the structural edit is one undoable
and redoable action. Moving the caret to the blank row immediately above the
table must hide the helper; moving it back into a cell must restore it. Raw
view must also hide the helper. A caret in leading or trailing cell padding,
including a hidden internal column separator, remains inside the table and
must keep the helper visible. Pure model
coverage separately exercises row and column insertion/deletion, whole-table
deletion, CRLF and alignment retention, malformed-row repair, overflow
preservation, and the header/one-column safety limits. The repair control stays
visible for discoverability, enables only for a recognized malformed table,
folds overflow text without discarding it, disables after repair, and performs
as one undoable and redoable edit.

`tests/live_note_undo_switch_regression.sh` covers the keyboard-routing boundary
that the offscreen persistence harness cannot prove. It types into one
disposable note through the real focused JotPin window, switches to a second
note and back, then injects an actual Ctrl+Z key chord. The visible source must
return to the original bytes, redo must become available, and the undone source
must be saved before the disposable notes are closed.

Regenerate the committed parser worker deliberately with:

```bash
cd scripts/vendor
npm ci --ignore-scripts
cd ../..
node scripts/build_markdown_bundle.mjs
```

Normal tests use the committed worker and do not require npm or network access.

The native display regression locks the established heading scale, readable
link and inline-code colors, continuous nested quote rails with source-aware
blank-row spacing, compact aligned
tables, task markers,
code card/language label, list indentation, explicit blank rows, and selection
layering. It also validates caret and pointer geometry across those structures,
including immediate projected updates for repeated Enter and newline Backspace
in both ordinary text and fenced-code rows,
including leading and trailing editable rows and a held-key repeat burst.

The performance regression runs deterministic 1 KiB, 10 KiB, 25 KiB, and
100 KiB notes through the production parser, syntax worker, Qt rich-text
layout, and source-geometry APIs. It also selects each complete note and
requires Live Preview to retain the full source selection while limiting
rectangle generation to the visible viewport. Its generous per-size ceilings
are intended to catch severe regressions rather than turn normal
machine-to-machine timing variation into failures; each run emits JSON timing
records for comparison. The isolated vendor smoke check separately times a
25 KiB Markdown-aware spelling pass in the real worker and records UI-loop
heartbeats while that work is in flight.

The offscreen persistence regression uses a private HOME, runtime directory,
note, and recovery directory. It verifies the idle debounce, immediate manual
save, edits arriving during an in-flight save, selection-only activity,
periodic recovery while continuously dirty, successful-save cleanup, startup
detection, Recover, and Discard against actual temporary file contents. The
production defaults remain 1.5 seconds for normal autosave and at most one
recovery snapshot every 10 seconds while dirty.

Startup loading is also race-tested: the note reader must remain inactive until
the restored session has selected its final active path. A simulated dropped
read must exhaust its bounded retries, release the loading overlay, and allow a
different tab to load normally instead of locking the whole file session.

The per-tab state stages also place a selection and caret inside a long note,
toggle Preview to Raw and back, and require the destination viewport to put the
same source caret at the same on-screen Y position in both directions. The
alignment waits for authoritative rendered geometry and is repeated after a
fresh component restore; a saved per-view scroll offset must not pull the user
away from the active caret during a view toggle. It also rapidly requests an
A-to-B switch while A is still loading and requires the final rendered document,
selection, scroll position, and bounded undo history to remain isolated per
note. After returning to the first note, the focus-gated command used by the
real Ctrl+Z shortcut must undo that note's edit before redo restores it.
Creating an empty note must clear both the editable source and the prior
native Preview document before showing the empty-note placeholder.

It also creates an unnamed `untitled-*.md` note, closes the production component,
and loads a fresh component to verify that the active file and open tab are
restored from the persisted session state. A separate blank generated note is
opened, closed from an inactive tab, and checked on disk to verify that its
temporary file is removed without affecting a populated note.

The same production component opens the in-plugin Open surface and verifies that
the configured default notes folder is listed with Markdown files only. The
settings surface is exercised against a disposable custom folder, both Side
drawer edges, a custom command shortcut, and a four-row maximum file-tab
layout; their persisted values are checked after the component exits and on a
fresh component restore. Values above the five-row limit are rejected.

All file ingress is Markdown-only: Open, Save As, summon paths, restored tabs,
and inline rename reject non-`.md` extensions. New names and omitted extensions
receive `.md`, while the rename and Save As controls display the suffix as a
fixed label and normal file-tab labels show only the filename stem.

Before the persistence lifecycle, the same offscreen production component is
loaded with an empty note and verifies that `Start writing your note…` shares the
editable caret's exact X/Y origin. This guards theme, font, and display-scale
changes without opening JotPin on the active desktop. The same stage opens and
closes the footer shortcut card and verifies the complete configurable command
shortcut model plus the fixed editing shortcuts are present without collisions.
It also verifies that the former F11 Full Screen default migrates to Ctrl+F and
the former Ctrl+Tab note-navigation defaults migrate to Ctrl+Left/Right without
replacing unrelated or explicitly customized shortcuts. The focused editor
route is checked because Qt otherwise reserves Ctrl+Left/Right for word
movement before a sibling shortcut can switch notes.

For a visual artifact pass without opening JotPin, render the representative
production fixture and inspect its PNG:

```bash
bash tests/native_markdown_visual.sh
# Optional output override:
JOTPIN_NATIVE_CAPTURE_PATH=/tmp/jotpin-check.png \
  bash tests/native_markdown_visual.sh
```

The individual `live_*.sh` scripts remain available for visual or compositor
lifecycle integration work, but every one refuses to run unless
`JOTPIN_ALLOW_LIVE_TESTS=1` is set. They summon the plugin, inject keyboard
input into the focused Wayland surface, and may change the visible JotPin
session. Do not use them while working in the desktop unless that interruption
is intentional. For the final visual pass, use:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/run.sh live
```

Native presentation lifecycle changes have a narrower compositor regression:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/run.sh window
```

The headless suite verifies that both `Center` and `Side` are native Quickshell
`FloatingWindow` xdg toplevels, that their distinct initial titles let static
Hyprland rules match at map time, and that `Center` uses the former theme-scaled
`Style.space(900)` x `Style.space(700)` size while `Side` can mount to either
edge at its former theme-scaled width, has no compositor border or shadow,
occupies the bar-reserved work area, and exposes only an outer-edge horizontal
resize affordance. The opt-in test temporarily loads those checkout rules,
launches both presentations in a disposable Quickshell process and HOME, and
checks compositor-managed fullscreen, maximize, restore, reserved-area
placement, and horizontal resize behavior without binding any JotPin-specific
key. It also invokes JotPin's Full Screen control in the disposable Side window and
checks that the control enters and leaves Hyprland's maximized/full-width mode,
matching the user's compositor action rather than true fullscreen. Cleanup
reloads the user's normal Hyprland configuration to remove the transient rules.
The test does not deploy the plugin or use the user's notes.

Workspace targeting captures a visible `special:*` workspace before the native
JotPin window maps, so opening from a scratchpad does not switch to the normal
workspace underneath it. The live test also keeps a disposable fixture in a
temporary special workspace and verifies that both the fixture and JotPin stay
there while the workspace remains visible.

The focused live test checks body and heading font-relative caret height,
single Backspace across line boundaries, held-Backspace key repeat, and rejects
any visible caret whose source or cursor revision is stale.
The focused navigation test covers Down from a paragraph into the first list
item, repeated rapid Up/Down movement, and movement to the next list item with
no blank source line between the paragraph and list.
The Markdown-gap navigation test reproduces the real scratchpad structure and
checks that Down enters the source-only blank separator, then continues to the
first rendered list item without modifying the note bytes.
The focused Enter test types `test`, presses Enter once, rejects any visible
caret using the previous row's geometry, and verifies the settled caret is on
the new rendered line while the source keeps its trailing newline. It then
types the first character and verifies the second-line caret keeps exactly the
same vertical position instead of collapsing an accidental block gap. A
three-line paragraph also verifies that adding rows never shifts the first
caret and that every row uses one consistent vertical advance.
The offscreen product harness also verifies that one Preview Enter moves from a
fence-language header over its existing source newline into the first code row,
and that deleting either three generated opener backticks or their selection
removes the untouched generated closer and escape line. It also walks repeated
Backspace from an empty first code row through `js` and the opener, requiring
the complete generated fence to disappear without stranding a lone opener.
The focused list-continuation test verifies that Enter creates the next bullet,
Preview Backspace removes an empty bullet row as one semantic edit without
stopping on its hidden separator or marker, and Enter on an empty bullet exits
the list without changing either completed item. Raw mode retains literal
character-by-character Markdown editing.
The focused blank-line spacing test uses `test`, `a`, an active empty line, and
`aa` to verify that text above, the blank caret row, and text below all use the
same vertical line advance without modifying the source.
The focused blank-line caret test uses the exact `test`, blank line, `aa`
structure to verify the blank row remains present before the caret enters it,
the following text does not move when the caret enters it, and mouse-targetable
layout changes never modify the source.
The focused blank-line metrics test covers leading blank rows and blank rows
between a list and a paragraph. It compares the live caret to the actual
rendered neighbor rows, checks body line advance and caret-height consistency,
and preserves both fixture sources.
The focused list-prefix navigation test starts on the first bullet letter and
checks that Left reaches the visible marker boundary, Right returns to the
letter in one step, and the reported three-Left / three-Right sequence never
stalls on the hidden Markdown marker characters. Its exact `- [ ] fsdaf`
fixture also walks Left and Right across every letter, proving that only the
checkbox and bullet syntax is collapsed.
The isolated task-list fixture uses three exact rows ending in `fsdaf` and
checks that clicking between `fs` and `daf` maps after the hidden `- [ ] `
prefix to the exact source column at both normal and high-DPI scale. It also
checks the task-text I-beam and an exact drag-selection range from `fs` to
`fsda`. The native mouse regression separately clicks the dedicated rounded
checkbox control through its enlarged pointer target and verifies that the
event resolves to the exact Markdown task line without moving the text caret.

For a focused QML layout/runtime warning check, use:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/live_qml_health.sh
```

Do not use the live suite as the edit-and-retry loop. Once the isolated
regression passes and the issue is actually solved, run
`bash tests/run.sh headless` once, then run the opt-in compositor pass only if
live evidence is needed. `bash tests/run.sh all` performs the headless checks
and adds the live portion only when the live opt-in environment variable is
present; otherwise it reports that the visual portion was skipped.

For implementation changes, the project contributor policy requires one
guarded deployment and Omarchy-shell restart after the headless validation
passes. Documentation-only changes do not trigger deployment or restart. The
live lifecycle checks remain opt-in because they control the active compositor.

That command validates the plugin manifest, checks the source-preserving editor
bindings, and runs the CommonMark/GFM fixtures through the installed `md2html`
parser. It does not edit `~/Documents/Notes/scratchpad.md`.
It also guards the file-tab layout invariant that each close control remains to
the right of its filename when inline rename is enabled.

For a live visual smoke test in an active Omarchy session, run:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/run.sh live
```

The smoke test opens `source-preservation.md` in the Side drawer, moves the
caret through a heading and nested list, captures Side/caret/Window screenshots,
captures the CommonMark and GFM fixtures in the live renderer, including the
rendered select-all highlight, the multi-file tab strip, and the inline file
rename field. It also checks caret placement on the second list item and
selection highlighting across blank lines, then verifies that `New` creates and
cleans up an empty
`untitled-*.md` file in `~/Documents/Notes`. The test closes JotPin and
verifies that none of the disposable fixtures were modified. It also types a
list marker one key at a time and checks that the editor completes `-` to `- `
without losing the source newline; it captures both the transient bare-marker
state and the settled list state so a caret jump during completion is visible
in the artifact set. A two-item bullet fixture is edited on its second row as
a caret-reflow regression check, ensuring the live caret remains on one visual
line and does not leave a second caret behind on the first item. It also
presses Enter between the paragraph and list and checks that the caret is
visible on the newly created blank source line. The repeated-Enter case also
types the literal `test a`, Enter, `a`, Enter sequence and checks that every
source line remains a separate visible row in Live mode,
captures the state before and after `Ctrl+S`, then types another character to
verify saving did not move the caret or rewrite the source. Immediate and
settled screenshots after the final `a` becomes `az` guard against transient
caret-height regressions during live layout.
Set `JOTPIN_ARTIFACT_DIR` to choose where screenshots are written. The live
test is intentionally separate because it needs the running shell, a
compositor screenshot tool, and `wtype` for keyboard-only caret movement.

For the focused fence-language key-routing regression, run:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/live_fence_language_enter_regression.sh
```

It opens only a disposable note, types an auto-completed fence and `javascript`
through Wayland, presses one physical Enter, and requires the visible caret and
the next typed character to land on the first code row below the language
header. It then repeats the user sequence with `js`, requires typed code to stay
above the generated closer, presses Down to reach the editable escape line,
and verifies text can be entered outside the block. Finally it holds physical
Backspace through an auto-paired brace and requires the language and complete
generated fence to disappear without ever exposing a one- or two-backtick
opener or an orphaned code closer.
It captures before/after screenshots and closes the disposable note.

For the fence-language caret and key-repeat regression, run:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/live_fence_language_repeat_regression.sh
```

This separate focused check holds a physical letter and physical Backspace in
the projected language header. While each key remains down, it samples the
source, rendered-document revision, and visible caret geometry. It requires at
least three distinct intermediate revisions for each held key and rejects any
frame that moves the caret off the language row or exposes stale rendered
text. It uses a disposable note, captures the final states, and closes JotPin.

The offscreen product harness separately clears transient pair tracking for
`function hello() {` followed by `}` on the next row, then requires one
Backspace after `{` to remove both sides of that otherwise-empty pair. This
covers tab switches and plugin reloads without treating populated braces as
generated pairs. It also starts from the exact surviving source—two blank
lines plus a lone triple-backtick row—reported after held Backspace and
requires the otherwise-unreachable bottom fence and its generated blank rows
to disappear together.

For the focused held-key row-paint regression, run:

```bash
JOTPIN_ALLOW_LIVE_TESTS=1 bash tests/live_key_repeat_rows_regression.sh
```

It physically holds Enter and Backspace in both ordinary text and a fenced
code body. While each key remains down, it samples current rendered-caret
revisions and requires at least three distinct source rows to become visible;
checking only the final source after release is intentionally insufficient.

The fixtures cover the Markdown constructs JotPin currently exposes: headings,
paragraphs, emphasis, inline code, links, images, hard breaks, block quotes,
nested unordered lists, ordered lists, thematic breaks, fenced code, GFM task
lists, strikethrough, and tables.
