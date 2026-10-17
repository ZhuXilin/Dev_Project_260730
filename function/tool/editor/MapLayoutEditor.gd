@tool
extends Control

# ============================================================
#  MapLayoutEditor — 地图布局可视化编辑器
#  v4.2 第 12 批：新增 undo/redo（Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y）
# ============================================================

const LAYER_HEIGHT : float = 28.0
const NODE_W : float = 40.0
const NODE_H : float = 14.0
const NODE_FONT_SIZE : int = 6
const CANVAS_PADDING_TOP : float = 20.0
const CANVAS_PADDING_BOTTOM : float = 12.0
const LAYOUT_DIR : String = "res://content/scenes/levels/maplayout/"
const BAKE_WIDTH : float = 400.0
const RELIC_DATA_PATH : String = "res://content/data/relic_data.json"

const COMBAT_NODE_TYPES : Array = [
	MapNode.NodeType.START,
	MapNode.NodeType.NORMAL,
	MapNode.NodeType.ELITE,
	MapNode.NodeType.BOSS,
]

# ★ 第十二批：undo/redo 栈
const MAX_UNDO : int = 30

enum Tool { EDIT, LINK }

# ============================================================
#  状态
# ============================================================
var _layout : MapLayout = null
var _current_day : int = 1
var _variant_idx : int = 0
var _current_tool : Tool = Tool.EDIT
var _layout_path : String = ""

var _selected_link : int = -1
var _dragging_idx : int = -1
var _mouse_pos : Vector2 = Vector2.ZERO

var _canvas : Control = null
var _scroll : ScrollContainer = null
var _popup_layer : Control = null

var _levellist : LevelListResource = null
var _levellist_path : String = ""
var _in_test_mode : bool = false
var _test_map_assignment : Dictionary = {}
var _levellist_btn : Button = null
var _test_btn : Button = null

var _day_buttons : Array[Button] = []
var _tool_buttons : Array[Button] = []
var _variant_label : Label = null
var _hint_label : Label = null

var _popup_confirm_callback : Callable = Callable()

var _relic_data_cache : Dictionary = {}

# ★ 第十二批：undo/redo 栈
var _undo_stack : Array = []   # [{day, variant_idx, nodes: Array[MapLayoutNode], tool, selected_link}]
var _redo_stack : Array = []


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_ensure_dir()
	_apply_tooltip_theme()
	_build_ui()
	call_deferred("_show_startup_menu")


func _ensure_dir():
	if not DirAccess.dir_exists_absolute(LAYOUT_DIR):
		DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)


func _apply_tooltip_theme():
	var t := Theme.new()
	t.set_font_size("font_size", "TooltipLabel", 8)
	t.set_font_size("font_size", "TooltipPanel", 8)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_top = 0
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	t.set_stylebox("panel", "TooltipPanel", sb)

	theme = t


# ============================================================
#  ★ 第十二批：undo / redo
# ============================================================
func _snapshot_current() -> Dictionary:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return {}
	var nodes_copy : Array = []
	for n in day_layout.nodes:
		var cp := MapLayoutNode.new()
		cp.node_type = n.node_type
		cp.random_pool = n.random_pool.duplicate()
		cp.position = n.position
		cp.layer = n.layer
		cp.connects_to = n.connects_to.duplicate()
		cp.unlock_relics = n.unlock_relics.duplicate()
		cp.unlock_units = n.unlock_units.duplicate()
		nodes_copy.append(cp)
	return {
		"day": _current_day,
		"variant_idx": _variant_idx,
		"nodes": nodes_copy,
		"tool": _current_tool,
		"selected_link": _selected_link,
	}


func _push_undo():
	var snap : Dictionary = _snapshot_current()
	if snap.is_empty():
		return
	_undo_stack.append(snap)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _undo():
	if _undo_stack.is_empty():
		print("[MapLayoutEditor] 无可撤销")
		return
	var cur : Dictionary = _snapshot_current()
	if not cur.is_empty():
		_redo_stack.append(cur)
	var snap : Dictionary = _undo_stack.pop_back()
	_apply_snapshot(snap)
	print("[MapLayoutEditor] ↶ 撤销（剩余 %d 步）" % _undo_stack.size())


func _redo():
	if _redo_stack.is_empty():
		print("[MapLayoutEditor] 无可重做")
		return
	var cur : Dictionary = _snapshot_current()
	if not cur.is_empty():
		_undo_stack.append(cur)
	var snap : Dictionary = _redo_stack.pop_back()
	_apply_snapshot(snap)
	print("[MapLayoutEditor] ↷ 重做（剩余 %d 步）" % _redo_stack.size())


func _apply_snapshot(snap : Dictionary):
	var day : int = int(snap.get("day", 1))
	var vi : int = int(snap.get("variant_idx", 0))
	var nodes : Array = snap.get("nodes", [])
	_current_day = day
	_variant_idx = vi
	var arr : Array = _get_variant_array_for_day(day)
	while arr.size() <= vi:
		arr.append(MapLayoutDay.new())
	var dl : MapLayoutDay = arr[vi]
	dl.nodes.clear()
	for n in nodes:
		dl.nodes.append(n)
	_current_tool = snap.get("tool", Tool.EDIT) as Tool
	_selected_link = int(snap.get("selected_link", -1))
	_dragging_idx = -1
	_update_all_labels()
	_refresh_canvas_size()
	if _canvas:
		_canvas.queue_redraw()


func _get_variant_array_for_day(day : int) -> Array:
	if _layout == null: return []
	match day:
		1: return _layout.day1_variants
		2: return _layout.day2_variants
		3: return _layout.day3_variants
	return []


func _clear_history():
	_undo_stack.clear()
	_redo_stack.clear()


