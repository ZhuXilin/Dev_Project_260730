class_name DragMoveController
extends Node

const DRAG_THRESHOLD : float = 4.0
const DOUBLE_CLICK_MS : int = 280

var _bf : Node2D
var _arrow : MoveArrowRenderer

var _is_pressing : bool = false
var _is_dragging : bool = false
var _pressing_unit : Unit = null
var _press_start_screen : Vector2 = Vector2.ZERO
var _current_target_cell : Vector2i = Vector2i(-1, -1)
var _reachable : Dictionary = {}
var _current_path : Array = []
var _hovered_target : Unit = null
var _mouse_out_of_range : bool = false

var _last_click_ms : int = 0
var _last_click_unit : Unit = null


func _init(bf : Node2D):
	_bf = bf


func setup():
	_arrow = MoveArrowRenderer.new()
	_arrow.name = "MoveArrowRenderer"
	_bf.add_child(_arrow)


func is_dragging() -> bool:
	return _is_dragging


func is_mouse_out_of_range() -> bool:
	return _mouse_out_of_range


func get_drag_hint() -> String:
	if not _is_dragging:
		return ""
	if _hovered_target != null:
		var is_healer = (_pressing_unit.get_weapon_type() == "staff")
		if is_healer:
			return "释放左键回复 HP"
		# 判断是原地还是移动后攻击
		if _is_target_in_range(_hovered_target):
			return "释放左键攻击"
		return "释放左键移动并攻击"
	return "释放左键移动"


# ============================================================
#  窗口事件
# ============================================================
func _notification(what):
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		if _is_dragging:
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("操作失败", 1.0)
			_cancel()
		elif _is_pressing:
			_cancel()


# ============================================================
#  输入入口
# ============================================================
func handle_input(event : InputEvent) -> bool:
	if not _can_handle():
		return false

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and (_is_dragging or _is_pressing):
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("已撤销操作", 1.0)
			_cancel()
			get_viewport().set_input_as_handled()
			return true
		return false

	if event is InputEventMouseButton:
		var mb : InputEventMouseButton = event

		if _is_dragging:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				return true
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP \
					or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				return true

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				return _on_left_press()
			else:
				return _on_left_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _is_dragging or _is_pressing:
				# ★ 撤销拖拽：播撤销音 + 提示
				SoundManager.play_cancel_sound()
				SignalBus.request_hint_override.emit("已撤销操作", 1.0)
				_cancel()
				return true
			return false
	elif event is InputEventMouseMotion:
		return _on_mouse_motion()
	return false


func _can_handle() -> bool:
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return false
	if TurnManager.is_game_over or TurnManager.all_acted or TurnManager.is_moving:
		return false
	if Globals.is_fading or Globals.is_transitioning or Globals.is_performing_action:
		return false
	if Globals.is_dialogue_active or Globals.is_item_get_popup_active:
		return false
	return true


# ============================================================
#  按下 / 移动 / 松开
# ============================================================
func _on_left_press() -> bool:
	var world_pos = _bf.get_global_mouse_position()
	var cell = _bf.world_to_grid(world_pos)
	var unit = UnitManager.get_unit_at_cell(cell)

	if unit == null or unit.unit_stats.team_id != 0:
		return false

	_is_pressing = true
	_is_dragging = false
	_pressing_unit = unit
	_press_start_screen = _bf.get_viewport().get_mouse_position()
	return true


func _on_mouse_motion() -> bool:
	if not _is_pressing:
		return false

	if not _is_dragging:
		var curr = _bf.get_viewport().get_mouse_position()
		if curr.distance_to(_press_start_screen) > DRAG_THRESHOLD:
			if not _pressing_unit.can_act_this_turn or _pressing_unit.has_acted:
				return true
			_start_drag()
		else:
			return true

	if _is_dragging:
		_update_drag()
		return true
	return false


