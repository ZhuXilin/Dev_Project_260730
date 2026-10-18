@tool
extends Control

const LAYER_HEIGHT : float = 28.0
const NODE_W : float = 40.0
const NODE_H : float = 14.0
const NODE_FONT_SIZE : int = 6
const CANVAS_PADDING_TOP : float = 20.0
const CANVAS_PADDING_BOTTOM : float = 12.0
const LAYOUT_DIR : String = "res://content/scenes/levels/maplayout/"
const BAKE_WIDTH : float = 400.0
const RELIC_DATA_PATH : String = "res://content/data/relic_data.json"
const UNIT_LEVEL_MAP_PATH : String = "res://content/scenes/levels/UnitLevelMap.tres"

const COMBAT_NODE_TYPES : Array = [
	MapNode.NodeType.START,
	MapNode.NodeType.NORMAL,
	MapNode.NodeType.ELITE,
	MapNode.NodeType.BOSS,
]

const MAX_UNDO : int = 30

enum Tool { EDIT, LINK }

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

var _undo_stack : Array = []
var _redo_stack : Array = []

var _unit_level_map : UnitLevelMapConfig = null
var _faction_btn : Button = null
var _current_faction : String = ""


func _ready():
	_ensure_dir()
	_apply_compact_theme()
	_load_unit_level_map()
	_build_ui()

	var factions := _get_all_factions()
	if factions.size() > 0:
		_current_faction = factions[0]
		_load_current_faction_layout()
	else:
		_new_layout()


func _ensure_dir():
	if not DirAccess.dir_exists_absolute(LAYOUT_DIR):
		DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)


func _apply_compact_theme():
	var t := Theme.new()
	t.set_font_size("font_size", "Button", 6)
	t.set_font_size("font_size", "Label", 6)
	t.set_font_size("font_size", "PopupMenu", 6)
	t.set_font_size("font_size", "TooltipLabel", 6)
	t.set_font_size("font_size", "TooltipPanel", 6)
	# ★ v4.5：统一弹窗里的字号
	t.set_font_size("font_size", "SpinBox", 7)
	t.set_font_size("font_size", "OptionButton", 7)
	t.set_font_size("font_size", "LineEdit", 7)

	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_right = 2
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	t.set_stylebox("normal", "Button", empty)
	t.set_stylebox("hover", "Button", empty)
	t.set_stylebox("pressed", "Button", empty)
	t.set_stylebox("focus", "Button", empty)

	# ★ v4.5：压扁 LineEdit
	var le_empty := StyleBoxEmpty.new()
	le_empty.content_margin_left = 2
	le_empty.content_margin_right = 2
	le_empty.content_margin_top = 0
	le_empty.content_margin_bottom = 0
	t.set_stylebox("normal", "LineEdit", le_empty)
	t.set_stylebox("focus", "LineEdit", le_empty)
	t.set_stylebox("read_only", "LineEdit", le_empty)

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
	t.set_constant("v_separation", "PopupMenu", 0)

	var tip_sb := StyleBoxFlat.new()
	tip_sb.bg_color = Color(0.15, 0.15, 0.15, 0.92)
	tip_sb.content_margin_left = 3
	tip_sb.content_margin_right = 3
	tip_sb.content_margin_top = 1
	tip_sb.content_margin_bottom = 1
	t.set_stylebox("panel", "TooltipPanel", tip_sb)

	theme = t


func _style_spin(sp : SpinBox):
	if not is_instance_valid(sp): return
	var le := sp.get_line_edit()
	if le:
		le.add_theme_font_size_override("font_size", 7)
	var btns : Array[Node] = sp.find_children("*", "Button", true, false)
	for b in btns:
		var btn := b as Button
		btn.custom_minimum_size = Vector2(3, 2)
		btn.icon_max_width = 2
		btn.icon_max_height = 2
		btn.focus_mode = Control.FOCUS_NONE
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 0
		e.content_margin_right = 0
		e.content_margin_top = 0
		e.content_margin_bottom = 0
		btn.add_theme_stylebox_override("normal", e)
		btn.add_theme_stylebox_override("hover", e)
		btn.add_theme_stylebox_override("pressed", e)
		btn.add_theme_stylebox_override("focus", e)
		btn.add_theme_stylebox_override("disabled", e)