# ============================================================
#  快捷键
# ============================================================
func _unhandled_input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	# ★ 第十二批：undo/redo 优先处理
	if event.ctrl_pressed and not event.alt_pressed:
		match event.keycode:
			KEY_Z:
				if event.shift_pressed:
					_redo()
				else:
					_undo()
				get_viewport().set_input_as_handled()
				return
			KEY_Y:
				_redo()
				get_viewport().set_input_as_handled()
				return
			KEY_S:
				_on_save()
				get_viewport().set_input_as_handled()
				return

	if _popup_layer == null or not is_instance_valid(_popup_layer):
		return
	if event.keycode == KEY_ESCAPE:
		_close_popup()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if _popup_confirm_callback.is_valid():
			_popup_confirm_callback.call()
		get_viewport().set_input_as_handled()


# ============================================================
#  启动菜单
# ============================================================
func _show_startup_menu():
	var menu := PopupMenu.new()
	menu.add_item("＋ 新建文件...", 0)
	menu.add_separator()

	var files : Array = _list_layout_files()
	if files.is_empty():
		menu.add_item("（目录为空）", -1)
		menu.set_item_disabled(menu.item_count - 1, true)
	else:
		for i in range(files.size()):
			menu.add_item(files[i], i + 1)

	menu.max_size = Vector2i(220, 160)
	add_child(menu)
	menu.id_pressed.connect(func(id):
		menu.queue_free()
		if id == 0:
			_prompt_new_file()
		elif id >= 1:
			var idx : int = id - 1
			if idx >= 0 and idx < files.size():
				_load_file(LAYOUT_DIR + files[idx])
	)
	menu.popup_centered()


# ============================================================
#  文件列表 / 加载 / 新建 / 保存
# ============================================================
func _list_layout_files() -> Array:
	var files : Array = []
	var dir := DirAccess.open(LAYOUT_DIR)
	if dir == null: return files
	dir.list_dir_begin()
	var fname : String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _load_file(path: String):
	_layout = load(path)
	if _layout == null:
		push_error("加载失败: " + path)
		return
	_layout_path = path
	_current_day = 1
	_variant_idx = 0
	_ensure_variant_exists()
	_clear_history()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()
	print("[MapLayoutEditor] 已加载: ", path)


func _prompt_new_file():
	_show_text_input_popup("新建文件", "文件名（不含 .tres）:", "MapLayout_New", func(file_name):
		if file_name == "":
			return
		if file_name.ends_with(".tres"):
			file_name = file_name.substr(0, file_name.length() - 5)
		var path : String = LAYOUT_DIR + file_name + ".tres"
		if ResourceLoader.exists(path):
			push_warning("文件已存在: " + path)
			return
		_layout = MapLayout.new()
		_layout.day1_variants.append(MapLayoutDay.new())
		_layout.day2_variants.append(MapLayoutDay.new())
		_layout.day3_variants.append(MapLayoutDay.new())
		_layout_path = path
		_current_day = 1
		_variant_idx = 0
		_ensure_variant_exists()
		_clear_history()
		_update_all_labels()
		_refresh_canvas_size()
		_canvas.queue_redraw()
		_save_to(path)
	)


func _save_to(path: String):
	_bake_positions()
	var err := ResourceSaver.save(_layout, path)
	if err == OK:
		_layout_path = path
		_update_all_labels()
		print("[MapLayoutEditor] 已保存: ", path)
	else:
		push_error("保存失败: %d" % err)


func _on_save():
	if _layout == null:
		push_warning("没有正在编辑的文件")
		return
	if _layout_path == "":
		_prompt_new_file()
		return
	_bake_positions()
	_save_to(_layout_path)


func _on_new():
	_prompt_new_file()


func _on_open():
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.add_filter("*.tres", "Tres 文件")
	fd.use_native_dialog = true
	fd.current_dir = LAYOUT_DIR
	fd.title = "打开地图布局"

	fd.file_selected.connect(func(path):
		_load_file(path)
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))


# ============================================================
#  LevelList + 测试
# ============================================================
func _on_pick_levellist():
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.add_filter("*.tres", "Tres 文件")
	fd.use_native_dialog = true
	fd.current_dir = "res://content/scenes/levels/levellists/"
	fd.title = "选择 LevelList 文件"
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res == null:
			push_warning("加载失败: " + path)
			fd.queue_free()
			return
		if not (res is LevelListResource):
			push_warning("选中的不是 LevelList 资源: " + path)
			Globals.show_confirm(
				self,
				"选中的文件不是关卡池（LevelList）\n请选择 levellists/ 目录下的 .tres 文件",
				"确定", "", func(): pass, func(): pass, false
			)
			fd.queue_free()
			return
		_levellist = res
		_levellist_path = path
		_update_all_labels()
		print("[MapLayoutEditor] 已加载 LevelList: ", path)
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(500, 400))


func _on_test_toggle():
	_in_test_mode = not _in_test_mode
	_test_btn.button_pressed = _in_test_mode

	if _in_test_mode:
		if _levellist == null:
			push_warning("请先选择 LevelList 文件")
			_in_test_mode = false
			_test_btn.button_pressed = false
			return
		_generate_test_map()
	else:
		_test_map_assignment.clear()

	_update_all_labels()
	_canvas.queue_redraw()


func _generate_test_map():
	_test_map_assignment.clear()
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return

	var pools : Dictionary = {}
	if _levellist and _levellist.levels:
		for m in _levellist.levels:
			if m == null: continue
			var t : int = m.node_type
			if not pools.has(t):
				pools[t] = []
			pools[t].append(m)

	var by_layer : Dictionary = {}
	for i in range(day_layout.nodes.size()):
		var ln : MapLayoutNode = day_layout.nodes[i]
		if not by_layer.has(ln.layer):
			by_layer[ln.layer] = []
		by_layer[ln.layer].append(i)

	for layer_key in by_layer:
		var indices : Array = by_layer[layer_key]

		var used_types : Dictionary = {}
		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			if ln.random_pool.is_empty():
				used_types[ln.node_type] = true

		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			var resolved : int = ln.node_type
			if not ln.random_pool.is_empty():
				var available : Array = []
				for t in ln.random_pool:
					if not used_types.has(t):
						available.append(t)
				if available.is_empty():
					available = ln.random_pool.duplicate()
				resolved = available[randi() % available.size()]
				used_types[resolved] = true

			var pool : Array = pools.get(resolved, [])
			if not pool.is_empty():
				var pick : MapData = pool[randi() % pool.size()]
				if pick.map_name != "":
					_test_map_assignment[ln] = pick.map_name
					continue

			_test_map_assignment[ln] = MapConst.get_node_display_name(resolved)


