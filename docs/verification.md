# JotPin verification

Read before selecting checks for executable plugin, installer, or test-harness
changes, and before any desktop-interactive test. Commands run from the
repository root. Deployment authorization remains in [AGENTS.md](../AGENTS.md).

## Safe default test workflow

For executable plugin, installer, or test-harness changes, run the narrow
regression while iterating and the full suite once on the final integrated
source before deployment:

```bash
bash tests/run.sh headless
```

This is the required default for runtime validation. It must remain disconnected
from the user's Wayland display and must not summon JotPin, inject input, capture the desktop,
change the active note, deploy files, or restart the shell.

Use the narrowest offscreen check while iterating:

```bash
bash tests/run.sh model
bash tests/run.sh render
bash tests/isolated_persistence_regression.sh
```

Choose the relevant command above; do not run them all by default. One passing
full suite on unchanged final source satisfies validation, deployment, and
completion requirements. Repeat checks only after relevant changes, failures,
or new concerns. Workers run their assigned checks; the coordinator owns the
final integrated run.

For documentation-only changes, verify paths, commands, links, and consistency.
Do not run runtime suites or deploy solely because guidance changed. Read-only
audits do not require runtime validation.

The persistence regression must verify actual temporary-file contents and
completion state. Static source-pattern checks or a QML-load smoke test are not
sufficient for save/recovery changes. Its coverage must include:

- idle-debounced save;
- immediate manual save;
- an edit arriving during an in-flight save;
- selection-only activity remaining clean;
- periodic recovery while continuously dirty;
- successful-save recovery cleanup;
- startup recovery detection;
- Recover persisting the snapshot;
- Discard preserving the saved note and removing the snapshot.

When a bug escapes these tests, add an offscreen reproduction before or with
the fix. Do not substitute a live desktop reproduction when the behavior can
be exercised in the isolated Quickshell harness.

## Desktop-interactive test policy

Desktop-interactive tests are only justified for behavior that depends on the
real compositor and cannot be represented by the offscreen harness, such as:

- native xdg-toplevel focus and keyboard routing;
- map-time placement and compositor fullscreen/maximize/restore lifecycle;
- the Side outer-edge resize affordance or compositor-specific screenshots.

They are never required for persistence, Markdown parsing, source editing,
syntax highlighting logic, recovery, or ordinary layout calculations.

The coordinating agent owns live tests; workers must not invoke them.
Use the offscreen harness whenever it can prove the behavior. If a required
behavior genuinely cannot be validated offscreen, the user has pre-authorized
the smallest necessary `tests/live_*.sh` run and the corresponding
`JOTPIN_ALLOW_LIVE_TESTS=1`, `wtype`, `grim`, or
`omarchy-shell shell summon/toggle` operations. Do not stop to ask for another
confirmation. Send a concise commentary warning immediately before the test so
the interruption is not surprising, then proceed.

When a live run is necessary:

- use only disposable fixture notes;
- run the smallest relevant live script once;
- do not use the live suite as an edit-and-retry loop;
- close the disposable note and restore prior visible state afterward;
- report exactly what required compositor evidence and what was observed.

Do not run a live test merely because one exists or as a generic final smoke
test. Its use must be tied to a concrete compositor-only assertion that the
offscreen suite cannot cover.

Read-only checks such as source inspection, `omarchy-shell shell ping`, and
filtered `journalctl --user -t omarchy-shell` diagnostics do not open JotPin
and are safe when relevant.

## Dependencies and validation assumptions

- Quickshell and the packaged `qs.Commons` / `qs.Ui` modules come from Omarchy.
- `md2html` from Arch's `md4c` package is used for CommonMark/GFM fixture
  validation.
- Generated Highlight.js and `nspell` workers plus their dictionaries and
  licenses are committed to the plugin; normal builds and tests must not fetch
  packages or depend on a system dictionary or syntax-highlighting service.
- npm is needed only when deliberately regenerating the pinned vendor bundles.
- Node.js runs the pure `EditorModel.js` tests.
- `jq`, `rg`, and standard coreutils support the isolated shell tests.

If a required dependency is missing, report it or install it only with the
user's authorization. Do not weaken or silently skip the corresponding test.
