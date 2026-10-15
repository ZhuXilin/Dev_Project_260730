$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$output = Join-Path $root "文件列表.txt"
Write-Host "正在生成列表..."

# 递归列全部文件+目录（含隐藏、系统文件），输出绝对路径
Get-ChildItem -Path $root -Recurse -Force -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName } |
    Set-Content -Path $output -Encoding UTF8

Write-Host "列表已生成到 $output"