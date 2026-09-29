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
#    中键拖动                平移视图（视口移动）
#    右键空白                取消所有选中
#
#  【键盘】
#    Delete                  删除所有选中音符
#    ↑ / ↓                   选中音符整体移调 ±1 半音
#    Shift + ↑ / ↓           选中音符整体移调 ±1 八度（12 半音）
#    ← / →                   选中音符整体左右移动 ±1 tick
#    Shift + ← / →           整体左右移动 ±1 拍
#    Ctrl+A                  全选当前通道所有音符（All 通道时全选）
#    Ctrl+X / Ctrl+C         剪切 / 复制选中音符（同通道内）
#    Ctrl+V                  粘贴到鼠标位置（同通道内，切通道清空）
#
#  【通道】
#    单击通道按钮            切换到该通道（清空选中）
#    All 按钮                显示所有通道（只读，空白处不能新建）
#    M 按钮                  静音该通道
#
#  【视图】
#    滚轮                    垂直滚动
#    Shift + 滚轮            水平滚动
#    Ctrl + 滚轮             以鼠标为中心整体缩放（同步宽 + 行高）
#    滚轮（在钢琴键区）      垂直滚动
#    通道面板"宽度"滑杆      横向缩放（10~120 px / 拍）
#    通道面板"行高"滑杆      纵向行高（3.0~14.0 px）
#
#  【歌曲元数据】（通道面板底部）
#    修改标题输入框          重命名歌曲（同步到底部只读 Label）
#    修改循环开关            是否循环（勾选时 loop_start=0, loop_end=total_ticks）
#
#  【撤销 / 重做】
#    Ctrl+Z                  撤销（最多 15 步）
#    Ctrl+Shift+Z / Ctrl+Y   重做
# ============================================================

const MUSIC_DIR : String = "res://content/music/"

const PITCH_MIN : int = 24
const PITCH_MAX : int = 96
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
const FS_LOOP   : int = 4

const BTN_H : int = 13
const SPIN_H : int = 13
const SPIN_W : int = 20
const SPIN_W_LONG : int = 24
const SPIN_W_NOTE : int = 20
const SPIN_W_NOTE_S : int = 18
const CH_PANEL_W : int = 90
const CH_EN_W : int = 40
const CN_LABEL_W : int = 22
const MUTE_W : int = 12
const MUTE_GAP : int = 12
const VSEP_W : int = 1
const MAX_UNDO : int = 15

# 底部信息栏固定高度（避免弹跳）
const INFO_PANEL_H : int = 16
# 循环按钮尺寸（6×6）
const LOOP_BTN : int = 6
# 滑杆控件高度
const SLIDER_H : int = 5
# 元数据行 Label 宽度
const META_LABEL_W : int = 28

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

# Loop 按钮颜色（蓝灰 / 暗灰）
const COL_LOOP_ON  : Color = Color(0.42, 0.56, 0.85)
const COL_LOOP_OFF : Color = Color(0.20, 0.20, 0.24)

const HINT_TEXT : String = "左键空白=添加/框选 · 左键音符=选中/拖动 · 拖右边缘=改时长 · 中键拖动=平移 · 右键音符=删除 · 右键空白=取消 · Delete=删除 · Ctrl+X/C/V=剪切/复制/粘贴 · ↑↓=移调 · Shift+↑↓=八度 · ←→=移动 · Shift+←→=整拍 · Ctrl+A=全选 · 滚轮=滚动 · Ctrl+滚轮=缩放 · 空格=播放 · Esc=退出"

# 行高 / 横向缩放
var _row_height : float = 7.0
var _px_per_beat : float = 60.0

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

# 中键平移
var _panning : bool = false
var _pan_start_mouse : Vector2 = Vector2.ZERO
var _pan_start_scroll : Vector2 = Vector2.ZERO

