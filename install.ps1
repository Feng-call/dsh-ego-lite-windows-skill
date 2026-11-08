# ego-lite-windows 技能安装脚本（不装插件，只复制 SKILL.md）
# 用法：powershell -ExecutionPolicy Bypass -File .\install.ps1
$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'skills\ego-lite-windows\SKILL.md'
if (-not (Test-Path -LiteralPath $src)) { throw "找不到 $src" }

$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$dstDir = Join-Path $dshHome 'skills\ego-lite-windows'
New-Item -ItemType Directory -Force -Path $dstDir | Out-Null

Copy-Item -LiteralPath $src -Destination (Join-Path $dstDir 'SKILL.md') -Force
Write-Host "installed -> $dstDir\SKILL.md"
Write-Host "技能目录热加载，重启会话即可在技能列表看到 ego-lite-windows。"