func _load_unit_level_map():
	if ResourceLoader.exists(UNIT_LEVEL_MAP_PATH):
		_unit_level_map = load(UNIT_LEVEL_MAP_PATH)
	if _unit_level_map == null:
		_unit_level_map = UnitLevelMapConfig.new()
		_unit_level_map.default_entry = UnitLevelMapEntry.new()
		_unit_level_map.entries.clear()


func _get_all_factions() -> Array:
	var factions : Dictionary = {}
	if _unit_level_map:
		for entry in _unit_level_map.entries:
			if entry.faction != "":
				factions[entry.faction] = true

	for u_key in UnitDataManager.get_all_unit_data():
		var u_data = UnitDataManager.get_unit_data(u_key)
		var f = u_data.get("faction", "")
		if f != "":
			factions[f] = true

	var result : Array = factions.keys()
	result.sort()
	return result


func _load_current_faction_layout():
	if _current_faction == "":
		_new_layout()
		return

	var entry : UnitLevelMapEntry = _get_entry_for_faction(_current_faction)
	if entry and entry.layout:
		_layout = entry.layout
		_layout_path = entry.layout.resource_path
	else:
		_new_layout()
		return

	_current_day = 1
	_variant_idx = 0
	_clear_history()
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	if _canvas:
		_canvas.queue_redraw()
	print("[MapLayoutEditor] 加载阵营 %s 的已有布局: %s" % [_current_faction, _layout_path])


func _new_layout():
	_layout = MapLayout.new()
	_layout.day1_variants.append(MapLayoutDay.new())
	_layout.day2_variants.append(MapLayoutDay.new())
	_layout.day3_variants.append(MapLayoutDay.new())
	_layout_path = ""
	_current_day = 1
	_variant_idx = 0
	_clear_history()
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	if _canvas:
		_canvas.queue_redraw()


func _show_faction_menu():
	var menu := PopupMenu.new()
	add_child(menu)

	var factions : Array = _get_all_factions()
	for i in range(factions.size()):
		menu.add_item(factions[i], i)

	menu.add_separator()
	menu.add_item("+ 新建阵营...", 999)
	if _current_faction != "":
		menu.add_item("✎ 重命名当前阵营...", 998)

	menu.id_pressed.connect(func(id):
		if id == 999:
			_prompt_new_faction()
		elif id == 998:
			_prompt_rename_faction()
		else:
			if id >= 0 and id < factions.size():
				_current_faction = factions[id]
				_update_all_labels()
				_load_current_faction_layout()
		menu.queue_free()
	)

	menu.popup_hide.connect(func():
		if is_instance_valid(menu):
			menu.queue_free()
	)

	var btn_rect : Rect2 = _faction_btn.get_global_rect()
	var px : int = int(btn_rect.position.x)
	var py : int = int(btn_rect.position.y + btn_rect.size.y)
	menu.popup(Rect2i(Vector2i(px, py), Vector2i(0, 0)))


func _prompt_new_faction():
	_show_text_input_popup("新建阵营", "输入阵营名称（如：精灵、亡灵）：", "", func(new_name):
		if new_name.strip_edges() == "":
			return
		new_name = new_name.strip_edges()

		var existing = _get_all_factions()
		if new_name in existing:
			Globals.show_confirm(self, "阵营「%s」已存在！" % new_name, "确定", "", func(): pass, func(): pass, false)
			return

		_current_faction = new_name
		var entry = _get_entry_for_faction(new_name)
		if entry == null:
			entry = UnitLevelMapEntry.new()
			entry.faction = new_name
			_unit_level_map.entries.append(entry)

		_new_layout()
		_update_all_labels()
	)


