@tool
extends Control

# ============================================================
#  ChipMusicEditor — 独立 8-bit 音乐编辑器
# ============================================================
#
#  【文件操作】
#    Ctrl+N              新建歌曲
#    Ctrl+O              打开歌曲
#    Ctrl+S              保存
#    Esc                 退出（有未保存修改会弹窗确认）
#
#  【播放控制】
#    空格                播放 / 暂停（记住当前位置）
#    播放按钮            从当前播放头位置开始
#    停止按钮            停止并回到 tick 0
#    拖拽进度条          拖动到指定位置（拖前在播放则续播）
#
#  【音符编辑 — 左键】
#    左键空白（无选中）      添加音符（默认半拍）
#    左键空白（有选中）      取消所有选中
#    左键拖拽空白            框选一片音符
#    Shift + 左键拖拽空白    追加框选（保留已有选中）
#    Shift + 左键点音符      加选 / 减选单个音符
#    左键点音符              选中该音符
#    左键拖拽音符            移动选中组（tick + 音高）
#    拖拽音符右边缘          调整该音符时长（整数 tick）
#
#  【音符编辑 — 右键 / 中键】
#    右键音符                删除该音符
#    中键音符                删除该音符
#    右键空白                取消所有选中
#
#  【键盘】
#    Delete                  删除所有选中音符
#    ↑ / ↓                   选中音符整体移调 ±1 半音
#    ← / →                   选中音符整体左右移动 ±1 tick
#    Shift + ← / →           整体左右移动 ±1 拍
#    Ctrl+A                  全选当前通道所有音符（All 通道时全选）
#
#  【通道】
#    单击通道按钮            切换到该通道（清空选中）
#    All 按钮                显示所有通道（只读，空白处不能新建）
#    M 按钮                  静音该通道
#
#  【视图】
#    滚轮                    垂直滚动
#    Ctrl + 滚轮             水平滚动
#    滚轮（在钢琴键区）      水平滚动
#    顶部缩放滑块            调整横向比例（px / 拍）
#
#  【撤销 / 重做】
#    Ctrl+Z                  撤销（最多 15 步）
#    Ctrl+Shift+Z / Ctrl+Y   重做
#
#  【通道说明】
#    Pulse 1  / 旋律         主旋律（占空比 12.5%）
#    Pulse 2  / 和声         和声 / 副旋律（占空比 25%）
#    Triangle / 贝斯         三角波贝斯（无音量控制）
#    Noise    / 鼓           噪声通道（鼓 / 打击）
# ============================================================

const MUSIC_DIR : String = "res://content/music/"

const PITCH_MIN : int = 24
const PITCH_MAX : int = 96
const ROW_HEIGHT : float = 7.0
const PIANO_WIDTH : float = 22.0
const SEEK_BAR_H : float = 14.0
const RESIZE_HANDLE_PX : float = 4.0

const FS_BUTTON : int = 6
const FS_LABEL  : int = 6
const FS_SMALL  : int = 5
const FS_PANEL  : int = 7
const FS_HINT   : int = 5
const FS_RULER  : int = 6
const FS_NOTE_VEL : int = 5

const BTN_H : int = 13
const SPIN_H : int = 13
const SPIN_W : int = 20
const SPIN_W_LONG : int = 24
const SPIN_W_NOTE : int = 20
const SPIN_W_NOTE_S : int = 18
const CH_PANEL_W : int = 82
const CH_EN_W : int = 40
const MUTE_W : int = 10
const VSEP_W : int = 1
const MAX_UNDO : int = 15

const CH_ALL : int = -1

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

const COL_MUTE_OFF : Color = Color(0.22, 0.22, 0.26)
const COL_MUTE_ON  : Color = Color(0.72, 0.22, 0.28)
const COL_VSEP     : Color = Color(0.36, 0.36, 0.42)

const COL_TRACK_START : Color = Color(0.30, 0.95, 0.45)
const COL_TRACK_END   : Color = Color(1.00, 0.65, 0.30)
const COL_BOX_SEL     : Color = Color(0.40, 0.70, 1.00)

const HINT_TEXT : String = "左键空白=添加/框选 · 左键音符=选中/拖动 · 拖右边缘=改时长 · Shift+拖=追加框选 · 右键空白=取消 · Delete=删除 · ↑↓=移调 · ←→=移动 · Shift+←→=整拍 · Ctrl+A=全选 · Ctrl+Z=撤销 · Ctrl+S=保存 · 空格=播放 · Esc=退出"

var _ch_en_names : Array[String] = ["Pulse 1", "Pulse 2", "Triangle", "Noise"]
var _ch_cn_names : Array[String] = ["旋律", "和声", "贝斯", "鼓"]
var _ch_tooltips : Array[String] = [
	"Pulse 1 (占空比 12.5%) — 主旋律",
	"Pulse 2 (占空比 25%) — 和声 / 副旋律",
	"Triangle — 三角波贝斯（无音量控制）",
	"Noise — 噪声通道（鼓 / 打击）",
]
var _ch_colors : Array[Color] = [
	Color(0.28, 0.72, 1.00),
	Color(1.00, 0.55, 0.30),
	Color(0.35, 0.95, 0.55),
	Color(1.00, 0.42, 0.72),
]


# ============================================================
class GridCanvas extends Control:
	var editor : Control = null
	func _draw():
		if editor: editor._draw_grid(self)
	func _gui_input(e : InputEvent):
		if editor: editor._on_grid_input(e, self)


