extends Camera2D
class_name CameraController

enum FollowMode { MOUSE, UNIT }

var follow_mode : FollowMode = FollowMode.MOUSE
var target_unit : Unit = null
var target_position : Vector2 = Vector2.ZERO   # 类成员变量
var map_rect : Rect2 = Rect2(0, 0, 640, 480)
var paused : bool = false
var grid_size : int = 16
var edge_scroll_margin : int = 80
var scroll_speed : float = 5.0
var smooth_tween : Tween
var _is_smooth_moving : bool = false

func _ready():
	make_current()
	var viewport_size = get_viewport().get_visible_rect().size
	var center = map_rect.position + map_rect.size / 2
	target_position = center - viewport_size / 2
	target_position = _snap_to_grid(target_position)
	global_position = target_position
	print("Camera ready, is_current:", is_current())

func _process(_delta):
	if Globals.is_dialogue_active:
		return

	if paused or _is_smooth_moving:
		return

	# ---- 单位跟随模式 ----
	if follow_mode == FollowMode.UNIT and target_unit and is_instance_valid(target_unit):
		# 直接使用单位位置（格子中心），不进行舍入，避免半格偏移
		var unit_pos = target_unit.global_position
		var clamped_pos = _clamp_camera(unit_pos)
		var move_step = (clamped_pos - global_position) * scroll_speed * _delta
		if move_step.length() > 0 and move_step.length() < 1.0:
			move_step = move_step.normalized() * 1.0
		global_position += move_step
		global_position = _clamp_camera(global_position)
		return

	# ---- 边缘滚动模式 ----
	var viewport = get_viewport()
	var viewport_size = viewport.get_visible_rect().size
	var mouse_pos = viewport.get_mouse_position()

	var move_x = 0.0
	var move_y = 0.0

	if mouse_pos.x < edge_scroll_margin:
		move_x = -1.0 * (1.0 - mouse_pos.x / edge_scroll_margin)
	elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
		move_x = 1.0 * ((mouse_pos.x - (viewport_size.x - edge_scroll_margin)) / edge_scroll_margin)

	if mouse_pos.y < edge_scroll_margin:
		move_y = -1.0 * (1.0 - mouse_pos.y / edge_scroll_margin)
	elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
		move_y = 1.0 * ((mouse_pos.y - (viewport_size.y - edge_scroll_margin)) / edge_scroll_margin)

	var move_vector = Vector2(move_x, move_y)
	var target_pos = global_position   # 使用局部变量，避免遮蔽类成员

	if move_vector.length() > 0.0:
		var max_offset = grid_size * 2.0
		var move_offset = move_vector.normalized() * max_offset
		var target_world = global_position + move_offset
		target_world = _clamp_camera(target_world)
		target_pos = target_world.round()
	else:
		target_pos = _clamp_camera(global_position).round()

	var step = (target_pos - global_position) * scroll_speed * _delta
	if step.length() > 0 and step.length() < 1.0:
		step = step.normalized() * 1.0
	global_position += step
	global_position = _clamp_camera(global_position).round()

func set_paused(p: bool):
	paused = p

func set_grid_size(size: int):
	grid_size = size

func set_edge_scroll_margin(margin: int):
	edge_scroll_margin = margin

func set_map_boundary(rect: Rect2):
	map_rect = rect
	var viewport_size = get_viewport().get_visible_rect().size
	var center = map_rect.position + map_rect.size / 2
	target_position = center - viewport_size / 2
	target_position = _snap_to_grid(target_position)
	global_position = target_position
	print("Map boundary set:", map_rect)

func force_position(pos: Vector2):
	target_position = _snap_to_grid(pos)
	global_position = target_position

func follow_unit(unit: Unit):
	follow_mode = FollowMode.UNIT
	target_unit = unit
	if unit:
		target_position = unit.global_position

func follow_mouse():
	follow_mode = FollowMode.MOUSE
	target_unit = null

func _clamp_camera(pos: Vector2) -> Vector2:
	var viewport_size = get_viewport().get_visible_rect().size
	var half = viewport_size / 2

	var min_x = map_rect.position.x + half.x
	var max_x = map_rect.position.x + map_rect.size.x - half.x
	var min_y = map_rect.position.y + half.y
	var max_y = map_rect.position.y + map_rect.size.y - half.y

	# 地图小于视口时居中
	if map_rect.size.x < viewport_size.x:
		min_x = map_rect.position.x + map_rect.size.x / 2
		max_x = min_x
	else:
		if max_x < min_x:
			min_x = map_rect.position.x
			max_x = map_rect.position.x + map_rect.size.x

	if map_rect.size.y < viewport_size.y:
		min_y = map_rect.position.y + map_rect.size.y / 2
		max_y = min_y
	else:
		if max_y < min_y:
			min_y = map_rect.position.y
			max_y = map_rect.position.y + map_rect.size.y

	# 返回钳位后的位置，但不对齐网格（由调用者决定）
	return Vector2(
		clamp(pos.x, min_x, max_x),
		clamp(pos.y, min_y, max_y)
	)

func _snap_to_grid(pos: Vector2) -> Vector2:
	return Vector2(round(pos.x / grid_size) * grid_size, round(pos.y / grid_size) * grid_size)

func smooth_move_to(target: Vector2, duration: float, restore_follow_mouse: bool = false):
	if smooth_tween and smooth_tween.is_valid():
		smooth_tween.kill()
	# 对齐到网格
	target = _snap_to_grid(target)
	target = _clamp_camera(target)
	_is_smooth_moving = true
	smooth_tween = create_tween()
	smooth_tween.tween_property(self, "global_position", target, duration).set_ease(Tween.EASE_IN_OUT)
	smooth_tween.tween_callback(func():
		_is_smooth_moving = false
		# 仅做边界钳位，不再对齐（已对齐）
		global_position = _clamp_camera(global_position)
		if restore_follow_mouse:
			follow_mouse()
	)

func cancel_smooth_move():
	if smooth_tween and smooth_tween.is_valid():
		smooth_tween.kill()
		smooth_tween = null
	_is_smooth_moving = false
	follow_mouse()

func clamp_position(pos: Vector2) -> Vector2:
	return _clamp_camera(pos)
