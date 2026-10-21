# 验证记录

最新日期：2026-10-22。

## Android 0.9.0 / Windows 0.4.0：原生可视化投稿、图片和官网模板

- 只读核对官网后台及当前脚本 SHA256：`4c80891d84d7b14a2e6fc2699abb2e2252f977d1d47d46befec13f45de9edf17`，与留存字节一致；确认图片响应 `data.url`、dlbox/iframe/collapse/poll/lottery 格式及权限条件。没有向官网创建测试投稿/投票、上传测试图或发送消息。
- 修复桌面上传回调仍处于busy时被插入守卫拒绝。真实PostEditor配合受控上传响应验证：等待中禁用编辑、完成后插图进入原选区、HTML与预览保留图片。两端增加账号、页面、正文版本保护。
- 正常模式与源码使用同一原始HTML。Android实际投影/模板/分页辅助类65项，既有编辑22项、扩展63项、core64项及social14项通过，全量Java编译及原签名APK构建通过。包含中文、emoji、段落、实体、图片、原属性/短代码保留、容量拒绝及代码示例不激活组件。
- Flutter静态分析无问题，52项通过、3项可选联网测试跳过。验证中文IME组合、上传busy回归、可视化/源码往返、图片布局不覆盖上下文、预览滚轮只移动预览、原下载附加字段与23条链接回填、投票创建/图片回调、账号切换在发送正文前中止。
- 已视觉检查正常编辑、下载/外链表单及预览滚动截图。图片为内存缓存合成示意图，没有真实用户图片、账号或消息。预览图片网络请求补齐官网Referer。
- 合并/嵌套表格保留源码并明确拒绝不安全的结构编辑；未提供合并/拆分单元格界面。原生编辑显示与完整预览可能有排版差异。Android完整界面、输入法与系统打印尚未真机验收；Windows打印导出使用清理后的独立HTML文件和系统浏览器。


Pages 已部署 `c227a102`，两端更新清单及公开下载SHA256核对通过；Windows原生引擎/DPAPI/防篡改/健康检查通过。此次只更新客户端与静态入口，未修改生产Worker及聊天数据库。

