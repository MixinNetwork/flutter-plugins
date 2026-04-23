---
name: flutter-pub-release
description: Prepare and draft a pub.dev release for a package in the flutter-plugins monorepo. Use when the user wants to generate changelog entries from commits since the last `{package}-v*` tag, bump the package version in `pubspec.yaml`, update `CHANGELOG.md`, and draft a GitHub release whose tag is `{package}-v{version}` for `.github/workflows/publish.yml`.
---

# Flutter Pub Release

Use this skill for package releases inside this repository.

Repository assumptions:
- Package source lives at `packages/<package>/`.
- Package version lives in `packages/<package>/pubspec.yaml`.
- Package changelog lives in `packages/<package>/CHANGELOG.md`.
- Example lockfile lives at `packages/<package>/example/pubspec.lock` when the package has an example app.
- Publish tags use `{package}-v{version}` and are consumed by `.github/workflows/publish.yml`.

Core rules:
- Generate changelog entries from commits touching `packages/<package>/` since the latest `{package}-v*` tag.
- Let the model inspect the actual code changes, public API surface, tests, examples, and commit context to judge whether this release is a breaking change.
- If the model judges it as breaking, bump the minor version and reset patch to `0`.
- Otherwise bump the patch version.
- Keep release notes and `CHANGELOG.md` in the same format.
- For PRs from other contributors, render entries exactly like:

```md
* fix build on android [#285](https://github.com/MixinNetwork/flutter-plugins/pull/285)
  by [AdamVe](https://github.com/AdamVe)
```

## Workflow

1. Verify repo state before editing.
- Run `gh auth status`.
- Prefer a clean worktree before release prep.

2. Preview the release plan.
- First inspect the package diff since the latest release tag and decide the bump in-model. Do not rely on a regex or commit-message heuristic for breaking-change detection.
- Useful checks:
  - `git diff <previous-tag>..HEAD -- packages/<package>`
  - `git log --oneline <previous-tag>..HEAD -- packages/<package>`
  - public exports under `packages/<package>/lib/`
  - matching tests, README, and `example/` changes when relevant
- Run:

```bash
python3 .codex/skills/flutter-pub-release/scripts/release_helper.py plan <package> --bump patch
```

- Use `--bump minor` when the model believes the change is breaking.
- Use `--version x.y.z` if you want to pin the exact version directly.

- This prints JSON with:
  - previous tag
  - next version
  - tag name
  - rendered changelog section

3. Apply the release files when the user wants the change written.
- Run:

```bash
python3 .codex/skills/flutter-pub-release/scripts/release_helper.py apply <package> --bump patch
```

- This updates:
  - `packages/<package>/pubspec.yaml`
  - `packages/<package>/CHANGELOG.md`
  - `packages/<package>/example/pubspec.lock` when present

- Then run dependency resolution from the package directory so lock/state stays consistent with the new version:

```bash
cd packages/<package>
dart pub get
```

4. Validate narrowly.
- Run package-scoped checks only when they are fast and relevant.
- Do not expand into repo-wide validation unless the change genuinely spans packages.

5. Commit and run publish dry-run before drafting the release.
- Use an English commit message such as:

```text
chore(release): prepare <package> <version>
```

- Commit the release changes directly on `main`.
- After commit, run a publish dry-run from the package directory and fix any reported errors before pushing:

```bash
cd packages/<package>
dart pub publish --dry-run
```

- Push `main`.

6. Draft the GitHub release.
- Run:

```bash
python3 .codex/skills/flutter-pub-release/scripts/release_helper.py draft-release <package>
```

- The script reads the current package version, extracts the matching changelog section, and creates a draft GitHub release with:
  - tag: `{package}-v{version}`
  - title: `{package}-v{version}`
  - notes: the same changelog section
  - target: current `HEAD`

- Stop there. Do not try to verify whether the tag exists remotely or whether `.github/workflows/publish.yml` has started running. This workflow is only responsible for preparing the draft release.

## Notes

- The script detects PR numbers from squash-merge subjects like `(#123)`.
- The script does not decide whether a release is breaking. The model must decide that before calling `plan` or `apply`.
- If the user wants to override the bump, use:

```bash
python3 .codex/skills/flutter-pub-release/scripts/release_helper.py plan <package> --bump minor
python3 .codex/skills/flutter-pub-release/scripts/release_helper.py apply <package> --version 0.2.0
```

- If the package has no previous tag, stop and ask the user how they want the first release version handled instead of guessing.
