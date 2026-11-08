#!/usr/bin/env bash
# ego-lite-windows 技能安装脚本（不装插件，只复制 SKILL.md）
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/skills/ego-lite-windows/SKILL.md"
[ -f "$src" ] || { echo "找不到 $src" >&2; exit 1; }

dst_dir="${DSH_HOME:-$HOME/.dsh}/skills/ego-lite-windows"
mkdir -p "$dst_dir"
cp "$src" "$dst_dir/SKILL.md"
echo "installed -> $dst_dir/SKILL.md"
echo "技能目录热加载，重启会话即可在技能列表看到 ego-lite-windows。"