# 剪贴板（单通道内）
var _clipboard : Dictionary = {}

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
var _title_label : Label = null
var _title_edit : LineEdit = null
var _loop_cb : Button = null
var _bpm_spin : SpinBox = null
var _bpb_spin : SpinBox = null
var _tpb_spin : SpinBox = null
var _total_spin : SpinBox = null
var _zoom_slider : HSlider = null
var _vzoom_slider : HSlider = null
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
	t.set_stylebox("read_only", "LineEdit", le_empty)   # 屏蔽时无背景框

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
	slider_sb.content_margin_top = 2.5
	slider_sb.content_margin_bottom = 2.5
	t.set_stylebox("slider", "HSlider", slider_sb)

	var grab_sb := StyleBoxFlat.new()
	grab_sb.bg_color = Color(0.55, 0.55, 0.60, 1.0)   # ★ 灰
	grab_sb.content_margin_top = 2.5
	grab_sb.content_margin_bottom = 2.5
	t.set_stylebox("grabber_area", "HSlider", grab_sb)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab_sb)

	# 细长把手：宽 2 高 5，与滑杆控件高度匹配
	var img := Image.create(2, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.78, 0.78, 0.82, 1.0))
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
	all_cn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	all_cn.custom_minimum_size = Vector2(CN_LABEL_W, 0)
	all_row.add_child(all_cn)

	# All 行右侧的占位（无 M 按钮，但保持与通道行右边界一致）
	var all_gap := Control.new()
	all_gap.custom_minimum_size = Vector2(MUTE_W + 1, 0)
	all_row.add_child(all_gap)

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
		cn_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cn_lbl.custom_minimum_size = Vector2(CN_LABEL_W, 0)
		cn_lbl.modulate = Color(0.75, 0.75, 0.78)
		row.add_child(cn_lbl)

		var m := Button.new()
		m.text = "M"
		m.toggle_mode = true
		m.tooltip_text = "静音"
		m.add_theme_font_size_override("font_size", FS_SMALL)
		m.custom_minimum_size = Vector2(MUTE_W, BTN_H)
		m.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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

	# 缩放区域：占据剩余空间，垂直居中
	var zoom_wrap := VBoxContainer.new()
	zoom_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zoom_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	zoom_wrap.add_theme_constant_override("separation", 3)
	parent.add_child(zoom_wrap)

	_make_bottom_zoom(zoom_wrap)
	_make_song_meta_panel(parent)

	_refresh_channel_buttons()


## 缩放控件：宽度（上）+ 行高（下）
## 标签左边与元数据行对齐；滑杆右侧与 M 按钮左侧对齐
func _make_bottom_zoom(parent : Node):
	# ===== 宽度 =====
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 2)
	parent.add_child(r1)

	var l1 := Label.new()
	l1.text = "宽度"
	l1.add_theme_font_size_override("font_size", FS_SMALL)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l1.custom_minimum_size = Vector2(META_LABEL_W, 0)   # ★ 与元数据标签同宽
	l1.modulate = Color(0.65, 0.65, 0.72)
	r1.add_child(l1)

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 10.0
	_zoom_slider.max_value = 120.0
	_zoom_slider.step = 0.2
	_zoom_slider.value = _px_per_beat
	_zoom_slider.tooltip_text = "宽度 / 横向缩放（10~120 px / 拍）"
	_zoom_slider.custom_minimum_size = Vector2(0, SLIDER_H)
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom_slider.value_changed.connect(func(v : float):
		_px_per_beat = v
		_clamp_scroll()
		if _grid_canvas: _grid_canvas.queue_redraw()
		if _seek_bar: _seek_bar.queue_redraw()
	)
	r1.add_child(_zoom_slider)

	var pad1 := Control.new()
	pad1.custom_minimum_size = Vector2(MUTE_W + 1, 0)
	r1.add_child(pad1)

	# ===== 行高 =====
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 2)
	parent.add_child(r2)

	var l2 := Label.new()
	l2.text = "行高"
	l2.add_theme_font_size_override("font_size", FS_SMALL)
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l2.custom_minimum_size = Vector2(META_LABEL_W, 0)   # ★ 与元数据标签同宽
	l2.modulate = Color(0.65, 0.65, 0.72)
	r2.add_child(l2)

	_vzoom_slider = HSlider.new()
	_vzoom_slider.min_value = 3.0
	_vzoom_slider.max_value = 14.0
	_vzoom_slider.step = 0.2
	_vzoom_slider.value = _row_height
	_vzoom_slider.tooltip_text = "行高（3~14 px）"
	_vzoom_slider.custom_minimum_size = Vector2(0, SLIDER_H)
	_vzoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vzoom_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vzoom_slider.value_changed.connect(func(v : float):
		_row_height = v
		if _grid_canvas: _grid_canvas.queue_redraw()
	)
	r2.add_child(_vzoom_slider)

	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(MUTE_W + 1, 0)
	r2.add_child(pad2)


