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

var _is_show_original_range : bool = false

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
	
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit): return ""
	
	if _hovered_target != null:
		var target = _hovered_target
		var is_healer = (unit.get_weapon_type() == "staff")
		var is_ally = (target.unit_stats.team_id == unit.unit_stats.team_id)
		
		if is_ally:
			if target.hit_points >= target.unit_stats.max_hp:
				return "不可释放"
			
			if is_healer:
				return "释放左键回复 HP"
			else:
				return "释放左键使用急救"
		else:
			if _is_target_in_range(target):
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
		# ★ v6.17：战斗守卫未通过时，若正处于按下/拖拽状态，必须清理状态，
		#   否则松手事件被吞、_is_pressing 永远为 true，后续所有拖拽都失效。
		#   （攻击 await 链中 is_performing_action 持有较久，快速连点时易触发）
		if _is_pressing or _is_dragging:
			if event is InputEventMouseButton \
					and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_cancel()
				_reset_state()
				return true
			if event is InputEventMouseButton \
					and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel()
				return true
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
	if Globals.is_auto_battle:
		return false
	return true


# ============================================================
#  按下 / 移动 / 松开
# ============================================================
func _on_left_press() -> bool:
	if not _can_handle(): return true
	
	var world_pos = _bf.get_global_mouse_position()
	var cell = _bf.world_to_grid(world_pos)
	var unit = UnitManager.get_unit_at_cell(cell)

	if unit == null and InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		unit = InputManager.selected_unit
		var screen_pos = _bf.get_viewport().get_canvas_transform() * unit.global_position
		_bf.get_viewport().warp_mouse(screen_pos)
		_press_start_screen = screen_pos
	else:
		_press_start_screen = _bf.get_viewport().get_mouse_position()

	if unit == null:
		return false

	if unit.unit_stats.team_id != 0:
		return true

	if not unit.can_act_this_turn or unit.has_acted:
		return true

	_is_pressing = true
	_is_dragging = false
	_pressing_unit = unit
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
		# ★ v6.17：优先用拖拽预览期间锁定的目标（玩家看到"释放左键攻击"的那个单位）。
		#   旧实现在松手瞬间用鼠标位置重算 cell，motion 与 release 是不同事件、
		#   坐标可能微移（相机平滑/震屏时更明显），导致目标变 null 或他人 →
		#   攻击落空或变成移动，表现为"拖拽攻击有时不生效"。
		#   仅当预览目标失效时才回退到按鼠标位置重算。
		var hovered_any : Unit = null
		if is_instance_valid(_hovered_target) and _hovered_target.hit_points > 0:
			hovered_any = _hovered_target
			cell = _hovered_target.grid_cell
		else:
			hovered_any = UnitManager.get_unit_at_cell(cell)

		if hovered_any != null:
			if not _is_valid_target(hovered_any):
				_bf.suppress_range_for_unit(hovered_any)
				SoundManager.play_cancel_sound()
				SignalBus.request_hint_override.emit("操作失败", 1.0)
				_cancel()
				_reset_state()
				return true

			if _is_target_in_range(hovered_any):
				_execute_attack_or_heal(hovered_any)
				_reset_state()
				return true
			
			# 不在射程内
			if hovered_any.unit_stats.team_id == _pressing_unit.unit_stats.team_id:
				# ★ 友军不在射程内：尝试寻找移动过去治疗的路径
				var heal_path = _find_heal_path(hovered_any)
				if heal_path.size() > 0:
					_execute_move_and_heal(heal_path, hovered_any)
					_reset_state()
					return true
				
				# 实在找不到位置
				SoundManager.play_cancel_sound()
				SignalBus.request_hint_override.emit("无法到达施法位置", 1.0)
				_cancel()
				_reset_state()
				return true

			# 敌军不在射程内：寻找移动攻击路径
			var path = _find_attack_path(hovered_any)
			if path.size() > 0:
				_execute_move_and_attack(path, hovered_any)
				_reset_state()
				return true
				
			var closest_cell = _find_closest_reachable_cell(hovered_any.grid_cell)
			if closest_cell != _pressing_unit.grid_cell:
				var move_path = UnitManager.calculate_path(_pressing_unit.grid_cell, closest_cell, _pressing_unit)
				if move_path.size() > 0:
					_execute_move_only(move_path)
					_reset_state()
					return true

			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("操作失败", 1.0)
			_cancel()
			_reset_state()
			return true

		_execute_move()
		_reset_state()
		return true

	var unit = _pressing_unit
	var now := Time.get_ticks_msec()

	if unit == _last_click_unit and unit != null \
			and now - _last_click_ms < DOUBLE_CLICK_MS:
		_last_click_ms = 0
		_last_click_unit = null
		if unit.can_act_this_turn and not unit.has_acted:
			_do_wait(unit)
		_reset_state()
		return true

	_last_click_ms = now
	_last_click_unit = unit
	_reset_state()
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

	# ★ v5.9：敌方威胁区只在拖拽开始时按真实棋盘算一次，会话内固定不变
	_bf.refresh_enemy_danger_zones()

	_reachable = UnitManager.get_reachable_cells(
		unit.grid_cell, unit.remaining_move, unit)

	SignalBus.request_hide_info.emit()

	var danger_color = Color(MapConst.HIGHLIGHT_ATTACK.r, MapConst.HIGHLIGHT_ATTACK.g, MapConst.HIGHLIGHT_ATTACK.b, 1.0)
	_bf.highlight_manager.show_move_highlight(
		_reachable, MapConst.HIGHLIGHT_MOVE, 0, true, unit.grid_cell, _filtered_danger(), danger_color)

	_current_target_cell = unit.grid_cell
	_current_path = []
	_arrow.hide_path()

	_update_attack_preview(unit.grid_cell, true)

