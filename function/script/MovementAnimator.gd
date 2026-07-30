extends Node
class_name MovementAnimator

signal movement_finished(unit)
signal ai_movement_finished(unit)

var move_tween : Tween
var ai_move_tween : Tween

# ---- 根据方向获取动画名 ----
func _get_anim_name(dir: Vector2) -> String:
	if dir == Vector2.ZERO:
		return "idle"
	if abs(dir.x) >= abs(dir.y):
		return "side"
	else:
		return "down" if dir.y > 0 else "up"

# ---- 玩家移动 ----
func play_movement(unit: Unit, path: Array, grid_to_world_func: Callable):
	if not is_instance_valid(unit) or path.is_empty():
		return
	if move_tween and move_tween.is_valid():
		move_tween.kill()

	# 设置第一步方向和动画
	var first_dir = Vector2(path[0].x - unit.grid_cell.x, path[0].y - unit.grid_cell.y)
	unit.set_facing_direction(first_dir)
	unit.play_animation(_get_anim_name(first_dir))

	SoundManager.play_move_sound(unit)
	move_tween = create_tween()
	move_tween.set_parallel(false)

	var positions = []
	for cell in path:
		positions.append(grid_to_world_func.call(cell))

	var step_duration = 0.15
	for i in range(positions.size()):
		var target_pos = positions[i]
		var is_last = (i == positions.size() - 1)
		var next_dir = Vector2.ZERO
		if not is_last:
			var cur_cell = path[i]
			var next_cell = path[i+1]
			next_dir = Vector2(next_cell.x - cur_cell.x, next_cell.y - cur_cell.y)

		move_tween.tween_property(unit, "position", target_pos, step_duration).set_delay(0.0)
		move_tween.tween_callback(_on_step_complete.bind(unit, path[i], is_last, next_dir))

	move_tween.tween_callback(func():
		if is_instance_valid(unit):
			unit.play_animation("idle")
		movement_finished.emit(unit)
		SoundManager.stop_looping()
	)

# ---- AI 移动 ----
func play_ai_movement(unit: Unit, path: Array, grid_to_world_func: Callable, on_ai_finished: Callable = Callable()):
	if not is_instance_valid(unit) or path.is_empty():
		if on_ai_finished.is_valid():
			on_ai_finished.call()
		return
	if ai_move_tween and ai_move_tween.is_valid():
		ai_move_tween.kill()

	var first_dir = Vector2(path[0].x - unit.grid_cell.x, path[0].y - unit.grid_cell.y)
	unit.set_facing_direction(first_dir)
	unit.play_animation(_get_anim_name(first_dir))

	SoundManager.play_move_sound(unit)
	ai_move_tween = create_tween()
	ai_move_tween.set_parallel(false)

	var positions = []
	for cell in path:
		positions.append(grid_to_world_func.call(cell))

	var step_duration = 0.12
	for i in range(positions.size()):
		var target_pos = positions[i]
		var is_last = (i == positions.size() - 1)
		var next_dir = Vector2.ZERO
		if not is_last:
			var cur_cell = path[i]
			var next_cell = path[i+1]
			next_dir = Vector2(next_cell.x - cur_cell.x, next_cell.y - cur_cell.y)

		ai_move_tween.tween_property(unit, "position", target_pos, step_duration).set_delay(0.0)
		ai_move_tween.tween_callback(_on_step_complete.bind(unit, path[i], is_last, next_dir))

	ai_move_tween.tween_callback(func():
		if is_instance_valid(unit):
			unit.play_animation("idle")
		ai_movement_finished.emit(unit)
		if on_ai_finished.is_valid():
			on_ai_finished.call()
		SoundManager.stop_looping()
	)

# ---- 步完成回调（更新格子并设置下一步方向） ----
func _on_step_complete(unit: Unit, cell: Vector2i, is_final: bool, next_dir: Vector2):
	if not is_instance_valid(unit):
		return
	unit.grid_cell = cell
	if is_final:
		unit.update_position(cell)
	else:
		if next_dir != Vector2.ZERO:
			unit.set_facing_direction(next_dir)
			unit.play_animation(_get_anim_name(next_dir))

# ---- 取消移动（仅杀死动画） ----
func cancel_movement():
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	if ai_move_tween and ai_move_tween.is_valid():
		ai_move_tween.kill()
	SoundManager.stop_looping()
