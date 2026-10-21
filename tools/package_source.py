"""Create a clean source delivery without SDKs, keys, build caches or credentials."""
import hashlib, json, zipfile, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output';OUT.mkdir(exist_ok=True)
archive=OUT/'Cangku-Xingyu-source.zip'
files=[ROOT/x for x in ['.gitignore','README.md','LICENSE','THIRD_PARTY_NOTICES.md','CHANGELOG.md','build.gradle','settings.gradle','gradle.properties','announcements.example.json','discovery.example.json']]
for folder in ['docs','tests','tools','app/src']:
    files += [p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
files.append(ROOT/'app/build.gradle')
for base,dirs,names in os.walk(ROOT/'desktop'):
    dirs[:]=[d for d in dirs if d not in ['build','.dart_tool','.idea','ephemeral','.git','__pycache__']]
    for name in names:
        p=Path(base)/name
        if p.suffix not in ['.iml','.log'] and name!='.flutter-plugins-dependencies':files.append(p)
server_files=[p for p in (ROOT/'chat-server').iterdir() if p.is_file() and p.name!='.env']
files+=server_files
cloud_files=[ROOT/'cloudflare-chat'/x for x in ['package.json','package-lock.json','wrangler.jsonc','README.md']]
for folder in ['src','test','public']:
    cloud_files += [p for p in (ROOT/'cloudflare-chat'/folder).rglob('*') if p.is_file() and p.suffix not in ['.apk','.zip']]
files+=cloud_files
entry_files=[p for p in (ROOT/'cloudflare-entry').iterdir() if p.is_file()]
files+=entry_files
files += [ROOT/'evidence'/x for x in ['api-contract.json','toolchain-sources.json','management-contract.json','chat-validation.json','cloudflare-validation.json','cloudflare-entry-validation.json','cloudflare-deployment.json','cloudflare-wss.json','cloudflare-public.json','social-contract.json','private-deployment.json','private-validation.json','chat-lifecycle-validation.json','verified-media-validation.json','release-0.6.0.json','release-0.6.1.json','release-0.6.2.json','release-0.6.3.json','release-0.7.0.json','release-0.7.1.json','release-0.8.0.json','release-0.9.0.json','release-0.9.1.json','release-0.9.2.json','emoji-layout-device-validation.json','emoji-layout-validation.json','github-release.json','comment-media-contract.json','comment-media-validation.json','comment-media-android-validation.json','home-discovery-validation.json'] if (ROOT/'evidence'/x).is_file()]
files += [p for p in (ROOT/'evidence').glob('desktop-*') if p.suffix in ['.json','.png']]
files += [p for p in (ROOT/'evidence').glob('qr-*') if p.suffix=='.json']
files += [p for p in (ROOT/'evidence').glob('ai-*') if p.suffix=='.json']
files += [p for p in (ROOT/'evidence').glob('editor-*') if p.suffix=='.json']
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(set(files)):z.write(p,Path('Cangku-Xingyu')/p.relative_to(ROOT))
sums=[]
server_archive=OUT/'Xingyu-Chat-Server.zip'
with zipfile.ZipFile(server_archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(server_files):z.write(p,Path('Xingyu-Chat-Server')/p.name)
cloud_archive=OUT/'Xingyu-Cloudflare-Server.zip'
with zipfile.ZipFile(cloud_archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(cloud_files):z.write(p,Path('Xingyu-Cloudflare-Server/cloudflare-chat')/p.relative_to(ROOT/'cloudflare-chat'))
    for p in sorted(entry_files):z.write(p,Path('Xingyu-Cloudflare-Server/cloudflare-entry')/p.name)
    for name in ['cloudflare.py','prepare_cloudflare.py','prepare_pages.py','publish_announcement.py','publish_discovery.py']:
        z.write(ROOT/'tools'/name,Path('Xingyu-Cloudflare-Server/tools')/name)
    z.write(ROOT/'announcements.example.json',Path('Xingyu-Cloudflare-Server/announcements.example.json'))
    z.write(ROOT/'discovery.example.json',Path('Xingyu-Cloudflare-Server/discovery.example.json'))
    z.write(ROOT/'docs/PENDING_CHANGES.md',Path('Xingyu-Cloudflare-Server/docs/PENDING_CHANGES.md'))
    for p in (ROOT/'cloudflare-chat/public/releases').iterdir():
        if p.suffix not in ['.apk','.zip']:continue
        z.write(p,Path('Xingyu-Cloudflare-Server/cloudflare-chat/public/releases')/p.name)
    z.writestr('Xingyu-Cloudflare-Server/README.md', '''# 星屿 Cloudflare 服务端交付包\n\n包含已经验收的后台、Pages入口和Android/Windows静态资源，不含授权令牌、签名私钥或聊天数据库。需要自行安装Node.js 22+和Python3。\n\n在本目录执行：\n\n```powershell\npython tools/prepare_cloudflare.py\npython tools/cloudflare.py install\npython tools/cloudflare.py login --device --browser=false --scopes account:read user:read workers_scripts:write pages:write\npython tools/cloudflare.py deploy --keep-vars\npython tools/publish_announcement.py configure\npython tools/prepare_pages.py\npython tools/cloudflare.py --cwd ../cloudflare-entry pages deploy --branch main\n```\n\n当前账号的项目已经创建，更新时无需重复创建。若用于其他账号，需要修改项目名、入口域名和版本元数据；APK内置地址也必须在完整源码工程中重新构建。\n\n完整源码工程还提供本机300连接测试、APK构建及后续版本发布脚本。详细限制见cloudflare-chat/README.md。\n''')
deliveries=[OUT/'Cangku-Xingyu-0.9.2-debug.apk',archive,server_archive,cloud_archive]
if (OUT/'Xingyu-Windows-0.4.1-x64.zip').is_file():deliveries.append(OUT/'Xingyu-Windows-0.4.1-x64.zip')
for p in deliveries:
    digest=hashlib.sha256(p.read_bytes()).hexdigest();sums.append(digest+'  '+p.name)
    print(p.name,p.stat().st_size,digest)
(OUT/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n',encoding='ascii')
