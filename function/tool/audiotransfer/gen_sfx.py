#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
8-bit 音效批量生成器

生成一批 chip_music_v1 格式的音效 JSON，放到 content/sound/

用法:
    双击 生成音效.bat
    或 python gen_sfx.py
    或 python gen_sfx.py --out-dir ../content/sound/
"""

import argparse
import json
import sys
from pathlib import Path


# ============================================================
#  音效定义
# ============================================================
def make_sfx(name, bpm, notes, wave="pulse_50", volume=0.5,
             env=None):
    """
    notes: [(note_midi, dur), ...]
    env:   {"attack":..., "decay":..., "sustain":..., "release":...}
    """
    if env is None:
        env = {"attack": 0.001, "decay": 0.03, "sustain": 0.3, "release": 0.02}

    total = sum(d for _, d in notes)
    events = []
    cursor = 0
    for note, dur in notes:
        events.append({
            "ch": 0,
            "tick": cursor,
            "note": int(note),
            "vel": 100,
            "dur": int(dur),
        })
        cursor += int(dur)

    return {
        "format": "chip_music_v1",
        "meta": {
            "title": name,
            "bpm": bpm,
            "beats_per_bar": 4,
            "ticks_per_beat": 4,
            "total_ticks": total,
            "loop_start": -1,
            "loop_end": 0,
        },
        "presets": {
            "sfx": {
                "wave": wave,
                "env": env,
            }
        },
        "channels": [{"preset": "sfx", "volume": volume, "pan": 0.0}],
        "events": events,
    }


# ============================================================
#  预定义音效（可以自由增删改）
# ============================================================
def build_all_sfx():
    # MIDI 音高参考：C4=60, E5=76, A4=69
    return {
        # ---- 选择单位：上行叮咚 ----
        "select_unit": make_sfx(
            "Select Unit", 240,
            notes=[(81, 1), (88, 2)],
            wave="pulse_25",
            volume=0.5,
            env={"attack": 0.001, "decay": 0.03, "sustain": 0.3, "release": 0.02},
        ),

        # ---- 命中：短噪声"砰" ----
        "hit": make_sfx(
            "Hit", 300,
            notes=[(40, 2)],
            wave="noise",
            volume=0.6,
            env={"attack": 0.001, "decay": 0.06, "sustain": 0.0, "release": 0.03},
        ),

        # ---- 未命中：短噪声"咻" ----
        "miss": make_sfx(
            "Miss", 300,
            notes=[(72, 1), (60, 1)],
            wave="noise",
            volume=0.4,
            env={"attack": 0.001, "decay": 0.04, "sustain": 0.0, "release": 0.02},
        ),

        # ---- 治疗：上行和弦分解 ----
        "heal": make_sfx(
            "Heal", 180,
            notes=[(72, 1), (76, 1), (79, 1), (84, 3)],
            wave="triangle",
            volume=0.5,
            env={"attack": 0.005, "decay": 0.05, "sustain": 0.6, "release": 0.05},
        ),

        # ---- 取消：下行短音 ----
        "cancel": make_sfx(
            "Cancel", 240,
            notes=[(72, 1), (65, 1)],
            wave="pulse_25",
            volume=0.5,
            env={"attack": 0.001, "decay": 0.03, "sustain": 0.2, "release": 0.02},
        ),

        # ---- 无效点击：低沉短音 ----
        "invalid_click": make_sfx(
            "Invalid Click", 240,
            notes=[(48, 2)],
            wave="pulse_12",
            volume=0.4,
            env={"attack": 0.001, "decay": 0.05, "sustain": 0.0, "release": 0.03},
        ),

        # ---- 待机：单音 ----
        "wait": make_sfx(
            "Wait", 180,
            notes=[(76, 2)],
            wave="triangle",
            volume=0.4,
            env={"attack": 0.005, "decay": 0.05, "sustain": 0.3, "release": 0.05},
        ),

        # ---- 获得道具：上行欢快 ----
        "get_item": make_sfx(
            "Get Item", 240,
            notes=[(76, 1), (81, 1), (84, 1), (88, 2)],
            wave="pulse_50",
            volume=0.5,
            env={"attack": 0.001, "decay": 0.03, "sustain": 0.4, "release": 0.03},
        ),

        # ---- 移动：极短"嗒"（循环用）----
        "move_sound": make_sfx(
            "Move", 480,
            notes=[(84, 1)],
            wave="noise",
            volume=0.25,
            env={"attack": 0.001, "decay": 0.02, "sustain": 0.0, "release": 0.01},
        ),
    }


# ============================================================
#  主流程
# ============================================================
def main():
    ap = argparse.ArgumentParser(description="8-bit 音效批量生成")
    ap.add_argument("--out-dir", help="输出目录（默认 ../content/sound/）")
    args = ap.parse_args()

    # 脚本所在目录
    script_dir = Path(__file__).parent.resolve()

    # 输出目录：优先命令行，否则默认 ../content/sound/
    if args.out_dir:
        out_dir = Path(args.out_dir).resolve()
    else:
        out_dir = (script_dir / ".." / ".." / ".." / "content" / "sound").resolve()

    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"输出目录: {out_dir}")
    print("-" * 50)

    sfx_dict = build_all_sfx()
    for name, data in sfx_dict.items():
        out_path = out_dir / f"{name}.json"
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        print(f"✓ {name}.json  ({len(data['events'])} 事件)")

    print("-" * 50)
    print(f"共生成 {len(sfx_dict)} 个音效")
    print(f"\n现在可以运行游戏测试音效了。")


if __name__ == "__main__":
    main()