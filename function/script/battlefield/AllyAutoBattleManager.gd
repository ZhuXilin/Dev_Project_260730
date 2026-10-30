class_name AllyAutoBattleManager
extends Node

# ============================================================
#  AllyAutoBattleManager — 我方自动战斗流水线
#
#  语义：
#    Globals.is_auto_battle = 玩家意愿开关（按 F 才变，回合切换不动）
#    _running                = 当前这一波 AI 是否在跑（回合切换时归零）
#
#  回合流程：
#    玩家回合开始 → is_auto_battle 为 true → _start_player_turn_auto()
#    AI 打完所有单位 → auto_end_turn → 敌方回合
#    切到敌方回合 → _run_serial++ → 主循环立即退出，_running = false
#    敌方回合结束 → 切回玩家回合 → is_auto_battle 仍 true → 自动恢复
#    胜利/失败 → VictoryHandler 主动把 is_auto_battle = false
#
#  原则：只发指令，不碰动画。全部走 TurnManager / CombatManager。
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


func _init(bf: Node2D):
	_bf = bf


func _ready():
	_enemy_ai = TurnManager.enemy_ai
	SignalBus.turn_changed.connect(_on_turn_changed)


# ============================================================
#  外部接口（Battlefield 按 F 调用）
# ============================================================
func set_enabled(v: bool) -> void:
	if v:
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
			SignalBus.request_hint_override.emit("仅在我方回合可开启自动战斗", 1.5)
			return
		if TurnManager.is_game_over:
			return
		Globals.is_auto_battle = true
		if not _running:
			_start_player_turn_auto()
	else:
		Globals.is_auto_battle = false
		# 不打断当前正在跑的动作，让 _should_continue 自然退出


## 强制取消（切场景用）
func cancel() -> void:
	Globals.is_auto_battle = false
	_run_serial += 1
	_running = false


# ============================================================
#  回合切换监听（★ 关键：开关不动，只切 _running）
# ============================================================
func _on_turn_changed(team: int) -> void:
	if team == TurnManager.Team.PLAYER:
		# ★ 玩家回合开始：如果玩家开关还在，自动恢复
		if Globals.is_auto_battle and not _running:
			_start_player_turn_auto()
	else:
		# ★ 敌方回合开始：中断当前 AI，但保留 is_auto_battle
		#    已开始的单次动作（攻击/移动动画）会自然跑完，主循环在下一检查点退出
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

	_clear_player_interaction_state()

	# 等回合切换动画播完
	await get_tree().create_timer(TURN_START_DELAY, true, false, true).timeout
	if my_serial != _run_serial: return

	# ★ 有界轮询：容忍过渡动画 / apply_map_functions 耗时 / 临时面板
	var waited : float = 0.0
	while not _should_continue():
		if my_serial != _run_serial: return
		if not Globals.is_auto_battle: _running = false; return
		if TurnManager.is_game_over: _running = false; return
		if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
			_running = false; return
		if waited >= MAX_WAIT:
			push_warning("[AutoBattle] 等待超时，本回合跳过（开关保留）")
			# ★ 超时也不关开关，下一玩家回合再试
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

	# 兜底：把剩余未行动单位强制待机，防止卡死
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

	var act : Dictionary = _enemy_ai.decide_action_for(unit)
	match str(act.get("type", "wait")):
		"attack":
			await _exec_attack(unit, act.get("target", null))
		"move":
			await _exec_move(unit, act.get("path", []))
		_:
			_finish_unit(unit)


func _exec_attack(unit: Unit, target) -> void:
	if not is_instance_valid(target) or target.hit_points <= 0:
		_finish_unit(unit)
		return
	await CombatManager.execute_attack(unit, target)
	if is_instance_valid(unit) and unit.hit_points > 0 and unit.can_act_this_turn:
		SignalBus.request_hide_info.emit()
		TurnManager.finish_unit_action(unit)


func _exec_move(unit: Unit, path: Array) -> void:
	if path.is_empty():
		_finish_unit(unit)
		return
	TurnManager.start_movement(unit, path)
	await TurnManager.move_completed
	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return
	var targets : Array = CombatManager.get_attackable_targets(unit)
	if not targets.is_empty():
		await CombatManager.execute_attack(unit, targets[0])
		if is_instance_valid(unit) and unit.hit_points > 0 and unit.can_act_this_turn:
			SignalBus.request_hide_info.emit()
			TurnManager.finish_unit_action(unit)
	else:
		_finish_unit(unit)


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
