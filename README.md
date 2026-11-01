# AIStudio2API · Render 新加坡部署仓库

> 只放**构建材料**，不放任何密钥/账号 Cookie。账号在服务跑起来后用管理台「Cookie 导入」添加，落在 Render 持久盘 `/var/data/auth/`。

## 内容

| 文件 | 作用 |
|---|---|
| `Dockerfile` | alpine 基础镜像 → 校验 gz sha256 → 解压出 a2a 二进制 |
| `entrypoint.sh` | 保证 `/var/data/{auth,runtime}` 就位 |
| `render.yaml` | Render Blueprint：新加坡 / 1c-2G / 2GB 盘挂 `/var/data` / 全量环境变量 |
| `artifacts/*.gz` | v0.2.14 + cloud-patches 二进制（gz 哈希 `8bed5f9e…`，与基地区台账一致） |

## 关键设计

- **不要隧道**：Render 直出 HTTPS，由 Cloudflare 侧 `a2a.yu-api.com` CNAME 指过来，Access 规则照旧生效。
- **端口**：a2a 不认 `PORT`，只能用 `LISTEN_ADDR=0.0.0.0:10000`（Render 默认 PORT 也是 10000）。
- **状态全落持久盘**：工作目录设为 `/var/data`，`.env`、`auth/`、`runtime/` 自然落在盘上，重建容器不丢账号。
- **双账号**：`auth/` 下每个子目录 = 一个 Google 账号，`ROUTING_STRATEGY=round-robin` 轮流调度；某号某模型 429 只冷却那一格，请求自动切另一个号。

## 运维参考

基地方档案 `aistudio2api-lifecycle.md`（§5 有 28 条已知坑）、`BUILD.md`（升级重编流程）。
