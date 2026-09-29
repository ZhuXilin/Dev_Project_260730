extends Control

# ============================================================
#  ChipMusicEditor — 独立 8-bit 音乐编辑器
#  参考 FamiStudio 的钢琴卷帘界面
# ============================================================

const MUSIC_DIR : String = "res://content/music/"

# ---- 网格 ----
const PITCH_MIN : int = 24
const PITCH_MAX : int = 96
const ROW_HEIGHT : float = 7.0
const PIANO_WIDTH : float = 34.0
const RULER_HEIGHT : float = 16.0

# ---- 字号（整体缩小） ----
const FS_TITLE  : int = 8
const FS_PANEL  : int = 7
const FS_BUTTON : int = 6
const FS_LABEL  : int = 6
const FS_SMALL  : int = 6
const FS_TINY   : int = 6

# ---- 尺寸 ----
const BTN_H : int = 14
const SPIN_W : int = 34
const SPIN_H : int = 14
const CH_PANEL_W : int = 82
const PROP_PANEL_W : int = 112

# ---- 颜色 ----
const COL_BG          := Color(0.06, 0.06, 0.08)
const COL_ROW_BLACK   := Color(0.09, 0.09, 0.12)
const COL_ROW_WHITE   := Color(0.13, 0.13, 0.17)
const COL_GRID_TICK   := Color(0.15, 0.15, 0.19)
const COL_GRID_BEAT   := Color(0.24, 0.24, 0.32)
const COL_GRID_BAR    := Color(0.42, 0.42, 0.55)
const COL_PIANO_WHITE := Color(0.82, 0.82, 0.85)
const COL_PIANO_BLACK := Color(0.13, 0.13, 0.16)
const COL_PIANO_LINE  := Color(0.30, 0.30, 0.30)
const COL_NOTE_SEL    := Color(1.0, 0.95, 0.55)
const COL_PLAYHEAD    := Color(1.0, 0.35, 0.35)
const COL_RULER_BG    := Color(0.14, 0.14, 0.17)
const COL_RULER_TEXT  := Color(0.75, 0.75, 0.80)
const COL_HINT_BG     := Color(0.10, 0.10, 0.13, 0.9)
const COL_HINT_TEXT   := Color(0.72, 0.72, 0.78)

var _ch_colors : Array[Color] = [
	Color(0.28, 0.72, 1.00),
	Color(1.00, 0.55, 0.30),
	Color(0.35, 0.95, 0.55),
	Color(1.00, 0.42, 0.72),
]
var _ch_names : Array[String] = ["Pulse 1", "Pulse 2", "Triangle", "Noise"]


# ============================================================
#  GridCanvas 内部类
# ============================================================
class GridCanvas extends Control:
	var editor : Control = null
	func _draw():
		if editor: editor._draw_grid(self)
	func _gui_input(e : InputEvent):
		if editor: editor._on_grid_input(e, self)


# ============================================================
#  状态
# ============================================================
var _player : ChipMusicPlayer = null
var _song : ChipSong = null
var _path : String = ""
var _playhead_tick : float = -1.0

var _selected_channel : int = 0
var _selected_indices : Array[int] = []
var _muted : Array[bool] = [false, false, false, false]

var _px_per_beat : float = 60.0
var _scroll_x : float = 0.0
var _scroll_y : float = 0.0

var _dragging : bool = false
var _drag_data : Array[Dictionary] = []
var _drag_start_mouse : Vector2 = Vector2.ZERO

# ---- UI ----
var _grid_canvas : GridCanvas = null
var _ch_buttons : Array[Button] = []
var _title_edit : LineEdit = null
var _bpm_spin : SpinBox = null
var _bpb_spin : SpinBox = null
var _tpb_spin : SpinBox = null
var _total_spin : SpinBox = null
var _zoom_slider : HSlider = null
var _play_btn : Button = null
var _stop_btn : Button = null
var _save_btn : Button = null
var _status : Label = null
var _note_info : Label = null
var _note_tick : SpinBox = null
var _note_pitch : SpinBox = null
var _note_vel : SpinBox = null
var _note_dur : SpinBox = null
var _note_box : VBoxContainer = null


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_apply_compact_theme()
	_player = ChipMusicPlayer.new()
	add_child(_player)
	_build_ui()
	_auto_load_default()