func _update_drag():
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
	_hovered_target = hovered

	# ★ v5.9：不再按光标位置重算敌方威胁区。
	#   旧逻辑把我方单位临时瞬移到光标格，改变了敌人寻路的占位阻挡，
	#   于是同一批敌人在不同光标位置算出不同危险区，红点跟着漂移。
	#   现在整个拖拽会话共用 _start_drag 里算好的静态表。

	if hovered == null and _bf._enemy_danger_zones.has(cell) and _reachable.has(cell):
		var attackers = _bf._enemy_danger_zones[cell]
		_bf.show_danger_indicators(attackers)
	else:
		_bf.clear_danger_indicators()

	if hovered != null and hovered != _pressing_unit:
		_mouse_out_of_range = false
		_is_show_original_range = false

		_bf.clear_danger_indicators()

		if not _is_valid_target(hovered):
			_bf.hide_damage_preview()
			_current_target_cell = cell
			_current_path = []
			_arrow.hide_path()
			_bf.highlight_manager.show_enemy_preview({}, {}, Color.WHITE, cell, true)
			return

		_bf.show_damage_preview(_pressing_unit, hovered)

		_current_target_cell = cell
		_current_path = []
		_arrow.hide_path()

		var single_cell_dict = {cell: true}

		var is_ally = (hovered.unit_stats.team_id == _pressing_unit.unit_stats.team_id)
		var is_wounded = hovered.hit_points < hovered.unit_stats.max_hp

		var is_healer = (_pressing_unit.get_weapon_type() == "staff")
		var can_emergency = SoulFireManager.can_spend(SoulFireManager.get_emergency_heal_cost())

		var is_heal_action = (is_ally and is_wounded and (is_healer or can_emergency))

		var color = MapConst.HIGHLIGHT_HEAL if is_heal_action else MapConst.HIGHLIGHT_ATTACK
		var danger_color = Color(MapConst.HIGHLIGHT_ATTACK.r, MapConst.HIGHLIGHT_ATTACK.g, MapConst.HIGHLIGHT_ATTACK.b, 1.0)

		_bf.highlight_manager.show_enemy_preview({}, single_cell_dict, color, cell, true, _filtered_danger(), danger_color)
		return

	if hovered == _pressing_unit:
		_hovered_target = null

	_bf.hide_damage_preview()

	if not _reachable.has(cell):
		_mouse_out_of_range = true
		if not _is_show_original_range:
			_is_show_original_range = true
			_bf._show_unit_ranges(_pressing_unit)
		_arrow.hide_path()
		return

	if _mouse_out_of_range or _is_show_original_range:
		_mouse_out_of_range = false
		_is_show_original_range = false
		_current_target_cell = Vector2i(-999, -999)

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

