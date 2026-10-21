# 网站分析记录

日期：2026-10-20。目标：用户指定的 `https://cangku.moe`。范围：正常登录、前端发布脚本的静态分析、浏览器界面检查、少量只读 API 验证。没有尝试获取服务端源码或绕过访问控制。

## 证据

本会话没有已连接的 REA 工具，系统 PATH 也没有 `rea` 或 `npm`。依据技能的恢复指南，继续使用现有浏览器、Python 和公开发布脚本进行分析。以下均为普通工具得到的证据，不冒称 REA Evidence，也没有生成虚构的 Evidence ID。

| 本地记录 | 观察 |
| --- | --- |
| 浏览器正常登录 | 登录成功后可见首页、分类、排行、作者和收藏等页面 |
| 公开 `/login` 配置 | `apiDomain = https://cangku.moe/api`，API 版本 `v1` |
| 发布脚本 `/assets/web/static/js/app.a97ae13d.js` | Vue 前端，封装了相同的登录、内容、分类、排行与收藏接口 |
| `evidence/api-contract.json` | 真实登录后只读请求的响应字段类型、分页和分类信息 |
| `evidence/toolchain-sources.json` | 官方构建工具来源及仓库校验值 |

脚本 SHA-256：`259c33da4ac502c09242aff52374ed78bd72d768e98a8a5d9e33b787b0add765`。原始网站脚本作为本地分析材料保留，但不纳入客户端和源码交付包。

## 接口映射

API 基址：`https://cangku.moe/api/v1/`。认证使用服务器 Cookie。初始化访问 `/login` 以接收 Cookie；如存在 `XSRF-TOKEN`，写请求带 URL 解码后的 `X-XSRF-TOKEN`。实际登录和随后的认证读取均成功。

| 页面/动作 | 路径 | 关键参数 | 证据与状态 |
| --- | --- | --- | --- |
| 登录 | POST `auth/login` | `login,password,remember,include` | 已实际验证成功 |
| 当前用户 | GET `auth/me` | — | 已实际验证 |
| 首页 | GET `post/list` | `page,per_page,simple,include,with[]` | 已实际验证 |
| 分类树 | GET `category/list` | `all=1,type=post` | 已实际验证，含 children |
| 分类内容 | GET `post/list` | `category_in[0]` | 已实际验证；错误参数 `category` 会被忽略，已修正 |
| 搜索 | GET `post/search` | `search,category_in[],page,per_page` | 已实际验证 |
| 排行 | GET `post/rank` | `year,date_type,date_value,page,per_page` | 日榜实际验证；周/月参数由发布脚本确认 |
| 文章 | GET `post/info` | `id,include=user,tags,categories,favorited,upvoted` | 已实际验证 |
| 收藏列表 | GET `user/favoritePost` | `id,page,per_page,simple` | 已实际验证 |
| 收藏/取消 | POST `post/favorite` / `post/unfavorite` | `id` | 发布脚本确认；未修改用户收藏 |
| 作者主页 | GET `user/info` | `id` | 发布脚本确认 |
| 作者投稿 | GET `user/post` | `id,page,per_page,simple` | 发布脚本确认 |
| 评论 | GET `comment/list` | `post_id,parent_id,page,include,order_by` | 基本读取实际验证；嵌套参数由发布脚本确认 |
| 评论发送 | POST `comment/create` | `post_id,content,parent_id,reply_to_id` | 发布脚本确认；未实际发送 |

标准响应：`{code,data,message,status_code,meta?}`。分页位于 `meta.pagination`，包括 `current_page,total_pages,total,per_page`。主列表元素的封面字段为 `thumb`，作者字段为 `user.nickname`，阅读计数为 `view_count`。

主分类共 10 个，ID、名称及子分类以响应为准，没有把分类写死在 APP 内。排行 `date_type` 为 `daily/weekly/monthly`，`date_value` 为年内日序号、周序号或月份。周序号按发布脚本所用 dayjs week 约定对应为周日开始的周。

## 下载内容

真实文章样本包含 `[dlbox title="..." info="..." link1="名称|URL"][/dlbox]`。部分网盘入口指向二维码图片，不能把图片 URL 当作网盘直链。客户端保持原链接，显示资源说明、图片预览和复制功能。未声称已恢复二维码背后的实际网盘地址。

正文使用原生 TextView 渲染，接口之外的图片请求不附带登录 Cookie。外部链接只接受 HTTP(S) 和 magnet；站内文章可回到原生详情。

## 边界与未覆盖项

