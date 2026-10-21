"""Fetch the pinned Apache-2.0 ZXing core dependency from Maven Central."""
import hashlib,json,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VERSION='3.5.4'
EXPECTED='71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13'
BASE=f'https://repo.maven.apache.org/maven2/com/google/zxing/core/{VERSION}/core-{VERSION}.jar'
TARGET=ROOT/'.toolchain/qr'/f'core-{VERSION}.jar'
def prepare():
    TARGET.parent.mkdir(parents=True,exist_ok=True)
    expected=EXPECTED
    if not TARGET.exists() or hashlib.sha256(TARGET.read_bytes()).hexdigest()!=expected:
        data=urllib.request.urlopen(BASE,timeout=60).read()
        assert hashlib.sha256(data).hexdigest()==expected,'ZXing checksum mismatch'
        TARGET.write_bytes(data)
    report={'dependency':'com.google.zxing:core','version':VERSION,'source':BASE,'sha256':expected,'license':'Apache-2.0'}
    (ROOT/'evidence/qr-dependency.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return TARGET
if __name__=='__main__':
    prepare();print('Verified ZXing core '+VERSION)
