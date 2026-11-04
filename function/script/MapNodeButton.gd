extends Button
class_name MapNodeButton

@export var map_node: MapNode
var map_scene_ref: CanvasLayer

var _icon_rect: TextureRect = null


func setup(node_data: MapNode, map_scene: CanvasLayer, override_pos: Vector2 = Vector2.INF):
	map_node = node_data
	map_scene_ref = map_scene
	
	# ★ 清空 Button 自带的文字
	text = ""

	size = MapConst.MAP_NODE_SIZE
	var pos : Vector2 = override_pos if override_pos != Vector2.INF else node_data.position
	position = pos - size / 2
	disabled = not node_data.is_available
	
	# ★ 核心：剥离原本的 StyleBox 背景，设为纯透明
	var empty_sb := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty_sb)
	add_theme_stylebox_override("pressed", empty_sb)
	add_theme_stylebox_override("hover", empty_sb)
	add_theme_stylebox_override("disabled", empty_sb)
	add_theme_stylebox_override("focus", empty_sb)

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 信号连接
	if pressed.is_connected(_on_clicked):
		pressed.disconnect(_on_clicked)
	pressed.connect(_on_clicked)

	if mouse_entered.is_connected(_on_hover_enter):
		mouse_entered.disconnect(_on_hover_enter)
	if mouse_exited.is_connected(_on_hover_exit):
		mouse_exited.disconnect(_on_hover_exit)
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)

	# ★ 创建/更新 图标
	_ensure_icon()
	_update_icon_visual(node_data)

	# 在图片正下方添加战斗目标徽章（如果有）
	_add_objective_badge(node_data)


func _ensure_icon():
	if _icon_rect == null or not is_instance_valid(_icon_rect):
		_icon_rect = TextureRect.new()
		_icon_rect.name = "IconRect"
		_icon_rect.size = MapConst.MAP_NODE_SIZE
		_icon_rect.position = Vector2.ZERO
		_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# ★ 核心：设置缩放中心为图片中心，以便悬停时向四周放大
		_icon_rect.pivot_offset = MapConst.MAP_NODE_SIZE / 2.0
		
		var mat := ShaderMaterial.new()
		mat.shader = load("res://content/resource/shader/pixel_outline.gdshader")
		mat.set_shader_parameter("outline_color", Color.WHITE)
		mat.set_shader_parameter("outline_width", 1)
		mat.set_shader_parameter("outline_enabled", true)
		_icon_rect.material = mat
		
		add_child(_icon_rect)


func _update_icon_visual(node: MapNode):
	var tex = MapConst.get_node_texture(node.node_type, node.hidden_node_type)
	
	if tex:
		_icon_rect.texture = tex
		_icon_rect.visible = true
	else:
		var img := Image.create(int(MapConst.MAP_NODE_SIZE.x), int(MapConst.MAP_NODE_SIZE.y), false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
		_icon_rect.texture = ImageTexture.create_from_image(img)
		_icon_rect.visible = true

	# ★ 核心：加深变暗程度
	if node.is_visited or node.is_passed:
		# 已访问 / 经过：极暗，接近透明
		_icon_rect.modulate = Color(0.2, 0.2, 0.2, 0.5)
	elif not node.is_available:
		# 不可用（未解锁）：明显暗灰
		_icon_rect.modulate = Color(0.35, 0.35, 0.35, 0.9)
	else:
		# 可用：原色高亮
		_icon_rect.modulate = Color.WHITE

	# 复位缩放
	_icon_rect.scale = Vector2.ONE


func _on_hover_enter():
	# ★ 核心：只在可用且未访问时提供悬停反馈
	if map_node.is_available and not map_node.is_visited and not map_node.is_passed:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		z_index = 10
		
		# 放大并提亮
		var tw = create_tween().set_parallel(true)
		tw.tween_property(_icon_rect, "scale", Vector2(1.15, 1.15), 0.1)
		tw.tween_property(_icon_rect, "modulate", Color(1.3, 1.3, 1.3), 0.1)
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		
	if map_scene_ref and map_scene_ref.has_method("show_node_info"):
		map_scene_ref.show_node_info(map_node)


func _on_hover_exit():
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	z_index = 0
	
	# 恢复原样
	var tw = create_tween().set_parallel(true)
	tw.tween_property(_icon_rect, "scale", Vector2.ONE, 0.1)
	_update_icon_visual(map_node)
	
	if map_scene_ref and map_scene_ref.has_method("hide_node_info"):
		map_scene_ref.hide_node_info()


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
	if int_text != "": parts.append(int_text)

	var obj_text : String = _objective_badge_text(node.map_data.objective_type)
	if obj_text != "": parts.append(obj_text)

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
	badge.text = "·".join(parts) # 缩减间距
	badge.add_theme_font_size_override("font_size", 6)
	
	# 徽章字体：白字黑边，保证在所有地图上都能看清
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 2)
	
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# ★ 核心调整：徽章放在图片正下方
	badge.anchor_left = 0.0
	badge.anchor_right = 1.0
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_top = 0 # 紧贴图片底部
	badge.offset_bottom = 10
	badge.offset_left = -10 # 左右稍微拉宽一点，防止文字截断
	badge.offset_right = 10
	
	add_child(badge)


func _objective_badge_text(t: int) -> String:
	match t:
		MapData.ObjectiveType.CAPTURE: return "占"
		MapData.ObjectiveType.FLAG: return "旗"
		MapData.ObjectiveType.ASSAULT: return "突"
		_: return ""


func _on_clicked():
	if map_node.is_visited or map_node.is_passed or not map_node.is_available:
		return
	if map_scene_ref and map_scene_ref.has_method("on_node_selected"):
		map_scene_ref.on_node_selected(map_node)

func _intensity_badge_text(intensity: int) -> String:
	match intensity:
		1: return "I"
		2: return "II"
		3: return "III"
		_: return ""
