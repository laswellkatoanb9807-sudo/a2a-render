#!/usr/bin/env bash
# Render 新机远程验收（只读 + 一次真实生成，测试纪律：gemini-flash-lite-latest + /v1beta）
# 用法: bash verify-remote.sh https://a2a-xxxx.onrender.com
set -uo pipefail

BASE="${1:?用法: bash verify-remote.sh <base-url>}"
BASE="${BASE%/}"
KEY="${PROXY_API_KEY:?请先 export PROXY_API_KEY=... （密钥绝不入仓库）}"
MODEL="gemini-flash-lite-latest"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
code() { curl -s --retry 3 --retry-all-errors -o /dev/null -w '%{http_code}' --max-time 30 "$@"; }

echo "== 靶子: $BASE =="

echo "[1] /health"
BODY=$(curl -s --retry 3 --retry-all-errors --max-time 30 "$BASE/health")
[ "$BODY" = '{"status":"ok"}' ] && ok "health=$BODY" || bad "health=$BODY"

echo "[2] 无 key 必须拒绝 (401/403)"
C=$(code "$BASE/v1beta/models")
{ [ "$C" = "401" ] || [ "$C" = "403" ]; } && ok "无key=$C" || bad "无key=$C（应为 401/403）"

echo "[3] 错 key 必须拒绝 (401/400)"
C=$(code "$BASE/v1beta/models" -H "x-goog-api-key: deadbeef")
{ [ "$C" = "401" ] || [ "$C" = "400" ]; } && ok "错key=$C" || bad "错key=$C（应为 401/400）"

echo "[4] 对 key 拉模型目录"
BODY=$(curl -s --retry 3 --retry-all-errors --max-time 60 "$BASE/v1beta/models" -H "x-goog-api-key: $KEY")
CNT=$(printf '%s' "$BODY" | grep -o '"name"' | wc -l | tr -d ' ')
[ "$CNT" -gt 0 ] && ok "模型数=$CNT" || bad "模型列表异常: $(printf '%s' "$BODY" | head -c 300)"

echo "[5] 真实生成（非流式）"
RESP=$(curl -s --retry 3 --retry-all-errors --max-time 180 -X POST "$BASE/v1beta/models/$MODEL:generateContent" \
  -H "x-goog-api-key: $KEY" -H 'Content-Type: application/json' \
  -d '{"contents":[{"role":"user","parts":[{"text":"只回复：PONG"}]}]}')
TXT=$(printf '%s' "$RESP" | tr -d '\n' | grep -o '"text": *"[^"]*"' | head -3 | tr '\n' ' ')
FR=$(printf '%s' "$RESP" | grep -o '"finishReason": *"[A-Z_]*"' | head -1)
[ -n "$TXT" ] && ok "正文=$TXT $FR" || bad "无正文: $(printf '%s' "$RESP" | head -c 400)"

echo "[6] 真实生成（流式 SSE 事件数）"
N=$(curl -s --retry 3 --retry-all-errors --max-time 180 -X POST "$BASE/v1beta/models/$MODEL:streamGenerateContent?alt=sse" \
  -H "x-goog-api-key: $KEY" -H 'Content-Type: application/json' \
  -d '{"contents":[{"role":"user","parts":[{"text":"数到三"}]}]}' | grep -c '^data: ')
[ "$N" -ge 2 ] && ok "SSE 事件=$N" || bad "SSE 事件=$N（应为多条）"

echo
echo "== 结果: 通过 $PASS 项 / 失败 $FAIL 项 =="
[ "$FAIL" -eq 0 ] || exit 1