class SeekBar extends Control:
	signal seek_started()
	signal seek_changed(tick : float)
	signal seek_ended(tick : float)

	var editor : Control = null
	var value : float = 0.0
	var dragging : bool = false

	func _get_total() -> float:
		if editor and editor._song:
			return maxf(1.0, float(editor._song.total_ticks))
		return 64.0

	func set_value(v : float):
		value = clampf(v, 0.0, _get_total())
		queue_redraw()

	func _draw():
		if editor == null: return
		var sz := size
		if sz.x <= 0.0 or sz.y <= 0.0: return
		var ppp : float = editor._px_per_beat
		var sx : float = editor._scroll_x
		var pw : float = editor.PIANO_WIDTH
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.14, 0.14, 0.17))
		var tpb : int = 4
		var bpb : int = 4
		var total : int = 64
		if editor._song:
			tpb = maxi(1, int(editor._song.ticks_per_beat))
			bpb = maxi(1, int(editor._song.beats_per_bar))
			total = int(editor._song.total_ticks)
		var fnt := ThemeDB.fallback_font
		var px_per_bar : float = ppp * float(bpb)
		var first_bar : int = int(floor(sx / px_per_bar))
		var bars_visible : int = int(ceil(sz.x / px_per_bar)) + 2
		for b in range(first_bar, first_bar + bars_visible + 1):
			var bx : float = pw + float(b) * px_per_bar - sx
			if bx < pw - 20.0 or bx > sz.x + 20.0: continue
			draw_line(Vector2(bx, sz.y - 4.0), Vector2(bx, sz.y),
				Color(0.45, 0.45, 0.50), 1.0)
			if bx >= pw - 4.0:
				draw_string(fnt, Vector2(bx + 2.0, sz.y - 4.0),
					str(b + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_RULER,
					COL_RULER_TEXT)

		# Track 头尾标记
		var start_x : float = pw - sx
		if start_x >= pw - 1.0 and start_x <= sz.x + 1.0:
			draw_line(Vector2(start_x, 0), Vector2(start_x, sz.y),
				COL_TRACK_START, 1.0)
		var end_x : float = pw + float(total) / float(tpb) * ppp - sx
		if end_x >= pw - 1.0 and end_x <= sz.x + 1.0:
			draw_line(Vector2(end_x, 0), Vector2(end_x, sz.y),
				COL_TRACK_END, 1.0)

		# 播放头
		var phx : float = pw + value / float(tpb) * ppp - sx
		if phx >= pw and phx <= sz.x:
			draw_line(Vector2(phx, 0), Vector2(phx, sz.y),
				Color(1.0, 0.9, 0.4), 2.0)

		var pos_txt := "%d / %d" % [int(value), total]
		var psize := fnt.get_string_size(pos_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_RULER)
		draw_string(fnt, Vector2(sz.x - psize.x - 4.0, sz.y - 4.0), pos_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_RULER, Color(0.92, 0.92, 0.92))

		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.30, 0.30, 0.35), false, 1.0)

	func _gui_input(event : InputEvent):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					dragging = true
					seek_started.emit()
					_seek(event.position)
					accept_event()
				else:
					dragging = false
					seek_ended.emit(value)
					accept_event()
		elif event is InputEventMouseMotion and dragging:
			_seek(event.position)
			accept_event()

	func _seek(pos : Vector2):
		if editor == null or editor._song == null: return
		var ppp : float = editor._px_per_beat
		var sx : float = editor._scroll_x
		var pw : float = editor.PIANO_WIDTH
		var tpb : int = maxi(1, int(editor._song.ticks_per_beat))
		var tick : float = (pos.x - pw + sx) / ppp * float(tpb)
		value = clampf(tick, 0.0, _get_total())
		seek_changed.emit(value)
		queue_redraw()


# ============================================================
#  状态
# ============================================================
var _player : ChipMusicPlayer = null
var _song : ChipSong = null
var _path : String = ""
var _playhead_tick : float = -1.0
var _dirty : bool = false

var _selected_channel : int = CH_ALL
var _selected_indices : Array[int] = []
var _muted : Array[bool] = [false, false, false, false]

var _px_per_beat : float = 60.0
var _scroll_x : float = 0.0
var _scroll_y : float = 0.0

# 拖拽移动
var _dragging : bool = false
var _drag_data : Array[Dictionary] = []
var _drag_start_mouse : Vector2 = Vector2.ZERO

# 拖拽右边缘 resize
var _resizing_idx : int = -1
var _resizing_start_dur : float = 1.0

# 框选
var _box_selecting : bool = false
var _box_start : Vector2 = Vector2.ZERO
var _box_end : Vector2 = Vector2.ZERO
var _box_additive : bool = false

var _dragging_progress : bool = false
var _was_playing_before_seek : bool = false

var _undo_stack : Array[Dictionary] = []
var _redo_stack : Array[Dictionary] = []

var _grid_canvas : GridCanvas = null
var _seek_bar : SeekBar = null
var _ch_buttons : Array[Button] = []
var _ch_cn_labels : Array[Label] = []
var _all_btn : Button = null
var _mute_buttons : Array[Button] = []
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
var _note_box : HBoxContainer = null


# ============================================================
func _ready():
	_apply_compact_theme()
	_player = ChipMusicPlayer.new()
	add_child(_player)
	_build_ui()
	_auto_load_default()


func _process(_delta : float):
	if _dragging_progress: return
	if _player and _player.is_playing():
		var raw_tick : float = float(_player.get_current_tick())
		var total : float = 64.0
		if _song: total = float(_song.total_ticks)
		_playhead_tick = clampf(raw_tick, 0.0, total)
		if _seek_bar: _seek_bar.set_value(_playhead_tick)
		if _grid_canvas: _grid_canvas.queue_redraw()


func _apply_compact_theme():
	var t := Theme.new()

	t.set_font_size("font_size", "Button", FS_BUTTON)
	var btn_empty := StyleBoxEmpty.new()
	btn_empty.content_margin_left = 1
	btn_empty.content_margin_right = 1
	btn_empty.content_margin_top = 0
	btn_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Button", btn_empty)
	t.set_stylebox("hover", "Button", btn_empty)
	t.set_stylebox("pressed", "Button", btn_empty)
	t.set_stylebox("focus", "Button", btn_empty)
	t.set_stylebox("disabled", "Button", btn_empty)

	t.set_font_size("font_size", "Label", FS_LABEL)
	var label_empty := StyleBoxEmpty.new()
	label_empty.content_margin_left = 0
	label_empty.content_margin_right = 0
	label_empty.content_margin_top = 0
	label_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Label", label_empty)

	t.set_font_size("font_size", "LineEdit", FS_BUTTON)
	var le_empty := StyleBoxEmpty.new()
	le_empty.content_margin_left = 0
	le_empty.content_margin_right = 0
	le_empty.content_margin_top = 0
	le_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "LineEdit", le_empty)
	t.set_stylebox("focus", "LineEdit", le_empty)

	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)
	t.set_font_size("font_size", "TooltipPanel", FS_SMALL)
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

	var sep_sb := StyleBoxLine.new()
	sep_sb.color = COL_VSEP
	sep_sb.thickness = 1
	sep_sb.vertical = true
	sep_sb.grow_begin = 2
	sep_sb.grow_end = 2
	t.set_stylebox("separator", "VSeparator", sep_sb)

	_setup_slider_theme(t)
	theme = t


