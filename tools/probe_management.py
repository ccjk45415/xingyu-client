"""Authenticate with stdin, inspect only current user's read-only management contracts."""
import datetime, hashlib, http.cookiejar, json, re, sys, urllib.error, urllib.parse, urllib.request
from pathlib import Path
BASE='https://cangku.moe'
jar=http.cookiejar.CookieJar()
client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
def req(path,body=None,html=False):
    h={'User-Agent':'Mozilla/5.0','Accept':'text/html' if html else 'application/json','Origin':BASE,'Referer':BASE+'/'}
    if body is not None:h['Content-Type']='application/json'
    for c in jar:
        if c.name=='XSRF-TOKEN':h['X-XSRF-TOKEN']=urllib.parse.unquote(c.value)
    request=urllib.request.Request(BASE+path,headers=h,data=None if body is None else json.dumps(body).encode())
    with client.open(request,timeout=35) as response:
        raw=response.read().decode()
        return raw if html else json.loads(raw)
def shape(x,depth=0):
    if depth>4:return type(x).__name__
    if isinstance(x,dict):return {k:shape(v,depth+1) for k,v in x.items()}
    if isinstance(x,list):return [shape(x[0],depth+1)] if x else []
    return type(x).__name__
req('/login',html=True)
account=sys.stdin.readline().strip();password=sys.stdin.readline().strip()
login=req('/api/v1/auth/login',{'login':account,'password':password,'remember':False,'include':'roles,permissions,meta'})
account=password=None
user=login['data'];uid=user['id']
print('LOGIN',login.get('code'),flush=True)
report={}
html=req('/admin/post/create',html=True)
domain=re.search(r"['\"]?apiDomain['\"]?\s*:\s*['\"]([^'\"]+)",html)
report['admin_api_domain']=domain.group(1) if domain else None
print('ADMIN_API',report['admin_api_domain'],flush=True)
paths={
 'me':'auth/me?include=roles,permissions,meta',
 'level':'user/level',
 'credit_log':'user/creditLog?page=1&per_page=1',
 'count':'post/count',
 'published':f'post/list?user_id={uid}&status=publish&page=1&per_page=1&include=categories:simple&simple=1',
 'draft':'post/list?user_id='+str(uid)+'&status=draft&page=1&per_page=1&simple=1',
 'pending':'post/list?user_id='+str(uid)+'&status=pending&page=1&per_page=1&simple=1',
 'future':'post/list?user_id='+str(uid)+'&status=future&page=1&per_page=1&simple=1',
 'rejected':'post/list?user_id='+str(uid)+'&status=rejected&page=1&per_page=1&include=meta:include(reject_reason)&simple=1',
 'trash':'post/list?user_id='+str(uid)+'&status=trash&page=1&per_page=1&simple=1',
}
own_id=0
for key,path in paths.items():
    try:
        response=req('/api/v1/'+path)
        report[key]={'path':path.replace('user_id='+str(uid),'user_id={currentUserId}'),'code':response.get('code'),'schema':shape(response)}
        if key=='me':
            u=response.get('data',{});report[key]['permission_names']=[p.get('name') for p in u.get('permissions',[])];report[key]['meta_keys']=[p.get('key') for p in u.get('meta',[])]
        if key=='published' and response.get('data'):own_id=response['data'][0]['id']
        if key in ('draft','pending','future','rejected','trash'):
            report[key]['count']=response.get('meta',{}).get('pagination',{}).get('total')
        print(key,json.dumps(report[key],ensure_ascii=True),flush=True)
    except urllib.error.HTTPError as e:
        report[key]={'http':e.code};print(key,'HTTP',e.code,flush=True)
if own_id:
    response=req('/api/v1/post/info?id='+str(own_id)+'&include=user,categories:simple,tags&exclude_view=1')
    report['own_edit']={'path':'post/info?id={ownPostId}&include=user,categories:simple,tags&exclude_view=1','code':response.get('code'),'schema':shape(response),'owned':response.get('data',{}).get('user_id')==uid}
    print('own_edit',json.dumps(report['own_edit'],ensure_ascii=True),flush=True)
report['admin_script_sha256']=hashlib.sha256(Path('evidence/admin-app.js').read_bytes()).hexdigest()
Path('evidence/management-contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('SAVED redacted management contract',flush=True)
