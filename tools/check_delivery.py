"""Check package boundaries, embedded endpoint and exclusion of live OAuth credentials."""
import hashlib,json,re,tomllib,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'cloudflare-chat/public/updates/android.json').read_text(encoding='utf-8'))
apk=ROOT/'output/Cangku-Xingyu-0.9.0-debug.apk'
assert manifest['sha256']==hashlib.sha256(apk.read_bytes()).hexdigest() and manifest['size']==apk.stat().st_size
assert manifest['url']=='https://xingyu-chat-ccjk45415.pages.dev/releases/'+apk.name
source=(ROOT/'app/src/main/java/moe/cangku/reader/ServiceEndpoint.java').read_text(encoding='utf-8')
values=[int(v) for v in re.search(r'DATA=\{([^}]+)\}',source).group(1).split(',')]
assert ''.join(chr(v^((0x6d+i*31)&255)) for i,v in enumerate(values))=='https://xingyu-chat-ccjk45415.pages.dev'
live=[];credential=ROOT/'.toolchain/cloudflare-auth/.wrangler/config/default.toml'
if credential.is_file():
    config=tomllib.loads(credential.read_text(encoding='utf-8'))
    live=[v.encode() for k,v in config.items() if k in ['oauth_token','refresh_token'] and isinstance(v,str) and v]
announcement_key=ROOT/'.toolchain/announcements/admin.key'
if announcement_key.is_file():
    value=announcement_key.read_text(encoding='ascii').strip()
    if value:live.append(value.encode())
def scan(data):
    for secret in live:assert secret not in data,'Live credential in delivery'
    if data[:4]==b'PK\x03\x04':
        import io
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name in archive.namelist():scan(archive.read(name))
for name in ['Cangku-Xingyu-source.zip','Xingyu-Cloudflare-Server.zip']:
    with zipfile.ZipFile(ROOT/'output'/name) as archive:
        for entry in archive.namelist():
            path=Path(entry);assert not any(p in path.parts for p in ['.toolchain','node_modules','.wrangler','.secrets'])
            assert path.suffix not in ['.keystore','.jks','.sqlite3'] and path.name not in ['.env','.dev.vars','default.toml']
            scan(archive.read(entry))
scan(apk.read_bytes())
with zipfile.ZipFile(apk) as archive:assert b'xingyu-chat-ccjk45415.pages.dev' not in archive.read('classes.dex')
print('PASS delivery boundaries, live credential exclusion, final endpoint, APK hash and size')