# ============================================================
#  遗物数据
# ============================================================
func _load_relic_data_for_editor() -> Dictionary:
	if not FileAccess.file_exists(RELIC_DATA_PATH):
		push_warning("[MapLayoutEditor] 遗物数据文件不存在: " + RELIC_DATA_PATH)
		return {}
	var file := FileAccess.open(RELIC_DATA_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return {}
	return data


func _get_relic_data_cached() -> Dictionary:
	if _relic_data_cache.is_empty():
		_relic_data_cache = _load_relic_data_for_editor()
	return _relic_data_cache


func _relic_display_name(relic_id: String) -> String:
	var d : Dictionary = _get_relic_data_cached()
	if d.has(relic_id):
		return d[relic_id].get("name", relic_id)
	return relic_id


func _node_can_unlock_relics(node: MapLayoutNode) -> bool:
	if not node.random_pool.is_empty():
		for t in node.random_pool:
			if t in COMBAT_NODE_TYPES:
				return true
		return false
	return node.node_type in COMBAT_NODE_TYPES


# ============================================================
#  嵌入式 Popup — 文本输入
# ============================================================
func _show_text_input_popup(title: String, label_text: String, default_text: String, on_ok: Callable):
	_close_popup()
	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_popup_layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -100
	panel.offset_right = 100
	panel.offset_top = 40
	panel.offset_bottom = -40
	_popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var title_lb := Label.new()
	title_lb.text = title
	title_lb.add_theme_font_size_override("font_size", 9)
	title_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lb)

	var lb := Label.new()
	lb.text = label_text
	lb.add_theme_font_size_override("font_size", 8)
	vbox.add_child(lb)

	var le := LineEdit.new()
	le.text = default_text
	le.add_theme_font_size_override("font_size", 8)
	le.custom_minimum_size = Vector2(0, 14)
	le.select_all()
	vbox.add_child(le)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vbox.add_child(btns)

	var ok := Button.new()
	ok.text = "确定"
	ok.add_theme_font_size_override("font_size", 8)
	ok.custom_minimum_size = Vector2(50, 16)
	btns.add_child(ok)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 8)
	cancel.custom_minimum_size = Vector2(50, 16)
	cancel.pressed.connect(_close_popup)
	btns.add_child(cancel)

	var confirm_action := func():
		var t : String = le.text.strip_edges()
		_close_popup()
		on_ok.call(t)
	ok.pressed.connect(confirm_action)
	_popup_confirm_callback = confirm_action

	le.text_submitted.connect(func(t):
		_close_popup()
		on_ok.call(t.strip_edges())
	)

	le.grab_focus()


