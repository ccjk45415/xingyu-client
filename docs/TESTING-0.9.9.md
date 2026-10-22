# Android 0.9.9 / Windows 0.4.6 本机测试

2026-10-22：修复投稿正文编辑框滚动条未初始化造成的绘制异常。用户提供 Android 16 / API 36 / 三星 SM-S9480 / 0.9.8 的 View.onDrawScrollBars 空指针日志。

根因：程序创建的 EditText 默认未必建立滚动条 Drawable，后续 setVerticalScrollBarEnabled(true) 只修改标记；setScrollbarFadingEnabled(false) 强制滚动条为 ON，第一帧绘制对 null 的 scrollBar.mutate() 调用引发异常。初始化与测量本身可以成功，故 0.9.8 的早期检查没有覆盖故障。独立 Android 13 探针增加真实 Canvas 绘制后，用原始生产类复现相同调用链。

修复：使用 ScrollableEditor 原生样式，在 View 构造阶段启用 vertical / fadeScrollbars=false / insideInset，交由框架同步初始化绘制对象。正文仍能内滚动；没有关闭滚动条，也没有捕获绘制异常来掩盖错误。同样的初始化方式应用于 AI 素材输入框。仅使用公开构造函数及资源属性，兼容 minSdk 26，无隐藏 API。

## 手机验收

安装 output/Cangku-Xingyu-0.9.9-debug.apk，无需卸载旧版。依次检查：

1. 我的 → 投稿与管理 → 新建投稿，等待数秒，再滚动整个表单。
2. 输入或粘贴多段长正文，在正文内部上下滑动。
3. 切换 HTML 源码和正常模式，检查内容保留。
4. 进入已有投稿编辑，检查长正文、图片、链接编辑和滚动。
5. 打开 AI 投稿助手，在作品素材框粘贴长内容并滚动。

不需向官网提交测试文章。若仍异常，重开 APP 后复制诊断发给开发者。

## 已完成验证

- 原始 0.9.8 生产类在 Android 13 临时进程中完成创建/布局后，Canvas 绘制触发 ScrollBarDrawable.mutate 空指针；与用户日志的 View.onDrawScrollBars 首帧失败一致。记录见 evidence/scrollbar-original-repro.txt。
- 修改后使用实际 0.9.9 APK 资源和生产类检查：表单绘制、空正文绘制、长正文绘制与 scrollBy 位移、HTML 模式绘制和源码保留、AI 素材框绘制、初始化失败恢复及重试全部通过。
- 使用合成 UID、内存偏好和进程内设置服务模拟，不安装/替换连接设备的真实客户端，不访问官网、不保存账号或写入生产内容。已清理设备临时探针与资源文件。
- 完整 Android 源码/资源编译、原生富文本 79 项回归、诊断隐私检查通过；原签名 APK 构建及包内容/凭证检查通过。
- 尚未在用户的 Android 16 三星手机上实测；完整真实 Activity 窗口生命周期仍待用户验收。

Windows 0.4.6 保持不变，后台无需修改。安装包仅本机，未上传、未修改线上更新入口、未推送源码或发布 GitHub Release。等待用户测试确认后再发布。

后续更新说明严格保持：优化了一些已知问题。
