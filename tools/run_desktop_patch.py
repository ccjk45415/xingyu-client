"""Validate or publish an explicitly authorized patch against an existing base.

Uses the pinned official CLI installed by the workflow. No bypass of native or
asset differences. Never creates a new release base or modifies update manifests.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('platform', choices=['windows', 'macos'])
parser.add_argument('--dry-run', action='store_true')
args = parser.parse_args()
name, build = {'windows': ('0.7.1', '28'), 'macos': ('0.3.1', '6')}[args.platform]
if sys.platform == 'win32':
    cli = Path(os.environ['RUNNER_TEMP']) / 'shorebird/bin/shorebird.ps1'
    command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(cli)]
else:
    command = [shutil.which('shorebird') or 'shorebird']
command += ['patch', args.platform, f'--release-version={name}+{build}',
            f'--build-name={name}', f'--build-number={build}',
            '--dart-define=XINGYU_PATCH_TRACK=staging',
            '--dart-define=XINGYU_REQUIRE_CODE_PUSH=true', '--track=staging']
if args.dry_run:
    command.append('--dry-run')
result = subprocess.run(command, cwd=ROOT / 'desktop', stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, encoding='utf-8', errors='replace')
if hasattr(sys.stdout, 'reconfigure'): sys.stdout.reconfigure(encoding='utf-8')
print(result.stdout, end='')
expected = 'No issues detected.' if args.dry_run else 'Published Patch '
if result.returncode or expected not in result.stdout:
    raise SystemExit('Shorebird did not confirm the requested patch operation; CLI exit status alone is insufficient.')
