@echo off
chcp 65001 >nul
set "output=文件列表.txt"
echo 正在生成列表...
dir /s /a > "%output%"
echo 列表已生成到 "%output%"
pause