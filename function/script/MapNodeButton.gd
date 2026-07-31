extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

func setup(node_data: MapNode, map_scene: CanvasLayer):
	map_node = node_data
	map_scene_ref = map_scene
	text = _get_node_label(node_data.node_type)
	size = Vector2(64, 28)
	position = node_data.position - size / 2
	
	disabled = not node_data.is_available
	modulate = _get_color(node_data)
	
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	if pressed.is_connected(_on_clicked):
		pressed.disconnect(_on_clicked)
	pressed.connect(_on_clicked)
	
	for child in get_children():
		if child.name == "CheckLabel":
			remove_child(child)
			child.queue_free()
			break
	
	if node_data.is_visited:
		var check = Label.new()
		check.name = "CheckLabel"
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 12)
		check.position = Vector2(size.x - 18, 4)
		add_child(check)

func _get_node_label(type: MapNode.NodeType) -> String:
	match type:
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
		return Color(0.5, 0.5, 0.5)
	if node.is_available:
		return Color.WHITE
	return Color(0.3, 0.3, 0.3)

func _on_clicked():
	print("地图按钮被点击: ", text)
	if map_scene_ref and map_scene_ref.has_method("on_node_selected"):
		map_scene_ref.on_node_selected(map_node)
	else:
		print("错误: map_scene_ref 无效或没有 on_node_selected 方法")
