#!/usr/bin/env bash
# 把「当前生效」的技能正文同步回仓库，并提交推送。
# 用法：bash ./sync.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${DSH_HOME:-$HOME/.dsh}/skills/ego-lite-windows/SKILL.md"
dst="$here/skills/ego-lite-windows/SKILL.md"
[ -f "$src" ] || { echo "找不到 $src（先跑 install.sh 装一次）" >&2; exit 1; }

cp "$src" "$dst"
echo "已复制: $src -> $dst"

if [ -z "$(git -C "$here" status --porcelain)" ]; then
  echo "没有变化，跳过提交。"
  exit 0
fi

git -C "$here" add -A
git -C "$here" commit -m "sync: 从 ~/.dsh/skills 同步 ego-lite-windows 正文"
git -C "$here" push
echo "已提交并推送。"
