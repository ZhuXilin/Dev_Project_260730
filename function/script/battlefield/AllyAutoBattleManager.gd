class_name AllyAutoBattleManager
extends Node

# ============================================================
#  AllyAutoBattleManager — 我方自动战斗流水线
# ============================================================

const ACTION_DELAY       : float = 0.35   # 每单位行动前的思考延迟
const AFTER_ACTION_DELAY : float = 0.40   # 两单位之间的间隔
const TURN_START_DELAY   : float = 0.90   # 等回合切换动画播完
const MAX_WAIT           : float = 5.0    # 有界等待上限
const WAIT_POLL          : float = 0.10   # 等待轮询间隔

var _bf : Node2D = null
var _enemy_ai : EnemyAI = null
var _running : bool = false
var _run_serial : int = 0                  # 协程序列号，用于取消过期执行
var _stuck_timer : float = 0.0


func _init(bf: Node2D):
	_bf = bf


func _ready():
	_enemy_ai = TurnManager.enemy_ai
	SignalBus.turn_changed.connect(_on_turn_changed)


# ============================================================
#  外部接口
# ============================================================
func set_enabled(v: bool) -> void:
	if v:
		if TurnManager.is_game_over:
			return
		Globals.is_auto_battle = true
		if TurnManager.current_turn_team == TurnManager.Team.PLAYER:
			if not _running:
				_start_player_turn_auto()
		else:
			SignalBus.request_hint_override.emit("自动战斗已开启，下回合生效", 1.5)
	else:
		Globals.is_auto_battle = false
		if _running:
			_run_serial += 1
			_running = false
		SignalBus.request_hint_override.emit("自动战斗 关闭", 1.5)


func cancel() -> void:
	Globals.is_auto_battle = false
	_run_serial += 1
	_running = false


# ============================================================
#  回合切换监听
# ============================================================
func _on_turn_changed(team: int) -> void:
	if team == TurnManager.Team.PLAYER:
		if Globals.is_auto_battle and not _running:
			_start_player_turn_auto()
	else:
		if _running:
			_run_serial += 1
			_running = false


# ============================================================
#  主流水线
# ============================================================
func _start_player_turn_auto() -> void:
	if _running: return
	_running = true
	_run_serial += 1
	var my_serial : int = _run_serial

	if _enemy_ai and _enemy_ai.has_method("begin_ally_turn_focus"):
		_enemy_ai.begin_ally_turn_focus()

	_clear_player_interaction_state()

	await get_tree().create_timer(TURN_START_DELAY, true, false, true).timeout
	if my_serial != _run_serial: return

	var waited : float = 0.0
	while not _should_continue():
		if my_serial != _run_serial: return
		if not Globals.is_auto_battle: _running = false; return
		if TurnManager.is_game_over: _running = false; return
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
			_running = false; return
		if waited >= MAX_WAIT:
			push_warning("[AutoBattle] 等待超时，本回合跳过（开关保留）")
			_running = false; return
		await get_tree().create_timer(WAIT_POLL, true, false, true).timeout
		waited += WAIT_POLL
		if my_serial != _run_serial: return

	# 主循环
	while true:
		if my_serial != _run_serial: break
		if not Globals.is_auto_battle: break
		if TurnManager.is_game_over: break
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER: break
		
		# ★ 防止死锁：如果系统认为在移动，但实际上卡住了，强制解锁
		if TurnManager.is_moving:
			_stuck_timer += 0.1
			if _stuck_timer > 2.0: # 2秒还在移动，视为卡死
				TurnManager.is_moving = false
				TurnManager.is_ai_moving = false
				SignalBus.request_clear_highlight.emit()
				push_warning("[AutoBattle] 检测到移动卡死，强制解锁")
				_stuck_timer = 0.0
			await get_tree().create_timer(0.1, true, false, true).timeout
			continue
		else:
			_stuck_timer = 0.0

		var unit := _pick_next_actor()
		if unit == null: break
		await _act_one_unit(unit)
		if my_serial != _run_serial: break
		await get_tree().create_timer(AFTER_ACTION_DELAY, true, false, true).timeout

	_running = false
	if my_serial != _run_serial: return
	if not Globals.is_auto_battle: return
	if TurnManager.is_game_over: return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER: return

	for u in UnitManager.unit_list:
		if is_instance_valid(u) and u.hit_points > 0 \
				and u.unit_stats.team_id == 0 and u.can_act_this_turn:
			TurnManager.finish_unit_action(u)


