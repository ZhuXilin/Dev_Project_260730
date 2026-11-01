@tool
extends Control
class_name UnitPoolEditor

# ============================================================
#  UnitPoolEditor — 随机池编辑面板（超级巨大版 · 去阵营）
# ============================================================

var _enemy_pool : Array[String] = []
var _callback : Callable = Callable()
var _ui_built : bool = false

var _unit_list : VBoxContainer
var _branch_list : VBoxContainer
var _pool_list : VBoxContainer
var _hint_label : Label

var _selected_unit : String = ""
var _selected_branch : String = ""


func setup(pool : Array, callback : Callable):
	_enemy_pool.clear()
	for p in pool:
		if p is String and (p as String) != "":
			_enemy_pool.append(p)
	_callback = callback
	if is_inside_tree():
		_build_ui()


func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _input(event: InputEvent):
	if not _ui_built: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_ok()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()


func _build_ui():
	if _ui_built: return
	_ui_built = true

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13, 1)
	sb.border_color = Color(0.50, 0.50, 0.60, 1)
	sb.border_width_left = 6
	sb.border_width_right = 6
	sb.border_width_top = 6
	sb.border_width_bottom = 6
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 64
	sb.content_margin_right = 64
	sb.content_margin_top = 64
	sb.content_margin_bottom = 64
	panel.add_theme_stylebox_override("panel", sb)
	
	# ★ 尺寸再翻一倍
	panel.custom_minimum_size = Vector2(3200, 2000)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 40)
	panel.add_child(root)

	var title_lb := Label.new()
	title_lb.text = "编辑随机池"
	title_lb.add_theme_font_size_override("font_size", 80) # 翻倍
	root.add_child(title_lb)

	var hint_lb := Label.new()
	hint_lb.text = "① 左列点单位  ② 中列选转职分支（可选）  ③ 点「加入池」  ④ 右列可排序 / 删除 (回车确认 / Esc取消)"
	hint_lb.add_theme_font_size_override("font_size", 44) # 翻倍
	hint_lb.modulate = Color(0.6, 0.6, 0.6)
	root.add_child(hint_lb)

	root.add_child(HSeparator.new())

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 64)
	root.add_child(hbox)

	# 左列
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(800, 0)
	hbox.add_child(left_col)
	left_col.add_child(_make_section_label("单位职业"))
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(left_scroll)
	_unit_list = VBoxContainer.new()
	_unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_list.add_theme_constant_override("separation", 8)
	left_scroll.add_child(_unit_list)

	# 中列
	var mid_col := VBoxContainer.new()
	mid_col.custom_minimum_size = Vector2(800, 0)
	hbox.add_child(mid_col)
	mid_col.add_child(_make_section_label("转职分支"))
	var mid_scroll := ScrollContainer.new()
	mid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid_col.add_child(mid_scroll)
	_branch_list = VBoxContainer.new()
	_branch_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_branch_list.add_theme_constant_override("separation", 8)
	mid_scroll.add_child(_branch_list)

	var add_btn := Button.new()
	add_btn.text = "+ 加入池"
	add_btn.custom_minimum_size = Vector2(0, 120) # 翻倍
	add_btn.add_theme_font_size_override("font_size", 56) # 翻倍
	add_btn.pressed.connect(_on_add_pressed)
	mid_col.add_child(add_btn)

	# 右列
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_col)

	var right_top := HBoxContainer.new()
	right_top.add_theme_constant_override("separation", 32)
	right_col.add_child(right_top)
	var pool_lb := _make_section_label("当前池")
	pool_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_top.add_child(pool_lb)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.custom_minimum_size = Vector2(300, 100)
	clear_btn.add_theme_font_size_override("font_size", 48)
	clear_btn.pressed.connect(_on_clear_pressed)
	right_top.add_child(clear_btn)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(right_scroll)
	_pool_list = VBoxContainer.new()
	_pool_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_list.add_theme_constant_override("separation", 16)
	right_scroll.add_child(_pool_list)

	# 底部
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 64)
	root.add_child(bottom)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 48)
	_hint_label.modulate = Color(0.7, 0.9, 0.7)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_hint_label)

	var ok_btn := Button.new()
	ok_btn.text = "确定 (Enter)"
	ok_btn.custom_minimum_size = Vector2(500, 140)
	ok_btn.add_theme_font_size_override("font_size", 56)
	ok_btn.pressed.connect(_on_ok)
	bottom.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消 (Esc)"
	cancel_btn.custom_minimum_size = Vector2(500, 140)
	cancel_btn.add_theme_font_size_override("font_size", 56)
	cancel_btn.pressed.connect(_on_cancel)
	bottom.add_child(cancel_btn)

	_refresh_unit_list()
	_refresh_branch_list()
	_refresh_pool_list()

	if not _enemy_pool.is_empty():
		var parts : PackedStringArray = _enemy_pool[0].split(":", false)
		var base : String = parts[0] if parts.size() > 0 else ""
		if base != "":
			_selected_unit = base
			if parts.size() >= 2: _selected_branch = parts[1]
			_refresh_unit_list()
			_refresh_branch_list()


func _make_section_label(text : String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 56) # 翻倍
	l.modulate = Color(0.85, 0.85, 1.0)
	return l


