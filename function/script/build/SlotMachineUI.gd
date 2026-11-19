extends Control
const BuildUI = preload("res://function/script/build/BuildUI.gd")

## ============================================================
##  SlotMachineUI — v6.7 转运军团风格老虎机转轮
## ============================================================
##  视觉：一个带边框的「转轮窗口」，窗口内 5 格符号条连续上下滚动，
##  上下两端渐隐遮罩，中间固定一条金色中奖线（▶ ◀ 标记）；
##  右侧是拉杆式启动/停止按钮。转动由真实时间驱动，不受游戏倍速影响。
##  玩法不变：玩家「开始 → 看准 → 停止」取当前条目。
##  用法：
##    var m := SlotMachineUI.new()
##    add_child(m)
##    m.setup(entries, "标题")   # entries: [{id,name,desc,color,icon,data}]
##    m.stopped.connect(_on_stopped)
## ============================================================

signal stopped(entry: Dictionary)
signal started()

const FS_TITLE: int = 10
const FS_BODY: int = 9
const FS_SMALL: int = 6

const ROW_H: int = 18          # 单格高度
const REEL_W: int = 132        # 转轮窗口宽度
const STRIP_ROWS: int = 5      # 符号条格数（-2 / -1 / 当前 / +1 / +2）
const PAYLINE_ROW: int = 2     # 中奖线在符号条中的下标

enum SpinState { IDLE, SPINNING, STOPPING, DONE }

var _entries: Array = []
var _state: int = SpinState.IDLE
var _index: int = 0
var _phase: float = 0.0          # 当前滚动到下一格的进度 0..1
var _interval: float = 0.16      # 每滚一格用时（真实秒）
var _spin_elapsed: float = 0.0
var _decel_ticks: int = 0
var _stop_at_boundary: bool = false
var _start_enabled: bool = true
var _last_tick_usec: int = 0

var _title: Label = null
var _window: Control = null
var _strip: Control = null
var _strip_rows: Array = []      # 5 个 {box,label,icon}
var _button: Button = null
var _hint: Label = null

var _gold_color := Color(0.98, 0.75, 0.25)
var _dim_color := Color(0.55, 0.55, 0.58)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func setup(entries: Array, title: String = "轮盘") -> void:
	_entries = entries.duplicate()
	_index = 0
	_state = SpinState.IDLE
	_phase = 0.0
	_interval = 0.16
	_spin_elapsed = 0.0
	_decel_ticks = 0
	_stop_at_boundary = false
	_last_tick_usec = Time.get_ticks_usec()
	_clear_children()
	_build_ui(title)
	_strip.position.y = -ROW_H   # 归位：让 strip 第2行对准固定金框（窗口中线）
	_update_reel()
	_update_highlight()
	_refresh_button()


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
	_strip_rows.clear()
	_title = null
	_window = null
	_strip = null
	_button = null
	_hint = null


