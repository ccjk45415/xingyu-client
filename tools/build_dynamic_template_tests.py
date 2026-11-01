"""Build local-only installers; never register releases, upload or stage feeds."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/2026年10月24日/20261101-动态模板测试'
PINNED = Path('C:/codex-tools/xingyu-shorebird/bin/cache/flutter/01aea2ee0626578b6b30ebbb2605f195833464fa')


def run(command, *, cwd=ROOT, env=None):
    subprocess.run([str(p) for p in command], cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['windows', 'android'], required=True)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(FLUTTER_ROOT=str(PINNED), CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
    if not (PINNED / 'bin/cache/dart-sdk/bin/dart.exe').is_file():
        raise SystemExit('Pinned Flutter SDK is missing')
    if args.platform == 'windows':
        version, build = '0.7.5-template-test', 32
        run([sys.executable, ROOT / 'tools/build_desktop.py', f'--build-name={version}', f'--build-number={build}',
             f'--dart-define=XINGYU_WINDOWS_VERSION={version}', f'--dart-define=XINGYU_WINDOWS_BUILD={build}',
             '--dart-define=XINGYU_PATCH_TRACK=local-template-test'], env=env)
        bundle = ROOT / 'desktop/build/windows/native-x64/runner'
        run([sys.executable, ROOT / 'tools/prepare_desktop_release.py', '--test-only', f'--version={version}',
             f'--build={build}', '--bundle', bundle], env=env)
        source = ROOT / f'output/Xingyu-Windows-{version}-x64.zip'
    else:
        version, build = '0.13.6-template-test', 42
        # The existing builder preserves the original package ID and signer,
        # using ASCII staging paths for NDK/Gradle and native asset hooks.
        os.environ['FLUTTER_ROOT'] = str(PINNED)
        from build_flutter_android import prepare, STAGE
        android_env = prepare()
        android_env['FLUTTER_ROOT'] = str(PINNED)
        dart = PINNED / 'bin/cache/dart-sdk/bin/dart.exe'
        snapshot = PINNED / 'bin/cache/flutter_tools.snapshot'
        run([dart, snapshot, 'pub', 'get', '--offline'], cwd=STAGE, env=android_env)
        run([dart, snapshot, 'build', 'apk', '--release', '--target-platform=android-arm64',
             f'--build-name={version}', f'--build-number={build}', '--dart-define=XINGYU_ANDROID_TEST=true',
             f'--dart-define=XINGYU_ANDROID_VERSION={version}', f'--dart-define=XINGYU_ANDROID_BUILD={build}',
             '--dart-define=XINGYU_PATCH_TRACK=local-template-test'], cwd=STAGE, env=android_env)
        source = STAGE / 'build/app/outputs/flutter-apk/app-release.apk'
    name = f'Xingyu-Windows-{version}-x64.zip' if args.platform == 'windows' else f'Cangku-Xingyu-{version}-arm64.apk'
    target = OUT / name
    shutil.copy2(source, target)
    report = {'platform': args.platform, 'version': version, 'build': build, 'artifact': name,
              'bytes': target.stat().st_size, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'uploaded': False, 'update_feeds_changed': False, 'patch_track': 'local-template-test'}
    (OUT / f'{args.platform}-build.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
