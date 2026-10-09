class_name TurnController
extends Node

var _bf : Node2D
var _turn_changed_locked : bool = false


func _init(bf : Node2D):
	_bf = bf


# ============================================================
#  回合切换回调
# ============================================================
func on_turn_changed(team : int) -> void:
	await _bf._wait_for_ui_clear()
	handle_turn_change_async(team)


func handle_turn_change_async(team : int) -> void:
	if team == TurnManager.Team.PLAYER:
		Globals.increment_battle_turn()
		_bf.turn_count_label.text = "第 " + str(Globals.current_battle_turn) + " 回合"

	if TurnManager.is_game_over:
		return
	if _turn_changed_locked:
		return
	_turn_changed_locked = true
	Globals.is_transitioning = true

	# 收起所有面板
	if is_instance_valid(_bf.menu_blocker):
		_bf.menu_blocker.visible = false
	if is_instance_valid(_bf.info_panel):
		_bf.info_panel.visible = false
	if is_instance_valid(_bf.setting_panel):
		PanelRevealer.hide_panel(_bf.setting_panel)
	if is_instance_valid(_bf.team_view_panel):
		PanelRevealer.hide_panel(_bf.team_view_panel)
	if is_instance_valid(_bf.setting_menu_panel):
		PanelRevealer.hide_panel(_bf.setting_menu_panel)
	if is_instance_valid(_bf.item_list_panel):
		PanelRevealer.hide_panel(_bf.item_list_panel)

	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}

	MusicManager.stop_music()

	await get_tree().create_timer(_bf.transition_delay_before_fade, true, false, true).timeout
	await _bf.turnlayer_manager.play_transition(team)
	await get_tree().create_timer(_bf.transition_delay_after_fade, true, false, true).timeout

	print("回合切换：", "玩家" if team == TurnManager.Team.PLAYER else "敌人")

	var target_pos = null
	if team == TurnManager.Team.PLAYER:
		var last_unit = TurnManager.get_last_player_unit()
		if is_instance_valid(last_unit):
			target_pos = _bf.grid_to_world(last_unit.grid_cell)
	else:
		var first_enemy = TurnManager.get_first_enemy_unit()
		if is_instance_valid(first_enemy):
			target_pos = _bf.grid_to_world(first_enemy.grid_cell)

	if target_pos:
		_bf.camera_controller.smooth_move_to(target_pos, _bf.turnlayer_manager.transition_duration, true)
	else:
		var fallback_pos = _get_center_position()
		if fallback_pos:
			_bf.camera_controller.smooth_move_to(fallback_pos, _bf.turnlayer_manager.transition_duration, true)

	# 音乐
	if not _bf.is_non_combat_mode:
		var is_boss = GameState.current_map_data and GameState.current_map_data.node_type == MapNode.NodeType.BOSS
		if is_boss:
			if team == TurnManager.Team.PLAYER:
				if MusicManager.config and MusicManager.config.boss_player_turn_music:
					MusicManager.play_music(MusicManager.config.boss_player_turn_music)
				else:
					MusicManager.play_player_turn_music()
			else:
				if MusicManager.config and MusicManager.config.boss_enemy_turn_music:
					MusicManager.play_music(MusicManager.config.boss_enemy_turn_music)
				else:
					MusicManager.play_enemy_turn_music()
		else:
			if team == TurnManager.Team.PLAYER:
				MusicManager.play_player_turn_music()
			else:
				MusicManager.play_enemy_turn_music()
	else:
		var music_stream = null
		if MusicManager.config and MusicManager.config.non_combat_music:
			music_stream = MusicManager.config.non_combat_music
		elif MusicManager.config and MusicManager.config.map_music:
			music_stream = MusicManager.config.map_music
		if music_stream:
			var player = MusicManager.player
			if not player.playing or player.stream != music_stream:
				MusicManager.play_music(music_stream)

	await _bf._function_handler.apply_map_functions(team)
	_bf._panel_manager.update_relic_icons()
	Globals.is_transitioning = false
	_turn_changed_locked = false

	if team == TurnManager.Team.ENEMY and not _bf.is_non_combat_mode:
		TurnManager.run_enemy_ai()


func _get_center_position() -> Vector2:
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			return unit.global_position
	var viewport_size = get_viewport().get_visible_rect().size
	var center = _bf.camera_controller.map_rect.position + _bf.camera_controller.map_rect.size / 2
	return center - viewport_size / 2


# ============================================================
#  战斗开始：遗物 + 熔铸 buff
# ============================================================
func apply_team_buffs() -> void:
	var relic_stats = GameState.get_global_relic_stats()
	var relic_effects = GameState.get_global_relic_effects()

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0:
			continue

		var sac_buffs : Dictionary = unit.unit_stats.get_sacrifice_buffs()
		for btype in sac_buffs:
			var bvalue : float = sac_buffs[btype]
			match btype:
				"attack_percent":
					unit.buff_attack_percent += bvalue
				"crit_damage_bonus":
					unit.buff_crit_damage_bonus += bvalue
				"defense_flat":
					unit.buff_defense_flat += int(bvalue)
				"damage_reduction":
					unit.buff_damage_reduction += bvalue
				"heal_bonus":
					unit.relic_heal_bonus += bvalue
				"counter_damage_bonus":
					unit.relic_counter_damage_bonus += bvalue
				_:
					pass

		var s = unit.unit_stats
		var old_max = s.max_hp
		s.max_hp       += int(relic_stats.get("max_hp", 0))
		s.strength     += int(relic_stats.get("strength", 0))
		s.dexterity    += int(relic_stats.get("dexterity", 0))
		s.intelligence += int(relic_stats.get("intelligence", 0))
		s.faith        += int(relic_stats.get("faith", 0))
		s.arcane       += int(relic_stats.get("arcane", 0))
		s.move_range   += int(relic_stats.get("move_range", 0))
		unit.buff_attack_flat       += int(relic_stats.get("attack", 0))
		unit.buff_defense_flat      += int(relic_stats.get("defense", 0))
		unit.buff_magic_attack_flat += int(relic_stats.get("magic_attack", 0))

		var hp_delta = s.max_hp - old_max
		if hp_delta > 0:
			unit.hit_points += hp_delta
		if unit.hit_points > s.max_hp:
			unit.hit_points = s.max_hp

		unit.relic_first_attack_crit_available = bool(relic_effects.get("first_attack_crit", false))
		unit.relic_low_hp_damage_reduce = float(relic_effects.get("low_hp_damage_reduce", 0.0))
		unit.relic_kill_grants_extra_move = int(relic_effects.get("kill_grants_extra_move", 0))
		unit.relic_first_spell_free_available = bool(relic_effects.get("first_spell_free", false))
		unit.relic_turn_first_hit_regen = float(relic_effects.get("turn_first_hit_regen", 0.0))
		unit.relic_strength_scale_damage = float(relic_effects.get("strength_scale_damage", 0.0))
		unit.relic_counter_damage_bonus = float(relic_effects.get("counter_damage_bonus", 0.0))
		unit.relic_heal_bonus = float(relic_effects.get("heal_bonus", 0.0))
		unit.relic_auto_revive_available = bool(relic_effects.get("auto_revive_once", false))

		unit.update_hp_label()

	print("[Battlefield] 遗物已应用 | 属性：", relic_stats, " 效果：", relic_effects)


func force_unlock() -> void:
	_turn_changed_locked = false
