# 把「当前生效」的技能正文同步回仓库，并提交推送。
# 用法：powershell -ExecutionPolicy Bypass -File .\sync.ps1
$ErrorActionPreference = 'Stop'

$src = Join-Path $env:USERPROFILE '.dsh\skills\ego-lite-windows\SKILL.md'
$dst = Join-Path $PSScriptRoot 'skills\ego-lite-windows\SKILL.md'
if (-not (Test-Path -LiteralPath $src)) { throw "找不到 $src（先跑 install.ps1 装一次）" }

Copy-Item -LiteralPath $src -Destination $dst -Force
Write-Host "已复制: $src -> $dst"

$changed = git -C $PSScriptRoot status --porcelain
if (-not $changed) { Write-Host "没有变化，跳过提交。"; exit 0 }

git -C $PSScriptRoot add -A
git -C $PSScriptRoot commit -m "sync: 从 ~/.dsh/skills 同步 ego-lite-windows 正文"
git -C $PSScriptRoot push
Write-Host "已提交并推送。"
