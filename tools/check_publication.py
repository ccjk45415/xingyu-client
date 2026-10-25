"""Verify the three-platform publication set and clean source before deployment."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / 'cloudflare-chat/public'
notes = (ROOT / 'docs/RELEASE-0.13.0.md').read_text('utf-8').strip()
secrets = []
credentials = ROOT / '.toolchain/cloudflare-auth/.wrangler/config/default.toml'
if credentials.is_file():
    secrets += [v.encode() for k,v in tomllib.loads(credentials.read_text('utf-8')).items()
                if k in ['oauth_token','refresh_token'] and isinstance(v,str) and v]
key = ROOT / '.toolchain/announcements/admin.key'
if key.is_file(): secrets.append(key.read_bytes().strip())
env = os.environ.copy(); env['GH_CONFIG_DIR'] = str(ROOT / '.toolchain/github-auth')
token = subprocess.run([str(ROOT / '.toolchain/github-cli/bin/gh.exe'), 'auth', 'token'],
                       env=env, capture_output=True, check=True).stdout.strip()
secrets.append(token)

def scan(data):
    assert all(not secret or secret not in data for secret in secrets), 'Live credential in delivery'
    if data.startswith(b'PK\x03\x04'):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            assert z.testzip() is None
            for name in z.namelist():
                p = Path(name)
                assert not p.is_absolute() and '..' not in p.parts
                assert not {'.toolchain','.git','.dart_tool','ephemeral','node_modules','.wrangler','.secrets','.codex-remote-attachments'} & set(p.parts)
                assert p.name not in ['default.toml','.env','.dev.vars','key.properties']
                assert p.suffix not in ['.keystore','.jks','.sqlite3']
                scan(z.read(name))

raw = (ROOT / 'cloudflare-entry/release-index.mjs').read_text('utf-8')
index = json.loads(raw.split('export default ',1)[1].strip().rstrip(';'))
records = []
for platform, expected in [('android',('0.13.0',36)),('windows',('0.7.0',27)),('macos',('0.3.0',5))]:
    info = json.loads((PUBLIC / f'updates/{platform}.json').read_text('utf-8'))
    assert (info['versionName'],info['versionCode']) == expected and info['notes'] == notes
    assert info['url'].startswith('https://xingyu-chat-ccjk45415.pages.dev/releases/')
    name = info['url'].rsplit('/',1)[1]
    file = ROOT / 'output' / name
    assert file.stat().st_size == info['size']
    assert hashlib.sha256(file.read_bytes()).hexdigest() == info['sha256']
    if name in index:
        h = hashlib.sha256()
        for path in index[name]['chunks']:
            p = PUBLIC / path.lstrip('/')
            assert p.stat().st_size <= 16 * 1024 * 1024
            h.update(p.read_bytes())
        assert h.hexdigest() == info['sha256']
    else: assert (PUBLIC / 'releases' / name).read_bytes() == file.read_bytes()
    scan(file.read_bytes())
    records.append({'file':name,'bytes':info['size'],'sha256':info['sha256']})
extra = ROOT / 'output/Xingyu-macOS-0.3.0-arm64.dmg'
assert hashlib.sha256(extra.read_bytes()).hexdigest() == index[extra.name]['sha256']
scan(extra.read_bytes())
records.append({'file':extra.name,'bytes':extra.stat().st_size,'sha256':index[extra.name]['sha256']})
source = ROOT / 'output/Cangku-Xingyu-0.13.0-source.zip'
scan(source.read_bytes())
with zipfile.ZipFile(source) as z:
    for name in ['desktop/lib/core/updates.dart','desktop/assets/windows-update.ps1',
                 'desktop/android/app/src/main/java/moe/cangku/xingyu_desktop/UpdateProvider.java',
                 'desktop/macos/Runner/MainFlutterWindow.swift','.github/workflows/macos-test.yml','LICENSE']:
        assert 'Cangku-Xingyu/' + name in z.namelist(), name
records.append({'file':source.name,'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
assert all(p.stat().st_size <= 25 * 1024 * 1024 for p in PUBLIC.rglob('*') if p.is_file())
report = {'stage':'pre-publication','status':'pass','packages':records,
          'notes_match':True,'credential_scan':'pass','static_assets_within_pages_limit':True,
          'complete_native_installers':True}
(ROOT / 'output/Release-0.13.0-SHA256SUMS.txt').write_text(''.join(p['sha256']+'  '+p['file']+'\n' for p in records),encoding='ascii')
(ROOT / 'evidence/release-0.13.0-assets.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