## 歌曲元数据：修改标题 + 修改循环（无横线分隔）
func _make_song_meta_panel(parent : Node):
	# ---- 修改标题 ----
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 2)
	parent.add_child(r1)

	var l1 := Label.new()
	l1.text = "修改标题"
	l1.add_theme_font_size_override("font_size", FS_SMALL)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l1.custom_minimum_size = Vector2(META_LABEL_W, 0)
	l1.modulate = Color(0.65, 0.65, 0.72)
	r1.add_child(l1)

	_title_edit = LineEdit.new()
	_title_edit.add_theme_font_size_override("font_size", FS_BUTTON)
	_title_edit.custom_minimum_size = Vector2(0, BTN_H - 1)
	_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_edit.placeholder_text = "（无标题）"
	_title_edit.text_changed.connect(func(t : String):
		if _song and _song.title != t:
			_song.title = t
			_dirty = true
		if _title_label:
			_title_label.text = t if t != "" else "（无标题）"
	)
	# ★ 回车 = 完成输入，释放焦点
	_title_edit.text_submitted.connect(func(_t : String):
		if is_instance_valid(_title_edit):
			_title_edit.release_focus()
	)
	r1.add_child(_title_edit)

	# ---- 修改循环 ----
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 2)
	parent.add_child(r2)

	var l2 := Label.new()
	l2.text = "修改循环"
	l2.add_theme_font_size_override("font_size", FS_SMALL)
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l2.custom_minimum_size = Vector2(META_LABEL_W, 0)
	l2.modulate = Color(0.65, 0.65, 0.72)
	r2.add_child(l2)

	_loop_cb = Button.new()
	_loop_cb.toggle_mode = true
	_loop_cb.text = ""
	_loop_cb.add_theme_font_size_override("font_size", FS_LOOP)
	_loop_cb.custom_minimum_size = Vector2(LOOP_BTN, LOOP_BTN)
	_loop_cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_loop_cb.focus_mode = Control.FOCUS_NONE
	_loop_cb.tooltip_text = "循环播放"
	_loop_cb.toggled.connect(func(v : bool):
		if _song == null: return
		if v:
			_song.loop_start = 0
			_song.loop_end = _song.total_ticks
		else:
			_song.loop_start = -1
			_song.loop_end = 0
		_dirty = true
		_apply_loop_visual(v)
	)
	_apply_loop_visual(true)
	r2.add_child(_loop_cb)


