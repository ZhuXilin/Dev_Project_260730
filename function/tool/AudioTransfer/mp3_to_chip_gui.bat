@echo off
chcp 65001 > nul
cd /d "%~dp0"
python mp3_to_chip_gui.py
if errorlevel 1 (
    echo.
    echo ============================================
    echo  运行失败，请检查：
    echo  1. 是否安装了 Python（勾选 Add to PATH）
    echo  2. 是否安装了依赖: pip install librosa soundfile
    echo  3. 是否有 ffmpeg（解码 MP3 需要）
    echo ============================================
    pause
)