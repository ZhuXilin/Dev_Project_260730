extends Control

# ============================================================
#  ChipMusicPreviewer — 独立运行的 8-bit 音乐/音效预览器
#  - F6 运行 ChipMusicPreviewer.tscn
#  - 顶部 Tab 切换：♪ 音乐 / ♫ 音效
#  - 单击选中，双击播放
#  - 播放 / 暂停 / 停止 / 进度条跳转
#  - 可修改 title、循环，保存回 JSON
#  - 空格 播放/暂停，Esc 退出
# ============================================================

const MUSIC_DIR : String = "res://content/music/"
const SFX_DIR : String = "res://content/sound/"

# ---- 播放 ----
var _player: ChipMusicPlayer = null
var _song: ChipSong = null
var _current_path: String = ""
var _selected_path: String = ""      # ★ 当前选中（单击）
var _is_paused: bool = false
var _paused_tick: int = 0
var _drag_seeking: bool = false

# ---- 分类文件缓存 ----
var _files_music: Array = []
var _files_sfx: Array = []
var _current_tab: String = "music"

# ---- UI 引用 ----
var _file_list: VBoxContainer = null
var _tab_music_btn: Button = null
var _tab_sfx_btn: Button = null
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
	_update_tab_style()


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

	# ---- 左：Tab + 文件列表 ----
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.clip_contents = true
	left.add_theme_constant_override("separation", 2)
	hbox.add_child(left)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 0)
	left.add_child(tab_row)

	_tab_music_btn = Button.new()
	_tab_music_btn.text = "♪ 音乐"
	_tab_music_btn.add_theme_font_size_override("font_size", 8)
	_tab_music_btn.toggle_mode = true
	_tab_music_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_music_btn.pressed.connect(func(): _switch_tab("music"))
	tab_row.add_child(_tab_music_btn)

	_tab_sfx_btn = Button.new()
	_tab_sfx_btn.text = "♫ 音效"
	_tab_sfx_btn.add_theme_font_size_override("font_size", 8)
	_tab_sfx_btn.toggle_mode = true
	_tab_sfx_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_sfx_btn.pressed.connect(func(): _switch_tab("sfx"))
	tab_row.add_child(_tab_sfx_btn)

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
	right.clip_contents = true
	hbox.add_child(right)

	_title_label = Label.new()
	_title_label.text = "未选择"
	_title_label.add_theme_font_size_override("font_size", 10)
	_title_label.clip_text = true
	right.add_child(_title_label)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 7)
	_info_label.modulate = Color(0.75, 0.75, 0.75)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info_label)

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

	# 设置行 1：标题
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	right.add_child(title_row)

	var title_lb := Label.new()
	title_lb.text = "标题:"
	title_lb.add_theme_font_size_override("font_size", 8)
	title_row.add_child(title_lb)

	_title_edit = LineEdit.new()
	_title_edit.add_theme_font_size_override("font_size", 8)
	_title_edit.custom_minimum_size = Vector2(60, 0)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_edit)

	# 设置行 2：循环 + 音量 + 保存
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
	_volume_slider.custom_minimum_size = Vector2(60, 0)
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

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 8)
	_toast_label.modulate = Color(0.6, 1.0, 0.6)
	_toast_label.text = ""
	_toast_label.clip_text = true
	right.add_child(_toast_label)

	var hint := Label.new()
	hint.text = "单击选中 · 双击播放 | 空格 播放/暂停 | Esc 退出"
	hint.add_theme_font_size_override("font_size", 7)
	hint.modulate = Color(0.5, 0.5, 0.5)
	hint.clip_text = true
	main_vbox.add_child(hint)

	_update_button_state()


# ============================================================
#  Tab 切换
# ============================================================
func _switch_tab(tab: String):
	if _current_tab == tab:
		return
	_current_tab = tab
	_update_tab_style()
	_refresh_list()


func _update_tab_style():
	if not _tab_music_btn or not _tab_sfx_btn:
		return
	_tab_music_btn.button_pressed = (_current_tab == "music")
	_tab_sfx_btn.button_pressed = (_current_tab == "sfx")
	_tab_music_btn.modulate = Color.WHITE if _current_tab == "music" else Color(0.55, 0.55, 0.55)
	_tab_sfx_btn.modulate = Color.WHITE if _current_tab == "sfx" else Color(0.55, 0.55, 0.55)


# ============================================================
#  文件扫描
# ============================================================
func _scan_files():
	_files_music.clear()
	_files_sfx.clear()
	_scan_dir(MUSIC_DIR, _files_music)
	_scan_dir(SFX_DIR, _files_sfx)
	_files_music.sort()
	_files_sfx.sort()


