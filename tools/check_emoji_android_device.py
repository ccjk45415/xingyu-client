"""Actual Android emoji layout regression, using a separate Internet-disabled test package."""
import json
import os
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / '.toolchain/android-sdk'
BT = SDK / 'build-tools/35.0.0'
JDK = Path(os.environ.get('JAVA_HOME', 'C:/Program Files/Java/jdk-17'))
ADB = SDK / 'platform-tools/adb.exe'
ANDROID = SDK / 'platforms/android-35/android.jar'
OUT = ROOT / 'app/build/emoji-device'
OUT.mkdir(parents=True, exist_ok=True)
PACKAGE = 'moe.cangku.reader.emojicheck'


def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True,
                          encoding='utf-8', errors='replace', timeout=kwargs.pop('timeout', 30), **kwargs)


def main():
    build_only = '--build-only' in sys.argv
    devices = [] if build_only else [line.split()[0] for line in run([ADB, 'devices']).stdout.splitlines() if line.endswith('\tdevice')]
    if not build_only and len(devices) != 1:
        raise RuntimeError('Exactly one authorized Android device is required')
    prefix = [] if build_only else [ADB, '-s', devices[0]]
    manifest = OUT / 'AndroidManifest.xml'
    manifest.write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{PACKAGE}"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="星屿表情布局独立测试" android:allowBackup="false"/><instrumentation android:name="moe.cangku.reader.EmojiGridInstrument" android:targetPackage="{PACKAGE}"/></manifest>''', encoding='utf-8')
    classes = OUT / 'classes'
    classes.mkdir(exist_ok=True)
    source = ROOT / 'app/src/main/java/moe/cangku/reader'
    run([JDK / 'bin/javac.exe', '-encoding', 'UTF-8', '--release', '17', '-cp', ANDROID,
         '-d', classes, source / 'Ui.java', source / 'CommentEmojiGrid.java', ROOT / 'tests/EmojiGridInstrument.java'])
    jar = OUT / 'classes.jar'
    with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in classes.rglob('*.class'):
            archive.write(file, file.relative_to(classes).as_posix())
    dex = OUT / 'dex'
    dex.mkdir(exist_ok=True)
    run([JDK / 'bin/java.exe', '-cp', BT / 'lib/d8.jar', 'com.android.tools.r8.D8', '--lib', ANDROID,
         '--min-api', '26', '--output', dex, jar])
    unsigned, aligned, signed = [OUT / name for name in ['unsigned.apk', 'aligned.apk', 'emoji-check.apk']]
    run([BT / 'aapt2.exe', 'link', '-o', unsigned, '--manifest', manifest, '-I', ANDROID])
    with zipfile.ZipFile(unsigned, 'a', zipfile.ZIP_DEFLATED) as archive:
        for file in dex.glob('*.dex'):
            archive.write(file, file.name)
    run([BT / 'zipalign.exe', '-f', '-p', '4', unsigned, aligned])
    run([JDK / 'bin/java.exe', '-jar', BT / 'lib/apksigner.jar', 'sign', '--ks', ROOT / '.toolchain/keys/debug.keystore',
         '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', signed, aligned])
    if build_only:
        print('PASS isolated emoji view test APK compiles/signs; not installed or executed')
        return
    report = {'isolated_test_package': PACKAGE, 'production_client_changed': False,
              'internet_permission': False, 'synthetic_images_only': True, 'result': 'not run'}
    try:
        run([*prefix, 'install', '--no-incremental', '-r', '-t', signed], timeout=30)
        output = run([*prefix, 'shell', 'am', 'instrument', '-w', PACKAGE + '/moe.cangku.reader.EmojiGridInstrument'], timeout=55).stdout
        report['result'] = output.strip()
        if 'EMOJI_GRID_DEVICE_PASS' not in output:
            raise RuntimeError(output[-2500:])
        for name in ['emoji-grid-9.png', 'emoji-grid-66.png', 'emoji-grid-large-font.png']:
            run([*prefix, 'pull', f'/sdcard/Android/data/{PACKAGE}/files/{name}', ROOT / 'evidence' / name])
        print(output.strip())
    except Exception as error:
        report['result'] = type(error).__name__ + ': isolated device test did not finish; no UI pass claimed'
        raise
    finally:
        try:
            run([*prefix, 'uninstall', PACKAGE], timeout=20)
        except Exception:
            pass
        (ROOT / 'evidence/emoji-layout-device-validation.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
