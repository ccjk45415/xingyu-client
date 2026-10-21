本次同时更新手机与电脑客户端：**Android 0.6.2 / Windows 0.1.1**。

- 手机长按正文、资源预览和聊天图片识别二维码；Windows右键图片选择“识别二维码链接”。在本机解码，结果支持复制或确认打开。
- 搜索新增“作品 / 作者”切换，作者头像、昵称、UID及分页，点击进入作者主页。
- 投稿编辑器新增15项HTML代码提示，查看示例后可在光标处插入。
- 新增多语言代码块插入窗口，支持C++、C、Python、Java、JavaScript、TypeScript、Dart、Kotlin、Rust、Go、C#、HTML、CSS、JSON、SQL、Shell和纯文本。自动转义HTML字符，保留缩进与换行。

### 下载与使用

- 手机下载 `Cangku-Xingyu-0.6.2-debug.apk`，Android 8.0及以上，沿用前版测试签名，可覆盖升级。
- 电脑下载 `Xingyu-Windows-0.1.1-x64.zip`，**完整解压后运行 `Xingyu.exe`**，保留全部DLL和data目录；无须安装Flutter或模拟器。当前为未签名测试版。
- `Release-SHA256SUMS.txt` 为上述两个文件的SHA-256校验值。

两端共用网站账号及现有认证聊天服务。旧客户端仍可通过原入口检查更新。

### 开源与验证

自有代码以MIT许可证开源，包含Android、Flutter Windows和Cloudflare服务端源码；第三方许可另行保留。没有内置账号密码或管理密钥。

Flutter静态分析、15项默认测试、Android基础54项/社交14项、QR与代码块JVM53项、真实官网只读作者搜索、两个频道认证WSS/心跳、原生Windows自检和文件完整性检查通过。未替用户向官网投稿、评论或修改资料；手机长按及不同输入法仍需实际使用反馈。
