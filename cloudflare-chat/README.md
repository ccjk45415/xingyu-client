# 星屿 Cloudflare 聊天服务（0.6.1）

使用 Workers Free + SQLite Durable Objects + Pages 免费入口 + 静态资源。固定两个频道，APP 通过支持休眠的 WebSocket 接收当前频道消息；退出页面或进入后台就关闭连接。两个频道共享一个协调对象，以便原子地限制总在线人数和全站额度。

当前入口 https://xingyu-chat-ccjk45415.pages.dev/ 已通过公网健康、更新清单、APK哈希、两个频道WSS握手和心跳检查，用户确认手机可打开健康检查。原workers.dev入口不可达，因此Pages通过内部服务绑定调用xingyu-chat后台，手机不需要访问workers.dev。

## 部署

根目录执行：

```powershell
python tools/prepare_cloudflare.py
python tools/cloudflare.py install
python tools/cloudflare.py login --device --browser=false --scopes account:read user:read workers_scripts:write pages:write
python tools/build_apk.py
python tools/prepare_release.py
python tools/test_cloudflare.py --pages
python tools/cloudflare.py deploy --keep-vars
python tools/publish_announcement.py configure
python tools/prepare_pages.py
python tools/cloudflare.py --cwd ../cloudflare-entry pages deploy --branch main
```

登录使用官方 OAuth 设备授权，不要求把密码或 API Key 放入项目。凭据保存在忽略交付的 `.toolchain/cloudflare-auth/`。`wrangler.jsonc` 只部署 `xingyu-chat`，Pages配置在同级`cloudflare-entry/`，不升级付费套餐。需要 Node.js 22+、Java 17 和项目的 Android SDK。

首次创建Pages项目时使用 `python tools/cloudflare.py --cwd ../cloudflare-entry pages project create xingyu-chat-ccjk45415 --production-branch main`。务必使用Pages配置目录；当前Wrangler可能将普通Pages创建命令自动迁移为Workers，无法获得所需的pages.dev入口。

## 默认限制

- 两个频道合计最多300条在线连接，每个聊天身份同时保留一个连接。切换频道不创建新身份。
- 每条纯文本消息最多300个 Unicode 字符；3秒一条，每分钟最多15条；每个身份每天最多200条，全站每天最多10000条。
- 每日额度在北京时间08:00重置，与 Cloudflare UTC 用量窗口对齐。
- 连续一分钟内的重复内容会被拒绝。相同发送 ID 重试返回原消息，不重复写入、不重复扣减额度。
- 最近7天历史可读，按30条翻页。后台每小时最多清理500条过期消息；可见期限严格为7天，物理删除可能稍后完成。
- 仓库认证每IP20次/日、每UID20次/日、全站1000次/日，失败也计数；现有令牌重连不计入认证次数。
- 聊天室和私信共用7天仓库认证，服务端只保存令牌哈希；消息的昵称、UID和头像由服务端验证结果生成，禁止匿名注册及自报身份。
- 认证经固定官网auth/me临时验证会话，不保存官网Cookie或密码。昵称、UID、头像、消息和图片会保存在Cloudflare；HTTPS/WSS为传输加密，并非端到端加密。
- 图片每UID每天10张、全站100张（聊天室/私信共用），活动图片存储64MiB；JPEG最长边1600、单张256KiB，未发送附件1小时失效，已发图片可读7天。使用现有DmHub SQLite，无R2。
- 免费服务额度不足时仍可能失败；APP 内限制不能保证不超过平台全部资源额度。仅使用免费产品，未开通付费附加服务。

## 更新

`/updates/android` 返回版本、说明、同来源下载地址、大小与 SHA-256。APK 作为静态资源托管在 `/releases/`；管理凭据和签名私钥不会上传。

APP 每天自动检查一次，也可在“我的 → 设置 → 检查更新”手动检查。用户选择下载后验证文件大小、SHA-256、包名、递增版本与现有安装签名，最后打开系统安装程序。支持 Android 8+；首次可能需要用户允许“安装未知应用”。

0.6.1继续沿用测试版签名以覆盖升级，不切换发布签名。未来公开正式发布时应单独规划发布密钥和一次性迁移。旧0.3.0没有检查更新入口，需要先手动安装0.4.0。

## 验证

`python tools/test_cloudflare.py` 启动临时127.0.0.1运行时，测试完成后停止。覆盖真正的 Android/JVM 传输代码、300连接、301拒绝、频道隔离、重试、限流、心跳、更新文件哈希。`--pages`参数验证入口函数→内部绑定→后台的完整链路。所有负载测试身份与消息都是本机合成数据；本机负载结果不能视为公网性能保证。