func _redraw_highlights(attack_cells : Dictionary, origin_cell: Vector2i):
	var color = MapConst.HIGHLIGHT_ATTACK
	var danger_color = Color(MapConst.HIGHLIGHT_ATTACK.r, MapConst.HIGHLIGHT_ATTACK.g, MapConst.HIGHLIGHT_ATTACK.b, 1.0)
	
	_bf.highlight_manager.show_enemy_preview(_reachable, attack_cells, color, origin_cell, true, _filtered_danger(), danger_color)


## 威胁区只标注在可移动到的格子上；供所有重绘分支共用同一份口径（v5.9）。
func _filtered_danger() -> Dictionary:
	var out := {}
	for c in _bf._enemy_danger_zones:
		if _reachable.has(c):
			out[c] = _bf._enemy_danger_zones[c]
	return out

func _reset_state():
	_is_pressing = false
	_is_dragging = false
	_pressing_unit = null
	_hovered_target = null
	_mouse_out_of_range = false
	_is_show_original_range = false
	_reachable.clear()
	_current_path.clear()
	_current_target_cell = Vector2i(-1, -1)
	if _arrow:
		_arrow.hide_path()
	if _bf:
		_bf.hide_damage_preview()
		_bf.clear_danger_indicators()

func _execute_move():
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit): return

	var start_cell = unit.grid_cell 

	if _current_target_cell != unit.grid_cell and _current_path.is_empty():
		var closest_cell = _find_closest_reachable_cell(_current_target_cell)
		if closest_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, closest_cell, unit)
			if path.size() > 0:
				_bf.highlight_manager.clear_highlight_split(start_cell, closest_cell)
				InputManager.interaction_phase = InputManager.Phase.IDLE
				InputManager.selected_unit = null
				TurnManager.start_movement(unit, path)
				return
				
	if _current_target_cell == unit.grid_cell or _current_path.is_empty():
		_bf.highlight_manager.clear_highlight_split(start_cell, _current_target_cell)
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("操作失败", 1.0)
		InputManager.interaction_phase = InputManager.Phase.IDLE
		InputManager.selected_unit = null
		return
		
	_bf.highlight_manager.clear_highlight_split(start_cell, _current_target_cell)
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null
	TurnManager.start_movement(unit, _current_path)


func _find_closest_reachable_cell(target_cell: Vector2i) -> Vector2i:
	var best_cell = _pressing_unit.grid_cell
	var min_dist = 9999
	for cell in _reachable.keys():
		if UnitManager.is_cell_occupied(cell) and cell != _pressing_unit.grid_cell:
			continue
		var dist = abs(cell.x - target_cell.x) + abs(cell.y - target_cell.y)
		if dist < min_dist:
			min_dist = dist
			best_cell = cell
	return best_cell


func _execute_move_only(path: Array):
	var end_cell = path[-1] if path.size() > 0 else _pressing_unit.grid_cell
	_bf.highlight_manager.clear_highlight_split(_pressing_unit.grid_cell, end_cell)
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null
	TurnManager.start_movement(_pressing_unit, path)


func _cancel():
	var unit = _pressing_unit
	var t_cell = _current_target_cell
	_reset_state()
	
	if unit and is_instance_valid(unit):
		var final_t_cell = t_cell if t_cell != Vector2i(-1, -1) and t_cell != Vector2i(-999, -999) else unit.grid_cell
		_bf.highlight_manager.clear_highlight_split(unit.grid_cell, final_t_cell)

	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null