func _prompt_rename_faction():
	if _current_faction == "":
		return
	_show_text_input_popup("重命名阵营", "修改当前阵营的名称：", _current_faction, func(new_name):
		if new_name.strip_edges() == "":
			return
		new_name = new_name.strip_edges()
		if new_name == _current_faction:
			return

		var existing = _get_all_factions()
		if new_name in existing:
			Globals.show_confirm(self, "阵营「%s」已存在！" % new_name, "确定", "", func(): pass, func(): pass, false)
			return

		var entry = _get_entry_for_faction(_current_faction)
		if entry != null:
			entry.faction = new_name

		_current_faction = new_name
		_layout_path = ""
		_update_all_labels()
		Globals.show_confirm(self, "阵营已重命名，保存后将生效。", "确定", "", func(): pass, func(): pass, false)
	)


func _on_save():
	if _layout == null:
		return
	if _current_faction == "":
		Globals.show_confirm(self, "请先选择或新建一个阵营！", "确定", "", func(): pass, func(): pass, false)
		return

	if _layout_path == "":
		_layout_path = LAYOUT_DIR + "MapLayout_%s.tres" % _current_faction
		if ResourceLoader.exists(_layout_path):
			_layout_path = LAYOUT_DIR + "MapLayout_%s_%d.tres" % [_current_faction, Time.get_ticks_msec()]

	_bake_positions()
	var err := ResourceSaver.save(_layout, _layout_path)
	if err != OK:
		push_error("保存 Layout 失败: %d" % err)
		return

	var entry : UnitLevelMapEntry = _get_entry_for_faction(_current_faction)
	if entry == null:
		entry = UnitLevelMapEntry.new()
		entry.faction = _current_faction
		_unit_level_map.entries.append(entry)

	entry.layout = _layout
	if entry.day1 == null:
		entry.day1 = load("res://content/scenes/levels/levellists/LevelListType001_Day1.tres")
	if entry.day2 == null:
		entry.day2 = load("res://content/scenes/levels/levellists/LevelListType001_Day2.tres")
	if entry.day3 == null:
		entry.day3 = load("res://content/scenes/levels/levellists/LevelListType001_Day3.tres")

	var err2 := ResourceSaver.save(_unit_level_map, UNIT_LEVEL_MAP_PATH)
	if err2 == OK:
		_update_all_labels()
		print("[MapLayoutEditor] 已保存 %s 阵营的布局，并更新 UnitLevelMap.tres" % _current_faction)
	else:
		push_error("保存 UnitLevelMap 失败: %d" % err2)


func _get_entry_for_faction(faction_cn: String) -> UnitLevelMapEntry:
	if _unit_level_map == null:
		return null
	for entry in _unit_level_map.entries:
		if entry.faction == faction_cn:
			return entry
	return null


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
		cp.objective_type = n.objective_type
		cp.objective_params = n.objective_params.duplicate(true)
		cp.max_waves = n.max_waves
		cp.reinforcement_count = n.reinforcement_count
		cp.reward_multiplier = n.reward_multiplier
		cp.enemy_hp_multiplier = n.enemy_hp_multiplier
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
		return
	var cur : Dictionary = _snapshot_current()
	if not cur.is_empty():
		_redo_stack.append(cur)
	var snap : Dictionary = _undo_stack.pop_back()
	_apply_snapshot(snap)


func _redo():
	if _redo_stack.is_empty():
		return
	var cur : Dictionary = _snapshot_current()
	if not cur.is_empty():
		_undo_stack.append(cur)
	var snap : Dictionary = _redo_stack.pop_back()
	_apply_snapshot(snap)


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
	if _layout == null:
		return []
	match day:
		1: return _layout.day1_variants
		2: return _layout.day2_variants
		3: return _layout.day3_variants
	return []


func _clear_history():
	_undo_stack.clear()
	_redo_stack.clear()


func _unhandled_input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var focus := get_viewport().gui_get_focus_owner()
	if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and focus is LineEdit:
		return

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