# ============================================================
#  条件
# ============================================================
func _should_continue() -> bool:
	if not is_instance_valid(self): return false
	if TurnManager.is_game_over: return false
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER: return false
	if not Globals.is_auto_battle: return false
	if TurnManager.is_moving or TurnManager.is_ai_moving: return false
	if Globals.is_performing_action: return false
	if Globals.is_dialogue_active or Globals.is_item_get_popup_active: return false
	if Globals.is_fading or Globals.is_transitioning: return false
	if _bf and _bf.victory_panel.visible: return false
	return true


func _pick_next_actor() -> Unit:
	for u in UnitManager.unit_list:
		if u == null or not is_instance_valid(u): continue
		if u.unit_stats.team_id != 0: continue
		if u.hit_points <= 0: continue
		if not u.can_act_this_turn: continue
		if u.has_acted: continue
		return u
	return null


# ============================================================
#  单单位执行
# ============================================================
func _act_one_unit(unit: Unit) -> void:
	if _enemy_ai == null or not is_instance_valid(unit):
		_finish_unit(unit)
		return

	await get_tree().create_timer(ACTION_DELAY, true, false, true).timeout
	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return

	# 等待对话（转阶段 / 死亡对话等）
	while Globals.is_dialogue_active:
		await get_tree().process_frame
		if not is_instance_valid(self): return
		if not is_instance_valid(unit) or unit.hit_points <= 0: return
		if not Globals.is_auto_battle: return
		if TurnManager.is_game_over: return
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER: return

	# 1. 优先检查急救
	if await _try_ai_emergency_heal(unit):
		return

	# 2. 正常决策
	var act : Dictionary = _enemy_ai.decide_action_for(unit)

	if str(act.get("type", "")) == "attack":
		_record_focus(unit, act.get("target", null))

	match str(act.get("type", "wait")):
		"attack":
			var target = act.get("target", null)
			# ★ 新增：如果决策的目标已经死了，立刻重新决策一次
			if not is_instance_valid(target) or target.hit_points <= 0:
				var retry_act = _enemy_ai.decide_action_for(unit)
				if retry_act and retry_act["type"] != "wait":
					if retry_act["type"] == "attack":
						await _exec_attack(unit, retry_act.get("target", null))
					elif retry_act["type"] == "move":
						await _exec_move(unit, retry_act.get("path", []))
					else:
						_finish_unit(unit)
				else:
					_finish_unit(unit)
				return
			await _exec_attack(unit, target)
		"move":
			var path = act.get("path", [])
			if path.is_empty() or unit.remaining_move <= 0:
				path = _enemy_ai._retry_find_path(unit)

			if path.is_empty():
				_finish_unit(unit)
			else:
				await _exec_move(unit, path)
		_:
			if unit.remaining_move > 0:
				var fallback_path = _enemy_ai._retry_find_path(unit)
				if fallback_path.size() > 0:
					await _exec_move(unit, fallback_path)
					ItemBattlefieldManager.try_pickup(unit)
					_finish_unit(unit)
					return

			ItemBattlefieldManager.try_pickup(unit)
			_finish_unit(unit)


