"""Read-only contract probe. Credentials and cookies stay in process memory."""
import datetime, getpass, http.cookiejar, json, sys, urllib.error, urllib.parse, urllib.request
from pathlib import Path

BASE='https://cangku.moe'
jar=http.cookiejar.CookieJar()
client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
report={}
def request(path, body=None):
    headers={'User-Agent':'Mozilla/5.0', 'Accept':'application/json', 'Origin':BASE, 'Referer':BASE+'/login', 'X-Requested-With':'XMLHttpRequest'}
    for c in jar:
        if c.name=='XSRF-TOKEN': headers['X-XSRF-TOKEN']=urllib.parse.unquote(c.value)
    if body is not None: headers['Content-Type']='application/json'
    req=urllib.request.Request(BASE+path, data=None if body is None else json.dumps(body).encode(), headers=headers)
    try:
        with client.open(req, timeout=35) as response:
            raw=response.read()
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        print('HTTP_ERROR',e.code,e.read().decode()[:600],flush=True)
        raise
def shape(x, depth=0):
    if depth>3:return type(x).__name__
    if isinstance(x,dict):return {k:shape(v,depth+1) for k,v in x.items()}
    if isinstance(x,list):return [shape(x[0],depth+1)] if x else []
    return type(x).__name__
client.open(urllib.request.Request(BASE+'/login',headers={'User-Agent':'Mozilla/5.0'}),timeout=30).read()
print('ACCOUNT:',flush=True)
account=sys.stdin.readline().strip()
print('PASSWORD:',flush=True)
password=sys.stdin.readline().strip()
result=request('/api/v1/auth/login',{'login':account,'password':password,'remember':False,'include':'roles'})
account=password=None
print('LOGIN_CODE',result.get('code'),'DATA_SCHEMA',json.dumps(shape(result.get('data')),ensure_ascii=True),flush=True)
if result.get('code')!=0:sys.exit(1)
uid=result.get('data',{}).get('id')
paths={
 'me':'auth/me',
 'categories':'category/list?all=1&type=post',
 'feed':'post/list?page=1&per_page=3&include=user,categories:simple&simple=1&with[]=user&with[]=categories',
 'search':'post/search?search='+urllib.parse.quote('你的名字')+'&per_page=2&include=user,categories:simple&simple=1',
 'category':'post/list?category_in[0]=12&per_page=2&include=user,categories:simple&simple=1',
 'rank':'post/rank?year='+str(datetime.date.today().year)+'&date_type=daily&date_value='+str(datetime.date.today().timetuple().tm_yday)+'&per_page=2&include=user&simple=1',
 'article':'post/info?id=229794&include=user,tags,categories,favorited,upvoted',
 'comments':'comment/list?post_id=229794&per_page=3&include=user',
 'favorites':f'user/favoritePost?id={uid}&per_page=2&include=user,categories:simple&simple=1',
}
for key,path in paths.items():
    try:
        data=request('/api/v1/'+path)
        report[key]={'path':path.replace(str(uid),'{userId}') if key=='favorites' else path,'code':data.get('code'),'schema':shape(data),'pagination':data.get('meta',{}).get('pagination')}
        if key=='categories':report[key]['categories']=[{'id':v.get('id'),'name':v.get('name'),'children':[{'id':x.get('id'),'name':x.get('name')} for x in v.get('children',[])]} for v in data.get('data',[])]
        if key=='category':report[key]['returned_categories']=[[{'id':c.get('id'),'name':c.get('name')} for c in v.get('categories',[])] for v in data.get('data',[])]
        if key=='article':
            article=data.get('data',{})
            report[key]['content_sample']=article.get('content','')[:7000]
        print(key,json.dumps(report[key],ensure_ascii=True),flush=True)
    except Exception as e:report[key]={'error':type(e).__name__}
Path('evidence/api-contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('SAVED redacted contract',flush=True)
