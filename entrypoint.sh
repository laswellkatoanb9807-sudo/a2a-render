#!/bin/sh
# Render 启动脚本：持久盘目录就位 → （可选）拉起 cloudflared 出站隧道 → 交给 a2a 主程序
set -eu

DATA_DIR="${A2A_DATA_DIR:-/var/data}"
mkdir -p "$DATA_DIR/auth" "$DATA_DIR/runtime/logs"

if [ ! -w "$DATA_DIR" ]; then
  echo "FATAL: $DATA_DIR 不可写，检查 Render 磁盘挂载" >&2
  exit 1
fi

# 首次启动播种（历史方案，Secret Files 只收文本故未启用；留作无害 no-op）
SEED=/etc/secrets/seed-auth.tar.gz
if [ -f "$SEED" ] && [ -z "$(ls -A "$DATA_DIR/auth" 2>/dev/null || true)" ]; then
  echo "[entrypoint] 检测到 $SEED，播种账号到 $DATA_DIR/auth"
  tar -xzf "$SEED" -C "$DATA_DIR/auth"
fi

# Cloudflare Tunnel（出站，无入站端口）：设了 TUNNEL_TOKEN 就拉起
# Render 的 onrender.com 本身在 CF 后面，CF 代理不能 CNAME 指过来（error 1000），故必须走隧道
if [ -n "${TUNNEL_TOKEN:-}" ]; then
  echo "[entrypoint] 启动 cloudflared 隧道"
  cloudflared tunnel --no-autoupdate --metrics 127.0.0.1:20241 run --token "$TUNNEL_TOKEN" \
    >>"$DATA_DIR/runtime/logs/cloudflared.log" 2>&1 &
  echo "[entrypoint] cloudflared pid=$!"
else
  echo "[entrypoint] 未设 TUNNEL_TOKEN，跳过隧道"
fi

echo "[entrypoint] data=$DATA_DIR listen=${LISTEN_ADDR:-unset} tz=${TZ:-unset}"
exec "$@"
