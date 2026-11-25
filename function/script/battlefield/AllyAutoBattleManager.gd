class_name AllyAutoBattleManager
extends Node

# ============================================================
#  AllyAutoBattleManager — 我方自动战斗流水线（v6.68b）
# ============================================================
#  修复要点：
#  1) 开关有唯一真值 _desired，空格随时可切换；面板/过场/await 期间不丢意图，
#     而是标记 pending 后逐帧重试，直到条件满足或进入下个我方回合。
#  2) 主循环统一走 _can_run()（对话/道具弹窗/攻击菜单/确认框/结算页/表演），
#     不再只看 is_moving 就往下冲。
#  3) 每次 await 后校验 _run_serial，关闭自动战斗或换回合后旧协程不再改状态。
#  4) 移动等待改成有界轮询，避免 move_completed 永远不来导致流水线挂死。
# ============================================================

const ACTION_DELAY       : float = 0.35
const AFTER_ACTION_DELAY : float = 0.40
const MAX_WAIT           : float = 8.0
const WAIT_POLL          : float = 0.10
const STUCK_LIMIT        : float = 2.0
const PANEL_RETRY        : float = 0.15

var _bf : Node2D = null
var _enemy_ai : EnemyAI = null
var _running : bool = false
var _run_serial : int = 0
var _stuck_timer : float = 0.0

# 开关状态：_desired 是唯一真值，Globals.is_auto_battle 只是对外镜像。
var _desired : bool = false
var _pending_start : bool = false
var _pending_hint_shown : bool = false
var _retry_accum : float = 0.0


func _init(bf: Node2D):
	_bf = bf


func _ready():
	_enemy_ai = TurnManager.enemy_ai
	SignalBus.turn_changed.connect(_on_turn_changed)


# ============================================================
#  外部接口
# ============================================================

## 空格键唯一入口：任何状态下都能立即翻转意图，不会被面板/await 吞掉。
func request_toggle() -> void:
	_set_desired(not _desired)


func set_enabled(v: bool) -> void:
	_set_desired(v)


func cancel() -> void:
	_set_desired(false)


func is_pending() -> bool:
	return _desired and _pending_start


func _set_desired(v: bool) -> void:
	if v and TurnManager != null and TurnManager.is_game_over:
		return
	_desired = v
	Globals.is_auto_battle = v
	if not v:
		_cancel_pipeline()
		_pending_start = false
		_pending_hint_shown = false
		_clear_player_interaction_state()
		SignalBus.request_hint_override.emit("自动战斗 关闭", 1.5)
		return
	# 开启：先收掉会挡住操作的瞬态面板，然后登记待启动，逐帧重试。
	_pending_hint_shown = false
	_clear_player_interaction_state()
	_pending_start = true
	_retry_accum = PANEL_RETRY
	SignalBus.request_hint_override.emit("自动战斗 开启", 1.2)
	_try_start_now()


func _cancel_pipeline() -> void:
	_run_serial += 1
	_running = false
	_stuck_timer = 0.0


func _process(delta: float) -> void:
	if not _desired or _running or not _pending_start:
		return
	_retry_accum += delta
	if _retry_accum < PANEL_RETRY:
		return
	_retry_accum = 0.0
	if TurnManager.is_game_over:
		_set_desired(false)
		return
	if not TurnManager.is_battle_ready():
		return
	if _can_run():
		_try_start_now()
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		_show_next_turn_hint()


func _show_next_turn_hint() -> void:
	if _pending_hint_shown:
		return
	_pending_hint_shown = true
	SignalBus.request_hint_override.emit("自动战斗已开启，下回合生效", 1.5)


# ============================================================
#  回合切换监听
# ============================================================
func _on_turn_changed(team: int) -> void:
	if team == TurnManager.Team.PLAYER:
		if _desired:
			_pending_start = true
			_try_start_now()
	else:
		# 敌方回合：中止旧协程，但保留开启意图，下个我方回合自动续上。
		_cancel_pipeline()


