"""Validate downloaded macOS test installers without installing them."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory', type=Path, default=Path('output/macos-test'))
parser.add_argument('--report', type=Path, default=Path('evidence/macos-test-artifacts.json'))
parser.add_argument('--version', default='0.1.0')
parser.add_argument('--formal', action='store_true')
args = parser.parse_args()
folder = args.directory.resolve()
suffix = '' if args.formal else '-test'
expected = {f'Xingyu-macOS-{args.version}{suffix}-arm64.{extension}' for extension in ['pkg', 'dmg']}
checksums = {}
for line in (folder / 'macOS-SHA256SUMS.txt').read_text('ascii').splitlines():
    digest, name = line.split()
    assert name in expected and len(digest) == 64
    checksums[name] = digest
assert set(checksums) == expected
artifacts = []
for name, digest in checksums.items():
    path = folder / name
    assert path.is_file() and path.stat().st_size > 1024
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    artifacts.append({'file': name, 'bytes': path.stat().st_size, 'sha256': digest})
package = folder / next(name for name in expected if name.endswith('.pkg'))
with package.open('rb') as stream:
    magic, header, version, packed, unpacked, algorithm = struct.unpack('>4sHHQQI', stream.read(28))
    assert magic == b'xar!' and version == 1 and header >= 28
    assert packed <= 32 * 1024 * 1024 and unpacked <= 32 * 1024 * 1024
    stream.seek(header)
    toc = zlib.decompressobj().decompress(stream.read(packed), unpacked + 1)
    assert len(toc) == unpacked
    tree = ET.fromstring(toc)
    names = {node.text for node in tree.findall('.//file/name')}
    assert {'Payload', 'PackageInfo'} <= names
    assert 'Scripts' not in names, 'Unexpected installer script payload'
image = folder / next(name for name in expected if name.endswith('.dmg'))
with image.open('rb') as stream:
    stream.seek(-512, 2)
    assert stream.read(4) == b'koly', 'Expected a real Apple UDIF image'
report = json.loads((folder / 'macOS-build-report.json').read_text('utf-8'))
assert report['platform'] == 'macos-arm64' and report['version'] == args.version
assert report['published'] is False
assert report['native_self_check']['macos_native_engine'] == 'pass'
assert report['native_self_check']['keychain_round_trip'] == 'pass'
root = Path(__file__).resolve().parents[1]
baseline = root / 'app/build/editor-fixes-public-before.json'
assert baseline.is_file(), 'Public update baseline is missing'
for name, digest in json.loads(baseline.read_text('utf-8')).items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, 'Public update metadata changed'
result = {'status': 'awaiting_user_test', 'installer_container': 'XAR component PKG',
          'disk_image': 'Apple UDIF', 'installer_scripts': False,
          'apple_notarized': False, 'public_update_unchanged': True,
          'native_report': report, 'artifacts': artifacts}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