func _refresh_unit_list():
	for c in _unit_list.get_children(): c.queue_free()
	for k in UnitDataManager.get_all_unit_ids():
		var btn := Button.new()
		# ★ 只保留职业名，不显示人名，不显示阵营
		btn.text = UnitDataManager.get_unit_type_display_name(k)
		
		btn.toggle_mode = true
		btn.button_pressed = (k == _selected_unit)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 100) # 翻倍
		btn.add_theme_font_size_override("font_size", 48) # 翻倍
		btn.pressed.connect(_select_unit.bind(k))
		_unit_list.add_child(btn)


func _select_unit(unit_key : String):
	if _selected_unit == unit_key: return
	_selected_unit = unit_key
	_selected_branch = ""
	_refresh_unit_list()
	_refresh_branch_list()


func _refresh_branch_list():
	for c in _branch_list.get_children(): c.queue_free()
	if _selected_unit == "": return
	_branch_list.add_child(_make_branch_btn("（无转职）", ""))
	var ud : Dictionary = UnitDataManager.get_unit_data(_selected_unit)
	for b in ud.get("advanced_branches", []):
		if b is Dictionary and str(b.get("id", "")) != "":
			_branch_list.add_child(_make_branch_btn(str(b.get("name", "")), str(b.get("id", ""))))


func _make_branch_btn(text : String, branch_id : String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_pressed = (branch_id == _selected_branch)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 100) # 翻倍
	btn.add_theme_font_size_override("font_size", 48) # 翻倍
	btn.pressed.connect(func():
		_selected_branch = branch_id
		_refresh_branch_list()
	)
	return btn


func _on_add_pressed():
	if _selected_unit == "": return
	var entry : String = _selected_unit if _selected_branch == "" else "%s:%s" % [_selected_unit, _selected_branch]
	if entry in _enemy_pool:
		_set_hint("已在池中")
		return
	_enemy_pool.append(entry)
	_refresh_pool_list()
	_set_hint("已加入")


func _on_clear_pressed():
	_enemy_pool.clear()
	_refresh_pool_list()
	_set_hint("已清空")


func _refresh_pool_list():
	for c in _pool_list.get_children(): c.queue_free()
	if _enemy_pool.is_empty():
		var hint := Label.new()
		hint.text = "（池为空）"
		hint.modulate = Color(0.5, 0.5, 0.5)
		hint.add_theme_font_size_override("font_size", 48) # 翻倍
		_pool_list.add_child(hint)
		return

	for i in range(_enemy_pool.size()):
		var entry : String = _enemy_pool[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 32)
		_pool_list.add_child(row)

		var num_lb := Label.new()
		num_lb.text = "%d." % (i + 1)
		num_lb.custom_minimum_size = Vector2(100, 0)
		num_lb.add_theme_font_size_override("font_size", 48) # 翻倍
		row.add_child(num_lb)

		var lb := Label.new()
		var parts : PackedStringArray = entry.split(":", false)
		var base_key : String = parts[0] if parts.size() > 0 else ""
		
		var display_text : String = UnitDataManager.get_unit_type_display_name(base_key)
		if parts.size() >= 2 and parts[1] != "":
			var adv_name : String = parts[1]
			var ud : Dictionary = UnitDataManager.get_unit_data(base_key)
			for b in ud.get("advanced_branches", []):
				if b is Dictionary and str(b.get("id", "")) == parts[1]:
					adv_name = str(b.get("name", parts[1]))
					break
			display_text += " → " + adv_name

		lb.text = display_text
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.clip_text = true
		lb.add_theme_font_size_override("font_size", 48) # 翻倍
		row.add_child(lb)

		var idx : int = i
		var up_btn := Button.new()
		up_btn.text = "↑"
		up_btn.custom_minimum_size = Vector2(120, 100) # 翻倍
		up_btn.add_theme_font_size_override("font_size", 48) # 翻倍
		up_btn.disabled = (i == 0)
		up_btn.pressed.connect(func(): _swap(idx, idx - 1))
		row.add_child(up_btn)

		var down_btn := Button.new()
		down_btn.text = "↓"
		down_btn.custom_minimum_size = Vector2(120, 100) # 翻倍
		down_btn.add_theme_font_size_override("font_size", 48) # 翻倍
		down_btn.disabled = (i == _enemy_pool.size() - 1)
		down_btn.pressed.connect(func(): _swap(idx, idx + 1))
		row.add_child(down_btn)

		var del_btn := Button.new()
		del_btn.text = "×"
		del_btn.custom_minimum_size = Vector2(120, 100) # 翻倍
		del_btn.add_theme_font_size_override("font_size", 48) # 翻倍
		del_btn.modulate = Color(1.0, 0.6, 0.6)
		del_btn.pressed.connect(func():
			if idx >= 0 and idx < _enemy_pool.size():
				_enemy_pool.remove_at(idx)
				_refresh_pool_list()
		)
		row.add_child(del_btn)


func _swap(a : int, b : int):
	if a < 0 or b < 0 or a >= _enemy_pool.size() or b >= _enemy_pool.size(): return
	var t : String = _enemy_pool[a]
	_enemy_pool[a] = _enemy_pool[b]
	_enemy_pool[b] = t
	_refresh_pool_list()


func _set_hint(text : String):
	if _hint_label: _hint_label.text = text

func _on_ok():
	if _callback.is_valid(): _callback.call(_enemy_pool.duplicate())
	queue_free()

func _on_cancel():
	queue_free()
