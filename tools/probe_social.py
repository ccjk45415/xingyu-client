"""Read-only social contract probe. Login via stdin; never save credentials/content."""
import hashlib, http.cookiejar, json, re, sys, urllib.error, urllib.parse, urllib.request
from pathlib import Path
BASE='https://cangku.moe'
jar=http.cookiejar.CookieJar()
client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
def req(path, data=None, html=False):
    h={'User-Agent':'Mozilla/5.0','Accept':'text/html' if html else 'application/json','Origin':BASE,'Referer':BASE+'/','X-Requested-With':'XMLHttpRequest'}
    for c in jar:
        if c.name=='XSRF-TOKEN':h['X-XSRF-TOKEN']=urllib.parse.unquote(c.value)
    if data is not None:h['Content-Type']='application/json'
    with client.open(urllib.request.Request(BASE+path,headers=h,data=None if data is None else json.dumps(data).encode()),timeout=35) as r:
        raw=r.read().decode()
    return raw if html else json.loads(raw)
def shape(v, depth=0):
    if depth>6:return type(v).__name__
    if isinstance(v,dict):return {k:shape(x,depth+1) for k,x in v.items()}
    if isinstance(v,list):return [shape(v[0],depth+1)] if v else []
    return type(v).__name__
print('Waiting for account and password on stdin (not retained)',flush=True)
account=sys.stdin.readline().strip();password=sys.stdin.readline().strip()
html=req('/login',html=True)
login=req('/api/v1/auth/login',{'login':account,'password':password,'remember':False})
account=password=None
if login.get('code')!=0:raise SystemExit('Login failed')
uid=login['data']['id'];report={'read_only':True,'private_content_saved':False}
paths={
    'own_comments':f'user/comment?id={uid}&page=1&per_page=2&include=post:simple,user&with[0]=post&with[1]=user',
    'notification_count':'user/unreadNotificationCount',
    'replies':'user/notification?action=reply&page=1&per_page=2&include=user,causer,subject&with[0]=user&with[1]=causer&with[2]=subject',
    'votes':'user/notification?action=vote&page=1&per_page=2&include=user,causer,subject&with[0]=user&with[1]=causer&with[2]=subject',
    'announcements':'announce/list?page=1&per_page=2',
    'comments':'comment/list?post_id=229794&parent_id=0&page=1&per_page=2&include=children:include(user):per_page(2),user&with[0]=children&with[1]=user&order_by=created_at&order=desc&sticky=1',
    'users':'user/list?search='+urllib.parse.quote('初音')+'&page=1&per_page=2',
}
for key,path in paths.items():
    try:
        data=req('/api/v1/'+path)
        item={'path':path.replace(str(uid),'{currentUserId}'),'code':data.get('code'),'schema':shape(data)}
        if key=='notification_count':item['count_keys']=list(data.get('data',{}))
        report[key]=item;print(key,json.dumps(item,ensure_ascii=True),flush=True)
    except urllib.error.HTTPError as e:
        report[key]={'http':e.code};print(key,'HTTP',e.code,flush=True)
scripts=re.findall(r'<script[^>]+src=["\']([^"\']+)["\']',html)
report['public_scripts']=scripts
for src in scripts:
    if re.search(r'/app(?:\.[a-f0-9]+)?\.js',src):
        value=urllib.parse.urljoin(BASE,src)
        if urllib.parse.urlparse(value).hostname not in ['cangku.moe','static.cangku.moe']:continue
        with client.open(urllib.request.Request(value,headers={'User-Agent':'Mozilla/5.0'}),timeout=35) as r:raw=r.read()
        report['public_script_sha256']=hashlib.sha256(raw).hexdigest()
        Path('evidence/site-app.js').write_bytes(raw)
Path('evidence/social-contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('Saved schemas only; no message/notification/comment writes',flush=True)
