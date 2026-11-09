#!/usr/bin/env bash
# 一键把 render/ 目录的文本文件推到 GitHub（Contents API，不打包、秒传）
# 用法：bash push-render.sh "提交说明"
set -euo pipefail

REPO="laswellkatoanb9807-sudo/a2a-render"
MSG="${1:-update render build files}"
TOKEN="$(gh auth token)"
cd "$(dirname "$0")"

FILES=(Dockerfile render.yaml entrypoint.sh push-render.sh .gitignore .gitattributes patches/cloud-patches.diff README.md verify-remote.sh)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "skip (missing): $f"; continue; }
  # 取现有 sha（更新已有文件必须带；若网络抖动则重试，避免空 sha 导致 GitHub 422）
  SHA=$(curl -sS --retry 3 --retry-all-errors -H "Authorization: token $TOKEN" \
        "https://api.github.com/repos/$REPO/contents/$f" \
        | python -c "import json,sys;d=json.load(sys.stdin);print(d.get('sha','') if isinstance(d,dict) else '')" 2>/dev/null || echo "")
  if [ -z "$SHA" ]; then
    echo "⚠️ retry fetching sha for $f..."
    sleep 2
    SHA=$(curl -sS --retry 3 --retry-all-errors -H "Authorization: token $TOKEN" \
          "https://api.github.com/repos/$REPO/contents/$f" \
          | python -c "import json,sys;d=json.load(sys.stdin);print(d.get('sha','') if isinstance(d,dict) else '')" 2>/dev/null || echo "")
  fi
  CONTENT=$(base64 -w0 < "$f" 2>/dev/null || base64 < "$f" | tr -d '\n')
  BODY=$(python -c "
import json,sys
d={'message':sys.argv[1]+': '+sys.argv[2],'content':sys.argv[3]}
if sys.argv[4]: d['sha']=sys.argv[4]
print(json.dumps(d))" "$MSG" "$f" "$CONTENT" "$SHA")
  CODE=$(curl -sS --retry 3 --retry-all-errors -o /tmp/pr.json -w "%{http_code}" -X PUT \
    -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/contents/$f" -d "$BODY")
  if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    echo "✅ $f"
  else
    echo "❌ $f (HTTP $CODE)"; head -c 300 /tmp/pr.json; echo
    exit 1
  fi
done
rm -f /tmp/pr.json
# 同步本地 git 指针到远端最新提交，防止后续其它 AI 跑 git status/merge 时把历史旧文件合回来
git fetch origin master >/dev/null 2>&1 && git reset --mixed origin/master >/dev/null 2>&1 || true
echo "--- 远端最新提交 ---"
curl -sS -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/commits?per_page=1" \
  | python -c "import json,sys;c=json.load(sys.stdin)[0];print(c['sha'][:7],c['commit']['message'].splitlines()[0])"
