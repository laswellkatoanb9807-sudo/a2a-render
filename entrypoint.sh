#!/bin/sh
# Render 启动脚本：保证持久盘目录结构就位；首次启动可用 Secret File 播种账号
set -eu

DATA_DIR="${A2A_DATA_DIR:-/var/data}"
mkdir -p "$DATA_DIR/auth" "$DATA_DIR/runtime/logs"

if [ ! -w "$DATA_DIR" ]; then
  echo "FATAL: $DATA_DIR 不可写，检查 Render 磁盘挂载" >&2
  exit 1
fi

# 首次启动播种：Render Secret File 里放 seed-auth.tar.gz（内含 <email>/storage-state.json + account.json）
SEED=/etc/secrets/seed-auth.tar.gz
if [ -f "$SEED" ] && [ -z "$(ls -A "$DATA_DIR/auth" 2>/dev/null || true)" ]; then
  echo "[entrypoint] 检测到 $SEED，播种账号到 $DATA_DIR/auth"
  tar -xzf "$SEED" -C "$DATA_DIR/auth"
  echo "[entrypoint] 播种完成：$(ls "$DATA_DIR/auth")"
fi

echo "[entrypoint] data=$DATA_DIR listen=${LISTEN_ADDR:-unset} tz=${TZ:-unset}"
exec "$@"
