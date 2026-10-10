extends Node

# ============================================================
#  TurnManager — 回合管理
#  含：所有批次改动（共鸣/光环/词条/套装/熔合/Boss/核心特性）
# ============================================================

enum Team { PLAYER = 0, ENEMY = 1 }

signal move_completed

var current_turn_team : Team = Team.PLAYER
var is_game_over : bool = false
var is_moving : bool = false
var is_ai_moving : bool = false

var last_player_unit : Unit = null
var all_acted : bool = false

var last_moved_unit : Unit = null

var enemy_ai : EnemyAI = null
var map_functions: Dictionary = {}

var _battle_ready : bool = false


func _ready():
	UnitManager.unit_removed.connect(_on_unit_removed)
	enemy_ai = EnemyAI.new()
	add_child(enemy_ai)
	enemy_ai.initialize(self)
	enemy_ai.ai_queue_finished.connect(_on_ai_queue_finished)


# ============================================================
#  战场就绪
# ============================================================
func set_battle_ready(value : bool):
	_battle_ready = value
	print("[TurnManager] set_battle_ready(", value, ")")


func is_battle_ready() -> bool:
	return _battle_ready


# ============================================================
#  单位移除 → 判胜负
# ============================================================
func _on_unit_removed(_unit: Unit, _team: int):
	if not _battle_ready:
		return
	if is_game_over:
		return
	check_victory()


func check_victory():
	if not _battle_ready:
		return
	var player_count = 0
	var enemy_count = 0
	for u in UnitManager.unit_list:
		if u.hit_points > 0:
			if u.unit_stats.team_id == 0:
				player_count += 1
			else:
				enemy_count += 1

	if player_count == 0 and enemy_count == 0:
		return

	if player_count == 0:
		_trigger_victory(1)
	elif enemy_count == 0:
		_trigger_victory(0)


func _trigger_victory(winning_team: int):
	if is_game_over:
		return
	is_game_over = true
	SignalBus.request_show_victory.emit(winning_team)
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()


# ============================================================
#  移动
# ============================================================
func start_movement(unit: Unit, path: Array):
	if is_game_over or is_moving:
		return
	if path.size() == 0:
		return
	unit.save_previous_position()
	var move_cost = path.size()
	unit.consume_move(move_cost)
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
	last_moved_unit = unit
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	SignalBus.request_clear_highlight.emit()
	SignalBus.request_hide_info.emit()
	move_completed.emit()


func on_ai_movement_finished(unit: Unit):
	is_ai_moving = false
	unit.has_moved = true
	unit.can_act_this_turn = false
	unit.has_attacked = false
	var targets = CombatManager.get_attackable_targets(unit)
	if targets.size() > 0:
		await CombatManager.execute_attack(unit, targets[0])
	unit.set_gray(true)
	await get_tree().create_timer(1.0).timeout
	move_completed.emit()


# ============================================================
#  回合启动（所有批次效果集中）
# ============================================================
func start_turn(team: Team):
	print("TurnManager.start_turn 被调用，team:", team)
	if is_game_over or is_moving:
		return

	if not _battle_ready:
		_battle_ready = true
		print("[TurnManager] 战场就绪")

	if Globals.is_non_combat_mode and team == Team.ENEMY:
		start_turn(Team.PLAYER)
		return

	current_turn_team = team
	all_acted = false
	is_moving = false
	is_ai_moving = false
	last_moved_unit = null
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()

	for unit in UnitManager.unit_list:
		if unit.hit_points > 0:
			unit.is_gray = false
			unit.update_color()
			if unit.animated_sprite:
				unit.animated_sprite.queue_redraw()

	call_deferred("_refresh_all_unit_colors")

	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.unit_stats.team_id == team:
			unit.accumulate_all_talents()

	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.unit_stats.team_id == team:
			unit.reset_turn()

	# ★ 所有批次：回合开始效果
	if team == Team.PLAYER:
		SoulFireManager.tick_turn_start(UnitManager.unit_list)   # 批次 8：归零扣血
		_apply_turn_start_regen()                                # 批次 6A + 6B：回合回复
		_apply_turn_start_auras()                                # 批次 5A：薪火相传
		_apply_turn_start_fusion()                               # 方向 1：不灭余烬
		_apply_charge_stacks()                                   # 方向 7：斧兵蓄力
		BossMechanicManager.on_player_turn_start()               # 方向 3：Day1
	else:
		BossMechanicManager.on_enemy_turn_start()                # 方向 3：Day2

	SignalBus.turn_changed.emit(team)


