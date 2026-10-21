# 星屿聊天室服务端

固定两个频道：**频道一**（ID `1`）与 **频道二**（ID `2`）。所有人可以随意切换，消息查询、长轮询通知、历史分页和发送路径都按频道隔离。

这是独立的聊天服务，不是 cangku.moe 的后台接口。使用独立聊天昵称和服务端生成的身份，昵称不代表官网认证。它不会接收或验证仓库账号密码、邮箱、Cookie。APP 保存聊天身份时使用 Android Keystore 加密。

目前没有预置公网服务器，所以安装 APP 后不会自动连接一个虚构的地址。服务部署完成后，在 APP“聊天室 → 设置”中填写同一个 HTTPS 地址并连接；不同手机即可聊天。

## 本机运行

需要 Python 3.13（本次验证版本）：

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.lock.txt
.venv/Scripts/python -m uvicorn server:create_app --factory --host 127.0.0.1 --port 8000 --workers 1 --no-access-log
```

Linux 将 `.venv/Scripts/python` 换成 `.venv/bin/python`。SQLite 数据默认放在 `data/chat.sqlite3`，可通过 `CHAT_DB` 指定路径。必须使用 **一个 worker**；当前通知机制在单进程内工作，多进程部署需要另外接入共享通知服务。

本机开发时可以使用 `adb reverse tcp:8000 tcp:8000`，然后在 APP 填 `http://127.0.0.1:8000`。这只把当前设备连接到开发机，不是供其他手机公网聊天的部署方式。APP 仅对 localhost/127.0.0.1 放行 HTTP，其余地址要求 HTTPS，没有关闭证书校验。

## 有服务器和域名后的部署

1. 把本目录上传到服务器，安装 Docker 与 Compose。
2. 将域名解析到服务器，并使服务器可接收 80、443 端口流量。
3. 将 `.env.example` 复制为 `.env`，把 `CHAT_DOMAIN` 改为自己的聊天域名。
4. 在本目录执行：

```sh
docker compose up -d --build
```

Compose 启动聊天服务和 Caddy。Caddy 为配置的域名处理 HTTPS，聊天容器不向公网单独暴露 8000 端口。访问 `https://你的聊天域名/health` 应得到：

```json
{"service":"xingyu-chat","protocol":1,"channel_count":2}
```

随后在每台手机的 APP 中填写 `https://你的聊天域名`，输入聊天昵称，点击“保存并连接”。也可把此地址写入安卓工程 `app/src/main/res/values/chat.xml` 的 `chat_server_url` 后重新构建，让后续安装的 APP 默认使用该地址。

数据库使用 `chat-data` 命名卷；普通容器重启不会删除消息。备份时可先停止 chat 服务，再备份此卷，备份完成后重启。首次运行和更新容器应保留这个数据卷。

## 聊天行为

- 用户身份由服务器生成，每台设备使用独立随机令牌，服务端仅保存令牌哈希，有效期30天。
- 两个频道向所有聊天用户开放，切换没有加入审批。
- 消息为纯文本，每条最多1000字符；同一身份每10秒最多发送8条。
- 客户端提供唯一发送 ID，重复请求返回同一条消息，避免网络重试重复发布。
- 使用最长25秒的异步长轮询：当前频道有新消息时立即返回。断开连接的轮询会定期释放。
- 服务端保存历史；APP 每次载入最近50条，支持向前翻阅，当前会话最多显示最近300条。
- APP 前台接收消息，离开聊天室或进入后台后停止轮询；没有后台推送通知。
- APP 两个频道各自保留当前进程内的输入草稿和发送重试状态。重启 APP 后不会恢复未发送的聊天输入。
- “断开连接”清除设备上的聊天令牌；再次连接会创建新聊天身份，历史消息仍保留。

## API

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/health` | 协议与频道数量 |
| POST | `/v1/session` | 用 `nickname` 创建聊天身份 |
| GET | `/v1/me` | 验证聊天身份 |
| GET | `/v1/channels` | 两个固定频道 |
| GET | `/v1/channels/{1或2}/messages` | 最近消息，或 `before` 历史分页，或 `after` 增量读取 |
| POST | `/v1/channels/{1或2}/messages` | 用 `text,client_id` 发送消息 |

除健康检查和创建身份外，请求使用 `Authorization: Bearer <聊天令牌>`。消息发送者完全由该令牌确定，不接受客户端传入发送者 ID。

## 验证

项目根目录的 `python tools/test_chat.py` 提供12项服务端测试，`python tools/smoke_chat.py` 会启动临时本机服务，使用两个真实 HTTP 客户端验证收发、切换与频道隔离，完成后自动停止。

开发环境运行测试还需安装 `requirements-dev.txt` 中的 httpx。测试不向任何公网聊天室发送消息。

服务端代码和本机 HTTP 联调已验证；Compose 文件已提供，但本机没有 Docker，因此没有运行公网容器部署。安卓安装包完成编译和协议检查，尚未进行手机实机聊天测试。

实现参考：[FastAPI 异步处理](https://fastapi.tiangolo.com/async/)、[Python SQLite](https://docs.python.org/3/library/sqlite3.html)、[Uvicorn 配置](https://www.uvicorn.org/settings/)、[Caddy 反向代理](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)。
