#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[4]
REPO = "MixinNetwork/flutter-plugins"
VERSION_RE = re.compile(r"^version:\s*([^\s]+)[ \t]*$", re.MULTILINE)
STABLE_VERSION_RE = re.compile(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)")


class ReleaseError(RuntimeError):
    pass


def run(cmd: list[str], *, cwd: Path | None = None, check: bool = True) -> str:
    completed = subprocess.run(cmd, cwd=cwd or ROOT, text=True, capture_output=True)
    if check and completed.returncode != 0:
        raise ReleaseError(completed.stderr.strip() or completed.stdout.strip() or "command failed")
    return completed.stdout


def git(*args: str, check: bool = True) -> str:
    return run(["git", *args], check=check)


def gh(*args: str) -> str:
    return run(["gh", *args])


def package_dir(package: str) -> Path:
    workflow = (ROOT / ".github/workflows/publish.yml").read_text()
    allowed = re.findall(r"^\s+- ['\"]([a-z][a-z0-9_]*)-v", workflow, re.MULTILINE)
    if package not in allowed:
        raise ReleaseError(f"{package} is not enabled in .github/workflows/publish.yml")
    path = ROOT / "packages" / package
    if not path.is_dir():
        raise ReleaseError(f"package not found: {package}")
    return path


def read_pubspec_version(pubspec_path: Path) -> str:
    match = VERSION_RE.search(pubspec_path.read_text())
    if not match:
        raise ReleaseError(f"failed to find version in {pubspec_path}")
    version = match.group(1)
    if not STABLE_VERSION_RE.fullmatch(version):
        raise ReleaseError(f"expected a stable version x.y.z, got {version!r}")
    return version


def refresh_remote() -> None:
    git("fetch", "origin", "refs/heads/main:refs/remotes/origin/main", "--tags")


def section_bounds(content: str, version: str) -> tuple[int, int]:
    headings = list(re.finditer(r"^##[ \t]+(.+?)[ \t]*$", content, re.MULTILINE))
    matches = [(index, heading) for index, heading in enumerate(headings) if heading.group(1) == version]
    if len(matches) != 1:
        raise ReleaseError(f"expected exactly one changelog section for {version}, found {len(matches)}")
    index, heading = matches[0]
    end = headings[index + 1].start() if index + 1 < len(headings) else len(content)
    return heading.start(), end


def extract_section(changelog_path: Path, version: str) -> str:
    content = changelog_path.read_text()
    start, end = section_bounds(content, version)
    return content[start:end].strip() + "\n"


def validate_notes(notes: str, version: str) -> str:
    notes = notes.strip() + "\n"
    start, end = section_bounds(notes, version)
    if start != 0 or end != len(notes):
        raise ReleaseError(f"notes must contain only the ## {version} section")
    if not re.search(r"^- \S", notes, re.MULTILINE):
        raise ReleaseError("notes must contain nonempty '- ' bullets written for package users")
    return notes


def ensure_clean_worktree() -> None:
    if git("status", "--short").strip():
        raise ReleaseError("worktree is not clean; preserve existing changes before releasing or verifying")


def ensure_on_main_branch() -> None:
    branch = git("rev-parse", "--abbrev-ref", "HEAD").strip()
    if branch != "main":
        raise ReleaseError(f"not on main branch (currently on {branch})")


def remote_tag_target(tag: str) -> str | None:
    output = git("ls-remote", "--tags", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    refs = dict(line.split()[::-1] for line in output.splitlines())
    return refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}")


def ensure_synced_with_origin_main() -> None:
    if git("rev-parse", "HEAD").strip() != git("rev-parse", "origin/main").strip():
        raise ReleaseError("HEAD differs from refreshed origin/main; synchronize main before proceeding")


def release_metadata(package: str) -> tuple[str, str, str]:
    pkg_dir = package_dir(package)
    version = read_pubspec_version(pkg_dir / "pubspec.yaml")
    notes = validate_notes(extract_section(pkg_dir / "CHANGELOG.md", version), version)
    return version, f"{package}-v{version}", notes


def pub_version_available(package: str, version: str) -> bool:
    url = f"https://pub.dev/api/packages/{package}/versions/{version}"
    try:
        with urlopen(url, timeout=20) as response:
            data = json.load(response)
    except HTTPError as error:
        error.close()
        if error.code in (404, 429) or error.code >= 500:
            return False
        raise ReleaseError(f"pub.dev verification failed: HTTP {error.code}") from error
    except (URLError, TimeoutError):
        return False
    pubspec = data.get("pubspec", {})
    return data.get("version") == version and pubspec.get("version") == version and pubspec.get("name") == package