func _on_test_toggle():
	# ★ 优化：如果准备开启测试且还没选文件，尝试自动加载当前阵营对应的关卡池
	if not _in_test_mode and _levellist == null:
		var entry = _get_entry_for_faction(_current_faction)
		if entry:
			match _current_day:
				1: _levellist = entry.day1
				2: _levellist = entry.day2
				3: _levellist = entry.day3
			
			if _levellist:
				_levellist_path = _levellist.resource_path
				print("[MapLayoutEditor] 自动加载测试关卡池: ", _levellist_path)
				_update_all_labels()

	_in_test_mode = not _in_test_mode
	_test_btn.button_pressed = _in_test_mode

	if _in_test_mode:
		if _levellist == null:
			Globals.show_confirm(self, "当前阵营（%s）第 %d 天未绑定 LevelList。\n请先点顶部【关卡池】按钮手动选择。" % [_current_faction, _current_day], "确定", "", func(): pass, func(): pass, false)
			_in_test_mode = false
			_test_btn.button_pressed = false
			return
		_generate_test_map()
	else:
		_test_map_assignment.clear()

	_update_all_labels()
	_canvas.queue_redraw()


func _on_pick_levellist():
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.add_filter("*.tres", "Tres 文件")
	fd.use_native_dialog = true
	# ★ 优化：默认直接打开 levellists 目录，防止选错到 maplayout 目录
	fd.current_dir = "res://content/scenes/levels/levellists/"
	fd.title = "选择关卡池（LevelList，不是 MapLayout）"
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res == null:
			fd.queue_free()
			return
		if not (res is LevelListResource):
			Globals.show_confirm(self, "选中的文件不是关卡池（LevelList）。\n请选择 levellists 文件夹下的文件。", "确定", "", func(): pass, func(): pass, false)
			fd.queue_free()
			return
		_levellist = res
		_levellist_path = path
		_update_all_labels()
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(500, 400))


func _generate_test_map():
	_test_map_assignment.clear()
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return

	var pools : Dictionary = {}
	if _levellist and _levellist.levels:
		for m in _levellist.levels:
			if m == null:
				continue
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


func _load_relic_data_for_editor() -> Dictionary:
	if not FileAccess.file_exists(RELIC_DATA_PATH):
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
	le.custom_minimum_size = Vector2(0, 16)
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
		get_viewport().set_input_as_handled()
		_close_popup()
		on_ok.call(t.strip_edges())
	)

	le.grab_focus()