func _process(_delta : float):
	if _player and _player.is_playing():
		_playhead_tick = float(_player.get_current_tick())
		if _grid_canvas: _grid_canvas.queue_redraw()
	elif _playhead_tick >= 0.0:
		_playhead_tick = -1.0
		if _grid_canvas: _grid_canvas.queue_redraw()


## 全局紧凑主题：去掉按钮 padding、缩小字号、去掉 tooltip 边框
func _apply_compact_theme():
	var t := Theme.new()

	# 默认按钮
	t.set_font_size("font_size", "Button", FS_BUTTON)
	var btn_empty := StyleBoxEmpty.new()
	btn_empty.content_margin_left = 3
	btn_empty.content_margin_right = 3
	btn_empty.content_margin_top = 0
	btn_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Button", btn_empty)
	t.set_stylebox("hover", "Button", btn_empty)
	t.set_stylebox("pressed", "Button", btn_empty)
	t.set_stylebox("focus", "Button", btn_empty)
	t.set_stylebox("disabled", "Button", btn_empty)

	# LineEdit
	t.set_font_size("font_size", "LineEdit", FS_BUTTON)
	var le_empty := StyleBoxEmpty.new()
	le_empty.content_margin_left = 2
	le_empty.content_margin_right = 2
	le_empty.content_margin_top = 0
	le_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "LineEdit", le_empty)
	t.set_stylebox("focus", "LineEdit", le_empty)

	# Label
	t.set_font_size("font_size", "Label", FS_LABEL)

	# CheckBox
	t.set_font_size("font_size", "CheckBox", FS_SMALL)

	# tooltip
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)
	t.set_font_size("font_size", "TooltipPanel", FS_SMALL)
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	tip_sb.border_width_left = 0
	tip_sb.border_width_right = 0
	tip_sb.border_width_top = 0
	tip_sb.border_width_bottom = 0
	tip_sb.corner_radius_top_left = 0
	tip_sb.corner_radius_top_right = 0
	tip_sb.corner_radius_bottom_left = 0
	tip_sb.corner_radius_bottom_right = 0
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

	# HSlider 缩小 grabber
	t.set_constant("grabber_offset", "HSlider", 0)

	theme = t


func _auto_load_default():
	if not DirAccess.dir_exists_absolute(MUSIC_DIR):
		_new_song(); return
	var d := DirAccess.open(MUSIC_DIR)
	if d == null:
		_new_song(); return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".json"):
			d.list_dir_end()
			_load_file(MUSIC_DIR + f)
			return
		f = d.get_next()
	d.list_dir_end()
	_new_song()


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 3
	root.offset_top = 2
	root.offset_right = -3
	root.offset_bottom = -2
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	_make_toolbar(root)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 3)
	root.add_child(hbox)

	_make_channel_panel(hbox)

	_grid_canvas = GridCanvas.new()
	_grid_canvas.editor = self
	_grid_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_canvas.clip_contents = true
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.add_child(_grid_canvas)

	_make_properties_panel(hbox)

	_make_hint_bar(root)


