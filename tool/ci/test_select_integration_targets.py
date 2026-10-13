"""Exercise PR selection against actual Git histories, without a hosted runner."""

import json
import itertools
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from select_integration_targets import ROOT, changed_files, load_targets, select_targets


class TargetSelectionTest(unittest.TestCase):
    def setUp(self):
        self.targets = load_targets(ROOT)

    def test_related_and_unrelated_paths(self):
        cases = {
            'packages/desktop_webview_window/windows/web_view.cc': True,
            'packages/desktop_webview_window/example/integration_test/new_test.dart': True,
            'packages/desktop_webview_window/tool/ci/setup_windows.ps1': True,
            'packages/desktop_drop/lib/desktop_drop.dart': False,
            'packages/desktop_webview_window_other/lib/test.dart': False,
            'README.md': False,
            'pubspec.yaml': True,
            'pubspec.lock': True,
            'packages/desktop_drop/pubspec.yaml': True,
            '.github/integration-tests.json': True,
            '.github/workflows/integration-tests.yml': True,
            'tool/ci/select_integration_targets.py': True,
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(bool(select_targets(self.targets, [path])), expected)

    def test_all_and_empty(self):
        self.assertEqual(select_targets(self.targets, None), self.targets)
        self.assertEqual(select_targets(self.targets, []), [])

    def test_multiple_packages_and_platforms(self):
        targets = [
            {'package': 'first', 'platform': 'windows'},
            {'package': 'first', 'platform': 'macos'},
            {'package': 'second', 'platform': 'linux'},
        ]
        self.assertEqual(select_targets(targets, ['packages/first/lib/a.dart']), targets[:2])
        self.assertEqual(select_targets(targets, ['pubspec.lock']), targets)

    def test_git_diff_uses_pr_merge_base_and_includes_deleted_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()

            def commit(path):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('fixture')
                git('add', '.')
                git('commit', '-m', 'test fixture')
                return git('rev-parse', 'HEAD')

            git('init', '-b', 'main')
            git('config', 'user.name', 'CI Test')
            git('config', 'user.email', 'ci@example.invalid')
            original = commit('packages/desktop_webview_window/source.dart')
            # The base branch advances with a relevant change after the PR forks.
            base = commit('packages/desktop_webview_window/base_only.dart')
            git('checkout', '-b', 'unrelated', original)
            head = commit('packages/desktop_drop/source.dart')
            paths = changed_files(root, base, head)
            self.assertEqual(paths, ['packages/desktop_drop/source.dart'])
            self.assertEqual(select_targets(self.targets, paths), [])
            # Moving a file out still affects the original package.
            git('mv', 'packages/desktop_webview_window/source.dart', 'moved.dart')
            git('commit', '-m', 'move fixture')
            paths = changed_files(root, base, 'HEAD')
            self.assertIn('packages/desktop_webview_window/source.dart', paths)
            self.assertEqual(select_targets(self.targets, paths), self.targets)
            with self.assertRaises(subprocess.CalledProcessError):
                changed_files(root, 'missing-base', 'HEAD')

    def test_invalid_manifest_fails_instead_of_skipping(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.github').mkdir()
            manifest = root / '.github/integration-tests.json'
            for targets in [[], self.targets, [{**self.targets[0], 'package': '../escape'}]]:
                with self.subTest(targets=targets):
                    manifest.write_text(json.dumps({'targets': targets}))
                    with self.assertRaises(ValueError):
                        load_targets(root)

    def test_driver_manifest_and_existing_target(self):
        macos = next(target for target in self.targets if target['platform'] == 'macos')
        windows = next(target for target in self.targets if target['platform'] == 'windows')
        self.assertEqual(macos['driver'], 'test_driver/integration_test.dart')
        self.assertNotIn('driver', windows)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.github').mkdir()
            example = root / 'packages' / macos['package'] / 'example'
            test = example / macos['test']
            test.parent.mkdir(parents=True)
            test.write_text('fixture')
            driver = example / macos['driver']
            driver.parent.mkdir(parents=True)
            driver.write_text('fixture')
            manifest = root / '.github/integration-tests.json'
            manifest.write_text(json.dumps({'targets': [macos]}))
            self.assertEqual(load_targets(root), [macos])
            invalid = example / 'test_driver/not_dart.txt'
            invalid.write_text('fixture')
            for path in ['../escape.dart', 'test_driver/missing.dart', 'test_driver/not_dart.txt']:
                with self.subTest(driver=path):
                    manifest.write_text(json.dumps({'targets': [{**macos, 'driver': path}]}))
                    with self.assertRaises(ValueError):
                        load_targets(root)

    def test_workflow_result_gate(self):
        workflow = (ROOT / '.github/workflows/integration-tests.yml').read_text()
        # Execute the actual gate, including its failure and unexpected-skip paths.
        script = workflow.split('      - name: Check results\n', 1)[1].split('        run: |\n', 1)[1]
        script = '\n'.join(line[10:] for line in script.splitlines())
        results = ['success', 'failure', 'cancelled', 'skipped']
        for selection, targets, integration in itertools.product(results, ['true', 'false', ''], results):
            with self.subTest(selection=selection, targets=targets, integration=integration):
                expected = selection == 'success' and (
                    (targets == 'true' and integration == 'success')
                    or (targets == 'false' and integration == 'skipped')
                )
                result = subprocess.run(
                    ['bash', '-e', '-c', script],
                    env={**os.environ, 'SELECTION': selection, 'HAS_TARGETS': targets, 'INTEGRATION': integration},
                    capture_output=True,
                )
                self.assertEqual(result.returncode == 0, expected)


if __name__ == '__main__':
    unittest.main()
