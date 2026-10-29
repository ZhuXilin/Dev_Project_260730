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
			# ★ v4.6：拖到自己 → 自愈
			if _hovered_target == _pressing_unit:
				return "释放左键治疗自身"
			if _hovered_target.unit_stats.team_id == _pressing_unit.unit_stats.team_id:
				return "释放左键回复 HP"
			if _is_target_in_range(_hovered_target):
				return "释放左键攻击"
			return "释放左键移动并攻击"
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

	if unit == null and InputManager.selected_unit != null and is_instance_valid(InputManager.selected_unit):
		unit = InputManager.selected_unit
		var screen_pos = _bf.get_viewport().get_canvas_transform() * unit.global_position
		_bf.get_viewport().warp_mouse(screen_pos)
		_press_start_screen = screen_pos
	else:
		_press_start_screen = _bf.get_viewport().get_mouse_position()

	if unit == null or unit.unit_stats.team_id != 0:
		return false

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
		if hovered_any == _pressing_unit:
			# ★ v4.6：修女拖到自己 → 自愈（仅当自己受伤时）
			var pressing = _pressing_unit
			if pressing.get_weapon_type() == "staff" \
					and pressing.hit_points < pressing.unit_stats.max_hp:
				# 保留 hovered_any（自己），走治疗流程
				pass
			else:
				hovered_any = null

		if hovered_any != null:
			if not _is_valid_target(hovered_any):
				SoundManager.play_cancel_sound()
				SignalBus.request_hint_override.emit("操作失败", 1.0)
				_cancel()
				_reset_state()
				return true

			if _is_target_in_range(hovered_any):
				_execute_attack_or_heal(hovered_any)
				_reset_state()
				return true

			var path = _find_attack_path(hovered_any)
			if path.size() > 0:
				_execute_move_and_attack(path, hovered_any)
				_reset_state()
				return true
				
			# ★ 打不到敌人时，自动寻找离该敌人最近的可达格子并移动过去（只传1个参数）
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
		# ★ v4.6：修女拖到自己 → 自愈目标（仅当自己受伤时）
		var pressing = _pressing_unit
		if pressing.get_weapon_type() == "staff" \
				and pressing.hit_points < pressing.unit_stats.max_hp:
			# 保留 hovered（自己），走治疗流程
			pass
		else:
			hovered = null
	
	if hovered != null:
		var is_valid = _is_valid_target(hovered)
		
		# ★ 核心修改：只要目标合法（比如是敌人），就视为悬停目标，直接显示预估面板
		# （即便移动过去也够不着，玩家也需要看伤害来做战斗计划）
		var new_target : Unit = hovered if is_valid else null

		if new_target != null and _hovered_target != new_target:
			SoundManager.play_select_sound()
		_hovered_target = new_target
		_mouse_out_of_range = false

		if new_target != null:
			# 只要悬停在敌军上，无论能否打得到，都弹出伤害预估面板
			_bf.show_damage_preview(_pressing_unit, new_target)
			
			# 因为够不着（或者不想走过去），所以隐藏路径箭头
			_current_target_cell = cell
			_current_path = []
			_arrow.hide_path()
		return

	_hovered_target = null
	_bf.hide_damage_preview() # ★ 鼠标移出敌人，立刻隐藏

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

	# 如果当前路径为空（说明拖到了不可达的空地）
	if _current_target_cell != unit.grid_cell and _current_path.is_empty():
		# ★ 寻找最近的可达格（这里原来传了2个参数，修正为传1个）
		var closest_cell = _find_closest_reachable_cell(_current_target_cell)
		if closest_cell != unit.grid_cell:
			var path = UnitManager.calculate_path(unit.grid_cell, closest_cell, unit)
			if path.size() > 0:
				SignalBus.request_clear_highlight.emit()
				InputManager.interaction_phase = InputManager.Phase.IDLE
				InputManager.selected_unit = null
				TurnManager.start_movement(unit, path)
				return
				
	# 如果原地，或者找不到路径，取消操作
	if _current_target_cell == unit.grid_cell or _current_path.is_empty():
		InputManager.interaction_phase = InputManager.Phase.IDLE
		InputManager.selected_unit = null
		SignalBus.request_clear_highlight.emit()
		return
		
	# 正常路径移动
	SignalBus.request_clear_highlight.emit()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null
	TurnManager.start_movement(unit, _current_path)

# 新增辅助函数：找离目标最近的可达格
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

# 新增辅助函数：仅执行移动（不触发攻击）
func _execute_move_only(path: Array):
	SignalBus.request_clear_highlight.emit()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null
	TurnManager.start_movement(_pressing_unit, path)


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
	if _bf:
		_bf.hide_damage_preview() # ★ 核心调用：强制清理面板

