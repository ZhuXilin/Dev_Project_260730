extends Control
const BuildUI = preload("res://function/script/build/BuildUI.gd")

## ============================================================
##  SlotMachineUI — v6.3 通用纵向轮盘老虎机
## ============================================================
##  玩家主动「开始 → 停止」选结果，而不是系统直接给结果。
##  视觉完全对齐参考图：纵向只显示 3 行（上一条 / 当前 / 下一条），
##  当前行金色高亮；右侧一个按钮，空闲时是开始，旋转时是停止。
##  启动后加速，按下停止后减速 6 格停住。
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

enum SpinState { IDLE, SPINNING, STOPPING, DONE }

var _entries: Array = []
var _state: int = SpinState.IDLE
var _index: int = 0
var _tick: float = 0.0
var _interval: float = 0.16
var _spin_elapsed: float = 0.0
var _decel_ticks: int = 0
var _start_enabled: bool = true
var _last_tick_usec: int = 0
var _spin_phase: float = 0.0

var _title: Label = null
var _rows: Array = []          # 3 个 PanelContainer：上 / 当前 / 下
var _row_labels: Array = []    # 3 个 Label
var _row_icons: Array = []     # 3 个 TextureRect
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
	_tick = 0.0
	_interval = 0.16
	_spin_elapsed = 0.0
	_decel_ticks = 0
	_last_tick_usec = Time.get_ticks_usec()
	_clear_children()
	_build_ui(title)
	_update_reel()
	_apply_reel_motion()
	_refresh_button()


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_row_labels.clear()
	_row_icons.clear()
	_title = null
	_button = null
	_hint = null


func _build_ui(title: String) -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 轮盘区域收窄居中：图标+文字作为一组居中，不再铺满全宽
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(140, 0)
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

	# 纵向三行：上一条 / 当前 / 下一条
	for row_i in range(3):
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(140, 16)
		box.size_flags_horizontal = Control.SIZE_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.16)
		sb.set_border_width_all(1)
		sb.border_color = _dim_color
		box.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 4)
		box.add_child(hb)
		var icon_holder := PanelContainer.new()
		icon_holder.custom_minimum_size = Vector2(18, 18)
		icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0.08, 0.08, 0.11)
		icon_holder.add_theme_stylebox_override("panel", isb)
		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.custom_minimum_size = Vector2(16, 16)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_holder.add_child(icon_rect)
		hb.add_child(icon_holder)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", FS_BODY)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.custom_minimum_size = Vector2(100, 0)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hb.add_child(name_label)
		left.add_child(box)
		_rows.append(box)
		_row_labels.append(name_label)
		_row_icons.append(icon_rect)

	_hint = Label.new()
	_hint.text = ""
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", FS_SMALL)
	_hint.add_theme_color_override("font_color", _dim_color)
	left.add_child(_hint)

	# 右侧同一个按钮：固定小尺寸，像老虎机上的启动/停止键，转动时不拉伸
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
	_tick = 0.0
	_interval = 0.16
	_spin_elapsed = 0.0
	_decel_ticks = 0
	_last_tick_usec = Time.get_ticks_usec()
	_hint.text = "看准目标，按右侧按钮停"
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
	# 用真实时间推进，不受游戏倍速 / Engine.time_scale 影响
	var now: int = Time.get_ticks_usec()
	var real_delta: float = float(now - _last_tick_usec) / 1000000.0
	_last_tick_usec = now
	# 上下行做渐隐 + 轻微纵向拉伸，形成连续滚动的视觉，而不是纯跳图标
	_spin_phase += real_delta * 9.0
	_apply_reel_motion()
	_tick -= real_delta
	if _tick > 0.0:
		return
	if _state == SpinState.SPINNING:
		_spin_elapsed += _interval
		# 慢速加速：0.16s → 0.085s，节奏清晰可见
		_interval = maxf(0.085, 0.16 - _spin_elapsed * 0.10)
		_advance()
		_tick = _interval
	elif _state == SpinState.STOPPING:
		# 慢速减速：每格 +0.05s，8 格后停住
		_interval = minf(0.30, _interval + 0.05)
		_advance()
		_tick = _interval
		_decel_ticks += 1
		if _decel_ticks >= 8:
			_finish()


## 上下行半透明 + 轻微拉伸，焦点集中在中间行
func _apply_reel_motion() -> void:
	for r in range(_rows.size()):
		var box: PanelContainer = _rows[r] as PanelContainer
		if box == null:
			continue
		var focus: bool = (r == 1)
		var alpha: float = 1.0 if focus else 0.38
		box.modulate = Color(1.0, 1.0, 1.0, alpha)
		box.scale = Vector2.ONE


func _advance() -> void:
	if _entries.is_empty():
		return
	_index = (_index + 1) % _entries.size()
	_update_reel()


func _update_reel() -> void:
	if _row_labels.size() < 3 or _entries.is_empty():
		return
	var entry_count: int = _entries.size()
	# ★ 滚动方向：从上往下——新条目从顶部进入，当前居中，旧条目从底部离开
	var indices: Array = [
		(_index + 1) % entry_count,
		_index,
		(_index - 1 + entry_count) % entry_count,
	]
	for r in range(3):
		var entry: Dictionary = _entries[indices[r]]
		var label: Label = _row_labels[r] as Label
		label.text = str(entry.get("name", "?"))
		var icon_rect: TextureRect = _row_icons[r] as TextureRect
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
		var box: PanelContainer = _rows[r] as PanelContainer
		# 每次新建 StyleBoxFlat 再覆盖；Godot 4 的方法名是 add_theme_stylebox_override
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(1)
		if r == 1:
			sb.bg_color = Color(0.28, 0.22, 0.10)
			sb.border_color = _gold_color
		else:
			sb.bg_color = Color(0.12, 0.12, 0.16)
			sb.border_color = _dim_color
		box.add_theme_stylebox_override("panel", sb)


func _finish() -> void:
	_state = SpinState.DONE
	_apply_reel_motion()
	_hint.text = "已停：%s" % str(get_current_entry().get("name", "?"))
	_refresh_button()
	stopped.emit(get_current_entry())
