#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[4]
REPO = "MixinNetwork/flutter-plugins"
PR_SUFFIX_RE = re.compile(r"\s*\(#(\d+)\)\s*$")
VERSION_RE = re.compile(r"^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)([^\s]*)?\s*$", re.MULTILINE)


class ReleaseError(RuntimeError):
    pass


@dataclass
class CommitInfo:
    sha: str
    subject: str
    author_name: str
    author_email: str
    body: str
    pr_number: int | None


def run(cmd: list[str], *, cwd: Path = ROOT, check: bool = True) -> str:
    completed = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        capture_output=True,
    )
    if check and completed.returncode != 0:
        raise ReleaseError(completed.stderr.strip() or completed.stdout.strip() or "command failed")
    return completed.stdout


def git(*args: str, check: bool = True) -> str:
    return run(["git", *args], check=check)


def gh(*args: str, check: bool = True) -> str:
    return run(["gh", *args], check=check)


def package_dir(package: str) -> Path:
    path = ROOT / "packages" / package
    if not path.is_dir():
        raise ReleaseError(f"package not found: {package}")
    return path


def read_pubspec_version(pubspec_path: Path) -> str:
    content = pubspec_path.read_text()
    match = VERSION_RE.search(content)
    if not match:
        raise ReleaseError(f"failed to find version in {pubspec_path}")
    return ".".join(match.group(i) for i in range(1, 4))


def replace_pubspec_version(pubspec_path: Path, version: str) -> None:
    content = pubspec_path.read_text()
    new_content, count = VERSION_RE.subn(f"version: {version}", content, count=1)
    if count != 1:
        raise ReleaseError(f"failed to update version in {pubspec_path}")
    pubspec_path.write_text(new_content)


def update_example_lock_version(lock_path: Path, package: str, version: str) -> bool:
    if not lock_path.exists():
        return False

    content = lock_path.read_text()
    lines = content.splitlines()
    package_header = f"  {package}:"
    in_package_block = False

    for index, line in enumerate(lines):
        if line == package_header:
            in_package_block = True
            continue
        if not in_package_block:
            continue
        if line.startswith("  ") and not line.startswith("    "):
            break
        if line.strip().startswith('version: "'):
            lines[index] = f'    version: "{version}"'
            lock_path.write_text("\n".join(lines) + "\n")
            return True

    raise ReleaseError(f"failed to update {package} version in {lock_path}")


def latest_tag(package: str) -> str:
    output = git("tag", "--list", f"{package}-v*", "--sort=-version:refname").strip().splitlines()
    if not output:
        raise ReleaseError(
            f"no previous tag found for {package}; first release needs an explicit version decision"
        )
    return output[0]


def parse_pr_number(subject: str) -> int | None:
    match = PR_SUFFIX_RE.search(subject)
    if not match:
        return None
    return int(match.group(1))


def load_commits(package: str, previous_tag: str) -> list[CommitInfo]:
    output = git(
        "log",
        "--reverse",
        "--format=%H%x1f%s%x1f%an%x1f%ae%x1f%b%x1e",
        f"{previous_tag}..HEAD",
        "--",
        f"packages/{package}",
    )
    commits: list[CommitInfo] = []
    for record in output.split("\x1e"):
        record = record.rstrip("\n")
        if not record:
            continue
        parts = record.split("\x1f", 4)
        if len(parts) != 5:
            raise ReleaseError("unexpected git log format")
        sha, subject, author_name, author_email, body = parts
        commits.append(
            CommitInfo(
                sha=sha,
                subject=subject.strip(),
                author_name=author_name.strip(),
                author_email=author_email.strip(),
                body=body.strip(),
                pr_number=parse_pr_number(subject),
            )
        )
    if not commits:
        raise ReleaseError(f"no commits found for packages/{package} since {previous_tag}")
    return commits


def current_github_login() -> str:
    return gh("api", "user", "--jq", ".login").strip()


def load_pr_details(pr_number: int) -> dict[str, Any]:
    output = gh(
        "pr",
        "view",
        str(pr_number),
        "--repo",
        REPO,
        "--json",
        "number,title,url,body,author",
    )
    return json.loads(output)


def cleanup_title(title: str) -> str:
    return PR_SUFFIX_RE.sub("", title).strip()


def bump_version(current_version: str, bump: str) -> str:
    major, minor, patch = [int(part) for part in current_version.split(".")]
    if bump == "minor":
        return f"{major}.{minor + 1}.0"
    if bump == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise ReleaseError(f"unsupported bump: {bump}")


def contributor_line(login: str) -> str:
    return f"  by [{login}](https://github.com/{login})"


def render_entries(
    commits: list[CommitInfo],
    prs: dict[int, dict[str, Any]],
    current_login: str,
) -> list[str]:
    lines: list[str] = []
    emitted_prs: set[int] = set()
    for commit in commits:
        if commit.pr_number and commit.pr_number in prs:
            if commit.pr_number in emitted_prs:
                continue
            emitted_prs.add(commit.pr_number)
            pr = prs[commit.pr_number]
            title = cleanup_title(pr["title"])
            lines.append(f"* {title} [#{pr['number']}]({pr['url']})")
            author = pr.get("author") or {}
            login = author.get("login")
            if login and login != current_login:
                lines.append(contributor_line(login))
            continue

        title = cleanup_title(commit.subject)
        lines.append(f"* {title}")
    return lines


def render_section(version: str, entries: list[str], breaking: bool) -> str:
    lines = [f"## {version}", ""]
    if breaking:
        lines.extend(["**BREAKING CHANGE**", ""])
    lines.extend(entries)
    return "\n".join(lines).rstrip() + "\n"


