@echo off
chcp 65001 > nul
cd /d "%~dp0"
python midi_to_chip_gui.py
if errorlevel 1 pause