extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

func setup(node_data: MapNode, map_scene: CanvasLayer, override_pos: Vector2 = Vector2.INF):
	map_node = node_data
	map_scene_ref = map_scene
	text = _get_node_label(node_data)
	
	size = MapConst.MAP_NODE_SIZE
	var pos : Vector2 = override_pos if override_pos != Vector2.INF else node_data.position
	position = pos - size / 2
	disabled = not node_data.is_available
	modulate = _get_color(node_data)
	visible = true
	add_theme_font_size_override("font_size", MapConst.MAP_NODE_FONT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_color_disabled", Color.WHITE)
	add_theme_color_override("font_color_hover", Color.WHITE)
	add_theme_color_override("font_color_pressed", Color.WHITE)
	
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
	match node.node_type:
		MapNode.NodeType.SHOP:     return "商店"
		MapNode.NodeType.FORGE:    return "铁匠铺"
		MapNode.NodeType.TREASURE: return "宝箱"
		MapNode.NodeType.CHAPEL:   return "圣坛"

	if node.map_data and node.map_data.map_name != "":
		return node.map_data.map_name

	return "?"

func _get_color(node: MapNode) -> Color:
	if node.is_visited:
		return MapConst.MAP_NODE_VISITED
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
