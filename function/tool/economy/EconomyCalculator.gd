extends Control

# ============================================================
#  EconomyCalculator — 通用 JSON 配置编辑器 + 多布局收益模拟
#  - 手动保存 / 手动重载（无自动保存）
#  - 递归自动生成 UI
#  - 布局多选，横向对比
# ============================================================

const CONFIG_DIR : String = "res://content/data/config/"
const LAYOUT_DIR : String = "res://content/scenes/levels/maplayout/"

const CONFIG_FILES : Array = [
	{"name": "经济", "file": "economy_config.json"},
	{"name": "战斗", "file": "combat_config.json"},
	{"name": "成长", "file": "progression_config.json"},
	{"name": "竞技场", "file": "arena_config.json"},
]

const COMBAT_TYPES : Array = ["START", "NORMAL", "ELITE", "BOSS"]
const TYPE_NAMES : Array = ["START", "NORMAL", "ELITE", "SHOP", "TREASURE", "BOSS", "FORGE", "CHAPEL"]

# ---- 状态 ----
var _current_file_idx : int = 0
var _cfg : Dictionary = {}
var _layouts : Array = []
var _selected_layout_indices : Array = [0]

# ---- UI ----
var _file_buttons : Array = []
var _layout_btn : Button = null
var _layout_menu : PopupMenu = null
var _layout_summary : Label = null
var _layout_row : HBoxContainer = null
var _dirty : bool = false
var _status_label : Label = null
var _editor_vbox : VBoxContainer = null
var _sim_section : VBoxContainer = null
var _sim_grid : GridContainer = null


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_scan_layouts()
	_build_ui()
	_load_current_file()


func _scan_layouts():
	_layouts.clear()
	if not DirAccess.dir_exists_absolute(LAYOUT_DIR): return
	var dir := DirAccess.open(LAYOUT_DIR)
	if dir == null: return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var path : String = LAYOUT_DIR + fname
			var res = load(path)
			if res is MapLayout:
				_layouts.append({"name": fname, "path": path, "resource": res})
		fname = dir.get_next()
	dir.list_dir_end()
	_layouts.sort_custom(func(a, b): return a["name"] < b["name"])
	if _layouts.is_empty():
		_selected_layout_indices = []
	elif _selected_layout_indices.is_empty():
		_selected_layout_indices = [0]


func _count_layout_nodes(layout : MapLayout) -> Dictionary:
	var result : Dictionary = {}
	for day in [1, 2, 3]:
		var variants : Array = []
		match day:
			1: variants = layout.day1_variants
			2: variants = layout.day2_variants
			3: variants = layout.day3_variants
		var day_counts : Dictionary = {}
		if not variants.is_empty():
			var dl : MapLayoutDay = variants[0]
			for node in dl.nodes:
				var t : int = node.node_type
				if not node.random_pool.is_empty():
					t = node.random_pool[0]
				if t < 0 or t >= TYPE_NAMES.size(): continue
				var key : String = TYPE_NAMES[t]
				day_counts[key] = day_counts.get(key, 0) + 1
		result[day] = day_counts
	return result


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 4
	root.offset_top = 4
	root.offset_right = -4
	root.offset_bottom = -4
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	_build_topbar(root)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	root.add_child(body)

	_build_left_column(body)
	_build_right_column(body)


func _build_topbar(parent : Node):
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	parent.add_child(bar)

	var title := Label.new()
	title.text = "配置编辑器"
	title.add_theme_font_size_override("font_size", 8)
	bar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 6)
	_status_label.modulate = Color(0.7, 0.9, 0.7)
	bar.add_child(_status_label)

	# ★ 手动保存 / 重载
	var reload_btn := Button.new()
	reload_btn.text = "重载"
	reload_btn.add_theme_font_size_override("font_size", 7)
	reload_btn.pressed.connect(_load_current_file)
	bar.add_child(reload_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.add_theme_font_size_override("font_size", 7)
	save_btn.pressed.connect(_do_save)
	bar.add_child(save_btn)


# ---- 左栏：配置文件列表 ----
func _build_left_column(parent : Node):
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(70, 0)
	left.add_theme_constant_override("separation", 1)
	parent.add_child(left)

	var lb := Label.new()
	lb.text = "— 文件 —"
	lb.add_theme_font_size_override("font_size", 7)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.modulate = Color(0.75, 0.75, 0.9)
	left.add_child(lb)

	_file_buttons.clear()
	for i in range(CONFIG_FILES.size()):
		var btn := Button.new()
		btn.text = CONFIG_FILES[i]["name"]
		btn.add_theme_font_size_override("font_size", 7)
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func():
			_current_file_idx = i
			_refresh_file_buttons()
			_load_current_file()
		)
		left.add_child(btn)
		_file_buttons.append(btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)

	_refresh_file_buttons()