# ============================================================
#  运行条件
# ============================================================
func _can_run() -> bool:
	if TurnManager == null or not TurnManager.is_battle_ready() or TurnManager.is_game_over:
		return false
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return false
	if TurnManager.is_moving or TurnManager.is_ai_moving:
		return false
	if Globals.is_performing_action or Globals.is_dialogue_active:
		return false
	if Globals.is_item_get_popup_active or Globals.is_attack_menu_active:
		return false
	if Globals.is_confirm_ui_active or Globals.is_reward_summary_active:
		return false
	if Globals.is_fading or Globals.is_transitioning:
		return false
	if _bf != null:
		var vp_v: Variant = _bf.get("victory_panel")
		if vp_v is Control and (vp_v as Control).visible:
			return false
	return true


func _wait_until_runnable(serial: int) -> bool:
	var waited: float = 0.0
	while not _can_run():
		if serial != _run_serial or not _desired:
			return false
		if TurnManager.is_game_over:
			return false
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
			_show_next_turn_hint()
			return false
		if waited >= MAX_WAIT:
			push_warning("[AutoBattle] 等待可操作状态超时，本回合暂停自动战斗（开关保留）")
			return false
		await get_tree().create_timer(WAIT_POLL, true, false, true).timeout
		waited += WAIT_POLL
	return true


func _try_start_now() -> void:
	if not _desired or _running or not _pending_start:
		return
	if not _can_run():
		return
	_pending_start = false
	_pending_hint_shown = false
	_start_player_turn_auto()


# ============================================================
#  主流水线
# ============================================================
func _start_player_turn_auto() -> void:
	if _running:
		return
	_running = true
	_run_serial += 1
	var my_serial: int = _run_serial
	_stuck_timer = 0.0

	if _enemy_ai != null and is_instance_valid(_enemy_ai) \
			and _enemy_ai.has_method("begin_ally_turn_focus"):
		_enemy_ai.begin_ally_turn_focus()

	_clear_player_interaction_state()
	if not await _wait_until_runnable(my_serial):
		_running = false
		if _desired:
			_pending_start = true
		return

	var aborted: bool = false
	while true:
		if my_serial != _run_serial or not _desired or TurnManager.is_game_over:
			aborted = true
			break
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
			_show_next_turn_hint()
			aborted = true
			break
		if not _can_run():
			aborted = true
			break

		# 防止死锁：系统认为在移动但迟迟没结束，超时后强制解锁（沿用原口径）。
		if TurnManager.is_moving or TurnManager.is_ai_moving:
			_stuck_timer += WAIT_POLL
			if _stuck_timer > STUCK_LIMIT:
				TurnManager.is_moving = false
				TurnManager.is_ai_moving = false
				SignalBus.request_clear_highlight.emit()
				push_warning("[AutoBattle] 检测到移动卡死，强制解锁")
				_stuck_timer = 0.0
			await get_tree().create_timer(WAIT_POLL, true, false, true).timeout
			continue
		_stuck_timer = 0.0

		var unit := _pick_next_actor()
		if unit == null:
			break
		await _act_one_unit(unit, my_serial)
		if my_serial != _run_serial or not _desired:
			aborted = true
			break
		await get_tree().create_timer(AFTER_ACTION_DELAY, true, false, true).timeout

	_running = false
	_stuck_timer = 0.0
	if my_serial != _run_serial:
		return
	if aborted:
		if _desired:
			_pending_start = true
		return
	if not _desired:
		return
	if TurnManager.is_game_over:
		_set_desired(false)
		return
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if not _can_run():
		_pending_start = true
		return

	# 正常收尾：仍可行动的单位全部待机，避免回合卡住。
	for u in UnitManager.unit_list:
		if is_instance_valid(u) and u.hit_points > 0 \
				and u.unit_stats.team_id == 0 and u.can_act_this_turn:
			TurnManager.finish_unit_action(u)


# ============================================================
#  条件与选人
# ============================================================
func _pick_next_actor() -> Unit:
	for u in UnitManager.unit_list:
		if u == null or not is_instance_valid(u):
			continue
		if u.unit_stats == null or u.unit_stats.team_id != 0:
			continue
		if u.hit_points <= 0 or not u.can_act_this_turn or u.has_acted or u.stun_rounds > 0:
			continue
		return u
	return null