func _show_type_picker_popup(node_idx: int):
	_close_popup()
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return
	if node_idx < 0 or node_idx >= day_layout.nodes.size():
		return

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
		[MapNode.NodeType.QUESTION, "QUESTION"],
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
		for rid in all_relics:
			valid_relic_ids[rid] = true
		for rid in current_relics:
			if not valid_relic_ids.has(rid):
				var orphan_lb := Label.new()
				orphan_lb.text = "⚠ 孤儿：" + rid
				orphan_lb.add_theme_font_size_override("font_size", 7)
				orphan_lb.modulate = Color(1.0, 0.5, 0.5)
				orphan_lb.tooltip_text = "该 id 在 relic_data.json 里不存在"
				relic_list.add_child(orphan_lb)

	main.add_child(right_box)

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
		for uid in all_unit_ids:
			valid_unit_ids[uid] = true
		for uid in current_units:
			if not valid_unit_ids.has(uid):
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

	# ============================================================
	#  ★ v4.5：目标、波次、奖励、倍率行（应用压扁字号与尺寸）
	# ============================================================
	var obj_row := HBoxContainer.new()
	obj_row.add_theme_constant_override("separation", 4)
	obj_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(obj_row)

	var obj_lb := Label.new()
	obj_lb.text = "目标:"
	obj_lb.add_theme_font_size_override("font_size", 7)
	obj_lb.custom_minimum_size = Vector2(0, 16)
	obj_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	obj_row.add_child(obj_lb)

	var obj_opt := OptionButton.new()
	obj_opt.add_theme_font_size_override("font_size", 7)
	obj_opt.add_item("全灭", int(MapData.ObjectiveType.ANNIHILATE))
	obj_opt.add_item("占领", int(MapData.ObjectiveType.CAPTURE))
	obj_opt.add_item("夺旗", int(MapData.ObjectiveType.FLAG))
	obj_opt.add_item("突进", int(MapData.ObjectiveType.ASSAULT))
	obj_opt.selected = int(node.objective_type)
	obj_opt.disabled = not can_unlock
	obj_opt.custom_minimum_size = Vector2(56, 16) # 限制高度
	obj_row.add_child(obj_opt)

	var obj_param_lb := Label.new()
	obj_param_lb.text = "参数:"
	obj_param_lb.add_theme_font_size_override("font_size", 7)
	obj_param_lb.custom_minimum_size = Vector2(0, 16)
	obj_param_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	obj_row.add_child(obj_param_lb)

	var obj_param_edit := LineEdit.new()
	obj_param_edit.add_theme_font_size_override("font_size", 7)
	obj_param_edit.custom_minimum_size = Vector2(0, 16) # 限制高度
	obj_param_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obj_param_edit.editable = can_unlock
	obj_param_edit.placeholder_text = "JSON，如 {\"target_cell\": [10, 7], \"hold_turns\": 3}"
	obj_param_edit.tooltip_text = "CAPTURE: {\"target_cell\": [x, y], \"hold_turns\": n}\nFLAG: {\"flag_cell\": [x, y], \"goal_cell\": [x, y]}\nASSAULT: {\"target_unit_name\": \"id\"}\n留空：由 ObjectiveManager 智能 fallback"
	if not node.objective_params.is_empty():
		obj_param_edit.text = JSON.stringify(node.objective_params)
	obj_row.add_child(obj_param_edit)

	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override("separation", 4)
	wave_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(wave_row)

	var wave_lb := Label.new()
	wave_lb.text = "波次:"
	wave_lb.add_theme_font_size_override("font_size", 7)
	wave_lb.custom_minimum_size = Vector2(0, 16)
	wave_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_row.add_child(wave_lb)

	var wave_spin := SpinBox.new()
	wave_spin.min_value = 1
	wave_spin.max_value = 3
	wave_spin.step = 1
	wave_spin.value = maxi(1, node.max_waves)
	wave_spin.custom_minimum_size = Vector2(40, 16)
	wave_spin.editable = can_unlock
	wave_row.add_child(wave_spin)
	_style_spin(wave_spin)

	var reinf_lb := Label.new()
	reinf_lb.text = " 增援:"
	reinf_lb.add_theme_font_size_override("font_size", 7)
	reinf_lb.custom_minimum_size = Vector2(0, 16)
	reinf_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_row.add_child(reinf_lb)

	var reinf_spin := SpinBox.new()
	reinf_spin.min_value = 0
	reinf_spin.max_value = 5
	reinf_spin.step = 1
	reinf_spin.value = maxi(0, node.reinforcement_count)
	reinf_spin.custom_minimum_size = Vector2(40, 16)
	reinf_spin.editable = can_unlock
	wave_row.add_child(reinf_spin)
	_style_spin(reinf_spin)

	var reward_lb := Label.new()
	reward_lb.text = " 奖励×:"
	reward_lb.add_theme_font_size_override("font_size", 7)
	reward_lb.custom_minimum_size = Vector2(0, 16)
	reward_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_row.add_child(reward_lb)

	var reward_spin := SpinBox.new()
	reward_spin.min_value = 1.0
	reward_spin.max_value = 2.0
	reward_spin.step = 0.1
	reward_spin.value = maxf(1.0, node.reward_multiplier)
	reward_spin.custom_minimum_size = Vector2(44, 16)
	reward_spin.editable = can_unlock
	wave_row.add_child(reward_spin)
	_style_spin(reward_spin)

	var enemy_hp_lb := Label.new()
	enemy_hp_lb.text = " 敌HP×:"
	enemy_hp_lb.add_theme_font_size_override("font_size", 7)
	enemy_hp_lb.custom_minimum_size = Vector2(0, 16)
	enemy_hp_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_row.add_child(enemy_hp_lb)

	var enemy_hp_spin := SpinBox.new()
	enemy_hp_spin.min_value = 1.0
	enemy_hp_spin.max_value = 1.5
	enemy_hp_spin.step = 0.1
	enemy_hp_spin.value = maxf(1.0, node.enemy_hp_multiplier)
	enemy_hp_spin.custom_minimum_size = Vector2(44, 16)
	enemy_hp_spin.editable = can_unlock
	wave_row.add_child(enemy_hp_spin)
	_style_spin(enemy_hp_spin)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 4)
	preset_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(preset_row)

	var preset_lb := Label.new()
	preset_lb.text = "快速预设:"
	preset_lb.add_theme_font_size_override("font_size", 7)
	preset_lb.custom_minimum_size = Vector2(0, 16)
	preset_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preset_row.add_child(preset_lb)

	var preset_normal := Button.new()
	preset_normal.text = "普通×2"
	preset_normal.add_theme_font_size_override("font_size", 7)
	preset_normal.custom_minimum_size = Vector2(52, 16)
	preset_normal.disabled = not can_unlock
	preset_normal.pressed.connect(func():
		wave_spin.value = 2
		reinf_spin.value = 0
		reward_spin.value = 1.5
		enemy_hp_spin.value = 1.0
	)
	preset_row.add_child(preset_normal)

	var preset_elite := Button.new()
	preset_elite.text = "精英×3"
	preset_elite.add_theme_font_size_override("font_size", 7)
	preset_elite.custom_minimum_size = Vector2(52, 16)
	preset_elite.disabled = not can_unlock
	preset_elite.pressed.connect(func():
		wave_spin.value = 3
		reinf_spin.value = 0
		reward_spin.value = 2.0
		enemy_hp_spin.value = 1.2
	)
	preset_row.add_child(preset_elite)

	var preset_boss := Button.new()
	preset_boss.text = "首领×2+援"
	preset_boss.add_theme_font_size_override("font_size", 7)
	preset_boss.custom_minimum_size = Vector2(64, 16)
	preset_boss.disabled = not can_unlock
	preset_boss.pressed.connect(func():
		wave_spin.value = 2
		reinf_spin.value = 1
		reward_spin.value = 2.0
		enemy_hp_spin.value = 1.4
	)
	preset_row.add_child(preset_boss)

	var preset_clear := Button.new()
	preset_clear.text = "清空"
	preset_clear.add_theme_font_size_override("font_size", 7)
	preset_clear.custom_minimum_size = Vector2(40, 16)
	preset_clear.disabled = not can_unlock
	preset_clear.pressed.connect(func():
		wave_spin.value = 1
		reinf_spin.value = 0
		reward_spin.value = 1.0
		enemy_hp_spin.value = 1.0
	)
	preset_row.add_child(preset_clear)

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

		if can_unlock:
			node.objective_type = obj_opt.selected as MapData.ObjectiveType
			var param_text : String = obj_param_edit.text.strip_edges()
			if param_text == "":
				node.objective_params = {}
			else:
				var parsed = JSON.parse_string(param_text)
				if parsed is Dictionary:
					var cleaned : Dictionary = {}
					for k in parsed:
						var v : Variant = parsed[k]
						var t : int = typeof(v)
						if t == TYPE_ARRAY and (v as Array).size() == 2:
							var arr : Array = v
							var t0 : int = typeof(arr[0])
							var t1 : int = typeof(arr[1])
							var is_num0 : bool = (t0 == TYPE_INT or t0 == TYPE_FLOAT)
							var is_num1 : bool = (t1 == TYPE_INT or t1 == TYPE_FLOAT)
							if is_num0 and is_num1:
								cleaned[k] = Vector2i(int(arr[0]), int(arr[1]))
								continue
						if t == TYPE_FLOAT:
							cleaned[k] = int(v)
						else:
							cleaned[k] = v
					node.objective_params = cleaned
				else:
					node.objective_params = {}

			node.max_waves = clampi(int(wave_spin.value), 1, 3)
			node.reinforcement_count = clampi(int(reinf_spin.value), 0, 5)
			node.reward_multiplier = clampf(float(reward_spin.value), 1.0, 2.0)
			node.enemy_hp_multiplier = clampf(float(enemy_hp_spin.value), 1.0, 1.5)
		else:
			node.objective_type = MapData.ObjectiveType.ANNIHILATE
			node.objective_params = {}
			node.max_waves = 1
			node.reinforcement_count = 0
			node.reward_multiplier = 1.0
			node.enemy_hp_multiplier = 1.0

		_canvas.queue_redraw()
		_close_popup()

	ok.pressed.connect(confirm_action)
	_popup_confirm_callback = confirm_action