func _setup_slider_theme(t : Theme):
	var slider_sb := StyleBoxFlat.new()
	slider_sb.bg_color = Color(0.22, 0.22, 0.28, 1.0)
	slider_sb.content_margin_top = 5.0
	slider_sb.content_margin_bottom = 5.0
	t.set_stylebox("slider", "HSlider", slider_sb)

	var grab_sb := StyleBoxFlat.new()
	grab_sb.bg_color = Color(0.45, 0.72, 1.0, 1.0)
	grab_sb.content_margin_top = 5.0
	grab_sb.content_margin_bottom = 5.0
	t.set_stylebox("grabber_area", "HSlider", grab_sb)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab_sb)

	var img := Image.create(4, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.92, 0.92, 1.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	t.set_icon("grabber", "HSlider", tex)
	t.set_icon("grabber_highlight", "HSlider", tex)
	t.set_icon("grabber_disabled", "HSlider", tex)

	t.set_constant("center_grabber", "HSlider", 1)
	t.set_constant("grabber_offset", "HSlider", 0)


func _auto_load_default():
	if not DirAccess.dir_exists_absolute(MUSIC_DIR):
		_new_song(); return
	var d := DirAccess.open(MUSIC_DIR)
	if d == null: _new_song(); return
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
	root.add_theme_constant_override("separation", 1)
	add_child(root)

	_make_toolbar(root)

	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 0)
	root.add_child(main_hbox)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(CH_PANEL_W, 0)
	left_col.add_theme_constant_override("separation", 0)
	main_hbox.add_child(left_col)
	_make_channel_panel(left_col)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 0)
	main_hbox.add_child(right_col)
	_make_seek_bar(right_col)
	_make_grid(right_col)

	_make_info_panel(root)
	_make_hint_bar(root)


func _make_toolbar(parent : Node):
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, BTN_H + 2)
	parent.add_child(scroll)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bar)

	bar.add_child(_mk_btn("新建", func(): _new_song()))
	bar.add_child(_mk_btn("打开", func(): _open_dialog()))
	_save_btn = _mk_btn("保存", func(): _save_file())
	bar.add_child(_save_btn)

	bar.add_child(_make_vsep())

	_play_btn = _mk_btn("播放", func(): _play())
	_play_btn.tooltip_text = "播放 (空格)"
	bar.add_child(_play_btn)

	_stop_btn = _mk_btn("停止", func(): _stop_play())
	_stop_btn.tooltip_text = "停止"
	bar.add_child(_stop_btn)

	bar.add_child(_make_vsep())

	bar.add_child(_small_label("BPM"))
	_bpm_spin = _make_spin(40, 300, 1, 100, SPIN_W)
	_bpm_spin.tooltip_text = "每分钟拍数（回车保存）"
	_bpm_spin.value_changed.connect(func(v : float):
		if _song and not is_equal_approx(_song.bpm, v):
			_song.bpm = v
			_dirty = true
	)
	bar.add_child(_bpm_spin)

	bar.add_child(_small_label("拍"))
	_bpb_spin = _make_spin(1, 16, 1, 4, SPIN_W)
	_bpb_spin.value_changed.connect(func(v : float):
		if _song and _song.beats_per_bar != int(v):
			_song.beats_per_bar = int(v)
			_dirty = true
			if _grid_canvas: _grid_canvas.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
	)
	bar.add_child(_bpb_spin)

	bar.add_child(_small_label("T"))
	_tpb_spin = _make_spin(1, 16, 1, 4, SPIN_W)
	_tpb_spin.tooltip_text = "每拍 tick 数"
	_tpb_spin.value_changed.connect(func(v : float):
		if _song and _song.ticks_per_beat != int(v):
			_song.ticks_per_beat = int(v)
			_dirty = true
			if _grid_canvas: _grid_canvas.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
	)
	bar.add_child(_tpb_spin)

	bar.add_child(_small_label("长"))
	_total_spin = _make_spin(4, 99999, 4, 64, SPIN_W_LONG)
	_total_spin.tooltip_text = "歌曲总长度（tick）"
	_total_spin.value_changed.connect(func(v : float):
		if _song and _song.total_ticks != int(v):
			_song.total_ticks = int(v)
			_dirty = true
			_clamp_scroll()
			if _grid_canvas: _grid_canvas.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
	)
	bar.add_child(_total_spin)

	bar.add_child(_make_vsep())

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 20.0
	_zoom_slider.max_value = 200.0
	_zoom_slider.step = 1.0
	_zoom_slider.value = 60.0
	_zoom_slider.custom_minimum_size = Vector2(52, BTN_H)
	_zoom_slider.tooltip_text = "横向缩放（px / 拍）"
	_zoom_slider.value_changed.connect(func(v : float):
		_px_per_beat = v
		_clamp_scroll()
		if _grid_canvas: _grid_canvas.queue_redraw()
		if _seek_bar: _seek_bar.queue_redraw()
	)
	bar.add_child(_zoom_slider)

	bar.add_child(_make_vsep())

	var quit_btn := _mk_btn("退出", func(): _request_quit())
	bar.add_child(quit_btn)


func _make_vsep() -> Control:
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(VSEP_W, BTN_H)
	return sep


func _make_seek_bar(parent : Node):
	_seek_bar = SeekBar.new()
	_seek_bar.editor = self
	_seek_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_bar.custom_minimum_size = Vector2(0, int(SEEK_BAR_H))
	_seek_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_seek_bar.seek_started.connect(_on_seek_started)
	_seek_bar.seek_changed.connect(_on_seek_changed)
	_seek_bar.seek_ended.connect(_on_seek_ended)
	parent.add_child(_seek_bar)


func _make_channel_panel(parent : Node):
	var lbl := Label.new()
	lbl.text = "通道"
	lbl.add_theme_font_size_override("font_size", FS_PANEL)
	parent.add_child(lbl)

	var all_row := HBoxContainer.new()
	all_row.add_theme_constant_override("separation", 1)
	parent.add_child(all_row)

	_all_btn = Button.new()
	_all_btn.text = "All"
	_all_btn.tooltip_text = "显示全部通道"
	_all_btn.add_theme_font_size_override("font_size", FS_BUTTON)
	_all_btn.toggle_mode = true
	_all_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_all_btn.custom_minimum_size = Vector2(CH_EN_W, BTN_H)
	_all_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_all_btn.focus_mode = Control.FOCUS_NONE
	_all_btn.clip_text = true
	_all_btn.pressed.connect(func(): _on_channel_btn(CH_ALL))
	all_row.add_child(_all_btn)

	var all_cn := Label.new()
	all_cn.text = "全部"
	all_cn.add_theme_font_size_override("font_size", FS_BUTTON)
	all_cn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	all_cn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_row.add_child(all_cn)

	for i in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		parent.add_child(row)

		var btn := Button.new()
		btn.text = _ch_en_names[i]
		btn.tooltip_text = _ch_tooltips[i]
		btn.add_theme_font_size_override("font_size", FS_BUTTON)
		btn.toggle_mode = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(CH_EN_W, BTN_H)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.pressed.connect(_on_channel_btn.bind(i))
		row.add_child(btn)
		_ch_buttons.append(btn)

		var cn_lbl := Label.new()
		cn_lbl.text = _ch_cn_names[i]
		cn_lbl.add_theme_font_size_override("font_size", FS_BUTTON)
		cn_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cn_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cn_lbl.modulate = Color(0.75, 0.75, 0.78)
		row.add_child(cn_lbl)
		_ch_cn_labels.append(cn_lbl)

		var m := Button.new()
		m.text = "M"
		m.toggle_mode = true
		m.tooltip_text = "静音"
		m.add_theme_font_size_override("font_size", FS_SMALL)
		m.custom_minimum_size = Vector2(MUTE_W, BTN_H)
		m.focus_mode = Control.FOCUS_NONE
		_make_mute_button_style(m)
		m.toggled.connect(func(v : bool):
			_muted[i] = v
			_apply_mute_visual(m, v)
			if _player and _player.has_method("set_channel_muted"):
				_player.set_channel_muted(i, v)
		)
		_apply_mute_visual(m, false)
		row.add_child(m)
		_mute_buttons.append(m)

	_refresh_channel_buttons()