def extract_section(changelog_path: Path, version: str) -> str:
    content = changelog_path.read_text()
    heading = f"## {version}"
    start = content.find(heading)
    if start == -1:
        raise ReleaseError(f"version section {version} not found in {changelog_path}")
    next_heading = content.find("\n## ", start + len(heading))
    if next_heading == -1:
        section = content[start:].strip()
    else:
        section = content[start:next_heading].strip()
    return section + "\n"


def update_changelog(changelog_path: Path, section: str, version: str) -> None:
    content = changelog_path.read_text() if changelog_path.exists() else "# Changelog\n"
    if f"## {version}" in content:
        raise ReleaseError(f"{changelog_path} already contains version {version}")

    heading = "# Changelog"
    if heading in content:
        prefix, suffix = content.split(heading, 1)
        rest = suffix.lstrip("\n")
        new_content = f"{prefix}{heading}\n\n{section}\n{rest.lstrip()}"
    else:
        new_content = f"# Changelog\n\n{section}\n{content.lstrip()}"
    changelog_path.write_text(new_content.rstrip() + "\n")


def ensure_clean_worktree() -> None:
    if git("status", "--short").strip():
        raise ReleaseError("worktree is not clean; commit or stash changes before drafting the release")


def resolve_release_intent(
    current_version: str,
    bump_override: str | None,
    version_override: str | None,
) -> tuple[str, str, bool]:
    if version_override:
        breaking = version_override.split(".")[1] != current_version.split(".")[1]
        return "custom", version_override, breaking
    if not bump_override:
        raise ReleaseError("missing version decision; pass --bump {patch|minor} or --version x.y.z")
    next_version = bump_version(current_version, bump_override)
    return bump_override, next_version, bump_override == "minor"


def plan_release(package: str, bump_override: str | None, version_override: str | None) -> dict[str, Any]:
    pkg_dir = package_dir(package)
    pubspec_path = pkg_dir / "pubspec.yaml"
    previous_tag = latest_tag(package)
    commits = load_commits(package, previous_tag)
    pr_numbers = []
    for commit in commits:
        if commit.pr_number and commit.pr_number not in pr_numbers:
            pr_numbers.append(commit.pr_number)
    prs = {number: load_pr_details(number) for number in pr_numbers}
    current_login = current_github_login()
    current_version = read_pubspec_version(pubspec_path)
    bump, next_version, breaking = resolve_release_intent(
        current_version,
        bump_override,
        version_override,
    )
    entries = render_entries(commits, prs, current_login)
    section = render_section(next_version, entries, breaking)
    return {
        "package": package,
        "previous_tag": previous_tag,
        "current_version": current_version,
        "next_version": next_version,
        "bump": bump,
        "breaking": breaking,
        "tag": f"{package}-v{next_version}",
        "entries": entries,
        "changelog": section,
    }


def cmd_plan(args: argparse.Namespace) -> int:
    plan = plan_release(args.package, args.bump, args.version)
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    plan = plan_release(args.package, args.bump, args.version)
    pkg_dir = package_dir(args.package)
    pubspec_path = pkg_dir / "pubspec.yaml"
    changelog_path = pkg_dir / "CHANGELOG.md"
    example_lock_path = pkg_dir / "example" / "pubspec.lock"
    replace_pubspec_version(pubspec_path, plan["next_version"])
    update_changelog(changelog_path, plan["changelog"], plan["next_version"])
    example_lock_updated = update_example_lock_version(
        example_lock_path,
        args.package,
        plan["next_version"],
    )
    updated_files = [
        str(pubspec_path.relative_to(ROOT)),
        str(changelog_path.relative_to(ROOT)),
    ]
    if example_lock_updated:
        updated_files.append(str(example_lock_path.relative_to(ROOT)))
    print(json.dumps({
        "package": args.package,
        "version": plan["next_version"],
        "tag": plan["tag"],
        "updated": updated_files,
    }, ensure_ascii=False, indent=2))
    return 0


def cmd_draft_release(args: argparse.Namespace) -> int:
    pkg_dir = package_dir(args.package)
    pubspec_path = pkg_dir / "pubspec.yaml"
    changelog_path = pkg_dir / "CHANGELOG.md"
    version = args.version or read_pubspec_version(pubspec_path)
    tag = f"{args.package}-v{version}"
    notes = extract_section(changelog_path, version)
    ensure_clean_worktree()
    target_ref = git("rev-parse", "HEAD").strip()

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
        handle.write(notes)
        notes_path = handle.name

    gh(
        "release",
        "create",
        tag,
        "--repo",
        REPO,
        "--draft",
        "--title",
        tag,
        "--target",
        target_ref,
        "--notes-file",
        notes_path,
    )
    print(json.dumps({
        "package": args.package,
        "version": version,
        "tag": tag,
        "target": target_ref,
        "notes_file": notes_path,
    }, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prepare and draft a package release for flutter-plugins.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_shared_flags(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("package", help="package name under packages/")
        subparser.add_argument(
            "--bump",
            choices=["patch", "minor"],
            help="override bump type",
        )
        subparser.add_argument(
            "--version",
            help="override next version directly",
        )

    plan_parser = subparsers.add_parser("plan", help="preview the computed release plan")
    add_shared_flags(plan_parser)
    plan_parser.set_defaults(func=cmd_plan)

    apply_parser = subparsers.add_parser("apply", help="update pubspec.yaml and CHANGELOG.md")
    add_shared_flags(apply_parser)
    apply_parser.set_defaults(func=cmd_apply)

    release_parser = subparsers.add_parser("draft-release", help="create the draft GitHub release")
    release_parser.add_argument("package", help="package name under packages/")
    release_parser.add_argument("--version", help="release version to draft; defaults to pubspec.yaml")
    release_parser.set_defaults(func=cmd_draft_release)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
