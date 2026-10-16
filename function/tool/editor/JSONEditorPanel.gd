class_name JSONEditorPanel
extends VBoxContainer

# ============================================================
#  JSONEditorPanel — 通用 JSON 编辑器（手动保存）
# ============================================================

signal saved(path : String)

var _path : String = ""
var _cfg : Dictionary = {}
var _editor_vbox : VBoxContainer = null
var _status : Label = null
var _dirty : bool = false


func setup(path : String, title : String = ""):
	_path = path
	if title != "":
		var lb := Label.new()
		lb.text = title
		lb.add_theme_font_size_override("font_size", 8)
		add_child(lb)
	_build_ui()
	_load()


func _build_ui():
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	add_child(bar)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 6)
	_status.modulate = Color(0.7, 0.9, 0.7)
	bar.add_child(_status)

	var reload_btn := Button.new()
	reload_btn.text = "重置"
	reload_btn.add_theme_font_size_override("font_size", 7)
	reload_btn.pressed.connect(_load)
	bar.add_child(reload_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.add_theme_font_size_override("font_size", 7)
	save_btn.pressed.connect(_save)
	bar.add_child(save_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_editor_vbox = VBoxContainer.new()
	_editor_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_editor_vbox)


func _load():
	if not FileAccess.file_exists(_path):
		_set_status("❌ 文件不存在")
		return
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null: return
	var text : String = f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		_set_status("❌ 解析失败")
		return
	_cfg = data
	_dirty = false
	_refresh()
	_set_status("已重载")


func _refresh():
	for c in _editor_vbox.get_children():
		_editor_vbox.remove_child(c)
		c.queue_free()
	_render_dict(_editor_vbox, _cfg, "", 0)


func _save():
	if _path == "": return
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		_set_status("❌ 保存失败")
		return
	f.store_string(JSON.stringify(_cfg, "  "))
	f.close()
	_dirty = false
	_set_status("✓ 已保存")
	saved.emit(_path)


func _set_status(text : String):
	if _status: _status.text = text


# ---- 递归渲染 ----
func _render_dict(parent : Node, dict : Dictionary, prefix : String, depth : int):
	for key in dict.keys():
		var value = dict[key]
		var path : String = key if prefix == "" else prefix + "." + key
		_render_field(parent, dict, key, value, path, depth)


func _render_field(parent : Node, target_dict : Dictionary, key : String, value, path : String, depth : int):
	var t : int = typeof(value)
	if t == TYPE_DICTIONARY:
		_render_group(parent, value, path, depth)
	elif t == TYPE_ARRAY:
		_render_array(parent, target_dict, key, value, path, depth)
	else:
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
			_render_simple_row_widget(content, "%s[%d]" % [path, i], JSON.stringify(v), func(nt):
				var parsed = JSON.parse_string(nt)
				if parsed != null:
					arr[i] = parsed
					_dirty = true
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
	lb.clip_text = true
	row.add_child(lb)

	for i in range(arr.size()):
		var v = arr[i]
		var t : int = typeof(v)
		if t == TYPE_INT:
			var sp := _make_spin(v, -999999, 999999, 1, 44)
			sp.value_changed.connect(func(nv):
				arr[i] = int(nv); _dirty = true
			)
			row.add_child(sp)
		elif t == TYPE_FLOAT:
			var sp := _make_spin(v, -999.0, 999.0, 0.01, 44)
			sp.value_changed.connect(func(nv):
				arr[i] = float(nv); _dirty = true
			)
			row.add_child(sp)
		else:
			var le := LineEdit.new()
			le.text = str(v)
			le.custom_minimum_size = Vector2(44, 0)
			le.add_theme_font_size_override("font_size", 6)
			le.text_changed.connect(func(t2):
				arr[i] = t2; _dirty = true
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
		sp.value_changed.connect(func(nv): arr[i] = int(nv); _dirty = true)
		row.add_child(sp)
	elif t == TYPE_FLOAT:
		var sp := _make_spin(v, -999.0, 999.0, 0.01, 44)
		sp.value_changed.connect(func(nv): arr[i] = float(nv); _dirty = true)
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
				target_dict[key] = int(nv); _dirty = true
			)
			row.add_child(sp)
		TYPE_FLOAT:
			var step : float = 0.01 if absf(value) < 10.0 else 0.1
			var sp := _make_spin(value, -999.0, 999.0, step, 54)
			sp.value_changed.connect(func(nv):
				target_dict[key] = float(nv); _dirty = true
			)
			row.add_child(sp)
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = value
			cb.add_theme_font_size_override("font_size", 6)
			cb.toggled.connect(func(p):
				target_dict[key] = p; _dirty = true
			)
			row.add_child(cb)
		TYPE_STRING:
			var le := LineEdit.new()
			le.text = str(value)
			le.custom_minimum_size = Vector2(100, 0)
			le.add_theme_font_size_override("font_size", 6)
			le.text_changed.connect(func(t2):
				target_dict[key] = t2; _dirty = true
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
