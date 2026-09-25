@tool
extends Control

const LAYER_HEIGHT : float = 46.0
const NODE_W : float = 66.0
const NODE_H : float = 22.0
const CANVAS_PADDING_TOP : float = 26.0
const CANVAS_PADDING_BOTTOM : float = 16.0

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

var _day_buttons : Array[Button] = []
var _tool_buttons : Array[Button] = []
var _variant_label : Label = null
var _path_label : Label = null
var _hint_label : Label = null


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_build_ui()
	_load_default_layout()


func _make_btn(text: String, tooltip: String = "", width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 10)
	# 减小按钮内部 padding
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", empty)
	if width > 0:
		b.custom_minimum_size = Vector2(width, 0)
	return b


func _build_ui():
	# ---- 顶部工具栏（用 HBox，缩小 padding） ----
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 2
	top.offset_right = -2
	top.offset_top = 2
	top.offset_bottom = 24
	top.add_theme_constant_override("separation", 1)
	add_child(top)

	# Day 按钮
	for d in [1, 2, 3]:
		var b := _make_btn("D%d" % d, "Day %d" % d)
		b.toggle_mode = true
		b.pressed.connect(_on_day_clicked.bind(d))
		top.add_child(b)
		_day_buttons.append(b)

	top.add_child(VSeparator.new())

	# 变体
	var prev_btn := _make_btn("◀", "上一个变体")
	prev_btn.pressed.connect(_on_variant_prev)
	top.add_child(prev_btn)

	_variant_label = Label.new()
	_variant_label.text = "1/1"
	_variant_label.custom_minimum_size = Vector2(36, 0)
	_variant_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_variant_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_variant_label.add_theme_font_size_override("font_size", 10)
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

	# 工具
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

	# 保存 / 加载（放最右，用最短文字）
	var save_btn := _make_btn("存", "保存到 " + _layout_path)
	save_btn.pressed.connect(_on_save)
	top.add_child(save_btn)

	var load_btn := _make_btn("读", "加载其他 .tres")
	load_btn.pressed.connect(_on_load)
	top.add_child(load_btn)

	# 路径 label 只作 tooltip，不占空间
	_path_label = Label.new()
	_path_label.visible = false
	add_child(_path_label)

	# ---- 底部提示 ----
	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -18
	_hint_label.offset_left = 6
	_hint_label.add_theme_font_size_override("font_size", 9)
	_hint_label.text = "左键空白=创建 | 拖动=改层 | 右键=菜单 | 滚轮=滚动 | 连线: 点两个节点"
	add_child(_hint_label)

	# ---- 滚动容器 + 画布 ----
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 2
	_scroll.offset_top = 26
	_scroll.offset_right = -2
	_scroll.offset_bottom = -22
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

	# ★ gui_input 信号只传 1 个参数（event）
	_canvas.gui_input.connect(_on_canvas_input)


# ============================================================
#  画布输入
# ============================================================
func _on_canvas_input(event: InputEvent):
	# ★ 局部坐标从 _canvas 获取
	var local_pos : Vector2 = _canvas.get_local_mouse_position()
	_mouse_pos = local_pos

	if event is InputEventMouseButton:
		_handle_mouse_button(event, local_pos)
	elif event is InputEventMouseMotion:
		if _dragging_idx >= 0:
			_canvas.queue_redraw()


func _handle_mouse_button(event: InputEventMouseButton, local: Vector2):
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
			var idx : int = _node_at(local)
			if idx >= 0:
				_show_node_menu(idx)
	else:
		if event.button_index == MOUSE_BUTTON_LEFT and _dragging_idx >= 0:
			_end_drag(local)


# ============================================================
#  布局管理
# ============================================================
func _load_default_layout():
	var path := "res://content/scenes/levels/MapLayoutDefault.tres"
	if ResourceLoader.exists(path):
		_layout = load(path)
		_layout_path = path
	else:
		_layout = MapLayout.new()
	if _layout.day1_variants.is_empty():
		_layout.day1_variants.append(MapLayoutDay.new())
	if _layout.day2_variants.is_empty():
		_layout.day2_variants.append(MapLayoutDay.new())
	if _layout.day3_variants.is_empty():
		_layout.day3_variants.append(MapLayoutDay.new())

	_variant_idx = 0
	_current_day = 1
	_ensure_variant_exists()
	_update_all_labels()
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _get_variant_array() -> Array:
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


# ============================================================
#  节点位置（Y 反向）
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


# ============================================================
#  右键菜单
# ============================================================
func _show_node_menu(idx: int):
	var menu := PopupMenu.new()
	menu.add_item("改类型...", 1)
	menu.add_item("改随机池...", 2)
	menu.add_item("删除节点", 3)
	add_child(menu)
	menu.id_pressed.connect(func(id):
		_on_menu_selected(id, idx)
		menu.queue_free()
	)
	menu.popup_on_parent(Rect2(get_global_mouse_position(), Vector2.ZERO))