# ============================================================
#  智能急救判断
# ============================================================
func _try_ai_emergency_heal(unit: Unit) -> bool:
	var cost : int = SoulFireManager.get_emergency_heal_cost()
	if not SoulFireManager.can_spend(cost):
		return false
		
	var best_target: Unit = null
	var lowest_ratio: float = 1.0
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0: continue
		if u.hit_points <= 0: continue
		if u == unit: continue
		var ratio = float(u.hit_points) / float(u.unit_stats.max_hp)
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			best_target = u
			
	# 只要有人掉血到 45% 以下，就可以考虑急救
	if best_target == null or lowest_ratio >= 0.45:
		return false
		
	var dist = abs(unit.grid_cell.x - best_target.grid_cell.x) + abs(unit.grid_cell.y - best_target.grid_cell.y)
	
	# 如果自己是纯正的奶妈，且目标在技能射程内，让 AI 正常治疗即可，不要乱花魂火
	if unit.get_weapon_type() == "staff":
		var weapon = unit.get_weapon_data()
		if weapon and dist >= weapon.min_attack_range and dist <= weapon.attack_range:
			return false
			
	if dist == 1:
		await CombatManager.execute_emergency_heal(unit, best_target)
		if is_instance_valid(unit) and unit.hit_points > 0 and unit.can_act_this_turn:
			SignalBus.request_hide_info.emit()
			ItemBattlefieldManager.try_pickup(unit)
			TurnManager.finish_unit_action(unit)
		return true
		
	if unit.remaining_move > 0:
		var reachable = UnitManager.get_reachable_cells(unit.grid_cell, unit.remaining_move, unit)
		var best_cell = Vector2i(-1, -1)
		for cell in reachable:
			if UnitManager.is_cell_occupied(cell): continue
			var d = abs(cell.x - best_target.grid_cell.x) + abs(cell.y - best_target.grid_cell.y)
			if d == 1:
				best_cell = cell
				break
				
		if best_cell != Vector2i(-1, -1):
			var path = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
			if not path.is_empty():
				TurnManager.start_movement(unit, path)
				await TurnManager.move_completed
				if is_instance_valid(unit) and unit.hit_points > 0 and is_instance_valid(best_target):
					await CombatManager.execute_emergency_heal(unit, best_target)
					if unit.can_act_this_turn:
						SignalBus.request_hide_info.emit()
						ItemBattlefieldManager.try_pickup(unit)
						TurnManager.finish_unit_action(unit)
					return true
					
	return false


# ============================================================
#  执行攻击
# ============================================================
func _exec_attack(unit: Unit, target) -> void:
	if not is_instance_valid(target) or target.hit_points <= 0:
		_finish_unit(unit)
		return
	
	var skill_id := ""
	var ready_skills := TalentManager.get_ready_active_skills(unit)
	for sid in ready_skills:
		var sdata = TalentManager.get_talent_data(sid)
		if sdata == null: continue
		if sdata.effect_type == "heal": continue 
		
		var cost : int = CombatManager._get_active_skill_cost(sdata)
		if SoulFireManager.can_spend(cost):
			skill_id = sid
			break
			
	await CombatManager.execute_attack(unit, target, skill_id)
	
	if is_instance_valid(unit) and unit.hit_points > 0 and unit.can_act_this_turn:
		SignalBus.request_hide_info.emit()
		ItemBattlefieldManager.try_pickup(unit)
		TurnManager.finish_unit_action(unit)


# ============================================================
#  执行移动
# ============================================================
func _exec_move(unit: Unit, path: Array) -> void:
	if path.is_empty():
		_finish_unit(unit)
		return

	if UnitManager.is_cell_occupied(path[-1]):
		var retry = _enemy_ai._retry_find_path(unit)
		if retry.is_empty() or UnitManager.is_cell_occupied(retry[-1]):
			_finish_unit(unit)
			return
		path = retry

	TurnManager.start_movement(unit, path)
	await TurnManager.move_completed

	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return

	var targets : Array = CombatManager.get_attackable_targets(unit)
	if not targets.is_empty():
		var follow_target = targets[0]
		_record_focus(unit, follow_target)
		await _exec_attack(unit, follow_target)
	else:
		_finish_unit(unit)


# ============================================================
#  辅助函数
# ============================================================
func _record_focus(attacker: Unit, target) -> void:
	if not is_instance_valid(target): return
	if target == attacker: return
	if target.hit_points <= 0: return
	if _enemy_ai == null: return
	if not _enemy_ai.has_method("record_focus_target"): return
	_enemy_ai.record_focus_target(target)


func _finish_unit(unit: Unit) -> void:
	if not is_instance_valid(unit): return
	if unit.can_act_this_turn or not unit.has_acted:
		TurnManager.finish_unit_action(unit)


func _clear_player_interaction_state() -> void:
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_clear_highlight_unit.emit()
	SignalBus.request_hide_info.emit()
	SignalBus.request_hide_setting.emit()