func _refresh_file_buttons():
	for i in range(_file_buttons.size()):
		var btn : Button = _file_buttons[i]
		btn.button_pressed = (i == _current_file_idx)
		btn.modulate = Color.WHITE if i == _current_file_idx else Color(0.65, 0.65, 0.65)


# ---- 右栏 ----
func _build_right_column(parent : Node):
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 3)
	parent.add_child(right)

	# ---- 布局多选行 ----
	_layout_row = HBoxContainer.new()
	_layout_row.add_theme_constant_override("separation", 4)
	right.add_child(_layout_row)

	var layout_lb := Label.new()
	layout_lb.text = "布局:"
	layout_lb.add_theme_font_size_override("font_size", 7)
	_layout_row.add_child(layout_lb)

	_layout_btn = Button.new()
	_layout_btn.text = "选择布局 (0)"
	_layout_btn.add_theme_font_size_override("font_size", 7)
	_layout_btn.custom_minimum_size = Vector2(120, 0)
	_layout_btn.pressed.connect(_open_layout_menu)
	_layout_row.add_child(_layout_btn)

	_layout_menu = PopupMenu.new()
	_layout_menu.add_theme_font_size_override("font_size", 7)
	_layout_menu.id_pressed.connect(_on_layout_menu_pressed)
	add_child(_layout_menu)

	_layout_summary = Label.new()
	_layout_summary.add_theme_font_size_override("font_size", 6)
	_layout_summary.modulate = Color(0.7, 0.7, 0.8)
	_layout_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_row.add_child(_layout_summary)

	# ---- 编辑器 ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)

	_editor_vbox = VBoxContainer.new()
	_editor_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_editor_vbox)

	# ---- 模拟 ----
	_sim_section = VBoxContainer.new()
	_sim_section.add_theme_constant_override("separation", 2)
	right.add_child(_sim_section)

	var sim_title := Label.new()
	sim_title.text = "══ 收益模拟 ══"
	sim_title.add_theme_font_size_override("font_size", 7)
	sim_title.modulate = Color(0.8, 0.85, 1.0)
	_sim_section.add_child(sim_title)

	var sim_scroll := ScrollContainer.new()
	sim_scroll.custom_minimum_size = Vector2(0, 140)
	sim_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sim_section.add_child(sim_scroll)

	_sim_grid = GridContainer.new()
	_sim_grid.columns = 5
	_sim_grid.add_theme_constant_override("h_separation", 6)
	_sim_grid.add_theme_constant_override("v_separation", 1)
	_sim_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sim_scroll.add_child(_sim_grid)

	_update_layout_label()


# ============================================================
#  布局多选
# ============================================================
func _open_layout_menu():
	_layout_menu.clear()
	if _layouts.is_empty():
		_layout_menu.add_item("（无布局）", -1)
		_layout_menu.set_item_disabled(0, true)
	else:
		for i in range(_layouts.size()):
			_layout_menu.add_check_item(_layouts[i]["name"], i)
			_layout_menu.set_item_checked(i, i in _selected_layout_indices)
	_layout_menu.popup_on_parent(Rect2i(
		Vector2i(_layout_btn.global_position + Vector2(0, _layout_btn.size.y)),
		Vector2i(240, 0)))


