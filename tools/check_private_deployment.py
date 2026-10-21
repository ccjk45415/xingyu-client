"""Explicit identity verification smoke check. No messages; secrets remain in process memory."""
import hashlib,http.cookiejar,json,sys,urllib.request,urllib.parse,urllib.error,subprocess,shutil
from pathlib import Path
SITE='https://cangku.moe';SERVICE='https://xingyu-chat-ccjk45415.pages.dev'
jar=http.cookiejar.CookieJar()
site=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
service=urllib.request.build_opener(NoRedirect())
def web(path,data=None):
    h={'User-Agent':'Mozilla/5.0','Accept':'application/json','Origin':SITE,'Referer':SITE+'/','X-Requested-With':'XMLHttpRequest'}
    for c in jar:
        if c.name=='XSRF-TOKEN':h['X-XSRF-TOKEN']=urllib.parse.unquote(c.value)
    if data is not None:h['Content-Type']='application/json'
    with site.open(urllib.request.Request(SITE+path,headers=h,data=None if data is None else json.dumps(data).encode()),timeout=35) as r:
        raw=r.read()
    return json.loads(raw) if path!='/login' else None
def dm(path,data=None,token=None):
    h={'User-Agent':'XingyuChat/1','Accept':'application/json'}
    if data is not None:h['Content-Type']='application/json'
    if token:h['Authorization']='Bearer '+token
    with service.open(urllib.request.Request(SERVICE+'/dm/v1/'+path,headers=h,data=None if data is None else json.dumps(data).encode()),timeout=35) as r:return json.loads(r.read())
print('Verifying current user only; credentials read from stdin, never retained',flush=True)
account=sys.stdin.readline().strip();password=sys.stdin.readline().strip()
web('/login');login=web('/api/v1/auth/login',{'login':account,'password':password,'remember':False});account=password=None
assert login.get('code')==0
uid=login['data']['id']
request=urllib.request.Request(SITE+'/api/v1/auth/me');jar.add_cookie_header(request)
cookie=request.get_header('Cookie');assert cookie
session=dm('session',{'site_cookie':cookie,'expected_user_id':uid})
assert session['user']['id']==uid and len(session['token'])==64
token=session['token']
try:
    synced=dm('profile/sync',{'site_cookie':cookie},token);assert synced['user']==session['user'];cookie=None
    assert dm('me',token=token)['user']['id']==uid
    assert dm('peer?id='+str(uid),token=token)['available']
    probe=subprocess.run([shutil.which('node'),'cloudflare-chat/test/verified-public-wss.mjs'],input=json.dumps({'token':token,'uid':uid}),text=True,capture_output=True,timeout=55)
    if probe.returncode:raise RuntimeError('Verified public WebSocket check failed (credentials omitted)')
    wss=json.loads(probe.stdout)
finally:
    cookie=None
    assert dm('logout',{},token)['ok']
try:dm('me',token=token);raise AssertionError('Revoked token accepted')
except urllib.error.HTTPError as e:assert e.code==401
token=session=None
result={'origin':SERVICE,'identity_verification':'pass','profile_sync':'pass (no website changes)','fixed_upstream':'https://cangku.moe/api/v1/auth/me','token_revocation':'pass','verified_wss':wss,'public_messages_sent':0,'credentials_saved':False}
Path('evidence/private-deployment.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result),flush=True)
