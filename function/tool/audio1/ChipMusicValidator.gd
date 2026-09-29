extends Control

# ============================================================
#  ChipMusicValidator — 8bit 风格批量校验器
#  - F6 运行 ChipMusicValidator.tscn
#  - 扫描 music/ 和 sound/ 下的所有 JSON
#  - 打印/显示 8bit 风格警告
# ============================================================

const MUSIC_DIR : String = "res://content/music/"
const SFX_DIR : String = "res://content/sound/"

var _report_rtl: RichTextLabel = null
var _summary_label: Label = null


func _ready():
	_build_ui()
	call_deferred("_run_validation")


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.11, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 8
	main_vbox.offset_top = 8
	main_vbox.offset_right = -8
	main_vbox.offset_bottom = -8
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# ---- 标题栏 ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	main_vbox.add_child(top)

	var title := Label.new()
	title.text = "8-bit 音乐校验器"
	title.add_theme_font_size_override("font_size", 12)
	top.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var rerun_btn := Button.new()
	rerun_btn.text = "重新校验"
	rerun_btn.add_theme_font_size_override("font_size", 8)
	rerun_btn.pressed.connect(_run_validation)
	top.add_child(rerun_btn)

	# ---- 摘要 ----
	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 9)
	_summary_label.text = "正在校验..."
	main_vbox.add_child(_summary_label)

	# ---- 报告 ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	_report_rtl = RichTextLabel.new()
	_report_rtl.bbcode_enabled = true
	_report_rtl.fit_content = true
	_report_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_rtl.add_theme_font_size_override("normal_font_size", 8)
	scroll.add_child(_report_rtl)

	# ---- 底部提示 ----
	var hint := Label.new()
	hint.text = "校验规则：通道数 ≤ 4 | 同通道同 tick 单音 | 音域 MIDI 24-96 | 单音 ≤ 32 tick"
	hint.add_theme_font_size_override("font_size", 7)
	hint.modulate = Color(0.5, 0.5, 0.5)
	hint.clip_text = true
	main_vbox.add_child(hint)


# ============================================================
#  校验
# ============================================================
func _run_validation():
	_report_rtl.clear()
	_summary_label.text = "正在校验..."

	var music_files: Array = _scan_dir(MUSIC_DIR)
	var sfx_files: Array = _scan_dir(SFX_DIR)

	var total := 0
	var passed := 0
	var warned := 0
	var failed := 0

	_report_rtl.append_text("[b]════ 音乐 (content/music/) ════[/b]\n")
	for path in music_files:
		var r := _validate_file(path)
		total += 1
		if r["status"] == "ok":
			passed += 1
		elif r["status"] == "warn":
			warned += 1
		else:
			failed += 1
		_append_report(path, r)

	_report_rtl.append_text("\n[b]════ 音效 (content/sound/) ════[/b]\n")
	for path in sfx_files:
		var r := _validate_file(path)
		total += 1
		if r["status"] == "ok":
			passed += 1
		elif r["status"] == "warn":
			warned += 1
		else:
			failed += 1
		_append_report(path, r)

	_summary_label.text = "共 %d 个文件  |  ✓ 通过 %d  |  ⚠ 警告 %d  |  ❌ 失败 %d" % [
		total, passed, warned, failed
	]

	# 控制台也打印一份
	print("\n========== ChipMusic 校验报告 ==========")
	print("总计: %d  |  通过: %d  |  警告: %d  |  失败: %d" % [total, passed, warned, failed])
	print("======================================\n")


func _validate_file(path: String) -> Dictionary:
	var r := {
		"status": "ok",
		"warnings": [] as Array[String],
		"stats": {},
	}
	if not FileAccess.file_exists(path):
		r["status"] = "fail"
		r["warnings"].append("文件不存在")
		return r

	var song := ChipSong.from_json(path)
	if song == null:
		r["status"] = "fail"
		r["warnings"].append("JSON 解析失败")
		return r

	var rep := song.validate_chip_style()
	r["warnings"] = rep["warnings"]
	r["stats"] = rep["stats"]
	r["status"] = "ok" if rep["ok"] else "warn"
	return r


func _append_report(path: String, r: Dictionary):
	var fname := path.get_file()
	match r["status"]:
		"ok":
			_report_rtl.append_text("[color=#7FBF7F]  ✓ %s[/color]" % fname)
			_report_rtl.append_text("  [color=#666666](%d ch / %d ev / %.1fs)[/color]\n" % [
				r["stats"].get("channel_count", 0),
				r["stats"].get("event_count", 0),
				r["stats"].get("duration", 0.0),
			])
		"warn":
			_report_rtl.append_text("[color=#FFD966]  ⚠ %s[/color]" % fname)
			_report_rtl.append_text("  [color=#666666](%d ch / %d ev)[/color]\n" % [
				r["stats"].get("channel_count", 0),
				r["stats"].get("event_count", 0),
			])
			for w in r["warnings"]:
				_report_rtl.append_text("     [color=#FFD966]· %s[/color]\n" % w)
		"fail":
			_report_rtl.append_text("[color=#FF6B6B]  ❌ %s[/color]\n" % fname)
			for w in r["warnings"]:
				_report_rtl.append_text("     [color=#FF6B6B]· %s[/color]\n" % w)


func _scan_dir(dir_path: String) -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			result.append(dir_path + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