# ============================================================
#  攻击 / 治疗判定
# ============================================================
func _is_target_in_range(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false
	var weapon = unit.get_weapon_data()
	if not weapon: return false
	# ★ 使用升级后的有效射程
	var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
	var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(weapon, up_lv)
	var dist = abs(unit.grid_cell.x - target.grid_cell.x) \
			+ abs(unit.grid_cell.y - target.grid_cell.y)
	return dist >= weapon.min_attack_range and dist <= max_range


func _is_valid_target(target : Unit) -> bool:
	var unit = _pressing_unit
	if unit == null or target == null: return false
	if unit.get_weapon_type() == "staff":
		return true   # ★ 友军治疗 / 敌军攻击
	return target.unit_stats.team_id != unit.unit_stats.team_id
	

func _find_attack_path(target : Unit) -> Array:
	var unit = _pressing_unit
	if unit == null: return []
	var weapon = unit.get_weapon_data()
	if not weapon: return []

	var min_range : int = weapon.min_attack_range
	# ★ 同上：升级后射程
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


func _execute_attack_or_heal(target : Unit) -> void:
	var unit = _pressing_unit
	if unit == null or not is_instance_valid(unit): return
	if target == null or not is_instance_valid(target): return

	SignalBus.request_clear_highlight.emit()
	_bf.highlight_manager.clear_highlight()
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.selected_unit = null

	if _bf:
		_bf.hide_damage_preview()

	_show_attack_menu(unit, target, false)
	

func _do_combat_async(attacker : Unit, defender : Unit, forced_skill_id: String = ""):
	await CombatManager.execute_attack(attacker, defender, forced_skill_id)


# ★ 核心修改：先移动，再弹窗
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


# 攻击方式选择菜单
func _show_attack_menu(attacker: Unit, target: Unit, is_after_move: bool) -> void:
	# ★ v4.6：自愈时跳过技能菜单，直接走 _execute_heal
	if attacker == target:
		call_deferred("_do_combat_async", attacker, target, "")
		return

	# ★ v4.6：白名单，治疗 / 增益类技能只能对友军释放
	var ally_only_effects : Array = ["heal", "buff"]
	var target_is_ally : bool = (target.unit_stats.team_id == attacker.unit_stats.team_id)

	var ready_skills = TalentManager.get_ready_active_skills(attacker)
	var available_skills = []
	for sid in ready_skills:
		var sdata = TalentManager.get_talent_data(sid)
		if sdata == null:
			continue
		# ★ 白名单过滤
		if sdata.effect_type in ally_only_effects and not target_is_ally:
			continue
		var cost = CombatManager._get_active_skill_cost(sdata)
		if SoulFireManager.can_spend(cost):
			available_skills.append(sdata)

	# 如果没有任何可用技能，或者玩家魂火不足，直接执行普攻
	if available_skills.is_empty():
		call_deferred("_do_combat_async", attacker, target, "")
		return

	# 构建菜单
	var popup := PopupMenu.new()
	
	# ★ 核心修改：统一 8bit 风格和字体
	var stylebox = load(Config.PATHS.STYLEBOX_8BIT)
	if stylebox:
		popup.add_theme_stylebox_override("panel", stylebox)
	popup.add_theme_font_size_override("font_size", UIConst.FONT_SIZE_NORMAL)
	popup.add_theme_constant_override("v_separation", 4)
	popup.add_theme_constant_override("h_separation", 4)
	
	_bf.add_child(popup)

	popup.add_item("普通攻击 (无消耗)", 0)

	for i in range(available_skills.size()):
		var sdata = available_skills[i]
		var cost = CombatManager._get_active_skill_cost(sdata)
		popup.add_item("%s (消耗 %d 魂火)" % [sdata.display_name, cost], i + 1)
		popup.set_item_metadata(i + 1, sdata.id)

	# ★ 核心修复：用字典记录状态，绕过 GDScript lambda 的值捕获限制
	var state = {"confirmed": false}

	popup.id_pressed.connect(func(id):
		state["confirmed"] = true
		var chosen_skill_id = ""
		if id > 0:
			chosen_skill_id = popup.get_item_metadata(id)

		popup.queue_free()
		call_deferred("_do_combat_async", attacker, target, chosen_skill_id)
	)

	popup.popup_hide.connect(func():
		if not state["confirmed"]:
			# 如果玩家点空白处取消
			popup.queue_free()
			if is_after_move:
				# 因为已经走过去了，为了不让玩家白白浪费移动，直接默认普攻
				call_deferred("_do_combat_async", attacker, target, "")
			else:
				# 原地取消，不做任何操作（回合尚未结束，玩家可以继续选中他）
				pass
	)

	# 在鼠标当前位置弹出
	var mouse_pos = _bf.get_viewport().get_mouse_position()
	popup.position = Vector2i(mouse_pos)
	popup.popup()


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
