@echo off
chcp 65001 > nul
cd /d "%~dp0"

echo ========================================
echo  8-bit 音效批量生成
echo ========================================
echo.

python gen_sfx.py
if errorlevel 1 (
    echo.
    echo ========================================
    echo  运行失败，请检查：
    echo  1. 是否安装了 Python
    echo  2. 命令行里能运行 python --version
    echo ========================================
    pause
    exit /b
)

echo.
pause