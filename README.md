# AIStudio2API · Render 新加坡部署仓库

> 现役：`v0.3.8-cloud`（2026-11-14，上游 `d94bf91`）。恢复 Build 写代码助手 `-build` 模型（按官网复用 Build 应用）、四协议未匹配工具结果转文本、Anthropic 空思考签名改为 thinking 块、正文输出后不再续写、出口地理定位与指纹/性能优化；另保留 CRLF 全链路归一化与 STRIP 下服务端工具真实签名。回滚与验收见基地方档案。

> 只放**构建材料**，不放任何密钥/账号 Cookie。账号在服务跑起来后用管理台「Cookie 导入」添加，落在 Render 持久盘 `/var/data/auth/`。

## 内容

| 文件 | 作用 |
|---|---|
| `Dockerfile` | Node 22 前端 + Go/CGO 云端现编；上游 v0.3.8 + CRLF 与服务端工具签名补丁；SpiderMonkey v158.0.1 / libwebp v1.6.0 静态库走 GitHub Asset API 并校验 SHA-256 |
| `entrypoint.sh` | 保证 `/var/data/{auth,runtime}` 就位 |
| `render.yaml` | Render Blueprint：新加坡 / 1c-2G / 2GB 盘挂 `/var/data` / 全量环境变量 |
| `patches/cloud-patches.diff` | CRLF 全链路归一化 + STRIP 下保留服务端工具真实签名（约 10KB），构建时应用并自检 |
| `verify-remote.sh` | 直连 Render 的六项验收脚本 |

## 关键设计

- **容器内出站隧道**：Render 直出 HTTPS，同时运行 cloudflared；`a2a.yu-api.com` 经 CF Tunnel 接入，Access 规则照旧生效（不要 CNAME 到 `onrender.com`，会触发 CF error 1000）。
- **端口**：a2a 不认 `PORT`，只能用 `LISTEN_ADDR=0.0.0.0:10000`（Render 默认 PORT 也是 10000）。
- **状态全落持久盘**：工作目录设为 `/var/data`，`.env`、`auth/`、`runtime/` 自然落在盘上，重建容器不丢账号。
- **双账号**：`auth/` 下每个子目录 = 一个 Google 账号，`ROUTING_STRATEGY=fill-first` 打满换号；某号某模型 429 只冷却那一格，请求自动切另一个号。

## 运维参考

基地方档案 `aistudio2api-lifecycle.md`（§5 已知坑与 §10 Render SOP）、`BUILD.md`（升级重编流程）。
