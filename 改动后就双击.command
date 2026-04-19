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
TEXT_BUILDER="$REPO/build_completed_texts_from_xlsx_portable.py"
MANIFEST_BUILDER="$REPO/build_manifests_portable.py"
COLLECTION_BUILDER="$REPO/build_collection_all_portable.py"

STATE_DIR="$REPO/.auto_state"
STATE_FILE="$STATE_DIR/last_run_state.json"

mkdir -p "$STATE_DIR"
cd "$REPO"

for f in "$MASTER_BUILDER" "$TEXT_BUILDER" "$MANIFEST_BUILDER" "$COLLECTION_BUILDER"; do
  if [ ! -f "$f" ]; then
    echo "缺少脚本: $f"
    exit 1
  fi
done

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

read_state() {
  local key="$1"
  if [ -f "$STATE_FILE" ]; then
    "$PYTHON" - <<'PY' "$STATE_FILE" "$key"
import json,sys
p,key = sys.argv[1], sys.argv[2]
try:
    d=json.load(open(p,'r',encoding='utf-8'))
    print(d.get(key,0))
except Exception:
    print(0)
PY
  else
    echo "0"
  fi
}

LAST_MASTER_XLSX=$(read_state "master_xlsx_mtime")
LAST_IMAGES_MASTER_XLSX=$(read_state "images_master_xlsx_mtime")
LAST_TEXT_MASTER_XLSX=$(read_state "text_master_xlsx_mtime")
LAST_IMAGES_TREE=$(read_state "images_tree_mtime")

NOW_MASTER_XLSX=$(get_mtime "$REPO/master.xlsx")
NOW_IMAGES_MASTER_XLSX=$(get_mtime "$REPO/images_master.xlsx")
NOW_TEXT_MASTER_XLSX=$(get_mtime "$REPO/soseki-manuscripts-text-master.xlsx")
NOW_IMAGES_TREE=$(get_latest_tree_mtime "$REPO/images")

echo "== 变更检查 =="
echo "master.xlsx                      : $LAST_MASTER_XLSX -> $NOW_MASTER_XLSX"
echo "images_master.xlsx               : $LAST_IMAGES_MASTER_XLSX -> $NOW_IMAGES_MASTER_XLSX"
echo "soseki-manuscripts-text-master.xlsx : $LAST_TEXT_MASTER_XLSX -> $NOW_TEXT_MASTER_XLSX"
echo "images/                          : $LAST_IMAGES_TREE -> $NOW_IMAGES_TREE"
echo

NEED_MASTER=0
NEED_TEXT=0
NEED_MANIFEST=0
NEED_COLLECTION=0

if [ "$NOW_MASTER_XLSX" != "$LAST_MASTER_XLSX" ] || [ "$NOW_IMAGES_MASTER_XLSX" != "$LAST_IMAGES_MASTER_XLSX" ]; then
  NEED_MASTER=1
  NEED_MANIFEST=1
  NEED_COLLECTION=1
fi

if [ "$NOW_TEXT_MASTER_XLSX" != "$LAST_TEXT_MASTER_XLSX" ]; then
  NEED_TEXT=1
  NEED_MANIFEST=1
  NEED_COLLECTION=1
fi

if [ "$NOW_IMAGES_TREE" != "$LAST_IMAGES_TREE" ]; then
  NEED_MANIFEST=1
  NEED_COLLECTION=1
fi

if [ "$NEED_MASTER" -eq 1 ]; then
  echo "== 1. 更新 master.json =="
  "$PYTHON" "$MASTER_BUILDER"
  echo
else
  echo "== 1. master.json 无需更新 =="
  echo
fi

if [ "$NEED_TEXT" -eq 1 ]; then
  echo "== 2. 从文本主表生成 completed_texts.json =="
  "$PYTHON" "$TEXT_BUILDER"
  echo
else
  echo "== 2. completed_texts.json 无需更新 =="
  echo
fi

if [ "$NEED_MANIFEST" -eq 1 ]; then
  echo "== 3. 更新 manifests =="
  "$PYTHON" "$MANIFEST_BUILDER"
  echo
else
  echo "== 3. manifests 无需更新 =="
  echo
fi

if [ "$NEED_COLLECTION" -eq 1 ]; then
  echo "== 4. 更新 collection-all.json =="
  "$PYTHON" "$COLLECTION_BUILDER"
  echo
else
  echo "== 4. collection-all.json 无需更新 =="
  echo
fi

$PYTHON - <<'PY' "$STATE_FILE" "$NOW_MASTER_XLSX" "$NOW_IMAGES_MASTER_XLSX" "$NOW_TEXT_MASTER_XLSX" "$NOW_IMAGES_TREE"
import json, sys
p, a, b, c, d = sys.argv[1:]
with open(p, 'w', encoding='utf-8') as f:
    json.dump({
        'master_xlsx_mtime': int(a),
        'images_master_xlsx_mtime': int(b),
        'text_master_xlsx_mtime': int(c),
        'images_tree_mtime': int(d),
    }, f, ensure_ascii=False, indent=2)
PY

echo "== 5. Git 状态 =="
git status --short
echo

if [ "$NEED_MASTER" -eq 1 ] || [ "$NEED_TEXT" -eq 1 ] || [ "$NEED_MANIFEST" -eq 1 ] || [ "$NEED_COLLECTION" -eq 1 ] || [ -n "$(git status --porcelain)" ]; then
  echo "== 6. 暂存全部仓库变更 =="
  git add -A
  echo
  echo "== 7. 提交并推送到云端仓库 =="
  if git diff --cached --quiet; then
    echo "没有可提交的变更。"
  else
    git commit -m "Auto update text master, master.json, manifests, and collection-all"
    git push origin main
  fi
else
  echo "没有检测到需要同步的内容。"
fi

echo
echo "全部完成。GitHub Pages 通常需等待 1-2 分钟。"
echo
read -p "按回车关闭..."
