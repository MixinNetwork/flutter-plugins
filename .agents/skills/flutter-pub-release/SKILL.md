---
name: flutter-pub-release
description: Prepare, publish, and verify pub.dev releases for packages in the flutter-plugins monorepo. Use when the user asks to prepare or publish a package release, including version selection, curated changelog entries, GitHub releases, and verification of the tag-triggered publish workflow and exact version on pub.dev.
---

# Flutter Pub Release

Use this skill for package releases in this repository. The Agent analyzes changes, chooses the version, and edits release files directly. `scripts/release_helper.py` only publishes and verifies the prepared release. Run the commands below from the repository root.

## Scope and completion

- A request to publish authorizes preparing release files, committing and pushing the release commit on `main`, creating a published GitHub release, and verifying publication. Complete these steps without handing the user a manual Publish button.
- A request to review the process, modify this skill, or prepare files only does not authorize publication. Respect any narrower scope given by the user.
- Create a draft only when explicitly requested, using `release --draft`. Draft creation is complete at the draft URL; it does not publish the package.
- A full release is complete only when the remote tag resolves to the release commit, the matching tag-triggered `publish.yml` run and its actual publish step succeed, and pub.dev serves the exact package version.
- Preserve unrelated local work. Do not automatically stash, discard, commit unrelated files, or create a worktree. If the release cannot proceed in the current checkout, explain the concrete conflict.

## Changelog editing

The Agent reads Git history and PR context and writes the final release notes directly in `CHANGELOG.md`. Inspect the actual diff, public API, README, tests, and examples. Commit and PR titles are source material, not finished entries.

- Describe changes for package users in English. Remove package names and prefixes such as `feat:` from the prose. Keep exact API names in backticks.
- Use `- ` bullets, sentence case, and consistent final periods. Each bullet describes one change; combine only closely related changes. Keep the triggering condition or migration detail when needed to understand the impact.
- Omit internal CI, tests, example-only work, and development tooling unless they affect consumers. Include dependency or SDK requirements that change compatibility.
- Prefix platform-specific entries with `Windows:`, `macOS:`, or `Linux:`. For a large multi-platform release, group under `### Windows`, etc. instead of repeating prefixes. Avoid headings for small releases.
- Put PR links and credit at the end of the same bullet. Credit external contributors using the PR author metadata. Preserve attribution when combining entries; a PR may produce several user-facing changes.
- Put breaking changes under `### Breaking changes`, naming the removed or changed API and the replacement or migration action. Summarize longer migrations and link to the README.
- Keep the final changelog section and GitHub release body identical. Preserve historical sections and the package's existing top-level heading style.

Example formatting:

```markdown
## 0.3.2

- Windows: Fix blank pages after navigation approval. ([#508](https://github.com/MixinNetwork/flutter-plugins/pull/508); thanks [mtallenca](https://github.com/mtallenca))
- Linux: Fix crashes when closing WebView windows.
```

## Workflow

### 1. Analyze changes and choose the version

Run `gh auth status`. Start preparation on a clean, synchronized `main`; refresh remote main and tags before choosing the release base:

```bash
git fetch origin refs/heads/main:refs/remotes/origin/main --tags
git status --short
git log --oneline HEAD..origin/main
git log --oneline origin/main..HEAD
git ls-remote --tags --refs origin '<package>-v*'
```

If local main differs from remote main, reconcile it before preparing the release. Confirm the package is enabled in `.github/workflows/publish.yml`. Select the highest stable version tag from the remote tag list, then verify it belongs to the current history with `git merge-base --is-ancestor <previous-tag> HEAD`. Use remote tags rather than unpushed local tags.

Read `git diff <previous-tag>..HEAD -- packages/<package>` and `git log <previous-tag>..HEAD -- packages/<package>`, plus shared configuration changes that affect the package. Use `gh pr view <number> --repo MixinNetwork/flutter-plugins --json title,body,author,url` for relevant PRs. Recognize both squash subjects ending in `(#123)` and ordinary `Merge pull request #123 ...` commits; deduplicate PR context and preserve contributor attribution.

Choose the version from the actual API and compatibility changes. For the repository's `0.x` packages, increment the minor version and reset patch to zero for breaking changes; increment patch otherwise. For stable `1.x` or later, increment major for breaking changes, minor for compatible new features, and patch for fixes. Respect an explicit user version choice, but explain compatibility conflicts before proceeding. Use a stable `x.y.z` version greater than the previous release.

Before bumping, compare `pubspec.yaml` with the latest remote tag. If they differ, inspect whether a prior release was prepared, failed, or is still running. Resume that release rather than automatically bumping again. If no previous tag exists, determine the first release and its separate pub.dev setup before proceeding.

### 2. Edit release files directly

Update `packages/<package>/pubspec.yaml` and prepend the curated `## <next-version>` section to `packages/<package>/CHANGELOG.md`. Preserve historical sections and the existing top-level heading style. Check for an exact duplicate version heading; `0.3.1` and `0.3.10` are different versions. The release section must contain nonempty `- ` bullets.

Run `dart pub get` at the repository root. The workspace uses a root `pubspec.lock`; do not hand-edit example lockfiles. Inspect the resulting diff and keep only necessary release changes. The helper does not calculate versions, collect changelog material, or edit these files.

### 3. Validate, commit, and push

Run relevant package-scoped tests and analysis, then publish dry-run from the package directory (`flutter pub publish --dry-run` for Flutter packages, `dart pub publish --dry-run` for Dart packages). Fix failures before committing. Inspect the dry-run file list for unexpected files.

Commit the release files on `main` with a package-scoped English message such as `<package>: prepare release <version>`. Include necessary root lockfile changes. Push `main` normally. If the push is rejected, stop and reconcile the new remote changes; do not force-push or reuse validation from a different commit without reviewing the difference.

### 4. Publish and verify

When the user requested publication, run:

```bash
python3 .agents/skills/flutter-pub-release/scripts/release_helper.py release <package>
```

The helper checks clean `main` against refreshed remote main, reads the version and exact changelog section, and creates a **published** GitHub release targeting that commit. Creating its new tag triggers the existing `publish.yml`; keep tag-push publishing rather than switching to a release-event or manual-dispatch publisher.

The helper then checks the remote tag, published release body, workflow identity, successful publish step, and exact pub.dev version. Verification defaults to 900 seconds; use `--timeout <seconds>` when necessary. While the command runs, continue giving the user concise progress updates.

If publication fails, report the failing stage and workflow URL. If verification times out or the creation command returns an uncertain result, inspect the release/tag and workflow before retrying. Do not automatically delete or replace tags, create a second release, or choose a new version. To resume read-only checks, use a clean checkout at the original release commit and run:

```bash
python3 .agents/skills/flutter-pub-release/scripts/release_helper.py verify <package>
```

Report the version, commit, GitHub release URL, publish workflow URL, and pub.dev version URL. Distinguish a created GitHub release from verified pub.dev publication. If the user requested preparation only, report the prepared files and validation without running `release`.
