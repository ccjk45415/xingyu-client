"""Stage a complete Flutter Windows bundle and independent update manifest. No deployment."""
import hashlib,json,os,shutil,struct,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output';OUT.mkdir(exist_ok=True)
version='0.4.1';code=8
bundles=[ROOT/'desktop/build/windows/native-x64/runner',ROOT/'desktop/build/windows/x64/runner/Release']
bundle=next((p for p in bundles if (p/'Xingyu.exe').is_file()),None)
if bundle is None:raise SystemExit('Build the Windows release first')
for path in ['Xingyu.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data/app.so','data/icudtl.dat','data/flutter_assets/NOTICES.Z']:
    if not (bundle/path).is_file():raise SystemExit('Incomplete Windows bundle: '+path)
exe=(bundle/'Xingyu.exe').read_bytes();offset=struct.unpack_from('<I',exe,0x3c)[0]
assert exe[:2]==b'MZ' and exe[offset:offset+4]==b'PE\0\0' and struct.unpack_from('<H',exe,offset+4)[0]==0x8664,'Expected native x64 PE'
files=[p for p in bundle.iterdir() if p.is_file() and p.suffix in ['.exe','.dll']]+[p for p in (bundle/'data').rglob('*') if p.is_file()]
archive=OUT/f'Xingyu-Windows-{version}-x64.zip';prefix=Path(f'Xingyu-Windows-{version}')
usage='''仓库 · 星屿 Windows 0.4.1（Flutter Desktop / x64）

完整解压后，双击 Xingyu.exe 运行。不要只复制 EXE：请保留全部 DLL 与 data 文件夹。
无需安装 Flutter 或安卓模拟器。本包已包含 VC++ 运行库，当前为未签名测试版本。

使用自己的仓库账号登录。密码不保存在电脑；保持登录的会话与聊天令牌使用当前 Windows 用户绑定的 DPAPI 加密。
桌面与安卓共享网站账号和聊天服务。聊天室需认证；同一 UID 同时只保留一个聊天室连接。
私信双方需开通认证，官网网页不会收到这些独立私信。消息和已发图片保留7天；每 UID 每日图片10张，与安卓共用额度。

左侧导航：发现、分类、排行、聊天室、我的。设置包含资料、安全、主题/字号和 Windows 更新。
Ctrl+K 搜索；Alt+← 返回；聊天 Enter 发送 / Shift+Enter 换行；编辑器 Ctrl+S 保存本机草稿。

更新时退出旧程序，再解压完整新版目录运行；本机阅读记录和草稿保留在 Windows 用户应用数据目录。
程序没有内置任何账号、密码、官网 Cookie、Cloudflare 管理凭据或发布密钥。
Flutter与依赖的许可信息在 data/flutter_assets/NOTICES.Z，Flutter引擎许可另见 LICENSE.flutter.txt。
'''
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(files):z.write(p,prefix/p.relative_to(bundle))
    z.writestr((prefix/'使用说明.txt').as_posix(),usage)
    z.writestr((prefix/'VERSION.json').as_posix(),json.dumps({'product':'moe.cangku.xingyu.desktop','platform':'windows-x64','versionName':version,'versionCode':code},indent=2))
    license=Path(os.environ.get('FLUTTER_ROOT','C:/codex-tools/flutter'))/'LICENSE'
    if license.is_file():z.write(license,prefix/'LICENSE.flutter.txt')
if archive.stat().st_size>24*1024*1024:raise SystemExit('ZIP exceeds this free static release channel file size limit')
public=ROOT/'cloudflare-chat/public';(public/'releases').mkdir(exist_ok=True);shutil.copy2(archive,public/'releases'/archive.name)
metadata={'available':True,'product':'moe.cangku.xingyu.desktop','platform':'windows-x64','versionCode':code,'versionName':version,'notes':'优化了一些已知问题','url':'https://xingyu-chat-ccjk45415.pages.dev/releases/'+archive.name,'size':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
(public/'updates/windows.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'archive':archive.name,'bytes':metadata['size'],'sha256':metadata['sha256'],'runtime_files':len(files),'platform':'windows-x64'},ensure_ascii=False))
