class_name DragMoveController
extends Node

# ============================================================
#  DragMoveController — 拖拽移动控制器
# ============================================================

const DRAG_THRESHOLD : float = 4.0

var _bf : Node2D
var _arrow : MoveArrowRenderer

var _hovered_target : Unit = null
var _is_pressing : bool = false
var _is_dragging : bool = false
var _pressing_unit : Unit = null
var _press_start_screen : Vector2 = Vector2.ZERO
var _current_target_cell : Vector2i = Vector2i(-1, -1)
var _reachable : Dictionary = {}
var _current_path : Array = []
var _last_sound_time : float = 0.0


func _init(bf: Node2D):
	_bf = bf


func setup():
	_arrow = MoveArrowRenderer.new()
	_arrow.name = "MoveArrowRenderer"
	_bf.add_child(_arrow)


# ============================================================
#  窗口事件：鼠标移出时取消拖拽
# ============================================================
func _notification(what):
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		if _is_dragging or _is_pressing:
			_cancel()


# ============================================================
#  输入入口
# ============================================================
func handle_input(event: InputEvent) -> bool:
	if not _can_handle():
		return false

	# ---- ESC 取消 ----
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and (_is_dragging or _is_pressing):
			_cancel()
			get_viewport().set_input_as_handled()
			return true
		return false

	if event is InputEventMouseButton:
		var mb : InputEventMouseButton = event

		# 拖拽中吞掉中键 / 滚轮
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
	if Globals.is_dialogue_active or Globals.is_item_get_popup_active or Globals.is_equip_menu_active:
		return false
	if InputManager.interaction_phase == InputManager.Phase.MOVING:
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
	if not unit.can_act_this_turn:
		return false
	if unit.has_attacked or unit.has_acted:
		return false
	if unit.remaining_move <= 0:
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
			_start_drag()
		else:
			return true   # 消费，避免被原逻辑当作"点击"

	if _is_dragging:
		_update_drag()
		return true
	return false


func _on_left_release() -> bool:
	if not _is_pressing:
		return false

	if _is_dragging:
		# ★ 先检查攻击/治疗
		if _try_attack_or_heal_target():
			_reset_state()
			return true
		# 否则按普通移动处理
		_execute_move()
	else:
		var unit = _pressing_unit
		_reset_state()
		if unit and is_instance_valid(unit):
			SignalBus.request_show_menu.emit(unit)
		return true

	_reset_state()
	return true


func _try_attack_or_heal_target() -> bool:
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit):
		return false
	if _hovered_target == null or not is_instance_valid(_hovered_target):
		return false

	var target = _hovered_target
	var weapon = unit.get_weapon_data()
	if not weapon:
		return false

	# 距离判定：从起始格到目标格
	var dist = abs(unit.grid_cell.x - target.grid_cell.x) \
			+ abs(unit.grid_cell.y - target.grid_cell.y)
	if dist < weapon.min_attack_range or dist > weapon.attack_range:
		return false

	var is_healer = (unit.get_weapon_type() == "staff")
	var target_is_ally = (target.unit_stats.team_id == unit.unit_stats.team_id)

	if is_healer:
		if not target_is_ally: return false
	else:
		if target_is_ally: return false

	# 有效 → 清高亮 + 异步执行战斗
	SignalBus.request_clear_highlight.emit()
	_bf.highlight_manager.clear_highlight()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null

	call_deferred("_do_combat_async", unit, target)
	return true


func _do_combat_async(attacker : Unit, defender : Unit):
	await CombatManager.execute_attack(attacker, defender)


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

	SignalBus.request_hide_menu.emit()
	SignalBus.request_hide_info.emit()   # ★ 隐藏信息面板
	_bf.highlight_manager.show_move_highlight(
		_reachable, MapConst.HIGHLIGHT_MOVE, 0, true)

	_current_target_cell = unit.grid_cell
	_current_path = []
	_arrow.hide_path()

func _update_drag():
	var world_pos = _bf.get_global_mouse_position()
	var cell = _bf.world_to_grid(world_pos)

	# ★ 检测鼠标悬停单位
	var hovered = UnitManager.get_unit_at_cell(cell)
	if hovered == _pressing_unit:
		hovered = null
	_hovered_target = hovered

	# 鼠标在单位上 → 不走移动路径，只更新攻击范围预览
	if hovered != null:
		_current_target_cell = cell
		_current_path = []
		_arrow.hide_path()
		_update_attack_preview(cell)
		return

	# 鼠标在空格（原逻辑）
	if not _reachable.has(cell):
		return
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

	_update_attack_preview(cell)


func _execute_move():
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit):
		return

	if _current_target_cell == unit.grid_cell or _current_path.is_empty():
		# 没移动 → 恢复菜单
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
	_reachable.clear()
	_current_path.clear()
	_current_target_cell = Vector2i(-1, -1)
	if _arrow:
		_arrow.hide_path()


# ============================================================
#  攻击范围动态预览
# ============================================================
func _update_attack_preview(unit_cell : Vector2i):
	var unit = _pressing_unit
	var weapon = unit.get_weapon_data()
	if not weapon:
		_redraw_highlights({})
		return

	var max_range : int = weapon.attack_range
	var min_range : int = weapon.min_attack_range

	var attack_cells : Dictionary = {}
	for x in range(-max_range, max_range + 1):
		for y in range(-max_range, max_range + 1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range:
				continue
			var c = unit_cell + Vector2i(x, y)
			if c.x < 0 or c.x >= TerrainManager.grid_size.x:
				continue
			if c.y < 0 or c.y >= TerrainManager.grid_size.y:
				continue
			# 排除自身格
			if c == unit_cell:
				continue
			# ★ 不再排除 _reachable，让攻击范围覆盖移动范围
			attack_cells[c] = true

	_redraw_highlights(attack_cells)


func _redraw_highlights(attack_cells: Dictionary):
	var color = MapConst.HIGHLIGHT_ATTACK
	if _pressing_unit and _pressing_unit.get_weapon_type() == "staff":
		color = MapConst.HIGHLIGHT_HEAL
	_bf.highlight_manager.show_enemy_preview(_reachable, attack_cells, color)
