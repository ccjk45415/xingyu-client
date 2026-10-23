# macOS Apple Silicon 安装包

目标：Flutter Desktop，同一份 Dart 业务代码，macOS 12+、M 系列 Mac。版本 0.1.1 (2)，包标识 moe.cangku.xingyu.macos。

## 安装产物

构建生成 Xingyu-macOS-0.1.1-arm64.pkg（双击安装向导）及同版本 .dmg（拖动到“应用程序”）。与安卓和 Windows 一起在 v0.11.0 Release 发布，Mac 独立更新清单为 `/updates/macos.json`；构建本身不触发部署。

当前构建使用 ad-hoc 签名，没有 Apple Developer ID 签名或公证。macOS 首次安装/打开可能要求“系统设置 → 隐私与安全性”确认；不会要求关闭 Gatekeeper 或系统完整性保护。正式免提示分发需要后续配置开发者签名、公证，当前没有植入任何 Apple 账号或证书。

## 平台适配

- 原生 AppKit 窗口、标准 Mac 菜单、系统字体与 Menlo 等宽字体，M 系列 arm64 主程序。
- 登录会话、聊天令牌和自定义 AI 配置通过 macOS 登录钥匙串保存，不回退到明文文件。
- 支持评论图片粘贴及上传，仍使用官网图床；保留 1 MB 与像素/编码大小限制。
- 支持系统手动 HTTP/HTTPS 代理和 VPN/TUN 路由；自动 PAC 脚本不在此桥接中执行。
- 搜索/编辑使用 Command 修饰键，返回为 Command+[；Windows 保留 Ctrl / Alt 快捷键。
- 原生视频、AVIF、图片放大、二维码、缓存、AI 投稿、关注/动态等继续使用共享实现。
- macOS 仅请求自己的更新清单；下载、校验后自动打开系统 PKG 安装器，不会下载 Windows 或安卓更新。

## 本机或云端编译

在 Apple Silicon Mac 安装 Xcode、CocoaPods 和 Flutter 3.47.7 后：

```sh
python3 tools/build_macos.py --native-check
```

脚本执行平台专项和核心测试、编译、Mach-O arm64/版本检查、应用签名检查、临时钥匙串读写及本机目录自检，最后生成 PKG、DMG、SHA-256 清单与构建报告。临时诊断不使用真实官网密码，不发帖或发消息。`--check-only` 仅验证工程配置，不能证明已生成 Mac 程序。

`.github/workflows/macos-test.yml` 由 macos-test 分支推送或手动触发，使用标准 macos-15 Apple Silicon runner 和只读 contents 权限，构建附件保留 7 天，不自动创建 Release。正式发布另行上传完整 PKG/DMG；GitHub 官方 workflow 授权已完成，无需在源码中保存密钥。

参考：[Flutter macOS 配置](https://docs.flutter.dev/platform-integration/macos/setup)、[平台构建与权限](https://docs.flutter.dev/platform-integration/macos/building)、[GitHub 标准 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。