# ============================================================
#  攻击 / 治疗判定
# ============================================================
func _is_target_in_range(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false

	var s = unit.unit_stats
	if s.weapon_name == "": return false

	# 与 CombatManager.get_attackable_targets 保持同一口径：就绪主动技能的
	# range_bonus 会临时扩大可攻击范围（如「狙击」+2、「龙息」+1）。
	var skill_bonus : int = CombatManager.get_active_skill_range_bonus(unit)

	if target.unit_stats.team_id == unit.unit_stats.team_id:
		if s.weapon_category == "staff":
			var max_range : int = s.attack_range + unit.bonus_attack_range + skill_bonus
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
			return dist >= s.min_attack_range and dist <= max_range
		else:
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
			return dist <= 1
	else:
		var max_range : int = s.attack_range + unit.bonus_attack_range + skill_bonus
		var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
		return dist >= s.min_attack_range and dist <= max_range

func _is_valid_target(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false

	if target.unit_stats.team_id == unit.unit_stats.team_id:
		return target.hit_points < target.unit_stats.max_hp

	return true

func _find_attack_path(target : Unit) -> Array:
	var unit = _pressing_unit
	if unit == null: return []
	
	var s = unit.unit_stats
	if s.weapon_name == "": return []

	var min_range : int = s.min_attack_range
	var max_range : int = s.attack_range + unit.bonus_attack_range

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

func _find_heal_path(target : Unit) -> Array:
	var unit = _pressing_unit
	if unit == null: return []
	
	var min_range : int = 0
	var max_range : int = 0
	
	var s = unit.unit_stats
	if s.weapon_category == "staff":
		max_range = s.attack_range + unit.bonus_attack_range
		min_range = s.min_attack_range
	else:
		max_range = 1
		min_range = 0

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

	_bf.highlight_manager.clear_highlight_split(unit.grid_cell, target.grid_cell)
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null

	if _bf:
		_bf.hide_damage_preview()

	_show_attack_menu(unit, target, false)


func _do_combat_async(attacker : Unit, defender : Unit, forced_skill_id: String = ""):
	await CombatManager.execute_attack(attacker, defender, forced_skill_id)
	if is_instance_valid(defender):
		_bf.suppress_range_for_unit(defender)


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
	TurnManager.start_movement(unit, path)
	await TurnManager.move_completed

	if not is_instance_valid(unit): return
	if unit.hit_points <= 0: return

	if is_instance_valid(target) and target.hit_points > 0:
		var s = unit.unit_stats
		if s.weapon_name != "":
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) \
					+ abs(unit.grid_cell.y - target.grid_cell.y)
			# ★ v5.9：移动后攻击也要算上就绪主动技能的射程加成（狙击 +2）
			var max_r : int = s.attack_range + unit.bonus_attack_range \
					+ CombatManager.get_active_skill_range_bonus(unit)
			if dist >= s.min_attack_range and dist <= max_r:
				_show_attack_menu(unit, target, true)


func _execute_move_and_heal(path : Array, target : Unit) -> void:
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit): return
	if path.size() == 0: return
	if target == null or not is_instance_valid(target): return

	SignalBus.request_clear_highlight.emit()
	_bf.highlight_manager.clear_highlight()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null

	call_deferred("_do_move_and_heal_async", unit, path, target)

func _do_move_and_heal_async(unit : Unit, path : Array, target : Unit):
	TurnManager.start_movement(unit, path)
	await TurnManager.move_completed

	if not is_instance_valid(unit): return
	if unit.hit_points <= 0: return

	if is_instance_valid(target) and target.hit_points > 0:
		var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
		var in_range = false
		
		var s = unit.unit_stats
		if s.weapon_category == "staff":
			var max_r = s.attack_range + unit.bonus_attack_range
			if dist >= s.min_attack_range and dist <= max_r:
				in_range = true
		else:
			if dist <= 1:
				in_range = true
				
		if in_range:
			_show_attack_menu(unit, target, true)
		else:
			_bf.suppress_range_for_unit(target)
			TurnManager.finish_unit_action(unit)

