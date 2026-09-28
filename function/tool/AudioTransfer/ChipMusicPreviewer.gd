extends Control

# ============================================================
#  ChipMusicPreviewer — 独立运行的 8-bit 音乐预览器
#  - F6 运行 ChipMusicPreviewer.tscn
#  - 播放 / 暂停 / 停止 / 进度条跳转
#  - 可修改 title、循环，保存回 JSON
#  - 空格 播放/暂停，Esc 退出
# ============================================================

const SCAN_DIRS : Array = [
	"res://content/music/",
	"res://content/sound/",
]

# ---- 播放 ----
var _player: ChipMusicPlayer = null
var _song: ChipSong = null
var _current_path: String = ""
var _is_paused: bool = false
var _paused_tick: int = 0
var _files: Array = []
var _drag_seeking: bool = false

# ---- UI 引用 ----
var _file_list: VBoxContainer = null
var _title_label: Label = null
var _info_label: Label = null
var _time_label: Label = null
var _progress_slider: HSlider = null
var _volume_slider: HSlider = null
var _play_btn: Button = null
var _pause_btn: Button = null
var _stop_btn: Button = null
var _loop_cb: CheckBox = null
var _title_edit: LineEdit = null
var _save_btn: Button = null
var _toast_label: Label = null


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_player = ChipMusicPlayer.new()
	add_child(_player)
	_build_ui()
	_scan_files()
	_refresh_list()


