extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

var _icon_rect: TextureRect = null

func setup(node_data: MapNode, map_scene: CanvasLayer, override_pos: Vector2 = Vector2.INF):
	map_node = node_data
	map_scene_ref = map_scene
	
	text = ""
	disabled = false 
	
	size = MapConst.MAP_NODE_SIZE
	var pos : Vector2 = override_pos if override_pos != Vector2.INF else node_data.position
	position = pos - size / 2
	
	var empty_sb := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty_sb)
	add_theme_stylebox_override("pressed", empty_sb)
	add_theme_stylebox_override("hover", empty_sb)
	add_theme_stylebox_override("disabled", empty_sb)
	add_theme_stylebox_override("focus", empty_sb)

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	if pressed.is_connected(_on_clicked): pressed.disconnect(_on_clicked)
	pressed.connect(_on_clicked)
	if mouse_entered.is_connected(_on_hover_enter): mouse_entered.disconnect(_on_hover_enter)
	if mouse_exited.is_connected(_on_hover_exit): mouse_exited.disconnect(_on_hover_exit)
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)

	_ensure_icon()
	_update_icon_visual(node_data)
	_add_objective_badge(node_data)

func _ensure_icon():
	if _icon_rect == null or not is_instance_valid(_icon_rect):
		_icon_rect = TextureRect.new()
		_icon_rect.name = "IconRect"
		# ★ 核心：尺寸稍微放大2像素，给外描边留空间
		_icon_rect.size = MapConst.MAP_NODE_SIZE + Vector2(2, 2)
		_icon_rect.position = Vector2(-1, -1) # 居中
		_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon_rect.pivot_offset = _icon_rect.size / 2.0
		
		var mat := ShaderMaterial.new()
		mat.shader = load("res://content/resource/shader/pixel_outline.gdshader")
		_icon_rect.material = mat
		
		add_child(_icon_rect)

func _update_icon_visual(node: MapNode):
	var tex = MapConst.get_node_texture(node.node_type, node.hidden_node_type)
	if tex:
		_icon_rect.texture = tex
	else:
		var img := Image.create(int(MapConst.MAP_NODE_SIZE.x), int(MapConst.MAP_NODE_SIZE.y), false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
		_icon_rect.texture = ImageTexture.create_from_image(img)
	
	_icon_rect.visible = true
	_icon_rect.scale = Vector2.ONE
	_icon_rect.modulate = Color.WHITE # 绝不变灰！

	var mat : ShaderMaterial = _icon_rect.material
	# ★ 核心：不改变图标颜色，只改变描边颜色
	if node.is_visited or node.is_passed:
		mat.set_shader_parameter("outline_color", Color(0.5, 0.5, 0.5, 1.0)) # 已访问，深灰半透明
	elif not node.is_available:
		mat.set_shader_parameter("outline_color", Color(1.0, 1.0, 1.0, 1.0)) # 不可用，暗灰
	else:
		mat.set_shader_parameter("outline_color", Color(1.0, 0.6, 0.2, 1.0)) # 可用，亮黄色！

func _on_clicked():
	if map_node.is_visited or map_node.is_passed or not map_node.is_available:
		return
	if map_scene_ref and map_scene_ref.has_method("on_node_selected"):
		map_scene_ref.on_node_selected(map_node)

func _on_hover_enter():
	if map_node.is_available and not map_node.is_visited and not map_node.is_passed:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		z_index = 10
		var tw = create_tween()
		tw.tween_property(_icon_rect, "scale", Vector2(1.15, 1.15), 0.1)
		# 悬停时，把黄边变得更亮
		var mat : ShaderMaterial = _icon_rect.material
		tw.tween_method(func(val): mat.set_shader_parameter("outline_color", val), Color(1.0, 0.6, 0.2, 1.0), Color(1.0, 0.6, 0.2, 1.0), 0.1)
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		
	if map_scene_ref and map_scene_ref.has_method("show_node_info"):
		map_scene_ref.show_node_info(map_node)

func _on_hover_exit():
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	z_index = 0
	var tw = create_tween()
	tw.tween_property(_icon_rect, "scale", Vector2.ONE, 0.1)
	_update_icon_visual(map_node)
	
	if map_scene_ref and map_scene_ref.has_method("hide_node_info"):
		map_scene_ref.hide_node_info()

# （保留原本的 _add_objective_badge 等，但偏移位置稍微调一下）
func _add_objective_badge(node: MapNode):
	var existing = get_node_or_null("ObjectiveBadge")
	if existing: existing.queue_free()
	if node == null or node.node_type == MapNode.NodeType.QUESTION: return
	if node.map_data == null: return
	var parts : Array = []
	var int_text : String = _intensity_badge_text(node.map_data.intensity)
	if int_text != "": parts.append(int_text)
	var obj_text : String = _objective_badge_text(node.map_data.objective_type)
	if obj_text != "": parts.append(obj_text)
	if node.map_data.max_waves > 1:
		if node.map_data.reinforcement_count > 0: parts.append("波%d+援%d" % [node.map_data.max_waves, node.map_data.reinforcement_count])
		else: parts.append("波%d" % node.map_data.max_waves)
	if node.map_data.reward_multiplier > 1.0: parts.append("×%.1f" % node.map_data.reward_multiplier)
	if parts.is_empty(): return
	var badge := Label.new()
	badge.name = "ObjectiveBadge"
	badge.text = "·".join(parts)
	badge.add_theme_font_size_override("font_size", 6)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 2)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.anchor_left = 0.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_top = 2
	badge.offset_bottom = 12
	badge.offset_left = -10
	badge.offset_right = 10
	add_child(badge)

func _objective_badge_text(t: int) -> String:
	match t:
		MapData.ObjectiveType.CAPTURE: return "占"
		MapData.ObjectiveType.FLAG: return "旗"
		MapData.ObjectiveType.ASSAULT: return "突"
		_: return ""

func _intensity_badge_text(intensity: int) -> String:
	match intensity:
		1: return "I"
		2: return "II"
		3: return "III"
		_: return ""
