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
var _test_map_assignment : Dictionary = {}   # MapLayoutNode -> 地图名
var _levellist_btn : Button = null
var _test_btn : Button = null

var _day_buttons : Array[Button] = []
var _tool_buttons : Array[Button] = []
var _variant_label : Label = null
var _hint_label : Label = null

var _popup_confirm_callback : Callable = Callable()

# ============================================================
#  生命周期
# ============================================================
func _ready():
	_ensure_dir()
	_build_ui()
	call_deferred("_show_startup_menu")


func _ensure_dir():
	if not DirAccess.dir_exists_absolute(LAYOUT_DIR):
		DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)


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
	fd.current_dir = "res://content/scenes/levels/"
	fd.title = "选择 LevelList 文件"
	fd.file_selected.connect(func(path):
		var ll = load(path)
		if ll == null:
			push_warning("加载失败: " + path)
			fd.queue_free()
			return
		_levellist = ll
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

	# ---- 收集每个类型的候选地图 ----
	var pools : Dictionary = {}
	if _levellist and _levellist.levels:
		for m in _levellist.levels:
			if m == null: continue
			var t : int = m.node_type
			if not pools.has(t):
				pools[t] = []
			pools[t].append(m)

	# ---- 逐层解析（同层去重，和 MapGenerator 一致） ----
	var by_layer : Dictionary = {}
	for i in range(day_layout.nodes.size()):
		var ln : MapLayoutNode = day_layout.nodes[i]
		if not by_layer.has(ln.layer):
			by_layer[ln.layer] = []
		by_layer[ln.layer].append(i)

	for layer_key in by_layer:
		var indices : Array = by_layer[layer_key]

		# 先处理固定节点占位
		var used_types : Dictionary = {}
		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			if ln.random_pool.is_empty():
				used_types[ln.node_type] = true

		# 再处理随机节点
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

			# 非战斗节点 → 空
			if resolved in [
				MapNode.NodeType.SHOP,
				MapNode.NodeType.FORGE,
				MapNode.NodeType.TREASURE,
				MapNode.NodeType.CHAPEL,
			]:
				_test_map_assignment[ln] = _node_type_short(resolved)
				continue

			# 战斗节点 → 从池里抽
			var pool : Array = pools.get(resolved, [])
			if pool.is_empty():
				_test_map_assignment[ln] = "?"
			else:
				var pick : MapData = pool[randi() % pool.size()]
				_test_map_assignment[ln] = pick.map_name

# ============================================================
#  嵌入式 Popup
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

	# 弹窗：左右居中，宽 200，上下留 40px
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

	# 撑高空间（输入框之后到按钮之间）
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vbox.add_child(btns)

	# 确认在左，取消在右
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

	# 确认回调
	var confirm_action := func():
		var t : String = le.text.strip_edges()
		_close_popup()
		on_ok.call(t)
	ok.pressed.connect(confirm_action)
	_popup_confirm_callback = confirm_action

	# Enter 提交
	le.text_submitted.connect(func(t):
		_close_popup()
		on_ok.call(t.strip_edges())
	)

	le.grab_focus()


func _show_pool_picker_popup(node_idx: int):
	_close_popup()
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	if node_idx < 0 or node_idx >= day_layout.nodes.size(): return

	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_popup_layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(bg)

	# 弹窗：左右居中，宽 200，上下留 40px
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
	title_lb.text = "选择随机池"
	title_lb.add_theme_font_size_override("font_size", 9)
	title_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lb)

	# 滚动列表
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(list_vbox)

	var checks : Array[CheckBox] = []
	var types := [
		[MapNode.NodeType.NORMAL, "NORMAL"],
		[MapNode.NodeType.ELITE, "ELITE"],
		[MapNode.NodeType.SHOP, "SHOP"],
		[MapNode.NodeType.TREASURE, "TREASURE"],
		[MapNode.NodeType.FORGE, "FORGE"],
		[MapNode.NodeType.CHAPEL, "CHAPEL"],
	]
	var current : MapLayoutNode = day_layout.nodes[node_idx]

	# 压 padding
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	empty.content_margin_left = 0
	empty.content_margin_right = 0

	for t in types:
		var cb := CheckBox.new()
		cb.text = t[1]
		cb.add_theme_font_size_override("font_size", 7)
		cb.add_theme_constant_override("h_separation", 3)
		cb.add_theme_stylebox_override("normal", empty)
		cb.add_theme_stylebox_override("hover", empty)
		cb.add_theme_stylebox_override("pressed", empty)
		cb.add_theme_stylebox_override("focus", empty)
		cb.add_theme_stylebox_override("disabled", empty)
		cb.custom_minimum_size = Vector2(0, 8)
		cb.set_meta("type", t[0])
		cb.button_pressed = current.random_pool.has(t[0])
		list_vbox.add_child(cb)
		checks.append(cb)

	# 底部按钮
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vbox.add_child(btns)

	# 确认在左，取消在右
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

	# 确认回调
	var confirm_action := func():
		var pool : Array = []
		for cb in checks:
			if cb.button_pressed:
				pool.append(cb.get_meta("type"))
		var typed_pool : Array[MapNode.NodeType] = []
		for p in pool:
			typed_pool.append(p as MapNode.NodeType)
		day_layout.nodes[node_idx].random_pool = typed_pool
		if not typed_pool.is_empty():
			day_layout.nodes[node_idx].node_type = typed_pool[0]
		_canvas.queue_redraw()
		_close_popup()
	ok.pressed.connect(confirm_action)
	_popup_confirm_callback = confirm_action


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
	_popup_layer.add_child(bg)

	# ★ 左右居中 + 上下贴边
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -100
	panel.offset_right = 100
	panel.offset_top = 4
	panel.offset_bottom = -4
	_popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title_lb := Label.new()
	title_lb.text = "节点类型（多选 = 随机池）"
	title_lb.add_theme_font_size_override("font_size", 8)
	title_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_lb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)

	var types := [
		[MapNode.NodeType.START, "START"],
		[MapNode.NodeType.NORMAL, "NORMAL"],
		[MapNode.NodeType.ELITE, "ELITE"],
		[MapNode.NodeType.SHOP, "SHOP"],
		[MapNode.NodeType.TREASURE, "TREASURE"],
		[MapNode.NodeType.BOSS, "BOSS"],
		[MapNode.NodeType.FORGE, "FORGE"],
		[MapNode.NodeType.CHAPEL, "CHAPEL"],
	]

	var is_in_pool : bool = not node.random_pool.is_empty()

	var checks : Array[CheckBox] = []
	for t in types:
		var cb := CheckBox.new()
		cb.text = t[1]
		cb.add_theme_font_size_override("font_size", 7)
		cb.add_theme_constant_override("h_separation", 3)
		# ★ 用 StyleBoxEmpty 压掉上下 padding
		var empty := StyleBoxEmpty.new()
		empty.content_margin_top = 0
		empty.content_margin_bottom = 0
		empty.content_margin_left = 0
		empty.content_margin_right = 0
		cb.add_theme_stylebox_override("normal", empty)
		cb.add_theme_stylebox_override("hover", empty)
		cb.add_theme_stylebox_override("pressed", empty)
		cb.add_theme_stylebox_override("focus", empty)
		cb.add_theme_stylebox_override("disabled", empty)
		cb.custom_minimum_size = Vector2(0, 8)   # ★ 极小高度
		cb.set_meta("type", t[0])
		if is_in_pool:
			cb.button_pressed = node.random_pool.has(t[0])
		else:
			cb.button_pressed = (t[0] == node.node_type)
		list.add_child(cb)
		checks.append(cb)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 8)
	vbox.add_child(btns)

	# ★ 确定在左，取消在右
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

	# ★ 保存确认回调（供 Enter 使用）
	var confirm_action := func():
		var selected : Array = []
		for cb in checks:
			if cb.button_pressed:
				selected.append(cb.get_meta("type"))
		if selected.size() == 1:
			node.node_type = selected[0]
			node.random_pool.clear()
		elif selected.size() > 1:
			var typed_pool : Array[MapNode.NodeType] = []
			for p in selected:
				typed_pool.append(p as MapNode.NodeType)
			node.random_pool = typed_pool
			node.node_type = typed_pool[0]
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
	b.add_theme_font_size_override("font_size", 9)
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
		b.toggle_mode = true
		b.pressed.connect(_on_day_clicked.bind(d))
		top.add_child(b)
		_day_buttons.append(b)

	top.add_child(VSeparator.new())

	var prev_btn := _make_btn("◀", "上一个变体")
	prev_btn.pressed.connect(_on_variant_prev)
	top.add_child(prev_btn)

	_variant_label = Label.new()
	_variant_label.text = "1/1"
	_variant_label.custom_minimum_size = Vector2(36, 0)
	_variant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_variant_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_variant_label.add_theme_font_size_override("font_size", 9)
	top.add_child(_variant_label)

	var next_btn := _make_btn("▶", "下一个变体")
	next_btn.pressed.connect(_on_variant_next)
	top.add_child(next_btn)

	var add_var_btn := _make_btn("+", "新建变体")
	add_var_btn.pressed.connect(_on_variant_add)
	top.add_child(add_var_btn)

	var del_var_btn := _make_btn("×", "删除当前变体")
	del_var_btn.pressed.connect(_on_variant_delete)
	top.add_child(del_var_btn)

	top.add_child(VSeparator.new())

	var edit_btn := _make_btn("编辑", "编辑模式")
	edit_btn.toggle_mode = true
	edit_btn.pressed.connect(_on_tool_clicked.bind(Tool.EDIT))
	top.add_child(edit_btn)
	_tool_buttons.append(edit_btn)

	var link_btn := _make_btn("连线", "连线模式")
	link_btn.toggle_mode = true
	link_btn.pressed.connect(_on_tool_clicked.bind(Tool.LINK))
	top.add_child(link_btn)
	_tool_buttons.append(link_btn)

	var add_layer_btn := _make_btn("+层", "新增一层")
	add_layer_btn.pressed.connect(_on_add_layer)
	top.add_child(add_layer_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	# ★ LevelList 选择
	_levellist_btn = _make_btn("关卡池", "选择 LevelList 文件")
	_levellist_btn.pressed.connect(_on_pick_levellist)
	top.add_child(_levellist_btn)

	# ★ 测试
	_test_btn = _make_btn("测试", "预览节点（按当前布局 + 关卡池）")
	_test_btn.toggle_mode = true
	_test_btn.pressed.connect(_on_test_toggle)
	top.add_child(_test_btn)

	top.add_child(VSeparator.new())

	var new_btn := _make_btn("新", "新建文件")
	new_btn.pressed.connect(_on_new)
	top.add_child(new_btn)

	var open_btn := _make_btn("开", "打开文件")
	open_btn.pressed.connect(_on_open)
	top.add_child(open_btn)

	var save_btn := _make_btn("存", "保存")
	save_btn.pressed.connect(_on_save)
	top.add_child(save_btn)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -14
	_hint_label.offset_left = 6
	_hint_label.add_theme_font_size_override("font_size", 6)
	_hint_label.text = "左键=创建/拖动 | 中键=删节点/删连线 | 右键=改类型 | 滚轮=滚动"
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

	var canvas_script = load("res://function/tool/MapLayoutCanvas.gd")
	_canvas = Control.new()
	_canvas.set_script(canvas_script)
	_canvas.editor = self
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.add_child(_canvas)

	_canvas.gui_input.connect(_on_canvas_input)


func _unhandled_input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
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
	# ★ 测试模式禁用所有编辑操作
	if _in_test_mode:
		return

	if event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var idx : int = _node_at(local)
			if idx >= 0:
				if _current_tool == Tool.EDIT:
					_dragging_idx = idx
				else:
					_handle_link_click(idx)
			else:
				if _current_tool == Tool.EDIT:
					_create_node_at(local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# ★ 编辑模式：右键节点 → 直接弹类型选择
			if _current_tool == Tool.EDIT:
				var idx : int = _node_at(local)
				if idx >= 0:
					_show_type_picker_popup(idx)
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
#  布局管理
# ============================================================
func _get_variant_array() -> Array:
	if _layout == null: return []
	match _current_day:
		1: return _layout.day1_variants
		2: return _layout.day2_variants
		3: return _layout.day3_variants
	return []


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
	# ★ 滚动到底部（L0 起点在画布底部）
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
		node.connects_to.append(idx)
	_canvas.queue_redraw()


func _delete_node(idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	if idx < 0 or idx >= day_layout.nodes.size(): return

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
	arr.remove_at(_variant_idx)
	_variant_idx = clampi(_variant_idx, 0, arr.size() - 1)
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _on_add_layer():
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
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

	# ★ LevelList 按钮文字
	if _levellist_btn:
		if _levellist_path != "":
			var fname : String = _levellist_path.get_file()
			if fname.ends_with(".tres"):
				fname = fname.substr(0, fname.length() - 5)
			if fname.length() > 8:
				fname = fname.substr(0, 7) + "…"
			_levellist_btn.text = fname
			_levellist_btn.tooltip_text = _levellist_path
		else:
			_levellist_btn.text = "关卡池"
			_levellist_btn.tooltip_text = "选择 LevelList 文件"

	# ★ 测试按钮
	if _test_btn:
		_test_btn.button_pressed = _in_test_mode
		_test_btn.text = "退出" if _in_test_mode else "测试"
		

## 保存前：把所有节点的计算位置写入 position 字段
func _bake_positions():
	if _layout == null: return
	for day_variants in [_layout.day1_variants, _layout.day2_variants, _layout.day3_variants]:
		for day_layout in day_variants:
			if day_layout == null: continue
			for i in range(day_layout.nodes.size()):
				var node : MapLayoutNode = day_layout.nodes[i]
				node.position = _node_pos_for_variant(day_layout, i)


## 独立版本：给定 day_layout + idx，算出位置（不依赖当前 _canvas）
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
		MapNode.NodeType.SHOP: return "SHOP"
		MapNode.NodeType.TREASURE: return "TREASURE"
		MapNode.NodeType.BOSS: return "BOSS"
		MapNode.NodeType.FORGE: return "FORGE"
		MapNode.NodeType.CHAPEL: return "CHAPEL"
	return "?"
