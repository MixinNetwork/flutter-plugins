# AGENTS

## Scope

This file describes repository-wide guidance for the `flutter-plugins` monorepo. Package-specific guidance may exist deeper in the tree and should be treated as higher-priority context for that subtree.

Detailed guidance for `mixin_markdown_widget` lives in [packages/mixin_markdown_widget/lib/AGENTS.md](packages/mixin_markdown_widget/AGENTS.md).

## Repository Overview

- This repository is a Dart/Flutter monorepo centered around the `packages/` directory.
- Most entries under `packages/` are independent Flutter plugins or Dart/Flutter libraries with their own `pubspec.yaml`, `analysis_options.yaml`, `README.md`, tests, and often an `example/` app.
- Public package APIs are generally exposed from a single top-level library file at `lib/<package>.dart`.
- The root [README.md](README.md) contains a manually maintained package table; if package status or documentation changes materially, check whether that table should be updated too.
- Publishing is not automatic for every package. The workflow at `.github/workflows/publish.yml` uses an explicit allowlist of package names and tag patterns.

## Monorepo Working Rules

- Scope changes to the smallest affected package unless the request explicitly spans multiple packages.
- Avoid repository-wide refactors unless they are clearly required; packages in this monorepo are mostly independent.
- Preserve each package's local style, linting, and platform structure instead of imposing a new shared pattern from the root.
- When changing a package's public API, check the package's top-level export file, README, tests, and example usage together.
- Prefer package-local validation from the package root rather than running broad workspace-wide commands.
- Treat generated or platform-host files carefully; do not rewrite native glue code or generated outputs unless the task actually requires it.

## Common Layout Expectations

- `packages/<name>/lib/` holds the package's public entrypoint and source tree.
- `packages/<name>/test/` contains focused regression coverage and should be updated when behavior changes.
- `packages/<name>/example/` is the fastest place to verify interactive or visual behavior for UI-heavy packages.
- Many packages in this repo are desktop-focused plugins, so changes often have platform-specific implications even when the Dart API surface looks small.

## Validation Guidance

- Prefer targeted test runs first, then broader package-level validation if the change affects shared behavior.
- For Flutter UI packages, pair automated tests with an `example/` sanity check when interaction or rendering is involved.
- Keep unrelated packages untouched unless there is a verified cross-package dependency.