func _make_mute_button_style(m : Button):
	var sb_off := StyleBoxFlat.new()
	sb_off.bg_color = COL_MUTE_OFF
	sb_off.content_margin_left = 0
	sb_off.content_margin_right = 0
	sb_off.content_margin_top = 0
	sb_off.content_margin_bottom = 0
	var sb_on := StyleBoxFlat.new()
	sb_on.bg_color = COL_MUTE_ON
	sb_on.content_margin_left = 0
	sb_on.content_margin_right = 0
	sb_on.content_margin_top = 0
	sb_on.content_margin_bottom = 0
	m.add_theme_stylebox_override("normal", sb_off)
	m.add_theme_stylebox_override("hover", sb_off)
	m.add_theme_stylebox_override("focus", sb_off)
	m.add_theme_stylebox_override("pressed", sb_on)
	m.add_theme_stylebox_override("disabled", sb_off)


func _apply_mute_visual(m : Button, muted : bool):
	m.modulate = Color(1.0, 0.5, 0.5) if muted else Color(0.7, 0.7, 0.7)


func _make_grid(parent : Node):
	_grid_canvas = GridCanvas.new()
	_grid_canvas.editor = self
	_grid_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_canvas.clip_contents = true
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_grid_canvas)


func _make_info_panel(parent : Node):
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	panel.add_child(row)

	row.add_child(_small_label("标题"))
	_title_edit = LineEdit.new()
	_title_edit.add_theme_font_size_override("font_size", FS_BUTTON)
	_title_edit.custom_minimum_size = Vector2(80, BTN_H - 1)
	_title_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_edit.placeholder_text = "（无标题）"
	_title_edit.text_changed.connect(func(_t : String): _dirty = true)
	row.add_child(_title_edit)

	var g1 := Control.new()
	g1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g1.custom_minimum_size = Vector2(4, 0)
	row.add_child(g1)

	_note_info = Label.new()
	_note_info.add_theme_font_size_override("font_size", FS_SMALL)
	_note_info.modulate = Color(0.8, 0.8, 0.8)
	_note_info.text = "（未选中）"
	_note_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note_info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(_note_info)

	_note_box = HBoxContainer.new()
	_note_box.add_theme_constant_override("separation", 1)
	_note_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(_note_box)

	_note_tick  = _make_inline_spin(_note_box, "tick", 0.0, 99999.0, 1.0, 0.0, SPIN_W_NOTE)
	_note_pitch = _make_inline_spin(_note_box, "音高", float(PITCH_MIN), float(PITCH_MAX), 1.0, 60.0, SPIN_W_NOTE_S)
	_note_vel   = _make_inline_spin(_note_box, "力度", 0.0, 127.0, 1.0, 100.0, SPIN_W_NOTE_S)
	_note_dur   = _make_inline_spin(_note_box, "时长", 1.0, 999.0, 1.0, 2.0, SPIN_W_NOTE_S)

	_note_tick.value_changed.connect(func(_v : float): _on_note_prop_changed())
	_note_pitch.value_changed.connect(func(_v : float): _on_note_prop_changed())
	_note_vel.value_changed.connect(func(_v : float): _on_note_prop_changed())
	_note_dur.value_changed.connect(func(_v : float): _on_note_prop_changed())

	_update_note_inspector()


func _make_hint_bar(parent : Node):
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13, 0.9)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", FS_HINT)
	_status.modulate = Color(0.72, 0.72, 0.78)
	_status.text = HINT_TEXT
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)