# ============================================================
#  嵌入式 Popup — 节点配置
# ============================================================
func _show_type_picker_popup(node_idx: int):
	_close_popup()
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	if node_idx < 0 or node_idx >= day_layout.nodes.size(): return

	var node : MapLayoutNode = day_layout.nodes[node_idx]

	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_popup_layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(event):
		if not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_close_popup()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _popup_confirm_callback.is_valid():
				_popup_confirm_callback.call()
			else:
				_close_popup()
	)
	_popup_layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = 8
	panel.offset_bottom = -8
	_popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var title_lb := Label.new()
	title_lb.text = "节点配置"
	title_lb.add_theme_font_size_override("font_size", 8)
	title_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lb)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_theme_constant_override("separation", 8)
	vbox.add_child(main)

	# ================= 左列：节点类型 =================
	var left_box := VBoxContainer.new()
	left_box.custom_minimum_size = Vector2(90, 0)
	left_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_theme_constant_override("separation", 2)

	var left_title := Label.new()
	left_title.text = "类型"
	left_title.add_theme_font_size_override("font_size", 7)
	left_box.add_child(left_title)

	var type_scroll := ScrollContainer.new()
	type_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	type_scroll.custom_minimum_size = Vector2(0, 120)
	type_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(type_scroll)

	var type_list := VBoxContainer.new()
	type_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_list.add_theme_constant_override("separation", 0)
	type_scroll.add_child(type_list)

	var types := [
		[MapNode.NodeType.START, "START"],
		[MapNode.NodeType.NORMAL, "NORMAL"],
		[MapNode.NodeType.ELITE, "ELITE"],
		[MapNode.NodeType.TREASURE, "TREASURE"],
		[MapNode.NodeType.BOSS, "BOSS"],
		[MapNode.NodeType.FORGE, "FORGE"],
		[MapNode.NodeType.CHAPEL, "CHAPEL"],
	]

	var is_in_pool : bool = not node.random_pool.is_empty()
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	empty.content_margin_left = 0
	empty.content_margin_right = 0

	var checks : Array[Button] = []
	for t in types:
		var initial_pressed : bool = false
		if is_in_pool:
			initial_pressed = node.random_pool.has(t[0])
		else:
			initial_pressed = (t[0] == node.node_type)

		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_pressed = initial_pressed
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = ("☑ " if initial_pressed else "☐ ") + t[1]
		btn.add_theme_font_size_override("font_size", 7)
		btn.add_theme_stylebox_override("normal", empty)
		btn.add_theme_stylebox_override("hover", empty)
		btn.add_theme_stylebox_override("pressed", empty)
		btn.add_theme_stylebox_override("focus", empty)
		btn.add_theme_stylebox_override("disabled", empty)
		btn.custom_minimum_size = Vector2(0, 10)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.set_meta("type", t[0])
		var label_text : String = t[1]
		btn.toggled.connect(func(pressed: bool):
			btn.text = ("☑ " if pressed else "☐ ") + label_text
		)
		type_list.add_child(btn)
		checks.append(btn)

	main.add_child(left_box)

	# ================= 右列：解锁遗物 =================
	var can_unlock : bool = _node_can_unlock_relics(node)

	var right_box := VBoxContainer.new()
	right_box.custom_minimum_size = Vector2(90, 0)
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 2)

	var right_title := Label.new()
	right_title.text = "解锁遗物"
	right_title.add_theme_font_size_override("font_size", 7)
	right_box.add_child(right_title)

	var relic_checks : Array[Button] = []

	if not can_unlock:
		var disabled_hint := Label.new()
		disabled_hint.text = "（非战斗节点\n不支持）"
		disabled_hint.add_theme_font_size_override("font_size", 7)
		disabled_hint.modulate = Color(0.6, 0.6, 0.6)
		disabled_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		disabled_hint.custom_minimum_size = Vector2(0, 60)
		disabled_hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		right_box.add_child(disabled_hint)
	else:
		var relic_scroll := ScrollContainer.new()
		relic_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		relic_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		relic_scroll.custom_minimum_size = Vector2(0, 120)
		relic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		right_box.add_child(relic_scroll)

		var relic_list := VBoxContainer.new()
		relic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		relic_list.add_theme_constant_override("separation", 0)
		relic_scroll.add_child(relic_list)

		var all_relics : Dictionary = _get_relic_data_cached()
		var current_relics : Array = node.unlock_relics

		for rid in all_relics:
			var rd : Dictionary = all_relics[rid]
			var rname : String = rd.get("name", rid)
			var is_checked : bool = rid in current_relics

			var btn := Button.new()
			btn.toggle_mode = true
			btn.button_pressed = is_checked
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.text = ("☑ " if is_checked else "☐ ") + rname
			btn.add_theme_font_size_override("font_size", 7)
			btn.add_theme_stylebox_override("normal", empty)
			btn.add_theme_stylebox_override("hover", empty)
			btn.add_theme_stylebox_override("pressed", empty)
			btn.add_theme_stylebox_override("focus", empty)
			btn.add_theme_stylebox_override("disabled", empty)
			btn.custom_minimum_size = Vector2(0, 10)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.set_meta("relic_id", rid)
			var relic_label : String = rname
			btn.toggled.connect(func(pressed: bool):
				btn.text = ("☑ " if pressed else "☐ ") + relic_label
			)
			relic_list.add_child(btn)
			relic_checks.append(btn)

		if relic_checks.is_empty():
			var hint := Label.new()
			hint.text = "（无遗物）"
			hint.add_theme_font_size_override("font_size", 7)
			hint.modulate = Color(0.6, 0.6, 0.6)
			relic_list.add_child(hint)

		var valid_relic_ids : Dictionary = {}
		for rid in all_relics: valid_relic_ids[rid] = true
		for rid in current_relics:
			if not valid_relic_ids.has(rid):
				var orphan_lb := Label.new()
				orphan_lb.text = "⚠ 孤儿：" + rid
				orphan_lb.add_theme_font_size_override("font_size", 7)
				orphan_lb.modulate = Color(1.0, 0.5, 0.5)
				orphan_lb.tooltip_text = "该 id 在 relic_data.json 里不存在"
				relic_list.add_child(orphan_lb)

	main.add_child(right_box)

	# ================= 第三列：解锁单位 =================
	var unit_box := VBoxContainer.new()
	unit_box.custom_minimum_size = Vector2(90, 0)
	unit_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_box.add_theme_constant_override("separation", 2)

	var unit_title := Label.new()
	unit_title.text = "解锁单位"
	unit_title.add_theme_font_size_override("font_size", 7)
	unit_box.add_child(unit_title)

	var unit_checks : Array[Button] = []

	if not can_unlock:
		var unit_hint := Label.new()
		unit_hint.text = "（非战斗节点\n不支持）"
		unit_hint.add_theme_font_size_override("font_size", 7)
		unit_hint.modulate = Color(0.6, 0.6, 0.6)
		unit_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unit_hint.custom_minimum_size = Vector2(0, 60)
		unit_hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		unit_box.add_child(unit_hint)
	else:
		var unit_scroll := ScrollContainer.new()
		unit_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		unit_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_scroll.custom_minimum_size = Vector2(0, 120)
		unit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		unit_box.add_child(unit_scroll)

		var unit_list := VBoxContainer.new()
		unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_list.add_theme_constant_override("separation", 0)
		unit_scroll.add_child(unit_list)

		var all_unit_ids : Array = Globals.get_map_unlock_units()
		var current_units : Array = node.unlock_units

		for uid in all_unit_ids:
			var udisplay : String = UnitDataManager.get_display_name(uid)
			var is_checked_u : bool = uid in current_units

			var btn := Button.new()
			btn.toggle_mode = true
			btn.button_pressed = is_checked_u
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.text = ("☑ " if is_checked_u else "☐ ") + udisplay
			btn.add_theme_font_size_override("font_size", 7)
			btn.add_theme_stylebox_override("normal", empty)
			btn.add_theme_stylebox_override("hover", empty)
			btn.add_theme_stylebox_override("pressed", empty)
			btn.add_theme_stylebox_override("focus", empty)
			btn.add_theme_stylebox_override("disabled", empty)
			btn.custom_minimum_size = Vector2(0, 10)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.set_meta("unit_id", uid)
			var unit_label : String = udisplay
			btn.toggled.connect(func(pressed: bool):
				btn.text = ("☑ " if pressed else "☐ ") + unit_label
			)
			unit_list.add_child(btn)
			unit_checks.append(btn)

		if unit_checks.is_empty():
			var hint2 := Label.new()
			hint2.text = "（无单位）"
			hint2.add_theme_font_size_override("font_size", 7)
			hint2.modulate = Color(0.6, 0.6, 0.6)
			unit_list.add_child(hint2)

		var valid_unit_ids : Dictionary = {}
		for uid in all_unit_ids: valid_unit_ids[uid] = true
		for uid in current_units:
			if not valid_unit_ids.has(uid):
				# ★ 孤儿：允许取消（作为 checkbox），避免无法清理
				var display_o : String = UnitDataManager.get_display_name(uid)
				var btn_o := Button.new()
				btn_o.toggle_mode = true
				btn_o.button_pressed = true
				btn_o.alignment = HORIZONTAL_ALIGNMENT_LEFT
				btn_o.text = "☑ ⚠ " + display_o + " (" + uid + ")"
				btn_o.add_theme_font_size_override("font_size", 7)
				btn_o.add_theme_stylebox_override("normal", empty)
				btn_o.add_theme_stylebox_override("hover", empty)
				btn_o.add_theme_stylebox_override("pressed", empty)
				btn_o.add_theme_stylebox_override("focus", empty)
				btn_o.add_theme_stylebox_override("disabled", empty)
				btn_o.custom_minimum_size = Vector2(0, 10)
				btn_o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn_o.set_meta("unit_id", uid)
				btn_o.tooltip_text = "该单位不在 map_unlock_units 里（孤儿）\n取消勾选可移除"
				btn_o.toggled.connect(func(pressed: bool):
					btn_o.text = ("☑ ⚠ " if pressed else "☐ ⚠ ") + display_o + " (" + uid + ")"
				)
				unit_list.add_child(btn_o)
				unit_checks.append(btn_o)

	main.add_child(unit_box)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vbox.add_child(btns)

	var ok := Button.new()
	ok.text = "确定"
	ok.add_theme_font_size_override("font_size", 8)
	ok.custom_minimum_size = Vector2(50, 16)
	btns.add_child(ok)

	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 8)
	cancel.custom_minimum_size = Vector2(50, 16)
	cancel.pressed.connect(_close_popup)
	btns.add_child(cancel)

	var confirm_action := func():
		# ★ 第十二批：节点配置改动 → 先 push undo
		_push_undo()

		var selected : Array = []
		for btn in checks:
			if btn.button_pressed:
				selected.append(btn.get_meta("type"))
		if selected.size() == 1:
			node.node_type = selected[0]
			node.random_pool.clear()
		elif selected.size() > 1:
			var typed_pool : Array[MapNode.NodeType] = []
			for p in selected:
				typed_pool.append(p as MapNode.NodeType)
			node.random_pool = typed_pool
			node.node_type = typed_pool[0]

		if can_unlock:
			var new_relics : Array[String] = []
			for btn in relic_checks:
				if btn.button_pressed:
					var rid : String = btn.get_meta("relic_id", "")
					if rid != "":
						new_relics.append(rid)
			node.unlock_relics = new_relics
		else:
			node.unlock_relics.clear()

		if can_unlock:
			var new_units : Array[String] = []
			for btn in unit_checks:
				if btn.button_pressed:
					var uid : String = btn.get_meta("unit_id", "")
					if uid != "":
						new_units.append(uid)
			node.unlock_units = new_units
		else:
			node.unlock_units.clear()

		_canvas.queue_redraw()
		_close_popup()

	ok.pressed.connect(confirm_action)
	_popup_confirm_callback = confirm_action


