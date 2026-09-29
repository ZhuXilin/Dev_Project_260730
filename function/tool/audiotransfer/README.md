# MP3 → Chip JSON

## 先说清楚：MP3 转谱是"半自动"的

| 情况 | 效果 |
|------|------|
| **单声部**（单一旋律/独奏） | ⭐⭐⭐⭐ 自动可用 |
| **双声部**（旋律 + 简单伴奏） | ⭐⭐ 主旋律能提取，伴奏会混 |
| **完整混音 BGM**（多乐器/和声/鼓） | ⭐ 基本不能自动，只能提取"最响的主旋律" |
| **原始 NES 音频**（5 通道混音后） | ⭐⭐ 主旋律勉强 |

**你要转的 Fire Emblem MP3** → 属于"完整混音"，自动提取只能拿到主旋律。**要完整还原必须找 MIDI**。

不过我可以给你一个 **MP3 → 主旋律 → chip JSON** 的 GUI，**先跑一首试试看**，效果你能接受就用。

---

# 方案对比

| 方案 | 依赖 | 效果 | 推荐度 |
|------|------|------|-------|
| **A. 找现成 MIDI** | 无 | ⭐⭐⭐⭐⭐ | 🥇 |
| **B. librosa 提取主旋律** | `pip install librosa` | ⭐⭐ | 🥈 |
| **C. basic-pitch（AI）** | `pip install basic-pitch` + TensorFlow | ⭐⭐⭐（复调） | 🥉 装起来烦 |

**先试 B**，不行再试 A/C。

---

# `function/tool/AudioTransfer/mp3_to_chip_gui.py`

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MP3/WAV → chip_music JSON 转换器（GUI 版）

注意：只能提取"主旋律"（单声部），复调混音会丢失伴奏信息。
完整还原建议找现成 MIDI 用 midi_to_chip_gui.py。

依赖:
    pip install librosa soundfile
