extends Node

# ---- 预加载 UnitDataManager ----
const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

signal move_completed

var current_turn_team : int = 0
var is_game_over : bool = false
var is_moving : bool = false
var is_ai_moving : bool = false

var last_player_unit : Unit = null
var all_acted : bool = false

var enemy_ai : EnemyAI = null
var map_functions: Dictionary = {}   # 由 Battlefield 设置

func _ready():
	UnitManager.unit_removed.connect(_on_unit_removed)
	# 初始化 AI 处理器
	enemy_ai = EnemyAI.new()
	add_child(enemy_ai)
	enemy_ai.initialize(self)
	enemy_ai.ai_queue_finished.connect(_on_ai_queue_finished)

func _on_unit_removed(_unit: Unit, _team: int):
	check_victory()

func check_victory():
	var player_count = 0
	var enemy_count = 0
	for u in UnitManager.unit_list:
		if u.hit_points > 0:
			if u.unit_stats.team_id == 0:
				player_count += 1
			else:
				enemy_count += 1
	if player_count == 0:
		_trigger_victory(1)
	elif enemy_count == 0:
		_trigger_victory(0)

func _trigger_victory(winning_team: int):
	is_game_over = true
	SignalBus.request_show_victory.emit(winning_team)
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()

func start_movement(unit: Unit, path: Array):
	if is_game_over or is_moving:
		return
	if path.size() == 0:
		return
	unit.save_previous_position()
	var move_cost = path.size()
	unit.consume_move(move_cost)
	# ---- 增加行动后移动计数 ----
	unit.moves_since_act += 1
	SignalBus.request_move_along_path.emit(unit, path)
	is_moving = true

func start_ai_movement(unit: Unit, path: Array):
	if is_game_over:
		return
	if path.size() == 0:
		return
	if UnitManager.is_cell_occupied(path[-1]):
		return
	unit.save_previous_position()
	var move_cost = path.size()
	unit.consume_move(move_cost)
	SignalBus.request_ai_move_along_path.emit(unit, path)
	is_ai_moving = true

func on_movement_finished(unit: Unit):
	is_moving = false
	unit.has_moved = true
	unit.can_act_this_turn = true
	InputManager.selected_unit = unit
	InputManager.interaction_phase = "menu"
	SignalBus.request_show_menu.emit(unit)
	SignalBus.request_clear_highlight.emit()

func on_ai_movement_finished(unit: Unit):
	is_ai_moving = false
	unit.has_moved = true
	unit.can_act_this_turn = false
	# ---- 标记已移动，即使未攻击也视为行动过 ----
	unit.has_attacked = false   # 未攻击，但已行动，不应再攻击
	var targets = CombatManager.get_attackable_targets(unit)
	if targets.size() > 0:
		await CombatManager.execute_attack(unit, targets[0])
	unit.set_gray(true)
	await get_tree().create_timer(1.0).timeout
	move_completed.emit()

func start_turn(team: int):
	print("TurnManager.start_turn 被调用，team:", team, " is_game_over:", is_game_over, " is_moving:", is_moving)
	if is_game_over or is_moving:
		print("跳过 start_turn")
		return
	current_turn_team = team
	all_acted = false
	is_moving = false
	is_ai_moving = false
	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.attackable_targets = []
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()

	# ---- 强制所有单位恢复彩色 ----
	for unit in UnitManager.unit_list:
		if unit.hit_points > 0:
			unit.is_gray = false
			unit.update_color()
			if unit.animated_sprite:
				unit.animated_sprite.queue_redraw()

	# ---- 延迟一帧再次强制刷新（确保渲染完成） ----
	call_deferred("_refresh_all_unit_colors")

	# ---- 重置当前队伍行动状态 ----
	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.unit_stats.team_id == team:
			unit.reset_turn()

	SignalBus.turn_changed.emit(team)

# ---- 辅助函数：二次刷新 ----
func _refresh_all_unit_colors():
	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.animated_sprite:
			unit.animated_sprite.queue_redraw()

# ---- AI 控制 ----
func run_enemy_ai():
	print("TurnManager.run_enemy_ai 被调用")
	if is_game_over or is_moving:
		print("跳过：is_game_over=", is_game_over, " is_moving=", is_moving)
		return
	if enemy_ai:
		print("调用 EnemyAI.run_enemy_ai")
		enemy_ai.run_enemy_ai()
	else:
		print("enemy_ai 为 null")

func _on_ai_queue_finished():
	# AI 队列完成，等待片刻后切回玩家回合
	await get_tree().create_timer(1.5).timeout
	start_turn(0)   # 改为直接调用

# ---- 其他回合控制 ----
func finish_unit_action(unit: Unit):
	if is_game_over or is_moving:
		return
	if unit.unit_stats.team_id == 0:
		last_player_unit = unit
	unit.can_act_this_turn = false
	unit.set_gray(true)
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()
	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"
	InputManager.current_highlight_cells = {}
	InputManager.attackable_targets = []
	check_all_acted()

func cancel_movement(unit: Unit):
	if is_game_over:
		return
	if unit.unit_stats.team_id == 0:
		last_player_unit = unit
	unit.revert_to_previous_position()
	unit.has_moved = false
	unit.can_act_this_turn = true
	unit.set_gray(false)
	SignalBus.request_move_unit.emit(unit, unit.grid_cell)
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()
	InputManager.selected_unit = null
	InputManager.interaction_phase = "idle"

func check_all_acted():
	var all_acted_local = true
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == current_turn_team and unit.hit_points > 0:
			if unit.can_act_this_turn == true:
				all_acted_local = false
				break
	all_acted = all_acted_local
	if all_acted_local and current_turn_team == 0:
		auto_end_turn()

func auto_end_turn():
	if is_game_over or is_moving:
		return
	if current_turn_team == 0:
		start_turn(1)

func clear_ai_state():
	if enemy_ai:
		enemy_ai.clear_state()
	is_ai_moving = false
	is_moving = false
	print("TurnManager AI 状态已清理")

func get_last_player_unit() -> Unit:
	return last_player_unit

func get_first_enemy_unit() -> Unit:
	return enemy_ai.first_ai_unit if enemy_ai else null
