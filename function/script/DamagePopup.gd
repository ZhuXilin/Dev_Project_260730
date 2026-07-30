extends Label

var duration : float = 0.5

func setup(world_pos: Vector2, damage: int, is_crit: bool, is_miss: bool, is_heal: bool):
	z_index = 10
	z_as_relative = false
	
	add_theme_font_size_override("font_size", 12)
	add_theme_constant_override("outline_size", 3)
	add_theme_color_override("font_outline_color", Color.BLACK)
	
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# 固定尺寸
	size = Vector2(50, 25)
	
	if is_heal:
		text = "+" + str(damage)
		self_modulate = Color.GREEN
	elif is_miss:
		text = "miss"
		self_modulate = Color.WHITE
	elif is_crit:
		text = str(damage)
		self_modulate = Color.RED
	else:
		text = str(damage)
		self_modulate = Color.YELLOW
	
	# 设置位置：中心点对齐到 world_pos 上方 28 像素
	global_position = world_pos - Vector2(0, 14) - size / 2
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15).set_delay(duration - 0.15)
	await get_tree().create_timer(duration).timeout
	queue_free()
