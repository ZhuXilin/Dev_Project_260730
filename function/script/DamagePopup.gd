extends Label

# ============================================================
#  DamagePopup — 伤害跳字（NES 风格）
#  锚定世界坐标，每帧重算屏幕位置（跟随摄像机）
# ============================================================

const RISE_TIME : float = 0.3
const RISE_DISTANCE : float = 12.0
const HOLD_TIME : float = 0.15
const POPUP_SIZE : Vector2 = Vector2(60, 24)

# ★ 世界坐标 + 上浮偏移
var _world_pos : Vector2 = Vector2.ZERO
var _rise_offset : float = 0.0


func setup(world_pos: Vector2, damage: int, is_crit: bool, is_miss: bool, is_heal: bool):
	_world_pos = world_pos

	z_index = 100
	z_as_relative = false

	add_theme_font_size_override("font_size", 12)
	add_theme_constant_override("outline_size", 3)
	add_theme_color_override("font_outline_color", Color.BLACK)

	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	custom_minimum_size = POPUP_SIZE
	size = POPUP_SIZE

	if is_heal:
		text = "+" + str(damage)
		self_modulate = Color(0.4, 1.0, 0.4)
	elif is_miss:
		text = "miss"
		self_modulate = Color.WHITE
	elif is_crit:
		text = str(damage)
		self_modulate = Color(1.0, 0.35, 0.35)
	else:
		text = str(damage)
		self_modulate = Color(1.0, 0.95, 0.4)

	# 首帧立即定位
	_update_screen_position()

	# 上浮：只改 _rise_offset，_process 每帧重算屏幕位置
	var tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_method(_set_rise_offset, 0.0, -RISE_DISTANCE, RISE_TIME)
	await tween.finished

	await get_tree().create_timer(HOLD_TIME, true, false, true).timeout

	if is_instance_valid(self):
		queue_free()


func _process(_delta):
	# 每帧重算屏幕坐标 → 跟随摄像机
	_update_screen_position()


func _set_rise_offset(v: float):
	_rise_offset = v
	_update_screen_position()


func _update_screen_position():
	var vp := get_viewport()
	if vp == null:
		return
	var canvas_xform := vp.get_canvas_transform()
	var screen_pos := canvas_xform * _world_pos
	position = screen_pos - POPUP_SIZE / 2 + Vector2(0, -12 + _rise_offset)