## 循环开关的视觉状态（蓝灰 / 暗灰，无绿色）
func _apply_loop_visual(on : bool):
	if _loop_cb == null: return
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.corner_radius_top_left = 1
	sb.corner_radius_top_right = 1
	sb.corner_radius_bottom_left = 1
	sb.corner_radius_bottom_right = 1
	if on:
		sb.bg_color = COL_LOOP_ON
		_loop_cb.text = "✓"
		_loop_cb.modulate = Color(1, 1, 1)
	else:
		sb.bg_color = COL_LOOP_OFF
		_loop_cb.text = ""
		_loop_cb.modulate = Color(0.55, 0.55, 0.60)
	_loop_cb.add_theme_stylebox_override("normal", sb)
	_loop_cb.add_theme_stylebox_override("hover", sb)
	_loop_cb.add_theme_stylebox_override("pressed", sb)
	_loop_cb.add_theme_stylebox_override("focus", sb)
	_loop_cb.add_theme_stylebox_override("disabled", sb)


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
	panel.custom_minimum_size = Vector2(0, INFO_PANEL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13)
	sb.content_margin_left = 6
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	# 只读标题 Label
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", FS_BUTTON)
	_title_label.text = "（无标题）"
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.modulate = Color(0.92, 0.92, 0.95)
	row.add_child(_title_label)

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
	_note_info.custom_minimum_size = Vector2(96, 0)   # 固定宽度防跳动
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
			if is_instance_valid(le):
				le.release_focus()
		)
		# ★ 方案 3：任何来源的 focus 进入，只要鼠标不在 LineEdit 上就释放
		le.focus_entered.connect(func():
			if is_instance_valid(le):
				var mp := get_viewport().get_mouse_position()
				if not le.get_global_rect().has_point(mp):
					le.call_deferred("release_focus")
		)

	var btns : Array[Node] = sp.find_children("*", "Button", true, false)
	for b in btns:
		_compact_spin_arrow_button(b as Button, sp)


