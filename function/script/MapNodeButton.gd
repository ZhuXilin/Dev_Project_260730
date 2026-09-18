extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

func setup(node_data: MapNode, map_scene: CanvasLayer):
	map_node = node_data
	map_scene_ref = map_scene
	text = _get_node_label(node_data)
	
	size = MapConst.MAP_NODE_SIZE
	position = node_data.position - size / 2
	disabled = not node_data.is_available
	modulate = _get_color(node_data)
	visible = true
	add_theme_font_size_override("font_size", MapConst.MAP_NODE_FONT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# ---- 强制所有状态下的字体颜色为白色 ----
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_color_disabled", Color.WHITE)
	add_theme_color_override("font_color_hover", Color.WHITE)
	add_theme_color_override("font_color_pressed", Color.WHITE)
	
	# ---- 使用 8bit_style_box_flat 样式（不透明） ----
	var stylebox = load(Config.PATHS.STYLEBOX_8BIT)
	if stylebox:
		add_theme_stylebox_override("normal", stylebox)
		add_theme_stylebox_override("pressed", stylebox)
		add_theme_stylebox_override("hover", stylebox)
		add_theme_stylebox_override("disabled", stylebox)
		add_theme_stylebox_override("focus", stylebox)
	
	if pressed.is_connected(_on_clicked):
		pressed.disconnect(_on_clicked)
	pressed.connect(_on_clicked)
	
	# ---- 悬停显示节点描述（新增） ----
	if mouse_entered.is_connected(_on_hover_enter):
		mouse_entered.disconnect(_on_hover_enter)
	if mouse_exited.is_connected(_on_hover_exit):
		mouse_exited.disconnect(_on_hover_exit)
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)
	
	for child in get_children():
		if child.name == "CheckLabel":
			remove_child(child)
			child.queue_free()
			break

func _get_node_label(node: MapNode) -> String:
	# ---- 非战斗节点：固定类型名 ----
	match node.node_type:
		MapNode.NodeType.SHOP:  return "商店"
		MapNode.NodeType.FORGE: return "铁匠铺"
		MapNode.NodeType.EVENT: return "宝箱"

	# ---- 战斗节点（START / NORMAL / ELITE / BOSS）：显示地图名 ----
	if node.map_data and node.map_data.map_name != "":
		return node.map_data.map_name

	# 兜底
	return "?"

func _get_color(node: MapNode) -> Color:
	if node.is_visited:
		return MapConst.MAP_NODE_VISITED      # 深灰色（已走过，不可交互）
	if node.is_available:
		return MapConst.MAP_NODE_AVAILABLE
	return MapConst.MAP_NODE_UNAVAILABLE

func _on_clicked():
	if map_node.is_visited or not map_node.is_available:
		print("节点已访问或不可用，忽略点击")
		return
	print("地图按钮被点击: ", text)
	if map_scene_ref and map_scene_ref.has_method("on_node_selected"):
		map_scene_ref.on_node_selected(map_node)

func _on_hover_enter():
	if map_scene_ref and map_scene_ref.has_method("show_node_info"):
		map_scene_ref.show_node_info(map_node)


func _on_hover_exit():
	if map_scene_ref and map_scene_ref.has_method("hide_node_info"):
		map_scene_ref.hide_node_info()
