# Flutter 安卓与动态性能测试

当前只制作本机测试包。没有上传安装包、推送源码、修改更新清单或部署后端。

## 安装

- 安卓：`output/Xingyu-Android-Flutter-0.10.0-test-arm64.apk`，适用于 Android 8.0+、ARM64 手机，应用名称「星屿 Flutter 测试」。
- 测试包使用独立包名 `moe.cangku.reader.fluttertest`，可以与现有原生版共存。原版账号、草稿和设置不会被改写，请保留原版。测试版需要重新登录；本次没有迁移原版私有数据。
- Windows：`output/Xingyu-Windows-0.4.9-x64.zip`，完整解压后运行 `Xingyu.exe`。
- 安卓测试包暂不接入正式更新通道，避免下载成原生安卓客户端。Windows 正式清单仍为旧版。

## 重点测试

1. 登录、记住登录、退出与重新打开；自定义 AI 配置能否保存。
2. 六个底部导航：主页、分类、排行、聊天室、动态、我的。返回键、键盘遮挡、横竖屏切换。
3. AI 投稿助手：提取作品链接、原标题/RJ号、中文翻译、分类和自购证明，导入后核对正文与图片。
4. 正常模式打字、选中文字编辑链接、上传正文图片、长正文内外滚动、源码切换和草稿恢复。
5. 评论表情、1 MB 以内图片上传；手机只支持上传图片，粘贴仍为文字。作品图片点击放大、双指缩放、长按识别二维码。
6. 聊天室两个频道、头像、艾特、回复、发图和私信。后台返回及切换频道应能恢复；同一 UID 同时只有一个聊天室连接，原版与测试版同时进聊天室可能互相断开。
7. 动态首次进入、切换作者、返回动态、刷新、继续查找、取消关注及切换账号。
8. 我的 → 设置 → 诊断信息，可查看/复制本机异常；无自动上传。

## 动态优化

- 首批投稿到达即显示，不再等待三页完成后一起显示。
- 后两页并行补齐，刷新时保留现有内容。
- 关注列表与已完成动态页在内存缓存 60 秒，最多保留 12 个动态页；重复请求合并。
- 可下拉刷新或点击刷新。改变关注关系、退出登录及失效认证会清空缓存；旧请求不得跨账号回填。
- 沿用现有接口。全部动态仍按官网最新投稿扫描每次最多 3 页，可以继续向前查找；并未增加不存在的官网批量作者接口。

## 代码与构建

手机与电脑共用 `desktop/lib` 的业务与界面代码；`desktop/android` 提供 Android 宿主。Android 使用 Keystore AES-GCM 加密会话与 AI 密钥，Windows 沿用 DPAPI。

Android 使用系统文件选择器，无需整个相册/存储权限；HTML 导出使用系统文档保存器。VPN 路由由系统处理，另读取 Android 显式 HTTP 代理，回到前台时重新读取。没有内置浏览器。

```powershell
python tools/prepare_flutter_android.py
# 使用 SDK Manager 接受标准 SDK 许可并准备 NDK 28.2.13676358/CMake 3.22.1。
python tools/build_flutter_android.py
# 合成账号、假接口，不向真实网站投稿或发消息：
python tools/build_flutter_android.py --device-test <adb-device-id>
python tools/build_desktop.py
python tools/prepare_desktop_release.py --test-only
```

构建工具在 ASCII 临时目录准备源码与 SDK/依赖，绕过 Windows CMake/Ninja 中文路径问题。只输出本机成品，未执行任何发布命令。

实际用户的 Android 16 三星设备仍需本人验收；本机设备验证不能代替该机型实测。

## 本次检查结果

- Flutter 全量回归：106 项通过，3 项真实账号/本地服务测试按既有条件跳过；最终图片组件自适应修改后，编辑器与手机页面专项 10 项通过。
- 静态检查：无问题。手机布局按 360/412 宽度检查了导航、阅读、作者、投稿、AI、设置、通知和私信等页面。
- Windows release 引擎自检：DPAPI 往返、篡改拒绝、应用目录、Unicode 路径和公开服务 health 通过，没有网站投稿或发消息。
- Android release APK 已生成；校验 ARM64 Flutter/AOT 运行库、版本/包名、原测试签名与 16 KB ZIP 对齐。
- 连接的 Android 13 设备安装集成测试 APK 时没有返回；停止等待后，非流式安装也在 45 秒内未完成。集成测试未进入应用，不能报告实机通过。测试暂存 APK 已清理。
- 线上 Android 0.9.10 / Windows 0.4.7 清单未修改；未上传、未部署、未推送 GitHub。
