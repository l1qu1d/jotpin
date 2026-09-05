# JotPin deployment and failure recovery

Read this procedure before deploying or stopping the shell. The coordinating
agent owns these operations; workers return their changes and focused evidence.
Deployment authorization remains in [AGENTS.md](../AGENTS.md); the live-test
policy is in [verification.md](verification.md#desktop-interactive-test-policy).
Run commands from the repository root.

## Desktop integration options

Omarchy's standard `plugin add --enable` installs and enables JotPin. It does not run
this repository's installer or add desktop configuration. The guarded installer
copies a tested checkout into the installed plugin directory. It is also the
route for installing optional desktop integration.

With `JOTPIN_ALLOW_CONFIG_CHANGES=1`, the guarded installer adds:

- JotPin-specific floating-window rules in `~/.config/hypr/jotpin.lua`, loaded
  from `~/.config/hypr/hyprland.lua`.
- A desktop entry and icon for the Apps list, plus a Personal > JotPin menu row.
- A workspace-aware `SUPER + N` shortcut when that binding is provably free.
  Existing or unverifiable bindings are left untouched.

Use the stop/install/restart procedure below. In its installer step, enable
these integrations with:

```bash
JOTPIN_ALLOW_DEPLOY=1 JOTPIN_ALLOW_CONFIG_CHANGES=1 bash install_safe.sh
```

The installer needs Bash, `omarchy-shell`, `pgrep`, and GNU coreutils.
Configuration integration also uses Omarchy, ripgrep, Perl, and `luac`.
Work from a local source checkout, not the installed plugin directory.

When no installed manifest exists, the installer creates
`~/Documents/Notes/welcome.md` if that note is absent. Existing notes are never
replaced. An upgrade with an installed manifest does not recreate the welcome
note. The standard Omarchy installer does not create it.

Guarded installations are copied artifacts, so update them by updating the
source checkout and repeating this procedure. Omarchy's `plugin update` command
requires a Git-based installation.

## Preflight

- Confirm the user requested implementation changes and did not exclude
  installation/restart. Reviews and documentation-only work do not deploy.
- Reuse the successful headless run on the final unchanged source. Do not stop
  the shell before required validation has passed.
- Inspect `install_safe.sh` for its current artifact list and prerequisites.
  Confirm required sources and commands exist before interrupting the shell.
- Record whether the shell is running, the existing installed-plugin state,
  current `hyprctl configerrors`, and entries in the deployment backup directory.
  Diagnose pre-existing config errors before shutdown; report unrelated errors
  instead of expanding into unrequested config repairs. Serialize deployment
  with other tasks.
- Optional Hyprland, menu, desktop-entry, and keybinding integration requires
  explicit task authorization. Existing authorization in the conversation
  counts; do not ask again. Generic plugin edits do not authorize integration.
- Record which optional integration paths exist before changes. The installer
  backs up existing files, but rollback must also account for newly created
  integration files. Preserve unrelated configuration edits.

## Stop, install, verify

1. Confirm the preflight and final headless validation above are complete.
2. Announce the brief shell stop/restart for a user-requested implementation.
3. Stop the shell with
   `timeout 5 quickshell kill -p /usr/share/omarchy/shell --any-display`.
4. Deploy with `JOTPIN_ALLOW_DEPLOY=1 bash install_safe.sh`. Add
   `JOTPIN_ALLOW_CONFIG_CHANGES=1` only when the user has explicitly consented
   to installing or updating the optional Hyprland, menu, and keybinding
   integration.
5. Run `hyprctl reload`, then require empty `hyprctl configerrors` output.
6. Restart with `omarchy restart shell`.
7. Verify `omarchy-shell shell ping` and compare the installed plugin with the
   tested checkout. When optional configuration integration was consented to,
   also compare `~/.config/hypr/jotpin.lua` and confirm the
   `require("hypr.jotpin")` integration remains present exactly once.
8. Leave JotPin closed. Do not summon or toggle it unless the user asks.

`install_safe.sh` must continue to fail closed when any Quickshell process is
running, create a timestamped backup of the existing plugin, install only the
declared artifacts, and avoid restarting or rescanning the shell on its own.
Without `JOTPIN_ALLOW_CONFIG_CHANGES=1`, it must leave user configuration
byte-for-byte unchanged. With explicit consent, it must back up affected user
files and add its integration idempotently without replacing unrelated menu
rows or occupied keybindings.

## Recover on failure

A failed install, config check, comparison, or ping is not a reason to abandon
a shell that this operation stopped. Keep the original failure evidence and
recover service before reporting the task as blocked or unsuccessful.

- Identify the backup from this deployment, not an arbitrary newest backup.
  The installer prints `Deployment backup: ...` on success. If it fails before
  that message, compare the recorded directory inventory and inspect this
  attempt's files. Do not restore an unidentified or incomplete backup.
- If failure occurred before any installed files changed, restart the prior
  shell when this operation stopped it, then verify `omarchy-shell shell ping`.
  A refusal due to an unrelated Quickshell process does not authorize killing
  that process; restore the shell and report the specific blocker.
- If plugin files changed, ensure the shell and Quickshell are stopped before
  restoration. Quarantine the failed installed plugin outside the plugin scan
  directory, then restore the complete prior plugin directory from this
  attempt's verified `plugin` backup. A whole-directory restoration prevents
  new artifacts from being left mixed with the previous build.
- If this was a first install with no prior plugin, quarantine the incomplete
  installation instead of fabricating a prior version. Preserve notes, recovery
  snapshots, and settings, including any first-run welcome note.
- If optional integration changed, restore only this attempt's affected files
  from its backup and remove only integrations created by this attempt. Do not
  overwrite concurrent edits: inspect/merge those differences explicitly.
  Recheck `hyprctl reload` and `hyprctl configerrors` after restoration.
- Restart with `omarchy restart shell` and verify `omarchy-shell shell ping`.
  If the recovered plugin prevents a healthy shell, stop it and quarantine only
  that plugin before attempting to restore the shell's other services. Keep
  backups and diagnostics; do not start a stop/restart retry loop.
- Leave JotPin closed. Report the original failure, recovery actions, exact
  backup/quarantine paths, and whether shell health was restored. If recovery
  cannot be completed, state that limitation explicitly rather than claiming
  successful deployment.

After a successful deployment, compare all declared installed plugin artifacts
with the tested source. When integration was authorized, also compare the rule
and check the require occurs exactly once as specified above. Backups are user
rollback artifacts and must not be deleted as temporary test files.