func _process(_delta):
	if _song == null or not _player.is_playing():
		return
	if _drag_seeking:
		return
	var cur_tick: int = _player.get_current_tick()
	_progress_slider.set_value_no_signal(float(cur_tick))
	_update_time_label(cur_tick, _song.total_ticks)


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	# ---- 背景 ----
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
	title.text = "8-bit 音乐预览器"
	title.add_theme_font_size_override("font_size", 12)
	top.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新列表"
	refresh_btn.add_theme_font_size_override("font_size", 8)
	refresh_btn.pressed.connect(func():
		_scan_files()
		_refresh_list()
	)
	top.add_child(refresh_btn)

	# ---- 主体 ----
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(hbox)

	# ---- 左：文件列表（缩窄 180 → 120） ----
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(120, 0)   # ★ 缩窄
	left.clip_contents = true                     # ★ 防溢出
	hbox.add_child(left)

	var left_title := Label.new()
	left_title.text = "— 音乐 —"
	left_title.add_theme_font_size_override("font_size", 8)
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(left_title)

	var file_scroll := ScrollContainer.new()
	file_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(file_scroll)

	_file_list = VBoxContainer.new()
	_file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_list.add_theme_constant_override("separation", 0)
	file_scroll.add_child(_file_list)

	# ---- 右：控制面板 ----
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	right.clip_contents = true                    # ★ 兜底裁剪
	hbox.add_child(right)

	# 标题（可裁剪）
	_title_label = Label.new()
	_title_label.text = "未选择"
	_title_label.add_theme_font_size_override("font_size", 10)
	_title_label.clip_text = true                 # ★ 防长名撑破
	right.add_child(_title_label)

	# 信息（可换行）
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 7)
	_info_label.modulate = Color(0.75, 0.75, 0.75)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # ★ 换行
	right.add_child(_info_label)

	# ---- 进度条 ----
	_progress_slider = HSlider.new()
	_progress_slider.min_value = 0
	_progress_slider.max_value = 100
	_progress_slider.step = 1
	_progress_slider.custom_minimum_size = Vector2(0, 16)
	_progress_slider.value_changed.connect(_on_progress_changed)
	_progress_slider.drag_started.connect(func(): _drag_seeking = true)
	_progress_slider.drag_ended.connect(func(_v): _drag_seeking = false)
	right.add_child(_progress_slider)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 7)
	_time_label.text = "0:00 / 0:00"
	right.add_child(_time_label)

	# ---- 按钮行 ----
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	right.add_child(btn_row)

	_play_btn = Button.new()
	_play_btn.text = "播放"
	_play_btn.add_theme_font_size_override("font_size", 9)
	_play_btn.pressed.connect(_play)
	btn_row.add_child(_play_btn)

	_pause_btn = Button.new()
	_pause_btn.text = "暂停"
	_pause_btn.add_theme_font_size_override("font_size", 9)
	_pause_btn.pressed.connect(_pause)
	btn_row.add_child(_pause_btn)

	_stop_btn = Button.new()
	_stop_btn.text = "停止"
	_stop_btn.add_theme_font_size_override("font_size", 9)
	_stop_btn.pressed.connect(_stop)
	btn_row.add_child(_stop_btn)

	# ---- 设置行 1：标题 ----
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	right.add_child(title_row)

	var title_lb := Label.new()
	title_lb.text = "标题:"
	title_lb.add_theme_font_size_override("font_size", 8)
	title_row.add_child(title_lb)

	_title_edit = LineEdit.new()
	_title_edit.add_theme_font_size_override("font_size", 8)
	_title_edit.custom_minimum_size = Vector2(60, 0)   # ★ 缩小
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_edit)

	# ---- 设置行 2：循环 + 音量 + 保存 ----
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 6)
	right.add_child(opts)

	_loop_cb = CheckBox.new()
	_loop_cb.text = "循环"
	_loop_cb.add_theme_font_size_override("font_size", 8)
	_loop_cb.toggled.connect(_on_loop_toggled)
	opts.add_child(_loop_cb)

	var vol_label := Label.new()
	vol_label.text = "音量:"
	vol_label.add_theme_font_size_override("font_size", 8)
	opts.add_child(vol_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = Globals.music_volume
	_volume_slider.custom_minimum_size = Vector2(60, 0)   # ★ 缩小
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(func(v):
		if _player:
			_player.set_volume(v)
	)
	opts.add_child(_volume_slider)

	_save_btn = Button.new()
	_save_btn.text = "保存"
	_save_btn.add_theme_font_size_override("font_size", 8)
	_save_btn.custom_minimum_size = Vector2(44, 0)
	_save_btn.pressed.connect(_save)
	opts.add_child(_save_btn)

	# ---- Toast ----
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 8)
	_toast_label.modulate = Color(0.6, 1.0, 0.6)
	_toast_label.text = ""
	_toast_label.clip_text = true
	right.add_child(_toast_label)

	# ---- 底部提示 ----
	var hint := Label.new()
	hint.text = "拖动进度条跳转 | 空格 播放/暂停 | Esc 退出"
	hint.add_theme_font_size_override("font_size", 7)
	hint.modulate = Color(0.5, 0.5, 0.5)
	hint.clip_text = true
	main_vbox.add_child(hint)

	_update_button_state()


# ============================================================
#  文件扫描
# ============================================================
func _scan_files():
	_files.clear()
	for dir_path in SCAN_DIRS:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".json"):
				_files.append(dir_path + fname)
			fname = dir.get_next()
		dir.list_dir_end()
	_files.sort()


func _refresh_list():
	for c in _file_list.get_children():
		_file_list.remove_child(c)
		c.queue_free()

	if _files.is_empty():
		var hint := Label.new()
		hint.text = "（无 JSON 文件）\n把 chip_music JSON\n放到 content/music/"
		hint.add_theme_font_size_override("font_size", 7)
		hint.modulate = Color(0.6, 0.6, 0.6)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_file_list.add_child(hint)
		return

	for path in _files:
		var btn := Button.new()
		btn.text = path.get_file()
		btn.add_theme_font_size_override("font_size", 8)
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_file_selected.bind(path))
		_file_list.add_child(btn)


