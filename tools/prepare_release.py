"""Stage a public APK and its update manifest; never uploads keys or source archives."""
import hashlib,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
apk=ROOT/'output/Cangku-Xingyu-0.6.2-debug.apk'
public=ROOT/'cloudflare-chat/public'
releases=public/'releases';releases.mkdir(parents=True,exist_ok=True)
if not apk.is_file():raise SystemExit('Build the APK first')
if apk.stat().st_size>24*1024*1024:raise SystemExit('APK exceeds this release channel size limit')
shutil.copy2(apk,releases/apk.name)
manifest={'available':True,'package':'moe.cangku.reader','versionCode':8,'versionName':'0.6.2','notes':'新增长按图片识别二维码链接、作品与作者搜索切换、15项HTML代码提示，以及支持C++等17种语言的代码块插入。二维码本机识别，结果可复制或确认打开。','minSdk':26,'url':'https://xingyu-chat-ccjk45415.pages.dev/releases/'+apk.name,'size':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest()}
(public/'updates/android.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Staged APK + public update metadata:',apk.name,apk.stat().st_size,manifest['sha256'])
