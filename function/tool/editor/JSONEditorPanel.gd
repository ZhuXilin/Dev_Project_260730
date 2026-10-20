class_name JSONEditorPanel
extends VBoxContainer

# ============================================================
#  JSONEditorPanel — 通用 JSON 编辑器（手动保存）
#  v4.6：增加英文字段名自动转中文；flavor 使用多行文本框
# ============================================================

signal saved(path : String)

const FS_BUTTON : int = 6
const FS_LABEL  : int = 6
const FS_SMALL  : int = 5
const FS_TINY   : int = 5
const FS_PANEL  : int = 7

const COL_BG     : Color = Color(0.08, 0.08, 0.10)
const COL_PANEL  : Color = Color(0.10, 0.10, 0.13)
const COL_VSEP   : Color = Color(0.36, 0.36, 0.42)
const COL_TIP_BG : Color = Color(0.15, 0.15, 0.15, 0.92)

const SPIN_H : int = 13
const ROW_H : int = 13

# ★ 新增：英文字段名 → 中文显示
const FIELD_TRANSLATIONS : Dictionary = {
	"id": "编号",
	"name": "名称",
	"display_name": "显示名",
	"description": "简介",
	"flavor": "叙事",
	"type": "类型",
	"quality": "品质",
	"min_quality": "最低品质",
	"price": "价格",
	"value_min": "最小值",
	"value_max": "最大值",
	"icon": "图标",
	"tags": "标签",
	"stats": "属性",
	"effects": "效果",
	"params": "参数",
	"unlock_type": "解锁类型",
	"tutorial_stage": "教程阶段",
	"soul_cost": "魂消耗",
	"research_time": "研究时长",
	"unlock_cost": "解锁消耗",
	"buy_cost": "购买消耗",
	"tag": "标签",
	"max_level": "最大等级",
	"attack_per_level": "每级攻击",
	"defense_per_level": "每级防御",
	"attack_percent": "攻击百分比",
	"damage_reduction": "减伤",
	"counter_bonus": "反击加成",
	"soul_fire_gain": "魂火获取",
	"heal_percent": "治疗百分比",
	"effect": "效果代码",
}

var _path : String = ""
var _cfg : Dictionary = {}
var _editor_vbox : VBoxContainer = null
var _status : Label = null
var _dirty : bool = false


func setup(path : String, title : String = ""):
	_path = path
	_apply_compact_theme()
	if title != "":
		var lb := Label.new()
		lb.text = title
		lb.add_theme_font_size_override("font_size", FS_PANEL)
		lb.modulate = Color(0.7, 0.8, 1.0)
		add_child(lb)
	_build_ui()
	_load()


