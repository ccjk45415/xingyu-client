"""Validate the local Flutter APK identity, engine, signature and 16 KB alignment."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / '.toolchain/android-sdk/build-tools/35.0.0'
JAVA = Path(os.environ.get('JAVA_HOME', 'C:/Program Files/Java/jdk-17')) / 'bin/java.exe'
APK = ROOT / 'output/Cangku-Xingyu-0.11.0-arm64.apk'

def output(command):
    return subprocess.check_output([str(v) for v in command], cwd=ROOT).decode('utf-8', errors='replace')

badging = output([SDK / 'aapt2.exe', 'dump', 'badging', APK.relative_to(ROOT)])
assert "name='moe.cangku.reader'" in badging
assert "application-label:'仓库 · 星屿'" in badging
assert "versionCode='33'" in badging and "versionName='0.11.0'" in badging
assert APK.stat().st_size <= 24 * 1024 * 1024
assert "minSdkVersion:'26'" in badging and "targetSdkVersion:'36'" in badging
assert 'application-debuggable' not in badging
assert 'android.permission.INTERNET' in badging and 'android.permission.ACCESS_NETWORK_STATE' in badging
assert 'android.permission.MANAGE_EXTERNAL_STORAGE' not in badging
with zipfile.ZipFile(APK) as archive:
    names = set(archive.namelist())
    assert {'lib/arm64-v8a/libflutter.so', 'lib/arm64-v8a/libapp.so',
            'assets/flutter_assets/NOTICES.Z', 'classes.dex', 'resources.arsc'} <= names
    assert not any('.keystore' in n or n.endswith('.jks') for n in names)
    assert not any('lib/armeabi-v7a/' in n or 'lib/x86/' in n or 'lib/x86_64/' in n for n in names)
    assert 'lib/arm64-v8a/libmpv.so' in names
    elf_libraries = []
    for name in sorted(n for n in names if n.endswith('.so')):
        data = archive.read(name)
        assert data[:6] == b'\x7fELF\x02\x01', 'Expected little endian ELF64'
        phoff = struct.unpack_from('<Q', data, 32)[0]
        entry_size, count = struct.unpack_from('<HH', data, 54)
        for index in range(count):
            offset = phoff + index * entry_size
            if struct.unpack_from('<I', data, offset)[0] == 1:
                file_offset, virtual = struct.unpack_from('<QQ', data, offset + 8)
                alignment = struct.unpack_from('<Q', data, offset + 48)[0]
                assert alignment >= 16384 and file_offset % 16384 == virtual % 16384, 'ELF 16 KB mismatch: ' + name
        elf_libraries.append(name)

def certificate(file):
    text = output([JAVA, '-jar', SDK / 'lib/apksigner.jar', 'verify', '--print-certs', file])
    return re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)', text).group(1)
assert certificate(APK) == certificate(ROOT / 'output/Cangku-Xingyu-0.9.10-debug.apk')
subprocess.run([str(SDK / 'zipalign.exe'), '-c', '-P', '16', '4', str(APK)], check=True)
report = {
    'artifact': APK.name, 'size': APK.stat().st_size, 'sha256': hashlib.sha256(APK.read_bytes()).hexdigest(),
    'engine': 'Flutter Android / Dart AOT', 'min_sdk': 26, 'target_sdk': 36,
    'package': 'moe.cangku.reader', 'version_name': '0.11.0', 'version_code': 33,
    'abi': 'arm64-v8a', 'signature_verified': True, 'original_test_signer_preserved': True,
    'alignment_16kb_verified': True, 'all_elf_load_segments_16kb_verified': True, 'native_libraries': elf_libraries, 'debuggable': False,
    'real_device_test': 'not_run_for_this_build', 'android_16_samsung_test': 'pending_user',
    'uploaded': False,
}
(ROOT / 'evidence/flutter-android-package.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