func _on_left_release() -> bool:
	if not _is_pressing:
		return false

	if _is_dragging:
		var world_pos = _bf.get_global_mouse_position()
		var cell = _bf.world_to_grid(world_pos)
		var hovered_any = UnitManager.get_unit_at_cell(cell)
		if hovered_any == _pressing_unit:
			hovered_any = null

		if hovered_any != null:
			# ---- 悬停在单位身上 ----
			if not _is_valid_target(hovered_any):
				SoundManager.play_cancel_sound()
				SignalBus.request_hint_override.emit("操作失败", 1.0)
				_cancel()
				_reset_state()
				return true

			# 原地攻击？
			if _is_target_in_range(hovered_any):
				_execute_attack_or_heal(hovered_any)
				_reset_state()
				return true

			# ★ 二合一：移动 + 攻击
			var path = _find_attack_path(hovered_any)
			if path.size() > 0:
				_execute_move_and_attack(path, hovered_any)
				_reset_state()
				return true

			# 都不行
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("操作失败", 1.0)
			_cancel()
			_reset_state()
			return true

		# ---- 悬停在空格 ----
		_execute_move()
		_reset_state()
		return true

	# ---- 纯点击 ----
	var unit = _pressing_unit
	var now := Time.get_ticks_msec()

	if unit == _last_click_unit and unit != null \
			and now - _last_click_ms < DOUBLE_CLICK_MS:
		_last_click_ms = 0
		_last_click_unit = null
		if InputManager.selected_unit == unit \
				and unit.can_act_this_turn and not unit.has_acted:
			_do_wait(unit)
		_reset_state()
		return true

	_last_click_ms = now
	_last_click_unit = unit
	_reset_state()
	if unit and is_instance_valid(unit):
		_do_select(unit)
	return true


# ============================================================
#  单击 / 双击
# ============================================================
func _do_select(unit : Unit):
	_bf.select_unit(unit)


func _do_wait(unit : Unit):
	SoundManager.play_wait_sound()
	TurnManager.finish_unit_action(unit)
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_hide_info.emit()


# ============================================================
#  拖拽
# ============================================================
func _start_drag():
	_is_dragging = true
	var unit = _pressing_unit

	InputManager.selected_unit = unit
	InputManager.interaction_phase = InputManager.Phase.DRAGGING_MOVE

	_reachable = UnitManager.get_reachable_cells(
		unit.grid_cell, unit.remaining_move, unit)

	SignalBus.request_hide_info.emit()
	_bf.highlight_manager.show_move_highlight(
		_reachable, MapConst.HIGHLIGHT_MOVE, 0, true)

	_current_target_cell = unit.grid_cell
	_current_path = []
	_arrow.hide_path()


func _update_drag():
	# 鼠标出视口检查
	var vp_size = _bf.get_viewport().get_visible_rect().size
	var mouse_screen = _bf.get_viewport().get_mouse_position()
	if mouse_screen.x < 0 or mouse_screen.x > vp_size.x \
			or mouse_screen.y < 0 or mouse_screen.y > vp_size.y:
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("操作失败", 1.0)
		_cancel()
		return

	var world_pos = _bf.get_global_mouse_position()
	var cell = _bf.world_to_grid(world_pos)

	var hovered = UnitManager.get_unit_at_cell(cell)
	if hovered == _pressing_unit:
		hovered = null

	# ---- 悬停在单位身上 ----
	if hovered != null:
		var is_valid = _is_valid_target(hovered)
		var can_attack_now = _is_target_in_range(hovered)
		var can_attack_after_move = false

		if is_valid and not can_attack_now:
			can_attack_after_move = (_find_attack_path(hovered).size() > 0)

		var new_target : Unit = hovered if (is_valid and (can_attack_now or can_attack_after_move)) else null

		if new_target != null and _hovered_target != new_target:
			SoundManager.play_select_sound()
		_hovered_target = new_target
		_mouse_out_of_range = false

		if new_target != null:
			_current_target_cell = cell
			_current_path = []
			_arrow.hide_path()
			# 红格保持上一帧（最后一次经过空格时的范围）
		return

	# ---- 悬停在空格 ----
	_hovered_target = null

	if not _reachable.has(cell):
		_mouse_out_of_range = true
		return

	_mouse_out_of_range = false

	if cell == _current_target_cell:
		return

	_current_target_cell = cell
	SoundManager.play_select_sound()

	if cell == _pressing_unit.grid_cell:
		_current_path = []
		_arrow.hide_path()
	else:
		_current_path = UnitManager.calculate_path(
			_pressing_unit.grid_cell, cell, _pressing_unit)
		_arrow.show_path(_pressing_unit.grid_cell, _current_path, _bf.grid_to_world)

	_update_attack_preview(cell, false)


func _execute_move():
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit):
		return

	if _current_target_cell == unit.grid_cell or _current_path.is_empty():
		InputManager.interaction_phase = InputManager.Phase.IDLE
		InputManager.selected_unit = null
		SignalBus.request_clear_highlight.emit()
		return

	SignalBus.request_clear_highlight.emit()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null
	TurnManager.start_movement(unit, _current_path)


func _cancel():
	_reset_state()
	SignalBus.request_clear_highlight.emit()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null


func _reset_state():
	_is_pressing = false
	_is_dragging = false
	_pressing_unit = null
	_hovered_target = null
	_mouse_out_of_range = false
	_reachable.clear()
	_current_path.clear()
	_current_target_cell = Vector2i(-1, -1)
	if _arrow:
		_arrow.hide_path()


