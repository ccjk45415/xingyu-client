"""Build the shared Flutter Android app locally; never stages/deploys updates.

Use an ASCII staging directory because Windows CMake/Ninja's native plugin
builds cannot reliably round-trip this workspace's Unicode path.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TOOL = Path(os.environ.get('XINGYU_TOOL_ROOT', 'C:/codex-tools'))
SDK = TOOL / 'xingyu-android-sdk'
CACHE = TOOL / 'xingyu-pub-cache'
STAGE = TOOL / 'xingyu-android-build'
FLUTTER = Path(os.environ.get('FLUTTER_ROOT', TOOL / 'flutter'))

def linked_copy(source, target):
    source, target = Path(source), Path(target)
    if target.exists():
        return str(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)
    return str(target)

def prepare():
    STAGE.mkdir(parents=True, exist_ok=True)
    sdk_source = ROOT / '.toolchain/android-sdk'
    shutil.copytree(sdk_source, SDK, dirs_exist_ok=True, copy_function=linked_copy,
                    ignore=shutil.ignore_patterns('.temp', '.downloadIntermediates'))
    pub = Path(os.environ.get('LOCALAPPDATA', '')) / 'Pub/Cache'
    for folder in ['hosted', 'hosted-hashes']:
        if (pub / folder).exists():
            shutil.copytree(pub / folder, CACHE / folder, dirs_exist_ok=True, copy_function=linked_copy)
    source = ROOT / 'desktop'
    for name in ['pubspec.yaml', 'pubspec.lock', '.metadata', 'analysis_options.yaml', 'shorebird.yaml']:
        if (source / name).is_file(): shutil.copy2(source / name, STAGE / name)
    for name in ['lib', 'assets', 'android', 'integration_test']:
        shutil.copytree(source / name, STAGE / name, dirs_exist_ok=True,
            ignore=shutil.ignore_patterns('build', '.gradle', '.cxx', 'local.properties', '*.iml'))
    # Never synthesize a new signing identity.
    original_key = ROOT / '.toolchain/keys/debug.keystore'
    if not original_key.is_file(): raise SystemExit('Original test signing key is missing')
    key = TOOL / 'xingyu-test-keys/debug.keystore'
    linked_copy(original_key, key)
    if key.read_bytes() != original_key.read_bytes(): raise SystemExit('Test signing identity differs')
    props = f'sdk.dir={SDK.as_posix()}\nflutter.sdk={FLUTTER.as_posix()}\n'
    (STAGE / 'android/local.properties').write_text(props, encoding='utf-8')
    env = os.environ.copy()
    env.update(ANDROID_HOME=str(SDK), ANDROID_SDK_ROOT=str(SDK),
        JAVA_HOME=os.environ.get('JAVA_HOME', 'C:/Program Files/Java/jdk-17'),
        PUB_CACHE=str(CACHE), GRADLE_USER_HOME=str(TOOL / 'gradle-cache'),
        FLUTTER_SUPPRESS_ANALYTICS='true', CI='true', XINGYU_TEST_KEYSTORE=str(key))
    return env

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device-test', help='Run isolated, synthetic integration tests on this ADB device')
    parser.add_argument('--shorebird-test', action='store_true', help='Build/register a private Shorebird test base, never publish an installer')
    parser.add_argument('--version', choices=['0.13.1', '0.13.2', '0.13.3'], default='0.13.2')
    parser.add_argument('--patch-track', default='staging')
    args = parser.parse_args()
    version, build = args.version, {'0.13.1':'37','0.13.2':'38','0.13.3':'39'}[args.version]
    version_flags = [f'--dart-define=XINGYU_ANDROID_VERSION={version}', f'--dart-define=XINGYU_ANDROID_BUILD={build}'] if build != '37' else []
    env = prepare()
    command = [str(FLUTTER / 'bin/cache/dart-sdk/bin/dart.exe'), str(FLUTTER / 'bin/cache/flutter_tools.snapshot')]
    def run(arguments):
        print('FLUTTER', ' '.join(arguments), flush=True)
        subprocess.run(command + arguments, cwd=STAGE, env=env, check=True)
    run(['pub', 'get', '--offline'])
    if args.device_test:
        env['XINGYU_ISOLATED_SMOKE'] = '1'
        run(['test', '--no-pub', 'integration_test/android_client_test.dart', '-d', args.device_test,
             '--dart-define=XINGYU_ANDROID_TEST=true', '--reporter=expanded'])
        return
    # Let Flutter regenerate release registrants without dev-only plugins.
    # --no-pub after a debug/pub-get pass leaves integration_test registered.
    if args.shorebird_test:
        env['APPDATA'] = str(ROOT / '.toolchain/shorebird-auth')
        env.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.longpaths', GIT_CONFIG_VALUE_0='true')
        subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            str(TOOL / 'xingyu-shorebird/bin/shorebird.ps1'), 'release', 'android', '--artifact=apk',
            '--target-platform=android-arm64', '--flutter-version=3.47.7', f'--build-name={version}',
            f'--build-number={build}', '--dart-define=XINGYU_ANDROID_TEST=true', f'--dart-define=XINGYU_PATCH_TRACK={args.patch_track}'] + version_flags,
            cwd=STAGE, env=env, check=True)
    else:
        run(['build', 'apk', '--release', '--target-platform=android-arm64',
             f'--build-name={version}', f'--build-number={build}', '--dart-define=XINGYU_ANDROID_TEST=true'] + version_flags)
    output = ROOT / f'output/Cangku-Xingyu-{version}-arm64.apk'
    output.parent.mkdir(exist_ok=True)
    shutil.copy2(STAGE / 'build/app/outputs/flutter-apk/app-release.apk', output)
    if output.stat().st_size > 24 * 1024 * 1024:
        raise SystemExit('APK exceeds the original Android updater limit')
    print(json.dumps({'apk': output.name, 'bytes': output.stat().st_size,
        'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'uploaded': False}, ensure_ascii=False), flush=True)

if __name__ == '__main__': main()