func _compact_spin_arrow_button(btn : Button, sp : SpinBox):
	btn.custom_minimum_size = Vector2(3, 2)
	btn.icon_max_width = 2
	btn.icon_max_height = 2
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

	# ★ 方案 1：鼠标按下瞬间（早于 SpinBox 内部逻辑）就释放焦点
	btn.gui_input.connect(func(e : InputEvent):
		if e is InputEventMouseButton and e.pressed \
			and e.button_index == MOUSE_BUTTON_LEFT:
			if is_instance_valid(sp):
				var le := sp.get_line_edit()
				if is_instance_valid(le) and le.has_focus():
					le.release_focus()
	)

	# ★ 方案 2：释放鼠标后兜底（deferred 保证 Godot 内部处理完再执行）
	btn.pressed.connect(func():
		if is_instance_valid(sp):
			var le := sp.get_line_edit()
			if is_instance_valid(le):
				le.call_deferred("release_focus")
	)


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

	_title_label.text = _song.title if _song.title != "" else "（无标题）"
	if _title_edit: _title_edit.text = _song.title
	if _loop_cb:
		_loop_cb.set_pressed_no_signal(_song.loop_end > 0)
		_apply_loop_visual(_song.loop_end > 0)
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
	# 遮罩层
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	# 面板（居中，260 × 130）
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -130
	panel.offset_right = 130
	panel.offset_top = -65
	panel.offset_bottom = 65

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.06)      # 黑色背景
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.28, 0.28, 0.34)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# 标题（居中）
	var title := Label.new()
	title.text = "未保存的修改"
	title.add_theme_font_size_override("font_size", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 正文（居中）
	var msg := Label.new()
	msg.text = "当前歌曲有未保存的修改，是否保存？"
	msg.add_theme_font_size_override("font_size", 7)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg)

	# 弹性间隔，把按钮推到下方
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# 按钮行（居中）
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vbox.add_child(btns)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.add_theme_font_size_override("font_size", 8)
	save_btn.custom_minimum_size = Vector2(72, 22)
	btns.add_child(save_btn)

	var nosave_btn := Button.new()
	nosave_btn.text = "不保存"
	nosave_btn.add_theme_font_size_override("font_size", 8)
	nosave_btn.custom_minimum_size = Vector2(72, 22)
	btns.add_child(nosave_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 8)
	cancel_btn.custom_minimum_size = Vector2(72, 22)
	btns.add_child(cancel_btn)

	# 按钮回调
	save_btn.pressed.connect(func():
		layer.queue_free()
		_save_file()
		if not _dirty:
			get_tree().quit()
	)
	nosave_btn.pressed.connect(func():
		layer.queue_free()
		get_tree().quit()
	)
	cancel_btn.pressed.connect(func():
		layer.queue_free()
	)


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

	_title_label.text = s.title if s.title != "" else "（无标题）"
	if _title_edit: _title_edit.text = s.title
	if _loop_cb:
		_loop_cb.set_pressed_no_signal(s.loop_end > 0)
		_apply_loop_visual(s.loop_end > 0)
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

	_title_label.text = "Untitled"
	if _title_edit: _title_edit.text = "Untitled"
	if _loop_cb:
		_loop_cb.set_pressed_no_signal(true)
		_apply_loop_visual(true)
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
	if _title_edit:
		_song.title = _title_edit.text
	_song.bpm = _bpm_spin.value
	_song.beats_per_bar = int(_bpb_spin.value)
	_song.ticks_per_beat = int(_tpb_spin.value)
	_song.total_ticks = int(_total_spin.value)
	if _loop_cb and _loop_cb.button_pressed:
		_song.loop_start = 0
		_song.loop_end = int(_total_spin.value)
	else:
		_song.loop_start = -1
		_song.loop_end = 0

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
		_title_label.text = _song.title if _song.title != "" else "（无标题）"
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
	if i != _selected_channel and not _clipboard.is_empty():
		_clipboard.clear()             # ★ 切换通道 → 清空剪贴板
		_status.text = "通道已切换，剪贴板已清空"
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

	var pitch_top : int = PITCH_MAX - int(_scroll_y / _row_height)
	var pitch_bot : int = PITCH_MAX - int((_scroll_y + gh) / _row_height) - 1
	pitch_top = mini(pitch_top, PITCH_MAX)
	pitch_bot = maxi(pitch_bot, PITCH_MIN)

	for p in range(pitch_bot, pitch_top + 1):
		var y : float = gy + float(PITCH_MAX - p) * _row_height - _scroll_y
		var col : Color = COL_ROW_BLACK if _is_black(p) else COL_ROW_WHITE
		c.draw_rect(Rect2(gx, y, gw, _row_height), col)

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
			var ey : float = gy + float(PITCH_MAX - int(en)) * _row_height - _scroll_y
			if ex + ew < gx or ex > sz.x: continue
			if ey + _row_height < gy or ey > sz.y: continue
			var col : Color = _ch_colors[ec] if ec < _ch_colors.size() else Color.WHITE
			if i in _selected_indices:
				col = COL_NOTE_SEL
			c.draw_rect(Rect2(ex, ey + 1.0, ew, _row_height - 2.0), col)

			# 力度数字
			if ew >= 12.0:
				var vel_txt := str(int(ev))
				var fnt2 := ThemeDB.fallback_font
				var tsize2 := fnt2.get_string_size(vel_txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FS_NOTE_VEL)
				var tx : float = ex + (ew - tsize2.x) * 0.5
				var ty : float = ey + _row_height - 2.0
				c.draw_string(fnt2, Vector2(tx, ty), vel_txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FS_NOTE_VEL,
					Color(0.98, 0.98, 0.98, 0.95))

	# 钢琴键
	c.draw_rect(Rect2(0, gy, PIANO_WIDTH, gh), Color(0.10, 0.10, 0.13))
	for p in range(pitch_bot, pitch_top + 1):
		var y : float = gy + float(PITCH_MAX - p) * _row_height - _scroll_y
		if y + _row_height < gy or y > sz.y: continue
		var key_col : Color = COL_PIANO_BLACK if _is_black(p) else COL_PIANO_WHITE
		var key_w : float = PIANO_WIDTH - 1.0
		c.draw_rect(Rect2(0, y, key_w, _row_height - 1.0), key_col)
		c.draw_line(Vector2(0, y), Vector2(key_w, y), COL_PIANO_LINE, 1.0)
		if p % 12 == 0:
			var oct : int = int(float(p) / 12.0) - 1
			var fnt := ThemeDB.fallback_font
			c.draw_string(fnt, Vector2(1.0, y + _row_height - 1.0),
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

		# Ctrl + 滚轮 = 以鼠标为中心整体缩放
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed \
			and Input.is_key_pressed(KEY_CTRL):
			_zoom_at_mouse(mp, 1.10, c)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed \
			and Input.is_key_pressed(KEY_CTRL):
			_zoom_at_mouse(mp, 1.0 / 1.10, c)
			return

		# 普通滚轮 = 垂直滚动；Shift + 滚轮 / 钢琴键区 = 水平滚动
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if Input.is_key_pressed(KEY_SHIFT) or mp.x < gx:
				_scroll_x = maxf(0.0, _scroll_x - 40.0)
			else:
				_scroll_y = maxf(0.0, _scroll_y - 40.0)
			c.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if Input.is_key_pressed(KEY_SHIFT) or mp.x < gx:
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
		var row_idx : int = int(floor(world_y / _row_height))
		var click_pitch : int = clampi(PITCH_MAX - row_idx, PITCH_MIN, PITCH_MAX)

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
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

		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				# 中键 → 平移
				_panning = true
				_pan_start_mouse = mp
				_pan_start_scroll = Vector2(_scroll_x, _scroll_y)
			else:
				_panning = false

	elif event is InputEventMouseMotion:
		var mm : InputEventMouseMotion = event
		if _panning:
			_perform_pan(mm.position)
			c.queue_redraw()
			if _seek_bar: _seek_bar.queue_redraw()
		elif _box_selecting:
			_box_end = mm.position
			c.queue_redraw()
		elif _resizing_idx >= 0:
			_perform_resize(mm.position)
			c.queue_redraw()
		elif _dragging and _drag_data.size() > 0:
			_perform_drag(mm.position)
			c.queue_redraw()


# ============================================================
#  平移 / 缩放
# ============================================================
## 中键平移：拖动视图
func _perform_pan(mouse_pos : Vector2):
	var dx : float = mouse_pos.x - _pan_start_mouse.x
	var dy : float = mouse_pos.y - _pan_start_mouse.y
	_scroll_x = maxf(0.0, _pan_start_scroll.x - dx)
	_scroll_y = maxf(0.0, _pan_start_scroll.y - dy)
	_clamp_scroll()


## 以鼠标位置为锚点整体缩放（同步调整 _px_per_beat 和 _row_height）
func _zoom_at_mouse(mp : Vector2, factor : float, c : Control):
	var gx : float = PIANO_WIDTH

	var zmin : float = 10.0
	var zmax : float = 120.0
	var vmin : float = 3.0
	var vmax : float = 14.0
	if _zoom_slider:
		zmin = _zoom_slider.min_value
		zmax = _zoom_slider.max_value
	if _vzoom_slider:
		vmin = _vzoom_slider.min_value
		vmax = _vzoom_slider.max_value

	var old_ppp : float = _px_per_beat
	var old_rh : float = _row_height
	var new_ppp : float = clampf(old_ppp * factor, zmin, zmax)
	var new_rh : float = clampf(old_rh * factor, vmin, vmax)

	if is_equal_approx(new_ppp, old_ppp) and is_equal_approx(new_rh, old_rh):
		return

	var ratio_x : float = new_ppp / old_ppp
	var ratio_y : float = new_rh / old_rh

	var rel_x : float = maxf(0.0, mp.x - gx)
	var rel_y : float = mp.y

	_scroll_x = (rel_x + _scroll_x) * ratio_x - rel_x
	_scroll_y = (rel_y + _scroll_y) * ratio_y - rel_y
	if _scroll_x < 0.0: _scroll_x = 0.0
	if _scroll_y < 0.0: _scroll_y = 0.0

	_px_per_beat = new_ppp
	_row_height = new_rh

	if _zoom_slider:
		_zoom_slider.set_value_no_signal(new_ppp)
	if _vzoom_slider:
		_vzoom_slider.set_value_no_signal(new_rh)

	_clamp_scroll()
	c.queue_redraw()
	if _seek_bar: _seek_bar.queue_redraw()


# ============================================================
#  框选
# ============================================================
func _finish_box_select(c : Control):
	_box_selecting = false
	var rect := Rect2(_box_start, _box_end - _box_start).abs()
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var gx : float = PIANO_WIDTH

	if rect.size.x < 3.0 and rect.size.y < 3.0:
		if _selected_indices.size() > 0 and not _box_additive:
			_selected_indices.clear()
			_update_note_inspector()
			c.queue_redraw()
			return
		if _selected_channel != CH_ALL:
			var world_x : float = _box_start.x - gx + _scroll_x
			var world_y : float = _box_start.y + _scroll_y
			var tick : int = int(world_x / _px_per_beat * float(tpb))
			var row_idx : int = int(floor(world_y / _row_height))
			var pitch : int = clampi(PITCH_MAX - row_idx, PITCH_MIN, PITCH_MAX)
			_push_undo()
			var ev : Dictionary = _make_event(maxi(0, tick), pitch, _selected_channel)
			_song.events.append(ev)
			_selected_indices.clear()
			_selected_indices.append(_song.events.size() - 1)
		_update_note_inspector()
		c.queue_redraw()
		return

	var new_selection : Array[int] = []
	if _box_additive:
		new_selection = _selected_indices.duplicate()

	for i in range(_song.events.size()):
		var e : Dictionary = _song.events[i]
		var ec : int = int(e.ch)
		if _selected_channel != CH_ALL and ec != _selected_channel: continue
		var ex : float = gx + float(e.tick) / float(tpb) * _px_per_beat - _scroll_x
		var ew : float = maxf(3.0, float(e.dur) / float(tpb) * _px_per_beat)
		var ey : float = float(PITCH_MAX - int(e.note)) * _row_height - _scroll_y
		var note_rect := Rect2(ex, ey, ew, _row_height)
		if rect.intersects(note_rect):
			if not (i in new_selection):
				new_selection.append(i)

	_selected_indices = new_selection
	_update_note_inspector()
	c.queue_redraw()
	_status.text = "已选中 %d 个音符" % _selected_indices.size()


# ============================================================
#  剪切 / 复制 / 粘贴
# ============================================================
func _copy_selected():
	if _song == null or _selected_indices.size() == 0:
		_status.text = "没有选中的音符"
		return
	if _selected_channel == CH_ALL:
		_status.text = "请先选择具体通道（All 模式下不可复制）"
		return
	var evts : Array = []
	var base_tick : float = INF
	var base_note : float = INF
	for idx in _selected_indices:
		if idx < 0 or idx >= _song.events.size(): continue
		var e : Dictionary = _song.events[idx]
		if int(e.ch) != _selected_channel: continue
		evts.append(e.duplicate())
		base_tick = minf(base_tick, float(e.tick))
		base_note = minf(base_note, float(e.note))
	if evts.is_empty():
		_status.text = "没有可复制的音符"
		return
	_clipboard = {
		"ch": _selected_channel,
		"events": evts,
		"base_tick": base_tick,
		"base_note": base_note,
	}
	_status.text = "已复制 %d 个音符（%s）" % [evts.size(), _ch_en_names[_selected_channel]]


func _cut_selected():
	if _song == null or _selected_indices.size() == 0:
		_status.text = "没有选中的音符"
		return
	if _selected_channel == CH_ALL:
		_status.text = "请先选择具体通道（All 模式下不可剪切）"
		return
	_copy_selected()
	if _clipboard.is_empty(): return
	var n : int = (_clipboard["events"] as Array).size()
	_delete_selected()
	_status.text = "已剪切 %d 个音符（%s）" % [n, _ch_en_names[_selected_channel]]


func _paste_at_mouse():
	if _song == null: return
	if _clipboard.is_empty():
		_status.text = "剪贴板为空"
		return
	if _selected_channel == CH_ALL:
		_status.text = "请先选择具体通道（All 模式下不可粘贴）"
		return
	# 通道一致性检查（切换通道时已清空，这里是双保险）
	if int(_clipboard.get("ch", -999)) != _selected_channel:
		_clipboard.clear()
		_status.text = "通道不匹配，剪贴板已清空"
		return
	if _grid_canvas == null: return

	# 鼠标位置 → tick / pitch
	var mp : Vector2 = _grid_canvas.get_local_mouse_position()
	var gx : float = PIANO_WIDTH
	if mp.x < gx:
		_status.text = "鼠标不在 tracker 区"
		return
	var tpb : int = maxi(1, int(_song.ticks_per_beat))
	var world_x : float = mp.x - gx + _scroll_x
	var world_y : float = mp.y + _scroll_y
	var mouse_tick : int = maxi(0, int(round(world_x / _px_per_beat * float(tpb))))
	var row_idx : int = int(floor(world_y / _row_height))
	var mouse_pitch : int = clampi(PITCH_MAX - row_idx, PITCH_MIN, PITCH_MAX)

	var base_tick : float = float(_clipboard.get("base_tick", 0.0))
	var base_note : float = float(_clipboard.get("base_note", 60.0))
	var evts : Array = _clipboard.get("events", [])

	_push_undo()
	var added : Array[int] = []
	for src in evts:
		var e : Dictionary = src
		var new_tick : float = maxf(0.0, float(mouse_tick) + (float(e.tick) - base_tick))
		var new_note : int = clampi(mouse_pitch + (int(e.note) - int(base_note)),
			PITCH_MIN, PITCH_MAX)
		var new_ev : Dictionary = {
			"ch": float(_selected_channel),
			"tick": new_tick,
			"note": float(new_note),
			"vel": float(e.vel),
			"dur": float(e.dur),
		}
		_song.events.append(new_ev)
		added.append(_song.events.size() - 1)

	_selected_indices = added
	_update_note_inspector()
	if _grid_canvas: _grid_canvas.queue_redraw()
	_status.text = "已粘贴 %d 个音符" % added.size()


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
	var dpitch : int = -int(round(dy / _row_height))
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
		_note_info.text = "（未选中）"
		_set_note_spins_enabled(false)
		return
	if _selected_indices.size() > 1:
		_note_info.text = "已选中 %d 个" % _selected_indices.size()
		_set_note_spins_enabled(false)
		return
	var idx : int = _selected_indices[0]
	if idx < 0 or idx >= _song.events.size():
		_note_info.text = "（索引失效）"
		_set_note_spins_enabled(false)
		return
	var e : Dictionary = _song.events[idx]
	_note_info.text = "ch%d t%d" % [int(e.ch), int(e.tick)]
	_set_note_spins_enabled(true)
	_note_tick.set_value_no_signal(float(e.tick))
	_note_pitch.set_value_no_signal(float(e.note))
	_note_vel.set_value_no_signal(float(e.vel))
	_note_dur.set_value_no_signal(float(e.dur))


## 统一控制 4 个 SpinBox 的可编辑 + 视觉
func _set_note_spins_enabled(on : bool):
	var spins : Array[SpinBox] = [_note_tick, _note_pitch, _note_vel, _note_dur]
	for sp in spins:
		if sp == null: continue
		sp.editable = on
		var le := sp.get_line_edit()
		if le:
			le.editable = on
		var btns : Array[Node] = sp.find_children("*", "Button", true, false)
		for b in btns:
			if b is Button:
				(b as Button).disabled = not on
		sp.modulate = Color(1, 1, 1) if on else Color(0.55, 0.55, 0.60)


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
	# ★ 鼠标左键按下：如果不在输入框上，释放焦点
	if event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT:
		var fe := get_viewport().gui_get_focus_owner()
		if fe is LineEdit:
			var mp := get_viewport().get_mouse_position()
			if not fe.get_global_rect().has_point(mp):
				fe.release_focus()

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
			KEY_X:
				_cut_selected()
				get_viewport().set_input_as_handled(); return
			KEY_C:
				_copy_selected()
				get_viewport().set_input_as_handled(); return
			KEY_V:
				_paste_at_mouse()
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
				if ke.shift_pressed:
					_nudge_selected_pitch(12)
				else:
					_nudge_selected_pitch(1)
				get_viewport().set_input_as_handled()
		KEY_DOWN:
			if _selected_indices.size() > 0:
				if ke.shift_pressed:
					_nudge_selected_pitch(-12)
				else:
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