这是对用户可访问网站客户端协议的重建，不能证明后台完整逻辑。0.2.0 已补充自己账号的投稿编辑和管理、个人资料、绑定邮箱与密码修改界面。未迁移画廊、社区、二次验证配置和全站管理员流程。未通过真实写入操作验证写接口；源码提供交互入口，并区分这些操作的验证范围。

本次没有修改用户的账号资料、密码、收藏、投稿或评论。只读接口可能产生正常访问日志与阅读计数变化。

## 0.2.0 投稿与资料扩展

通过浏览器打开已登录的 `/admin/post/create`，观察到标题、Froala 正文、保存草稿、发布、状态、时间、封面、分类树和标签。没有填写或提交表单。

管理端发布脚本：`/assets/admin/static/js/app.4c0ebfd5.js`，SHA-256：`4c80891d84d7b14a2e6fc2699abb2e2252f977d1d47d46befec13f45de9edf17`。管理端同样使用 `https://cangku.moe/api/v1/`。以此确定请求字段和写入路径；原始脚本不进入源码交付包。

`evidence/management-contract.json` 保留了只读验证的字段类型与权限名称，不含账号、会话、个人资料实际值或私人稿件正文。当前账号能读取自己的发布、定时、草稿、待审、退回和回收站列表；编辑读取使用 `exclude_view=1`。

| 操作 | 接口与字段 | 验证范围 |
| --- | --- | --- |
| 带权限和资料的当前用户 | GET `auth/me?include=roles,permissions,meta` | 实际只读成功 |
| 自己的状态列表 | GET `post/list?user_id={currentUserId}&status=...` | 各状态实际读取成功 |
| 自己的文章编辑数据 | GET `post/info?id=...&include=user,categories:simple,tags&exclude_view=1` | 实际读取并检查 owner |
| 积分经验 | GET `user/creditLog` | 实际读取成功 |
| 新建投稿 | POST `post/create`，`title,content,status,thumb,tags,categories,created_at?` | 发布脚本确认，未实际写入 |
| 修改投稿 | POST `post/update`，上述内容加 `id` | 发布脚本确认，未实际写入 |
| 退回后重新送审 | POST `post/review`，`id,title,content,thumb,tags,categories` | 发布脚本确认，状态交由网站决定 |
| 回收站 | POST `post/delete` / `post/restore`，`id` | 发布脚本确认，未操作现有内容 |
| 编辑锁检查 | POST `post/editLock/refresh`，`id` | 发布脚本确认，APP 提交修改前调用；不主动接管冲突锁 |
| 个人资料 | POST `user/update`，当前 `id` 和改动字段 | 前台脚本确认；仅提交变化字段 |
| 头像上传 | POST `user/uploadImage`，multipart `avatar` 与 `type=avatar` | 上传组件字段确认，未实际上传 |
| 背景上传 | POST `user/uploadImage`，multipart `image` 与 `type=banner` | 上传组件字段确认，未实际上传 |
| 文章图片 | POST `upload/image`，multipart `image` | 管理端编辑器配置确认，未实际上传 |
| 邮箱与密码 | POST `user/updateEmail` / `user/updatePassword` | 前台脚本确认；未更改现有凭据 |

已有文章以 HTML 源码编辑，未经过 `Html.fromHtml → Html.toHtml` 的有损转换。纯文本在明确转换或提交时转义。文章修改前重新读取 `updated_at` 和正文/元数据指纹，阻止已检测到的并发修改；网站接口没有条件更新机制，因此这不是服务器提供的原子版本控制。

本机草稿以用户 ID 与文章 ID 分开存储，支持进程重启后的恢复。上传、发布和资料保存期间禁用表单，防止提交过程中继续编辑导致丢失。账号安全输入不加入本机草稿或持久化状态。

## 0.5.0 社交扩展（2026-10-20）

沿用reverse-engineer-anything的证据分界；现有仓库源码分析使用普通工具，官网发布脚本的字符串/调用关系也为普通工具静态证据，不冒称REA Evidence。只读真实响应schema见`evidence/social-contract.json`。已验证我的评论、回复/点赞通知、系统公告及用户搜索的读取。发布脚本确认评论创建/删除/vote/unvote、user/followableIdList、makeNotificationAsRead（ids或all/action）、makeAnnounceAsRead。未执行真实评论、赞、通知状态写入。定位展示通知或评论列表提供的快照，再按已知根评论ID加载子回复；没有猜测comment/info接口或扫描所有评论页。

当前发布脚本枚举的API中未发现私信流程，这一有界搜索不证明网站后台完全不支持私信。经用户明确同意，使用APP独立私信服务，以固定官网auth/me验证当前会话并确认UID，双方需要安装和开通。生产验证与令牌注销成功，没有发送生产私信。
