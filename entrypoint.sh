#!/bin/sh
# Render 启动脚本：只负责保证持久盘目录结构就位，然后交给 a2a 主程序
set -eu

DATA_DIR="${A2A_DATA_DIR:-/var/data}"
mkdir -p "$DATA_DIR/auth" "$DATA_DIR/runtime/logs"

# 首次启动：目录权限自检（Render 持久盘可能以 root 挂载）
if [ ! -w "$DATA_DIR" ]; then
  echo "FATAL: $DATA_DIR 不可写，检查 Render 磁盘挂载" >&2
  exit 1
fi

echo "[entrypoint] data=$DATA_DIR listen=${LISTEN_ADDR:-unset} tz=${TZ:-unset}"
exec "$@"