# ============================================================
#  全局主题
# ============================================================
func _apply_compact_theme():
	var t := Theme.new()

	# ---- Button ----
	t.set_font_size("font_size", "Button", FS_BUTTON)
	var btn_empty := StyleBoxEmpty.new()
	btn_empty.content_margin_left = 1
	btn_empty.content_margin_right = 1
	t.set_stylebox("normal", "Button", btn_empty)
	t.set_stylebox("hover", "Button", btn_empty)
	t.set_stylebox("pressed", "Button", btn_empty)
	t.set_stylebox("focus", "Button", btn_empty)
	t.set_stylebox("disabled", "Button", btn_empty)

	# ---- Label ----
	t.set_font_size("font_size", "Label", FS_LABEL)
	var label_empty := StyleBoxEmpty.new()
	t.set_stylebox("normal", "Label", label_empty)

	# ---- LineEdit / TextEdit ----
	t.set_font_size("font_size", "LineEdit", FS_BUTTON)
	t.set_font_size("font_size", "TextEdit", FS_BUTTON)
	var le_empty := StyleBoxEmpty.new()
	le_empty.content_margin_left = 2
	le_empty.content_margin_right = 2
	t.set_stylebox("normal", "LineEdit", le_empty)
	t.set_stylebox("focus", "LineEdit", le_empty)
	t.set_stylebox("read_only", "LineEdit", le_empty)

	# ---- SpinBox ----
	t.set_font_size("font_size", "SpinBox", FS_BUTTON)

	# ---- OptionButton + 小箭头 ----
	t.set_font_size("font_size", "OptionButton", FS_BUTTON)
	var arrow_img := Image.create(7, 4, false, Image.FORMAT_RGBA8)
	arrow_img.fill(Color(0, 0, 0, 0))
	for y in range(4):
		for x in range(7):
			var half : float = float(y) * 0.5
			if float(x) >= half and float(x) <= 6.0 - half:
				arrow_img.set_pixel(x, y, Color(0.72, 0.72, 0.78, 1.0))
	var arrow_tex := ImageTexture.create_from_image(arrow_img)
	t.set_icon("arrow", "OptionButton", arrow_tex)
	t.set_constant("arrow_margin", "OptionButton", 2)

	# ---- CheckBox ----
	t.set_font_size("font_size", "CheckBox", FS_LABEL)

	# ---- PopupMenu ----
	t.set_font_size("font_size", "PopupMenu", FS_SMALL)
	t.set_constant("item_start_padding", "PopupMenu", 3)
	t.set_constant("item_end_padding", "PopupMenu", 3)
	t.set_constant("v_separation", "PopupMenu", 0)
	t.set_constant("h_separation", "PopupMenu", 0)
	t.set_constant("icon_max_width", "PopupMenu", 6)

	var popup_panel := StyleBoxFlat.new()
	popup_panel.bg_color = Color(0.13, 0.13, 0.16, 1)
	popup_panel.border_color = Color(0.28, 0.28, 0.34, 1)
	popup_panel.border_width_left = 1
	popup_panel.border_width_right = 1
	popup_panel.border_width_top = 1
	popup_panel.border_width_bottom = 1
	popup_panel.content_margin_left = 2
	popup_panel.content_margin_right = 2
	popup_panel.content_margin_top = 2
	popup_panel.content_margin_bottom = 2
	t.set_stylebox("panel", "PopupMenu", popup_panel)

	# ---- Tooltip ----
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)
	t.set_font_size("font_size", "TooltipPanel", FS_SMALL)
	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = COL_TIP_BG
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

	# ---- 细滚动条 ----
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.08, 0.10, 1)
	var grab_off := StyleBoxFlat.new()
	grab_off.bg_color = Color(0.32, 0.32, 0.38, 1)
	grab_off.corner_radius_top_left = 2
	grab_off.corner_radius_top_right = 2
	grab_off.corner_radius_bottom_left = 2
	grab_off.corner_radius_bottom_right = 2
	var grab_hl := StyleBoxFlat.new()
	grab_hl.bg_color = Color(0.55, 0.55, 0.65, 1)
	grab_hl.corner_radius_top_left = 2
	grab_hl.corner_radius_top_right = 2
	grab_hl.corner_radius_bottom_left = 2
	grab_hl.corner_radius_bottom_right = 2

	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", grab_off)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hl)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hl)
	t.set_constant("minimum_grab_size", "VScrollBar", 6)
	t.set_constant("scroll_width", "VScrollBar", 4)

	t.set_stylebox("scroll", "HScrollBar", track)
	t.set_stylebox("scroll_focus", "HScrollBar", track)
	t.set_stylebox("grabber", "HScrollBar", grab_off)
	t.set_stylebox("grabber_highlight", "HScrollBar", grab_hl)
	t.set_stylebox("grabber_pressed", "HScrollBar", grab_hl)
	t.set_constant("minimum_grab_size", "HScrollBar", 6)
	t.set_constant("scroll_height", "HScrollBar", 4)

	# ---- VSeparator ----
	var sep_sb := StyleBoxLine.new()
	sep_sb.color = COL_VSEP
	sep_sb.thickness = 1
	sep_sb.vertical = true
	t.set_stylebox("separator", "VSeparator", sep_sb)

	theme = t


# ============================================================
#  UI 构建
# ============================================================
func _build_ui():
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	add_child(bar)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_status = Label.new()
	_status.modulate = Color(0.7, 0.9, 0.7)
	bar.add_child(_status)

	var reload_btn := Button.new()
	reload_btn.text = "重置"
	reload_btn.pressed.connect(_load)
	bar.add_child(reload_btn)

	var save_btn := Button.new()
	save_btn.text = "保存"
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


# ============================================================
#  加载 / 保存
# ============================================================
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


