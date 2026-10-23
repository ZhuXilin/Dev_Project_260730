extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

var _text_label: Label = null


func setup(node_data: MapNode, map_scene: CanvasLayer, override_pos: Vector2 = Vector2.INF):
	map_node = node_data
	map_scene_ref = map_scene
	
	# ★ 清空 Button 自带的文字
	text = ""

	size = MapConst.MAP_NODE_SIZE
	var pos : Vector2 = override_pos if override_pos != Vector2.INF else node_data.position
	position = pos - size / 2
	disabled = not node_data.is_available
	
	# 保持纯白调制，底色用 box_sb 控制
	modulate = Color.WHITE
	
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 根据状态决定底色
	var bg_color := Color.WHITE
	if node_data.is_visited:
		bg_color = Color(0.6, 0.6, 0.6) # 已访问：深灰色
	elif not node_data.is_available:
		bg_color = Color(0.85, 0.85, 0.85) # 不可用：浅灰色

	# 强制白/灰底，黑边
	var box_sb := StyleBoxFlat.new()
	box_sb.bg_color = bg_color
	box_sb.border_width_left = 1
	box_sb.border_width_right = 1
	box_sb.border_width_top = 1
	box_sb.border_width_bottom = 1
	box_sb.border_color = Color.BLACK
	
	add_theme_stylebox_override("normal", box_sb)
	add_theme_stylebox_override("pressed", box_sb)
	add_theme_stylebox_override("hover", box_sb)
	add_theme_stylebox_override("disabled", box_sb)
	add_theme_stylebox_override("focus", box_sb)

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

	# ★ 核心修复：创建专属的 Label 来显示文字，无视 Button 自带渲染
	_ensure_label()
	_text_label.text = _get_node_label(node_data)

	_add_objective_badge(node_data)


func _ensure_label():
	if _text_label == null or not is_instance_valid(_text_label):
		_text_label = Label.new()
		_text_label.name = "TextLabel"
		_text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_text_label)

	# 强制黑字，去掉所有描边
	_text_label.add_theme_font_size_override("font_size", MapConst.MAP_NODE_FONT_SIZE)
	_text_label.add_theme_color_override("font_color", Color.BLACK)
	_text_label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	_text_label.add_theme_constant_override("outline_size", 0)
	_text_label.add_theme_constant_override("shadow_offset_x", 0)
	_text_label.add_theme_constant_override("shadow_offset_y", 0)


func _add_objective_badge(node: MapNode):
	var existing = get_node_or_null("ObjectiveBadge")
	if existing:
		existing.queue_free()

	if node == null or node.node_type == MapNode.NodeType.QUESTION:
		return
	if node.map_data == null:
		return

	var parts : Array = []

	var int_text : String = _intensity_badge_text(node.map_data.intensity)
	if int_text != "":
		parts.append(int_text)

	var obj_text : String = _objective_badge_text(node.map_data.objective_type)
	if obj_text != "":
		parts.append(obj_text)

	if node.map_data.max_waves > 1:
		if node.map_data.reinforcement_count > 0:
			parts.append("波%d+援%d" % [node.map_data.max_waves, node.map_data.reinforcement_count])
		else:
			parts.append("波%d" % node.map_data.max_waves)

	if node.map_data.reward_multiplier > 1.0:
		parts.append("×%.1f" % node.map_data.reward_multiplier)

	if parts.is_empty():
		return

	var badge := Label.new()
	badge.name = "ObjectiveBadge"
	badge.text = " · ".join(parts)
	badge.add_theme_font_size_override("font_size", 6)
	
	# 徽章也使用纯黑字
	badge.add_theme_color_override("font_color", Color.BLACK)
	badge.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	badge.add_theme_constant_override("outline_size", 0)
	
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 0.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_top = 2
	badge.offset_bottom = 10
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


func _on_clicked():
	if map_node.is_visited or not map_node.is_available:
		print("节点已访问或不可用，忽略点击")
		return
	print("地图按钮被点击: ", _get_node_label(map_node))
	if map_scene_ref and map_scene_ref.has_method("on_node_selected"):
		map_scene_ref.on_node_selected(map_node)


func _on_hover_enter():
	if map_scene_ref and map_scene_ref.has_method("show_node_info"):
		map_scene_ref.show_node_info(map_node)


func _on_hover_exit():
	if map_scene_ref and map_scene_ref.has_method("hide_node_info"):
		map_scene_ref.hide_node_info()


func _intensity_badge_text(intensity: int) -> String:
	match intensity:
		1: return "强度I"
		2: return "强度II"
		3: return "强度III"
		_: return ""
