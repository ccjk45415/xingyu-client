# 仓库 · 星屿

cangku.moe 的非官方 Flutter Android、Windows 与 macOS 客户端，三个平台共享 Dart 业务代码。支持浅色/深色主题、手机布局与桌面侧栏。Android 8+ ARM64（目标 API 36）、Windows x64、macOS 12+ Apple Silicon。

Android 0.6.1修复改名后聊天室资料不同步，并为作品详情页增加右侧滚动条。0.6.0加入统一设置、作者UID复制、首页实时公告轮播，以及仓库认证聊天室、聊天室/私信图片、@和引用回复；详细说明见[0.6.0修改说明](docs/PENDING_CHANGES.md)。

当前版本：**Android 0.13.0 / Windows 0.7.0 / macOS 0.3.0**。新增应用外通知与启动更新提醒，优化热更新与动态。见[更新记录](CHANGELOG.md)与[安装说明](docs/RELEASE-INSTALLATION.md)。

## 下载

| 平台 | 版本 | GitHub下载 |
| --- | --- | --- |
| Android 8.0及以上 | 0.13.0 | [APK安装包](https://github.com/ccjk45415/xingyu-client/releases/download/v0.13.0/Cangku-Xingyu-0.13.0-arm64.apk) |
| Windows x64 | 0.7.0 | [完整免安装ZIP](https://github.com/ccjk45415/xingyu-client/releases/download/v0.13.0/Xingyu-Windows-0.7.0-x64.zip) |
| macOS 12+ M 系列 | 0.3.0 | [PKG 安装包](https://github.com/ccjk45415/xingyu-client/releases/download/v0.13.0/Xingyu-macOS-0.3.0-arm64.pkg) / [DMG](https://github.com/ccjk45415/xingyu-client/releases/download/v0.13.0/Xingyu-macOS-0.3.0-arm64.dmg) |

[全部发布记录与校验文件](https://github.com/ccjk45415/xingyu-client/releases)。Android可覆盖前一版本；Windows完整解压后运行 `Xingyu.exe`，保留全部DLL和data文件夹。Android 沿用原签名；Windows 尚未进行代码签名，macOS 使用 ad-hoc 签名且尚未公证，首次安装可能需要系统安全确认。

## 消息提醒

在“我的 → 设置 → 通知”启用应用外通知，支持私信、聊天室艾特/回复、作品/评论回复和点赞。默认隐藏正文预览。Android 使用系统定期检查，最短周期 15 分钟，可能受省电、网络与代理影响；强行停止后需重新打开。电脑端需保持程序运行。详情与测试边界见 [通知与权限说明](docs/NOTIFICATIONS.md)。

新版在发现后续完整安装包时提示一次，可选择“立即更新”或“暂时不更新”。当前旧 Windows 基础包的补丁引擎初始化异常，仍需手动进入检查更新或下载新版；新基础包已增加中文路径兼容初始化。

## 诊断信息

两端均可在「我的 → 设置 → 诊断信息」查看、复制和清空本机异常记录；登录页也提供入口。最多保留10条异常，不自动上传，不记录密码、会话、API Key、请求正文或异常消息。Windows 记录通过当前用户的 DPAPI 加密保存。诊断不能保证捕获系统强制结束、断电或所有原生引擎崩溃。

## Windows 桌面版

Flutter Desktop **0.7.0 / Windows x64** 已制作，采用原生 Windows 引擎与重新设计的侧栏、封面网格和宽屏阅读/聊天布局。完整解压 `output/Xingyu-Windows-0.7.0-x64.zip` 后运行 `Xingyu.exe`。复用现有网站账号和认证聊天服务，支持评论通知、投稿管理、图片、艾特和引用回复。详见 [Windows 使用与构建说明](desktop/README.md)。Windows 版本及更新清单与安卓独立。

[下载 Windows 0.7.0 x64 免安装包](https://xingyu-chat-ccjk45415.pages.dev/releases/Xingyu-Windows-0.7.0-x64.zip)（约37.4 MiB）。

## Android 安装

安装包：`output/Cangku-Xingyu-0.13.0-arm64.apk`。使用与上一版相同的测试签名，可覆盖升级。

安装后输入自己的仓库账号密码。项目、安装包与交付压缩包不包含预置账号、密码或登录 Cookie。默认仅在本次进程内保持会话；勾选“保持登录”后，会话通过 Android Keystore 的 AES-GCM 密钥加密保存。密码始终不写入磁盘。

这是供自行安装、测试使用的调试证书签名版本。正式发布应使用你自己保管的发布签名密钥；请不要使用调试证书上架。


## 开源与许可证

应用与服务端自有代码采用 [MIT许可证](LICENSE)；第三方许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。这是非官方客户端，与网站运营方无隶属关系；开源范围不含网站内容、用户消息、账号凭据、SDK或签名密钥。克隆后请使用自己的账号；自行部署服务时请修改两端服务地址及Cloudflare项目配置。

## AI投稿助手

读取详细介绍与正文图片，AI只逐段翻译成中文，不概括、不补写、不生成标签；图片按原顺序以HTTPS链接导入。已是中文可跳过AI直接原样带入，不消耗次数。修复“AI草稿字段错误”，不再精简/截断介绍。内置每UID每日3个任务、共享16份翻译批次预算，超出预算明确提示使用自定义AI。密钥设备加密保存并直连提供商。预览后选择导入，不自动发表；详见[完整流程与限制](docs/AI_ASSISTANT.md)。

## 功能

- 原生账号登录、会话恢复、过期提醒与本地退出。
- 首页封面网格、分页、刷新。
- 搜索可在作品与作者列表之间切换；作者结果显示头像、昵称和UID并支持分页。
- 手机长按、Windows右键图片识别二维码，识别结果先展示，再复制或主动打开链接。
- 投稿编辑器支持可视化与源码切换、官网模板及AI助手：格式、标题、列表、引用、链接、图片、表格、代码、正文字号、颜色、高亮、对齐、上下标、缩进、清除格式、日期、查找替换、编辑字号及撤销重做；手机按常用/排版/插入/更多分组，按钮显示中文名称，长按查看说明；桌面悬停查看名称。
- 17种语言代码块插入（含C++），自动处理HTML特殊字符并保留换行与缩进。
- 正文字号写入选区排版；编辑字号只改变当前输入区，保存在本机。撤销历史仅当前编辑过程保留，最多50步且有内存上限。
- 主分类和子分类浏览，关键词搜索与分类筛选。
- 日榜、周榜、月榜，按站点的上海时区计算日期。
- 原生文章阅读、正文图片、作者主页、作者投稿；作品详情页右侧持续显示滚动条（内容可滚动时）。
- 官网收藏列表、收藏及取消收藏。
- 作品详情底部直接显示原生评论，完整列表及子回复分页，发布、回复、点赞/取消，确认后删除自己的评论。
- “我的评论”与官网同步，支持关联作品、讨论定位和删除管理。
- “通知”展示回复、点赞、系统公告及未读数量，单条/全部已读由用户操作后同步。
- 独立私信：选择昵称或UID搜索收信人、作者主页私信按钮、会话未读、分页历史、失败幂等重试和拒收名单；双方需安装并开通。
- 文章下载短代码转为资源卡片，链接复制、二维码图片查看、外部应用打开。
- 按账号隔离的本地阅读历史，明暗主题与正文字号设置。
- 站内文章链接打开、系统分享菜单。
- 原生新建和编辑投稿，纯文本 / HTML 源码、格式工具、图片与下载卡片、本机预览。
- 按账号隔离的本机草稿自动保存与恢复；云端草稿、发布、提交审核和定时发布。
- 投稿管理：已发布、定时、草稿、待审核、退回、回收站；搜索、退回说明、删除到回收站和恢复。
- 原生个人资料编辑：昵称、简介、性别、网站、所在地、头像和空间背景。
- 系统图片选择器、上传前预览、头像居中裁剪、EXIF 方向修正、压缩上传。
- 更改绑定邮箱、修改密码；保存成功后清除本机会话并重新登录。
- 账号积分与经验记录。
- 底部导航：**首页 / 分类 / 排行 / 聊天室 / 动态 / 我的**，六个图标使用相同占位尺寸，文字使用相同字号、固定高度和基线。
- 原生聊天室：频道一、频道二，两者消息、历史游标、当前输入和失败重试分别维护，可随时切换。
- 聊天室绑定仓库账号后进入，显示官网昵称、UID与头像；点击名字或头像艾特，支持引用回复；聊天室与私信支持图片。
- 作者UID点击复制；统一设置入口；首页发现/公告左右轮播，在线公告独立更新，无需再升级APP。
- 每日自动检查更新，“我的 → 设置 → 检查更新”手动入口；用户选择下载后校验文件、包名、版本、签名，交给系统确认安装。

## 聊天室的启用

Cloudflare 版本使用 Workers Free、SQLite Durable Objects、Pages 免费入口和支持休眠的 WebSocket。固定服务入口已内置并混淆，用户需先验证绑定仓库账号。混淆不能使公开服务地址真正保密。

当前入口：https://xingyu-chat-ccjk45415.pages.dev/ 。原 workers.dev 在电脑和用户手机上均遇到连接关闭，因此改由 Pages 内部服务绑定连接后台。新入口的公网健康检查、更新文件完整性、两个频道WSS握手和心跳已通过；用户已确认手机可以打开新入口的健康检查。未开通付费套餐、未购买域名。

- 当前服务端包：`output/Xingyu-Cloudflare-Server.zip`；说明见 [cloudflare-chat/README.md](cloudflare-chat/README.md)。旧 `chat-server/` 是0.3版长轮询实现，不是当前APP的部署目标。
- 两个频道共用300连接上限，各自广播和查询历史；同一身份同一时间保留一个连接。
- 单条300字，3秒一条、每分钟15条，每个聊天身份每天200条、全站每天10000条；额度北京时间08:00重置，历史可见7天。
- 聊天室和私信共享官网认证，7天有效；验证每IP每天20次、每UID每天20次、全站每天1000次（含失败）。旧匿名身份不能进入新版聊天室。
- 认证时临时转发当前官网会话到固定auth/me验证，服务不保存官网Cookie或密码；服务仅存令牌哈希，本机令牌由Android Keystore加密。HTTPS/WSS不是端到端加密。
- 图片每UID每天10张、全站100张、活动存储64MiB上限，聊天室/私信共用；已发图片7天可读，未发送附件1小时失效。仅使用现有SQLite存储，不接入付费图床。
- APP仅在聊天室前台接收消息，退出页面/进入后台断开；没有后台推送。频道输入草稿仅在当前进程内保留；历史每次30条，界面最多显示最近300条。
- 免费平台额度仍可能耗尽；本机300连接测试通过不等于公网300人稳定性或永久免费保证。未开通付费套餐。
- 0.3版没有检查更新功能，需先手动安装0.4版；此后新版可以通过APP检查和下载安装。APK使用静态下载地址，校验SHA-256以及现有安装签名。

当前正文由 Flutter HTML 组件和原生媒体引擎渲染，支持正文图片、AVIF 与默认静音的视频；不使用网页容器渲染整个站点。复杂互动组件仍可使用文章末尾的原文入口。图片二维码可长按在本机识别，识别结果支持复制或确认打开。

上述新增功能在“我的”页面进入。编辑已有投稿保留原始 HTML 和短代码；提交前检查文章版本与内容指纹，发现网站内容已变化时要求重新载入。本机草稿仅保存在当前设备的应用私有目录，不会自动提交网站。选择图片并确认上传后，图片会发送至网站；个人资料表单仍需点击保存。

二次验证配置、站外社区、画廊及管理员对其他用户内容的审核操作仍使用官网。当前投稿管理只面向自己账号的内容，没有添加永久删除入口。

## 0.5.0 修复与私信

聊天室切换导航、频道或退后台时，先使旧连接与回调失效，再由后台线程关闭 TLS/socket，避免界面线程关闭连接引起网络线程异常。已测试阻塞关闭、重复关闭、旧发送回调以及300客户端本机联调；尚无手机崩溃堆栈，也未完成实体设备安装验收。

私信与聊天室共用仓库认证，消息与官网通知分开。第一次开通需要用户主动选择“验证官网身份”：当前官网 Cookie 通过 HTTPS 临时交给自己的 Cloudflare 服务，仅向固定的 `https://cangku.moe/api/v1/auth/me` 验证；拒绝跳转、身份不一致、待二次验证及封禁/禁言状态。服务器不保存 Cookie、密码、官网完整响应或原始私信令牌，只保存验证后的UID、昵称、头像和令牌哈希。本机私信令牌使用独立 Android Keystore 密钥加密，退出账号会清除并尝试撤销。

双方都需开通，身份7天后重新验证。未开通作者会明确显示不可收信，不会冒充已送达。消息仅双方可读取，服务端仍可读取明文；HTTPS并非端到端加密。私信只在前台每20秒检查，不提供系统推送。

每条最多500字、3秒间隔、每分钟15条、每身份每天100条，全站私信每天2000条，每天最多主动联系10位用户。开通验证每IP每天20次（失败也计数），全站每天1000次；额度北京时间08:00重置。消息可见7天，后台分批清理，物理删除可能延后。持续轮询仍会消耗Cloudflare免费请求额度，不能保证300人全天持续使用仍不超额。

官网评论、回复、点赞及标记通知已读的写接口依照发布脚本实现，没有替真实账号执行这些写入。公网已验证私信身份开通及令牌撤销，未发送生产私信。

## 当前 Flutter 构建

Flutter 3.47.7 / Dart 3.13.5，客户端业务代码位于 `desktop/lib/`。执行 `python tools/build_flutter_android.py` 构建同包名安卓客户端，`python tools/build_desktop.py` 构建 Windows，再执行 `python tools/prepare_desktop_release.py --test-only` 打包完整 ZIP。Mac 需在 Apple Silicon Mac/Xcode 上执行 `python3 tools/build_macos.py --native-check`，详见 [Mac 构建说明](docs/MACOS-BUILD.md)。构建脚本不自动部署，正式发布资源由 `tools/stage_release.py` 准备。

## 旧 Java 引擎构建（保留历史源码）

Android UI、网络、图片解码使用系统平台 API；二维码本机识别使用ZXing core 3.5.4，不内置浏览器或WebView。提供标准 Android Gradle 工程，可直接在 Android Studio 中打开；插件版本 8.9.1、JDK 17、compileSdk 35。

本次安装包使用下面的可复现脚本构建，无需安装 Android Studio 或 Gradle；构建脚本会从Maven Central下载并校验固定版本ZXing依赖：

```powershell
# Python 3 + JDK 17；JAVA_HOME 可指向自己的 JDK。
python tools/prepare_toolchain.py
python tools/test_core.py
python tools/test_qr.py
python tools/test_editor.py
python tools/test_chat_lifecycle.py
python tools/build_apk.py
```

`prepare_toolchain.py` 从 Google 官方 SDK 仓库下载 Windows Build Tools 35.0.0、Android 35 平台和 Platform Tools，核对官方仓库声明的校验值，保存到项目内的 `.toolchain/`。不会修改系统 PATH。构建脚本依次执行 aapt2、javac、D8、zipalign 和 apksigner。默认 JDK 路径为 `C:/Program Files/Java/jdk-17`。

源码交付包不含 SDK 和生成的签名私钥。再次构建时会在本地生成新的调试私钥；使用不同签名覆盖旧版本前需要卸载旧 APP（会清除它的本地数据），或继续使用同一工作目录中保留的私钥。

## 验证与接口依据

- `docs/INVESTIGATION.md`：分析范围、接口、证据与局限。
- `docs/VALIDATION.md`：构建、测试及实机验证结果。
- `evidence/api-contract.json`：实际只读 API 响应的字段类型，不含账号、Cookie 或会话值。
- `tests/CoreTest.java`：URL 边界和真实下载短代码解析测试。
- `evidence/management-contract.json`：管理、个人资料和投稿状态的只读接口契约。
- `evidence/chat-validation.json`：临时本机监听器、两个实际 HTTP 客户端联调结果，不含令牌或消息数据。
- `tests/test_chat_server.py`：服务端频道隔离、长轮询、幂等、身份和持久化测试。

源码中的发布、编辑、删除恢复、资料保存及账号安全操作均由用户在相应界面主动确认后执行。分析阶段仅登录并读取数据，没有发布稿件、修改已有投稿、改动资料或更改密码。写入流程依据网站实际发布脚本实现，尚未用真实写入操作验证，也尚未实机验证。

## 目录

```text
app/src/main/java/moe/cangku/reader/
  MainActivity.java   原生页面、导航和交互
  Ui.java             主题、卡片、图标、星空渐变
  ApiClient.java      站点 API、Cookie、错误处理
  SessionStore.java   设备密钥加密与过期感知 Cookie 存储
  ImageLoader.java    限流、内存缓存、采样图片解码
  ReaderContent.java 下载短代码解析
  UrlPolicy.java     接口来源和可打开链接边界
  LocalLibrary.java  阅读历史与外观设置
  AuthoringScreens.java 投稿编辑、管理和账号表单
  AuthoringRules.java 原文保留、选择范围和上海时区时间处理
  ChatScreens.java    两频道原生聊天界面和前台收发
  ChatClient.java     独立聊天室登录与历史 HTTP 传输
  ChatSocket.java     校验TLS与握手的WebSocket传输
  ChatVault.java      加密保存独立聊天身份
  ChatRules.java      频道隔离、过期响应和服务器地址边界
  ServiceEndpoint.java 公开服务地址混淆
  AppUpdates.java    更新检查、校验、下载及系统安装入口
  UpdateProvider.java 仅共享已验证APK的只读内容提供器
```

不包含网站后端源代码。网站接口变动、网络访问限制及账号权限可能影响使用。

构建配置参考：[Android Gradle Plugin 8.9 官方说明](https://developer.android.com/build/releases/agp-8-9-0-release-notes)、[Android 官方 SDK 工具](https://developer.android.com/studio#command-line-tools-only)。

## 0.6.1 资料同步

保存昵称或头像后，已开通的聊天身份自动向固定官网auth/me重新验证资料；仅更新当前UID资料，不新建或延长认证令牌。进入聊天室/私信或回到聊天室前台时检查官网资料（正常检查至少间隔60秒），资料未变时不调用服务端同步。同步成功后在线频道更新昵称/头像，历史消息和引用作者按最新资料显示；正文里已经发送的艾特文字保留原文。资料同步每UID每天最多20次，与认证共用全站每天1000次验证额度；失败会保留现有身份并提示重试。
