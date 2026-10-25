"""Verify anonymous first-party release downloads against local publication hashes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request
import urllib.parse
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--origin', required=True)
parser.add_argument('--report', required=True)
args = parser.parse_args()
origin = args.origin.rstrip('/')
assert urllib.parse.urlparse(origin).scheme == 'https'
assert urllib.parse.urlparse(origin).hostname.endswith('.pages.dev')
folder = ROOT / '.toolchain' / ('release-download-check-' + uuid.uuid4().hex)
folder.mkdir()
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl): return None
opener = urllib.request.build_opener(NoRedirect)
def fetch(path):
    return opener.open(urllib.request.Request(origin + path, headers={
        'User-Agent':'XingyuReleaseVerification/1', 'Accept-Encoding':'identity'}), timeout=120)

for platform in ['android','windows','macos']:
    expected = json.loads((ROOT / f'cloudflare-chat/public/updates/{platform}.json').read_text('utf-8'))
    with fetch(f'/updates/{platform}.json') as response:
        assert response.status == 200 and json.load(response) == expected, platform
with fetch('/updates/android') as response:
    assert json.load(response) == json.loads((ROOT / 'cloudflare-chat/public/updates/android.json').read_text('utf-8'))
with fetch('/health') as response:
    health = json.load(response)
    assert health.get('protocol') == 3 and health.get('channel_count') == 2
records = json.loads((ROOT / 'evidence/release-0.13.1-assets.json').read_text('utf-8'))['packages']
def download(record):
    size, digest = 0, hashlib.sha256()
    name = record['file']
    with fetch('/releases/' + name) as response, (folder / name).open('wb') as file:
        assert response.status == 200, name
        assert response.headers.get_content_type() != 'text/html', name
        while data := response.read(1024 * 1024):
            size += len(data)
            assert size <= record['bytes'], name
            file.write(data); digest.update(data)
    assert size == record['bytes'] and digest.hexdigest() == record['sha256'], name
    print('Verified anonymous download:',name,size,flush=True)
    return {'file':name,'size':size,'sha256':digest.hexdigest(),'status':200}
with ThreadPoolExecutor(max_workers=3) as pool:
    downloads = list(pool.map(download,records))
report = {'origin':origin,'status':'pass','manifest_channels':3,'legacy_android_endpoint':'pass',
          'anonymous_downloads_verified':downloads,'health_protocol':health['protocol'],
          'messages_sent':0,'redirects_followed':False}
(ROOT / args.report).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report))