# ============================================================
#  加载 / 播放
# ============================================================
func _on_file_selected(path: String):
	_player.stop()
	_is_paused = false
	_paused_tick = 0

	var s := ChipSong.from_json(path)
	if s == null:
		_title_label.text = "❌ 加载失败"
		_info_label.text = path
		return

	_song = s
	_current_path = path

	_title_label.text = s.title if s.title != "" else path.get_file()
	_title_edit.text = s.title       # ★ 填充输入框

	var duration := s.get_duration_seconds()
	_info_label.text = "%.0f BPM | %d 事件 | %d 通道 | %.1fs" % [
		s.bpm, s.events.size(), s.get_channel_count(), duration
	]

	_progress_slider.min_value = 0
	_progress_slider.max_value = max(1, s.total_ticks)
	_progress_slider.set_value_no_signal(0)
	_time_label.text = "0:00 / " + _fmt_time(duration)
	_loop_cb.set_pressed_no_signal(s.loop_end > 0)
	_update_button_state()


func _play():
	if _song == null:
		return
	# ★ 统一：从进度条当前位置开始（无论是否暂停）
	var start_tick := int(_progress_slider.value)
	if start_tick > 0:
		_player.play_song_from_tick(_song, start_tick)
	else:
		_player.play_song(_song)
	_is_paused = false
	_player.set_volume(_volume_slider.value)
	_update_button_state()


func _pause():
	if _player.is_playing():
		_paused_tick = _player.get_current_tick()
		_player.stop()
		_is_paused = true
		_update_button_state()


func _stop():
	_player.stop()
	_is_paused = false
	_paused_tick = 0
	_progress_slider.set_value_no_signal(0)
	if _song:
		_time_label.text = "0:00 / " + _fmt_time(_song.get_duration_seconds())
	_update_button_state()


# ============================================================
#  事件
# ============================================================
func _on_progress_changed(value: float):
	if _player.is_playing():
		_player.seek_to_tick(int(value))
	if _song:
		_update_time_label(int(value), _song.total_ticks)


func _on_loop_toggled(pressed: bool):
	if _song == null:
		return
	if pressed:
		_song.loop_start = 0
		_song.loop_end = _song.total_ticks
	else:
		_song.loop_start = -1
		_song.loop_end = 0


func _save():
	if _song == null or _current_path == "":
		return
	_song.title = _title_edit.text.strip_edges()

	if _song.save_to_json(_current_path):
		# ★ 同步顶部标题
		_title_label.text = _song.title if _song.title != "" else _current_path.get_file()
		_toast("✓ 已保存到 " + _current_path.get_file())
		print("[Previewer] 已保存: ", _current_path)
	else:
		_toast("❌ 保存失败")


# ============================================================
#  辅助
# ============================================================
func _update_button_state():
	var playing := _player.is_playing()
	_play_btn.disabled = playing
	_pause_btn.disabled = not playing
	_stop_btn.disabled = not playing and not _is_paused
	_save_btn.disabled = (_song == null)


func _update_time_label(cur_tick: int, total_tick: int):
	if _song == null:
		return
	var t1 := _tick_to_seconds(cur_tick)
	var t2 := _tick_to_seconds(total_tick)
	_time_label.text = "%s / %s" % [_fmt_time(t1), _fmt_time(t2)]


func _tick_to_seconds(tick: int) -> float:
	if _song == null or _song.bpm <= 0:
		return 0.0
	return tick / float(_song.ticks_per_beat) / _song.bpm * 60.0


func _fmt_time(sec: float) -> String:
	var total_sec: int = int(sec)
	var m: int = int(sec / 60.0)      # ★ float 除法再取整，避免警告
	var s: int = total_sec % 60
	return "%d:%02d" % [m, s]


func _toast(msg: String):
	_toast_label.text = msg
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_toast_label):
		_toast_label.text = ""


func _input(event: InputEvent):
	# ★ 鼠标点击：点击输入框外时取消焦点
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _title_edit and _title_edit.has_focus():
			var mp := get_global_mouse_position()
			if not _title_edit.get_global_rect().has_point(mp):
				_title_edit.release_focus()

	# 键盘快捷键
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# ★ 标题输入框有焦点时，屏蔽界面快捷键
	if _title_edit and _title_edit.has_focus():
		return

	if event.keycode == KEY_SPACE:
		if _player.is_playing():
			_pause()
		else:
			_play()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		get_tree().quit()
