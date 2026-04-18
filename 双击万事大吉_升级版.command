#!/bin/bash
set -euo pipefail

REPO="/Users/fengbo/GitHub/soseki-manuscripts"
PYTHON="/Library/Frameworks/Python.framework/Versions/3.13/bin/python3"

MASTER_BUILDER="$REPO/build_master_json_from_repo_xlsx.py"
MANIFEST_BUILDER="$REPO/build_manifests_from_repo_images_versioned_recursive.py"

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
    stat -f "%m" "$target"
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
  find "$target" -type f \
    ! -name ".DS_Store" \
    -print0 | xargs -0 stat -f "%m" 2>/dev/null | sort -nr | head -n 1
}

LAST_MASTER_XLSX=0
LAST_IMAGES_MASTER_XLSX=0
LAST_IMAGES_TREE=0

if [ -f "$STATE_FILE" ]; then
  LAST_MASTER_XLSX=$(/usr/bin/python3 - <<'PY' "$STATE_FILE"
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p,'r',encoding='utf-8'))
    print(d.get('master_xlsx_mtime',0))
except Exception:
    print(0)
PY
)
  LAST_IMAGES_MASTER_XLSX=$(/usr/bin/python3 - <<'PY' "$STATE_FILE"
import json,sys
p=sys.argv[1]
try:
    d=json.load(open(p,'r',encoding='utf-8'))
    print(d.get('images_master_xlsx_mtime',0))
except Exception:
    print(0)
PY
)
  LAST_IMAGES_TREE=$(/usr/bin/python3 - <<'PY' "$STATE_FILE"
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

CUR_MASTER_XLSX=$(get_mtime "$REPO/master.xlsx")
CUR_IMAGES_MASTER_XLSX=$(get_mtime "$REPO/images_master.xlsx")
CUR_IMAGES_TREE=$(get_latest_tree_mtime "$REPO/images")

NEED_MASTER=0
NEED_MANIFESTS=0

if [ "$CUR_MASTER_XLSX" -gt "$LAST_MASTER_XLSX" ] || [ "$CUR_IMAGES_MASTER_XLSX" -gt "$LAST_IMAGES_MASTER_XLSX" ]; then
  NEED_MASTER=1
  NEED_MANIFESTS=1
fi

if [ "$CUR_IMAGES_TREE" -gt "$LAST_IMAGES_TREE" ]; then
  NEED_MANIFESTS=1
fi

echo "== 变更检查 =="
echo "master.xlsx        : $LAST_MASTER_XLSX -> $CUR_MASTER_XLSX"
echo "images_master.xlsx : $LAST_IMAGES_MASTER_XLSX -> $CUR_IMAGES_MASTER_XLSX"
echo "images/            : $LAST_IMAGES_TREE -> $CUR_IMAGES_TREE"
echo ""

ANY_ACTION=0

if [ "$NEED_MASTER" -eq 1 ]; then
  echo "== 1. 更新 master.json =="
  "$PYTHON" "$MASTER_BUILDER"
  ANY_ACTION=1
else
  echo "== 1. master.json 无需更新 =="
fi
echo ""

if [ "$NEED_MANIFESTS" -eq 1 ]; then
  echo "== 2. 更新 manifests =="
  "$PYTHON" "$MANIFEST_BUILDER"
  ANY_ACTION=1
else
  echo "== 2. manifests 无需更新 =="
fi
echo ""

if [ "$ANY_ACTION" -eq 0 ]; then
  echo "== 3. 没有检测到需要处理的内容 =="
  echo "无需提交，也无需推送。"
  echo ""
  read -p "按回车关闭..."
  exit 0
fi

echo "== 3. Git 状态 =="
git status --short
echo ""

echo "== 4. 暂存全部仓库变更 =="
git add -A
echo ""

if git diff --cached --quiet; then
  echo "== 5. 处理完成，但没有新的 git 变更 =="
else
  echo "== 5. 提交并推送到云端仓库 =="
  COMMIT_MSG="Auto update master.json, manifests, and repo contents"
  git commit -m "$COMMIT_MSG"
  git push origin main
fi
echo ""

cat > "$STATE_FILE" <<EOF
{
  "master_xlsx_mtime": $CUR_MASTER_XLSX,
  "images_master_xlsx_mtime": $CUR_IMAGES_MASTER_XLSX,
  "images_tree_mtime": $CUR_IMAGES_TREE
}
EOF

echo "全部完成。GitHub Pages 通常需等待 1-2 分钟。"
echo ""
read -p "按回车关闭..."
