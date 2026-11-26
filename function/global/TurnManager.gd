extends Node

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

func set_battle_ready(value : bool):
	var was_ready : bool = _battle_ready
	_battle_ready = value
	if value and not was_ready:
		call_deferred("check_victory")

func is_battle_ready() -> bool:
	return _battle_ready

func _on_unit_removed(unit: Unit, team: int):
	if not _battle_ready: return
	if is_game_over: return
	if ObjectiveManager: ObjectiveManager.on_unit_removed(unit, team)
	check_victory()
	

## 后续波次单位在激活前被 WaveManager 隐藏（visible=false / PROCESS_MODE_DISABLED），
## 但 hit_points 仍是满的。统计存活敌人时必须排除它们，否则首波全灭后 enemy_count
## 恒 > 0：既不推进下一波、也不触发胜利，战斗永久卡死（v5.8 修复）。
static func _is_active_enemy(u) -> bool:
	return u.visible and u.process_mode != Node.PROCESS_MODE_DISABLED


func check_victory():
	if not _battle_ready: return
	var player_count = 0
	var enemy_count = 0                 # 已激活敌人：用于「敌人全灭 / 推进下一波」
	var total_enemy_count = 0           # 含未激活波次：用于「玩家全灭」判定
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.hit_points <= 0: continue
		if u.unit_stats.team_id == 0:
			player_count += 1
		else:
			total_enemy_count += 1
			if _is_active_enemy(u):
				enemy_count += 1

	if player_count == 0 and total_enemy_count == 0: return
	if player_count == 0:
		_trigger_victory(1)
		return
		
	if ObjectiveManager and ObjectiveManager.is_completed():
		_trigger_victory(0)
		return
		
	if (not ObjectiveManager) or ObjectiveManager.is_annihilate():
		if enemy_count == 0:
			# ★ 核心修复：首波全灭时，直接触发下一波，而不等玩家结束回合
			if WaveManager and WaveManager.has_pending_waves():
				WaveManager.activate_next_wave_immediately()
				
				# 刷新后再次检查是否已有新敌人出场
				var new_enemy_count = 0
				for u in UnitManager.unit_list:
					if not is_instance_valid(u): continue
					if u.unit_stats.team_id == 1 and u.hit_points > 0 and _is_active_enemy(u):
						new_enemy_count += 1
				
				if new_enemy_count > 0:
					return # 成功刷出敌人，当前并未完全通关
					
			_trigger_victory(0)


func _trigger_victory(winning_team: int):
	if is_game_over: return
	is_game_over = true
	SignalBus.request_show_victory.emit(winning_team)
	SignalBus.request_clear_highlight.emit()

func start_movement(unit: Unit, path: Array):
	if is_game_over or is_moving: return
	if path.size() == 0: return
	unit.save_previous_position()
	unit.consume_move(path.size())
	SignalBus.request_move_along_path.emit(unit, path)
	is_moving = true

func start_ai_movement(unit: Unit, path: Array):
	if is_game_over: return
	if path.size() == 0: return
	if UnitManager.is_cell_occupied(path[-1]): return
	unit.save_previous_position()
	unit.consume_move(path.size())
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
	await get_tree().create_timer(0.25).timeout
	move_completed.emit()