# ============================================================
#  单单位执行
# ============================================================
func _act_one_unit(unit: Unit, serial: int) -> void:
	if not is_instance_valid(unit):
		return
	await get_tree().create_timer(ACTION_DELAY, true, false, true).timeout
	if serial != _run_serial or not _desired:
		return
	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return
	if not await _wait_until_runnable(serial):
		return
	if _enemy_ai == null or not is_instance_valid(_enemy_ai):
		_finish_unit(unit)
		return

	# 优先去捡血瓶（避免浪费加血技能/魂火）
	var orb_cell: Vector2i = _enemy_ai._find_reachable_orb(unit)
	if orb_cell != Vector2i(-1, -1) and unit.remaining_move > 0:
		var path: Array = UnitManager.calculate_path(unit.grid_cell, orb_cell, unit)
		if path.size() > 0:
			await _exec_move(unit, path, serial)
			return

	if await _try_ai_emergency_heal(unit, serial):
		return
	if serial != _run_serial or not _desired:
		return

	var act: Dictionary = _enemy_ai.decide_action_for(unit)
	if str(act.get("type", "")) == "attack":
		_record_focus(unit, act.get("target", null))

	match str(act.get("type", "wait")):
		"attack":
			var target_v: Variant = act.get("target", null)
			var target: Unit = null
			if target_v is Unit:
				target = target_v as Unit
			if not is_instance_valid(target) or target.hit_points <= 0:
				var retry_act: Dictionary = _enemy_ai.decide_action_for(unit)
				var retry_type: String = str(retry_act.get("type", "wait"))
				if retry_type == "attack":
					await _exec_attack(unit, retry_act.get("target", null), serial)
				elif retry_type == "move":
					await _exec_move(unit, retry_act.get("path", []), serial)
				else:
					_finish_unit(unit)
				return
			await _exec_attack(unit, target, serial)
		"move":
			var path: Array = act.get("path", [])
			if path.is_empty() or unit.remaining_move <= 0:
				path = _enemy_ai._retry_find_path(unit)
			if path.is_empty():
				_finish_unit(unit)
			else:
				await _exec_move(unit, path, serial)
		_:
			if unit.remaining_move > 0:
				var fallback_path: Array = _enemy_ai._retry_find_path(unit)
				if fallback_path.size() > 0:
					await _exec_move(unit, fallback_path, serial)
					if serial == _run_serial and is_instance_valid(unit):
						ItemBattlefieldManager.try_pickup(unit)
					return
			ItemBattlefieldManager.try_pickup(unit)
			_finish_unit(unit)


# ============================================================
#  智能急救判断
# ============================================================
func _try_ai_emergency_heal(unit: Unit, serial: int) -> bool:
	var cost: int = SoulFireManager.get_emergency_heal_cost()
	if not SoulFireManager.can_spend(cost):
		return false

	var best_target: Unit = null
	var lowest_ratio: float = 1.0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u.unit_stats == null:
			continue
		if u.unit_stats.team_id != 0 or u.hit_points <= 0:
			continue
		var ratio: float = float(u.hit_points) / float(maxi(1, u.unit_stats.max_hp))
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			best_target = u

	if best_target == null or lowest_ratio >= 0.45:
		return false

	var dist: int = absi(unit.grid_cell.x - best_target.grid_cell.x) \
			+ absi(unit.grid_cell.y - best_target.grid_cell.y)

	if unit.get_weapon_type() == "staff" and unit != best_target:
		var max_r: int = unit.get_effective_attack_range()
		var min_r: int = unit.get_effective_min_attack_range()
		if dist >= min_r and dist <= max_r:
			return false

	if dist <= 1:
		await CombatManager.execute_emergency_heal(unit, best_target)
		if serial != _run_serial or not _desired:
			return true
		if is_instance_valid(unit) and unit.hit_points > 0 and unit.can_act_this_turn:
			SignalBus.request_hide_info.emit()
			ItemBattlefieldManager.try_pickup(unit)
			TurnManager.finish_unit_action(unit)
		return true

	if unit.remaining_move > 0:
		var reachable: Dictionary = UnitManager.get_reachable_cells(
				unit.grid_cell, unit.remaining_move, unit)
		var best_cell: Vector2i = Vector2i(-1, -1)
		for cell in reachable:
			if UnitManager.is_cell_occupied(cell):
				continue
			var d: int = absi(cell.x - best_target.grid_cell.x) \
					+ absi(cell.y - best_target.grid_cell.y)
			if d == 1:
				best_cell = cell
				break
		if best_cell != Vector2i(-1, -1):
			var path: Array = UnitManager.calculate_path(unit.grid_cell, best_cell, unit)
			if not path.is_empty():
				TurnManager.start_movement(unit, path)
				await _wait_movement_done(serial)
				if serial != _run_serial or not _desired:
					return true
				if is_instance_valid(unit) and unit.hit_points > 0 \
						and is_instance_valid(best_target) and best_target.hit_points > 0:
					await CombatManager.execute_emergency_heal(unit, best_target)
					if serial != _run_serial or not _desired:
						return true
					if unit.can_act_this_turn:
						SignalBus.request_hide_info.emit()
						ItemBattlefieldManager.try_pickup(unit)
						TurnManager.finish_unit_action(unit)
					return true
	return false


