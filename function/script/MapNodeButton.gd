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

	# ★ v4.4：目标徽章
	_add_objective_badge(node_data)


func _add_objective_badge(node: MapNode):
	var existing = get_node_or_null("ObjectiveBadge")
	if existing:
		existing.queue_free()

	if node == null or node.map_data == null:
		return
	if node.map_data.objective_type == MapData.ObjectiveType.ANNIHILATE:
		return

	var badge_text : String = _objective_badge_text(node.map_data.objective_type)
	if badge_text == "":
		return

	var badge := Label.new()
	badge.name = "ObjectiveBadge"
	badge.text = badge_text
	badge.add_theme_font_size_override("font_size", 5)
	badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 1)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 0.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_top = 1
	badge.offset_bottom = 9
	add_child(badge)


func _objective_badge_text(t: int) -> String:
	match t:
		MapData.ObjectiveType.CAPTURE: return "★占"
		MapData.ObjectiveType.FLAG: return "★旗"
		MapData.ObjectiveType.ASSAULT: return "★突"
		_: return ""


func _get_node_label(node: MapNode) -> String:
	if node.node_type == MapNode.NodeType.QUESTION:
		return "???"

	if node.node_type in [
		MapNode.NodeType.FORGE,
		MapNode.NodeType.TREASURE,
		MapNode.NodeType.CHAPEL,
	]:
		return MapConst.get_node_display_name(node.node_type)
	if node.map_data and node.map_data.map_name != "":
		return node.map_data.map_name
	return MapConst.get_node_display_name(node.node_type)


func _get_color(node: MapNode) -> Color:
	if node.is_visited:
		return MapConst.MAP_NODE_VISITED
	if node.is_available:
		if node.node_type == MapNode.NodeType.QUESTION:
			return Color(1.0, 0.85, 0.3)
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
