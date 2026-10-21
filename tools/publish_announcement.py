"""Validate locally, configure a private server key, or publish announcement DATA only.

Nothing happens on import. No APK builds, Worker deploys, or client update metadata writes.
"""
import argparse,json,re,secrets,subprocess,sys,urllib.error,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ORIGIN='https://xingyu-chat-ccjk45415.pages.dev'
KEY=ROOT/'.toolchain/announcements/admin.key'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None
def load(path):
    value=json.loads(Path(path).read_text(encoding='utf-8-sig'))
    if not isinstance(value,dict) or set(value)!={'items'}:raise ValueError('文件只应包含items字段')
    items=value['items']
    if not isinstance(items,list) or len(items)>10:raise ValueError('最多保留10条公告')
    seen=set();result=[]
    for item in items:
        if not isinstance(item,dict) or set(item)!={'id','title','content'}:raise ValueError('每条公告需要id/title/content')
        ident=item['id']
        if not isinstance(ident,str) or not re.fullmatch('[a-zA-Z0-9_-]{1,64}',ident) or ident in seen:raise ValueError('公告ID无效或重复')
        seen.add(ident)
        for key,limit in [('title',80),('content',5000)]:
            if not isinstance(item[key],str) or not item[key].strip() or len(item[key])>limit or re.search('[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]',item[key]):raise ValueError('公告标题或正文无效')
        result.append({k:item[k].strip() for k in ['id','title','content']})
    return result
def request(path,data=None,key=None):
    headers={'User-Agent':'XingyuAnnouncementPublisher/1','Accept':'application/json','Cache-Control':'no-cache'}
    if key:headers['Authorization']='Bearer '+key
    if data is not None:headers['Content-Type']='application/json; charset=utf-8'
    req=urllib.request.Request(ORIGIN+path,headers=headers,data=None if data is None else json.dumps(data,ensure_ascii=False).encode('utf-8'))
    with urllib.request.build_opener(NoRedirect()).open(req,timeout=20) as response:return json.loads(response.read(262144))
def configure():
    KEY.parent.mkdir(parents=True,exist_ok=True)
    if not KEY.exists():
        with KEY.open('x',encoding='ascii') as f:f.write(secrets.token_hex(32)+'\n')
    secret=KEY.read_text(encoding='ascii').strip()
    if not re.fullmatch('[a-f0-9]{64}',secret):raise ValueError('本机公告发布密钥格式无效')
    result=subprocess.run([sys.executable,str(ROOT/'tools/cloudflare.py'),'secret','put','ANNOUNCEMENTS_ADMIN_KEY'],input=secret+'\n',text=True,encoding='utf-8',errors='replace',capture_output=True,cwd=ROOT)
    if result.returncode:raise RuntimeError('Cloudflare密钥配置失败；请检查官方OAuth登录状态后重试（密钥未输出）')
    print('公告发布密钥已配置；仅保存在本机忽略目录和Cloudflare服务端，不进入APP。')
def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='command',required=True)
    for name in ['validate','publish']:sub.add_parser(name).add_argument('file')
    sub.add_parser('configure');args=parser.parse_args()
    if args.command=='configure':configure();return
    items=load(args.file)
    if args.command=='validate':print('PASS 公告格式：',len(items),'条；未连接或修改线上服务。');return
    if not KEY.is_file():raise ValueError('公告发布尚未配置。功能获准部署后先运行configure；本次不会自动配置或部署。')
    secret=KEY.read_text(encoding='ascii').strip()
    if not re.fullmatch('[a-f0-9]{64}',secret):raise ValueError('公告发布密钥格式无效')
    current=request('/announcements');revision=current['revision']
    result=request('/announcements/publish',{'items':items,'base_revision':revision},secret)
    if not result.get('ok'):raise RuntimeError('公告发布未被确认')
    latest=request('/announcements')
    if latest.get('revision')!=result['revision'] or latest.get('items')!=items:raise RuntimeError('公告已提交，但随后内容已变化，请读取最新公告确认')
    print('公告数据已发布并校验，版本',latest['revision'],'；已通知在线首页，未构建或发布客户端。')
if __name__=='__main__':
    try:main()
    except urllib.error.HTTPError as e:raise SystemExit('公告服务返回HTTP '+str(e.code)+'；未自动重试覆盖。')
    except Exception as e:raise SystemExit(str(e))