GitHub [v0.9.0](https://github.com/ccjk45415/xingyu-client/releases/tag/v0.9.0)已公开，源码提交 `b02fd739a9b4a618a2cc742137298e1008a75b1c`，312个源码文件；APK、完整Windows ZIP和校验文件三项匿名下载SHA256核对通过。源码与交付包扫描排除官网凭据及Cloudflare/GitHub/公告管理密钥。

## Android 0.8.0 / Windows 0.3.0：详细介绍、原图与逐段翻译

- DLsite手机版链接改读同一作品的官方电脑版详细介绍；真实提取RJ01726046的完整介绍2344字符和4张正文图片。桌面、生产Android AiClient/DOM解析器在JVM的结果一致；发布前复查时当前出口被来源站地区限制，无法再次取得介绍与实测图片加载；已加入明确地区错误提示，未绕过限制。未保存真实介绍正文。
- 内置固定翻译指令与JSON模式通过官方远程AI绑定的真实模型测试：两个中性英文片段完整返回中文及对应ID，未使用官网账号生成额度；没有处理或保存真实作品译文。临时本地探测服务已关闭。
- 服务端36组测试、Pages内部绑定/真实SQLite旧表兼容升级及原300人聊天室362项通过。完整任务预算原子预留、缺段拒绝、幂等、旧版失败一次补偿均验证。
- Android生产提取与翻译辅助类20项、原生DNS策略50项通过；逐段与插图顺序、Unicode长段拼接和缺段拒绝通过。手机完整UI未取得真机验收。
- Flutter验证详情优先于SEO/资料表、懒加载/段内图片顺序、长段无损拼接、自定义密钥隔离、中文原文不经过AI且不耗额度、窄窗与原编辑/二维码/聊天回归。静态分析无问题，29项通过、3项可选网络测试默认跳过；另加来源地区限制错误回归。结果及截图见ai-source-document-*、ai-translation-model-live及desktop-ai-faithful-original。

已部署翻译Worker版本 `c4ace08b-7ec3-453f-b3d0-aee3c760df56`，Pages部署 `d344cc53`；两端新更新清单与公开下载包SHA256核对通过。Windows真实原生引擎、DPAPI加密、防篡改及健康检查通过。

GitHub [v0.8.0](https://github.com/ccjk45415/xingyu-client/releases/tag/v0.8.0)已公开，源码提交 `308d1e5c909fedd6275fd7dddce4a7523423521a`，280个源码文件；APK、完整Windows ZIP及校验文件三项匿名下载SHA256全部通过。发布包排除Cloudflare/GitHub令牌、公告管理密钥及官网账号密码的检查通过。

## Android 0.7.1 / Windows 0.2.1：代理DNS误判修复

- 在当前真实代理环境复现www.dlsite.com被解析为198.18.5.104，旧版直接误判内网；经HTTPS公共DNS确认公开解析后，通过原代理提取用户提供的RJ01721474作品介绍和封面成功。测试不记录作品正文，也不调用AI。
- Android SourceNetworkRules 原样JVM回归50项，覆盖公网、Fake-IP需要核实、私网/混合/空结果拒绝；生产AiClient.checkSourceHost原样在JVM进行真实HTTPS核实并成功，org.json仅为测试替换成SHA256固定的JSON-java jar，未执行Android界面或HTML解析。见ai-source-network-native、native-live及live报告。
- Flutter静态分析无问题，25项测试通过/3项可选网络测试默认跳过；另单独运行真实DLsite代理提取测试通过。覆盖来源DNS核实、域名关联、私网/混合解析和缓存，不降低HTTPS验证。
- Android完成原签名覆盖升级包构建，Windows完成原生引擎发布构建；客户端修复，无需修改生产Worker和聊天数据。手机完整UI未取得真机验收。

GitHub [v0.7.1](https://github.com/ccjk45415/xingyu-client/releases/tag/v0.7.1)和原更新入口已发布，Pages部署4d5fa226。两端公开下载与GitHub三项匿名资产下载均核对SHA256成功，源码提交 `9f875bb01d0b7732b5362cdf7c612c8e0882f64c`。

## Android 0.7.0 / Windows 0.2.0：AI投稿与手机工具栏

- 服务端AI请求白名单、任务结构、来源、短正文、个人/全局额度、同UID并发、幂等重放与错误信息隔离通过；完整Node28组、真实Pages内部绑定/SQLite/300用户回归357项通过。
- 线上通过公共Pages入口认证，提取公开Steam作品、真实Cloudflare AI生成一次草稿、重复结果不再次扣次数，随后撤销临时认证。未发布官网投稿或真实聊天消息，未保存测试账号或生成内容。见ai-live-validation.json。
- Flutter覆盖HTTPS接口规范、私网来源拒绝、HTML转义、来源关联、自定义长正文、直连密钥/无Cookie隔离、重定向拒绝及加密配置/窄窗组件；沿用Android基础54、社交14、编辑22和二维码53项检查。手机分组工具栏完成编译，尚无本次真机UI结果。
- 密钥保存分别复用独立Android Keystore/Windows DPAPI存储。内置部署新增v5 SQLite DO与AI绑定，保留原聊天和公告数据；发布前扫描排除管理/账号凭据并验证两端包哈希。

GitHub [v0.7.0](https://github.com/ccjk45415/xingyu-client/releases/tag/v0.7.0)与原更新入口已发布。Flutter静态分析无问题，23项测试通过、2项可选联网测试默认跳过；Windows真实引擎/DPAPI自检通过。GitHub匿名下载APK、Windows ZIP和校验文件均核对成功；源码提交 `9cf637ffaaed320bbf72c30732ab512337a165d4`。部署、版本与SHA256见release-0.7.0.json和github-release.json。

## Android 0.6.3 / Windows 0.1.2：独立图标工具栏

- 两端移除HTML提示按钮及其菜单，39项功能直接以同一风格图标呈现。手机GridLayout按宽度换行并提供长按名称，桌面Wrap支持悬停提示；代码块使用文档/代码图标，HTML源码与预览开关另列。
- 新增正文选区字号12–48px与独立编辑字号10–28；颜色、背景色、对齐、上下标、源码缩进、格式清除、日期、字面查找/替换及撤销重做。保留全部原提示功能和17种语言代码块。HTML特殊字符仍处理为实体，源码与预览不执行代码。
- 编辑操作保留选区，纯文本转HTML映射位置；撤销恢复文字、选区及HTML模式，输入750ms合并、最多50步和累计200万字符。全部替换预计算长度，超过100万字符拒绝，避免先分配巨大结果。
- Android编辑规则JVM22项通过，覆盖选区、中文/转义、反向选区、占位文字、格式切换、列表、缩进边界、字面替换、超限拒绝、合并输入/重做失效及字体样式标记；基础54项、社交14项继续通过。
- Flutter静态分析无问题；18项默认测试通过、2项专用联网测试默认跳过。实际组件验证段落/加粗/字号、撤销重做、编辑字号不改正文、查找替换可一次撤销、代码块、宽1440及960窗口；完整保留前版二维码和作者搜索测试。截图见desktop-editor-toolbar和desktop-editor-toolbar-compact。
- Android原生阅读和预览加入字号Span处理，不修改发布源码；已编译，尚未取得真机效果验收。连接设备安装无Internet权限的独立测试APK在30秒后超时，没有运行设备UI测试；已确认独立测试包不存在，原客户端未安装或更改。详见editor-device-validation。
- APK0.6.3/code9，467584字节，SHA256 `2ae0400d19effdf2f500470c0cc73e146baea2f06857fdcfe4977ec19a0f3210`，完整构建和原签名一致验证通过。Windows0.1.2/build3真实引擎发布构建、中文路径DPAPI/篡改拒绝/健康自检通过；ZIP14238006字节，SHA256 `2dfe03b70dd000d587d386a791850018752cd28a36a101e562c29f38d9fee032`。
- Pages部署 `5df20a4a`，两端更新清单、下载大小及SHA256核对通过；未改Worker、公告、数据库或官网资料/投稿。源码和发布包继续扫描排除网站凭据、Cloudflare/GitHub OAuth及公告密钥。

GitHub v0.6.3已发布，公开源码提交 `1db58f5c9bd0e4385667c782e8af7c8ec35c9ab3`；匿名下载APK、Windows ZIP及校验文件后哈希核对通过，结果见github-release.json。

结果见 `evidence/editor-android-validation.json`、`editor-device-validation.json`、`release-0.6.3.json`；Windows使用细节见desktop/README.md。

## Android 0.6.2 / Windows 0.1.1：二维码、作者搜索与投稿辅助

- Android原生长按正文/资源预览/聊天图片，Windows正文、查看器和聊天图片右键菜单识别二维码；后台本机解码，先显示结果，再由用户复制或打开链接。非链接文本只显示与复制，不自动执行或导航。
- 实际Android QrDecoder的JVM测试53项通过：UTF-8中文链接与文本、旋转/反色、普通文字、危险scheme不允许打开、空白与非法尺寸；Java生成合成二维码交叉验证Dart实现，PNG/JPEG/WebP和UTF-8通过。Dart charset适配修复依赖中Int8List导致UTF-8出现替换字符的问题，不修改依赖缓存。
- 投稿辅助新增15项HTML提示和17种语言的代码块窗口，含C++；转义特殊字符、保留换行缩进；Android阅读/预览额外适配pre标签空白。测试用合成代码验证转义与模板选择，不向官网发帖。
- 作者搜索按官网user/list接口分页，结果显示头像、昵称、UID并进入作者主页。真实官网只读测试验证本人昵称可查回同UID；两频道认证WSS及心跳继续通过，临时认证结束后撤销，无生产消息或内容写入。
- Flutter静态分析通过；15项默认测试通过、2项专用联网测试默认跳过。覆盖右键菜单、识别结果复制、放大查看器确认打开站内作品、作者分页/主页、HTML插入、C++代码插入和既有导航/聊天布局。合成截图见desktop-author-search、desktop-html-hints、desktop-code-dialog。
- Android基础54项、社交14项通过；0.6.2/code8完整构建、资源、D8、zipalign、v2/v3签名通过，证书与0.6.1一致。455296字节，SHA256 `f477ef2ea5c678948ed34249ca047c943f3c3604c2b685746c13bb3b8960c2f7`。ZXing3.5.4 jar从Maven Central按固定SHA256下载，完整Apache许可证随APK分发。
- Windows0.1.1/build2原生发布构建与中文路径DPAPI/篡改拒绝/健康自检通过。ZIP14215300字节，SHA256 `4f4de63df6867256adca7864e58ef2f62b4ba8dd0fa9669aa9d2ba6873fb903a`。
- Pages部署 `0c22438c`，两端更新清单与下载哈希核对通过。此轮只发布静态资源，后台与数据库未改。开源自有代码采用MIT，第三方许可另行保留；交付扫描排除真实网站账号密码、Cloudflare/GitHub OAuth令牌及公告密钥。
- 手机长按手势与不同品牌输入法尚未真机验收，Windows系统选择器/多显示器等仍有前版人工验收限制；没有替用户执行官网发布、评论或资料写操作。代码块提供语言标记和排版，不是代码执行或在线编译器。

详见 `evidence/qr-android-validation.json`、`qr-dependency.json`、`release-0.6.2.json` 与 `desktop-native-validation.json`。

## Windows 0.1.0 / build 1

- Flutter 3.47.7 stable、Dart 3.13.5、MSVC 19.44、Windows SDK 10.0.26100.0，生成真实 x64 Win32 Runner、Flutter Windows 引擎与 Dart AOT 发布包；不需要安卓模拟器。包含 VC++ 运行库和全部 data 文件。
- `flutter analyze` 无问题；默认 Flutter 测试10项通过、2项专用联网测试默认跳过。布局覆盖1440及960宽度、登录/发现/分类/排行/阅读/作者/设置/资料/安全/通知/评论/投稿编辑与管理/认证聊天/私信、深色阅读及跨页频道草稿。截图使用合成作品与账号，见 `evidence/desktop-*.png`。
- 实际发布 EXE 在中文安装路径运行 `--self-check`，原生引擎、DPAPI写入读取、磁盘密文无明文、篡改后拒绝解密、应用数据目录和公网protocol3健康检查通过。完整ZIP解压后再次运行通过；仅使用随机临时测试文件/键。见 `desktop-native-validation.json`、`desktop-package-native.json`。
- 真实 Dart SiteApi/ServiceApi 验证官网登录及文章、评论、收藏、通知、投稿等只读接口；临时认证身份的两个频道 WSS 和心跳通过，结束后撤销令牌。未修改官网内容或资料，未发送生产聊天室/私信消息，凭据未写入文件。见 `desktop-live-validation.json`。
- 本机 Pages内部绑定→真实workerd/SQLite DO：22组Node测试、349项运行时检查及现有JVM传输通过，包括300认证连接、第301拒绝、资料同步、图片权限、隔离和幂等；实际 Dart ChatController/ServiceApi 加入双频道、艾特、引用、图片、私信、切换与暂停恢复验证。全部使用本机合成身份，见 `desktop-transport.json`。
- ZIP `Xingyu-Windows-0.1.0-x64.zip`，14,088,378字节，SHA256 `6d262b2749e9bbb02577767fd2a670323c0f79ec7c34545ece8662471cc9468d`。Pages部署 `adbb651a`，公网Windows清单、ZIP大小与哈希核对通过；只部署静态Windows资源，没有改Worker、公告或数据库。安卓仍为0.6.1/code7，公网APK哈希与原包一致。见 `desktop-release.json`。
- Windows更新清单独立，用户主动下载校验后退出并解压更新；没有后台消息推送。Windows用户绑定DPAPI保存自愿保持登录的网站会话和聊天令牌；账户密码不保存。
- 系统文件选择器、中文输入法、多显示器和Windows10交互尚需用户实际使用反馈；未以真实账号执行投稿、评论、资料与安全设置写操作。组件和协议测试不等于所有Windows设备人工验收。本包当前未签名。

Windows完整源码在 `desktop/`，使用和构建说明见 `desktop/README.md`；源码包同时保留Android与Cloudflare服务端。

## 0.6.1 资料同步修复与作品详情滚动条

- 原因：官网个人资料保存后只更新本机账号资料；聊天服务仍使用首次认证的昵称/头像，历史消息也读取发送时的快照。
- 新增已认证身份的资料同步接口，固定官网auth/me校验，不接收自报昵称或UID，不更换/延长令牌。APP保存资料后触发；进入聊天室/私信及回到聊天室前台检查官网资料（无变化时60秒内合并检查）。资料变化才调用云端同步；每UID每天20次、全站与开通共用1000次验证额度。
- 认证聊天室发布profile事件，在线两个频道刷新头像/名字；历史消息和引用作者使用最新已验证资料。正文中的艾特文字保留发送原文。仅作品详情页新增持续显示的右侧滚动条，内容不超出屏幕时系统不显示滑块；聊天室和私信滚动条行为未改动。
- 22组Node测试通过，新增身份冒用拒绝、原令牌和到期时间不变、配额测试；本机Pages/workerd/DO联调346项通过，覆盖双频道资料广播、改名后历史及引用刷新、随后新消息的新昵称，以及原有300连接、图片隔离、回复、撤销和JVM传输。
- 基础54项、社交14项及关闭/切页14项回归通过。完整APK构建、对齐、v2/v3签名通过，0.6.1/code7，与0.6.0同签名；180782字节，SHA256 `b0987883c3cd7fb28227593fd90b1738503b36b4d8e0c6f52451fe19130be531`。
- 已部署Worker `ce9668ad-5ad2-4ec0-8dca-d92553025f48`及Pages `9d0cc5e8`。公网健康、更新清单、APK下载哈希、公告快照/心跳和匿名权限拒绝通过；现有公告密钥及绑定保留。
- 公网资料同步只核验当前资料，不修改官网昵称/头像、不发送聊天/私信消息。结果见evidence/private-deployment.json。没有实机验收作品详情滚动条或改名交互。

## 0.6.0 认证聊天、图片、艾特、回复和实时公告（历史记录）

2026-10-21用户授权发布。本版versionCode6、协议3，已上线。

- 完整APK构建、zipalign、v2/v3签名通过，176686字节，SHA256 `e5a60807e5e565be1d4e338efce9513e4d9570a104c607cf3237715ca039075e`。与0.5.0签名证书一致，可覆盖升级。
- 基础54项、社交14项、连接关闭/切换14项回归通过；21组Node测试通过。
- 本机Pages内部绑定 → 真实workerd/DO SQLite，300个认证连接、第301拒绝、身份伪造拒绝、频道隔离、艾特、引用回复、图片权限及过期、令牌撤销、确切Android/JVM传输共338项通过。全部使用合成身份与数据，没有访问官网或向生产发送消息。
- 公告实际DO及Android/JVM链路20项通过，覆盖3个订阅者、UTF8、发布后实时广播、快照、心跳。生产公告接口及实时快照/心跳已验收，缓存禁止有效；独立管理密钥已通过官方OAuth配置，授权的无效请求被400拒绝且公告版本不变，匿名发布401。没有写入生产公告。
- Worker最终版本 `016b394c-9ea2-427d-818a-af9c64850699`，Pages部署 `b7071c98`。保留v1/v2数据及绑定，新增公告v3和认证频道v4；旧匿名频道不迁入认证频道。
- 公网固定官网身份验证成功；两个频道WSS正确返回认证身份并通过心跳，退出后令牌401。未发送公共或私信消息。匿名注册410、未认证媒体401通过。完整媒体收发和隔离在本机验证，没有用真实用户消息测试图片投递。
- 公网健康protocol3、更新清单code6、APK下载大小及SHA256通过。凭据只在进程内使用，公告管理密钥不进入APP/源码交付包。
- 真机图片选择/预览、艾特与引用交互、轮播手势、UID复制、设置及覆盖安装仍未实机验收；本机测试不能替代真机UI检查。
- 当前每UID图片10张/日、全站100张/日、活动存储64MiB，聊天室与私信共享。消息/已发图片7天可读，未发送图片1小时失效。未开通付费套餐或购买域名。

当前结果见 `evidence/release-0.6.0.json`、`verified-media-validation.json`、`cloudflare-public.json`、`private-deployment.json`、`cloudflare-deployment.json`。

## 0.5.0 评论、通知、私信与聊天室修复（历史记录）

- `python tools/test_core.py`：54项原有检查 + 14项社交通知路由/评论归属断言通过。
- `python tools/test_chat_lifecycle.py`：14项关闭生命周期回归通过，覆盖阻塞TLS关闭不阻塞点击线程、重复关闭、同时关闭、RuntimeException、阻塞read解除和旧代发送/回调拒绝。主线程TLS close是与用户触发条件吻合的源码推断，尚未取得真机崩溃堆栈。Android官方异常语义见 https://developer.android.com/reference/android/os/NetworkOnMainThreadException 。
- 官网只读登录检查`user/comment`、`user/unreadNotificationCount`、`user/notification`回复和点赞、`announce/list`、嵌套评论及用户搜索，均code0；只保存字段类型于evidence/social-contract.json，未保存正文/私人通知内容。评论写入、删除、点赞和通知已读按发布脚本实现，未对真实官网写入。
- `node --test test/dm.test.mjs test/entry.test.mjs test/policy.test.mjs`：14组通过。私信使用真实SQLite验证双方权限、第三人隔离、伪造sender拒绝、nonce绑定、先拉取再已读、拒收、7天期限、限额、分页、Cookie和原始token不入库。
- `node test/dm-runtime.integration.mjs`：真实workerd + DO SQLite本机28项通过；网站请求与生产消息均为0。
- 0.5.0 / code5，minSdk26/target35，完整资源/Java/D8/zipalign/v2-v3签名通过，保留原测试签名。
- 发现可用Android 13调试设备，但streaming及no-streaming APK安装均未完成、已终止；未确认应用启动。不能将编译、本机协议测试当作手机界面/切页/输入法验收。
- 公网身份验证已成功：通过Pages内部绑定→DmHub→固定官网登录会话验证，UID一致，me和peer正确；退出后token返回401。结果见evidence/private-deployment.json，无生产私信、凭据不落盘。
- 私信客户端发送确认不推进接收游标，避免在轮询间隔收到的新消息因自己的后发消息ID更大而漏读。分页/页面与后台回调使用代次隔离；仍需手机确认交互体验。

- 最终0.5.0已部署Worker（a5a6ef73-5c0d-47e6-b93c-90af6589e5ee）和Pages（4bd4eded），保留原公共聊天室namespace，新增DmHub SQLite。
- Pages入口本机300客户端/20条合成消息/319项检查通过（14784ms）；14组组合Node测试及确切Android/JVM WebSocket传输检查通过。
- 公网两个频道WSS/心跳/证书验证通过，未发送公共消息。更新清单versionCode5、160302字节APK、SHA256 `1aefa8675bb136d306e52bf5a93c3fc005617d57ad1c2168889b8985943af1a0`下载核对通过。
- 旧0.4.0与新0.5.0的签名证书SHA256完全一致；可覆盖升级。交付包包含新的匿名化社交契约及测试结果，排除真实凭据。

## 0.4.0 Cloudflare 版本（历史记录）

- `python tools/test_core.py`：54项阅读、编辑、频道与来源边界断言通过。
- `python tools/test_cloudflare.py`：4项边界策略测试、真实JVM/Android传输协议测试、319项本机集成断言通过。一次性建立300个真实TCP WebSocket连接，20条合成消息按频道广播，第301连接被拒绝；包含幂等重试、心跳、身份伪造拒绝、频道切换和更新包哈希检查。
- `evidence/cloudflare-validation.json` 记录本机结果，不含用户令牌或消息数据。
- APK资源、Java、D8、对齐和v2/v3签名验证通过。版本0.4.0 / code4，minSdk26，targetSdk35，继续使用旧测试签名。
- Wrangler dry-run通过；官方OAuth授权account:read、user:read、workers_scripts:write、pages:write和默认offline_access。管理凭据在忽略的.toolchain中，不进入APK或交付包。
- Cloudflare已接收xingyu-chat Worker、SQLite Durable Object绑定、版本元数据及APK静态资源。原workers.dev在电脑和用户手机上均连接被关闭，已部署Pages入口，通过内部服务绑定访问Worker。用户确认新入口健康检查在手机可以打开。
- `python tools/test_cloudflare.py --pages`：入口函数与后台在同一临时运行时通过内部服务绑定连接，300个真实WebSocket客户端与319项断言通过；结果见evidence/cloudflare-entry-validation.json。2项入口路由测试也已单独通过。
- `python tools/check_chat_deployment.py`：公网新入口的健康检查、版本4元数据、127534字节APK下载和SHA-256通过。`evidence/cloudflare-deployment.json`记录完整性。
- 公网WSS分别验证两个频道的握手和心跳，证书验证保持开启；仅创建两个技术检测身份，未向任何频道发送聊天消息、未读取聊天历史。结果见evidence/cloudflare-wss.json。
- 最终入口：https://xingyu-chat-ccjk45415.pages.dev/ 。后台的预览URL已关闭。工具默认迁移意外创建的同名多余Worker已清理，并通过Cloudflare API code10007确认不存在；同名Pages项目和原xingyu-chat后台保留。
- `python tools/check_delivery.py`：交付包路径排除、真实OAuth访问/刷新令牌未混入交付、APK内置入口解码结果、更新文件大小与哈希一致性检查通过。源码包不含SDK、构建缓存、签名私钥、聊天数据库或管理凭据。
- 尚未在实体安卓设备验证聊天室、更新下载安装、输入法适配和网络切换。未向公网聊天室发布测试消息，未进行公网300客户端压测。

下面为0.3版及此前的历史记录。

## 历史已完成

- 正常账号登录，之后 `auth/me` 认证读取成功。
- 实际读取首页、分类树、按分类筛选、关键词搜索、日榜、文章、评论及收藏列表，响应 `code=0`。
- 修正分类接口参数：使用 `category_in[0]`，实际返回总数与全站列表不同，响应分类包含目标分类。
- 用真实文章的下载短代码验证资源标题、提取说明、多链接与 HTML 实体处理。
- `python tools/test_core.py`：54 项断言全部通过，覆盖原有阅读/编辑行为，以及两个频道的响应过滤、切换后旧响应失效和独立聊天服务地址边界。
- `python tools/build_apk.py`：资源编译、Java 17 编译、D8 转换、APK 对齐、签名成功。
- `apksigner verify --verbose`：APK 签名验证通过，v2/v3 已验证。
- 包信息：`moe.cangku.reader`，版本 `0.3.0` / versionCode 3，minSdk 26，targetSdk 35；与上一版使用相同签名。
- 应用没有 WebView；网络、图片解码、HTML 文本与导航使用 Android 平台 API。
- 只读验证当前用户权限、资料 meta、等级、投稿计数、自己的各状态列表及自己的文章编辑字段，均返回成功。
- 投稿编辑与资料表单已完成编译检查，图片使用系统文件选择器，不额外申请相册读取权限。
- `python tools/test_chat.py`：12项服务端测试通过，覆盖两个用户自由切换、频道历史隔离、只唤醒同频道长轮询、发送幂等、并发重试、身份伪造拒绝、令牌过期、持久化和限流。
- `python tools/smoke_chat.py`：临时启动仅监听127.0.0.1的真实服务，两个HTTP客户端完成7项检查，测试后已停止服务；结果见 `evidence/chat-validation.json`。
- 五个底部导航入口统一为28dp图标占位、24dp图标、3dp间距、17dp文字区域、11sp单行文字，去掉字体额外上下留白。已做代码和编译检查，未做手机截图核验。

## 未验证 / 局限

- 未安装到连接的个人安卓设备，尚无实机运行截图与 UI 自动化验证。0.5.0安装尝试超时，不能将编译成功当作实机功能全部通过。
- 发布/编辑/审核提交、回收站删除恢复、图片上传、个人资料保存、更改邮箱密码以及收藏评论写入均未对真实账号执行。实现依据发布脚本，仍需用户主动使用时检查结果。
- Android Keystore 加密会话恢复、网络中断后恢复、不同 Android 厂商与不同屏幕尺寸尚未实机验证。
- 文章中的二维码图片可以显示、复制和外部打开，未实现离线二维码解码；复杂网页互动组件使用官网原文入口。
- 这是调试证书签名的客户端，管理范围为当前账号自己的投稿。未迁移网站管理员的全站管理流程。
- 旧Python聊天服务及其Docker/Caddy配置未部署。当前使用已经部署并公网验收的Cloudflare后端。
- 安卓聊天室页面、输入法显示、手机网络切换与加密身份恢复尚未实机验证。

最终 APK 和源码包的 SHA-256 位于 `output/SHA256SUMS.txt`。