# ============================================================
#  递归渲染
# ============================================================
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
	# ★ 汉化显示
	var display_path = FIELD_TRANSLATIONS.get(path, path)
	title.text = "▼ " + (display_path if path != "" else "根目录")
	title.add_theme_font_size_override("font_size", FS_PANEL)
	title.modulate = Color(0.85, 0.85, 1.0)
	title.tooltip_text = path # 悬停显示原英文路径
	vb.add_child(title)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	vb.add_child(content)

	title.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			content.visible = not content.visible
			title.text = ("▼ " if content.visible else "▶ ") + (display_path if path != "" else "根目录")
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
	var display_path = FIELD_TRANSLATIONS.get(path, path)
	title.text = "▼ %s [%d]" % [display_path, arr.size()]
	title.add_theme_font_size_override("font_size", FS_PANEL)
	title.modulate = Color(0.85, 0.85, 1.0)
	title.tooltip_text = path
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
	var display_path = FIELD_TRANSLATIONS.get(path, path)
	title.text = "▼ " + display_path
	title.add_theme_font_size_override("font_size", FS_SMALL)
	title.modulate = Color(0.8, 0.8, 0.95)
	title.tooltip_text = path
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
	var display_path = FIELD_TRANSLATIONS.get(path, path)
	lb.text = display_path
	lb.tooltip_text = path
	lb.custom_minimum_size = Vector2(110, 0)
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
			le.custom_minimum_size = Vector2(44, ROW_H)
			le.text_changed.connect(func(t2):
				arr[i] = t2; _dirty = true
			)
			row.add_child(le)


func _render_array_index_editor(parent : Node, arr : Array, i : int, path : String):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	var display_path = FIELD_TRANSLATIONS.get(path, path)
	lb.text = display_path
	lb.tooltip_text = path
	lb.custom_minimum_size = Vector2(110, 0)
	lb.clip_text = true
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
		le.custom_minimum_size = Vector2(44, ROW_H)
		row.add_child(le)


func _render_simple_row(parent : Node, target_dict : Dictionary, key : String, value, path : String):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	# ★ 汉化显示
	var display_key = FIELD_TRANSLATIONS.get(key, key)
	lb.text = display_key
	lb.tooltip_text = path # 悬停仍显示原始路径，方便查错
	lb.custom_minimum_size = Vector2(110, 0)
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
			cb.toggled.connect(func(p):
				target_dict[key] = p; _dirty = true
			)
			row.add_child(cb)
		TYPE_STRING:
			# ★ 如果是 flavor（叙事），使用多行 TextEdit，并修复左侧 Label 被挤压的问题
			if key == "flavor":
				var te := TextEdit.new()
				te.text = str(value)
				te.custom_minimum_size = Vector2(200, 64) # 加大高度
				te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				te.add_theme_font_size_override("font_size", FS_BUTTON)
				te.text_changed.connect(func():
					target_dict[key] = te.text
					_dirty = true
				)
				row.add_child(te)
			else:
				var le := LineEdit.new()
				le.text = str(value)
				le.custom_minimum_size = Vector2(100, ROW_H)
				le.text_changed.connect(func(t2):
					target_dict[key] = t2; _dirty = true
				)
				row.add_child(le)
		_:
			var lb2 := Label.new()
			lb2.text = str(value)
			lb2.modulate = Color(0.6, 0.6, 0.6)
			row.add_child(lb2)


func _render_simple_row_widget(parent : Node, label : String, initial : String, on_change : Callable):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)

	var lb := Label.new()
	var display_label = FIELD_TRANSLATIONS.get(label, label)
	lb.text = display_label
	lb.tooltip_text = label
	lb.custom_minimum_size = Vector2(110, 0)
	row.add_child(lb)

	var le := LineEdit.new()
	le.text = initial
	le.custom_minimum_size = Vector2(140, ROW_H)
	le.text_submitted.connect(on_change)
	row.add_child(le)


# ============================================================
#  SpinBox 工厂 + 紧凑箭头
# ============================================================
func _make_spin(value, min_v : float, max_v : float, step : float, w : float) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step
	sp.value = value
	sp.custom_minimum_size = Vector2(w, SPIN_H)
	sp.ready.connect(func(): _setup_spin(sp), CONNECT_ONE_SHOT)
	return sp


func _setup_spin(sp : SpinBox):
	if not is_instance_valid(sp): return
	var le := sp.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", FS_BUTTON)
		le.select_all_on_focus = true
	var btns : Array[Node] = sp.find_children("*", "Button", true, false)
	for b in btns:
		_compact_spin_arrow_button(b as Button)


func _compact_spin_arrow_button(btn : Button):
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