func _refresh_all_unit_colors():
	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.animated_sprite:
			unit.animated_sprite.queue_redraw()


# ============================================================
#  回合开始效果 · 批次 6A + 6B（词条 + 套装）
# ============================================================
func _apply_turn_start_regen():
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0:
			continue
		var regen_pct : float = 0.0
		# 词条：轮回
		for slot in u.armor_slots:
			if slot:
				regen_pct += slot.get_affix_value_float("turn_regen")
		# 套装：生生不息
		var active : Array = SetBonusManager.get_active_sets_for_unit(u)
		for entry in active:
			var b : Dictionary = entry["bonus"]
			if b.get("effect", "") == "turn_regen":
				regen_pct += float(b.get("value", 0.0))
		# ★ 方向 2：轮回不息（交叉效果）
		var cross_active : Array = SetBonusManager.get_active_cross_bonuses()
		for entry in cross_active:
			var b2 : Dictionary = entry["data"]
			if b2.get("effect", "") == "turn_regen":
				regen_pct += float(b2.get("value", 0.03))
		if regen_pct > 0.0:
			var heal : int = int(u.unit_stats.max_hp * regen_pct)
			if heal > 0:
				var old : int = u.hit_points
				u.hit_points = mini(u.hit_points + heal, u.unit_stats.max_hp)
				var actual : int = u.hit_points - old
				if actual > 0:
					u.update_hp_label()
					SignalBus.request_damage_popup.emit(u.global_position, actual, false, false, true)


# ============================================================
#  回合开始效果 · 批次 5A（光环）
# ============================================================
func _apply_turn_start_auras():
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0:
			continue
		for aid in u.active_auras:
			if not u.active_auras[aid]:
				continue
			var d : Dictionary = AuraManager.get_aura(aid)
			if d.get("effect", "") != "turn_start_gain_soul_fire":
				continue
			var gain : int = int(d.get("params", {}).get("soul_fire_gain", 1))
			SoulFireManager.add(gain)
			print("[光环] %s：回合开始 +%d 魂火" % [d.get("name", aid), gain])
			return


# ============================================================
#  回合开始效果 · 方向 1（不灭余烬）
# ============================================================
func _apply_turn_start_fusion():
	if SoulFireManager.current > 0:
		return
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0:
			continue
		if u.has_fusion_effect("sacrifice_zero_recover"):
			SoulFireManager.add(1)
			print("[不灭余烬] 魂火归零，回合开始 +1 魂火")
			return


# ============================================================
#  回合开始效果 · 方向 7（蓄力）
# ============================================================
func _apply_charge_stacks():
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0:
			continue
		if u.has_core_trait("charge") and not u.has_attacked:
			u.charge_stacks = mini(u.charge_stacks + 1, 5)
			print("[蓄力] %s 累积至 %d 层" % [u.unit_stats.unit_name, u.charge_stacks])


# ============================================================
#  AI
# ============================================================
func run_enemy_ai():
	if is_game_over or is_moving:
		return
	if enemy_ai:
		enemy_ai.run_enemy_ai()


func _on_ai_queue_finished():
	await get_tree().create_timer(1.5).timeout
	start_turn(Team.PLAYER)


# ============================================================
#  单位行动结束
# ============================================================
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
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
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
	if last_moved_unit == unit:
		last_moved_unit = null
	SignalBus.request_move_unit.emit(unit, unit.grid_cell)
	SignalBus.request_hide_menu.emit()
	SignalBus.request_clear_highlight.emit()
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE


# ============================================================
#  全场行动检查
# ============================================================
func check_all_acted():
	if not _battle_ready:
		return
	var all_acted_local = true
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == current_turn_team and unit.hit_points > 0:
			if unit.can_act_this_turn == true:
				all_acted_local = false
				break
	all_acted = all_acted_local
	if all_acted_local and current_turn_team == Team.PLAYER:
		auto_end_turn()


func auto_end_turn():
	if is_game_over or is_moving:
		return
	if current_turn_team == Team.PLAYER:
		start_turn(Team.ENEMY)


# ============================================================
#  AI 状态清理
# ============================================================
func clear_ai_state():
	if enemy_ai:
		enemy_ai.clear_state()
	is_ai_moving = false
	is_moving = false


# ============================================================
#  查询
# ============================================================
func get_last_player_unit() -> Unit:
	return last_player_unit


func get_first_enemy_unit() -> Unit:
	if enemy_ai:
		return enemy_ai.first_ai_unit
	return null
