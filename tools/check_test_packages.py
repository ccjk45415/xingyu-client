"""Validate local test packages without changing any public release metadata."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--apk', required=True)
parser.add_argument('--windows', required=True)
parser.add_argument('--stdin-secrets', action='store_true')
parser.add_argument('--report', default='evidence/test-packages.json')
args = parser.parse_args()
secrets = []
oauth = ROOT / '.toolchain/cloudflare-auth/.wrangler/config/default.toml'
if oauth.is_file():
    values = tomllib.loads(oauth.read_text(encoding='utf-8'))
    secrets += [value.encode() for key, value in values.items()
                if key in ['oauth_token', 'refresh_token'] and isinstance(value, str) and value]
key = ROOT / '.toolchain/announcements/admin.key'
if key.is_file() and key.read_text(encoding='ascii').strip():
    secrets.append(key.read_text(encoding='ascii').strip().encode())
gh = ROOT / '.toolchain/github-cli/bin/gh.exe'
if gh.is_file() and (ROOT / '.toolchain/github-auth').is_dir():
    env = os.environ.copy()
    env['GH_CONFIG_DIR'] = str(ROOT / '.toolchain/github-auth')
    token = subprocess.run([str(gh), 'auth', 'token'], env=env, capture_output=True, timeout=15)
    if token.returncode == 0 and token.stdout.strip():
        secrets.append(token.stdout.strip())
if args.stdin_secrets:
    secrets += [line.strip().encode() for line in sys.stdin if line.strip()]


def scan(data):
    assert all(secret not in data for secret in secrets), 'Live credential found in test package'
    if data.startswith(b'PK\x03\x04'):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            assert archive.testzip() is None, 'Corrupted archive'
            for name in archive.namelist():
                path = Path(name)
                assert not path.is_absolute() and '..' not in path.parts
                assert not any(part in ['.toolchain', '.dart_tool', 'node_modules', '.wrangler', '.secrets', 'ephemeral'] for part in path.parts)
                assert path.suffix not in ['.keystore', '.jks', '.sqlite3']
                assert path.name not in ['default.toml', '.env', '.dev.vars']
                scan(archive.read(name))


packages = [Path(args.apk).resolve(), Path(args.windows).resolve()]
for package in packages:
    scan(package.read_bytes())
with zipfile.ZipFile(packages[0]) as archive:
    assert {'AndroidManifest.xml', 'classes.dex', 'resources.arsc'} <= set(archive.namelist())
with zipfile.ZipFile(packages[1]) as archive:
    version_file = next(name for name in archive.namelist() if name.endswith('/VERSION.json'))
    version = json.loads(archive.read(version_file))
    prefix = version_file[:-len('VERSION.json')]
    assert version['platform'] == 'windows-x64'
    for name in ['Xingyu.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll',
                 'vcruntime140_1.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z']:
        assert prefix + name in archive.namelist(), 'Incomplete Windows runtime'
    assert archive.read(prefix + 'Xingyu.exe').startswith(b'MZ')
before = ROOT / 'app/build/editor-fixes-public-before.json'
if before.is_file():
    for name, digest in json.loads(before.read_text(encoding='utf-8')).items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, 'Public update metadata changed'
report = {
    'status': 'awaiting_user_test',
    'uploaded': False,
    'public_update_metadata_unchanged': True,
    'complete_native_runtime': True,
    'live_credentials_excluded': True,
    'packages': [{'file': p.name, 'size': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in packages],
}
(ROOT / args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
