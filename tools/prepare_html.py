"""Pinned MIT jsoup parser. No runtime HTTP client from this library is used."""
import hashlib,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VERSION='1.23.2';EXPECTED='e9d8c856856680427f096d156f02a414289985c930998fcb519ce5be39b42003'
def prepare():
    p=ROOT/'.toolchain/html'/f'jsoup-{VERSION}.jar';p.parent.mkdir(exist_ok=True,parents=True)
    if not p.is_file():p.write_bytes(urllib.request.urlopen(f'https://repo.maven.apache.org/maven2/org/jsoup/jsoup/{VERSION}/jsoup-{VERSION}.jar',timeout=45).read())
    assert hashlib.sha256(p.read_bytes()).hexdigest()==EXPECTED,'jsoup checksum mismatch'
    target=ROOT/'app/src/main/assets/third_party/LICENSE.jsoup.txt'
    with zipfile.ZipFile(p) as z:target.write_bytes(z.read('META-INF/jsoup/LICENSE'))
    return p
if __name__=='__main__':prepare();print('Verified jsoup '+VERSION)