# ============================================================
#  攻击 / 治疗判定
# ============================================================
func _is_target_in_range(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false
	var weapon = unit.get_weapon_data()
	if not weapon: return false
	var dist = abs(unit.grid_cell.x - target.grid_cell.x) \
			+ abs(unit.grid_cell.y - target.grid_cell.y)
	return dist >= weapon.min_attack_range and dist <= weapon.attack_range


func _is_valid_target(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false
	var is_healer = (unit.get_weapon_type() == "staff")
	var same_team = (target.unit_stats.team_id == unit.unit_stats.team_id)
	if is_healer:
		return same_team
	else:
		return not same_team


## 找一条能攻击到 target 的最短路径（移动后能攻击）
## 返回 [] 表示找不到
func _find_attack_path(target : Unit) -> Array:
	var unit = _pressing_unit
	if unit == null: return []
	var weapon = unit.get_weapon_data()
	if not weapon: return []

	var min_range : int = weapon.min_attack_range
	var max_range : int = weapon.attack_range

	var reachable = UnitManager.get_reachable_cells(
		unit.grid_cell, unit.remaining_move, unit)

	var best_path : Array = []
	var best_len : int = 9999

	for cell in reachable.keys():
		if cell == unit.grid_cell: continue
		var dist = abs(cell.x - target.grid_cell.x) + abs(cell.y - target.grid_cell.y)
		if dist < min_range or dist > max_range: continue
		if UnitManager.is_cell_occupied(cell): continue
		var path = UnitManager.calculate_path(unit.grid_cell, cell, unit)
		if path.size() == 0: continue
		if path.size() < best_len:
			best_len = path.size()
			best_path = path

	return best_path


func _execute_attack_or_heal(target : Unit) -> void:
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit): return
	if target == null or not is_instance_valid(target): return

	SignalBus.request_clear_highlight.emit()
	_bf.highlight_manager.clear_highlight()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null

	call_deferred("_do_combat_async", unit, target)


func _do_combat_async(attacker : Unit, defender : Unit):
	await CombatManager.execute_attack(attacker, defender)


## ★ 二合一：先移动，再攻击
func _execute_move_and_attack(path : Array, target : Unit) -> void:
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit): return
	if path.size() == 0: return
	if target == null or not is_instance_valid(target): return

	SignalBus.request_clear_highlight.emit()
	_bf.highlight_manager.clear_highlight()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null

	call_deferred("_do_move_and_attack_async", unit, path, target)


func _do_move_and_attack_async(unit : Unit, path : Array, target : Unit):
	# 1. 移动
	TurnManager.start_movement(unit, path)
	await TurnManager.move_completed

	if not is_instance_valid(unit): return
	if unit.hit_points <= 0: return

	# 2. 攻击
	if is_instance_valid(target) and target.hit_points > 0:
		# 二次确认射程（防止中途状态变化）
		var weapon = unit.get_weapon_data()
		if weapon:
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) \
					+ abs(unit.grid_cell.y - target.grid_cell.y)
			if dist >= weapon.min_attack_range and dist <= weapon.attack_range:
				await CombatManager.execute_attack(unit, target)


# ============================================================
#  攻击范围显示
# ============================================================
func _update_attack_preview(unit_cell : Vector2i, from_self : bool = false):
	var unit = _pressing_unit
	if unit == null: return
	var weapon = unit.get_weapon_data()
	if not weapon:
		_redraw_highlights({})
		return

	var max_range : int = weapon.attack_range
	var min_range : int = weapon.min_attack_range
	var origin_cell : Vector2i = unit.grid_cell if from_self else unit_cell

	var attack_cells : Dictionary = {}
	for x in range(-max_range, max_range + 1):
		for y in range(-max_range, max_range + 1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range:
				continue
			var c = origin_cell + Vector2i(x, y)
			if c.x < 0 or c.x >= TerrainManager.grid_size.x:
				continue
			if c.y < 0 or c.y >= TerrainManager.grid_size.y:
				continue
			if c == origin_cell:
				continue

			var occupant = UnitManager.get_unit_at_cell(c)
			if occupant != null and not UnitManager.is_attack_target_of(unit, occupant):
				continue

			attack_cells[c] = true

	_redraw_highlights(attack_cells)


func _redraw_highlights(attack_cells : Dictionary):
	var color = MapConst.HIGHLIGHT_ATTACK
	if _pressing_unit and _pressing_unit.get_weapon_type() == "staff":
		color = MapConst.HIGHLIGHT_HEAL
	_bf.highlight_manager.show_enemy_preview(_reachable, attack_cells, color)
