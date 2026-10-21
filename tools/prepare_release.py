"""Stage a public APK and its update manifest; never uploads keys or source archives."""
import hashlib,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
apk=ROOT/'output/Cangku-Xingyu-0.9.0-debug.apk'
public=ROOT/'cloudflare-chat/public'
releases=public/'releases';releases.mkdir(parents=True,exist_ok=True)
if not apk.is_file():raise SystemExit('Build the APK first')
if apk.stat().st_size>24*1024*1024:raise SystemExit('APK exceeds this release channel size limit')
shutil.copy2(apk,releases/apk.name)
manifest={'available':True,'package':'moe.cangku.reader','versionCode':13,'versionName':'0.9.0','notes':'修复上传正文图片未插入；新增原生可视化编辑与HTML源码双向切换，保留图片和排版；下载卡片、外部链接等按官网格式填写；Windows本机预览支持独立滚轮滚动。','minSdk':26,'url':'https://xingyu-chat-ccjk45415.pages.dev/releases/'+apk.name,'size':apk.stat().st_size,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest()}
(public/'updates/android.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Staged APK + public update metadata:',apk.name,apk.stat().st_size,manifest['sha256'])
