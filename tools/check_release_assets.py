"""Verify staged public assets and sanitized source before an authorized release."""
import hashlib,io,json,os,subprocess,tomllib,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
notes=(ROOT/'docs/RELEASE-0.9.10.md').read_text(encoding='utf-8').strip()
secrets=[]
oauth=ROOT/'.toolchain/cloudflare-auth/.wrangler/config/default.toml'
if oauth.exists():
    secrets += [v.encode() for k,v in tomllib.loads(oauth.read_text(encoding='utf-8')).items() if k in ['oauth_token','refresh_token'] and isinstance(v,str) and v]
key=ROOT/'.toolchain/announcements/admin.key'
if key.exists() and key.read_text().strip():secrets.append(key.read_text().strip().encode())
env=os.environ.copy();env['GH_CONFIG_DIR']=str(ROOT/'.toolchain/github-auth')
token=subprocess.run([str(ROOT/'.toolchain/github-cli/bin/gh.exe'),'auth','token'],env=env,capture_output=True,timeout=15)
if token.returncode==0 and token.stdout.strip():secrets.append(token.stdout.strip())
def scan(data):
    assert all(secret not in data for secret in secrets),'Live secret found'
    if data.startswith(b'PK\x03\x04'):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            assert archive.testzip() is None,'Corrupt archive'
            for name in archive.namelist():
                path=Path(name);assert not path.is_absolute() and '..' not in path.parts,'Invalid archive path'
                assert not set(path.parts)&{'.toolchain','.git','.dart_tool','.wrangler','node_modules','.secrets','ephemeral','.codex-remote-attachments'},'Private path in delivery'
                assert path.name not in {'.env','.dev.vars','default.toml'} and path.suffix not in {'.jks','.keystore','.sqlite3'},'Private file in delivery'
                scan(archive.read(name))
packages=[]
for platform in ['android','windows']:
    manifest=json.loads((ROOT/f'cloudflare-chat/public/updates/{platform}.json').read_text(encoding='utf-8'))
    package=ROOT/'output'/manifest['url'].rsplit('/',1)[1]
    assert manifest['notes']==notes
    assert package.stat().st_size==manifest['size'] and hashlib.sha256(package.read_bytes()).hexdigest()==manifest['sha256']
    assert (ROOT/'cloudflare-chat/public/releases'/package.name).read_bytes()==package.read_bytes()
    scan(package.read_bytes())
    if platform=='windows':
        with zipfile.ZipFile(package) as archive:
            name=next(n for n in archive.namelist() if n.endswith('/VERSION.json'));version=json.loads(archive.read(name));prefix=name[:-len('VERSION.json')]
            assert version['versionName']==manifest['versionName'] and version['versionCode']==manifest['versionCode']
            for p in ['Xingyu.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data/app.so','data/icudtl.dat','data/flutter_assets/NOTICES.Z']:assert prefix+p in archive.namelist()
    packages.append({'file':package.name,'size':manifest['size'],'sha256':manifest['sha256'],'version':manifest['versionName'],'code':manifest['versionCode']})
source=ROOT/'output/Cangku-Xingyu-source.zip';scan(source.read_bytes())
with zipfile.ZipFile(source) as archive:
    for name in ['app/src/main/java/moe/cangku/reader/CrashDiagnostics.java','desktop/lib/core/error_diagnostics.dart','desktop/lib/pages/diagnostics.dart','LICENSE']:
        assert 'Cangku-Xingyu/'+name in archive.namelist()
packages.append({'file':source.name,'size':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
report={'stage':'pre-publication','status':'pass','secrets_excluded':True,'notes_exact':True,'packages':packages}
(ROOT/'evidence/diagnostics-release-assets.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(ROOT/'output/Release-SHA256SUMS.txt').write_text(''.join(p['sha256']+'  '+p['file']+'\n' for p in packages),encoding='ascii')
print(json.dumps(report,ensure_ascii=False))
