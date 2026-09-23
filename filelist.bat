@echo off
chcp 65001 >nul
set "output=文件列表.txt"
echo 正在生成纯净文件列表（仅路径）...
dir /s /a /b > "%output%" 2>nul
echo 列表已生成到 "%output%"
pause