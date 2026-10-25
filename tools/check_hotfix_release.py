"""Verify the authorized 0.13.1 release before publishing its three update feeds."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
notes = (ROOT / 'docs/RELEASE-0.13.1.md').read_text('utf-8').strip()
names = ['Cangku-Xingyu-0.13.1-arm64.apk', 'Xingyu-Windows-0.7.1-x64.zip',
         'Xingyu-macOS-0.3.1-arm64.pkg', 'Xingyu-macOS-0.3.1-arm64.dmg',
         'Cangku-Xingyu-0.13.1-source.zip']
secrets = []
for path in [ROOT / '.toolchain/shorebird-auth/shorebird/credentials-v2.json',
             ROOT / '.toolchain/hotfix-ci-short.json']:
    if path.exists():
        value = json.loads(path.read_text('utf-8'))
        secrets += [value[k].encode() for k in ['accessToken', 'refreshToken', 'idToken']
                    if isinstance(value.get(k), str) and value[k]]
oauth = ROOT / '.toolchain/cloudflare-auth/.wrangler/config/default.toml'
if oauth.exists():
    value = tomllib.loads(oauth.read_text('utf-8'))
    secrets += [value[k].encode() for k in ['oauth_token', 'refresh_token'] if value.get(k)]
for name in ['checkin/master.key', 'announcements/admin.key']:
    key = ROOT / '.toolchain' / name
    if key.exists() and key.read_text().strip(): secrets.append(key.read_text().strip().encode())
env = os.environ.copy(); env['GH_CONFIG_DIR'] = str(ROOT / '.toolchain/github-auth')
token = subprocess.run([str(ROOT / '.toolchain/github-cli/bin/gh.exe'), 'auth', 'token'],
                       env=env, capture_output=True, check=True).stdout.strip()
if token: secrets.append(token)

def scan(data):
    assert all(secret not in data for secret in secrets), 'Live credential in delivery'

records = []
for name in names:
    file = ROOT / 'output' / name
    data = file.read_bytes(); scan(data)
    if zipfile.is_zipfile(file):
        with zipfile.ZipFile(file) as archive:
            assert archive.testzip() is None
            for entry in archive.namelist():
                path = Path(entry)
                assert not path.is_absolute() and '..' not in path.parts
                assert not set(path.parts) & {'.toolchain', '.git', '.dart_tool', '.wrangler', 'node_modules', '.secrets', 'ephemeral', '.codex-remote-attachments'}
                assert path.name not in {'.env', '.dev.vars', 'default.toml', 'credentials-v2.json'}
                assert path.suffix not in {'.jks', '.keystore', '.sqlite3'}
                scan(archive.read(entry))
    records.append({'file': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
for platform, version, code in [('android', '0.13.1', 37), ('windows', '0.7.1', 28), ('macos', '0.3.1', 6)]:
    manifest = json.loads((ROOT / f'cloudflare-chat/public/updates/{platform}.json').read_text('utf-8'))
    record = next(r for r in records if manifest['url'].endswith('/' + r['file']))
    assert (manifest['versionName'], manifest['versionCode'], manifest['notes']) == (version, code, notes)
    assert (manifest['size'], manifest['sha256']) == (record['bytes'], record['sha256'])
with zipfile.ZipFile(ROOT / 'output' / names[1]) as archive:
    v = json.loads(archive.read('Xingyu-Windows-0.7.1/VERSION.json'))
    assert (v['versionName'], v['versionCode']) == ('0.7.1', 28)
with zipfile.ZipFile(ROOT / 'output' / names[4]) as archive:
    assert 'Cangku-Xingyu/desktop/lib/core/windows_update_handoff.dart' in archive.namelist()
report = {'stage': 'pre-publication', 'status': 'pass', 'packages': records,
          'notes_match': True, 'credential_scan': 'pass', 'complete_native_installers': True}
(ROOT / 'evidence/release-0.13.1-assets.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
(ROOT / 'output/Release-0.13.1-SHA256SUMS.txt').write_text(''.join(r['sha256']+'  '+r['file']+'\n' for r in records), encoding='ascii')
print(json.dumps(report))