func start_turn(team: Team):
	if is_game_over or is_moving: return
	if not _battle_ready: _battle_ready = true
	if Globals.is_non_combat_mode and team == Team.ENEMY:
		start_turn(Team.PLAYER)
		return
	# ★ v6.62y：异常品质变体（禁疗/减速）在「目标所属队伍回合结束」时递减，
	#   避免敌方回合一开始就归零导致 epic 效果打不出收益。
	if team != current_turn_team:
		for u in UnitManager.unit_list:
			if not is_instance_valid(u) or u.unit_stats == null:
				continue
			if u.unit_stats.team_id != current_turn_team:
				continue
			if u.no_heal_rounds > 0: u.no_heal_rounds -= 1
			if u.abnormal_slow_rounds > 0: u.abnormal_slow_rounds -= 1
			# ★ v6.66：守护团队减伤 1 回合递减
			if u.guard_team_dr_rounds > 0:
				u.guard_team_dr_rounds -= 1
				if u.guard_team_dr_rounds <= 0:
					u.guard_team_dr = 0.0
			# ★ v6.67：撞墙眩晕递减（在目标所属队伍回合结束时）
			if u.stun_rounds > 0:
				u.stun_rounds -= 1

	if team == Team.ENEMY and current_turn_team == Team.PLAYER:
		if ObjectiveManager: ObjectiveManager.on_player_turn_end()
		check_victory()
		if is_game_over: return
		if WaveManager: WaveManager.on_player_turn_end()
		check_victory()
		if is_game_over: return

	current_turn_team = team
	all_acted = false
	is_moving = false
	is_ai_moving = false
	last_moved_unit = null
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	SignalBus.request_clear_highlight.emit()

	if team == Team.PLAYER:
		AnalyticsLogger.record_soul_fire_sample()
		CombatManager.tick_ash_tiles()   # ★ v6.2 灰烬地块只活到下一次我方回合

	for unit in UnitManager.unit_list:
		if unit.hit_points > 0:
			unit.is_gray = false
			unit.update_color()
			if unit.animated_sprite: unit.animated_sprite.queue_redraw()

	call_deferred("_refresh_all_unit_colors")

	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.unit_stats.team_id == team:
			unit.accumulate_all_talents()

	# ★ v6.62x：异常 DOT 结算（灼烧/灰烬附着每回合掉层伤害，击杀归施加者）。
	#   放在 buff 累积之后、reset_turn 之前；结算后先判胜，避免死单位继续行动。
	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.unit_stats.team_id == team:
			AbnormalManager.tick_dot(unit)
	check_victory()
	if is_game_over: return

	if team == Team.PLAYER:
		SoulFireManager.tick_turn_start(UnitManager.unit_list)
		_apply_turn_start_regen()
		# ★ v6.35：独立光环回合效果已移除（aura_* 并入遗物 effects，避免双重结算）
		_apply_turn_start_fusion()
		_apply_charge_stacks()

	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.unit_stats.team_id == team:
			unit.reset_turn()

	# ★ v6.2 献祭：在 reset_turn 之后写入，保证本回合攻击加成不被清掉
	if team == Team.PLAYER:
		_apply_school_turn_start()

	if team == Team.PLAYER: BossMechanicManager.on_player_turn_start()
	else:
		BossMechanicManager.on_enemy_turn_start()
		# ★ v6.70e：敌方回合推进蓄力意图（满 N 回合后就绪，下次攻击按倍率释放）
		for u in UnitManager.unit_list:
			if is_instance_valid(u) and u.hit_points > 0 and u.unit_stats.team_id == 1:
				EnemyIntentManager.advance_turn(u)

	SignalBus.turn_changed.emit(team)


## ★ v6.2 献祭机制：回合开始扣血换本回合攻击力，扣到 1 HP 为止（不自杀）。
func _apply_school_turn_start() -> void:
	for unit in UnitManager.unit_list:
		if not is_instance_valid(unit) or unit.hit_points <= 0:
			continue
		if unit.unit_stats.team_id != Team.PLAYER:
			continue
		var lv: int = BuildManager.get_effective_school_level(unit, "献祭")
		if lv <= 0:
			unit.school_sacrifice_attack_bonus = 0.0
			continue
		var ratio: float = BuildManager.get_sacrifice_hp_cost_ratio(lv)
		var cost: int = maxi(1, int(float(unit.unit_stats.max_hp) * ratio))
		cost = mini(cost, maxi(0, unit.hit_points - 1))
		if cost > 0:
			unit.apply_damage(cost)
			SignalBus.request_damage_popup.emit(unit.global_position, cost, false, false, false)
		unit.school_sacrifice_attack_bonus = BuildManager.get_sacrifice_attack_bonus(lv)
		# ★ v6.59：F4 血祭传递阵型效果已移除（献祭自身攻击加成仍保留）
		# ★ v6.34（B2）献祭 Lv4 质变：残血(<30%)时本回合攻击加成翻倍
		if BuildManager.has_breakthrough(unit, "献祭", "sacrifice_rage") \
				and float(unit.hit_points) / float(maxi(1, unit.unit_stats.max_hp)) < 0.30:
			unit.school_sacrifice_attack_bonus *= 2.0
			SignalBus.request_hint_override.emit("献祭·焚尽 · 残血攻击翻倍！", 1.0)
		SignalBus.request_hint_override.emit(
			"献祭 · 扣 %d HP，本回合攻击 +%d%%" % [
				cost, int(unit.school_sacrifice_attack_bonus * 100.0)], 0.9)