func _on_layout_menu_pressed(id : int):
	if id < 0 or id >= _layouts.size():
		return
	if id in _selected_layout_indices:
		_selected_layout_indices.erase(id)
	else:
		_selected_layout_indices.append(id)
	if _selected_layout_indices.is_empty():
		_selected_layout_indices.append(id)
	_update_layout_label()
	_refresh_sim()


func _update_layout_label():
	if _layouts.is_empty():
		_layout_btn.text = "（无布局）"
		_layout_summary.text = ""
		return
	var names : Array = []
	for i in _selected_layout_indices:
		if i >= 0 and i < _layouts.size():
			names.append(_layouts[i]["name"].replace(".tres", ""))
	_layout_btn.text = "选择布局 (%d)" % _selected_layout_indices.size()
	_layout_summary.text = "已选: " + ", ".join(names) if names.size() > 0 else "（无）"


# ============================================================
#  加载 / 保存
# ============================================================
func _load_current_file():
	var fname : String = CONFIG_FILES[_current_file_idx]["file"]
	var src : Dictionary = GameConfigManager.get_file(fname)
	_cfg = src.duplicate(true) if not src.is_empty() else {}
	_dirty = false
	_refresh_editor()
	_refresh_sim_visibility()
	_set_status("已重载: " + fname)


func _do_save():
	var fname : String = CONFIG_FILES[_current_file_idx]["file"]
	var path : String = CONFIG_DIR + fname
	var json_str : String = JSON.stringify(_cfg, "  ")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("❌ 保存失败: " + fname)
		return
	f.store_string(json_str)
	f.close()
	GameConfigManager.reload(fname)
	_dirty = false
	_set_status("✓ 已保存: " + fname)
	print("[EconomyCalculator] 保存: ", path)


# ============================================================
#  编辑器构建（递归）
# ============================================================
func _refresh_editor():
	for c in _editor_vbox.get_children():
		_editor_vbox.remove_child(c)
		c.queue_free()
	if _cfg.is_empty():
		var hint := Label.new()
		hint.text = "（空配置）"
		hint.add_theme_font_size_override("font_size", 7)
		hint.modulate = Color(0.6, 0.6, 0.6)
		_editor_vbox.add_child(hint)
		return
	_render_dict(_editor_vbox, _cfg, "", 0)


func _render_dict(parent : Node, dict : Dictionary, prefix : String, depth : int):
	for key in dict.keys():
		var value = dict[key]
		var path : String = key if prefix == "" else prefix + "." + key
		_render_field(parent, dict, key, value, path, depth)


func _render_field(parent : Node, target_dict : Dictionary, key : String, value, path : String, depth : int):
	var t : int = typeof(value)
	if t == TYPE_DICTIONARY:
		_render_group(parent, value, path, depth)
		return
	if t == TYPE_ARRAY:
		_render_array(parent, target_dict, key, value, path, depth)
		return
	_render_simple_row(parent, target_dict, key, value, path)


func _render_group(parent : Node, dict : Dictionary, path : String, depth : int):
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.18, 1.0) if depth % 2 == 0 else Color(0.12, 0.12, 0.15, 1.0)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "▼ " + (path if path != "" else "根")
	title.add_theme_font_size_override("font_size", 7)
	title.modulate = Color(0.85, 0.85, 1.0)
	vb.add_child(title)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	vb.add_child(content)

	title.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			content.visible = not content.visible
			title.text = ("▼ " if content.visible else "▶ ") + (path if path != "" else "根")
	)

	_render_dict(content, dict, path, depth + 1)