func _make_toolbar(parent : Node):
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 1)
	bar.custom_minimum_size = Vector2(0, BTN_H)
	parent.add_child(bar)

	var b_new := _make_btn("新建")
	b_new.pressed.connect(_new_song)
	bar.add_child(b_new)

	var b_open := _make_btn("打开")
	b_open.pressed.connect(_open_dialog)
	bar.add_child(b_open)

	_save_btn = _make_btn("保存")
	_save_btn.pressed.connect(_save_file)
	bar.add_child(_save_btn)

	bar.add_child(VSeparator.new())

	_play_btn = _make_btn("▶")
	_play_btn.tooltip_text = "播放 (空格)"
	_play_btn.pressed.connect(_play)
	bar.add_child(_play_btn)

	_stop_btn = _make_btn("■")
	_stop_btn.tooltip_text = "停止"
	_stop_btn.pressed.connect(_stop_play)
	bar.add_child(_stop_btn)

	bar.add_child(VSeparator.new())

	bar.add_child(_small_label("BPM"))
	_bpm_spin = _make_spin(40, 300, 1, 100, SPIN_W)
	_bpm_spin.value_changed.connect(func(v : float):
		if _song: _song.bpm = v
	)
	bar.add_child(_bpm_spin)

	bar.add_child(_small_label("拍/小节"))
	_bpb_spin = _make_spin(1, 16, 1, 4, SPIN_W - 8)
	_bpb_spin.value_changed.connect(func(v : float):
		if _song: _song.beats_per_bar = int(v)
		if _grid_canvas: _grid_canvas.queue_redraw()
	)
	bar.add_child(_bpb_spin)

	bar.add_child(_small_label("Tick/拍"))
	_tpb_spin = _make_spin(1, 16, 1, 4, SPIN_W - 8)
	_tpb_spin.value_changed.connect(func(v : float):
		if _song: _song.ticks_per_beat = int(v)
		if _grid_canvas: _grid_canvas.queue_redraw()
	)
	bar.add_child(_tpb_spin)

	bar.add_child(_small_label("总Tick"))
	_total_spin = _make_spin(4, 99999, 4, 64, SPIN_W + 4)
	_total_spin.value_changed.connect(func(v : float):
		if _song: _song.total_ticks = int(v)
		if _grid_canvas: _grid_canvas.queue_redraw()
	)
	bar.add_child(_total_spin)

	bar.add_child(VSeparator.new())

	bar.add_child(_small_label("缩放"))
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 20.0
	_zoom_slider.max_value = 200.0
	_zoom_slider.step = 1.0
	_zoom_slider.value = 60.0
	_zoom_slider.custom_minimum_size = Vector2(60, 0)
	_zoom_slider.value_changed.connect(func(v : float):
		_px_per_beat = v
		if _grid_canvas: _grid_canvas.queue_redraw()
	)
	bar.add_child(_zoom_slider)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	var quit_btn := _make_btn("退出")
	quit_btn.pressed.connect(func(): get_tree().quit())
	bar.add_child(quit_btn)


func _make_channel_panel(parent : Node):
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(CH_PANEL_W, 0)
	left.add_theme_constant_override("separation", 1)
	parent.add_child(left)

	var lbl := Label.new()
	lbl.text = "通道"
	lbl.add_theme_font_size_override("font_size", FS_PANEL)
	left.add_child(lbl)

	for i in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		left.add_child(row)

		var btn := Button.new()
		btn.text = " " + _ch_names[i]
		btn.add_theme_font_size_override("font_size", FS_BUTTON)
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, BTN_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_channel_btn.bind(i))
		row.add_child(btn)
		_ch_buttons.append(btn)

		var m := CheckBox.new()
		m.text = "M"
		m.add_theme_font_size_override("font_size", FS_SMALL)
		m.tooltip_text = "静音"
		m.custom_minimum_size = Vector2(0, BTN_H)
		m.focus_mode = Control.FOCUS_NONE
		m.toggled.connect(func(v : bool):
			_muted[i] = v
			if _player and _player.has_method("set_channel_muted"):
				_player.set_channel_muted(i, v)
		)
		row.add_child(m)

	_refresh_channel_buttons()


