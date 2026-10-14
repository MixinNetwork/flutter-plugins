#!/usr/bin/env python3

import argparse
from contextlib import ExitStack, redirect_stdout, redirect_stderr
import io
import json
import re
import shutil
import textwrap
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import release_helper as helper


PACKAGE = "desktop_drop"
VERSION = "0.1.1"
TAG = f"{PACKAGE}-v{VERSION}"
NOTES = f"## {VERSION}\n\n- Windows: Fix dropped file paths.\n"
SHA = "a" * 40
RELEASE = {"tagName": TAG, "isDraft": False, "body": NOTES, "url": "https://example.test/release"}
RUN = {
    "databaseId": 123, "headSha": SHA, "headBranch": TAG,
    "status": "completed", "conclusion": "success", "url": "https://example.test/run",
}
JOBS = {"jobs": [{"steps": [{"name": "Publish to pub.dev", "conclusion": "success"}]}]}


class NotesTests(unittest.TestCase):
    def test_exact_version_matching(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "CHANGELOG.md"
            path.write_text("## 0.3.10\n\n- New fix.\n\n## 0.3.1\n\n- Old fix.\n")
            self.assertEqual(helper.extract_section(path, "0.3.1"), "## 0.3.1\n\n- Old fix.\n")
            path.write_text("## 0.3.10\n\n- New fix.\n")
            with self.assertRaises(helper.ReleaseError):
                helper.extract_section(path, "0.3.1")

    def test_accepts_curated_notes_with_subsections(self):
        section = NOTES + "\n### Linux\n\n- Fix window closing.\n"
        self.assertEqual(helper.validate_notes(section, VERSION), section)

    def test_rejects_wrong_empty_or_multiple_sections(self):
        for notes in ("## 0.1.10\n\n- Wrong version.\n", f"## {VERSION}\n", NOTES + "\n## 0.1.0\n\n- Extra.\n"):
            with self.subTest(notes=notes), self.assertRaises(helper.ReleaseError):
                helper.validate_notes(notes, VERSION)

    def test_rejects_duplicate_version_sections(self):
        with self.assertRaises(helper.ReleaseError):
            helper.validate_notes(NOTES + "\n" + NOTES, VERSION)

    def test_pubspec_requires_stable_version(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pubspec.yaml"
            for version in ("invalid", "0.2", "0.2.0-beta.1"):
                path.write_text(f"version: {version}\n")
                with self.subTest(version=version), self.assertRaises(helper.ReleaseError):
                    helper.read_pubspec_version(path)
            path.write_text(f"version: {VERSION}\n")
            self.assertEqual(helper.read_pubspec_version(path), VERSION)

    def test_cli_only_supports_publish_and_verify_without_version_override(self):
        parser = helper.build_parser()
        with redirect_stderr(io.StringIO()):
            for args in (["plan", PACKAGE], ["apply", PACKAGE], ["release", PACKAGE, "--version", VERSION]):
                with self.subTest(args=args), self.assertRaises(SystemExit):
                    parser.parse_args(args)
        self.assertEqual(parser.parse_args(["release", PACKAGE]).func, helper.cmd_release)
        self.assertEqual(parser.parse_args(["verify", PACKAGE]).func, helper.cmd_verify)


class LocalRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.root = directory / "checkout"
        self.root.mkdir()
        self.remote = directory / "remote.git"
        self.command("git", "init", "--bare", str(self.remote))
        self.command("git", "init", "-b", "main")
        self.command("git", "config", "user.name", "Release Test")
        self.command("git", "config", "user.email", "release@example.test")
        (self.root / ".github/workflows").mkdir(parents=True)
        (self.root / ".github/workflows/publish.yml").write_text(
            "on:\n  push:\n    tags:\n      - 'desktop_drop-v[0-9]+.[0-9]+.[0-9]+*'\n"
        )
        self.pkg = self.root / "packages" / PACKAGE
        self.pkg.mkdir(parents=True)
        (self.pkg / "pubspec.yaml").write_text(f"name: {PACKAGE}\nversion: {VERSION}\n")
        (self.pkg / "CHANGELOG.md").write_text(NOTES + "\n## 0.1.0\n\n* Initial release.\n")
        self.command("git", "add", ".")
        self.command("git", "commit", "-m", "Prepare release")
        self.command("git", "remote", "add", "origin", str(self.remote))
        self.command("git", "push", "origin", "main")
        self.root_patch = patch.object(helper, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.github = patch.object(helper, "gh", side_effect=AssertionError("Unexpected external call"))
        self.gh = self.github.start()
        self.addCleanup(self.github.stop)

    def command(self, *args):
        return subprocess.run(args, cwd=self.root, text=True, capture_output=True, check=True).stdout

    def release(self):
        with redirect_stdout(io.StringIO()):
            return helper.cmd_release(argparse.Namespace(package=PACKAGE, draft=False, timeout=60))

    def test_release_reads_prepared_files_without_editing_them(self):
        before = {path: path.read_bytes() for path in self.pkg.iterdir()}
        target = self.command("git", "rev-parse", "HEAD").strip()
        def create(*args):
            self.assertEqual(args[:3], ("release", "create", TAG))
            self.assertEqual(args[args.index("--target") + 1], target)
            self.assertEqual(Path(args[args.index("--notes-file") + 1]).read_text(), NOTES)
            return RELEASE["url"]
        self.gh.side_effect = create
        with patch.object(helper, "verify_release", return_value={"verified": True}) as verify:
            self.assertEqual(self.release(), 0)
            verify.assert_called_once_with(PACKAGE, 60)
        self.assertEqual({path: path.read_bytes() for path in self.pkg.iterdir()}, before)
        self.assertEqual(self.command("git", "status", "--short"), "")

    def test_dirty_checkout_is_preserved(self):
        path = self.root / "unrelated.txt"
        path.write_text("Keep this work.\n")
        with self.assertRaises(helper.ReleaseError):
            self.release()
        self.assertEqual(path.read_text(), "Keep this work.\n")
        self.gh.assert_not_called()

    def test_refreshed_remote_main_prevents_stale_publication(self):
        old_head = self.command("git", "rev-parse", "HEAD").strip()
        self.command("git", "commit", "--allow-empty", "-m", "Remote change")
        self.command("git", "push", "origin", "main")
        # Restore only the temporary repository to simulate stale checkout and tracking refs.
        self.command("git", "checkout", "-B", "main", old_head)
        self.command("git", "update-ref", "refs/remotes/origin/main", old_head)
        with self.assertRaisesRegex(helper.ReleaseError, "refreshed origin/main"):
            self.release()
        self.gh.assert_not_called()

    def test_existing_remote_tag_prevents_release_creation(self):
        self.command("git", "tag", TAG)
        self.command("git", "push", "origin", TAG)
        with self.assertRaisesRegex(helper.ReleaseError, "already exists"):
            self.release()
        self.gh.assert_not_called()

    def test_pubspec_and_changelog_mismatch_prevents_publication(self):
        (self.pkg / "pubspec.yaml").write_text(f"name: {PACKAGE}\nversion: 0.1.2\n")
        self.command("git", "add", ".")
        self.command("git", "commit", "-m", "Mismatched version")
        self.command("git", "push", "origin", "main")
        with self.assertRaisesRegex(helper.ReleaseError, "changelog section for 0.1.2"):
            self.release()
        self.gh.assert_not_called()

    def test_unsupported_package_is_rejected(self):
        with self.assertRaisesRegex(helper.ReleaseError, "not enabled"):
            helper.package_dir("unlisted_package")


class PublishTests(unittest.TestCase):
    def test_published_release_uses_exact_commit_and_verifies(self):
        for draft in (False, True):
            with self.subTest(draft=draft), ExitStack() as stack:
                for name in ("ensure_on_main_branch", "ensure_clean_worktree", "refresh_remote", "ensure_synced_with_origin_main"):
                    stack.enter_context(patch.object(helper, name))
                stack.enter_context(patch.object(helper, "release_metadata", return_value=(VERSION, TAG, NOTES)))
                stack.enter_context(patch.object(helper, "remote_tag_target", return_value=None))
                stack.enter_context(patch.object(helper, "git", return_value=SHA))
                verify = stack.enter_context(patch.object(helper, "verify_release", return_value={"verified": True}))
                captured_notes = []
                def create(*args):
                    self.assertEqual(args[args.index("--target") + 1], SHA)
                    self.assertEqual("--draft" in args, draft)
                    captured_notes.append(Path(args[args.index("--notes-file") + 1]).read_text())
                    return RELEASE["url"]
                create_mock = stack.enter_context(patch.object(helper, "gh", side_effect=create))
                with redirect_stdout(io.StringIO()):
                    helper.cmd_release(argparse.Namespace(package=PACKAGE, draft=draft, timeout=60))
                create_mock.assert_called_once()
                self.assertEqual(captured_notes, [NOTES])
                self.assertEqual(verify.call_count, 0 if draft else 1)

    def test_existing_tag_cannot_be_recreated(self):
        with ExitStack() as stack:
            for name in ("ensure_on_main_branch", "ensure_clean_worktree", "refresh_remote", "ensure_synced_with_origin_main"):
                stack.enter_context(patch.object(helper, name))
            stack.enter_context(patch.object(helper, "release_metadata", return_value=(VERSION, TAG, NOTES)))
            stack.enter_context(patch.object(helper, "remote_tag_target", return_value=SHA))
            create = stack.enter_context(patch.object(helper, "gh"))
            with self.assertRaisesRegex(helper.ReleaseError, "already exists"):
                helper.cmd_release(argparse.Namespace(package=PACKAGE, draft=False, timeout=60))
            create.assert_not_called()

    def test_annotated_tag_resolves_to_commit(self):
        with patch.object(helper, "git", return_value=f"{'b' * 40}\trefs/tags/{TAG}\n{SHA}\trefs/tags/{TAG}^{{}}\n"):
            self.assertEqual(helper.remote_tag_target(TAG), SHA)


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(helper, "release_metadata", return_value=(VERSION, TAG, NOTES)))
        self.stack.enter_context(patch.object(helper, "git", return_value=SHA))
        self.stack.enter_context(patch.object(helper, "remote_tag_target", return_value=SHA))
        self.stack.enter_context(patch.object(helper.time, "sleep"))
        self.stack.enter_context(redirect_stderr(io.StringIO()))
        self.release = dict(RELEASE)
        self.run = dict(RUN)
        self.jobs = JOBS
        self.github = self.stack.enter_context(patch.object(helper, "gh", side_effect=self.response))
        self.pub = self.stack.enter_context(patch.object(helper, "pub_version_available", return_value=True))

    def response(self, *args):
        if args[:2] == ("release", "view"):
            return json.dumps(self.release)
        if args[:2] == ("run", "list"):
            self.assertIn(TAG, args)
            self.assertIn(SHA, args)
            self.assertIn("push", args)
            self.assertIn("publish.yml", args)
            return json.dumps([self.run])
        if args[:2] == ("run", "view"):
            return json.dumps(self.jobs)
        self.fail(f"Unexpected command: {args}")

    def test_success_requires_workflow_and_exact_pub_version(self):
        self.pub.side_effect = [False, True]
        result = helper.verify_release(PACKAGE, 60)
        self.assertTrue(result["verified"])
        self.assertEqual(result["workflow_url"], RUN["url"])
        self.assertEqual(self.pub.call_count, 2)

    def test_crlf_release_body_matches(self):
        self.release["body"] = NOTES.replace("\n", "\r\n")
        self.assertTrue(helper.verify_release(PACKAGE, 60)["verified"])

    def test_draft_or_mismatched_notes_cannot_succeed(self):
        for replacement in ({"isDraft": True}, {"body": "Wrong notes"}):
            self.release = dict(RELEASE, **replacement)
            with self.subTest(replacement=replacement), self.assertRaises(helper.ReleaseError):
                helper.verify_release(PACKAGE, 60)
        self.pub.assert_not_called()

    def test_wrong_remote_tag_cannot_succeed(self):
        with patch.object(helper, "remote_tag_target", return_value="wrong-sha"):
            with self.assertRaisesRegex(helper.ReleaseError, "points to"):
                helper.verify_release(PACKAGE, 60)
        self.pub.assert_not_called()

    def test_failed_workflow_cannot_succeed_even_if_version_exists(self):
        self.run["conclusion"] = "failure"
        with self.assertRaisesRegex(helper.ReleaseError, "publish failed"):
            helper.verify_release(PACKAGE, 60)
        self.pub.assert_not_called()

    def test_skipped_publish_step_cannot_succeed(self):
        self.jobs = {"jobs": [{"steps": [{"name": "Publish to pub.dev", "conclusion": "skipped"}]}]}
        with self.assertRaisesRegex(helper.ReleaseError, "publish step did not succeed"):
            helper.verify_release(PACKAGE, 60)
        self.pub.assert_not_called()

    def test_wrong_tag_or_sha_runs_are_ignored(self):
        for replacement in ({"headSha": "wrong-sha"}, {"headBranch": "other-tag"}):
            self.run = dict(RUN, **replacement)
            with self.subTest(replacement=replacement), patch.object(helper.time, "monotonic", side_effect=[0, 0, 61, 61]):
                with self.assertRaisesRegex(helper.ReleaseError, "timed out"):
                    helper.verify_release(PACKAGE, 60)
        self.pub.assert_not_called()

    def test_pending_workflow_is_waited_for(self):
        original = self.response
        calls = 0
        def response(*args):
            nonlocal calls
            if args[:2] == ("run", "list"):
                calls += 1
                if calls == 1:
                    return json.dumps([dict(RUN, status="in_progress", conclusion="")])
            return original(*args)
        self.github.side_effect = response
        self.assertTrue(helper.verify_release(PACKAGE, 60)["verified"])
        self.assertEqual(calls, 2)

    def test_pub_not_visible_times_out_without_republishing(self):
        self.pub.return_value = False
        with patch.object(helper.time, "monotonic", side_effect=[0, 0, 61, 61]):
            with self.assertRaisesRegex(helper.ReleaseError, "Resume with verify"):
                helper.verify_release(PACKAGE, 60)
        self.assertFalse(any(call.args[:2] == ("release", "create") for call in self.github.call_args_list))


class PubApiTests(unittest.TestCase):
    def test_exact_package_version_metadata(self):
        for name, version, expected in ((PACKAGE, VERSION, True), (PACKAGE, "0.1.2", False), ("other_package", VERSION, False)):
            data = {"version": VERSION, "pubspec": {"name": name, "version": version}}
            response = io.StringIO(json.dumps(data))
            with self.subTest(name=name, version=version), patch.object(helper, "urlopen", return_value=response) as request:
                self.assertEqual(helper.pub_version_available(PACKAGE, VERSION), expected)
                self.assertEqual(request.call_args.args[0], f"https://pub.dev/api/packages/{PACKAGE}/versions/{VERSION}")

    def test_missing_or_temporary_errors_are_retryable(self):
        for code in (404, 429, 503):
            with self.subTest(code=code), patch.object(helper, "urlopen", side_effect=HTTPError("url", code, "error", {}, None)):
                self.assertFalse(helper.pub_version_available(PACKAGE, VERSION))

    def test_forbidden_response_is_reported(self):
        with patch.object(helper, "urlopen", side_effect=HTTPError("url", 403, "error", {}, None)):
            with self.assertRaisesRegex(helper.ReleaseError, "HTTP 403"):
                helper.pub_version_available(PACKAGE, VERSION)


class WorkflowTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "Node.js is required to exercise github-script")
    def test_tag_name_and_version_guard(self):
        workflow = (helper.ROOT / ".github/workflows/publish.yml").read_text()
        source = re.search(r"          script: \|\n(.*?)\n      - name: Publish - dry run", workflow, re.DOTALL)
        self.assertIsNotNone(source)
        script = textwrap.dedent(source.group(1))
        cases = [
            (f"refs/tags/{TAG}", f"name: {PACKAGE}\nversion: {VERSION}\n", None, True),
            (f"refs/tags/{TAG}", f"name: {PACKAGE}\nversion: 0.1.0\n", None, False),
            (f"refs/tags/{TAG}", f"name: other_package\nversion: {VERSION}\n", None, False),
            (f"refs/tags/{TAG}-invalid", f"name: {PACKAGE}\nversion: {VERSION}\n", None, False),
            ("refs/heads/main", f"name: {PACKAGE}\nversion: {VERSION}\n", PACKAGE, True),
        ]
        runner = """
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const execute = new Function('context', 'require', input.script);
const context = {ref: input.ref, payload: {inputs: {package: input.package}}};
const mockRequire = () => ({readFileSync: () => input.pubspec});
try { execute(context, mockRequire); } catch (error) { process.exit(1); }
"""
        for ref, pubspec, package, succeeds in cases:
            with self.subTest(ref=ref, pubspec=pubspec):
                result = subprocess.run(
                    ["node", "-e", runner], text=True, capture_output=True,
                    input=json.dumps({"script": script, "ref": ref, "pubspec": pubspec, "package": package}),
                )
                self.assertEqual(result.returncode == 0, succeeds, result.stderr)


if __name__ == "__main__":
    unittest.main()