func _render_array(parent : Node, target_dict : Dictionary, key : String, arr : Array, path : String, depth : int):
	var all_simple : bool = true
	for v in arr:
		var t : int = typeof(v)
		if t == TYPE_DICTIONARY or t == TYPE_ARRAY:
			all_simple = false
			break

	if all_simple:
		_render_simple_array(parent, target_dict, key, arr, path)
		return

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.16, 1.0)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "▼ %s [%d]" % [path, arr.size()]
	title.add_theme_font_size_override("font_size", 7)
	title.modulate = Color(0.85, 0.85, 1.0)
	vb.add_child(title)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	vb.add_child(content)

	title.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			content.visible = not content.visible
	)

	for i in range(arr.size()):
		var v = arr[i]
		var t : int = typeof(v)
		if t == TYPE_DICTIONARY:
			var sub_path : String = "%s[%d]" % [path, i]
			var wrapped := VBoxContainer.new()
			content.add_child(wrapped)
			_render_array_item_dict(wrapped, arr, i, sub_path, depth + 1)
		elif t == TYPE_ARRAY:
			_render_simple_row_widget(content, "%s[%d]" % [path, i], JSON.stringify(v), func(new_text):
				var parsed = JSON.parse_string(new_text)
				if parsed != null:
					arr[i] = parsed
					_dirty = true
					_refresh_sim()
			)
		else:
			_render_array_index_editor(content, arr, i, "%s[%d]" % [path, i])


func _render_array_item_dict(parent : Node, arr : Array, idx : int, path : String, depth : int):
	var dict : Dictionary = arr[idx]
	var sub := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13, 1.0)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sub.add_theme_stylebox_override("panel", sb)
	parent.add_child(sub)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	sub.add_child(vb)

	var title := Label.new()
	title.text = "▼ " + path
	title.add_theme_font_size_override("font_size", 6)
	title.modulate = Color(0.8, 0.8, 0.95)
	vb.add_child(title)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	vb.add_child(content)

	title.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			content.visible = not content.visible
	)

	for k in dict.keys():
		_render_field(content, dict, k, dict[k], "%s.%s" % [path, k], depth + 1)


func _render_simple_array(parent : Node, _target_dict : Dictionary, _key : String, arr : Array, path : String):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = path
	lb.custom_minimum_size = Vector2(110, 0)
	lb.add_theme_font_size_override("font_size", 6)
	row.add_child(lb)

	for i in range(arr.size()):
		var v = arr[i]
		var t : int = typeof(v)
		if t == TYPE_INT:
			var sp := _make_spin(v, -999999, 999999, 1, 44)
			sp.value_changed.connect(func(nv):
				arr[i] = int(nv)
				_dirty = true
				_refresh_sim()
			)
			row.add_child(sp)
		elif t == TYPE_FLOAT:
			var sp := _make_spin(v, -999.0, 999.0, 0.01, 44)
			sp.value_changed.connect(func(nv):
				arr[i] = float(nv)
				_dirty = true
				_refresh_sim()
			)
			row.add_child(sp)
		else:
			var le := LineEdit.new()
			le.text = str(v)
			le.custom_minimum_size = Vector2(44, 0)
			le.add_theme_font_size_override("font_size", 6)
			le.text_changed.connect(func(t2):
				arr[i] = t2
				_dirty = true
			)
			row.add_child(le)


func _render_array_index_editor(parent : Node, arr : Array, i : int, path : String):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = path
	lb.custom_minimum_size = Vector2(110, 0)
	lb.add_theme_font_size_override("font_size", 6)
	row.add_child(lb)

	var v = arr[i]
	var t : int = typeof(v)
	if t == TYPE_INT:
		var sp := _make_spin(v, -999999, 999999, 1, 44)
		sp.value_changed.connect(func(nv):
			arr[i] = int(nv)
			_dirty = true
			_refresh_sim()
		)
		row.add_child(sp)
	elif t == TYPE_FLOAT:
		var sp := _make_spin(v, -999.0, 999.0, 0.01, 44)
		sp.value_changed.connect(func(nv):
			arr[i] = float(nv)
			_dirty = true
			_refresh_sim()
		)
		row.add_child(sp)
	else:
		var le := LineEdit.new()
		le.text = str(v)
		le.custom_minimum_size = Vector2(44, 0)
		le.add_theme_font_size_override("font_size", 6)
		row.add_child(le)


