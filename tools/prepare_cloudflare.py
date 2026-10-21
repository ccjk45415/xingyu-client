"""Install an isolated npm CLI from the official npm registry (no global changes)."""
import io,json,tarfile,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'.toolchain'/'npm'
root.mkdir(parents=True,exist_ok=True)
meta=json.load(urllib.request.urlopen('https://registry.npmjs.org/npm/latest',timeout=40))
url=meta['dist']['tarball']
if not url.startswith('https://registry.npmjs.org/npm/-/'):raise RuntimeError('Unexpected npm source')
data=urllib.request.urlopen(url,timeout=90).read()
import base64,hashlib
algorithm,expected=meta['dist']['integrity'].split('-',1)
if algorithm!='sha512' or base64.b64encode(hashlib.sha512(data).digest()).decode()!=expected:raise RuntimeError('npm integrity mismatch')
with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:archive.extractall(root,filter='data')
print('Installed isolated npm',meta['version'])