# ============================================================
#  执行攻击 / 移动
# ============================================================
func _exec_attack(unit: Unit, target, serial: int) -> void:
	if not is_instance_valid(target) or target.hit_points <= 0:
		_finish_unit(unit)
		return

	var is_ally_target: bool = (target.unit_stats.team_id == unit.unit_stats.team_id)
	var skill_id: String = ""
	var ready_skills: Array = TalentManager.get_ready_active_skills(unit)
	for sid in ready_skills:
		var sdata = TalentManager.get_talent_data(sid)
		if sdata == null:
			continue
		if sdata.effect_type == "heal":
			if not is_ally_target:
				continue
		else:
			if is_ally_target:
				continue
		var cost: int = CombatManager._get_active_skill_cost(sdata)
		if SoulFireManager.can_spend(cost):
			skill_id = sid
			break

	# v6.63：爆发只走技能按钮出口，托管下有技能即可能自动爆发，不另起指令。
	await CombatManager.execute_attack(unit, target, skill_id)
	if serial != _run_serial or not _desired:
		return
	if is_instance_valid(unit) and unit.hit_points > 0 and unit.can_act_this_turn:
		SignalBus.request_hide_info.emit()
		ItemBattlefieldManager.try_pickup(unit)
		TurnManager.finish_unit_action(unit)


func _wait_movement_done(serial: int) -> void:
	var waited: float = 0.0
	while (TurnManager.is_moving or TurnManager.is_ai_moving) and waited < MAX_WAIT:
		await get_tree().create_timer(WAIT_POLL, true, false, true).timeout
		waited += WAIT_POLL
		if serial != _run_serial or not _desired:
			return
	if TurnManager.is_moving or TurnManager.is_ai_moving:
		TurnManager.is_moving = false
		TurnManager.is_ai_moving = false
		SignalBus.request_clear_highlight.emit()
		push_warning("[AutoBattle] 移动等待超时，强制清理移动状态")


func _exec_move(unit: Unit, path: Array, serial: int) -> void:
	if path.is_empty():
		_finish_unit(unit)
		return
	if UnitManager.is_cell_occupied(path[-1]):
		var retry: Array = _enemy_ai._retry_find_path(unit)
		if retry.is_empty() or UnitManager.is_cell_occupied(retry[-1]):
			_finish_unit(unit)
			return
		path = retry

	if TurnManager.is_moving or TurnManager.is_ai_moving:
		await _wait_movement_done(serial)
		if serial != _run_serial or not _desired:
			return
	TurnManager.start_movement(unit, path)
	if not TurnManager.is_moving:
		_finish_unit(unit)
		return
	await _wait_movement_done(serial)
	if serial != _run_serial or not _desired:
		return
	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return

	var targets: Array = CombatManager.get_attackable_targets(unit)
	if not targets.is_empty():
		var follow_target = targets[0]
		_record_focus(unit, follow_target)
		await _exec_attack(unit, follow_target, serial)
	else:
		_finish_unit(unit)


# ============================================================
#  辅助函数
# ============================================================
func _record_focus(attacker: Unit, target) -> void:
	if not is_instance_valid(target):
		return
	if target == attacker or target.hit_points <= 0:
		return
	if _enemy_ai == null or not is_instance_valid(_enemy_ai):
		return
	if _enemy_ai.has_method("record_focus_target"):
		_enemy_ai.record_focus_target(target)


func _finish_unit(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
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
	if _bf != null and _bf.has_method("force_close_transient_ui"):
		_bf.force_close_transient_ui()
