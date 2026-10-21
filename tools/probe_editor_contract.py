"""Read-only official editor contract probe. Secrets/cookies remain in memory."""
import http.cookiejar,json,sys,urllib.request,urllib.parse,urllib.error,re,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE='https://cangku.moe'
jar=http.cookiejar.CookieJar();client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
def request(path,body=None):
 headers={'User-Agent':'Mozilla/5.0 XingyuEditorContract/1','Origin':BASE,'Referer':BASE+'/admin/post/create','Accept':'application/json,text/html','X-Requested-With':'XMLHttpRequest'}
 for c in jar:
  if c.name=='XSRF-TOKEN':headers['X-XSRF-TOKEN']=urllib.parse.unquote(c.value)
 if body is not None:headers['Content-Type']='application/json'
 try:
  with client.open(urllib.request.Request(BASE+path,data=None if body is None else json.dumps(body).encode(),headers=headers),timeout=30) as r:return r.status,r.read(2*1024*1024)
 except urllib.error.HTTPError as e:return e.code,e.read(16384)
account=sys.stdin.readline().strip();password=sys.stdin.readline().strip();request('/login');status,raw=request('/api/v1/auth/login',{'login':account,'password':password,'remember':False,'include':'roles,permissions'});account=password=None
v=json.loads(raw);assert status==200 and v.get('code')==0
report={'read_only':True,'credentials_saved':False,'posts_or_uploads_written':0,'permission_names':[p['name'] for p in v['data'].get('permissions',[]) if 'poll' in p['name'] or 'lotter' in p['name']],'role_names':[p['name'] for p in v['data'].get('roles',[])]}
status,raw=request('/admin/post/create');report['admin_page_status']=status
scripts=re.findall(r'<script[^>]+src=[\"\x27]([^\"\x27]+)',raw.decode('utf-8','replace'))
report['scripts']=scripts
for script in scripts:
 url=urllib.parse.urljoin(BASE,script);u=urllib.parse.urlparse(url)
 if u.netloc=='cangku.moe' and ('app.' in u.path or u.path.endswith('/app.js')):
  status,body=request(u.path+('?' + u.query if u.query else ''))
  if status==200 and len(body)>10000:
   report['current_admin_bundle_sha256']=hashlib.sha256(body).hexdigest();report['retained_admin_bundle_matches_current']=report['current_admin_bundle_sha256']==hashlib.sha256((ROOT/'evidence/admin-app.js').read_bytes()).hexdigest()
for base in ['/api','/api/v1']:
 for path in ['poll/list','lottery/list']:
  status,raw=request(base+'/'+path+'?page=1&per_page=1')
  try:
   v=json.loads(raw);data=v.get('data');first=data[0] if isinstance(data,list) and data else {}
   item={'http_status':status,'code':v.get('code'),'data_type':type(data).__name__,'item_keys':list(first),'pagination':v.get('meta',{}).get('pagination')}
  except Exception:item={'http_status':status,'json':False}
  report[base+'/'+path]=item
(ROOT/'evidence/editor-official-contract-probe.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=True))
