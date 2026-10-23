"""Prepare workspace-only Android SDK packages for the shared Flutter client."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / '.toolchain/android-sdk'
CACHE = ROOT / '.toolchain/downloads'
BASE = 'https://dl.google.com/android/repository/'

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(BASE + 'repository2-3.xml', headers={'User-Agent': 'XingyuBuild/1'})
    with urllib.request.urlopen(req, timeout=60) as response:
        tree = ET.fromstring(response.read())
    packages = {e.get('path'): e for e in tree.findall('remotePackage')}
    sources = {}
    for name in ['platforms;android-36', 'build-tools;36.0.0', 'cmdline-tools;19.0']:
        target = SDK.joinpath(*name.split(';'))
        if (target / 'source.properties').exists():
            print('READY', name, flush=True)
            continue
        node = packages[name]
        complete = next(a.find('complete') for a in node.findall('archives/archive')
                        if a.findtext('host-os') in (None, 'windows') and a.find('complete') is not None)
        relative = complete.findtext('url')
        url = relative if relative.startswith('https:') else BASE + relative
        checksum = complete.find('checksum')
        algorithm = checksum.get('type', 'sha1')
        digest = checksum.text.strip()
        archive = CACHE / Path(relative).name
        if not archive.exists():
            print('DOWNLOAD', Path(relative).name, flush=True)
            with urllib.request.urlopen(url, timeout=90) as r, archive.open('wb') as f:
                shutil.copyfileobj(r, f)
        if hashlib.new(algorithm, archive.read_bytes()).hexdigest() != digest:
            raise RuntimeError('Official SDK checksum mismatch: ' + name)
        stage = CACHE / ('flutter-sdk-' + name.replace(';', '-'))
        stage.mkdir(exist_ok=True)
        with zipfile.ZipFile(archive) as z:
            z.extractall(stage)
        directories = list(stage.iterdir())
        source = directories[0] if len(directories) == 1 and directories[0].is_dir() else stage
        shutil.copytree(source, target, dirs_exist_ok=True)
        sources[name] = {'url': url, algorithm: digest}
        print('READY', name, flush=True)
    (ROOT / 'evidence/flutter-android-toolchain.json').write_text(json.dumps(sources, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
