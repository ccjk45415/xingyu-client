"""Read-only deployed health, update metadata and APK integrity checks. No chat posts."""
import hashlib,json,urllib.request,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
origin=sys.argv[1] if len(sys.argv)>1 else 'https://xingyu-chat-ccjk45415.pages.dev'
assert origin in ['https://xingyu-chat.ccjk45415.workers.dev','https://xingyu-chat-ccjk45415.pages.dev']
def get(path):
    request=urllib.request.Request(origin+path,headers={'User-Agent':'XingyuDeploymentCheck/1','Cache-Control':'no-cache'})
    with urllib.request.urlopen(request,timeout=30) as response:return response.read()
health=json.loads(get('/health'));assert health['service']=='xingyu-chat' and health['protocol']==3 and health['channel_count']==2
manifest=json.loads(get('/updates/android'));assert manifest['available'] and manifest['versionCode']==13 and manifest['package']=='moe.cangku.reader'
assert manifest['url'].startswith(origin+'/releases/')
apk=get(manifest['url'][len(origin):]);assert len(apk)==manifest['size'] and hashlib.sha256(apk).hexdigest()==manifest['sha256']
local=ROOT/'output/Cangku-Xingyu-0.9.0-debug.apk';assert hashlib.sha256(local.read_bytes()).hexdigest()==manifest['sha256']
result={'origin':origin,'health':'pass','protocol':3,'channels':2,'versionCode':13,'apk_bytes':len(apk),'sha256':manifest['sha256'],'public_messages_sent':0,'public_load_tested':False}
(ROOT/'evidence/cloudflare-deployment.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result))
