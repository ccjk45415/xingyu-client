"""Read-only authenticated probe, no credentials/content retained."""
import getpass,sys,json,http.cookiejar,urllib.request,urllib.parse,urllib.error
from pathlib import Path
jar=http.cookiejar.CookieJar();client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar));base='https://cangku.moe'
def req(path,data=None,html=False):
 h={'User-Agent':'Mozilla/5.0','Accept':'text/html' if html else 'application/json','Origin':base,'Referer':base+'/','X-Requested-With':'XMLHttpRequest'}
 for c in jar:
  if c.name=='XSRF-TOKEN':h['X-XSRF-TOKEN']=urllib.parse.unquote(c.value)
 if data is not None:h['Content-Type']='application/json'
 with client.open(urllib.request.Request(base+path,headers=h,data=None if data is None else json.dumps(data).encode()),timeout=25) as r:b=r.read()
 return b.decode() if html else json.loads(b)
print('Awaiting account/password via stdin; not saved',flush=True)
account=(getpass.getpass('Account: ') if sys.stdin.isatty() else sys.stdin.readline()).strip();password=(getpass.getpass('Password: ') if sys.stdin.isatty() else sys.stdin.readline()).strip()
if not account or not password:raise SystemExit('Credentials not supplied; no login attempted')
req('/login',html=True);login=req('/api/v1/auth/login',{'login':account,'password':password,'remember':False});account=password=None
if login.get('code')!=0:raise SystemExit('Login failed')
baseq={'simple':1,'include':'user,categories:simple','per_page':3}
def posts(extra):return req('/api/v1/post/list?'+urllib.parse.urlencode({**baseq,**extra}))
first=posts({})['data'];target=first[0]['user_id'];unknown=2147483000
report={'read_only':True,'content_saved':False,'cases':{}}
for key in ['user_in[0]','user_id','author_id']:
 try:
  a=posts({key:target});b=posts({key:unknown})
  report['cases'][key]={'code':a.get('code'),'matches_target':all(int(p.get('user_id',0))==target for p in a.get('data',[])),'target_nonempty':bool(a.get('data')),'unknown_empty':not b.get('data'),'pagination_keys':list(a.get('meta',{}).get('pagination',{}))}
 except Exception as e:report['cases'][key]={'error_type':type(e).__name__}
 print(key,json.dumps(report['cases'][key]),flush=True)
Path('evidence/follow-site-contract.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