func _close_popup():
	if _popup_layer and is_instance_valid(_popup_layer):
		_popup_layer.queue_free()
		_popup_layer = null
	_popup_confirm_callback = Callable()


# ============================================================
#  UI 构建
# ============================================================
func _make_btn(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 6)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", empty)
	return b


func _build_ui():
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 2
	top.offset_right = -2
	top.offset_top = 2
	top.offset_bottom = 22
	top.add_theme_constant_override("separation", 1)
	add_child(top)

	for d in [1, 2, 3]:
		var b := _make_btn("D%d" % d, "Day %d" % d)
		b.add_theme_font_size_override("font_size", 7)
		b.toggle_mode = true
		b.pressed.connect(_on_day_clicked.bind(d))
		top.add_child(b)
		_day_buttons.append(b)

	top.add_child(VSeparator.new())

	var prev_btn := _make_btn("◀", "上一个变体")
	prev_btn.add_theme_font_size_override("font_size", 7)
	prev_btn.pressed.connect(_on_variant_prev)
	top.add_child(prev_btn)

	_variant_label = Label.new()
	_variant_label.text = "1/1"
	_variant_label.custom_minimum_size = Vector2(24, 0)
	_variant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_variant_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_variant_label.add_theme_font_size_override("font_size", 7)
	top.add_child(_variant_label)

	var next_btn := _make_btn("▶", "下一个变体")
	next_btn.add_theme_font_size_override("font_size", 7)
	next_btn.pressed.connect(_on_variant_next)
	top.add_child(next_btn)

	var add_var_btn := _make_btn("+", "新建变体")
	add_var_btn.add_theme_font_size_override("font_size", 7)
	add_var_btn.pressed.connect(_on_variant_add)
	top.add_child(add_var_btn)

	var del_var_btn := _make_btn("×", "删除当前变体")
	del_var_btn.add_theme_font_size_override("font_size", 7)
	del_var_btn.pressed.connect(_on_variant_delete)
	top.add_child(del_var_btn)

	top.add_child(VSeparator.new())

	var edit_btn := _make_btn("编辑", "编辑模式")
	edit_btn.add_theme_font_size_override("font_size", 6)
	edit_btn.toggle_mode = true
	edit_btn.pressed.connect(_on_tool_clicked.bind(Tool.EDIT))
	top.add_child(edit_btn)
	_tool_buttons.append(edit_btn)

	var link_btn := _make_btn("连线", "连线模式")
	link_btn.add_theme_font_size_override("font_size", 6)
	link_btn.toggle_mode = true
	link_btn.pressed.connect(_on_tool_clicked.bind(Tool.LINK))
	top.add_child(link_btn)
	_tool_buttons.append(link_btn)

	var add_layer_btn := _make_btn("+层", "新增一层")
	add_layer_btn.add_theme_font_size_override("font_size", 6)
	add_layer_btn.pressed.connect(_on_add_layer)
	top.add_child(add_layer_btn)

	# ★ 第十二批：撤销 / 重做按钮
	var undo_btn := _make_btn("↶", "撤销 (Ctrl+Z)")
	undo_btn.add_theme_font_size_override("font_size", 6)
	undo_btn.pressed.connect(_undo)
	top.add_child(undo_btn)

	var redo_btn := _make_btn("↷", "重做 (Ctrl+Shift+Z / Ctrl+Y)")
	redo_btn.add_theme_font_size_override("font_size", 6)
	redo_btn.pressed.connect(_redo)
	top.add_child(redo_btn)

	top.add_child(VSeparator.new())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	_levellist_btn = _make_btn("关卡池", "选择 LevelList 文件")
	_levellist_btn.add_theme_font_size_override("font_size", 4)
	_levellist_btn.pressed.connect(_on_pick_levellist)
	top.add_child(_levellist_btn)

	_test_btn = _make_btn("测试", "预览节点（按当前布局 + 关卡池）")
	_test_btn.add_theme_font_size_override("font_size", 6)
	_test_btn.toggle_mode = true
	_test_btn.pressed.connect(_on_test_toggle)
	top.add_child(_test_btn)

	var new_btn := _make_btn("新", "新建文件")
	new_btn.add_theme_font_size_override("font_size", 6)
	new_btn.pressed.connect(_on_new)
	top.add_child(new_btn)

	var open_btn := _make_btn("开", "打开文件")
	open_btn.add_theme_font_size_override("font_size", 6)
	open_btn.pressed.connect(_on_open)
	top.add_child(open_btn)

	var save_btn := _make_btn("存", "保存")
	save_btn.add_theme_font_size_override("font_size", 6)
	save_btn.pressed.connect(_on_save)
	top.add_child(save_btn)

	var validate_btn := _make_btn("校验", "扫描所有节点的 unlock_relics / unlock_units")
	validate_btn.add_theme_font_size_override("font_size", 6)
	validate_btn.pressed.connect(_run_layout_validation)
	top.add_child(validate_btn)

	var quit_btn := _make_btn("退出", "关闭编辑器")
	quit_btn.add_theme_font_size_override("font_size", 6)
	quit_btn.pressed.connect(func(): get_tree().quit())
	top.add_child(quit_btn)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -14
	_hint_label.offset_left = 6
	_hint_label.add_theme_font_size_override("font_size", 6)
	_hint_label.text = "左键=创建/拖动 | 中键=删节点/删连线 | 右键=改类型/空白处=插入层 | Ctrl+Z=撤销 | 滚轮=滚动"
	add_child(_hint_label)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 2
	_scroll.offset_top = 24
	_scroll.offset_right = -2
	_scroll.offset_bottom = -16
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	var canvas_script = load("res://function/tool/editor/MapLayoutCanvas.gd")
	_canvas = Control.new()
	_canvas.set_script(canvas_script)
	_canvas.set("editor", self)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.add_child(_canvas)

	_canvas.gui_input.connect(_on_canvas_input)