"""

import sys
import json
import traceback
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError:
    print("错误: 缺少 tkinter")
    sys.exit(1)

try:
    import numpy as np
    import librosa
except ImportError:
    print("错误: 需要 librosa")
    print("请运行: pip install librosa soundfile")
    sys.exit(1)


# ============================================================
#  配置
# ============================================================
TICKS_PER_BEAT = 4
DEFAULT_BPM = 120.0
DEFAULT_BEATS_PER_BAR = 4

# 音高检测范围
FMIN = "C2"
FMAX = "C7"

# 归并阈值
MIN_NOTE_DUR_FRAMES = 4      # 短于这个的噪声帧丢弃
PITCH_MERGE_TOLERANCE = 0.6  # 半音容差（避免抖动）


=====================================================

```

---

# 安装依赖

## 一次性准备（命令行里跑）

```bat
pip install librosa soundfile
```

**librosa 会自动拉一堆依赖**（numpy / scipy / numba / audioread），**第一次装可能要 3-5 分钟**。

## MP3 解码问题

librosa 读 MP3 需要系统有 **ffmpeg** 或 **audioread + 后端**。

**最省事**：装 ffmpeg

- 下载：https://www.gyan.dev/ffmpeg/builds/（选 `ffmpeg-release-essentials.zip`）
- 解压后把 `bin\ffmpeg.exe` 所在目录加进系统 PATH
- 或者直接把 `ffmpeg.exe` 放到 `AudioTransfer/` 目录（librosa 会去找 PATH，不一定找到本目录）

**不想装 ffmpeg**：先把 MP3 用在线工具转成 WAV（随便搜"MP3 转 WAV"），再用这个 GUI。

---

# 使用流程

1. **双击运行**（和之前一样，用 `.bat` 或打包成 exe）
2. 选择 MP3 文件
3. 选输出目录
4. **填 BPM**（关键！影响音符时长换算）
   - 不知道？先用 120 试，听效果再调
   - 或者用音乐识别软件（如 Mixxx、VirtualDJ）分析
5. 点"开始转换"
6. 检查 `chip_output/xxx.json`

---

# 参数调优

如果结果不好，改脚本里这三个：

```python
FMIN = "C2"                  # 最低音（默认低音 C）
FMAX = "C7"                  # 最高音（默认高音 C）
MIN_NOTE_DUR_FRAMES = 4      # 最短音符帧数（越大忽略越多短促噪声）
PITCH_MERGE_TOLERANCE = 0.6  # 抖动容差（半音）
```

**如果是低音多的曲子** → `FMIN = "C1"`
**如果高音花腔多** → `FMAX = "C8"`
**如果杂音多** → `MIN_NOTE_DUR_FRAMES = 8`

---

# 现实预期

**Fire Emblem MP3** 跑出来大概会：

- ✅ 主旋律能听出轮廓
- ❌ 低音/鼓/伴奏全丢
- ❌ 部分音节会因为混响/和声变成错误音符
- ⚠️ 生成的 JSON 事件可能只有原曲的 1/4

**如果试跑效果还行** → 能当"占位 8-bit 版"用
**如果效果差** → 建议：

1. 去 [VGMusic](https://www.vgmusic.com/) 找 **Fire Emblem 的 MIDI**（几百个）
2. 用 `midi_to_chip_gui.py` 转
3. 效果天壤之别

---

# 建议操作顺序

1. **先试 MP3**（用上面的 GUI）—— 看效果能不能接受
2. **如果不行** → 去 VGMusic 搜 "Fire Emblem"，下载 MIDI
3. **用 midi_to_chip_gui.py 转 MIDI** —— 这就是完整版

要不要我先把 **MIDI 的 GUI 脚本**（`midi_to_chip_gui.py`）也给你？这样两条路都通了。





















# 带界面的 MIDI 转换工具

给你三种方案，从简单到彻底：

| 方案 | 用户操作 | 首次准备 |
|------|---------|---------|
| **A. 双击 `.bat`** | 双击 bat → 弹文件选择 → 弹保存对话框 | 装 Python + mido |
| **B. 打包成 exe** | 双击 exe → 弹文件选择 → 弹保存对话框 | 装 Python + mido + PyInstaller，打包一次 |
| **C. 手动拖拽** | 拖 MIDI 到 bat 上 | 装 Python + mido |

**推荐 B**——装一次环境，打包成 exe 后可以扔给任何人用。

---

# 一、GUI 版 Python 脚本

## `function/tool/AudioTransfer/midi_to_chip_gui.py`




......




---

# 二、双击运行的 `.bat`

## `function/tool/AudioTransfer/启动.bat`

```bat
@echo off
chcp 65001 > nul
cd /d "%~dp0"
python midi_to_chip_gui.py
if errorlevel 1 pause
```

**注意**：文件保存为 **ANSI 或 UTF-8 无 BOM**（用记事本另存为时选"ANSI"最保险），否则 `chcp 65001` 可能不生效。

---

# 三、打包成 exe（推荐）

## 3.1 一次性准备

1. 安装 Python（[python.org](https://www.python.org/downloads/)，勾选 "Add Python to PATH"）
2. 打开命令行（cmd），运行：

```bat
pip install mido pyinstaller
```

## 3.2 打包

```bat
cd D:\Project\Dev_Project_260730\function\tool\AudioTransfer
pyinstaller --onefile --noconsole --name "MIDItoChip" midi_to_chip_gui.py
```

**参数说明**：
- `--onefile` — 打包成单个 exe
- `--noconsole` — 双击不弹黑窗
- `--name` — exe 名字

**产物**：`dist\MIDItoChip.exe`（约 15 MB）

## 3.3 使用

**双击 `MIDItoChip.exe`** → 弹窗 → 选文件 → 转换。

**不需要 Python 环境**，可以扔给任何人。

---

# 四、完整目录

```
function/tool/AudioTransfer/
├── .gdignore                  # 让 Godot 忽略此目录
├── midi_to_chip_gui.py        # GUI 版（推荐）
├── midi_to_chip.py            # 命令行版（备用）
├── 启动.bat                    # 双击运行 GUI
├── README.md
├── requirements.txt
├── input/                     # 放 MIDI
│   └── .gitignore
├── build/                     # PyInstaller 生成（不进 Git）
├── dist/
│   └── MIDItoChip.exe         # ← 打包后的 exe
└── MIDItoChip.spec            # PyInstaller 配置（不进 Git）
```

## `.gitignore`（放在 `AudioTransfer/` 下）

```
__pycache__/
*.pyc
build/
dist/
*.spec
input/*.mid
input/*.midi
```

---

# 五、GUI 使用流程

```
┌────────────────────────────────────────────────────┐
│   MIDI → 8-bit Chip Music 转换工具                  │
├────────────────────────────────────────────────────┤
│ ┌─ 1. 选择 MIDI 文件 ─────────────────────────────┐│
│ │ [选择单个] [选择多个] [清空]                    ││
│ │ ┌──────────────────────────────────────────────┐││
│ │ │ battle.mid                                   │││
│ │ │ boss.mid                                     │││
│ │ └──────────────────────────────────────────────┘││
│ └─────────────────────────────────────────────────┘│
│ ┌─ 2. 输出目录 ───────────────────────────────────┐│
│ │ [D:\...\chip_output            ] [浏览...]      ││
│ └─────────────────────────────────────────────────┘│
│ ┌─ 3. 选项 ───────────────────────────────────────┐│
│ │ 主旋律波形: [pulse_25 ▼]                        ││
│ │ BPM 覆盖: [    ] （留空 = 用 MIDI 内 BPM）      ││
│ │ ☑ 循环播放                                       ││
│ └─────────────────────────────────────────────────┘│
│                                                     │
│           [     开始转换     ]                       │
│                                                     │
│ ┌─ 日志 ──────────────────────────────────────────┐│
│ │ 输出目录: D:\...\chip_output                    ││
│ │ ✓ battle.mid                                     ││
│ │    事件数: 1243  时长: 96.0s  BPM: 140.0        ││
│ │    ch lead: 412 事件                             ││
│ │    ...                                            ││
│ └─────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────┘
```

---

# 六、操作步骤（你只需要做一次）

1. **装 Python**：[python.org](https://www.python.org/downloads/) → 下载 → 安装时勾选 "Add to PATH"
2. **装依赖**：打开 cmd，运行 `pip install mido pyinstaller`
3. **打包 exe**：`cd D:\...\AudioTransfer` 然后运行 `pyinstaller --onefile --noconsole --name MIDItoChip midi_to_chip_gui.py`
4. **完成**：以后双击 `dist\MIDItoChip.exe` 就能用

---

# 七、如果嫌打包麻烦

**直接双击 `启动.bat`** 也能跑（前提是装了 Python + mido）。不用打包，只是要带着 Python 环境。

---

**先按上面步骤跑通**，告诉我：
1. 有没有报错
2. 生成的 JSON 事件数
3. 用记事本打开 JSON 看一眼，格式对不对

之后再给你 **Godot 运行时的 4 个文件**。