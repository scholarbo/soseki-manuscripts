#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "未找到 python3 / python"
  exit 1
fi

MASTER_BUILDER="$REPO/build_master_json_portable.py"
MANIFEST_BUILDER="$REPO/build_manifests_portable.py"

STATE_DIR="$REPO/.auto_state"
STATE_FILE="$STATE_DIR/last_run_state.json"

mkdir -p "$STATE_DIR"
cd "$REPO"

if [ ! -f "$MASTER_BUILDER" ]; then
  echo "缺少脚本: $MASTER_BUILDER"
  exit 1
fi

if [ ! -f "$MANIFEST_BUILDER" ]; then
  echo "缺少脚本: $MANIFEST_BUILDER"
  exit 1
fi

get_mtime() {
  local target="$1"
  if [ -e "$target" ]; then
    stat -f "%m" "$target" 2>/dev/null || stat -c "%Y" "$target" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

get_latest_tree_mtime() {
  local target="$1"
  if [ ! -e "$target" ]; then
    echo "0"
    return
  fi
  local val
  val=$(find "$target" -type f ! -name ".DS_Store" -print0 2>/dev/null | xargs -0 sh -c '
    for f in "$@"; do
      stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null
    done
  ' sh 2>/dev/null | sort -nr | head -n 1)
  echo "${val:-0}"
}

LAST_MASTER_XLSX=0
LAST_IMAGES_MASTER_XLSX=0
LAST_IMAGES_TREE=0

if [ -f "$STATE_FILE" ]; then
  LAST_MASTER_XLSX=$($PYTHON - <<'PY' "$STATE_FILE"
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p,'r',encoding='utf-8'))
    print(d.get('master_xlsx_mtime',0))
except Exception:
    print(0)
PY
)
  LAST_IMAGES_MASTER_XLSX=$($PYTHON - <<'PY' "$STATE_FILE"
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p,'r',encoding='utf-8'))
    print(d.get('images_master_xlsx_mtime',0))
except Exception:
    print(0)
PY
)
  LAST_IMAGES_TREE=$($PYTHON - <<'PY' "$STATE_FILE"
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p,'r',encoding='utf-8'))
    print(d.get('images_tree_mtime',0))
except Exception:
    print(0)
PY
)
fi

NOW_MASTER_XLSX=$(get_mtime "$REPO/master.xlsx")
NOW_IMAGES_MASTER_XLSX=$(get_mtime "$REPO/images_master.xlsx")
NOW_IMAGES_TREE=$(get_latest_tree_mtime "$REPO/images")

echo "== 变更检查 =="
echo "master.xlsx        : $LAST_MASTER_XLSX -> $NOW_MASTER_XLSX"
echo "images_master.xlsx : $LAST_IMAGES_MASTER_XLSX -> $NOW_IMAGES_MASTER_XLSX"
echo "images/            : $LAST_IMAGES_TREE -> $NOW_IMAGES_TREE"
echo

NEED_MASTER=0
NEED_MANIFEST=0

if [ "$NOW_MASTER_XLSX" != "$LAST_MASTER_XLSX" ] || [ "$NOW_IMAGES_MASTER_XLSX" != "$LAST_IMAGES_MASTER_XLSX" ]; then
  NEED_MASTER=1
  NEED_MANIFEST=1
fi

if [ "$NOW_IMAGES_TREE" != "$LAST_IMAGES_TREE" ]; then
  NEED_MANIFEST=1
fi

if [ "$NEED_MASTER" -eq 1 ]; then
  echo "== 1. 更新 master.json =="
  "$PYTHON" "$MASTER_BUILDER"
  echo
else
  echo "== 1. master.json 无需更新 =="
  echo
fi

if [ "$NEED_MANIFEST" -eq 1 ]; then
  echo "== 2. 更新 manifests =="
  "$PYTHON" "$MANIFEST_BUILDER"
  echo
else
  echo "== 2. manifests 无需更新 =="
  echo
fi

$PYTHON - <<'PY' "$STATE_FILE" "$NOW_MASTER_XLSX" "$NOW_IMAGES_MASTER_XLSX" "$NOW_IMAGES_TREE"
import json, sys
p, a, b, c = sys.argv[1:]
with open(p, "w", encoding="utf-8") as f:
    json.dump({
        "master_xlsx_mtime": int(a),
        "images_master_xlsx_mtime": int(b),
        "images_tree_mtime": int(c),
    }, f, ensure_ascii=False, indent=2)
PY

echo "== 3. Git 状态 =="
git status --short
echo

if [ "$NEED_MASTER" -eq 1 ] || [ "$NEED_MANIFEST" -eq 1 ] || [ -n "$(git status --porcelain)" ]; then
  echo "== 4. 暂存全部仓库变更 =="
  git add -A
  echo
  echo "== 5. 提交并推送到云端仓库 =="
  if git diff --cached --quiet; then
    echo "没有可提交的变更。"
  else
    git commit -m "Auto update master.json, manifests, and repo contents"
    git push origin main
  fi
else
  echo "没有检测到需要同步的内容。"
fi

echo
echo "全部完成。GitHub Pages 通常需等待 1-2 分钟。"
echo
read -p "按回车关闭..."
