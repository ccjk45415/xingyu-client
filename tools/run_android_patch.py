"""Validate/publish an authorized Dart patch against the current Android base.

Keeps original release flags and signing identity; never publishes an installer.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

from build_flutter_android import ROOT, STAGE, TOOL, prepare

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dry-run', action='store_true')
args = parser.parse_args()
sdk = TOOL / 'xingyu-shorebird/bin/cache/flutter/7dbbfb1fc6d89d11974ff5a770610d0937d27206'
os.environ['FLUTTER_ROOT'] = str(sdk)
# prepare() uses the module-level Flutter path when writing local.properties.
import build_flutter_android
build_flutter_android.FLUTTER = sdk
env = prepare()
env.update(APPDATA=str(ROOT / '.toolchain/shorebird-auth'), CI='true',
           GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.longpaths',
           GIT_CONFIG_VALUE_0='true')
command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
           str(TOOL / 'xingyu-shorebird/bin/shorebird.ps1'), 'patch', 'android',
           '--release-version=0.13.1+37', '--build-name=0.13.1', '--build-number=37',
           '--dart-define=XINGYU_ANDROID_TEST=true',
           '--dart-define=XINGYU_PATCH_TRACK=staging', '--track=staging']
if args.dry_run:
    command.append('--dry-run')
command += ['--', '--target-platform=android-arm64']
result = subprocess.run(command, cwd=STAGE, env=env, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, encoding='utf-8', errors='replace')
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')
print(result.stdout, end='')
expected = 'No issues detected.' if args.dry_run else 'Published Patch '
if result.returncode or expected not in result.stdout:
    raise SystemExit('Shorebird did not confirm this patch operation.')