func _render_simple_row(parent : Node, target_dict : Dictionary, key : String, value, path : String):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = key
	lb.custom_minimum_size = Vector2(110, 0)
	lb.add_theme_font_size_override("font_size", 6)
	lb.tooltip_text = path
	lb.clip_text = true
	row.add_child(lb)

	var t : int = typeof(value)
	match t:
		TYPE_INT:
			var sp := _make_spin(value, -999999, 999999, 1, 54)
			sp.value_changed.connect(func(nv):
				target_dict[key] = int(nv)
				_dirty = true
				_refresh_sim()
			)
			row.add_child(sp)
		TYPE_FLOAT:
			var step : float = 0.01 if absf(value) < 10.0 else 0.1
			var sp := _make_spin(value, -999.0, 999.0, step, 54)
			sp.value_changed.connect(func(nv):
				target_dict[key] = float(nv)
				_dirty = true
				_refresh_sim()
			)
			row.add_child(sp)
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = value
			cb.add_theme_font_size_override("font_size", 6)
			cb.toggled.connect(func(p):
				target_dict[key] = p
				_dirty = true
			)
			row.add_child(cb)
		TYPE_STRING:
			var le := LineEdit.new()
			le.text = str(value)
			le.custom_minimum_size = Vector2(100, 0)
			le.add_theme_font_size_override("font_size", 6)
			le.text_changed.connect(func(t2):
				target_dict[key] = t2
				_dirty = true
			)
			row.add_child(le)
		_:
			var lb2 := Label.new()
			lb2.text = str(value)
			lb2.add_theme_font_size_override("font_size", 6)
			lb2.modulate = Color(0.6, 0.6, 0.6)
			row.add_child(lb2)


func _render_simple_row_widget(parent : Node, label : String, initial : String, on_change : Callable):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	lb.text = label
	lb.custom_minimum_size = Vector2(110, 0)
	lb.add_theme_font_size_override("font_size", 6)
	row.add_child(lb)

	var le := LineEdit.new()
	le.text = initial
	le.custom_minimum_size = Vector2(140, 0)
	le.add_theme_font_size_override("font_size", 6)
	le.text_submitted.connect(on_change)
	row.add_child(le)


func _make_spin(value, min_v : float, max_v : float, step : float, w : float) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step
	sp.value = value
	sp.custom_minimum_size = Vector2(w, 0)
	_style_spin(sp, 6)
	return sp


func _style_spin(sp : SpinBox, font_px : int):
	sp.add_theme_font_size_override("font_size", font_px)
	sp.ready.connect(func():
		if not is_instance_valid(sp): return
		var le := sp.get_line_edit()
		if le:
			le.add_theme_font_size_override("font_size", font_px)
		var up = sp.get_node_or_null("up")
		var dn = sp.get_node_or_null("down")
		if up: up.custom_minimum_size = Vector2(5, 4)
		if dn: dn.custom_minimum_size = Vector2(5, 4)
	, CONNECT_ONE_SHOT)


# ============================================================
#  收益模拟（多布局对比）
# ============================================================
func _refresh_sim_visibility():
	var is_economy : bool = CONFIG_FILES[_current_file_idx]["file"] == "economy_config.json"
	_sim_section.visible = is_economy
	_layout_row.visible = is_economy
	if is_economy:
		_refresh_sim()


func _refresh_sim():
	if _sim_grid == null: return
	for c in _sim_grid.get_children():
		_sim_grid.remove_child(c)
		c.queue_free()

	if _selected_layout_indices.is_empty() or _layouts.is_empty():
		_add_cells(["（未选择布局）"])
		return

	var results : Array = []
	for idx in _selected_layout_indices:
		if idx < 0 or idx >= _layouts.size(): continue
		results.append(_simulate_layout(_layouts[idx]))

	_add_cells(["══ 布局对比 ══", "", "", "", ""])
	_add_cells(["布局", "金", "魂", "材料合计", "战斗数"])
	for r in results:
		var mat_sum : int = 0
		for m in r["mats"]:
			mat_sum += int(r["mats"][m])
		_add_cells([
			r["name"],
			str(r["net_gold"]),
			str(r["net_soul"]),
			str(mat_sum),
			str(r["fights"]),
		])

	for r in results:
		_add_cells(["", "", "", "", ""])
		_add_cells(["── %s ──" % r["name"], "", "", "", ""])
		_add_cells(["天", "类型", "次数", "金币", "魂"])
		for row in r["rows"]:
			_add_cells([str(row["day"]), row["label"],
						str(row["count"]), str(row["gold"]), str(row["soul"])])
		_add_cells(["", "战斗合计", str(r["fights"]), str(r["gross_gold"]), str(r["gross_soul"])])
		var mat_parts : Array = []
		for m in r["mats"]:
			mat_parts.append("%s:%d" % [m, r["mats"][m]])
		_add_cells(["", "材料", "", "", " ".join(mat_parts)])
		_add_cells(["", "─ 支出 ─", "", "", ""])
		_add_cells(["", "商店", "", "-" + str(r["shop_spend"]), ""])
		_add_cells(["", "合成", str(r["craft_count"]), "-" + str(r["craft_cost_total"]), ""])
		_add_cells(["", "熔魂换金", str(r["melt_count"]), "+" + str(r["melt_gold"]), "-" + str(r["melt_soul"])])
		_add_cells(["", "★ 净收益", "", str(r["net_gold"]), str(r["net_soul"])])


