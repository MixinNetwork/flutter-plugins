"""Validate registered targets and select jobs from a Git diff or all targets."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]


def load_targets(root):
    targets = json.loads((root / '.github/integration-tests.json').read_text())['targets']
    if not isinstance(targets, list) or not targets:
        raise ValueError('Register at least one integration target')
    seen = set()
    for target in targets:
        if set(target) - {'package', 'platform', 'runner', 'test', 'setup', 'driver'}:
            raise ValueError(f'Unknown target fields: {target}')
        package = target['package']
        platform = target['platform']
        if not re.fullmatch(r'[a-z][a-z0-9_]*', package):
            raise ValueError(f'Invalid package: {package}')
        if platform not in {'windows', 'macos', 'linux', 'web'}:
            raise ValueError(f'Invalid platform: {platform}')
        runner_prefix = {'windows': 'windows-', 'macos': 'macos-', 'linux': 'ubuntu-', 'web': 'ubuntu-'}[platform]
        if not re.fullmatch(runner_prefix + r'[a-zA-Z0-9.-]+', target['runner']):
            raise ValueError(f'Invalid runner: {target["runner"]}')
        key = (package, platform)
        if key in seen:
            raise ValueError(f'Duplicate target: {key}')
        seen.add(key)
        package_root = root / 'packages' / package
        entrypoint = target['test']
        if platform == 'web':
            if entrypoint != 'test/browser' or 'driver' in target or 'setup' in target:
                raise ValueError('Browser targets must use test/browser without a driver or setup script')
            if not any((package_root / entrypoint).rglob('*_test.dart')):
                raise ValueError(f'Missing browser tests: {package_root / entrypoint}')
            continue
        if entrypoint != 'integration_test/app_test.dart':
            raise ValueError('Each package must use integration_test/app_test.dart')
        actual_entries = sorted((package_root / 'example' / 'integration_test').rglob('*_test.dart'))
        if actual_entries != [package_root / 'example' / entrypoint]:
            raise ValueError(f'Keep one integration test entry point for {package}: {actual_entries}')
        for field, base in [('test', package_root / 'example'), ('setup', package_root), ('driver', package_root / 'example')]:
            if field in {'setup', 'driver'} and field not in target:
                continue
            path = target[field]
            if not re.fullmatch(r'[a-zA-Z0-9_./-]+', path) or Path(path).is_absolute() or '..' in Path(path).parts:
                raise ValueError(f'Invalid {field} path: {path}')
            if not (base / path).is_file():
                raise ValueError(f'Missing {field}: {base / path}')
        if not target['test'].startswith('integration_test/') or not target['test'].endswith('_test.dart'):
            raise ValueError('Test must be an integration_test/*_test.dart entry point')
        if 'driver' in target and not target['driver'].endswith('.dart'):
            raise ValueError('Driver must be a Dart entry point')
        if 'setup' in target and not target['setup'].endswith('.ps1'):
            raise ValueError('Setup scripts must use PowerShell (.ps1)')
    return targets


def diffable_base(root, base):
    """Return base when it names a local commit, or None when a push diff cannot be computed.

    A new branch reports an all-zero base, and a force push can report a base
    that is no longer in the history.
    """
    exists = subprocess.run(['git', 'cat-file', '-e', f'{base}^{{commit}}'], cwd=root, capture_output=True)
    return base if exists.returncode == 0 else None


def changed_files(root, base, head):
    # Include both sides of moves so moving a file out of a package still tests it.
    output = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', f'{base}...{head}', '--'],
        cwd=root,
    )
    return output.decode().split('\0')[:-1]


def read_pubspec(text):
    """Read the package name, workspace members, and direct dependency names from pubspec text.

    Only the top-level keys this selector needs are parsed, line by line, because
    the standard library has no YAML parser.
    """
    pubspec = {'name': None, 'workspace': [], 'dependencies': set()}
    section = child_indent = None
    for line in text.splitlines():
        content = line.split('#', 1)[0].rstrip()
        if not content.strip():
            continue
        indent = len(content) - len(content.lstrip())
        if indent == 0:
            section, _, value = content.partition(':')
            child_indent = None
            if section == 'name':
                pubspec['name'] = value.strip().strip('\'"')
            continue
        if child_indent is None:
            child_indent = indent
        if section == 'workspace' and content.lstrip().startswith('- '):
            pubspec['workspace'].append(content.lstrip()[2:].strip().strip('\'"').rstrip('/'))
        elif section in {'dependencies', 'dev_dependencies'} and indent == child_indent:
            match = re.fullmatch(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*:.*', content)
            if match:
                pubspec['dependencies'].add(match.group(1))
    return pubspec


def load_workspace(root):
    """Map each workspace member directory to its parsed pubspec."""
    members = read_pubspec((root / 'pubspec.yaml').read_text())['workspace']
    return {member: read_pubspec((root / member / 'pubspec.yaml').read_text()) for member in members}


def base_manifest_targets(root, base, head):
    """Return the registered targets at the PR merge base, or none when the manifest did not exist."""
    merge_base = subprocess.check_output(['git', 'merge-base', base, head], cwd=root).decode().strip()
    revision = f'{merge_base}:.github/integration-tests.json'
    if subprocess.run(['git', 'cat-file', '-e', revision], cwd=root, capture_output=True).returncode:
        return []
    return json.loads(subprocess.check_output(['git', 'show', revision], cwd=root))['targets']


def select_targets(targets, paths, base_targets=(), workspace=None):
    if paths is None:
        return targets
    # Lockfile and CI changes can affect every job.
    if any(path == 'pubspec.lock' or path.startswith(('.github/workflows/', 'tool/ci/')) for path in paths):
        return targets
    workspace = workspace or {}
    packages = {path.split('/')[1] for path in paths if path.startswith('packages/') and path.count('/') > 1}
    # A member pubspec change also affects workspace members that depend on it, directly or transitively.
    names = {
        workspace[path.removesuffix('/pubspec.yaml')]['name']
        for path in paths
        if path.endswith('/pubspec.yaml') and path.removesuffix('/pubspec.yaml') in workspace
    }
    while dependents := {
        pubspec['name'] for pubspec in workspace.values() if pubspec['dependencies'] & names
    } - names:
        names |= dependents
    packages |= {
        member.split('/')[1]
        for member, pubspec in workspace.items()
        if member.startswith('packages/') and pubspec['name'] in names
    }
    # A manifest change affects only added or edited targets; removed targets need no job.
    manifest_changed = '.github/integration-tests.json' in paths
    return [target for target in targets if target['package'] in packages or (
        manifest_changed and target not in base_targets
    )]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', help='PR base or pushed-before SHA; omit to select all targets')
    parser.add_argument('--head', default='HEAD', help='PR head or pushed SHA')
    parser.add_argument('--output', type=Path, help='GitHub Actions output file')
    args = parser.parse_args()
    targets = load_targets(ROOT)
    base = args.base and diffable_base(ROOT, args.base)
    if args.base and not base:
        print(f'Cannot diff from {args.base}; selecting all targets.', file=sys.stderr)
    paths = changed_files(ROOT, base, args.head) if base else None
    base_targets = base_manifest_targets(ROOT, base, args.head) if base else []
    selected = select_targets(targets, paths, base_targets, load_workspace(ROOT))
    matrix = json.dumps({'include': selected}, separators=(',', ':'))
    print(matrix)
    if args.output:
        with args.output.open('a') as output:
            output.write(f'matrix={matrix}\n')
            output.write(f'has_targets={str(bool(selected)).lower()}\n')


if __name__ == '__main__':
    main()
