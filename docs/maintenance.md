# Maintaining JotPin

The repository is `l1qu1d/jotpin`. Repository visibility, security features,
branch rules, and external app access are managed in GitHub settings separately
from the configuration committed here. Visibility changes are an owner decision.

## Pull requests and CI

Use short branches and pull requests for changes. CI runs on pushes to `main`,
pull requests, and manual dispatch, with read-only repository permissions and
no persisted checkout credentials. It never runs the desktop-interactive suite.

- **Model tests** run portable JavaScript tests on Ubuntu with Node 24.
- **Full headless suite** runs the existing production runner in an isolated
  Arch container as an unprivileged user so file-permission regressions are
  exercised correctly. Omarchy's source revision is pinned in the workflow; its
  install scripts and desktop shell are never started. Arch packages follow
  the current repository, so this also detects dependency compatibility drift.

Once both jobs are green, require these checks in the `main` branch rules and
block force pushes and deletion. A solo maintainer need not require another
human's approval. Verify that the rules are enabled and enforced for the
repository on its current GitHub plan.
Use squash merges and delete merged branches. Do not automatically merge
dependency or AI-generated changes.

### Branch cleanup

Keep GitHub's **Automatically delete head branches** setting enabled. It deletes
remote branches after pull request merges. Enable pruning in each checkout with
`git config --local fetch.prune true` to remove stale remote-tracking references
on fetch.

After a task's merge and required checks succeed, Codex must finish cleanup
without another request: confirm the task's changes reached the target branch,
switch to that branch in a clean checkout, delete the task's merged local branch,
and delete its remote branch if GitHub has not already done so. This includes
fast-forward merges pushed directly to the target branch. Fetch with pruning
and verify that the task branch is gone locally and remotely before reporting
completion.

Only delete branches belonging to the completed task. Preserve default and
protected branches, branches with additional unmerged work, and branches in use
by another worktree or active task. For squash or rebase merges, verify the
merged PR and its exact head before removing a local branch whose original
commits are no longer ancestors of the target. Repository instructions govern
Codex's local cleanup; GitHub's setting does not delete local branches.

## Dependency updates

Dependabot checks GitHub Actions and `scripts/vendor` weekly, grouping routine
updates. Security alerts and automated security fixes are separate repository
settings. The lockfile records build dependencies; users run committed workers.

For vendor updates, review upstream changes, update any explicit version values
in the generation scripts, and rebuild from the pinned dependencies:

```bash
npm ci --prefix scripts/vendor
node scripts/build_vendor_bundles.mjs
node scripts/build_markdown_bundle.mjs
bash tests/run.sh headless
```

Commit the regenerated workers, accurate `vendor/VERSIONS.json`, and any changed
licenses/notices with the dependency update. Review `THIRD_PARTY_NOTICES.md` for
version and attribution changes. Never merge a lockfile-only update as though
it patched the runtime worker. CI tests the shipped workers; it does not yet
prove that all bundles reproduce byte-for-byte from the lockfile.

## CodeRabbit

`.coderabbit.yaml` configures advisory reviews focused on JotPin's contracts and
excludes generated workers and dictionaries. The owner must install or grant
the CodeRabbit GitHub App access to this repository before reviews will run.
Check current plan eligibility and repository access before activation. The
file itself does not subscribe to a plan or install the app. Review suggestions
before applying them.

## Issues and releases

Use the bug and feature forms, and label issues with `bug`, `enhancement`,
`needs reproduction`, or `good first issue` as appropriate. Do not automatically
close unresolved bugs merely because they are old.

Maintain `CHANGELOG.md` under Unreleased. For an intentional release, run the
required checks, update `manifest.json` and the changelog to the chosen version,
create a matching `vX.Y.Z` tag, and prepare a GitHub release. The release-note
configuration groups changes by label; review the generated notes before
publishing. Do not create tags or releases for every merged PR.

## Repository readiness

- Review the files and history for private data and confirm release readiness.
- Enable private vulnerability reporting and follow `SECURITY.md`.
- Verify secret scanning/push protection and Dependabot alerts are enabled.
- Verify branch rules and required CI checks are enforced.
- Connect CodeRabbit if wanted and verify plan eligibility.
- Keep the README installation command usable with the canonical HTTPS URL.

Repeat these checks when repository visibility or plan settings change.
Committing configuration does not activate GitHub features or external apps.
Evaluate CodeQL separately; its JavaScript coverage does not replace QML tests.