func _simulate_layout(layout_entry : Dictionary) -> Dictionary:
	var layout : MapLayout = layout_entry["resource"]
	var counts : Dictionary = _count_layout_nodes(layout)

	var reward_gold : Dictionary = _cfg.get("reward_gold", {})
	var reward_soul : Dictionary = _cfg.get("reward_soul", {})
	var reward_mats : Dictionary = _cfg.get("reward_materials", {})
	var material_order : Array = _cfg.get("material_order", [])
	var forge_cfg : Dictionary = _cfg.get("forge", {})
	var params : Dictionary = _cfg.get("params", {})

	var mult : float = float(params.get("drop_mult", 1.0))
	var gross_gold : int = 0
	var gross_soul : int = 0
	var mats : Dictionary = {}
	for m in material_order: mats[m] = 0
	var fights : int = 0
	var rows : Array = []

	for day in [1, 2, 3]:
		var day_counts : Dictionary = counts.get(day, {})
		for type_name in day_counts:
			var count : int = int(day_counts[type_name])
			if count <= 0: continue
			if type_name not in COMBAT_TYPES: continue
			var gold : int = int(int(reward_gold.get(type_name, 0)) * mult) * count
			var soul : int = int(int(reward_soul.get(type_name, 0)) * mult) * count
			gross_gold += gold
			gross_soul += soul
			fights += count
			var m_dict : Dictionary = reward_mats.get(type_name, {})
			for m in m_dict:
				if m in mats:
					mats[m] += int(int(m_dict[m]) * mult) * count
			rows.append({"day": day, "label": type_name, "count": count, "gold": gold, "soul": soul})

	var shop_spend : int = int(params.get("shop_spend", 0))
	var craft_count : int = int(params.get("craft_count", 0))
	var craft_cost_total : int = int(forge_cfg.get("craft_cost", 200)) * craft_count
	var melt_count : int = int(params.get("melt_count", 0))
	var melt_per : int = int(params.get("melt_per", 0))
	var melt_soul : int = melt_per * melt_count
	var melt_gold : int = melt_soul * int(params.get("melt_gold_per_soul", 1))
	var net_gold : int = gross_gold - shop_spend - craft_cost_total + melt_gold
	var net_soul : int = gross_soul - melt_soul

	return {
		"name": layout_entry["name"].replace(".tres", ""),
		"gross_gold": gross_gold,
		"gross_soul": gross_soul,
		"net_gold": net_gold,
		"net_soul": net_soul,
		"fights": fights,
		"mats": mats,
		"rows": rows,
		"shop_spend": shop_spend,
		"craft_count": craft_count,
		"craft_cost_total": craft_cost_total,
		"melt_count": melt_count,
		"melt_gold": melt_gold,
		"melt_soul": melt_soul,
	}


func _add_cells(cells : Array):
	for c in cells:
		var lb := Label.new()
		lb.text = str(c)
		lb.add_theme_font_size_override("font_size", 6)
		_sim_grid.add_child(lb)


# ============================================================
#  状态提示
# ============================================================
func _set_status(text : String):
	if _status_label:
		_status_label.text = text
