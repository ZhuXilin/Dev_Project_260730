class_name ChipSong
extends RefCounted

# ============================================================
#  ChipSong — chip_music_v1 JSON 的数据容器
#  v3 更新（配合 ChipSynth/Sequencer v3）：
#    - validate_chip_style() 增加 noise_period / sweep_* / 波形合法性校验
#    - _wave_from_string() 未知波形名 push_warning，避免静默错音
#    - channels 改为深拷贝，防止外部误改污染 _raw_data
#    - 新增 env 参数白名单说明（写在注释里）
# ============================================================

var title: String = ""
var bpm: float = 120.0
var beats_per_bar: int = 4
var ticks_per_beat: int = 4
var total_ticks: int = 0
var loop_start: int = -1
var loop_end: int = 0

var channels: Array = []   # [{ preset, volume, pan }]
var events: Array = []     # 已解析 + 排序

## 原始 JSON 字典（用于保存回文件）
var _raw_data: Dictionary = {}

# ★ v3: env 支持字段白名单（写在 preset.env 里）
#   ADSR: attack, decay, sustain, release（秒 / 0-1）
#   噪声: noise_period (0-15 NES 索引), noise_short (bool)
#   扫频: sweep_enabled (bool), sweep_period (0-7), sweep_shift (0-7),
#         sweep_negate (bool)
const VALID_WAVES: Array[String] = [
	"pulse_12", "pulse_25", "pulse_50", "pulse_75",
	"triangle", "noise", "saw"
]