# ---------------- UI 小工具 ----------------
func _mk_btn(t : String, cb : Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", FS_BUTTON)
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _small_label(t : String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", FS_LABEL)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.custom_minimum_size = Vector2(0, BTN_H)
	return l


func _make_spin(mn : float, mx : float, step : float,
		val : float, w : float) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = step
	sp.value = val
	sp.custom_minimum_size = Vector2(w, SPIN_H)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sp.add_theme_font_size_override("font_size", FS_BUTTON)
	sp.add_theme_constant_override("separation", 0)
	sp.ready.connect(func(): _setup_spin(sp), CONNECT_ONE_SHOT)
	return sp


func _setup_spin(sp : SpinBox):
	var le := sp.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", FS_BUTTON)
		le.custom_minimum_size = Vector2(0, SPIN_H - 2)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.editable = true
		le.select_all_on_focus = true
		le.context_menu_enabled = false
		le.text_submitted.connect(func(_t : String):
			call_deferred("_save_after_spin")
		)
	var btns := sp.find_children("*", "Button", true, false)
	for b in btns:
		_compact_spin_arrow_button(b as Button)


func _compact_spin_arrow_button(btn : Button):
	btn.custom_minimum_size = Vector2(5, 4)
	btn.icon_max_width = 4
	btn.icon_max_height = 4
	btn.focus_mode = Control.FOCUS_NONE
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 0
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.add_theme_stylebox_override("disabled", empty)


func _save_after_spin():
	if _song == null: return
	if _path == "" or _path.begins_with("res://"): return
	_do_save(_path)


func _make_inline_spin(parent : Node, label_text : String,
		mn : float, mx : float, step : float, val : float, w : float) -> SpinBox:
	parent.add_child(_small_label(label_text))
	var sp := _make_spin(mn, mx, step, val, w)
	parent.add_child(sp)
	return sp


# ============================================================
#  滚动 clamp
# ============================================================
func _get_max_scroll_x() -> float:
	if _song == null or _grid_canvas == null: return 0.0
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var gw : float = _grid_canvas.size.x - PIANO_WIDTH
	if gw <= 0.0: return 0.0
	var total_w : float = float(_song.total_ticks) / float(tpb) * _px_per_beat
	return maxf(0.0, total_w - gw + _px_per_beat)


func _clamp_scroll():
	_scroll_x = clampf(_scroll_x, 0.0, _get_max_scroll_x())


# ============================================================
#  撤销 / 重做
# ============================================================
func _make_snapshot() -> Dictionary:
	var ev : Array = []
	if _song:
		for e in _song.events:
			ev.append((e as Dictionary).duplicate())
	return {
		"events": ev,
		"title": _song.title if _song else "",
		"bpm": _song.bpm if _song else 100.0,
		"beats_per_bar": _song.beats_per_bar if _song else 4,
		"ticks_per_beat": _song.ticks_per_beat if _song else 4,
		"total_ticks": _song.total_ticks if _song else 64,
		"loop_start": _song.loop_start if _song else 0,
		"loop_end": _song.loop_end if _song else 0,
	}


func _push_undo():
	if _song == null: return
	_undo_stack.append(_make_snapshot())
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_dirty = true


func _apply_snapshot(snap : Dictionary):
	if _song == null: return
	_song.events.clear()
	for e in snap["events"]:
		_song.events.append((e as Dictionary).duplicate())
	_song.title = snap["title"]
	_song.bpm = snap["bpm"]
	_song.beats_per_bar = snap["beats_per_bar"]
	_song.ticks_per_beat = snap["ticks_per_beat"]
	_song.total_ticks = snap["total_ticks"]
	_song.loop_start = snap["loop_start"]
	_song.loop_end = snap["loop_end"]

	_title_edit.text = _song.title
	_bpm_spin.set_value_no_signal(_song.bpm)
	_bpb_spin.set_value_no_signal(float(_song.beats_per_bar))
	_tpb_spin.set_value_no_signal(float(_song.ticks_per_beat))
	_total_spin.set_value_no_signal(float(_song.total_ticks))

	_selected_indices.clear()
	_clamp_scroll()
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()
	if _seek_bar: _seek_bar.queue_redraw()


func _undo():
	if _undo_stack.is_empty():
		_status.text = "无可撤销操作"; return
	_redo_stack.append(_make_snapshot())
	var snap : Dictionary = _undo_stack.pop_back()
	_apply_snapshot(snap)
	_dirty = true
	_status.text = "↶ 撤销 (剩余 %d 步)" % _undo_stack.size()


func _redo():
	if _redo_stack.is_empty():
		_status.text = "无可重做操作"; return
	_undo_stack.append(_make_snapshot())
	var snap : Dictionary = _redo_stack.pop_back()
	_apply_snapshot(snap)
	_dirty = true
	_status.text = "↷ 重做 (剩余 %d 步)" % _redo_stack.size()


# ============================================================
#  退出确认
# ============================================================
func _request_quit():
	if not _dirty:
		get_tree().quit(); return
	_show_unsaved_dialog()


func _show_unsaved_dialog():
	var dlg := ConfirmationDialog.new()
	dlg.title = "未保存的修改"
	dlg.dialog_text = "当前歌曲有未保存的修改，是否保存？"
	dlg.ok_button_text = "保存"
	dlg.cancel_button_text = "不保存"
	dlg.add_button("取消", true, "cancel")
	dlg.confirmed.connect(func():
		_save_file()
		if not _dirty: get_tree().quit()
		else: dlg.queue_free()
	)
	dlg.canceled.connect(func(): get_tree().quit())
	dlg.custom_action.connect(func(action : String):
		if action == "cancel":
			dlg.hide(); dlg.queue_free()
	)
	add_child(dlg)
	dlg.popup_centered(Vector2i(300, 100))


# ============================================================
#  文件
# ============================================================
func _open_dialog():
	var fd := FileDialog.new()
	fd.use_native_dialog = true
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.add_filter("*.json", "Chip Music")
	fd.current_path = ProjectSettings.globalize_path(MUSIC_DIR)
	fd.file_selected.connect(func(p : String):
		_load_file(p); fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered()


func _load_file(path : String):
	_player.stop()
	var s := ChipSong.from_json(path)
	if s == null:
		_status.text = "❌ 加载失败: " + path; return
	_song = s
	_path = path
	_selected_indices.clear()
	_selected_channel = CH_ALL
	_scroll_x = 0.0
	_scroll_y = 0.0
	_playhead_tick = -1.0
	_undo_stack.clear()
	_redo_stack.clear()
	_dirty = false

	_title_edit.text = s.title
	_bpm_spin.set_value_no_signal(s.bpm)
	_bpb_spin.set_value_no_signal(float(s.beats_per_bar))
	_tpb_spin.set_value_no_signal(float(s.ticks_per_beat))
	_total_spin.set_value_no_signal(float(s.total_ticks))
	if _seek_bar: _seek_bar.set_value(0.0)

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
	_selected_channel = CH_ALL
	_scroll_x = 0.0
	_scroll_y = 0.0
	_playhead_tick = -1.0
	_undo_stack.clear()
	_redo_stack.clear()
	_dirty = false

	_title_edit.text = "Untitled"
	_bpm_spin.set_value_no_signal(100.0)
	_bpb_spin.set_value_no_signal(4.0)
	_tpb_spin.set_value_no_signal(4.0)
	_total_spin.set_value_no_signal(64.0)
	if _seek_bar: _seek_bar.set_value(0.0)

	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()
	_status.text = "新建歌曲"


func _save_file():
	if _song == null:
		_status.text = "没有可保存的歌曲"; return
	if _path == "" or _path.begins_with("res://"):
		_save_as_dialog(); return
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
		_do_save(pp); fd.queue_free()
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

	# 裁剪超出 total_ticks 的音符
	var total : float = float(_song.total_ticks)
	var filtered : Array = []
	var trimmed_count : int = 0
	var clipped_count : int = 0
	for e in _song.events:
		var ev : Dictionary = e
		var tick : float = float(ev.tick)
		var dur : float = float(ev.dur)
		if tick >= total:
			trimmed_count += 1
			continue
		if tick + dur > total:
			ev = ev.duplicate()
			ev.dur = total - tick
			clipped_count += 1
		filtered.append(ev)
	_song.events = filtered

	if _song.save_to_json(path):
		_path = path
		_dirty = false
		var extra : String = ""
		if trimmed_count > 0 or clipped_count > 0:
			extra = "  [裁掉 %d, 截断 %d]" % [trimmed_count, clipped_count]
		_status.text = "✓ 已保存: " + path.get_file() + extra
		_selected_indices.clear()
		_update_note_inspector()
		if _grid_canvas: _grid_canvas.queue_redraw()
	else:
		_status.text = "❌ 保存失败: " + path


# ============================================================
#  播放
# ============================================================
func _play():
	if _song == null: return
	_player.stop()
	if _playhead_tick > 0.0:
		_player.play_song_from_tick(_song, int(_playhead_tick))
	else:
		_player.play_song(_song)


func _stop_play():
	_player.stop()
	_playhead_tick = -1.0
	if _seek_bar: _seek_bar.set_value(0.0)
	if _grid_canvas: _grid_canvas.queue_redraw()


func _on_seek_started():
	_dragging_progress = true
	_was_playing_before_seek = _player.is_playing()
	if _was_playing_before_seek: _player.stop()


func _on_seek_changed(tick : float):
	_playhead_tick = tick
	if _grid_canvas: _grid_canvas.queue_redraw()


func _on_seek_ended(tick : float):
	_dragging_progress = false
	_playhead_tick = tick
	if _song == null:
		_was_playing_before_seek = false; return
	if _was_playing_before_seek:
		_player.play_song_from_tick(_song, int(tick))
	_was_playing_before_seek = false
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
	if _all_btn:
		_all_btn.button_pressed = (_selected_channel == CH_ALL)
		_all_btn.modulate = Color(1, 1, 1) if _selected_channel == CH_ALL else Color(0.65, 0.65, 0.65)
	for i in range(_ch_buttons.size()):
		var b : Button = _ch_buttons[i]
		b.button_pressed = (i == _selected_channel)
		var c : Color = _ch_colors[i]
		if i == _selected_channel:
			b.modulate = c
			if i < _ch_cn_labels.size():
				_ch_cn_labels[i].modulate = c
		else:
			b.modulate = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)
			if i < _ch_cn_labels.size():
				_ch_cn_labels[i].modulate = Color(0.72, 0.72, 0.75)


# ============================================================
#  绘制
# ============================================================
func _draw_grid(c : Control):
	var sz : Vector2 = c.size
	var gx : float = PIANO_WIDTH
	var gy : float = 0.0
	var gw : float = sz.x - gx
	var gh : float = sz.y - gy
	if gw <= 0.0 or gh <= 0.0: return

	c.draw_rect(Rect2(Vector2.ZERO, sz), COL_BG)

	var tpb : int = 4
	var bpb : int = 4
	if _song:
		tpb = maxi(1, int(_song.ticks_per_beat))
		bpb = maxi(1, int(_song.beats_per_bar))

	var pitch_top : int = PITCH_MAX - int(_scroll_y / ROW_HEIGHT)
	var pitch_bot : int = PITCH_MAX - int((_scroll_y + gh) / ROW_HEIGHT) - 1
	pitch_top = mini(pitch_top, PITCH_MAX)
	pitch_bot = maxi(pitch_bot, PITCH_MIN)

	for p in range(pitch_bot, pitch_top + 1):
		var y : float = gy + float(PITCH_MAX - p) * ROW_HEIGHT - _scroll_y
		var col : Color = COL_ROW_BLACK if _is_black(p) else COL_ROW_WHITE
		c.draw_rect(Rect2(gx, y, gw, ROW_HEIGHT), col)

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
			if _selected_channel != CH_ALL and ec != _selected_channel: continue
			var et : float = float(e.tick)
			var ed : float = float(e.dur)
			var en : float = float(e.note)
			var ev : float = float(e.vel)
			var ex : float = gx + et / float(tpb) * _px_per_beat - _scroll_x
			var ew : float = maxf(3.0, ed / float(tpb) * _px_per_beat)
			var ey : float = gy + float(PITCH_MAX - int(en)) * ROW_HEIGHT - _scroll_y
			if ex + ew < gx or ex > sz.x: continue
			if ey + ROW_HEIGHT < gy or ey > sz.y: continue
			var col : Color = _ch_colors[ec] if ec < _ch_colors.size() else Color.WHITE
			if i in _selected_indices:
				col = COL_NOTE_SEL
			c.draw_rect(Rect2(ex, ey + 1.0, ew, ROW_HEIGHT - 2.0), col)

			# 在块上显示力度（宽度足够时）
			if ew >= 12.0:
				var vel_txt := str(int(ev))
				var fnt2 := ThemeDB.fallback_font
				var tsize2 := fnt2.get_string_size(vel_txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FS_NOTE_VEL)
				var tx : float = ex + (ew - tsize2.x) * 0.5
				var ty : float = ey + ROW_HEIGHT - 2.0
				var txt_col : Color = Color(0.10, 0.10, 0.10, 0.85)
				if col == COL_NOTE_SEL:
					txt_col = Color(0.25, 0.15, 0.0, 0.9)
				c.draw_string(fnt2, Vector2(tx, ty), vel_txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FS_NOTE_VEL, txt_col)

	# 钢琴键
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
			var fnt := ThemeDB.fallback_font
			c.draw_string(fnt, Vector2(1.0, y + ROW_HEIGHT - 1.0),
						  "C%d" % oct, HORIZONTAL_ALIGNMENT_LEFT, -1, 6,
						  Color(0.35, 0.35, 0.40))
	c.draw_line(Vector2(PIANO_WIDTH, gy), Vector2(PIANO_WIDTH, sz.y),
				COL_GRID_BAR, 1.0)

	# Track 头尾标记
	if _song:
		var total_tick : float = float(_song.total_ticks)
		var start_x : float = gx - _scroll_x
		if start_x >= gx - 1.0 and start_x <= sz.x + 1.0:
			c.draw_line(Vector2(start_x, gy), Vector2(start_x, sz.y),
				COL_TRACK_START, 1.0)
			c.draw_colored_polygon(PackedVector2Array([
				Vector2(start_x - 3.0, gy),
				Vector2(start_x + 3.0, gy),
				Vector2(start_x, gy + 4.0),
			]), COL_TRACK_START)
		var end_x : float = gx + total_tick / float(tpb) * _px_per_beat - _scroll_x
		if end_x >= gx - 1.0 and end_x <= sz.x + 1.0:
			c.draw_line(Vector2(end_x, gy), Vector2(end_x, sz.y),
				COL_TRACK_END, 1.0)
			c.draw_colored_polygon(PackedVector2Array([
				Vector2(end_x - 3.0, gy),
				Vector2(end_x + 3.0, gy),
				Vector2(end_x, gy + 4.0),
			]), COL_TRACK_END)

	# 框选矩形
	if _box_selecting:
		var br := Rect2(_box_start, _box_end - _box_start).abs()
		c.draw_rect(br, Color(COL_BOX_SEL.r, COL_BOX_SEL.g, COL_BOX_SEL.b, 0.15), true)
		c.draw_rect(br, Color(COL_BOX_SEL.r, COL_BOX_SEL.g, COL_BOX_SEL.b, 0.90), false, 1.0)

	# 播放头
	if _playhead_tick >= 0.0:
		var px : float = gx + _playhead_tick / float(tpb) * _px_per_beat - _scroll_x
		if px >= gx and px <= sz.x:
			c.draw_line(Vector2(px, gy), Vector2(px, sz.y), COL_PLAYHEAD, 1.5)


# ============================================================
#  网格输入
# ============================================================
func _on_grid_input(event : InputEvent, c : Control):
	if _song == null: return
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var gx : float = PIANO_WIDTH

	if event is InputEventMouseButton:
		var mb : InputEventMouseButton = event
		var mp : Vector2 = mb.position

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if Input.is_key_pressed(KEY_CTRL) or mp.x < gx:
				_scroll_x = maxf(0.0, _scroll_x - 40.0)
			else:
				_scroll_y = maxf(0.0, _scroll_y - 40.0)
			c.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if Input.is_key_pressed(KEY_CTRL) or mp.x < gx:
				_scroll_x += 40.0
				_clamp_scroll()
			else:
				_scroll_y += 40.0
			c.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
			return

		if mp.x < gx: return

		var world_x : float = mp.x - gx + _scroll_x
		var world_y : float = mp.y + _scroll_y
		var click_tick : float = world_x / _px_per_beat * float(tpb)
		var row_idx : int = int(floor(world_y / ROW_HEIGHT))
		var click_pitch : int = clampi(PITCH_MAX - row_idx, PITCH_MIN, PITCH_MAX)

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# ① 右边缘 resize
				var edge_idx : int = _find_note_right_edge(mp.x, click_pitch)
				if edge_idx >= 0:
					_resizing_idx = edge_idx
					_resizing_start_dur = float(_song.events[edge_idx].dur)
					_drag_start_mouse = mp
					_selected_indices.clear()
					_selected_indices.append(edge_idx)
					_push_undo()
					_update_note_inspector()
					c.queue_redraw()
					return

				# ② 点到音符 → 选中 / 拖动
				var hit : int = _find_note_at(click_tick, float(click_pitch))
				if hit >= 0:
					if Input.is_key_pressed(KEY_SHIFT):
						if hit in _selected_indices:
							_selected_indices.erase(hit)
						else:
							_selected_indices.append(hit)
					else:
						if not (hit in _selected_indices):
							_selected_indices.clear()
							_selected_indices.append(hit)
					_start_drag(mp)
					_update_note_inspector()
					c.queue_redraw()
					return

				# ③ 空白处 → 开始框选
				_box_selecting = true
				_box_start = mp
				_box_end = mp
				_box_additive = Input.is_key_pressed(KEY_SHIFT)
				c.queue_redraw()
			else:
				if _box_selecting:
					_finish_box_select(c)
				_resizing_idx = -1
				_dragging = false
				_drag_data.clear()

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _box_selecting:
				_box_selecting = false
				c.queue_redraw()
				return
			var hit : int = _find_note_at(click_tick, float(click_pitch))
			if hit >= 0:
				_push_undo()
				_song.events.remove_at(hit)
				_selected_indices.clear()
				_update_note_inspector()
				c.queue_redraw()
			else:
				if _selected_indices.size() > 0:
					_selected_indices.clear()
					_update_note_inspector()
					c.queue_redraw()

		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			var hit : int = _find_note_at(click_tick, float(click_pitch))
			if hit >= 0:
				_push_undo()
				_song.events.remove_at(hit)
				_selected_indices.clear()
				_update_note_inspector()
				c.queue_redraw()

	elif event is InputEventMouseMotion:
		var mm : InputEventMouseMotion = event
		if _box_selecting:
			_box_end = mm.position
			c.queue_redraw()
		elif _resizing_idx >= 0:
			_perform_resize(mm.position)
			c.queue_redraw()
		elif _dragging and _drag_data.size() > 0:
			_perform_drag(mm.position)
			c.queue_redraw()


# ============================================================
#  框选
# ============================================================
func _finish_box_select(c : Control):
	_box_selecting = false
	var rect := Rect2(_box_start, _box_end - _box_start).abs()
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var gx : float = PIANO_WIDTH

	# 框太小 → 当作单击
	if rect.size.x < 3.0 and rect.size.y < 3.0:
		# 有选中 → 取消选择（不添加音符）
		if _selected_indices.size() > 0 and not _box_additive:
			_selected_indices.clear()
			_update_note_inspector()
			c.queue_redraw()
			return
		# 无选中 → 添加音符
		if _selected_channel != CH_ALL:
			var world_x : float = _box_start.x - gx + _scroll_x
			var world_y : float = _box_start.y + _scroll_y
			var tick : int = int(world_x / _px_per_beat * float(tpb))
			var row_idx : int = int(floor(world_y / ROW_HEIGHT))
			var pitch : int = clampi(PITCH_MAX - row_idx, PITCH_MIN, PITCH_MAX)
			_push_undo()
			var ev : Dictionary = _make_event(maxi(0, tick), pitch, _selected_channel)
			_song.events.append(ev)
			_selected_indices.clear()
			_selected_indices.append(_song.events.size() - 1)
		_update_note_inspector()
		c.queue_redraw()
		return

	# 大框 → 选中框内音符
	var new_selection : Array[int] = []
	if _box_additive:
		new_selection = _selected_indices.duplicate()

	for i in range(_song.events.size()):
		var e : Dictionary = _song.events[i]
		var ec : int = int(e.ch)
		if _selected_channel != CH_ALL and ec != _selected_channel: continue
		var ex : float = gx + float(e.tick) / float(tpb) * _px_per_beat - _scroll_x
		var ew : float = maxf(3.0, float(e.dur) / float(tpb) * _px_per_beat)
		var ey : float = float(PITCH_MAX - int(e.note)) * ROW_HEIGHT - _scroll_y
		var note_rect := Rect2(ex, ey, ew, ROW_HEIGHT)
		if rect.intersects(note_rect):
			if not (i in new_selection):
				new_selection.append(i)

	_selected_indices = new_selection
	_update_note_inspector()
	c.queue_redraw()
	_status.text = "已选中 %d 个音符" % _selected_indices.size()


# ============================================================
#  选中操作
# ============================================================
func _nudge_selected_pitch(delta_pitch : int):
	if _song == null or _selected_indices.size() == 0: return
	_push_undo()
	for idx in _selected_indices:
		if idx < 0 or idx >= _song.events.size(): continue
		var e : Dictionary = _song.events[idx]
		e.note = float(clampi(int(e.note) + delta_pitch, PITCH_MIN, PITCH_MAX))
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()


func _nudge_selected_tick(delta_tick : int):
	if _song == null or _selected_indices.size() == 0: return
	_push_undo()
	for idx in _selected_indices:
		if idx < 0 or idx >= _song.events.size(): continue
		var e : Dictionary = _song.events[idx]
		e.tick = maxf(0.0, float(e.tick) + float(delta_tick))
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()


func _select_all_in_channel():
	if _song == null: return
	_selected_indices.clear()
	for i in range(_song.events.size()):
		var e : Dictionary = _song.events[i]
		if _selected_channel != CH_ALL and int(e.ch) != _selected_channel: continue
		_selected_indices.append(i)
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()
	_status.text = "已选中 %d 个音符" % _selected_indices.size()


# ============================================================
#  Resize
# ============================================================
func _find_note_right_edge(mouse_x : float, click_pitch : int) -> int:
	if _song == null: return -1
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var gx : float = PIANO_WIDTH
	for i in range(_song.events.size() - 1, -1, -1):
		var e : Dictionary = _song.events[i]
		var ec : int = int(e.ch)
		if _selected_channel != CH_ALL and ec != _selected_channel: continue
		if int(e.note) != click_pitch: continue
		var end_tick : float = float(e.tick) + float(e.dur)
		var end_x : float = gx + end_tick / float(tpb) * _px_per_beat - _scroll_x
		if abs(mouse_x - end_x) <= RESIZE_HANDLE_PX:
			return i
	return -1


func _perform_resize(mouse_pos : Vector2):
	if _song == null or _resizing_idx < 0: return
	if _resizing_idx >= _song.events.size(): return
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var dx : float = mouse_pos.x - _drag_start_mouse.x
	var dtick : float = dx / _px_per_beat * float(tpb)
	var new_dur : float = roundf(maxf(1.0, _resizing_start_dur + dtick))
	var e : Dictionary = _song.events[_resizing_idx]
	e.dur = new_dur
	_update_note_inspector()


# ============================================================
#  事件辅助
# ============================================================
func _make_event(tick : int, pitch : int, ch : int) -> Dictionary:
	var tpb : int = 4
	if _song: tpb = maxi(1, int(_song.ticks_per_beat))
	return {
		"ch": float(ch),
		"tick": float(maxi(0, tick)),
		"note": float(clampi(pitch, PITCH_MIN, PITCH_MAX)),
		"vel": 100.0,
		"dur": float(maxi(1, tpb >> 1)),
	}


func _find_note_at(tick : float, pitch : float) -> int:
	if _song == null: return -1
	for i in range(_song.events.size() - 1, -1, -1):
		var e : Dictionary = _song.events[i]
		if _selected_channel != CH_ALL and int(e.ch) != _selected_channel: continue
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
	if _drag_data.size() > 0:
		_push_undo()


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
#  音符属性
# ============================================================
func _update_note_inspector():
	if _song == null or _selected_indices.size() == 0:
		_note_box.visible = false
		_note_info.text = "（未选中）"
		return
	if _selected_indices.size() > 1:
		_note_box.visible = false
		_note_info.text = "已选中 %d 个" % _selected_indices.size()
		return
	var idx : int = _selected_indices[0]
	if idx < 0 or idx >= _song.events.size():
		_note_box.visible = false
		_note_info.text = "（索引失效）"
		return
	var e : Dictionary = _song.events[idx]
	_note_box.visible = true
	_note_info.text = "ch%d t%d" % [int(e.ch), int(e.tick)]
	_note_tick.set_value_no_signal(float(e.tick))
	_note_pitch.set_value_no_signal(float(e.note))
	_note_vel.set_value_no_signal(float(e.vel))
	_note_dur.set_value_no_signal(float(e.dur))


func _on_note_prop_changed():
	if _song == null or _selected_indices.size() == 0: return
	var idx : int = _selected_indices[0]
	if idx < 0 or idx >= _song.events.size(): return
	var e : Dictionary = _song.events[idx]
	var nt : float = maxf(0.0, _note_tick.value)
	var np : float = clampf(_note_pitch.value, float(PITCH_MIN), float(PITCH_MAX))
	var nv : float = clampf(_note_vel.value, 0.0, 127.0)
	var nd : float = maxf(1.0, _note_dur.value)
	if is_equal_approx(e.tick, nt) and is_equal_approx(e.note, np) \
		and is_equal_approx(e.vel, nv) and is_equal_approx(e.dur, nd):
		return
	_push_undo()
	e.tick = nt
	e.note = np
	e.vel = nv
	e.dur = nd
	if _grid_canvas: _grid_canvas.queue_redraw()


func _delete_selected():
	if _song == null or _selected_indices.size() == 0: return
	_push_undo()
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

	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		if not ke.ctrl_pressed: return
		match ke.keycode:
			KEY_Z:
				if ke.shift_pressed: _redo()
				else: _undo()
				get_viewport().set_input_as_handled(); return
			KEY_Y:
				_redo()
				get_viewport().set_input_as_handled(); return
			KEY_S:
				_save_file()
				get_viewport().set_input_as_handled(); return
			KEY_A:
				_select_all_in_channel()
				get_viewport().set_input_as_handled(); return
		return

	if ke.ctrl_pressed:
		match ke.keycode:
			KEY_Z:
				if ke.shift_pressed: _redo()
				else: _undo()
				get_viewport().set_input_as_handled(); return
			KEY_Y:
				_redo()
				get_viewport().set_input_as_handled(); return
			KEY_S:
				_save_file()
				get_viewport().set_input_as_handled(); return
			KEY_O:
				_open_dialog()
				get_viewport().set_input_as_handled(); return
			KEY_N:
				_new_song()
				get_viewport().set_input_as_handled(); return
			KEY_A:
				_select_all_in_channel()
				get_viewport().set_input_as_handled(); return

	match ke.keycode:
		KEY_SPACE:
			if _player and _player.is_playing():
				_playhead_tick = float(_player.get_current_tick())
				_player.stop()
				if _grid_canvas: _grid_canvas.queue_redraw()
			else:
				_play()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			_delete_selected()
			get_viewport().set_input_as_handled()
		KEY_UP:
			if _selected_indices.size() > 0:
				_nudge_selected_pitch(1)
				get_viewport().set_input_as_handled()
		KEY_DOWN:
			if _selected_indices.size() > 0:
				_nudge_selected_pitch(-1)
				get_viewport().set_input_as_handled()
		KEY_LEFT:
			if _selected_indices.size() > 0:
				if ke.shift_pressed:
					_nudge_selected_tick(-maxi(1, int(_song.ticks_per_beat)))
				else:
					_nudge_selected_tick(-1)
				get_viewport().set_input_as_handled()
		KEY_RIGHT:
			if _selected_indices.size() > 0:
				if ke.shift_pressed:
					_nudge_selected_tick(maxi(1, int(_song.ticks_per_beat)))
				else:
					_nudge_selected_tick(1)
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_request_quit()
