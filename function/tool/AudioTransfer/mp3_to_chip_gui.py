#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MP3/WAV → chip_music JSON 转换器（GUI 版）

★ 8bit 风格自动过滤：
  - 音域归一化（超 [24, 96] 平移八度到范围内）

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

FMIN = "C2"
FMAX = "C7"

MIN_NOTE_DUR_FRAMES = 4
PITCH_MERGE_TOLERANCE = 0.6

# ★ 8bit 音域
NOTE_LOW = 24    # C1
NOTE_HIGH = 96   # C7


# ============================================================
#  核心转换
# ============================================================
def mp3_to_events(mp3_path, bpm, fmin_note=FMIN, fmax_note=FMAX,
                  progress_cb=None):
    if progress_cb:
        progress_cb("加载音频...")

    y, sr = librosa.load(mp3_path, sr=22050, mono=True)

    if progress_cb:
        progress_cb(f"提取音高（时长 {len(y)/sr:.1f}s）...")

    hop_length = 512
    f0, voiced_flag, voiced_prob = librosa.pyin(
        y,
        fmin=librosa.note_to_hz(fmin_note),
        fmax=librosa.note_to_hz(fmax_note),
        sr=sr,
        hop_length=hop_length,
        fill_na=None,
    )

    if progress_cb:
        progress_cb("归并音符...")

    frame_time = hop_length / sr
    tick_per_sec = bpm / 60.0 * TICKS_PER_BEAT

    raw = []
    cur_note = None
    cur_start = 0

    for i in range(len(f0)):
        if not voiced_flag[i] or np.isnan(f0[i]):
            if cur_note is not None:
                if i - cur_start >= MIN_NOTE_DUR_FRAMES:
                    raw.append((cur_start, i, cur_note))
                cur_note = None
            continue

        note = int(round(librosa.hz_to_midi(f0[i])))
        if cur_note is None:
            cur_note = note
            cur_start = i
        elif abs(note - cur_note) > PITCH_MERGE_TOLERANCE:
            if i - cur_start >= MIN_NOTE_DUR_FRAMES:
                raw.append((cur_start, i, cur_note))
            cur_note = note
            cur_start = i

    if cur_note is not None:
        if len(f0) - cur_start >= MIN_NOTE_DUR_FRAMES:
            raw.append((cur_start, len(f0), cur_note))

    events = []
    for start_frame, end_frame, note in raw:
        start_tick = int(round(start_frame * frame_time * tick_per_sec))
        end_tick = int(round(end_frame * frame_time * tick_per_sec))
        dur = max(1, end_tick - start_tick)
        events.append({
            "ch": 0,
            "tick": start_tick,
            "note": int(note),
            "vel": 100,
            "dur": dur,
        })

    total_ticks = max((e["tick"] + e["dur"] for e in events), default=0)
    bar_ticks = TICKS_PER_BEAT * DEFAULT_BEATS_PER_BAR
    total_ticks = ((total_ticks + bar_ticks - 1) // bar_ticks) * bar_ticks

    return events, total_ticks, sr


# ============================================================
#  ★ 8bit 音域归一化
# ============================================================
def normalize_note_range(events, low=NOTE_LOW, high=NOTE_HIGH):
    """把超出 [low, high] 的音符平移八度"""
    shifted = 0
    for e in events:
        orig = e["note"]
        while e["note"] < low:
            e["note"] += 12
        while e["note"] > high:
            e["note"] -= 12
        if e["note"] != orig:
            shifted += 1
    return events, shifted


def convert(mp3_path, output_path, bpm, loop, wave, progress_cb=None):
    events, total_ticks, sr = mp3_to_events(mp3_path, bpm, progress_cb=progress_cb)

    if not events:
        return None, "未检测到音符（可能纯伴奏/鼓点，或音量太低）"

    # ★ 音域归一化
    events, shifted = normalize_note_range(events, low=NOTE_LOW, high=NOTE_HIGH)
    if shifted > 0:
        if progress_cb:
            progress_cb(f"音域归一化：平移 {shifted} 个音符到 [{NOTE_LOW}, {NOTE_HIGH}]")

    presets = {
        "lead": {
            "wave": wave,
            "env": {"attack": 0.005, "decay": 0.05, "sustain": 0.7, "release": 0.05},
        }
    }
    channels = [{"preset": "lead", "volume": 0.8, "pan": 0.0}]

    data = {
        "format": "chip_music_v1",
        "meta": {
            "title": Path(mp3_path).stem,
            "bpm": float(bpm),
            "beats_per_bar": DEFAULT_BEATS_PER_BAR,
            "ticks_per_beat": TICKS_PER_BEAT,
            "total_ticks": total_ticks,
            "loop_start": 0 if loop else -1,
            "loop_end": total_ticks if loop else 0,
            "source": "mp3_extracted",
        },
        "presets": presets,
        "channels": channels,
        "events": events,
    }

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)

    duration = total_ticks / TICKS_PER_BEAT / bpm * 60
    return {
        "events": len(events),
        "total_ticks": total_ticks,
        "duration": duration,
        "bpm": bpm,
        "shifted": shifted,
    }, None


