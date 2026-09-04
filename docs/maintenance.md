# Maintaining JotPin

The repository is `l1qu1d/jotpin`. Keep it private until the owner chooses to
publish it. Repository visibility and external app installation are separate
from the configuration committed here.

## Pull requests and CI

Use short branches and pull requests for changes. CI runs on pushes to `main`,
pull requests, and manual dispatch, with read-only repository permissions and
no persisted checkout credentials. It never runs the desktop-interactive suite.

- **Model tests** run portable JavaScript tests on Ubuntu with Node 24.
- **Full headless suite** runs the existing production runner in an isolated
  Arch container. Omarchy's source revision is pinned in the workflow; its
  install scripts and desktop shell are never started. Arch packages follow
  the current repository, so this also detects dependency compatibility drift.

Once both jobs are green, require these checks in the `main` branch rules and
block force pushes and deletion. A solo maintainer need not require another
human's approval. Private-repository branch rules depend on the GitHub plan;
enable them when available and check them again when making the project public.
Use squash merges and delete merged branches. Do not automatically merge
dependency or AI-generated changes.

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
Check the private-repository plan before activation; the free open-source
offering applies after publication. The file itself does not subscribe to a
plan or install the app. Review suggestions before applying them.

## Issues and releases

Use the bug and feature forms, and label issues with `bug`, `enhancement`,
`needs reproduction`, or `good first issue` as appropriate. Do not automatically
close unresolved bugs merely because they are old.

Maintain `CHANGELOG.md` under Unreleased. For an intentional release, run the
required checks, update `manifest.json` and the changelog to the chosen version,
create a matching `vX.Y.Z` tag, and prepare a GitHub release. The release-note
configuration groups changes by label; review the generated notes before
publishing. Do not create tags or releases for every merged PR.

## Before making the repository public

- Review the files and history for private data and confirm release readiness.
- Enable private vulnerability reporting and follow `SECURITY.md`.
- Verify secret scanning/push protection and Dependabot alerts are enabled.
- Enable branch rules and required CI checks if unavailable on the private plan.
- Connect CodeRabbit if wanted and verify its open-source plan status.
- Check the SSH installation instructions; public users can use the HTTPS URL.

GitHub features that require a paid private-repository plan are not activated
by committing these files. CodeQL can be considered after publication, but its
JavaScript coverage does not replace QML tests.