# 攻击方式选择菜单
func _show_attack_menu(attacker: Unit, target: Unit, _is_after_move: bool) -> void:
	if attacker == target:
		if attacker.hit_points >= attacker.unit_stats.max_hp:
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("自身未受伤", 1.0)
			return
		call_deferred("_do_combat_async", attacker, target, "")
		return

	var is_healer : bool = (attacker.get_weapon_type() == "staff")
	var target_is_ally : bool = (target.unit_stats.team_id == attacker.unit_stats.team_id)
	var target_wounded : bool = target.hit_points < target.unit_stats.max_hp

	var ally_only_effects : Array = ["heal", "buff"]
	var ready_skills = TalentManager.get_ready_active_skills(attacker)
	var available_skills = []
	for sid in ready_skills:
		var sdata = TalentManager.get_talent_data(sid)
		if sdata == null: continue
		if sdata.effect_type in ally_only_effects and not target_is_ally: continue
		var cost = CombatManager._get_active_skill_cost(sdata)
		if SoulFireManager.can_spend(cost):
			available_skills.append(sdata)

	var emergency_cost : int = SoulFireManager.get_emergency_heal_cost()
	var emergency_available : bool = target_is_ally and target_wounded \
		and SoulFireManager.can_spend(emergency_cost)

	var normal_attack_available : bool = not target_is_ally
	var normal_heal_available : bool = is_healer and target_is_ally and target_wounded
	var normal_available : bool = normal_attack_available or normal_heal_available

	# ★ v6.63：魂火爆发并入技能按钮，不再有独立爆发按钮。
	#   魂火 ≥3 时技能自动爆发（见下方技能项文案与 skill_id 替换）。
	var sf_cost : int = SoulFireManager.current
	var will_burst : bool = sf_cost >= SoulFireIdentity.get_burst_threshold()

	# 目标只因主动技能 range_bonus 才可达时（如狙击 +2），禁用普攻，
	# 并且只保留射程加成足以覆盖该距离的技能，避免越距普攻。
	if not target_is_ally:
		var atk_s = attacker.unit_stats
		var base_max : int = atk_s.attack_range + attacker.bonus_attack_range
		var dist : int = abs(attacker.grid_cell.x - target.grid_cell.x) \
			+ abs(attacker.grid_cell.y - target.grid_cell.y)
		if dist > base_max or dist < atk_s.min_attack_range:
			normal_attack_available = false
			normal_available = normal_heal_available
			var ranged_skills : Array = []
			for sd in available_skills:
				var bonus : int = int(sd.effect_params.get("range_bonus", 0))
				if base_max + bonus >= dist:
					ranged_skills.append(sd)
			available_skills = ranged_skills

	var total_options : int = 0
	if normal_available: total_options += 1
	total_options += available_skills.size()
	if emergency_available: total_options += 1

	if total_options == 0:
		if target_is_ally:
			SoundManager.play_cancel_sound()
			if not target_wounded:
				SignalBus.request_hint_override.emit("目标未受伤", 1.0)
			else:
				SignalBus.request_hint_override.emit("魂火不足", 1.0)
			return
		# ★ v5.9：目标只因技能射程加成才够得着、但魂火不足或技能未就绪时，
		#   不能静默回退成普通攻击（会越距且看不出魂火是否消耗）。
		var atk_s0 = attacker.unit_stats
		var base_max0 : int = atk_s0.attack_range + attacker.bonus_attack_range
		var dist0 : int = abs(attacker.grid_cell.x - target.grid_cell.x) \
			+ abs(attacker.grid_cell.y - target.grid_cell.y)
		if dist0 > base_max0:
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("魂火不足或技能未就绪，无法远程攻击", 1.2)
			_on_attack_canceled(attacker)
			return
		call_deferred("_do_combat_async", attacker, target, "")
		return

	if total_options == 1:
		if emergency_available and available_skills.is_empty() \
				and not normal_attack_available and not normal_heal_available:
			call_deferred("_do_emergency_heal_async", attacker, target)
			return
		if available_skills.size() == 1 and not emergency_available \
				and not normal_attack_available and not normal_heal_available:
			var only_skill = available_skills[0]
			var only_heal : bool = str(only_skill.effect_type) == "heal" \
				or (only_skill.effect_params is Dictionary and (only_skill.effect_params as Dictionary).has("heal_multiplier"))
			# ★ v6.63：唯一技能项同样遵循"魂火≥3 自动爆发"
			var final_id : String = "soul_fire_burst" if (will_burst and not target_is_ally and not only_heal) else str(only_skill.id)
			call_deferred("_do_combat_async", attacker, target, final_id)
			return
		call_deferred("_do_combat_async", attacker, target, "")
		return

	var popup := PopupMenu.new()
	var stylebox = load(Config.PATHS.STYLEBOX_8BIT)
	if stylebox:
		popup.add_theme_stylebox_override("panel", stylebox)
	popup.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	popup.add_theme_constant_override("v_separation", 4)
	popup.add_theme_constant_override("h_separation", 4)
	
	Globals.is_attack_menu_active = true
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_bf.add_child(blocker)
	_bf.add_child(popup)

	var state = {"confirmed": false}
	var next_id : int = 0
	var meta_by_id : Dictionary = {}

	if normal_attack_available:
		popup.add_item("普攻", next_id)
		meta_by_id[next_id] = {"kind": "attack", "skill_id": ""}
		next_id += 1

	if normal_heal_available:
		popup.add_item("治疗", next_id)
		meta_by_id[next_id] = {"kind": "attack", "skill_id": ""}
		next_id += 1

	for sdata in available_skills:
		# ★ v6.63c：极简文案——「名称·状态」一个短词，不写满一行。
		#   爆发态只标「·爆发」；普通态只标「·N魂」。伤害/回复数字省略，
		#   玩家要判断的是"这次花几魂 / 会不会爆发"，不是看数值预览。
		var skill_cost : int = CombatManager._get_active_skill_cost(sdata)
		var bursting : bool = will_burst and attacker.unit_stats.team_id == 0
		var skill_text : String = sdata.display_name
		if bursting:
			# ★ v6.64：爆发文案写单位/转职身份（如"横扫击退"/"嘲讽护盾"）
			var label : String = SoulFireIdentity.get_burst_label(
				attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
			skill_text += "·" + label
		else:
			skill_text += "·%d魂" % skill_cost
		popup.add_item(skill_text, next_id)
		meta_by_id[next_id] = {"kind": "attack", "skill_id": sdata.id, "is_skill": true}
		next_id += 1

	# ★ v6.24：把「冷却中 / 魂火不足」的主动技能也列进菜单并灰显，标出原因，
	#   让玩家看懂"技能还在、只是没就绪"，而不是从菜单里凭空消失。
	#   灰显项用独立 kind 占位，不计入 total_options，也不触发任何攻击。
	var equipped_active : Array = []  # [{data, inst}]
	for slot in attacker.talent_slots:
		var slot_inst: TalentInstance = slot as TalentInstance
		if slot_inst and slot_inst.is_active:
			var slot_data = TalentManager.get_talent_data(slot_inst.talent_id)
			if slot_data and slot_data.is_active_skill:
				equipped_active.append({"data": slot_data, "inst": slot_inst})
	var adv_inst: TalentInstance = attacker.advanced_talent_inst as TalentInstance
	if adv_inst and adv_inst.is_active:
		var adv_data = TalentManager.get_talent_data(adv_inst.talent_id)
		if adv_data and adv_data.is_active_skill:
			equipped_active.append({"data": adv_data, "inst": adv_inst})

	var available_ids : Array = []
	for sd in available_skills:
		available_ids.append(sd.id)

	for entry in equipped_active:
		var sd = entry["data"]
		if available_ids.has(sd.id):
			continue  # 已在正常可用列表
		if sd.effect_type in ally_only_effects and not target_is_ally:
			continue  # 治疗/增益对敌人不显示
		var einst: TalentInstance = entry["inst"]
		var reason : String = ""
		if einst.cooldown_remaining > 0:
			reason = "冷%d" % einst.cooldown_remaining
		else:
			reason = "魂火不足"
		popup.add_item("%s·%s" % [sd.display_name, reason], next_id)
		popup.set_item_disabled(popup.item_count - 1, true)
		meta_by_id[next_id] = {"kind": "disabled"}
		next_id += 1

	# ★ v6.34（B4）：Build 觉醒技——攒满 100 能量可主动释放 build 专属大招
	if attacker.unit_stats.team_id == 0:
		var be := CombatManager.get_build_energy(attacker)
		var dom := CombatManager.get_dominant_school(attacker)
		if CombatManager.can_release_build_burst(attacker) and dom != "":
			popup.add_item("★%s觉醒" % dom, next_id)
			meta_by_id[next_id] = {"kind": "build_burst"}
		else:
			popup.add_item("觉醒%d/100" % be, next_id)
			popup.set_item_disabled(popup.item_count - 1, true)
			meta_by_id[next_id] = {"kind": "disabled"}
		next_id += 1

	if emergency_available:
		popup.add_item("急救·%d魂" % emergency_cost, next_id)
		meta_by_id[next_id] = {"kind": "emergency_heal"}
		next_id += 1

	# ★ v6.63：独立「魂火爆发」按钮已移除——爆发并入技能按钮（见上方技能项）。

	popup.id_pressed.connect(func(id):
		var meta : Dictionary = meta_by_id.get(id, {})
		var kind : String = str(meta.get("kind", "attack"))
		if kind == "disabled":
			return   # 灰显的冷却/魂火不足技能不可选
		state["confirmed"] = true
		Globals.is_attack_menu_active = false
		var skill_id : String = str(meta.get("skill_id", ""))
		# ★ v6.63：魂火 ≥3 时技能自动爆发——替换 skill_id，走 CombatManager 统一爆发通道。
		#   仅技能项（is_skill）触发，普攻不自动爆发；治疗技能不触发爆发。
		var picked_skill = TalentManager.get_talent_data(skill_id)
		var is_heal_skill : bool = false
		if picked_skill != null:
			is_heal_skill = str(picked_skill.effect_type) == "heal" \
				or (picked_skill.effect_params is Dictionary and (picked_skill.effect_params as Dictionary).has("heal_multiplier"))
		if bool(meta.get("is_skill", false)) and will_burst and not target_is_ally and not is_heal_skill:
			skill_id = "soul_fire_burst"
		popup.queue_free()
		blocker.queue_free()

		if kind == "emergency_heal":
			call_deferred("_do_emergency_heal_async", attacker, target)
		elif kind == "build_burst":
			call_deferred("_do_build_burst_async", attacker)
		else:
			call_deferred("_do_combat_async", attacker, target, skill_id)
	)

	popup.popup_hide.connect(func():
		if not state["confirmed"]:
			Globals.is_attack_menu_active = false
			popup.queue_free()
			blocker.queue_free()
			_on_attack_canceled(attacker)
	)

	popup.window_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			popup.hide()
			get_viewport().set_input_as_handled()
	)

	blocker.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT:
				popup.hide()
				get_viewport().set_input_as_handled()
	)

	var mouse_pos = _bf.get_viewport().get_mouse_position()
	popup.position = Vector2i(mouse_pos)
	popup.popup()