# ============================================================
#  GUI
# ============================================================
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("MP3/WAV → 8-bit Chip Music")
        self.geometry("620x560")
        self.resizable(False, False)

        self.input_files = []
        self.output_dir = tk.StringVar(value="")

        self._build_ui()

    def _build_ui(self):
        pad = {"padx": 10, "pady": 4}

        tk.Label(self, text="MP3 → 8-bit Chip Music（主旋律提取）",
                 font=("Microsoft YaHei", 12, "bold")).pack(**pad)

        warn = tk.Label(self,
                        text="⚠ 仅提取主旋律，复调混音会丢失伴奏\n完整还原请用现成 MIDI",
                        font=("Microsoft YaHei", 8), fg="#cc6600")
        warn.pack(**pad)

        tk.Label(self,
                 text="★ 自动音域归一化：超出 [24, 96] 平移八度",
                 font=("Microsoft YaHei", 8), fg="#0066cc").pack(**pad)

        # ---- 输入 ----
        input_frame = tk.LabelFrame(self, text="1. 选择 MP3/WAV 文件",
                                     font=("Microsoft YaHei", 9))
        input_frame.pack(fill="x", **pad)

        btn_row = tk.Frame(input_frame)
        btn_row.pack(fill="x", padx=6, pady=4)
        tk.Button(btn_row, text="选择单个", command=self.pick_file,
                  width=12).pack(side="left", padx=2)
        tk.Button(btn_row, text="选择多个", command=self.pick_files,
                  width=12).pack(side="left", padx=2)
        tk.Button(btn_row, text="清空", command=self.clear_input,
                  width=8).pack(side="left", padx=2)

        self.file_list = tk.Listbox(input_frame, height=4, font=("Consolas", 9))
        self.file_list.pack(fill="x", padx=6, pady=4)

        # ---- 输出 ----
        output_frame = tk.LabelFrame(self, text="2. 输出目录",
                                      font=("Microsoft YaHei", 9))
        output_frame.pack(fill="x", **pad)
        out_row = tk.Frame(output_frame)
        out_row.pack(fill="x", padx=6, pady=4)
        tk.Entry(out_row, textvariable=self.output_dir,
                 font=("Consolas", 9)).pack(side="left", fill="x",
                                            expand=True, padx=2)
        tk.Button(out_row, text="浏览...", command=self.pick_output_dir,
                  width=10).pack(side="left", padx=2)

        # ---- 选项 ----
        opt_frame = tk.LabelFrame(self, text="3. 选项",
                                   font=("Microsoft YaHei", 9))
        opt_frame.pack(fill="x", **pad)

        bpm_row = tk.Frame(opt_frame)
        bpm_row.pack(fill="x", padx=6, pady=4)
        tk.Label(bpm_row, text="BPM:",
                 font=("Microsoft YaHei", 9)).pack(side="left")
        self.bpm_var = tk.StringVar(value="120")
        tk.Entry(bpm_row, textvariable=self.bpm_var, width=8,
                 font=("Consolas", 9)).pack(side="left", padx=4)
        tk.Label(bpm_row, text="（重要！影响音符时长换算）",
                 font=("Microsoft YaHei", 8), fg="gray").pack(side="left")

        wave_row = tk.Frame(opt_frame)
        wave_row.pack(fill="x", padx=6, pady=4)
        tk.Label(wave_row, text="主旋律波形:",
                 font=("Microsoft YaHei", 9)).pack(side="left")
        self.wave_var = tk.StringVar(value="pulse_25")
        ttk.Combobox(wave_row, textvariable=self.wave_var,
                     values=["pulse_12", "pulse_25", "pulse_50",
                             "pulse_75", "triangle", "saw"],
                     state="readonly", width=12).pack(side="left", padx=4)

        self.loop_var = tk.BooleanVar(value=True)
        tk.Checkbutton(opt_frame, text="循环播放",
                       variable=self.loop_var,
                       font=("Microsoft YaHei", 9)).pack(anchor="w", padx=6)

        # ---- 转换按钮 ----
        self.convert_btn = tk.Button(
            self, text="开始转换", command=self.do_convert,
            font=("Microsoft YaHei", 11, "bold"),
            bg="#2196F3", fg="white", height=2)
        self.convert_btn.pack(fill="x", padx=10, pady=8)

        # ---- 日志 ----
        log_frame = tk.LabelFrame(self, text="日志",
                                   font=("Microsoft YaHei", 9))
        log_frame.pack(fill="both", expand=True, **pad)
        self.log = tk.Text(log_frame, height=8, font=("Consolas", 8),
                           bg="#1e1e1e", fg="#d4d4d4")
        self.log.pack(fill="both", expand=True, padx=4, pady=4)

    # ---------- 事件 ----------
    def pick_file(self):
        path = filedialog.askopenfilename(
            title="选择音频文件",
            filetypes=[("音频", "*.mp3 *.wav *.flac *.ogg *.m4a"),
                       ("所有文件", "*.*")])
        if path:
            self.input_files = [path]
            self._refresh_list()
            self._auto_output(path)

    def pick_files(self):
        paths = filedialog.askopenfilenames(
            title="选择多个音频文件",
            filetypes=[("音频", "*.mp3 *.wav *.flac *.ogg *.m4a"),
                       ("所有文件", "*.*")])
        if paths:
            self.input_files = list(paths)
            self._refresh_list()
            self._auto_output(paths[0])

    def clear_input(self):
        self.input_files = []
        self._refresh_list()

    def _refresh_list(self):
        self.file_list.delete(0, tk.END)
        for p in self.input_files:
            self.file_list.insert(tk.END, Path(p).name)

    def _auto_output(self, sample):
        if not self.output_dir.get():
            self.output_dir.set(str(Path(sample).parent / "chip_output"))

    def pick_output_dir(self):
        path = filedialog.askdirectory(title="选择输出目录")
        if path:
            self.output_dir.set(path)

    def _log(self, text):
        self.log.insert(tk.END, text)
        self.log.see(tk.END)
        self.update_idletasks()

    def _progress(self, text):
        self._log("  " + text + "\n")

    # ---------- 转换 ----------
    def do_convert(self):
        if not self.input_files:
            messagebox.showwarning("提示", "请先选择音频文件")
            return
        out_dir = self.output_dir.get().strip()
        if not out_dir:
            messagebox.showwarning("提示", "请指定输出目录")
            return
        try:
            bpm = float(self.bpm_var.get().strip())
        except ValueError:
            messagebox.showerror("错误", "BPM 必须是数字")
            return

        wave = self.wave_var.get()
        loop = self.loop_var.get()

        self.log.delete("1.0", tk.END)
        self._log(f"输出目录: {out_dir}\n")
        self._log(f"BPM: {bpm}  波形: {wave}  循环: {loop}\n")
        self._log("-" * 60 + "\n")

        ok, fail = 0, 0
        for inp in self.input_files:
            try:
                self._log(f"[{Path(inp).name}]\n")
                out_path = Path(out_dir) / (Path(inp).stem + ".json")
                info, err = convert(inp, str(out_path), bpm, loop, wave,
                                    progress_cb=self._progress)
                if err:
                    self._log(f"  ✗ {err}\n")
                    fail += 1
                else:
                    self._log(f"  ✓ → {out_path.name}\n")
                    self._log(f"     事件数: {info['events']}  "
                              f"时长: {info['duration']:.1f}s\n")
                    ok += 1
            except Exception as ex:
                self._log(f"  ✗ 异常: {ex}\n")
                self._log(traceback.format_exc() + "\n")
                fail += 1

        self._log("-" * 60 + "\n")
        self._log(f"完成: {ok} 成功, {fail} 失败\n")

        if ok > 0:
            messagebox.showinfo("完成",
                                f"成功 {ok} 个，失败 {fail} 个\n\n输出: {out_dir}")


if __name__ == "__main__":
    App().mainloop()