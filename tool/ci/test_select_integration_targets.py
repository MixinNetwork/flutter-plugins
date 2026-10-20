"""Exercise PR selection against actual Git histories, without a hosted runner."""

import json
import itertools
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from select_integration_targets import (
    ROOT,
    base_manifest_targets,
    changed_files,
    load_targets,
    load_workspace,
    read_pubspec,
    select_targets,
)


class TargetSelectionTest(unittest.TestCase):
    def setUp(self):
        self.targets = load_targets(ROOT)
        self.workspace = load_workspace(ROOT)

    def test_related_and_unrelated_paths(self):
        native = [target for target in self.targets if target['package'] == 'desktop_webview_window']
        browser = [target for target in self.targets if target['package'] == 'desktop_drop']
        cases = {
            'packages/desktop_webview_window/windows/web_view.cc': native,
            'packages/desktop_webview_window/example/integration_test/new_test.dart': native,
            'packages/desktop_webview_window/tool/ci/setup_windows.ps1': native,
            'packages/desktop_drop/lib/desktop_drop.dart': browser,
            'packages/desktop_drop/test/browser/web_drop_test.dart': browser,
            'packages/desktop_webview_window_other/lib/test.dart': [],
            'README.md': [],
            'pubspec.yaml': [],
            'pubspec.lock': self.targets,
            'packages/desktop_drop/pubspec.yaml': browser,
            'packages/desktop_drop/example/pubspec.yaml': browser,
            '.github/integration-tests.json': [],
            '.github/workflows/integration-tests.yml': self.targets,
            '.github/workflows/ci.yml': self.targets,
            'tool/ci/select_integration_targets.py': self.targets,
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(select_targets(self.targets, [path], self.targets, self.workspace), expected)

    def test_read_pubspec(self):
        pubspec = read_pubspec('''name: 'sample' # comment
environment:
  sdk: ^3.12.0
workspace:
  - packages/first
  - "packages/first/example/"  # trailing slash
dependencies:
  flutter:
    sdk: flutter

  # commented_out: ^1.0.0
  local:
    path: ../local
  hosted: ^1.0.0
dev_dependencies:
    lints: ^6.0.0
    git_package:
      git:
        url: https://example.invalid/repo.git#main
dependency_overrides:
  overridden: ^1.0.0
flutter:
  plugin:
    platforms:
      linux:
        pluginClass: SamplePlugin
''')
        self.assertEqual(pubspec, {
            'name': 'sample',
            'workspace': ['packages/first', 'packages/first/example'],
            'dependencies': {'flutter', 'local', 'hosted', 'lints', 'git_package'},
        })

    def test_real_workspace_dependencies(self):
        self.assertEqual(self.workspace['packages/desktop_drop']['name'], 'desktop_drop')
        self.assertIn('desktop_drop', self.workspace['packages/desktop_drop/example']['dependencies'])
        targets = [
            {'package': 'mixin_logger', 'platform': 'linux'},
            {'package': 'desktop_multi_window', 'platform': 'linux'},
            {'package': 'win_toast', 'platform': 'windows'},
            {'package': 'desktop_drop', 'platform': 'web'},
        ]
        # Both examples depend on mixin_logger.
        self.assertEqual(
            select_targets(targets, ['packages/mixin_logger/pubspec.yaml'], workspace=self.workspace),
            targets[:3],
        )

    def test_package_pubspec_selects_transitive_dependents(self):
        workspace = {
            'packages/base': {'name': 'base', 'workspace': [], 'dependencies': {'flutter'}},
            'packages/base/example': {'name': 'base_example', 'workspace': [], 'dependencies': {'base'}},
            'packages/middle': {'name': 'middle', 'workspace': [], 'dependencies': {'base'}},
            'packages/top': {'name': 'top', 'workspace': [], 'dependencies': {'middle'}},
            'packages/other': {'name': 'other', 'workspace': [], 'dependencies': {'flutter'}},
        }
        targets = [{'package': package, 'platform': 'linux'} for package in ['base', 'middle', 'top', 'other']]
        cases = {
            'packages/base/pubspec.yaml': targets[:3],
            'packages/base/example/pubspec.yaml': targets[:1],
            'packages/middle/pubspec.yaml': targets[1:3],
            'packages/top/pubspec.yaml': targets[2:3],
            'packages/base/lib/base.dart': targets[:1],
            'packages/removed/pubspec.yaml': [],
            'pubspec.yaml': [],
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                self.assertEqual(select_targets(targets, [path], workspace=workspace), expected)

    def test_manifest_change_selects_added_and_edited_targets(self):
        unchanged = {'package': 'unchanged', 'platform': 'linux', 'runner': 'ubuntu-latest'}
        edited = {'package': 'edited', 'platform': 'macos', 'runner': 'macos-latest'}
        removed = {'package': 'removed', 'platform': 'linux', 'runner': 'ubuntu-latest'}
        added = {'package': 'added', 'platform': 'windows', 'runner': 'windows-latest'}
        base = [unchanged, edited, removed]
        head = [unchanged, {**edited, 'runner': 'macos-15'}, added]
        manifest = '.github/integration-tests.json'
        self.assertEqual(select_targets(head, [manifest], base), head[1:])
        self.assertEqual(select_targets(head, [manifest], head), [])
        self.assertEqual(select_targets(head, [manifest], []), head)
        # Unrelated targets in the base manifest do not matter when it is unchanged.
        self.assertEqual(select_targets(head, ['packages/unchanged/lib/a.dart'], []), head[:1])

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

    def test_browser_suite_registration(self):
        target = {
            'package': 'browser_plugin',
            'platform': 'web',
            'runner': 'ubuntu-latest',
            'test': 'test/browser',
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.github').mkdir()
            manifest = root / '.github/integration-tests.json'
            manifest.write_text(json.dumps({'targets': [target]}))
            suite = root / 'packages/browser_plugin/test/browser'
            suite.mkdir(parents=True)
            with self.assertRaises(ValueError):
                load_targets(root)
            (suite / 'drop_test.dart').write_text('fixture')
            self.assertEqual(load_targets(root), [target])
            for override in [
                {'test': '../escape'},
                {'test': 'test/other'},
                {'runner': 'windows-latest'},
                {'driver': 'test_driver/integration_test.dart'},
                {'setup': 'setup.ps1'},
            ]:
                with self.subTest(override=override):
                    manifest.write_text(json.dumps({'targets': [{**target, **override}]}))
                    with self.assertRaises(ValueError):
                        load_targets(root)

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
            head = commit('packages/unrelated_plugin/source.dart')
            paths = changed_files(root, base, head)
            self.assertEqual(paths, ['packages/unrelated_plugin/source.dart'])
            self.assertEqual(select_targets(self.targets, paths), [])
            # Moving a file out still affects the original package.
            git('mv', 'packages/desktop_webview_window/source.dart', 'moved.dart')
            git('commit', '-m', 'move fixture')
            paths = changed_files(root, base, 'HEAD')
            self.assertIn('packages/desktop_webview_window/source.dart', paths)
            self.assertEqual(
                select_targets(self.targets, paths),
                [target for target in self.targets if target['package'] == 'desktop_webview_window'],
            )
            with self.assertRaises(subprocess.CalledProcessError):
                changed_files(root, 'missing-base', 'HEAD')

    def test_base_manifest_uses_merge_base_and_handles_missing_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL).decode().strip()

            def commit(path, content):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(content)
                git('add', '.')
                git('commit', '-m', 'test fixture')
                return git('rev-parse', 'HEAD')

            def manifest(*packages):
                return json.dumps({'targets': [{'package': package, 'platform': 'linux'} for package in packages]})

            git('init', '-b', 'main')
            git('config', 'user.name', 'CI Test')
            git('config', 'user.email', 'ci@example.invalid')
            path = '.github/integration-tests.json'
            original = commit('README.md', 'fixture')
            head = commit(path, manifest('first'))
            self.assertEqual(base_manifest_targets(root, original, head), [])
            fork = commit(path, manifest('first', 'second'))
            git('checkout', '-b', 'feature')
            head = commit(path, manifest('first', 'second', 'third'))
            git('checkout', 'main')
            # The base branch edits the manifest after the PR forks; compare against the fork point.
            base = commit(path, manifest('first', 'second', 'base_only'))
            base_targets = base_manifest_targets(root, base, head)
            self.assertEqual(base_targets, json.loads(manifest('first', 'second'))['targets'])
            head_targets = json.loads(manifest('first', 'second', 'third'))['targets']
            self.assertEqual(select_targets(head_targets, [path], base_targets), head_targets[2:])
            self.assertEqual(fork, git('merge-base', base, head))

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

    def test_package_rejects_additional_integration_entry_points(self):
        target = next(target for target in self.targets if target['platform'] == 'windows' and 'setup' in target)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.github').mkdir()
            package = root / 'packages' / target['package']
            entrypoint = package / 'example' / target['test']
            entrypoint.parent.mkdir(parents=True)
            entrypoint.write_text('fixture')
            setup = package / target['setup']
            setup.parent.mkdir(parents=True)
            setup.write_text('fixture')
            manifest = root / '.github/integration-tests.json'
            manifest.write_text(json.dumps({'targets': [target]}))
            self.assertEqual(load_targets(root), [target])
            extra = entrypoint.parent / 'src' / 'extra_test.dart'
            extra.parent.mkdir()
            extra.write_text('fixture')
            with self.assertRaisesRegex(ValueError, 'Keep one integration test entry point'):
                load_targets(root)
            manifest.write_text(json.dumps({'targets': [{**target, 'test': 'integration_test/other_test.dart'}]}))
            with self.assertRaisesRegex(ValueError, 'must use integration_test/app_test.dart'):
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