func _scan_dir(dir_path: String, out: Array):
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			out.append(dir_path + fname)
		fname = dir.get_next()
	dir.list_dir_end()


# ============================================================
#  列表项（自定义：单击选中，双击播放）
# ============================================================
func _refresh_list():
	for c in _file_list.get_children():
		_file_list.remove_child(c)
		c.queue_free()

	var list : Array = _files_music if _current_tab == "music" else _files_sfx

	if list.is_empty():
		var hint := Label.new()
		hint.text = "（无文件）\n把 JSON 放到：\n" + (MUSIC_DIR if _current_tab == "music" else SFX_DIR)
		hint.add_theme_font_size_override("font_size", 7)
		hint.modulate = Color(0.6, 0.6, 0.6)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_file_list.add_child(hint)
		return

	for path in list:
		_file_list.add_child(_make_file_item(path))

	_update_selection_highlight()


func _make_file_item(path: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, 16)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("is_file_item", true)
	row.set_meta("file_path", path)

	# 背景样式（默认透明）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", sb)

	var lb := Label.new()
	lb.text = "  " + path.get_file()
	lb.add_theme_font_size_override("font_size", 8)
	lb.clip_text = true
	lb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 点击穿透到 row
	row.add_child(lb)

	row.gui_input.connect(_on_file_item_gui_input.bind(path))
	row.mouse_entered.connect(_on_file_item_hover_enter.bind(row))
	row.mouse_exited.connect(_on_file_item_hover_exit.bind(row))
	return row


func _on_file_item_gui_input(event: InputEvent, path: String):
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.double_click:
		# ★ 双击：选中 + 加载 + 播放
		_select_file(path)
		_on_file_selected(path)
		_play()
		get_viewport().set_input_as_handled()
	else:
		# ★ 单击：只选中
		_select_file(path)


func _select_file(path: String):
	_selected_path = path
	_update_selection_highlight()


func _update_selection_highlight():
	for child in _file_list.get_children():
		if not child.has_meta("is_file_item"):
			continue
		var p: String = child.get_meta("file_path", "")
		var is_sel: bool = (p == _selected_path)
		var sb: StyleBoxFlat = child.get_theme_stylebox("panel")
		if sb == null:
			sb = StyleBoxFlat.new()
			child.add_theme_stylebox_override("panel", sb)
		if is_sel:
			sb.bg_color = Color(0.25, 0.45, 0.7, 0.85)   # 蓝色高亮
		else:
			sb.bg_color = Color(0, 0, 0, 0)


func _on_file_item_hover_enter(row: PanelContainer):
	if row.get_meta("file_path", "") == _selected_path:
		return
	var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
	if sb:
		sb.bg_color = Color(1, 1, 1, 0.08)


func _on_file_item_hover_exit(row: PanelContainer):
	if row.get_meta("file_path", "") == _selected_path:
		return
	var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
	if sb:
		sb.bg_color = Color(0, 0, 0, 0)


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
	_title_edit.text = s.title

	var duration := s.get_duration_seconds()
	_info_label.text = "%.0f BPM | %d 事件 | %d 通道 | %.1fs" % [
		s.bpm, s.events.size(), s.get_channel_count(), duration
	]

	_progress_slider.min_value = 0
	_progress_slider.max_value = max(1, s.total_ticks)
	_progress_slider.set_value_no_signal(0)
	_time_label.text = "0:00 / " + _fmt_time(duration)

	# 音效默认不循环
	var is_sfx: bool = path.begins_with(SFX_DIR)
	if is_sfx:
		_loop_cb.set_pressed_no_signal(false)
		_song.loop_start = -1
		_song.loop_end = 0
	else:
		_loop_cb.set_pressed_no_signal(s.loop_end > 0)

	_update_button_state()


func _play():
	if _song == null:
		return
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
		_title_label.text = _song.title if _song.title != "" else _current_path.get_file()
		_toast("✓ 已保存到 " + _current_path.get_file())
		print("[Previewer] 已保存: ", _current_path)
	else:
		_toast("❌ 保存失败")


# ============================================================
#  辅助
# ============================================================
func _update_button_state():
	if _play_btn == null:
		return
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
	var m: int = int(sec / 60.0)
	var s: int = total_sec % 60
	return "%d:%02d" % [m, s]


func _toast(msg: String):
	_toast_label.text = msg
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_toast_label):
		_toast_label.text = ""


func _input(event: InputEvent):
	# 鼠标点击：点击输入框外时取消焦点
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _title_edit and _title_edit.has_focus():
			var mp := get_global_mouse_position()
			if not _title_edit.get_global_rect().has_point(mp):
				_title_edit.release_focus()

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

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