# ============================================================
#  加载
# ============================================================
static func from_json(path: String) -> ChipSong:
	if not FileAccess.file_exists(path):
		push_error("ChipSong: 文件不存在 " + path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ChipSong: 打开失败 " + path)
		return null
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		push_error("ChipSong: JSON 解析失败 " + path)
		return null
	return from_dict(data)


static func from_dict(data: Dictionary) -> ChipSong:
	var song := ChipSong.new()
	# 保存原始字典（深拷贝，后续可安全改动）
	song._raw_data = data.duplicate(true)

	# ---- meta ----
	var meta: Dictionary = data.get("meta", {})
	song.title = meta.get("title", "")
	song.bpm = float(meta.get("bpm", 120.0))
	song.beats_per_bar = int(meta.get("beats_per_bar", 4))
	song.ticks_per_beat = int(meta.get("ticks_per_beat", 4))
	song.total_ticks = int(meta.get("total_ticks", 0))
	song.loop_start = int(meta.get("loop_start", -1))
	song.loop_end = int(meta.get("loop_end", 0))

	# ---- channels（★ v3: 深拷贝，防止引用污染 _raw_data）----
	var raw_channels: Array = data.get("channels", [])
	song.channels = []
	for ch_cfg in raw_channels:
		if ch_cfg is Dictionary:
			song.channels.append((ch_cfg as Dictionary).duplicate(true))
	var presets: Dictionary = data.get("presets", {})

	# ---- events（解析 preset → wave + env） ----
	var raw_events: Array = data.get("events", [])
	var resolved: Array = []
	for ev in raw_events:
		if not (ev is Dictionary):
			continue
		var ch: int = int(ev.get("ch", 0))
		if ch < 0 or ch >= song.channels.size():
			continue
		var ch_cfg: Dictionary = song.channels[ch]
		var preset: Dictionary = presets.get(ch_cfg.get("preset", ""), {})
		resolved.append({
			"ch": ch,
			"tick": int(ev.get("tick", 0)),
			"note": int(ev.get("note", 60)),
			"vel": int(ev.get("vel", 100)),
			"dur": int(ev.get("dur", 1)),
			"wave": _wave_from_string(preset.get("wave", "pulse_50")),
			"env": preset.get("env", {}),
		})

	# 按 tick 排序，同 tick 按 ch
	resolved.sort_custom(func(a, b):
		if a["tick"] != b["tick"]:
			return a["tick"] < b["tick"]
		return a["ch"] < b["ch"]
	)
	song.events = resolved

	# 加载时校验 8bit 风格
	var report := song.validate_chip_style()
	if not report["ok"]:
		var t := song.title if song.title != "" else "(未命名)"
		push_warning("[ChipSong] '%s' 有 %d 条 8bit 风格警告：" % [t, report["warnings"].size()])
		for w in report["warnings"]:
			push_warning("  - " + w)

	return song


# ============================================================
#  保存
# ============================================================
## 导出为字典（用于保存回 JSON）
func to_dict() -> Dictionary:
	var out: Dictionary = _raw_data.duplicate(true)
	if not out.has("meta"):
		out["meta"] = {}
	out["meta"]["title"] = title
	out["meta"]["bpm"] = bpm
	out["meta"]["beats_per_bar"] = beats_per_bar
	out["meta"]["ticks_per_beat"] = ticks_per_beat
	out["meta"]["total_ticks"] = total_ticks
	out["meta"]["loop_start"] = loop_start
	out["meta"]["loop_end"] = loop_end

	# 重新序列化 events（剔除运行时字段 wave/env，只保留原始 JSON 5 字段）
	var ev_out : Array = []
	for e in events:
		var ev : Dictionary = e
		ev_out.append({
			"ch": float(ev.get("ch", 0.0)),
			"tick": float(ev.get("tick", 0.0)),
			"note": float(ev.get("note", 60.0)),
			"vel": float(ev.get("vel", 100.0)),
			"dur": float(ev.get("dur", 1.0)),
		})
	out["events"] = ev_out

	# ★ v3: channels 也写回（否则用户改了通道音量/声像没法保存）
	out["channels"] = channels

	return out


## 直接保存到文件
func save_to_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ChipSong: 无法写入 " + path)
		return false
	f.store_string(JSON.stringify(to_dict(), " ", false))
	f.close()
	return true


# ============================================================
#  波形转换
# ============================================================
static func _wave_from_string(s: String) -> int:
	match s:
		"pulse_12": return ChipSynth.Wave.PULSE_12
		"pulse_25": return ChipSynth.Wave.PULSE_25
		"pulse_50": return ChipSynth.Wave.PULSE_50
		"pulse_75": return ChipSynth.Wave.PULSE_75
		"triangle": return ChipSynth.Wave.TRIANGLE
		"noise":    return ChipSynth.Wave.NOISE
		"saw":      return ChipSynth.Wave.SAW
	# ★ v3: 未知波形名给个可见警告，而不是静默 fallback
	push_warning("[ChipSong] 未知波形名 '%s'，已回退为 pulse_50" % s)
	return ChipSynth.Wave.PULSE_50


# ============================================================
#  查询
# ============================================================
func get_channel_count() -> int:
	return channels.size()


func get_channel_volume(ch: int) -> float:
	if ch < 0 or ch >= channels.size():
		return 1.0
	return float(channels[ch].get("volume", 1.0))


func get_channel_pan(ch: int) -> float:
	if ch < 0 or ch >= channels.size():
		return 0.0
	return float(channels[ch].get("pan", 0.0))


func get_duration_seconds() -> float:
	var safe_bpm : float = maxf(bpm, 1.0)
	var safe_tpb : int = maxi(ticks_per_beat, 1)
	return total_ticks / float(safe_tpb) / safe_bpm * 60.0


# ============================================================
#  8bit 风格校验
# ============================================================
## 返回 { "ok": bool, "warnings": [String], "stats": { ... } }
func validate_chip_style() -> Dictionary:
	var result := {
		"ok": true,
		"warnings": [] as Array[String],
		"stats": {
			"channel_count": channels.size(),
			"event_count": events.size(),
			"duration": get_duration_seconds(),
			"bpm": bpm,
			"total_ticks": total_ticks,
		},
	}
	var warnings: Array[String] = []

	# ---- 1. 通道数 ≤ 4（NES 硬件限制） ----
	if channels.size() > 4:
		warnings.append("通道数 %d > 4（NES 只有 4-5 声道）" % channels.size())

	# ---- 2. 单音化检查（同 ch 同 tick 多音） ----
	var multi_count := 0
	var seen: Dictionary = {}
	for ev in events:
		var key := "%d_%d" % [ev["ch"], ev["tick"]]
		if seen.has(key):
			multi_count += 1
		seen[key] = true
	if multi_count > 0:
		warnings.append("有 %d 处同通道同 tick 多音（8bit 单声道）" % multi_count)

	# ---- 3. 音域检查（MIDI 24-96，即 C1-C7） ----
	var range_low := 0
	var range_high := 0
	for ev in events:
		var note: int = ev["note"]
		if note < 24:
			range_low += 1
		elif note > 96:
			range_high += 1
	if range_low > 0:
		warnings.append("有 %d 个音符低于 MIDI 24（C1）" % range_low)
	if range_high > 0:
		warnings.append("有 %d 个音符高于 MIDI 96（C7）" % range_high)

	# ---- 4. 单音时长（> 8 拍 = 32 tick 过长） ----
	var dur_long := 0
	for ev in events:
		if ev["dur"] > 32:
			dur_long += 1
	if dur_long > 0:
		warnings.append("有 %d 个音符时长 > 32 tick（> 8 拍）" % dur_long)

	# ---- 5. 通道预设检查（波形合法性） ----
	var presets: Dictionary = _raw_data.get("presets", {})
	for i in range(channels.size()):
		var preset_name: String = channels[i].get("preset", "")
		if preset_name != "" and presets.has(preset_name):
			var w: String = presets[preset_name].get("wave", "")
			if w != "" and w not in VALID_WAVES:
				warnings.append("通道 %d 使用了未知波形 '%s'" % [i, w])

	# ---- 6. ★ v3: env 新字段校验 ----
	var env_warn := _validate_env_fields(presets)
	warnings.append_array(env_warn)

	result["warnings"] = warnings
	result["ok"] = warnings.is_empty()
	return result


## ★ v3: 校验 presets 里的 env 字段取值范围
func _validate_env_fields(presets: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for preset_name in presets.keys():
		var preset: Dictionary = presets[preset_name]
		if not (preset is Dictionary):
			continue
		var env: Dictionary = preset.get("env", {})
		if not (env is Dictionary) or env.is_empty():
			continue

		# noise_period: 0-15
		if env.has("noise_period"):
			var np: int = int(env["noise_period"])
			if np < 0 or np > 15:
				out.append("preset '%s' 的 noise_period=%d 越界（应为 0-15）"
					% [preset_name, np])

		# sweep_shift: 0-7
		if env.has("sweep_shift"):
			var ss: int = int(env["sweep_shift"])
			if ss < 0 or ss > 7:
				out.append("preset '%s' 的 sweep_shift=%d 越界（应为 0-7）"
					% [preset_name, ss])

		# sweep_period: 0-7（NES 硬件 3-bit）
		if env.has("sweep_period"):
			var sp: int = int(env["sweep_period"])
			if sp < 0 or sp > 7:
				out.append("preset '%s' 的 sweep_period=%d 越界（应为 0-7）"
					% [preset_name, sp])

		# sweep 用在三角波/噪声上是无效的（NES 硬件不支持）
		var wave_name: String = preset.get("wave", "")
		if bool(env.get("sweep_enabled", false)) \
				and wave_name in ["triangle", "noise", "saw"]:
			out.append("preset '%s' 的波形 '%s' 不支持 sweep（NES 硬件限制）"
				% [preset_name, wave_name])

		# noise 通道带 noise_short 但 noise_period 没设 → 只是提示
		# （不报错，默认 0 也是合法的）

	return out


## 打印校验报告
func print_validation_report() -> void:
	var r := validate_chip_style()
	var display_title := title if title != "" else "(未命名)"
	if r["ok"]:
		print("[ChipSong] ✓ %s — 通过（%d 通道 / %d 事件 / %.1fs）" % [
			display_title, r["stats"]["channel_count"], r["stats"]["event_count"],
			r["stats"]["duration"]])
	else:
		print("[ChipSong] ⚠ %s — %d 条警告：" % [display_title, r["warnings"].size()])
		for w in r["warnings"]:
			print("  - " + w)