def verify_release(package: str, timeout: int) -> dict[str, Any]:
    version, tag, notes = release_metadata(package)
    target = git("rev-parse", "HEAD").strip()
    release = json.loads(gh(
        "release", "view", tag, "--repo", REPO, "--json", "tagName,isDraft,body,url",
    ))
    if release["isDraft"] or release["tagName"] != tag:
        raise ReleaseError(f"{tag} is not a published GitHub release")
    if release["body"].replace("\r\n", "\n").strip() != notes.strip():
        raise ReleaseError(f"{tag} release notes differ from the committed changelog")
    deadline = time.monotonic() + timeout
    state = "waiting for remote tag"
    publish_run = None
    while time.monotonic() < deadline:
        remote_target = remote_tag_target(tag)
        if remote_target is not None and remote_target != target:
            raise ReleaseError(f"{tag} points to {remote_target}, expected {target}")
        if remote_target == target and publish_run is None:
            runs = json.loads(gh(
                "run", "list", "--repo", REPO, "--workflow", "publish.yml", "--branch", tag,
                "--event", "push", "--commit", target, "--limit", "20",
                "--json", "databaseId,headSha,headBranch,status,conclusion,url",
            ))
            runs = [item for item in runs if item["headSha"] == target and item["headBranch"] == tag]
            state = "waiting for tag-triggered publish.yml"
            if runs:
                candidate = runs[0]
                state = f"publish.yml {candidate['status']}: {candidate['url']}"
                if candidate["status"] == "completed":
                    if candidate["conclusion"] != "success":
                        raise ReleaseError(f"publish failed ({candidate['conclusion']}): {candidate['url']}")
                    details = json.loads(gh(
                        "run", "view", str(candidate["databaseId"]), "--repo", REPO, "--json", "jobs",
                    ))
                    steps = [step for job in details["jobs"] for step in job.get("steps", [])
                             if step["name"] == "Publish to pub.dev"]
                    if not steps or any(step.get("conclusion") != "success" for step in steps):
                        raise ReleaseError(f"publish step did not succeed: {candidate['url']}")
                    publish_run = candidate
        if remote_target == target and publish_run is not None:
            state = "waiting for the exact version on pub.dev"
            if pub_version_available(package, version):
                return {
                    "package": package, "version": version, "tag": tag, "target": target,
                    "release_url": release["url"], "workflow_url": publish_run["url"],
                    "pub_url": f"https://pub.dev/packages/{package}/versions/{version}",
                    "verified": True,
                }
        print(state, file=sys.stderr, flush=True)
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(min(10, remaining))
    raise ReleaseError(
        f"verification timed out: {state}; release may already exist. "
        f"Resume with verify {package}; do not create another release or replace the tag."
    )


def cmd_release(args: argparse.Namespace) -> int:
    ensure_on_main_branch()
    ensure_clean_worktree()
    refresh_remote()
    ensure_synced_with_origin_main()
    version, tag, notes = release_metadata(args.package)
    if remote_tag_target(tag) is not None:
        raise ReleaseError(f"tag {tag} already exists; inspect it and use verify instead of recreating it")
    target = git("rev-parse", "HEAD").strip()
    with tempfile.NamedTemporaryFile("w", encoding="utf-8") as handle:
        handle.write(notes)
        handle.flush()
        command = ["release", "create", tag, "--repo", REPO, "--title", tag,
                   "--target", target, "--notes-file", handle.name]
        if args.draft:
            command.append("--draft")
        url = gh(*command).strip()
    print(json.dumps({"tag": tag, "target": target, "release_url": url, "draft": args.draft}), flush=True)
    if not args.draft:
        print(json.dumps(verify_release(args.package, args.timeout), indent=2))
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    ensure_clean_worktree()
    print(json.dumps(verify_release(args.package, args.timeout), indent=2))
    return 0


def positive_seconds(value: str) -> int:
    seconds = int(value)
    if seconds <= 0:
        raise argparse.ArgumentTypeError("timeout must be positive")
    return seconds


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Publish and verify flutter-plugins releases.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    for command in ("release", "verify"):
        subparser = subparsers.add_parser(command, help="publish and verify" if command == "release" else "resume read-only verification")
        subparser.add_argument("package", help="package name under packages/")
        subparser.add_argument("--timeout", type=positive_seconds, default=900, help="verification timeout in seconds (default: 900)")
        if command == "release":
            subparser.add_argument("--draft", action="store_true", help="create only a draft when explicitly requested")
        subparser.set_defaults(func=cmd_release if command == "release" else cmd_verify)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        return args.func(args)
    except (ReleaseError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