func _make_properties_panel(parent : Node):
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(PROP_PANEL_W, 0)
	right.add_theme_constant_override("separation", 2)
	parent.add_child(right)

	var lbl_song := Label.new()
	lbl_song.text = "歌曲"
	lbl_song.add_theme_font_size_override("font_size", FS_PANEL)
	right.add_child(lbl_song)

	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 2)
	right.add_child(r1)
	r1.add_child(_small_label("标题"))
	_title_edit = LineEdit.new()
	_title_edit.add_theme_font_size_override("font_size", FS_BUTTON)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.custom_minimum_size = Vector2(0, BTN_H)
	r1.add_child(_title_edit)

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 4)
	right.add_child(sep)

	var lbl_note := Label.new()
	lbl_note.text = "选中音符"
	lbl_note.add_theme_font_size_override("font_size", FS_PANEL)
	right.add_child(lbl_note)

	_note_info = Label.new()
	_note_info.add_theme_font_size_override("font_size", FS_SMALL)
	_note_info.modulate = Color(0.8, 0.8, 0.8)
	_note_info.text = "（未选中）"
	right.add_child(_note_info)

	_note_box = VBoxContainer.new()
	_note_box.add_theme_constant_override("separation", 1)
	right.add_child(_note_box)

	_note_tick  = _make_prop_row(_note_box, "Tick", 0.0, 99999.0, 1.0, 0.0)
	_note_pitch = _make_prop_row(_note_box, "音高", float(PITCH_MIN), float(PITCH_MAX), 1.0, 60.0)
	_note_vel   = _make_prop_row(_note_box, "力度", 0.0, 127.0, 1.0, 100.0)
	_note_dur   = _make_prop_row(_note_box, "时值", 1.0, 999.0, 1.0, 2.0)

	_note_tick.value_changed.connect(func(_v : float): _on_note_prop_changed())
	_note_pitch.value_changed.connect(func(_v : float): _on_note_prop_changed())
	_note_vel.value_changed.connect(func(_v : float): _on_note_prop_changed())
	_note_dur.value_changed.connect(func(_v : float): _on_note_prop_changed())

	_update_note_inspector()


func _make_hint_bar(parent : Node):
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_HINT_BG
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", FS_SMALL)
	_status.modulate = COL_HINT_TEXT
	_status.clip_text = false
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "左键空白=添加音符 · 左键音符=选中/拖动 · 右键音符=删除 · 中键音符=删除 · Delete=删除选中 · 滚轮=滚动 · Ctrl+滚轮=横向滚动 · 空格=播放/暂停 · Ctrl+S=保存 · Ctrl+O=打开 · Esc=退出"
	panel.add_child(_status)


func _make_prop_row(parent : Node, label_text : String,
		mn : float, mx : float, step : float, val : float) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	row.add_child(_small_label(label_text))
	var sp := _make_spin(mn, mx, step, val, 40)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	return sp


func _make_btn(t : String) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", FS_BUTTON)
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", empty)
	b.add_theme_stylebox_override("disabled", empty)
	return b


func _small_label(t : String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", FS_LABEL)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _make_spin(mn : float, mx : float, step : float,
		val : float, w : float) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = step
	sp.value = val
	sp.custom_minimum_size = Vector2(w, SPIN_H)
	sp.add_theme_font_size_override("font_size", FS_BUTTON)
	# SpinBox 内部的 LineEdit 也强制字号
	var le := sp.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", FS_BUTTON)
	return sp