`python tools/check_chat_deployment.py` 只读检查生产服务与 APK 元数据。当前没有后台推送，也没有给普通客户端提供云端管理权限。禁言/封禁字段预留在服务端，尚未提供管理员操作界面。

服务地址只做混淆，运行时地址仍可被分析；安全边界是 TLS、随机聊天令牌与云端校验，不能依赖隐藏地址。

## 独立私信

新增 `/dm/v1/*`，使用独立SQLite Durable Object `DmHub`（迁移v2，保留ChatHub v1及已有数据）。Pages的`/dm/*`通过同一内部绑定进入后台；没有新增付费产品。

- `POST session` 只接受`site_cookie,expected_user_id`；用户明确开通后临时接收官网会话，经固定HTTPS `auth/me`验证，不跟随跳转、不保存会话、密码或完整官网响应。账号ID不得由昵称自报。禁言、封禁、二次验证未完成或UID不符均拒绝。
- 私信身份7天有效，每UID最多3个令牌，服务仅存SHA256哈希。收信人也需开通且身份仍有效。`logout`撤销当前令牌。
- Bearer身份可访问`me`、`peer?id=`、`conversations?before=`、`messages?peer=&before=|after=`、`read`、`blocks`和`block`。所有消息查询只含当前账号与指定收信人的消息。最大30条/页，after按ASC并返回has_more/cursor。
- `POST messages`仅接受`peer_id,text,client_id,image_id`（image_id可省略），不接受sender_id。nonce绑定发送账号、收信人和内容，重试不重复。read只允许已实际拉取的收到消息。双方任一拒收即不能发送。
- 每条500个Unicode字符、3秒间隔、15条/分钟、100条/账号/UTC日、全站2000条/UTC日、10位主动联系人/账号/UTC日。验证每IP20次/日（含失败）、每UID20次/日、全站1000次/日；读请求内存限流60次/分钟/身份。最多10000身份、20000会话。
- 7天可见期限，小时alarm分批清理；令牌过期与已注销账号不因客户端字段绕过。私信服务保存明文，HTTPS并非端到端加密，无后台推送。
- `node --test test/dm.test.mjs`：8组真实Node SQLite验证及权限、分页、幂等、限额测试。`node test/dm-runtime.integration.mjs`：一次性workerd及实际DO SQLite，28项合成数据检查；不访问官网或生产私信。
- `tools/check_private_deployment.py` 经用户授权执行真实官网身份认证、验证和退出，凭据从stdin进入且不落盘；不发送任何消息。evidence/private-deployment.json只保存结果。

免费平台请求/计算/SQLite额度可能耗尽，轮询不是无限免费。尤其大量用户长时间打开私信会消耗请求额度，当前限制并非费用或可用性保证。

## 协议3、公告和图片

0.6.0增加VerifiedChatHub、强制仓库认证、图片、UID艾特和引用回复；保留v1/v2并增加公告v3、认证聊天室v4迁移。旧匿名历史保留但不进入新认证频道，原私信文本和已认证身份保留。完整范围、权限、图片额度和兼容性见[修改说明](../docs/PENDING_CHANGES.md)。本机默认测试更新为`python tools/test_cloudflare.py --pages`，使用隔离合成身份，不向官网或生产发送消息。

公告首次配置使用上述configure命令，密钥仅在本机忽略目录和Cloudflare secret中。后续按docs/PENDING_CHANGES.md准备完整列表，使用publish_announcement.py publish仅更新数据，不重新部署或构建APK。

## 0.6.1 昵称/头像同步

新增需Bearer认证的POST /dm/v1/profile/sync，只接受site_cookie，并根据现有令牌的UID向固定官网auth/me验证，不接受自报昵称、UID或头像。仅更新dm_users资料，不轮换或延长令牌；每UID每天20次、全站与开通验证共用1000次/日。APP只在资料变化时调用，保存资料后自动触发；服务端更新participants并向两个频道发送profile事件，查询历史及引用作者使用最新已验证资料。新增回归覆盖令牌不变、冒用拒绝、额度、双频道广播和历史引用同步，22组Node及346项本机运行时检查通过。

## Windows 客户端

Flutter Windows 0.1.0与安卓共用协议3认证、聊天室、私信和公告。Windows更新清单为Pages静态资源`/updates/windows.json`，使用独立版本号和ZIP；不改变Android versionCode。Windows完整源码及验证说明见`../desktop/README.md`。可通过`CHAT_TEST_FLUTTER=1`及`XINGYU_DESKTOP_TEST_DIR`把真实Dart客户端加入本机运行时测试；该模式需完整源码工程和Flutter SDK。