func _on_attack_canceled(attacker: Unit):
	SoundManager.play_cancel_sound()
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_clear_highlight_unit.emit()
	SignalBus.request_hide_info.emit()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null
	
	if is_instance_valid(attacker):
		_bf.suppress_range_for_unit(attacker)


func _update_attack_preview(unit_cell : Vector2i, from_self : bool = false):
	var unit = _pressing_unit
	if unit == null: return
	
	var s = unit.unit_stats
	if s.weapon_name == "":
		_redraw_highlights({}, _pressing_unit.grid_cell)
		return

	var max_range : int = s.attack_range + unit.bonus_attack_range
	var min_range : int = s.min_attack_range
	var origin_cell : Vector2i = unit.grid_cell if from_self else unit_cell

	var attack_cells : Dictionary = {}
	
	for x in range(-max_range, max_range + 1):
		for y in range(-max_range, max_range + 1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range:
				continue
			var c = origin_cell + Vector2i(x, y)
			
			if c.x < 0 or c.x >= TerrainManager.grid_size.x: continue
			if c.y < 0 or c.y >= TerrainManager.grid_size.y: continue
			if c == origin_cell: continue
			
			var tt = TerrainManager.get_terrain(c)
			if tt == TerrainManager.TerrainType.IMPASSABLE_ALL: continue

			var occ = UnitManager.get_unit_at_cell(c)
			if occ != null and not UnitManager.is_attack_target_of(unit, occ):
				continue
				
			attack_cells[c] = true

	_redraw_highlights(attack_cells, origin_cell)

func _do_emergency_heal_async(attacker : Unit, target : Unit):
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	await CombatManager.execute_emergency_heal(attacker, target)
	if is_instance_valid(target):
		_bf.suppress_range_for_unit(target)


## ★ v6.34（B4）：释放 build 觉醒技并消耗该单位本回合行动
func _do_build_burst_async(attacker : Unit):
	if not is_instance_valid(attacker):
		return
	CombatManager.release_build_burst(attacker)
	if is_instance_valid(attacker):
		attacker.has_attacked = true
		attacker.has_acted = true
		_bf.suppress_range_for_unit(attacker)
