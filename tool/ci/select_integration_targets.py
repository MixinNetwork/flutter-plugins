"""Validate registered targets and select jobs from a Git diff or all targets."""

import argparse
import json
from pathlib import Path
import re
import subprocess


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
        if platform not in {'windows', 'macos', 'linux'}:
            raise ValueError(f'Invalid platform: {platform}')
        runner_prefix = {'windows': 'windows-', 'macos': 'macos-', 'linux': 'ubuntu-'}[platform]
        if not re.fullmatch(runner_prefix + r'[a-zA-Z0-9.-]+', target['runner']):
            raise ValueError(f'Invalid runner: {target["runner"]}')
        key = (package, platform)
        if key in seen:
            raise ValueError(f'Duplicate target: {key}')
        seen.add(key)
        package_root = root / 'packages' / package
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


def changed_files(root, base, head):
    # Include both sides of moves so moving a file out of a package still tests it.
    output = subprocess.check_output(
        ['git', 'diff', '--name-only', '--no-renames', '-z', f'{base}...{head}', '--'],
        cwd=root,
    )
    return output.decode().split('\0')[:-1]


def select_targets(targets, paths):
    if paths is None:
        return targets
    shared = any(
        path in {'pubspec.yaml', 'pubspec.lock', '.github/integration-tests.json'}
        or path.startswith(('.github/workflows/', 'tool/ci/'))
        or (path.startswith('packages/') and path.endswith('/pubspec.yaml'))
        for path in paths
    )
    return [target for target in targets if shared or any(
        path.startswith(f'packages/{target["package"]}/') for path in paths
    )]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', help='PR base SHA; omit to select all targets')
    parser.add_argument('--head', default='HEAD', help='PR head SHA')
    parser.add_argument('--output', type=Path, help='GitHub Actions output file')
    args = parser.parse_args()
    targets = load_targets(ROOT)
    paths = changed_files(ROOT, args.base, args.head) if args.base else None
    selected = select_targets(targets, paths)
    matrix = json.dumps({'include': selected}, separators=(',', ':'))
    print(matrix)
    if args.output:
        with args.output.open('a') as output:
            output.write(f'matrix={matrix}\n')
            output.write(f'has_targets={str(bool(selected)).lower()}\n')


if __name__ == '__main__':
    main()
