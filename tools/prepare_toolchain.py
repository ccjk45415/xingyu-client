"""Download only official Google SDK packages into this workspace (no global changes)."""
import hashlib, json, os, shutil, urllib.request, zipfile, xml.etree.ElementTree as ET
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SDK=ROOT/'.toolchain'/'android-sdk'
CACHE=ROOT/'.toolchain'/'downloads'
SDK.mkdir(parents=True,exist_ok=True)
CACHE.mkdir(parents=True,exist_ok=True)
BASE='https://dl.google.com/android/repository/'
def fetch(url,path):
    print('DOWNLOAD',url,flush=True)
    with urllib.request.urlopen(url,timeout=90) as r, path.open('wb') as f:shutil.copyfileobj(r,f)
    print('DOWNLOADED',path.name,path.stat().st_size,flush=True)
repo=CACHE/'repository2-3.xml'
if not repo.exists():fetch(BASE+'repository2-3.xml',repo)
tree=ET.parse(repo).getroot()
packages={e.get('path'):e for e in tree.findall('remotePackage')}
manifest={}
for name in ['platforms;android-35','build-tools;35.0.0','platform-tools']:
    node=packages.get(name)
    if node is None:raise RuntimeError('Missing official package '+name)
    candidates=[]
    for archive in node.findall('archives/archive'):
        host=archive.findtext('host-os')
        if host not in (None,'windows'):continue
        complete=archive.find('complete')
        if complete is not None:candidates.append(complete)
    if not candidates:raise RuntimeError('No Windows archive for '+name)
    complete=candidates[0]
    relative=complete.findtext('url')
    url=relative if relative.startswith('https:') else BASE+relative
    checksum=complete.find('checksum')
    digest=checksum.text.strip();algorithm=checksum.get('type','sha1')
    archive_path=CACHE/Path(relative).name
    if not archive_path.exists():fetch(url,archive_path)
    actual=hashlib.new(algorithm,archive_path.read_bytes()).hexdigest()
    if actual!=digest:raise RuntimeError('Checksum mismatch '+str(archive_path))
    target=SDK.joinpath(*name.split(';'))
    if not (target/'source.properties').exists():
        stage=CACHE/('extract-'+name.replace(';','-'))
        stage.mkdir(exist_ok=True)
        with zipfile.ZipFile(archive_path) as z:z.extractall(stage)
        roots=list(stage.iterdir())
        source=roots[0] if len(roots)==1 and roots[0].is_dir() else stage
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copytree(source,target,dirs_exist_ok=True)
    manifest[name]={'url':url,'checksum_type':algorithm,'checksum':digest}
    print('READY',name,flush=True)
(ROOT/'evidence'/'toolchain-sources.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(ROOT/'local.properties').write_text('sdk.dir='+str(SDK).replace('\\','/')+'\n',encoding='utf-8')
print('SDK_READY',flush=True)