func _build_ui(title: String) -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(REEL_W + 16, 0)
	left.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 1)
	root.add_child(left)

	_title = Label.new()
	_title.text = title
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", FS_TITLE)
	_title.add_theme_color_override("font_color", _gold_color)
	left.add_child(_title)

	# 老虎机外壳（金属边框）
	var frame := PanelContainer.new()
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.14, 0.14, 0.19)
	frame_sb.set_border_width_all(2)
	frame_sb.border_color = Color(0.45, 0.42, 0.5)
	frame_sb.content_margin_left = 1
	frame_sb.content_margin_right = 1
	frame_sb.content_margin_top = 1
	frame_sb.content_margin_bottom = 1
	frame.add_theme_stylebox_override("panel", frame_sb)
	left.add_child(frame)

	var frame_box := VBoxContainer.new()
	frame_box.add_theme_constant_override("separation", 0)
	frame.add_child(frame_box)

	var viewport := HBoxContainer.new()
	viewport.alignment = BoxContainer.ALIGNMENT_CENTER
	viewport.add_theme_constant_override("separation", 1)
	frame_box.add_child(viewport)

	# 中奖线左右箭头标记
	var marker_l := Label.new()
	marker_l.text = ">"
	marker_l.add_theme_font_size_override("font_size", FS_BODY)
	marker_l.add_theme_color_override("font_color", _gold_color)
	marker_l.set_anchors_preset(Control.PRESET_CENTER)
	marker_l.custom_minimum_size = Vector2(6, ROW_H * 3)
	marker_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(marker_l)

	# 转轮窗口：裁剪内容，符号条在里面连续滚动
	_window = Control.new()
	_window.custom_minimum_size = Vector2(REEL_W, ROW_H * 3)
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(_window)

	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_strip)
	for k in range(STRIP_ROWS):
		_strip.add_child(_make_reel_row(k))

	# 固定中奖线：只画金色边框，不铺背景色，让选中的符号保持原色。
	# 上下两行由 fade 遮罩淡出变灰，中间的聚焦靠金框体现。
	var payline := PanelContainer.new()
	var p_sb := StyleBoxFlat.new()
	p_sb.bg_color = Color(0, 0, 0, 0)
	p_sb.set_border_width_all(2)
	p_sb.border_color = _gold_color
	p_sb.content_margin_left = 0
	p_sb.content_margin_right = 0
	p_sb.content_margin_top = 0
	p_sb.content_margin_bottom = 0
	payline.add_theme_stylebox_override("panel", p_sb)
	payline.position = Vector2(0, ROW_H)
	payline.size = Vector2(REEL_W, ROW_H)
	payline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(payline)

	var marker_r := Label.new()
	marker_r.text = "<"
	marker_r.add_theme_font_size_override("font_size", FS_BODY)
	marker_r.add_theme_color_override("font_color", _gold_color)
	marker_r.custom_minimum_size = Vector2(6, ROW_H * 3)
	marker_r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(marker_r)

	_hint = Label.new()
	_hint.text = ""
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", FS_SMALL)
	_hint.add_theme_color_override("font_color", _dim_color)
	left.add_child(_hint)

	# 右侧拉杆式按钮：固定尺寸，转动时不拉伸
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(60, 0)
	right.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(right)
	_button = Button.new()
	_button.text = "开始"
	_button.custom_minimum_size = Vector2(56, 22)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button.clip_text = true
	_button.add_theme_font_size_override("font_size", FS_BODY)
	BuildUI.style_button(_button, _gold_color)
	_button.pressed.connect(_on_button_pressed)
	right.add_child(_button)


func _make_reel_row(k: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.position = Vector2(0, k * ROW_H)
	box.size = Vector2(REEL_W, ROW_H)
	box.custom_minimum_size = Vector2(REEL_W, ROW_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.24, 0.24, 0.29)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	box.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 4)
	box.add_child(hb)

	var icon_holder := PanelContainer.new()
	icon_holder.custom_minimum_size = Vector2(16, 16)
	icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.06, 0.06, 0.09)
	isb.content_margin_left = 0
	isb.content_margin_right = 0
	isb.content_margin_top = 0
	isb.content_margin_bottom = 0
	icon_holder.add_theme_stylebox_override("panel", isb)
	var icon_rect := TextureRect.new()
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(icon_rect)
	hb.add_child(icon_holder)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", FS_BODY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(96, 0)
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hb.add_child(name_label)

	_strip_rows.append({"box": box, "label": name_label, "icon": icon_rect})
	return box



func _on_button_pressed() -> void:
	if _state == SpinState.IDLE:
		start_spin()
	elif _state == SpinState.SPINNING:
		request_stop()


func start_spin() -> void:
	if _entries.is_empty() or _state == SpinState.SPINNING or _state == SpinState.STOPPING:
		return
	if not _start_enabled:
		return
	_state = SpinState.SPINNING
	_phase = 0.0
	_interval = 0.16
	_spin_elapsed = 0.0
	_decel_ticks = 0
	_stop_at_boundary = false
	_last_tick_usec = Time.get_ticks_usec()
	_hint.text = "看准中奖线，按右侧按钮停"
	_refresh_button()
	started.emit()


func request_stop() -> void:
	if _state != SpinState.SPINNING:
		return
	_state = SpinState.STOPPING
	_decel_ticks = 0
	_hint.text = "减速中……"
	_refresh_button()


func is_spinning() -> bool:
	return _state == SpinState.SPINNING or _state == SpinState.STOPPING


