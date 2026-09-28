#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MIDI → chip_music JSON 转换器（GUI 版）
双击运行，通过文件对话框选择输入和输出
"""

import sys
import json
import traceback
from pathlib import Path

try:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk
except ImportError:
    print("错误: 缺少 tkinter（一般 Python 自带）")
    sys.exit(1)

try:
    import mido
except ImportError:
    print("错误: 需要 mido 库")
    print("请运行: pip install mido")
    sys.exit(1)


# ============================================================
#  配置
# ============================================================
TICKS_PER_BEAT = 4
DEFAULT_BPM = 120.0
DEFAULT_BEATS_PER_BAR = 4

CHANNEL_PRESETS = {
    0: {"name": "lead",    "wave": "pulse_25",
        "env": {"attack": 0.005, "decay": 0.05, "sustain": 0.7, "release": 0.05}},
    1: {"name": "harmony", "wave": "pulse_12",
        "env": {"attack": 0.010, "decay": 0.05, "sustain": 0.6, "release": 0.05}},
    2: {"name": "bass",    "wave": "triangle",
        "env": {"attack": 0.010, "decay": 0.10, "sustain": 0.8, "release": 0.10}},
    3: {"name": "pad",     "wave": "pulse_50",
        "env": {"attack": 0.020, "decay": 0.10, "sustain": 0.5, "release": 0.15}},
    9: {"name": "drum",    "wave": "noise",
        "env": {"attack": 0.001, "decay": 0.05, "sustain": 0.0, "release": 0.02}},
}
FALLBACK_PRESET = CHANNEL_PRESETS[0]


# ============================================================
#  转换核心
# ============================================================
def load_midi(path):
    mid = mido.MidiFile(path)
    bpm = DEFAULT_BPM
    for track in mid.tracks:
        for msg in track:
            if msg.type == "set_tempo":
                bpm = mido.tempo2bpm(msg.tempo)
                return mid, bpm
    return mid, bpm


def extract_notes(mid):
    midi_tpb = mid.ticks_per_beat
    scale = TICKS_PER_BEAT / midi_tpb

    all_events = []
    channel_set = set()

    for track in mid.tracks:
        abs_time = 0
        note_on_map = {}
        for msg in track:
            abs_time += msg.time
            our_tick = int(round(abs_time * scale))

            if msg.type == "note_on" and msg.velocity > 0:
                key = (msg.channel, msg.note)
                note_on_map[key] = (our_tick, msg.velocity)

            elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
                key = (msg.channel, msg.note)
                if key not in note_on_map:
                    continue
                start_tick, vel = note_on_map.pop(key)
                dur = our_tick - start_tick
                if dur <= 0:
                    dur = 1
                all_events.append({
                    "ch": msg.channel,
                    "tick": start_tick,
                    "note": msg.note,
                    "vel": vel,
                    "dur": dur,
                })
                channel_set.add(msg.channel)

    all_events.sort(key=lambda e: (e["tick"], e["ch"]))
    total_ticks = max((e["tick"] + e["dur"] for e in all_events), default=0)

    bar_ticks = TICKS_PER_BEAT * DEFAULT_BEATS_PER_BAR
    total_ticks = ((total_ticks + bar_ticks - 1) // bar_ticks) * bar_ticks

    return all_events, channel_set, total_ticks


def remap_channels(events, channel_set, lead_wave=None):
    used = sorted(channel_set)
    used = [c for c in used if c != 9] + ([9] if 9 in used else [])

    presets_dict = {}
    channels_list = []
    remap = {}

    for new_ch, old_ch in enumerate(used):
        remap[old_ch] = new_ch
        preset = CHANNEL_PRESETS.get(old_ch, FALLBACK_PRESET).copy()
        if new_ch == 0 and lead_wave:
            preset["wave"] = lead_wave

        presets_dict[preset["name"]] = {
            "wave": preset["wave"],
            "env": preset["env"],
        }

        vol = 0.8
        if preset["name"] == "drum":
            vol = 0.4
        elif preset["name"] == "bass":
            vol = 0.7
        elif preset["name"] == "harmony":
            vol = 0.6

        channels_list.append({
            "preset": preset["name"],
            "volume": vol,
            "pan": 0.0,
        })

    new_events = []
    for e in events:
        if e["ch"] not in remap:
            continue
        e2 = e.copy()
        e2["ch"] = remap[e["ch"]]
        new_events.append(e2)

    return new_events, presets_dict, channels_list


def convert(input_path, output_path, override_bpm=None, loop=True, lead_wave=None):
    mid, midi_bpm = load_midi(input_path)
    bpm = override_bpm if override_bpm else midi_bpm

    events, channel_set, total_ticks = extract_notes(mid)
    if not events:
        return None, "无音符事件"

    new_events, presets_dict, channels_list = remap_channels(
        events, channel_set, lead_wave=lead_wave
    )

    ls = 0 if loop else -1
    le = total_ticks if loop else 0

    data = {
        "format": "chip_music_v1",
        "meta": {
            "title": Path(input_path).stem,
            "bpm": float(bpm),
            "beats_per_bar": DEFAULT_BEATS_PER_BAR,
            "ticks_per_beat": TICKS_PER_BEAT,
            "total_ticks": total_ticks,
            "loop_start": ls,
            "loop_end": le,
        },
        "presets": presets_dict,
        "channels": channels_list,
        "events": new_events,
    }

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

    info = {
        "events": len(new_events),
        "total_ticks": total_ticks,
        "duration": total_ticks / TICKS_PER_BEAT / bpm * 60,
        "bpm": bpm,
        "channels": [
            {"name": channels_list[i]["preset"],
             "count": sum(1 for e in new_events if e["ch"] == i)}
            for i in range(len(channels_list))
        ],
    }
    return info, None


# ============================================================
#  GUI
# ============================================================
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MIDI → 8-bit Chip Music")
        self.geometry("560x420")
        self.resizable(False, False)

        self.input_files = []
        self.output_dir = tk.StringVar(value="")

        self._build_ui()

    def _build_ui(self):
        pad = {"padx": 10, "pady": 4}

        # ---- 标题 ----
        tk.Label(self, text="MIDI → 8-bit Chip Music 转换工具",
                 font=("Microsoft YaHei", 12, "bold")).pack(**pad)

        # ---- 输入 ----
        input_frame = tk.LabelFrame(self, text="1. 选择 MIDI 文件", font=("Microsoft YaHei", 9))
        input_frame.pack(fill="x", **pad)

        btn_row = tk.Frame(input_frame)
        btn_row.pack(fill="x", padx=6, pady=4)
        tk.Button(btn_row, text="选择单个 MIDI", command=self.pick_file, width=16).pack(side="left", padx=2)
        tk.Button(btn_row, text="选择多个 MIDI", command=self.pick_files, width=16).pack(side="left", padx=2)
        tk.Button(btn_row, text="清空", command=self.clear_input, width=8).pack(side="left", padx=2)

        self.file_list = tk.Listbox(input_frame, height=5, font=("Consolas", 9))
        self.file_list.pack(fill="x", padx=6, pady=4)

        # ---- 输出 ----
        output_frame = tk.LabelFrame(self, text="2. 输出目录", font=("Microsoft YaHei", 9))
        output_frame.pack(fill="x", **pad)

        out_row = tk.Frame(output_frame)
        out_row.pack(fill="x", padx=6, pady=4)
        tk.Entry(out_row, textvariable=self.output_dir, font=("Consolas", 9)).pack(
            side="left", fill="x", expand=True, padx=2)
        tk.Button(out_row, text="浏览...", command=self.pick_output_dir, width=10).pack(side="left", padx=2)

        # ---- 选项 ----
        opt_frame = tk.LabelFrame(self, text="3. 选项", font=("Microsoft YaHei", 9))
        opt_frame.pack(fill="x", **pad)

        # 主旋律波形
        wave_row = tk.Frame(opt_frame)
        wave_row.pack(fill="x", padx=6, pady=4)
        tk.Label(wave_row, text="主旋律波形:", font=("Microsoft YaHei", 9)).pack(side="left")
        self.wave_var = tk.StringVar(value="pulse_25")
        wave_combo = ttk.Combobox(wave_row, textvariable=self.wave_var,
                                  values=["pulse_12", "pulse_25", "pulse_50", "pulse_75",
                                          "triangle", "saw"],
                                  state="readonly", width=12)
        wave_combo.pack(side="left", padx=4)

        # BPM 覆盖
        bpm_row = tk.Frame(opt_frame)
        bpm_row.pack(fill="x", padx=6, pady=4)
        tk.Label(bpm_row, text="BPM 覆盖:", font=("Microsoft YaHei", 9)).pack(side="left")
        self.bpm_var = tk.StringVar(value="")
        tk.Entry(bpm_row, textvariable=self.bpm_var, width=8,
                 font=("Consolas", 9)).pack(side="left", padx=4)
        tk.Label(bpm_row, text="（留空 = 用 MIDI 内 BPM）",
                 font=("Microsoft YaHei", 8), fg="gray").pack(side="left")

        # 循环
        self.loop_var = tk.BooleanVar(value=True)
        tk.Checkbutton(opt_frame, text="循环播放", variable=self.loop_var,
                       font=("Microsoft YaHei", 9)).pack(anchor="w", padx=6)

        # ---- 转换按钮 ----
        self.convert_btn = tk.Button(self, text="开始转换", command=self.do_convert,
                                     font=("Microsoft YaHei", 11, "bold"),
                                     bg="#4CAF50", fg="white", height=2)
        self.convert_btn.pack(fill="x", padx=10, pady=8)

        # ---- 日志 ----
        log_frame = tk.LabelFrame(self, text="日志", font=("Microsoft YaHei", 9))
        log_frame.pack(fill="both", expand=True, **pad)

        self.log = tk.Text(log_frame, height=6, font=("Consolas", 8),
                           bg="#1e1e1e", fg="#d4d4d4")
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

        scroll = tk.Scrollbar(self.log, command=self.log.yview)
        self.log.configure(yscrollcommand=scroll.set)

    # ---------- 事件 ----------
    def pick_file(self):
        path = filedialog.askopenfilename(
            title="选择 MIDI 文件",
            filetypes=[("MIDI 文件", "*.mid *.midi"), ("所有文件", "*.*")]
        )
        if path:
            self.input_files = [path]
            self._refresh_file_list()
            self._auto_fill_output_dir(path)

    def pick_files(self):
        paths = filedialog.askopenfilenames(
            title="选择多个 MIDI 文件",
            filetypes=[("MIDI 文件", "*.mid *.midi"), ("所有文件", "*.*")]
        )
        if paths:
            self.input_files = list(paths)
            self._refresh_file_list()
            self._auto_fill_output_dir(paths[0])

    def clear_input(self):
        self.input_files = []
        self._refresh_file_list()

    def _refresh_file_list(self):
        self.file_list.delete(0, tk.END)
        for p in self.input_files:
            self.file_list.insert(tk.END, Path(p).name)

    def _auto_fill_output_dir(self, sample_path):
        # 默认输出到 MIDI 同目录的 chip_output/
        if not self.output_dir.get():
            self.output_dir.set(str(Path(sample_path).parent / "chip_output"))

    def pick_output_dir(self):
        path = filedialog.askdirectory(title="选择输出目录")
        if path:
            self.output_dir.set(path)

    # ---------- 转换 ----------
    def do_convert(self):
        if not self.input_files:
            messagebox.showwarning("提示", "请先选择 MIDI 文件")
            return
        out_dir = self.output_dir.get().strip()
        if not out_dir:
            messagebox.showwarning("提示", "请指定输出目录")
            return

        bpm_override = None
        if self.bpm_var.get().strip():
            try:
                bpm_override = float(self.bpm_var.get().strip())
            except ValueError:
                messagebox.showerror("错误", "BPM 必须是数字")
                return

        lead = self.wave_var.get()
        loop = self.loop_var.get()

        self.log.delete("1.0", tk.END)
        self._log(f"输出目录: {out_dir}\n")
        self._log(f"循环: {loop}  波形: {lead}\n")
        self._log("-" * 60 + "\n")

        ok, fail = 0, 0
        for inp in self.input_files:
            try:
                out_path = Path(out_dir) / (Path(inp).stem + ".json")
                info, err = convert(inp, str(out_path),
                                    override_bpm=bpm_override,
                                    loop=loop, lead_wave=lead)
                if err:
                    self._log(f"✗ {Path(inp).name}: {err}\n")
                    fail += 1
                else:
                    self._log(f"✓ {Path(inp).name}\n")
                    self._log(f"   事件数: {info['events']}  "
                              f"时长: {info['duration']:.1f}s  BPM: {info['bpm']:.1f}\n")
                    for ch in info["channels"]:
                        self._log(f"   ch {ch['name']}: {ch['count']} 事件\n")
                    ok += 1
            except Exception as ex:
                self._log(f"✗ {Path(inp).name}: {ex}\n")
                self._log(traceback.format_exc() + "\n")
                fail += 1

        self._log("-" * 60 + "\n")
        self._log(f"完成: {ok} 成功, {fail} 失败\n")

        if ok > 0:
            messagebox.showinfo("完成", f"成功转换 {ok} 个文件\n失败 {fail} 个\n\n输出: {out_dir}")

    def _log(self, text):
        self.log.insert(tk.END, text)
        self.log.see(tk.END)
        self.update_idletasks()


# ============================================================
#  入口
# ============================================================
if __name__ == "__main__":
    App().mainloop()