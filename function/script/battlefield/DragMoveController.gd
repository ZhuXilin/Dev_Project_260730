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
	# 只要有任何一个全局锁开启，直接拒绝处理任何输入
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
	# 再次强校验，防止在这极短的瞬间状态被改变
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
		var hovered_any = UnitManager.get_unit_at_cell(cell)

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

	_reachable = UnitManager.get_reachable_cells(
		unit.grid_cell, unit.remaining_move, unit)

	SignalBus.request_hide_info.emit()
	_bf.highlight_manager.show_move_highlight(
		_reachable, MapConst.HIGHLIGHT_MOVE, 0, true, unit.grid_cell)

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
	
	if hovered != null and hovered != _pressing_unit:
		_mouse_out_of_range = false
		_is_show_original_range = false
		
		if _is_valid_target(hovered):
			_bf.show_damage_preview(_pressing_unit, hovered)
		else:
			_bf.hide_damage_preview()
			
		_current_target_cell = cell
		_current_path = []
		_arrow.hide_path()
		
		var single_cell_dict = {cell: true}
		var color = MapConst.HIGHLIGHT_HEAL if hovered.unit_stats.team_id == _pressing_unit.unit_stats.team_id else MapConst.HIGHLIGHT_ATTACK
		
		_bf.highlight_manager.show_enemy_preview({}, single_cell_dict, color, cell, true)
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


# ============================================================
#  攻击 / 治疗判定
# ============================================================
func _is_target_in_range(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false

	if target.unit_stats.team_id == unit.unit_stats.team_id:
		if unit.get_weapon_type() == "staff":
			var weapon = unit.get_weapon_data()
			if not weapon: return false
			var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
			var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(weapon, up_lv)
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
			return dist >= weapon.min_attack_range and dist <= max_range
		else:
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
			return dist <= 1
	else:
		var weapon = unit.get_weapon_data()
		if not weapon: return false
		var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
		var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(weapon, up_lv)
		var dist = abs(unit.grid_cell.x - target.grid_cell.x) + abs(unit.grid_cell.y - target.grid_cell.y)
		return dist >= weapon.min_attack_range and dist <= max_range


func _is_valid_target(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false

	if target.unit_stats.team_id == unit.unit_stats.team_id:
		return target.hit_points < target.unit_stats.max_hp

	return true


func _find_attack_path(target : Unit) -> Array:
	var unit = _pressing_unit
	if unit == null: return []
	var weapon = unit.get_weapon_data()
	if not weapon: return []

	var min_range : int = weapon.min_attack_range
	var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
	var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(weapon, up_lv)

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
	
	if unit.get_weapon_type() == "staff":
		var weapon = unit.get_weapon_data()
		if not weapon: return []
		var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
		max_range = WeaponUpgradeHelper.get_effective_attack_range(weapon, up_lv)
		min_range = weapon.min_attack_range
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
		var weapon = unit.get_weapon_data()
		if weapon:
			var dist = abs(unit.grid_cell.x - target.grid_cell.x) \
					+ abs(unit.grid_cell.y - target.grid_cell.y)
			if dist >= weapon.min_attack_range and dist <= weapon.attack_range:
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
		
		if unit.get_weapon_type() == "staff":
			var weapon = unit.get_weapon_data()
			if weapon:
				var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
				var max_r = WeaponUpgradeHelper.get_effective_attack_range(weapon, up_lv)
				if dist >= weapon.min_attack_range and dist <= max_r:
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
func _show_attack_menu(attacker: Unit, target: Unit, is_after_move: bool) -> void:
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
		call_deferred("_do_combat_async", attacker, target, "")
		return

	if total_options == 1:
		if emergency_available and available_skills.is_empty() \
				and not normal_attack_available and not normal_heal_available:
			call_deferred("_do_emergency_heal_async", attacker, target)
			return
		if available_skills.size() == 1 and not emergency_available \
				and not normal_attack_available and not normal_heal_available:
			call_deferred("_do_combat_async", attacker, target, available_skills[0].id)
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
	_bf.add_child(popup)

	var state = {"confirmed": false}
	var next_id : int = 0
	var meta_by_id : Dictionary = {}

	if normal_attack_available:
		popup.add_item("普通攻击 (无消耗)", next_id)
		meta_by_id[next_id] = {"kind": "attack", "skill_id": ""}
		next_id += 1

	if normal_heal_available:
		popup.add_item("普通治疗 (无消耗)", next_id)
		meta_by_id[next_id] = {"kind": "attack", "skill_id": ""}
		next_id += 1

	for sdata in available_skills:
		var cost : int = CombatManager._get_active_skill_cost(sdata)
		popup.add_item("%s (消耗 %d 魂火)" % [sdata.display_name, cost], next_id)
		meta_by_id[next_id] = {"kind": "attack", "skill_id": sdata.id}
		next_id += 1

	if emergency_available:
		var em_amt : int = CombatManager.get_expected_emergency_heal(attacker, target)
		var actual_em : int = mini(target.hit_points + em_amt, target.unit_stats.max_hp) - target.hit_points
		popup.add_item("急救 (+%d HP，消耗 %d 魂火)" % [actual_em, emergency_cost], next_id)
		meta_by_id[next_id] = {"kind": "emergency_heal"}
		next_id += 1

	popup.id_pressed.connect(func(id):
		state["confirmed"] = true
		var meta : Dictionary = meta_by_id.get(id, {})
		var kind : String = str(meta.get("kind", "attack"))
		var skill_id : String = str(meta.get("skill_id", ""))
		popup.queue_free()

		if kind == "emergency_heal":
			call_deferred("_do_emergency_heal_async", attacker, target)
		else:
			call_deferred("_do_combat_async", attacker, target, skill_id)
	)

	popup.popup_hide.connect(func():
		if not state["confirmed"]:
			popup.queue_free()
			if is_after_move:
				call_deferred("_do_combat_async", attacker, target, "")
	)

	var mouse_pos = _bf.get_viewport().get_mouse_position()
	popup.position = Vector2i(mouse_pos)
	popup.popup()


func _update_attack_preview(unit_cell : Vector2i, from_self : bool = false):
	var unit = _pressing_unit
	if unit == null: return
	var weapon = unit.get_weapon_data()
	if not weapon:
		_redraw_highlights({}, _pressing_unit.grid_cell)
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


func _redraw_highlights(attack_cells : Dictionary, origin_cell: Vector2i):
	var color = MapConst.HIGHLIGHT_ATTACK
	if _pressing_unit and _pressing_unit.get_weapon_type() == "staff":
		color = MapConst.HIGHLIGHT_HEAL
		
	_bf.highlight_manager.show_enemy_preview(_reachable, attack_cells, color, origin_cell, true)


func _do_emergency_heal_async(attacker : Unit, target : Unit):
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	await CombatManager.execute_emergency_heal(attacker, target)
	if is_instance_valid(target):
		_bf.suppress_range_for_unit(target)
