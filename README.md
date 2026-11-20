# AIStudio2API · Render 新加坡部署仓库

> **现役镜像**：`v0.3.13-cloud`（上游 `c77dd89` + 云端双补丁：**CRLF 全链路归一化** + **STRIP 下保留服务端工具真实签名**）。
> 本仓库仅放构建材料，**零密钥、零 Cookie、零二进制**；账号经管理 API 导入，落 Render 持久盘 `/var/data/auth/`。

## 文件清单

| 文件 | 作用 |
|---|---|
| `Dockerfile` | Node 22 前端（含跨目录 `internal/i18n/messages`）+ Go 1.27 CGO 现编；SpiderMonkey `v158.0.1-aistudio2api.2` / libwebp `v1.6.0` 走 GitHub Asset API 并验 SHA-256；内置 cloudflared `2026.10.7` |
| `entrypoint.sh` | 确保 `/var/data/{auth,runtime}` 就位并拉起容器内 cloudflared |
| `render.yaml` | Render Blueprint：Singapore / Starter 0.5c-512MB（配 `GOMEMLIMIT=300MiB`）/ 2GB 盘挂 `/var/data` / 全量环境变量 |
| `patches/cloud-patches.diff` | CRLF 归一化 + STRIP 服务端工具签名保留（UTF-8 LF，构建时 `git apply` + marker 自检） |
| `verify-remote.sh` | 直连 Render 的六项验收脚本 |
| `push-render.sh` | 经 GitHub Contents API 推送文本文件并自动对齐本地 git 指针 |

## 关键设计

- **出站隧道接入**：CF 不能代理 CNAME 到 `onrender.com`（error 1000），故由容器内 cloudflared 拨出隧道 `a2a-render` 承接 `a2a.yu-api.com` 并保持 CF Access 保护。
- **端口与持久盘**：a2a 不认 `PORT`，须设 `LISTEN_ADDR=0.0.0.0:10000`；工作目录 `/var/data` 跨部署保留 `.env` / `auth/` / `runtime/`。
- **多账号调度**：三号（Camoufox 隔离会话）`ROUTING_STRATEGY=fill-first` + `WARM_WORKER_LIMIT=3`，429 冷却按 `<账号>:<通道>:<模型>` 隔离。

详细运维、升级与排障见基地主档案 `aistudio2api-lifecycle.md`。
