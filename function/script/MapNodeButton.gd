extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

func setup(node_data: MapNode, map_scene: CanvasLayer):
	map_node = node_data
	map_scene_ref = map_scene
	text = _get_node_label(node_data)
	
	size = Vector2(40, 20)
	position = node_data.position - size / 2
	disabled = not node_data.is_available
	modulate = _get_color(node_data)
	visible = true
	add_theme_font_size_override("font_size", 5)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	if pressed.is_connected(_on_clicked):
		pressed.disconnect(_on_clicked)
	pressed.connect(_on_clicked)
	
	for child in get_children():
		if child.name == "CheckLabel":
			remove_child(child)
			child.queue_free()
			break

func _get_node_label(node: MapNode) -> String:
	if node.custom_label != "":
		return node.custom_label
	match node.node_type:
		MapNode.NodeType.START: return "起点"
		MapNode.NodeType.CAMPFIRE: return "篝火"
		MapNode.NodeType.NORMAL: return "普通"
		MapNode.NodeType.ELITE: return "精英"
		MapNode.NodeType.SHOP: return "商店"
		MapNode.NodeType.EVENT: return "事件"
		MapNode.NodeType.BOSS: return "Boss"
		MapNode.NodeType.FINAL_PREP: return "备战"
		_: return "?"

func _get_color(node: MapNode) -> Color:
	if node.is_visited:
		return Color(0.4, 0.4, 0.4)      # 深灰色（已走过，不可交互）
	if node.is_available:
		return Color.WHITE
	return Color(0.3, 0.3, 0.3)

func _on_clicked():
	if map_node.is_visited or not map_node.is_available:
		print("节点已访问或不可用，忽略点击")
		return
	print("地图按钮被点击: ", text)
	if map_scene_ref and map_scene_ref.has_method("on_node_selected"):
		map_scene_ref.on_node_selected(map_node)