func _refresh_all_unit_colors():
	for unit in UnitManager.unit_list:
		if unit.hit_points > 0 and unit.animated_sprite:
			unit.animated_sprite.queue_redraw()

func _apply_turn_start_regen():
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0: continue
		var regen_from_affix : float = 0.0
		for slot in u.armor_slots:
			if slot: regen_from_affix += slot.get_affix_value_float("turn_regen")
		var regen_from_set : float = SetBonusManager.get_unit_set_effect_value(u, "turn_regen")
		var regen_from_cross : float = 0.0
		var cross_active : Array = SetBonusManager.get_active_cross_bonuses()
		for entry in cross_active:
			var b2 : Dictionary = entry["data"]
			if b2.get("effect", "") == "turn_regen":
				regen_from_cross = maxf(regen_from_cross, float(b2.get("value", 0.03)))
		var regen_pct : float = regen_from_affix + maxf(regen_from_set, regen_from_cross)
		regen_pct = minf(regen_pct, 0.15)
		if regen_pct > 0.0:
			var heal : int = int(u.unit_stats.max_hp * regen_pct)
			if heal > 0:
				var old : int = u.hit_points
				u.hit_points = mini(u.hit_points + heal, u.unit_stats.max_hp)
				var actual : int = u.hit_points - old
				if actual > 0:
					u.update_hp_label()
					SignalBus.request_damage_popup.emit(u.global_position, actual, false, false, true)

func _apply_turn_start_fusion():
	if SoulFireManager.current > 0: return
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0: continue
		if u.has_fusion_effect("sacrifice_zero_recover"):
			SoulFireManager.add(1)
			return

func _apply_charge_stacks():
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0: continue
		if u.has_core_trait("charge") and not u.has_attacked:
			u.charge_stacks = mini(u.charge_stacks + 1, 5)

func run_enemy_ai():
	if is_game_over or is_moving: return
	if enemy_ai: enemy_ai.run_enemy_ai()

func _on_ai_queue_finished():
	await get_tree().create_timer(0.75).timeout
	start_turn(Team.PLAYER)

func finish_unit_action(unit: Unit):
	if is_game_over or is_moving: return
	if unit.unit_stats.team_id == 0: last_player_unit = unit
	unit.can_act_this_turn = false
	unit.set_gray(true)
	SignalBus.request_clear_highlight.emit()
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	check_all_acted()

func cancel_movement(unit: Unit):
	if is_game_over: return
	if unit.unit_stats.team_id == 0: last_player_unit = unit
	unit.revert_to_previous_position()
	unit.has_moved = false
	unit.can_act_this_turn = true
	unit.set_gray(false)
	if last_moved_unit == unit: last_moved_unit = null
	SignalBus.request_move_unit.emit(unit, unit.grid_cell)
	SignalBus.request_clear_highlight.emit()
	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE

func check_all_acted():
	if not _battle_ready: return
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
	if is_game_over or is_moving: return
	if current_turn_team == Team.PLAYER:
		start_turn(Team.ENEMY)

func clear_ai_state():
	if enemy_ai: enemy_ai.clear_state()
	is_ai_moving = false
	is_moving = false

func get_last_player_unit() -> Unit:
	return last_player_unit

func get_first_enemy_unit() -> Unit:
	if enemy_ai: return enemy_ai.first_ai_unit
	return null
