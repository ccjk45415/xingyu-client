"""Validate local test installers without logging website or build credentials."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/2026年10月24日/20261101-动态模板测试'
SDK = ROOT / '.toolchain/android-sdk/build-tools/35.0.0'


def command(args):
    return subprocess.check_output([str(a) for a in args], cwd=ROOT, text=True, encoding='utf-8', errors='replace')


def main():
    apk = OUT / 'Cangku-Xingyu-0.13.6-template-test-arm64.apk'
    archive = OUT / 'Xingyu-Windows-0.7.5-template-test-x64.zip'
    report = {'uploaded': False, 'formal_feeds_changed': False}
    badging = command([SDK / 'aapt2.exe', 'dump', 'badging', apk])
    for value in ["name='moe.cangku.reader'", "application-label:'仓库 · 星屿'", "versionCode='42'", "versionName='0.13.6-template-test'", "targetSdkVersion:'36'"]:
        assert value in badging, value
    assert 'application-debuggable' not in badging
    alignments = {}
    with zipfile.ZipFile(apk) as package:
        names = package.namelist()
        assert any('sqlite' in name.lower() and name.endswith('.so') for name in names), 'Missing Android SQLite native asset'
        assert not any(name.endswith(('.jks', '.keystore')) for name in names)
        for name in names:
            if not name.startswith('lib/') or not name.endswith('.so'):
                continue
            assert name.startswith('lib/arm64-v8a/'), 'Unexpected ABI'
            data = package.read(name)
            assert data[:6] == b'\x7fELF\x02\x01'
            offset = struct.unpack_from('<Q', data, 32)[0]
            size, count = struct.unpack_from('<HH', data, 54)
            values = [struct.unpack_from('<Q', data, offset + i * size + 48)[0]
                      for i in range(count) if struct.unpack_from('<I', data, offset + i * size)[0] == 1]
            assert values and min(values) >= 16384, f'Unaligned native library: {name}'
            alignments[name] = min(values)
    env = os.environ.copy()
    env['JAVA_HOME'] = env.get('JAVA_HOME', 'C:/Program Files/Java/jdk-17')
    def signer(path):
        out = subprocess.check_output([str(SDK/'apksigner.bat'), 'verify', '--print-certs', str(path)], env=env, text=True, encoding='utf-8', errors='replace')
        return re.search(r'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)', out).group(1)
    assert signer(apk) == signer(ROOT/'output/Cangku-Xingyu-0.13.5-arm64.apk'), 'Original signer mismatch'
    with zipfile.ZipFile(archive) as package:
        prefix = 'Xingyu-Windows-0.7.5-template-test/'
        names = package.namelist()
        for name in ['Xingyu.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z']:
            assert prefix + name in names, name
        assert any('sqlite' in name.lower() and name.endswith('.dll') for name in names), 'Missing Windows SQLite native asset'
        version = json.loads(package.read(prefix+'VERSION.json'))
        assert version['versionCode'] == 32
    for platform, path in [('android', apk), ('windows', archive)]:
        report[platform] = {'file': path.name, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    report['android']['native_alignments'] = alignments
    report['android']['original_signer_matches'] = True
    report['public_versions'] = {}
    for platform, version in [('android','0.13.5'),('windows','0.7.4'),('macos','0.3.4')]:
        url = f'https://xingyu-chat-ccjk45415.pages.dev/updates/{platform}.json'
        request = urllib.request.Request(url, headers={'User-Agent': 'XingyuDesktop/0.7.5-template-test', 'Accept': 'application/json'})
        with urllib.request.urlopen(request, timeout=30) as response:
            value = json.load(response)
        assert value['versionName'] == version, f'Unexpected formal feed: {platform}'
        report['public_versions'][platform] = value['versionName']
    (OUT/'package-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
