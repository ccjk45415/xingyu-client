"""Validate/publish an authorized Dart patch against the current Android base.

Keeps original release flags and signing identity; never publishes an installer.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

from build_flutter_android import ROOT, TOOL

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dry-run', action='store_true')
parser.add_argument('--release-version', choices=['0.13.1+37', '0.13.2+38'], default='0.13.2+38')
args = parser.parse_args()
sdk = TOOL / 'xingyu-shorebird/bin/cache/flutter/7dbbfb1fc6d89d11974ff5a770610d0937d27206'
os.environ['FLUTTER_ROOT'] = str(sdk)
# prepare() uses the module-level Flutter path when writing local.properties.
import build_flutter_android
build_flutter_android.FLUTTER = sdk
legacy = args.release_version == '0.13.1+37'
build_flutter_android.STAGE = TOOL / ('xingyu-android-patch37' if legacy else 'xingyu-android-build')
STAGE = build_flutter_android.STAGE
env = build_flutter_android.prepare()
if legacy:
    # Native scheduling improvements require the new installer. Keep the old
    # release's native inputs byte-for-byte; the official CLI still validates it.
    checkout = ROOT if (ROOT / '.git').exists() else ROOT / '.toolchain/macos-build'
    baseline = '0a46c0c'
    paths = subprocess.check_output(['git', '-C', str(checkout), 'ls-tree', '-r', '--name-only', baseline, '--', 'desktop/android'], text=True).splitlines()
    if not paths:
        raise SystemExit('Installed Android native baseline is unavailable')
    for name in paths:
        target = STAGE / Path(name).relative_to('desktop')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(subprocess.check_output(['git', '-C', str(checkout), 'show', f'{baseline}:{name}']))
    (STAGE / 'android/app/src/main/java/moe/cangku/xingyu_desktop/CheckinPolicy.java').unlink(missing_ok=True)
name, build = args.release_version.split('+')
env.update(APPDATA=str(ROOT / '.toolchain/shorebird-auth'), CI='true',
           GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.longpaths',
           GIT_CONFIG_VALUE_0='true')
command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
           str(TOOL / 'xingyu-shorebird/bin/shorebird.ps1'), 'patch', 'android',
           f'--release-version={args.release_version}', f'--build-name={name}', f'--build-number={build}',
           '--dart-define=XINGYU_ANDROID_TEST=true',
           '--dart-define=XINGYU_PATCH_TRACK=staging', '--track=staging']
if not legacy:
    command += [f'--dart-define=XINGYU_ANDROID_VERSION={name}', f'--dart-define=XINGYU_ANDROID_BUILD={build}']
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
