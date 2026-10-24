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
name, build = {'windows': ('0.6.0', '25'), 'macos': ('0.2.0', '3')}[args.platform]
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
subprocess.run(command, cwd=ROOT / 'desktop', check=True)
