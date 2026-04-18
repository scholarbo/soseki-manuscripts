#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

if command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON="python"
else
  echo "未找到 python3 / python"
  exit 1
fi

echo "== Python =="
"$PYTHON" --version

echo "== 安装依赖 =="
"$PYTHON" -m pip install -r requirements.txt

echo "== 设置执行权限 =="
chmod +x "$REPO/build_master_json_portable.py" || true
chmod +x "$REPO/build_manifests_portable.py" || true
chmod +x "$REPO/改动后就双击.command" || true
chmod +x "$REPO/新设备先点我.command" || true

echo
echo "初始化完成。"
echo "接下来可直接运行："
echo "./改动后就双击.command"
echo
read -p "按回车关闭..."