func _close_popup():
	if _popup_layer and is_instance_valid(_popup_layer):
		_popup_layer.queue_free()
		_popup_layer = null
	_popup_confirm_callback = Callable()


func _make_btn(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 6)
	return b


func _build_ui():
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 2
	top.offset_right = -2
	top.offset_top = 2
	top.offset_bottom = 20
	top.add_theme_constant_override("separation", 1)
	add_child(top)

	_faction_btn = _make_btn("阵营: 未选择 ▼", "点击设置当前布局归属的阵营")
	_faction_btn.add_theme_font_size_override("font_size", 7)
	_faction_btn.pressed.connect(_show_faction_menu)
	top.add_child(_faction_btn)

	top.add_child(VSeparator.new())

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

	var new_btn := _make_btn("新建", "新建一个空布局")
	new_btn.add_theme_font_size_override("font_size", 6)
	new_btn.pressed.connect(_new_layout)
	top.add_child(new_btn)

	var save_btn := _make_btn("保存", "保存当前布局并绑定阵营")
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
					_push_undo()
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
	if day_layout == null:
		return
	var insert_at : int = _compute_insert_layer_at_y(local.y)
	if insert_at < 0:
		return
	_insert_layer(insert_at)


func _insert_layer(insert_at: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return

	_push_undo()

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
	if _layout == null:
		return
	var arr : Array = _get_variant_array()
	while arr.size() <= _variant_idx:
		arr.append(MapLayoutDay.new())
	var day_layout : MapLayoutDay = arr[_variant_idx]
	if day_layout.nodes.is_empty():
		var n := MapLayoutNode.new()
		n.node_type = MapNode.NodeType.START
		n.layer = 0
		day_layout.nodes.append(n)


func _get_max_layer() -> int:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return 0
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


func _canvas_width() -> float:
	if _canvas == null:
		return 400.0
	return maxf(_canvas.size.x, 200.0)


func _node_pos(idx: int) -> Vector2:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return Vector2.ZERO
	if idx < 0 or idx >= day_layout.nodes.size():
		return Vector2.ZERO
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
	if day_layout == null:
		return -1
	for i in range(day_layout.nodes.size()):
		if local.distance_to(_node_pos(i)) < NODE_W * 0.6:
			return i
	return -1


func _link_at(local: Vector2) -> Array:
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return []
	var tol : float = 4.0
	for i in range(day_layout.nodes.size()):
		var node : MapLayoutNode = day_layout.nodes[i]
		var from_pos : Vector2 = _node_pos(i)
		for target in node.connects_to:
			if target < 0 or target >= day_layout.nodes.size():
				continue
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
	if day_layout == null:
		return
	if from_idx < 0 or from_idx >= day_layout.nodes.size():
		return
	_push_undo()
	day_layout.nodes[from_idx].connects_to.erase(to_idx)
	_canvas.queue_redraw()


func _layer_at_y(y: float) -> int:
	var max_layer : int = _get_max_layer()
	var rel : float = y - CANVAS_PADDING_TOP
	var l : int = max_layer - int(rel / LAYER_HEIGHT)
	return clampi(l, 0, max_layer)


func _create_node_at(local: Vector2):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return
	_push_undo()
	var new_layer : int = _layer_at_y(local.y)
	var n := MapLayoutNode.new()
	n.node_type = MapNode.NodeType.NORMAL
	n.layer = new_layer
	day_layout.nodes.append(n)
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _end_drag(local: Vector2):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return
	if _dragging_idx < 0 or _dragging_idx >= day_layout.nodes.size():
		_dragging_idx = -1
		return
	var new_layer : int = _layer_at_y(local.y)
	day_layout.nodes[_dragging_idx].layer = new_layer
	_dragging_idx = -1
	_canvas.queue_redraw()


func _handle_link_click(idx: int):
	if _selected_link == -1:
		_selected_link = idx
		_canvas.queue_redraw()
		return
	var from_idx : int = _selected_link
	_selected_link = -1
	if from_idx == idx:
		return
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return
	var node : MapLayoutNode = day_layout.nodes[from_idx]
	if not node.connects_to.has(idx):
		_push_undo()
		node.connects_to.append(idx)
	_canvas.queue_redraw()


func _delete_node(idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return
	if idx < 0 or idx >= day_layout.nodes.size():
		return

	_push_undo()

	var removed_layer : int = day_layout.nodes[idx].layer
	day_layout.nodes.remove_at(idx)

	for n in day_layout.nodes:
		var new_list : Array[int] = []
		for t in n.connects_to:
			if t == idx:
				continue
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
		return
	_variant_idx += 1
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_variant_add():
	_push_undo()
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
	_push_undo()
	arr.remove_at(_variant_idx)
	_variant_idx = clampi(_variant_idx, 0, arr.size() - 1)
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_add_layer():
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null:
		return
	_push_undo()
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
	if _faction_btn:
		if _current_faction == "":
			_faction_btn.text = "阵营: 未选择 ▼"
		else:
			_faction_btn.text = "阵营: %s ▼" % _current_faction

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


func _bake_positions():
	if _layout == null:
		return
	var valid_pool : Array = Globals.get_map_unlock_units()
	var valid_dict : Dictionary = {}
	for u in valid_pool:
		valid_dict[u] = true
	var clean_count : int = 0

	for day_variants in [_layout.day1_variants, _layout.day2_variants, _layout.day3_variants]:
		for day_layout in day_variants:
			if day_layout == null:
				continue
			for i in range(day_layout.nodes.size()):
				var node : MapLayoutNode = day_layout.nodes[i]
				node.position = _node_pos_for_variant(day_layout, i)

				var new_units : Array[String] = []
				for uid in node.unlock_units:
					var key := UnitDataManager.normalize_unit_key(uid)
					if valid_dict.has(key):
						new_units.append(key)
					else:
						clean_count += 1
						print("[MapLayoutEditor] 自动清理非法的地图解锁单位: ", uid)
				node.unlock_units = new_units

	if clean_count > 0:
		print("[MapLayoutEditor] 保存前共清理 %d 个违规的解锁单位" % clean_count)


func _run_layout_validation():
	if _layout == null:
		Globals.show_confirm(self, "未加载布局文件。", "确定", "", func(): pass, func(): pass, false)
		return

	var errors : Array = []

	var relic_db : Dictionary = _get_relic_data_cached()
	var valid_relics : Dictionary = {}
	for rid in relic_db:
		valid_relics[rid] = true

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
			if dl == null:
				continue
			for ni in range(dl.nodes.size()):
				var node : MapLayoutNode = dl.nodes[ni]
				var pos_str : String = "(%.0f, %.0f)" % [node.position.x, node.position.y]

				# ★ v4.5：校验倍率
				if node.reward_multiplier < 1.0 or node.reward_multiplier > 2.0:
					errors.append("Day%d V%d Node[%d]%s  reward_multiplier=%.2f 越界（应为 1.0-2.0）"
						% [day_num, vi, ni, pos_str, node.reward_multiplier])
				if node.enemy_hp_multiplier < 1.0 or node.enemy_hp_multiplier > 1.5:
					errors.append("Day%d V%d Node[%d]%s  enemy_hp_multiplier=%.2f 越界（应为 1.0-1.5）"
						% [day_num, vi, ni, pos_str, node.enemy_hp_multiplier])
				if node.reward_multiplier > 1.0 and node.enemy_hp_multiplier <= 1.0:
					errors.append("Day%d V%d Node[%d]%s  有奖励倍率但没有负面代价，建议配 enemy_hp_multiplier"
						% [day_num, vi, ni, pos_str])

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

	Globals.show_confirm(self, msg, "确定", "", func(): pass, func(): pass, false)


func _node_pos_for_variant(day_layout: MapLayoutDay, idx: int) -> Vector2:
	if day_layout == null:
		return Vector2.ZERO
	if idx < 0 or idx >= day_layout.nodes.size():
		return Vector2.ZERO
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
		MapNode.NodeType.QUESTION: return "QUESTION"
	return "?"
