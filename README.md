# 🔔 叮咚 Dingdong

> A cute macOS menu bar notifier: let your AI agents ping you with one HTTP call.

一个 macOS 顶部栏小通知器。AI（或任何脚本）带着 token 调一个 HTTP 接口，你的菜单栏铃铛就会摇一摇，右上角冒出一张小卡片。

```
AI / 脚本 ──POST /api/notify (token)──▶ server (Go) ──SSE──▶ 菜单栏客户端 (SwiftUI)
```

每条通知只显示四样东西：**标题 · 简短内容 · 来源 · 时间**。

## 快速开始

```bash
# 1. 服务端（二选一）
cd server && go build -o dingdong-server . && ./dingdong-server   # 前台运行，启动时打印 token
./scripts/install-server-launchd.sh                                # 或者装成本机后台服务

# 2. 客户端
./scripts/build-app.sh          # 生成 dist/Dingdong.app
open dist/Dingdong.app          # 第一次打开会弹出设置，填服务器地址和 token
```

token 第一次启动时自动生成，存在数据目录的 `token` 文件里；也可以用环境变量 `DINGDONG_TOKEN` 指定。

## 发通知

```bash
curl -X POST http://127.0.0.1:8787/api/notify \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"title":"任务完成","body":"简短内容","source":"Claude"}'
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `title` | ✓ | 标题，最多 80 字 |
| `body` |  | 简短内容，最多 500 字（也可以叫 `content`） |
| `source` |  | 来源，最多 40 字；不填就读 `X-Source` 请求头，再不行就是“未知来源” |
| `level` |  | `info`（默认）/ `success` / `warning` / `error`，只影响卡片左边的颜色条 |
| `url` |  | 可选，点击卡片时打开 |

时间由服务端自动记录。token 可以放在 `Authorization: Bearer`、`X-Token` 请求头，或者 `?token=` 参数里。JSON、表单、GET 参数三种写法都行，哪种 AI 好调就用哪种：

```bash
curl "http://127.0.0.1:8787/api/notify?token=<TOKEN>&title=好了&body=跑完了&source=脚本"
```

终端里还可以用小工具：

```bash
export DINGDONG_TOKEN=<TOKEN>
./scripts/ding "构建完成" "用时 42 秒" "CI" success
```

### 给 AI 的提示词片段

> 当你完成一个耗时任务、需要我确认、或遇到阻塞时，用下面的命令通知我（标题一句话，内容不超过两句，来源写你自己的名字）：
> `curl -s -X POST http://127.0.0.1:8787/api/notify -H "Authorization: Bearer <TOKEN>" -H "Content-Type: application/json" -d '{"title":"...","body":"...","source":"...","level":"info|success|warning|error"}'`

## 其他接口（都需要 token）

| 方法 | 路径 | 作用 |
|---|---|---|
| GET | `/api/stream` | SSE 推送：连上先给一份 `snapshot`，之后推送 `message` / `delete` / `clear` |
| GET | `/api/messages?limit=50` | 历史消息，新的在前 |
| DELETE | `/api/messages/{id}` | 删一条 |
| DELETE | `/api/messages` | 全部清空 |
| GET | `/healthz` | 健康检查（不需要 token） |

## 部署到服务器（让云端的 AI 也能发）

```bash
cd server
docker build -t dingdong .
docker run -d --name dingdong -p 8787:8787 -v dingdong-data:/data -e DINGDONG_TOKEN=<自己定一个长 token> dingdong
```

建议在前面放一层 HTTPS 反代（nginx/Caddy）。SSE 需要关掉反代缓冲，服务端已经带了 `X-Accel-Buffering: no`。客户端设置里把地址改成 `https://你的域名`。

## 客户端

- 左键点铃铛：打开消息面板；右键：发测试通知 / 退出
- 新消息：铃铛摇摆 + 未读数 + 右上角弹卡（5.5 秒后自动收起，鼠标悬停时不收）+ “Pop” 音效
- 卡片悬停出现 × 删除；右上角 ✨ 点两下清空
- 设置里可以开关弹卡、音效、开机自启，一键复制 curl 示例
- 断线自动重连（指数退避，最长 30 秒），电脑睡醒立刻重连
- 只保留最近 200 条（服务端 `-keep` 参数可调）

## 目录

```
server/   Go 服务端，零依赖，单个二进制
client/   SwiftUI 菜单栏客户端（Swift Package，macOS 14+）
scripts/  build-app.sh 打包 · install-server-launchd.sh 后台服务 · ding 命令行
```

## License

MIT