## 外部可按金币等条件禁用「开始」按钮
func set_start_enabled(value: bool) -> void:
	_start_enabled = value
	_refresh_button()


func _refresh_button() -> void:
	if _button == null:
		return
	match _state:
		SpinState.SPINNING:
			_button.text = "停！"
			_button.disabled = false
		SpinState.STOPPING:
			_button.text = "减速…"
			_button.disabled = true
		SpinState.DONE:
			_button.text = "已停止"
			_button.disabled = true
		_:
			_button.text = "开始"
			_button.disabled = not _start_enabled


func get_current_entry() -> Dictionary:
	if _entries.is_empty():
		return {}
	return _entries[_index]


func _process(_delta: float) -> void:
	if _state == SpinState.IDLE or _state == SpinState.DONE:
		return
	# 真实时间推进，不受游戏倍速 / Engine.time_scale 影响
	var now: int = Time.get_ticks_usec()
	var real_delta: float = float(now - _last_tick_usec) / 1000000.0
	_last_tick_usec = now
	_spin_elapsed += real_delta
	if _state == SpinState.SPINNING:
		_interval = maxf(0.085, 0.16 - _spin_elapsed * 0.10)
	_phase += real_delta / maxf(_interval, 0.01)

	# 连续滚动：整数格推进时换内容；STOPPING 每格递增间隔做减速
	while _phase >= 1.0:
		_phase -= 1.0
		_index = (_index + 1) % _entries.size()
		_update_reel()
		if _state == SpinState.STOPPING:
			_interval = minf(0.30, _interval + 0.05)
			_decel_ticks += 1
			if _decel_ticks >= 8:
				_stop_at_boundary = true

	# 落到整格后才真正停止，保证中奖线对准一个符号
	if _stop_at_boundary:
		_phase = 0.0
		_finish()
		return

	# 符号条整体上移/下移：phase 越大越接近下一格（新符号从上方进入）
	_strip.position.y = -ROW_H + _phase * ROW_H
	_update_highlight()


func _update_reel() -> void:
	if _strip_rows.size() < STRIP_ROWS or _entries.is_empty():
		return
	var n: int = _entries.size()
	for k in range(STRIP_ROWS):
		var idx: int = (_index + (PAYLINE_ROW - k)) % n
		if idx < 0:
			idx += n
		var entry: Dictionary = _entries[idx]
		var row: Dictionary = _strip_rows[k]
		var label: Label = row["label"] as Label
		label.text = str(entry.get("name", "?"))
		var icon_rect: TextureRect = row["icon"] as TextureRect
		var icon_v: Variant = entry.get("icon", null)
		if icon_v is Texture2D:
			icon_rect.texture = icon_v as Texture2D
		else:
			icon_rect.texture = null
		var cv: Variant = entry.get("color", null)
		var text_color: Color = Color.WHITE
		if cv is Color:
			text_color = cv as Color
		label.add_theme_color_override("font_color", text_color)


## ★ 高亮始终给「正落在窗口中线金框的那一行」：
##   行 k 的屏幕中心 = (k-1+phase)*ROW_H + ROW_H/2，金框中心 = 1.5*ROW_H；
##   距离最小即最近的 k。静止 phase=0 → k=2（中行）；滚动过半 → k=1。
func _update_highlight() -> void:
	if _strip_rows.is_empty():
		return
	var best_k: int = 2
	var best_dist: float = 999.0
	for k in range(STRIP_ROWS):
		var dist: float = absf(float(k) - 2.0 + _phase)
		if dist < best_dist:
			best_dist = dist
			best_k = k
	for k in range(STRIP_ROWS):
		var row_box: PanelContainer = _strip_rows[k]["box"] as PanelContainer
		if row_box == null:
			continue
		row_box.modulate = Color.WHITE if k == best_k else Color(1, 1, 1, 0.55)


func _finish() -> void:
	_state = SpinState.DONE
	_strip.position.y = -ROW_H
	_phase = 0.0
	_update_highlight()
	_hint.text = "已停：%s" % str(get_current_entry().get("name", "?"))
	_refresh_button()
	stopped.emit(get_current_entry())
