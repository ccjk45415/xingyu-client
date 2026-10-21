"""Check native bundle completeness, manifests, boundaries and live secret exclusion."""
import hashlib,json,sys,tomllib,zipfile,io,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output'
manifest=json.loads((ROOT/'cloudflare-chat/public/updates/windows.json').read_text(encoding='utf-8'))
archive=OUT/'Xingyu-Windows-0.1.1-x64.zip'
assert manifest['platform']=='windows-x64' and manifest['versionCode']==2
assert manifest['url']=='https://xingyu-chat-ccjk45415.pages.dev/releases/'+archive.name
assert manifest['size']==archive.stat().st_size and manifest['sha256']==hashlib.sha256(archive.read_bytes()).hexdigest()
secrets=[];oauth=ROOT/'.toolchain/cloudflare-auth/.wrangler/config/default.toml'
if oauth.is_file():
    values=tomllib.loads(oauth.read_text(encoding='utf-8'))
    secrets += [v.encode() for k,v in values.items() if k in ['oauth_token','refresh_token'] and isinstance(v,str) and v]
key=ROOT/'.toolchain/announcements/admin.key'
if key.is_file():secrets.append(key.read_text(encoding='ascii').strip().encode())
gh=ROOT/'.toolchain/github-cli/bin/gh.exe'
if gh.is_file() and (ROOT/'.toolchain/github-auth').is_dir():
    env=os.environ.copy();env['GH_CONFIG_DIR']=str(ROOT/'.toolchain/github-auth')
    result=subprocess.run([str(gh),'auth','token'],env=env,capture_output=True,timeout=15)
    if result.returncode==0 and result.stdout.strip():secrets.append(result.stdout.strip())
if '--stdin-secrets' in sys.argv:secrets += [line.strip().encode() for line in sys.stdin if line.strip()]
def scan(data):
    for secret in secrets:assert secret not in data,'Live credential found in delivery'
    if data.startswith(b'PK\x03\x04'):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            assert z.testzip() is None
            for name in z.namelist():
                p=Path(name);assert not any(part in ['.toolchain','.dart_tool','node_modules','.wrangler','.secrets','ephemeral'] for part in p.parts)
                assert p.suffix not in ['.keystore','.jks','.sqlite3'] and p.name not in ['default.toml','.env','.dev.vars']
                scan(z.read(name))
for name in ['Xingyu-Windows-0.1.1-x64.zip','Cangku-Xingyu-source.zip','Xingyu-Cloudflare-Server.zip']:scan((OUT/name).read_bytes())
with zipfile.ZipFile(archive) as z:
    prefix='Xingyu-Windows-0.1.1/'
    for name in ['Xingyu.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','data/app.so','data/icudtl.dat','data/flutter_assets/NOTICES.Z']:assert prefix+name in z.namelist()
    assert z.read(prefix+'Xingyu.exe').startswith(b'MZ')
    obfuscated=b'https://xingyu-chat-ccjk45415.pages.dev' not in z.read(prefix+'data/app.so')
with zipfile.ZipFile(OUT/'Cangku-Xingyu-source.zip') as z:assert 'Cangku-Xingyu/desktop/lib/main.dart' in z.namelist()
report={'windows_zip':'pass','platform':'windows-x64','version':'0.1.1','size':manifest['size'],'sha256':manifest['sha256'],'complete_native_runtime':True,'live_credentials_excluded':True,'endpoint_literal_absent_from_aot':obfuscated,'source_contains_flutter_project':True}
(ROOT/'evidence/desktop-delivery.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