func _on_menu_selected(id: int, idx: int):
	match id:
		1: _show_type_picker(idx)
		2: _show_pool_picker(idx)
		3: _delete_node(idx)


func _delete_node(idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	day_layout.nodes.remove_at(idx)
	for n in day_layout.nodes:
		var new_list : Array[int] = []
		for t in n.connects_to:
			if t == idx: continue
			new_list.append(t - 1 if t > idx else t)
		n.connects_to = new_list
	_refresh_canvas_size()
	_canvas.queue_redraw()


func _show_type_picker(idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return
	var menu := PopupMenu.new()
	var types := [
		[MapNode.NodeType.START, "START"],
		[MapNode.NodeType.NORMAL, "NORMAL"],
		[MapNode.NodeType.ELITE, "ELITE"],
		[MapNode.NodeType.SHOP, "SHOP"],
		[MapNode.NodeType.EVENT, "EVENT"],
		[MapNode.NodeType.BOSS, "BOSS"],
		[MapNode.NodeType.FORGE, "FORGE"],
		[MapNode.NodeType.CHAPEL, "CHAPEL"],
	]
	for t in types:
		# ★ id 用 index 而不是 enum（避免 cast 问题）
		menu.add_item(t[1], menu.item_count)
	add_child(menu)
	menu.id_pressed.connect(func(item_idx):
		var t : Array = types[item_idx]
		day_layout.nodes[idx].node_type = t[0]
		day_layout.nodes[idx].random_pool.clear()
		_canvas.queue_redraw()
		menu.queue_free()
	)
	menu.popup_on_parent(Rect2(get_global_mouse_position(), Vector2.ZERO))


func _show_pool_picker(idx: int):
	var day_layout : MapLayoutDay = _get_current_day_layout()
	if day_layout == null: return

	var dlg := AcceptDialog.new()
	dlg.title = "选择随机池"
	dlg.min_size = Vector2i(180, 240)
	dlg.ok_button_text = "确定"
	var cancel_btn := dlg.add_cancel_button("取消")

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(160, 180)
	dlg.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)

	var checks : Array[CheckBox] = []
	var types := [
		[MapNode.NodeType.NORMAL, "NORMAL"],
		[MapNode.NodeType.ELITE, "ELITE"],
		[MapNode.NodeType.SHOP, "SHOP"],
		[MapNode.NodeType.EVENT, "EVENT"],
		[MapNode.NodeType.FORGE, "FORGE"],
		[MapNode.NodeType.CHAPEL, "CHAPEL"],
	]
	var current : MapLayoutNode = day_layout.nodes[idx]
	for t in types:
		var cb := CheckBox.new()
		cb.text = t[1]
		cb.add_theme_font_size_override("font_size", 9)
		cb.set_meta("type", t[0])
		cb.button_pressed = current.random_pool.has(t[0])
		vbox.add_child(cb)
		checks.append(cb)

	add_child(dlg)
	dlg.confirmed.connect(func():
		var pool : Array = []
		for cb in checks:
			if cb.button_pressed:
				pool.append(cb.get_meta("type"))
		var typed_pool : Array[MapNode.NodeType] = []
		for p in pool:
			typed_pool.append(p as MapNode.NodeType)
		day_layout.nodes[idx].random_pool = typed_pool
		if not typed_pool.is_empty():
			day_layout.nodes[idx].node_type = typed_pool[0]
		_canvas.queue_redraw()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered(Vector2i(180, 240))      # ★ 强制尺寸


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
		push_warning("至少保留 1 个变体")
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
	_variant_label.text = "%d/%d" % [_variant_idx + 1, arr.size()]
	if _path_label:
		_path_label.text = _layout_path if _layout_path != "" else "(未保存)"


# ============================================================
#  保存 / 加载
# ============================================================
func _on_save():
	if _layout_path == "":
		_layout_path = "res://content/scenes/levels/MapLayoutDefault.tres"
	var err := ResourceSaver.save(_layout, _layout_path)
	if err == OK:
		print("[MapLayoutEditor] 已保存: ", _layout_path)
		_update_all_labels()
	else:
		push_error("保存失败: %d" % err)


func _on_load():
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.add_filter("*.tres", "Tres")
	fd.min_size = Vector2i(320, 240)            # ★ 明确最小尺寸
	fd.file_selected.connect(func(path):
		_layout = load(path)
		_layout_path = path
		_current_day = 1
		_variant_idx = 0
		_ensure_variant_exists()
		_update_all_labels()
		_refresh_canvas_size()
		_canvas.queue_redraw()
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(320, 240))       # ★ 强制尺寸