# ============================================================
#  文件操作（系统原生对话框）
# ============================================================
func _open_dialog():
	var fd := FileDialog.new()
	fd.use_native_dialog = true
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.add_filter("*.json", "Chip Music")
	fd.current_path = ProjectSettings.globalize_path(MUSIC_DIR)
	fd.file_selected.connect(func(p : String):
		_load_file(p)
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered()


func _load_file(path : String):
	_player.stop()
	var s := ChipSong.from_json(path)
	if s == null:
		_status.text = "❌ 加载失败: " + path
		return
	_song = s
	_path = path
	_selected_indices.clear()
	_selected_channel = 0
	_scroll_x = 0.0
	_scroll_y = 0.0
	_playhead_tick = -1.0

	_title_edit.text = s.title
	_bpm_spin.set_value_no_signal(s.bpm)
	_bpb_spin.set_value_no_signal(float(s.beats_per_bar))
	_tpb_spin.set_value_no_signal(float(s.ticks_per_beat))
	_total_spin.set_value_no_signal(float(s.total_ticks))

	_refresh_channel_buttons()
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()
	_status.text = "✓ 已加载: " + path.get_file() \
		+ "  (" + str(s.events.size()) + " 事件)"


func _new_song():
	_player.stop()
	_path = ""
	_song = ChipSong.new()
	_song.title = "Untitled"
	_song.bpm = 100.0
	_song.beats_per_bar = 4
	_song.ticks_per_beat = 4
	_song.total_ticks = 64
	_song.loop_start = 0
	_song.loop_end = 64
	_song.events = []
	_selected_indices.clear()
	_scroll_x = 0.0
	_scroll_y = 0.0

	_title_edit.text = "Untitled"
	_bpm_spin.set_value_no_signal(100.0)
	_bpb_spin.set_value_no_signal(4.0)
	_tpb_spin.set_value_no_signal(4.0)
	_total_spin.set_value_no_signal(64.0)

	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()
	_status.text = "新建歌曲"


func _save_file():
	if _song == null:
		_status.text = "没有可保存的歌曲"
		return
	if _path == "" or _path.begins_with("res://"):
		_save_as_dialog()
		return
	_do_save(_path)


func _save_as_dialog():
	var fd := FileDialog.new()
	fd.use_native_dialog = true
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.add_filter("*.json", "Chip Music")
	fd.current_path = ProjectSettings.globalize_path(MUSIC_DIR)
	fd.current_file = "new_song.json"
	fd.file_selected.connect(func(p : String):
		var pp := p
		if not pp.ends_with(".json"): pp += ".json"
		_do_save(pp)
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered()


func _do_save(path : String):
	_song.title = _title_edit.text
	_song.bpm = _bpm_spin.value
	_song.beats_per_bar = int(_bpb_spin.value)
	_song.ticks_per_beat = int(_tpb_spin.value)
	_song.total_ticks = int(_total_spin.value)
	_song.loop_start = 0
	_song.loop_end = int(_total_spin.value)

	if _song.save_to_json(path):
		_path = path
		_status.text = "✓ 已保存: " + path.get_file()
	else:
		_status.text = "❌ 保存失败: " + path


# ============================================================
#  播放
# ============================================================
func _play():
	if _song == null:
		_status.text = "没有歌曲"
		return
	_player.stop()
	_player.play_song(_song)


func _stop_play():
	_player.stop()
	_playhead_tick = -1.0
	if _grid_canvas: _grid_canvas.queue_redraw()


# ============================================================
#  通道
# ============================================================
func _on_channel_btn(i : int):
	_selected_channel = i
	_selected_indices.clear()
	_refresh_channel_buttons()
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()


func _refresh_channel_buttons():
	for i in range(_ch_buttons.size()):
		var b : Button = _ch_buttons[i]
		b.button_pressed = (i == _selected_channel)
		var c : Color = _ch_colors[i]
		if i == _selected_channel:
			b.modulate = c
		else:
			b.modulate = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)


# ============================================================
#  绘制
# ============================================================
func _draw_grid(c : Control):
	var sz : Vector2 = c.size
	var gx : float = PIANO_WIDTH
	var gy : float = RULER_HEIGHT
	var gw : float = sz.x - gx
	var gh : float = sz.y - gy
	if gw <= 0.0 or gh <= 0.0: return

	c.draw_rect(Rect2(Vector2.ZERO, sz), COL_BG)

	var tpb : int = 4
	var bpb : int = 4
	if _song:
		tpb = maxi(1, int(_song.ticks_per_beat))
		bpb = maxi(1, int(_song.beats_per_bar))

	# 可见音高
	var pitch_top : int = PITCH_MAX - int(_scroll_y / ROW_HEIGHT)
	var pitch_bot : int = PITCH_MAX - int((_scroll_y + gh) / ROW_HEIGHT) - 1
	pitch_top = mini(pitch_top, PITCH_MAX)
	pitch_bot = maxi(pitch_bot, PITCH_MIN)

	# 行背景
	for p in range(pitch_bot, pitch_top + 1):
		var y : float = gy + float(PITCH_MAX - p) * ROW_HEIGHT - _scroll_y
		var col : Color = COL_ROW_BLACK if _is_black(p) else COL_ROW_WHITE
		c.draw_rect(Rect2(gx, y, gw, ROW_HEIGHT), col)

	# 垂直网格
	var px_per_tick : float = _px_per_beat / float(tpb)
	var step : int = 1
	if px_per_tick < 2.0: step = tpb
	if px_per_tick * float(step) < 3.0: step = tpb * bpb

	var first_tick : int = int(_scroll_x / _px_per_beat * float(tpb))
	first_tick = first_tick - (first_tick % step)
	var last_tick : int = int((_scroll_x + gw) / _px_per_beat * float(tpb)) + step

	var t : int = first_tick
	while t <= last_tick:
		var x : float = gx + float(t) / float(tpb) * _px_per_beat - _scroll_x
		if x >= gx and x <= sz.x:
			var col : Color = COL_GRID_TICK
			var w : float = 1.0
			if t % (tpb * bpb) == 0:
				col = COL_GRID_BAR
				w = 1.5
			elif t % tpb == 0:
				col = COL_GRID_BEAT
			c.draw_line(Vector2(x, gy), Vector2(x, sz.y), col, w)
		t += step

	# 音符
	if _song:
		for i in range(_song.events.size()):
			var e : Dictionary = _song.events[i]
			var ec : int = int(e.ch)
			if ec != _selected_channel: continue
			var et : float = float(e.tick)
			var ed : float = float(e.dur)
			var en : float = float(e.note)
			var ex : float = gx + et / float(tpb) * _px_per_beat - _scroll_x
			var ew : float = maxf(3.0, ed / float(tpb) * _px_per_beat)
			var ey : float = gy + float(PITCH_MAX - int(en)) * ROW_HEIGHT - _scroll_y
			if ex + ew < gx or ex > sz.x: continue
			if ey + ROW_HEIGHT < gy or ey > sz.y: continue
			var col : Color = _ch_colors[ec] if ec < _ch_colors.size() else Color.WHITE
			if i in _selected_indices:
				col = COL_NOTE_SEL
			c.draw_rect(Rect2(ex, ey + 1.0, ew, ROW_HEIGHT - 2.0), col)
			c.draw_rect(Rect2(ex, ey + 1.0, ew, ROW_HEIGHT - 2.0),
						col.darkened(0.45), false, 1.0)

	# ---- 标尺 ----
	c.draw_rect(Rect2(0, 0, sz.x, RULER_HEIGHT), COL_RULER_BG)
	var fnt := ThemeDB.fallback_font
	var first_bar : int = int(_scroll_x / (_px_per_beat * float(bpb)))
	var bars_visible : int = int(gw / (_px_per_beat * float(bpb))) + 2
	for b in range(first_bar, first_bar + bars_visible + 1):
		var bx : float = gx + float(b) * _px_per_beat * float(bpb) - _scroll_x
		if bx < gx - 20.0 or bx > sz.x + 20.0: continue
		c.draw_line(Vector2(bx, 0), Vector2(bx, RULER_HEIGHT),
					COL_GRID_BAR, 1.0)
		c.draw_string(fnt, Vector2(bx + 2.0, 10.0),
					  str(b + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, COL_RULER_TEXT)
	var first_beat : int = int(_scroll_x / _px_per_beat)
	var beats_vis : int = int(gw / _px_per_beat) + 2
	for bt in range(first_beat, first_beat + beats_vis + 1):
		var bx : float = gx + float(bt) * _px_per_beat - _scroll_x
		if bx < gx or bx > sz.x: continue
		c.draw_line(Vector2(bx, RULER_HEIGHT - 3.0),
					Vector2(bx, RULER_HEIGHT), COL_GRID_BEAT, 1.0)

	# ---- 钢琴键 ----
	c.draw_rect(Rect2(0, gy, PIANO_WIDTH, gh), Color(0.10, 0.10, 0.13))
	for p in range(pitch_bot, pitch_top + 1):
		var y : float = gy + float(PITCH_MAX - p) * ROW_HEIGHT - _scroll_y
		if y + ROW_HEIGHT < gy or y > sz.y: continue
		var key_col : Color = COL_PIANO_BLACK if _is_black(p) else COL_PIANO_WHITE
		var key_w : float = PIANO_WIDTH - 1.0
		c.draw_rect(Rect2(0, y, key_w, ROW_HEIGHT - 1.0), key_col)
		c.draw_line(Vector2(0, y), Vector2(key_w, y), COL_PIANO_LINE, 1.0)
		if p % 12 == 0:
			var oct : int = int(float(p) / 12.0) - 1
			c.draw_string(fnt, Vector2(1.0, y + ROW_HEIGHT - 1.0),
						  "C%d" % oct, HORIZONTAL_ALIGNMENT_LEFT, -1, 6,
						  Color(0.35, 0.35, 0.40))
	c.draw_line(Vector2(PIANO_WIDTH, gy), Vector2(PIANO_WIDTH, sz.y),
				COL_GRID_BAR, 1.0)

	# ---- 播放头 ----
	if _playhead_tick >= 0.0:
		var px : float = gx + _playhead_tick / float(tpb) * _px_per_beat - _scroll_x
		if px >= gx and px <= sz.x:
			c.draw_line(Vector2(px, gy), Vector2(px, sz.y), COL_PLAYHEAD, 1.5)


# ============================================================
#  输入
# ============================================================
func _on_grid_input(event : InputEvent, c : Control):
	if _song == null: return
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var gx : float = PIANO_WIDTH
	var gy : float = RULER_HEIGHT

	if event is InputEventMouseButton:
		var mb : InputEventMouseButton = event
		var mp : Vector2 = mb.position

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if Input.is_key_pressed(KEY_CTRL) or mp.x < gx:
				_scroll_x = maxf(0.0, _scroll_x - 40.0)
			else:
				_scroll_y = maxf(0.0, _scroll_y - 40.0)
			c.queue_redraw(); return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if Input.is_key_pressed(KEY_CTRL) or mp.x < gx:
				_scroll_x += 40.0
			else:
				_scroll_y += 40.0
			c.queue_redraw(); return

		if mp.x < gx or mp.y < gy: return

		var world_x : float = mp.x - gx + _scroll_x
		var world_y : float = mp.y - gy + _scroll_y
		var click_tick : float = world_x / _px_per_beat * float(tpb)

		# ★ 修复：鼠标所在"行"才是目标 pitch（用 floor 而不是 int(pitch)）
		var row_idx : int = int(floor(world_y / ROW_HEIGHT))
		var click_pitch : int = PITCH_MAX - row_idx
		click_pitch = clampi(click_pitch, PITCH_MIN, PITCH_MAX)

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit : int = _find_note_at(click_tick, float(click_pitch))
				if hit >= 0:
					if not (hit in _selected_indices):
						_selected_indices.clear()
						_selected_indices.append(hit)
				else:
					var ev : Dictionary = _make_event(int(click_tick), click_pitch)
					_song.events.append(ev)
					_selected_indices.clear()
					_selected_indices.append(_song.events.size() - 1)
				_start_drag(mp)
				_update_note_inspector()
				c.queue_redraw()
			else:
				_dragging = false
				_drag_data.clear()

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit : int = _find_note_at(click_tick, float(click_pitch))
			if hit >= 0:
				_song.events.remove_at(hit)
				_selected_indices.clear()
				_update_note_inspector()
				c.queue_redraw()

		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			# ★ 中键也能删除（更快捷）
			var hit : int = _find_note_at(click_tick, float(click_pitch))
			if hit >= 0:
				_song.events.remove_at(hit)
				_selected_indices.clear()
				_update_note_inspector()
				c.queue_redraw()

	elif event is InputEventMouseMotion:
		var mm : InputEventMouseMotion = event
		if _dragging and _drag_data.size() > 0:
			_perform_drag(mm.position)
			c.queue_redraw()


func _make_event(tick : int, pitch : int) -> Dictionary:
	var tpb : int = 4
	if _song: tpb = maxi(1, int(_song.ticks_per_beat))
	return {
		"ch": float(_selected_channel),
		"tick": float(maxi(0, tick)),
		"note": float(clampi(pitch, PITCH_MIN, PITCH_MAX)),
		"vel": 100.0,
		"dur": float(maxi(1, tpb >> 1)),
	}


func _find_note_at(tick : float, pitch : float) -> int:
	if _song == null: return -1
	for i in range(_song.events.size() - 1, -1, -1):
		var e : Dictionary = _song.events[i]
		if int(e.ch) != _selected_channel: continue
		if int(e.note) != int(pitch): continue
		var et : float = float(e.tick)
		var ed : float = float(e.dur)
		if tick >= et - 0.5 and tick <= et + ed + 0.5:
			return i
	return -1


func _start_drag(mouse_pos : Vector2):
	_dragging = true
	_drag_start_mouse = mouse_pos
	_drag_data.clear()
	for idx in _selected_indices:
		if idx < 0 or idx >= _song.events.size(): continue
		var e : Dictionary = _song.events[idx]
		_drag_data.append({
			"idx": idx,
			"orig_tick": float(e.tick),
			"orig_note": float(e.note),
		})


func _perform_drag(mouse_pos : Vector2):
	if _song == null: return
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var dx : float = mouse_pos.x - _drag_start_mouse.x
	var dy : float = mouse_pos.y - _drag_start_mouse.y
	var dtick : int = int(round(dx / _px_per_beat * float(tpb)))
	var dpitch : int = -int(round(dy / ROW_HEIGHT))
	for d in _drag_data:
		var idx : int = int(d.get("idx", -1))
		if idx < 0 or idx >= _song.events.size(): continue
		var e : Dictionary = _song.events[idx]
		var orig_tick : float = float(d.get("orig_tick", 0.0))
		var orig_note : float = float(d.get("orig_note", 60.0))
		e.tick = maxf(0.0, orig_tick + float(dtick))
		e.note = clampf(orig_note + float(dpitch),
			float(PITCH_MIN), float(PITCH_MAX))
	_update_note_inspector()


# ============================================================
#  音符属性检查器
# ============================================================
func _update_note_inspector():
	if _song == null or _selected_indices.size() == 0:
		_note_box.visible = false
		_note_info.text = "（未选中）"
		return
	var idx : int = _selected_indices[0]
	if idx < 0 or idx >= _song.events.size():
		_note_box.visible = false
		_note_info.text = "（索引失效）"
		return
	var e : Dictionary = _song.events[idx]
	_note_box.visible = true
	_note_info.text = "ch %d · tick %d" % [int(e.ch), int(e.tick)]
	_note_tick.set_value_no_signal(float(e.tick))
	_note_pitch.set_value_no_signal(float(e.note))
	_note_vel.set_value_no_signal(float(e.vel))
	_note_dur.set_value_no_signal(float(e.dur))


func _on_note_prop_changed():
	if _song == null or _selected_indices.size() == 0: return
	var idx : int = _selected_indices[0]
	if idx < 0 or idx >= _song.events.size(): return
	var e : Dictionary = _song.events[idx]
	e.tick = maxf(0.0, _note_tick.value)
	e.note = clampf(_note_pitch.value, float(PITCH_MIN), float(PITCH_MAX))
	e.vel = clampf(_note_vel.value, 0.0, 127.0)
	e.dur = maxf(1.0, _note_dur.value)
	if _grid_canvas: _grid_canvas.queue_redraw()


func _delete_selected():
	if _song == null or _selected_indices.size() == 0: return
	var sorted : Array[int] = _selected_indices.duplicate()
	sorted.sort()
	sorted.reverse()
	for idx in sorted:
		if idx >= 0 and idx < _song.events.size():
			_song.events.remove_at(idx)
	_selected_indices.clear()
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()


# ============================================================
#  辅助
# ============================================================
func _is_black(p : int) -> bool:
	var n : int = ((p % 12) + 12) % 12
	return n == 1 or n == 3 or n == 6 or n == 8 or n == 10


func _input(event : InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ke : InputEventKey = event
	if _title_edit and _title_edit.has_focus():
		return
	match ke.keycode:
		KEY_SPACE:
			if _player and _player.is_playing():
				_stop_play()
			else:
				_play()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			_delete_selected()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			get_tree().quit()
		KEY_S:
			if ke.ctrl_pressed:
				_save_file()
				get_viewport().set_input_as_handled()
		KEY_O:
			if ke.ctrl_pressed:
				_open_dialog()
				get_viewport().set_input_as_handled()
		KEY_N:
			if ke.ctrl_pressed:
				_new_song()
				get_viewport().set_input_as_handled()