# ============================================================
#  画布输入
# ============================================================
func _on_canvas_input(event: InputEvent):
	var local_pos : Vector2 = _canvas.get_local_mouse_position()
	_mouse_pos = local_pos

	if event is InputEventMouseButton:
		_handle_mouse_button(event, local_pos)
	elif event is InputEventMouseMotion:
		if _dragging_idx >= 0:
			_canvas.queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton, local: Vector2):
	if _in_test_mode:
		return

	if event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var idx : int = _node_at(local)
			if idx >= 0:
				if _current_tool == Tool.EDIT:
					_push_undo()   # ★ 拖动起点 push
					_dragging_idx = idx
				else:
					_handle_link_click(idx)
			else:
				if _current_tool == Tool.EDIT:
					_create_node_at(local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _current_tool == Tool.EDIT:
				var idx : int = _node_at(local)
				if idx >= 0:
					_show_type_picker_popup(idx)
				else:
					_try_insert_layer_at_mouse(local)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if _current_tool == Tool.EDIT:
				var idx2 : int = _node_at(local)
				if idx2 >= 0:
					_delete_node(idx2)
			elif _current_tool == Tool.LINK:
				var link : Array = _link_at(local)
				if link.size() == 2:
					_delete_link(link[0], link[1])
	else:
		if event.button_index == MOUSE_BUTTON_LEFT and _dragging_idx >= 0:
			_end_drag(local)


# ============================================================
#  插入层
# ============================================================
func _compute_insert_layer_at_y(y: float) -> int:
	var max_layer : int = _get_max_layer()
	if y < CANVAS_PADDING_TOP - LAYER_HEIGHT * 0.5:
		return max_layer + 1
	var bottom_y : float = CANVAS_PADDING_TOP + (max_layer + 1) * LAYER_HEIGHT + LAYER_HEIGHT * 0.5
	if y > bottom_y:
		return 0

	var layer_idx : int = _layer_at_y(y)
	var center_y : float = CANVAS_PADDING_TOP + (max_layer - layer_idx + 0.5) * LAYER_HEIGHT
	var dist : float = abs(y - center_y)

	if dist < NODE_H / 2.0 + 2.0:
		return -1

	if y < center_y:
		return layer_idx + 1
	return layer_idx


func _try_insert_layer_at_mouse(local: Vector2):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	var insert_at : int = _compute_insert_layer_at_y(local.y)
	if insert_at < 0:
		return
	_insert_layer(insert_at)


func _insert_layer(insert_at: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return

	_push_undo()   # ★ 第十二批

	for n in day_layout.nodes:
		if n.layer >= insert_at:
			n.layer += 1

	var n := MapLayoutNode.new()
	n.node_type = MapNode.NodeType.NORMAL
	n.layer = insert_at
	day_layout.nodes.append(n)

	_refresh_canvas_size()
	_canvas.queue_redraw()
	print("[MapLayoutEditor] 在 L%d 处插入新层" % insert_at)


# ============================================================
#  布局管理
# ============================================================
func _get_variant_array() -> Array:
	return _get_variant_array_for_day(_current_day)


func _get_current_day_layout() -> MapLayoutDay:
	var arr : Array = _get_variant_array()
	if arr.is_empty():
		return null
	if _variant_idx < 0 or _variant_idx >= arr.size():
		_variant_idx = 0
	return arr[_variant_idx]


func _ensure_variant_exists():
	if _layout == null: return
	var arr : Array = _get_variant_array()
	while arr.size() <= _variant_idx:
		arr.append(MapLayoutDay.new())
	var day_layout : MapLayoutDay = arr[_variant_idx]
	if day_layout.nodes.is_empty():
		var n := MapLayoutNode.new()
		n.node_type = MapNode.NodeType.START
		n.layer = 0
		day_layout.nodes.append(n)


# ============================================================
#  画布尺寸
# ============================================================
func _get_max_layer() -> int:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return 0
	var m : int = 0
	for n in day_layout.nodes:
		m = maxi(m, n.layer)
	return m


func _refresh_canvas_size():
	var max_layer : int = _get_max_layer()
	var h : float = CANVAS_PADDING_TOP + (max_layer + 1) * LAYER_HEIGHT + CANVAS_PADDING_BOTTOM
	_canvas.custom_minimum_size = Vector2(0, h)
	call_deferred("_scroll_to_bottom")


func _scroll_to_bottom():
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = 999999


# ============================================================
#  节点位置（Y 反向：L0 在底部）
# ============================================================
func _canvas_width() -> float:
	if _canvas == null: return 400.0
	return maxf(_canvas.size.x, 200.0)


func _node_pos(idx: int) -> Vector2:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return Vector2.ZERO
	if idx < 0 or idx >= day_layout.nodes.size(): return Vector2.ZERO
	var node : MapLayoutNode = day_layout.nodes[idx]
	var same_layer : Array[int] = []
	for i in range(day_layout.nodes.size()):
		if day_layout.nodes[i].layer == node.layer:
			same_layer.append(i)
	var my_pos : int = same_layer.find(idx)
	var count : int = same_layer.size()
	var ratio : float = float(my_pos + 1) / float(count + 1)
	var x : float = _canvas_width() * ratio
	var max_layer : int = _get_max_layer()
	var y : float = CANVAS_PADDING_TOP + (max_layer - node.layer + 0.5) * LAYER_HEIGHT
	return Vector2(x, y)


func _node_at(local: Vector2) -> int:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return -1
	for i in range(day_layout.nodes.size()):
		if local.distance_to(_node_pos(i)) < NODE_W * 0.6:
			return i
	return -1


func _link_at(local: Vector2) -> Array:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return []
	var tol : float = 4.0
	for i in range(day_layout.nodes.size()):
		var node : MapLayoutNode = day_layout.nodes[i]
		var from_pos : Vector2 = _node_pos(i)
		for target in node.connects_to:
			if target < 0 or target >= day_layout.nodes.size(): continue
			var to_pos : Vector2 = _node_pos(target)
			if _point_near_segment(local, from_pos, to_pos, tol):
				return [i, target]
	return []


func _point_near_segment(p: Vector2, a: Vector2, b: Vector2, tol: float) -> bool:
	var ab : Vector2 = b - a
	var ab_len_sq : float = ab.length_squared()
	if ab_len_sq < 0.001:
		return p.distance_to(a) <= tol
	var t : float = (p - a).dot(ab) / ab_len_sq
	t = clampf(t, 0.0, 1.0)
	var closest : Vector2 = a + ab * t
	return p.distance_to(closest) <= tol


func _delete_link(from_idx: int, to_idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	if from_idx < 0 or from_idx >= day_layout.nodes.size(): return
	_push_undo()   # ★
	day_layout.nodes[from_idx].connects_to.erase(to_idx)
	_canvas.queue_redraw()


func _layer_at_y(y: float) -> int:
	var max_layer : int = _get_max_layer()
	var rel : float = y - CANVAS_PADDING_TOP
	var l : int = max_layer - int(rel / LAYER_HEIGHT)
	return clampi(l, 0, max_layer)


func _create_node_at(local: Vector2):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	_push_undo()   # ★
	var new_layer : int = _layer_at_y(local.y)
	var n := MapLayoutNode.new()
	n.node_type = MapNode.NodeType.NORMAL
	n.layer = new_layer
	day_layout.nodes.append(n)
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _end_drag(local: Vector2):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	if _dragging_idx < 0 or _dragging_idx >= day_layout.nodes.size():
		_dragging_idx = -1
		return
	var new_layer : int = _layer_at_y(local.y)
	day_layout.nodes[_dragging_idx].layer = new_layer
	_dragging_idx = -1
	_canvas.queue_redraw()


# ============================================================
#  连线
# ============================================================
func _handle_link_click(idx: int):
	if _selected_link == -1:
		_selected_link = idx
		_canvas.queue_redraw()
		return
	var from_idx : int = _selected_link
	_selected_link = -1
	if from_idx == idx: return
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	var node : MapLayoutNode = day_layout.nodes[from_idx]
	if not node.connects_to.has(idx):
		_push_undo()   # ★
		node.connects_to.append(idx)
	_canvas.queue_redraw()


func _delete_node(idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	if idx < 0 or idx >= day_layout.nodes.size(): return

	_push_undo()   # ★

	var removed_layer : int = day_layout.nodes[idx].layer
	day_layout.nodes.remove_at(idx)

	for n in day_layout.nodes:
		var new_list : Array[int] = []
		for t in n.connects_to:
			if t == idx: continue
			new_list.append(t - 1 if t > idx else t)
		n.connects_to = new_list

	var has_in_layer : bool = false
	for n in day_layout.nodes:
		if n.layer == removed_layer:
			has_in_layer = true
			break
	if not has_in_layer:
		for n in day_layout.nodes:
			if n.layer > removed_layer:
				n.layer -= 1

	_refresh_canvas_size()
	_canvas.queue_redraw()


# ============================================================
#  工具栏回调
# ============================================================
func _on_day_clicked(d: int):
	_current_day = d
	_variant_idx = 0
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_variant_prev():
	_variant_idx = maxi(0, _variant_idx - 1)
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_variant_next():
	var arr : Array = _get_variant_array()
	if _variant_idx + 1 >= arr.size():
		arr.append(MapLayoutDay.new())
	_variant_idx += 1
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_variant_add():
	_push_undo()   # ★
	var arr : Array = _get_variant_array()
	arr.append(MapLayoutDay.new())
	_variant_idx = arr.size() - 1
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_variant_delete():
	var arr : Array = _get_variant_array()
	if arr.size() <= 1:
		return
	_push_undo()   # ★
	arr.remove_at(_variant_idx)
	_variant_idx = clampi(_variant_idx, 0, arr.size() - 1)
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_add_layer():
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	_push_undo()   # ★
	var new_layer : int = _get_max_layer() + 1
	var n := MapLayoutNode.new()
	n.node_type = MapNode.NodeType.NORMAL
	n.layer = new_layer
	day_layout.nodes.append(n)
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_tool_clicked(t: int):
	_current_tool = t as Tool
	_selected_link = -1
	_dragging_idx = -1
	_update_all_labels()
	_canvas.queue_redraw()


func _update_all_labels():
	for i in range(_day_buttons.size()):
		_day_buttons[i].button_pressed = (i + 1 == _current_day)
	for i in range(_tool_buttons.size()):
		_tool_buttons[i].button_pressed = (i == _current_tool)
	var arr : Array = _get_variant_array()
	if _variant_label:
		_variant_label.text = "%d/%d" % [_variant_idx + 1, maxi(arr.size(), 1)]

	if _levellist_btn:
		if _levellist_path != "":
			var fname : String = _levellist_path.get_file()
			if fname.ends_with(".tres"):
				fname = fname.substr(0, fname.length() - 5)
			_levellist_btn.text = fname
			_levellist_btn.tooltip_text = _levellist_path
		else:
			_levellist_btn.text = "关卡池"
			_levellist_btn.tooltip_text = "选择 LevelList 文件"

	if _test_btn:
		_test_btn.button_pressed = _in_test_mode
		_test_btn.text = "退出" if _in_test_mode else "测试"


# ============================================================
#  保存前烘焙位置
# ============================================================
func _bake_positions():
	if _layout == null: return
	for day_variants in [_layout.day1_variants, _layout.day2_variants, _layout.day3_variants]:
		for day_layout in day_variants:
			if day_layout == null: continue
			for i in range(day_layout.nodes.size()):
				var node : MapLayoutNode = day_layout.nodes[i]
				node.position = _node_pos_for_variant(day_layout, i)


# ============================================================
#  校验
# ============================================================
func _run_layout_validation():
	if _layout == null:
		Globals.show_confirm(self, "未加载布局文件。", "确定", "",
			func(): pass, func(): pass, false)
		return

	var errors : Array = []

	var relic_db : Dictionary = _get_relic_data_cached()
	var valid_relics : Dictionary = {}
	for rid in relic_db:
		valid_relics[rid] = true

	# ★ 只允许 map_unlock_units 出现在 unlock_units
	var unit_ids : Array = Globals.get_map_unlock_units()
	var valid_units : Dictionary = {}
	for uid in unit_ids:
		valid_units[uid] = true

	var all_days : Array = [
		{"day": 1, "variants": _layout.day1_variants},
		{"day": 2, "variants": _layout.day2_variants},
		{"day": 3, "variants": _layout.day3_variants},
	]

	for day_data in all_days:
		var day_num : int = day_data["day"]
		var variants : Array = day_data["variants"]
		for vi in range(variants.size()):
			var dl : MapLayoutDay = variants[vi]
			if dl == null: continue
			for ni in range(dl.nodes.size()):
				var node : MapLayoutNode = dl.nodes[ni]
				var pos_str : String = "(%.0f, %.0f)" % [node.position.x, node.position.y]

				for rid in node.unlock_relics:
					if not valid_relics.has(rid):
						errors.append("Day%d V%d Node[%d]%s  遗物不存在: %s"
							% [day_num, vi, ni, pos_str, rid])

				for uid in node.unlock_units:
					if not valid_units.has(uid):
						errors.append("Day%d V%d Node[%d]%s  非地图解锁单位: %s（不在 map_unlock_units 里）"
							% [day_num, vi, ni, pos_str, uid])

	var msg : String = ""
	if errors.is_empty():
		msg = "✓ 校验通过\n\n所有 unlock_relics / unlock_units 引用均存在。"
		print("[MapLayoutEditor] ✓ 校验通过")
	else:
		msg = "发现 %d 个错误:\n\n" % errors.size()
		var show_count : int = mini(errors.size(), 15)
		for i in range(show_count):
			msg += "· " + errors[i] + "\n"
		if errors.size() > show_count:
			msg += "\n... (还有 %d 个，见控制台)" % (errors.size() - show_count)

		print("[MapLayoutEditor] === 校验报告 ===")
		for e in errors:
			print("[校验] " + e)

	Globals.show_confirm(self, msg, "确定", "",
		func(): pass, func(): pass, false)


func _node_pos_for_variant(day_layout: MapLayoutDay, idx: int) -> Vector2:
	if day_layout == null: return Vector2.ZERO
	if idx < 0 or idx >= day_layout.nodes.size(): return Vector2.ZERO
	var node : MapLayoutNode = day_layout.nodes[idx]

	var max_layer : int = 0
	for n in day_layout.nodes:
		max_layer = maxi(max_layer, n.layer)

	var same_layer : Array[int] = []
	for i in range(day_layout.nodes.size()):
		if day_layout.nodes[i].layer == node.layer:
			same_layer.append(i)
	var my_pos : int = same_layer.find(idx)
	var count : int = same_layer.size()
	var ratio : float = float(my_pos + 1) / float(count + 1)

	var x : float = BAKE_WIDTH * ratio
	var y : float = CANVAS_PADDING_TOP + (max_layer - node.layer + 0.5) * LAYER_HEIGHT
	return Vector2(x, y)


func _node_type_short(t: int) -> String:
	match t:
		MapNode.NodeType.START: return "START"
		MapNode.NodeType.NORMAL: return "NORMAL"
		MapNode.NodeType.ELITE: return "ELITE"
		MapNode.NodeType.TREASURE: return "TREASURE"
		MapNode.NodeType.BOSS: return "BOSS"
		MapNode.NodeType.FORGE: return "FORGE"
		MapNode.NodeType.CHAPEL: return "CHAPEL"
	return "?"
