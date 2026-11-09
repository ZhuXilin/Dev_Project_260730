class_name TurnController
extends Node

var _bf : Node2D
var _turn_changed_locked : bool = false

func _init(bf : Node2D):
	_bf = bf

func force_unlock() -> void:
	_turn_changed_locked = false


func on_turn_changed(team : int) -> void:
	# ★ 进入此函数瞬间，立刻锁死光标，防止玩家在过场前乱点
	if is_instance_valid(_bf._cursor_controller):
		_bf._cursor_controller.set_locked(true)
		
	await _bf._wait_for_ui_clear()
	handle_turn_change_async(team)


func handle_turn_change_async(team : int) -> void:
	if Globals.current_battle_turn == 0 and team == TurnManager.Team.PLAYER:
		var map_data = GameState.current_map_data
		if map_data and map_data.reward_multiplier > 1.0:
			var msg : String = "★ 高收益战斗 (奖励×%.1f)" % map_data.reward_multiplier
			if map_data.enemy_hp_multiplier > 1.0:
				msg += " | ⚠ 敌方 HP×%.1f" % map_data.enemy_hp_multiplier
			SignalBus.request_hint_override.emit(msg, 3.5)

	if team == TurnManager.Team.PLAYER:
		Globals.increment_battle_turn()
		_bf.turn_count_label.text = "第 " + str(Globals.current_battle_turn) + " 回合"

	if TurnManager.is_game_over: return
	if _turn_changed_locked: return
	_turn_changed_locked = true
	
	# ★ 进场、切回合期间强制锁死输入与光标
	Globals.is_transitioning = true
	if is_instance_valid(_bf._cursor_controller):
		_bf._cursor_controller.set_locked(true)

	if is_instance_valid(_bf.menu_blocker): _bf.menu_blocker.visible = false
	if is_instance_valid(_bf.info_panel): _bf.info_panel.visible = false
	if is_instance_valid(_bf.setting_panel): PanelRevealer.hide_panel(_bf.setting_panel)
	if is_instance_valid(_bf.team_view_panel): PanelRevealer.hide_panel(_bf.team_view_panel)
	if is_instance_valid(_bf.setting_menu_panel): PanelRevealer.hide_panel(_bf.setting_menu_panel)

	InputManager.selected_unit = null
	InputManager.interaction_phase = InputManager.Phase.IDLE
	InputManager.current_highlight_cells = {}
	MusicManager.stop_music()

	await get_tree().create_timer(_bf.transition_delay_before_fade, true, false, true).timeout
	await _bf.turnlayer_manager.play_transition(team)
	await get_tree().create_timer(_bf.transition_delay_after_fade, true, false, true).timeout

	var target_pos = null
	if team == TurnManager.Team.PLAYER:
		var last_unit = TurnManager.get_last_player_unit()
		if is_instance_valid(last_unit): target_pos = _bf.grid_to_world(last_unit.grid_cell)
	else:
		var first_enemy = TurnManager.get_first_enemy_unit()
		if is_instance_valid(first_enemy): target_pos = _bf.grid_to_world(first_enemy.grid_cell)

	if target_pos:
		_bf.camera_controller.smooth_move_to(target_pos, _bf.turnlayer_manager.transition_duration, true)
	else:
		var fallback_pos = _get_center_position()
		if fallback_pos:
			_bf.camera_controller.smooth_move_to(fallback_pos, _bf.turnlayer_manager.transition_duration, true)

	if not _bf.is_non_combat_mode:
		var is_boss = GameState.current_map_data and GameState.current_map_data.node_type == MapNode.NodeType.BOSS
		if is_boss:
			if team == TurnManager.Team.PLAYER:
				if MusicManager.config and MusicManager.config.boss_player_turn_music:
					MusicManager.play_music(MusicManager.config.boss_player_turn_music)
				else: MusicManager.play_player_turn_music()
			else:
				if MusicManager.config and MusicManager.config.boss_enemy_turn_music:
					MusicManager.play_music(MusicManager.config.boss_enemy_turn_music)
				else: MusicManager.play_enemy_turn_music()
		else:
			if team == TurnManager.Team.PLAYER: MusicManager.play_player_turn_music()
			else: MusicManager.play_enemy_turn_music()
	else:
		var music_stream = null
		if MusicManager.config and MusicManager.config.non_combat_music: music_stream = MusicManager.config.non_combat_music
		elif MusicManager.config and MusicManager.config.map_music: music_stream = MusicManager.config.map_music
		if music_stream:
			var player = MusicManager.player
			if not player.playing or player.stream != music_stream: MusicManager.play_music(music_stream)

	await _bf._function_handler.apply_map_functions(team)
	_bf._panel_manager.update_relic_icons()
	
	# ★ 此时所有动画和前置结算完毕，解除封锁
	Globals.is_transitioning = false
	_turn_changed_locked = false

	if team == TurnManager.Team.PLAYER and not _bf.is_non_combat_mode:
		_bf._cursor_controller.set_locked(false)
		
		if _bf.is_first_turn:
			_bf.is_first_turn = false
			var first_unit : Unit = null
			for u in UnitManager.unit_list:
				if is_instance_valid(u) and u.unit_stats.team_id == 0 and u.hit_points > 0:
					first_unit = u
					break
			
			if first_unit != null:
				var world_pos = _bf.grid_to_world(first_unit.grid_cell)
				var screen_pos = _bf.get_viewport().get_canvas_transform() * world_pos
				_bf.get_viewport().warp_mouse(screen_pos)
				SignalBus.request_show_info.emit(first_unit)

	if team == TurnManager.Team.ENEMY and not _bf.is_non_combat_mode:
		_bf._cursor_controller.set_locked(true)
		TurnManager.run_enemy_ai()


func _get_center_position() -> Vector2:
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			return unit.global_position
	var viewport_size = get_viewport().get_visible_rect().size
	var center = _bf.camera_controller.map_rect.position + _bf.camera_controller.map_rect.size / 2
	return center - viewport_size / 2


# ============================================================
#  战斗开始 buff（含光环）
# ============================================================
func apply_team_buffs() -> void:
	var relic_stats = GameState.get_global_relic_stats()
	var relic_effects = GameState.get_global_relic_effects()
	_sync_auras_to_units()

	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue

		# ★ 步 2：熔铸 buff 由"熔铸防具"承载
		var melt_attack_flat : int = 0
		for slot in unit.armor_slots:
			if slot == null: continue
			var md : ItemData = ItemManager.get_item_data(slot.item_id)
			if md == null: continue
			var meff : Dictionary = md.get("melt_armor_effect")
			if not meff is Dictionary or meff.is_empty(): 
				continue
			if meff.is_empty(): continue
			melt_attack_flat += int(meff.get("attack_flat", 0))
			var mstype : String = str(meff.get("special_type", ""))
			var msval : float = float(meff.get("special_value", 0))
			match mstype:
				"attack_percent":       unit.buff_attack_percent += msval
				"crit_damage_bonus":    unit.buff_crit_damage_bonus += msval
				"defense_flat":
					unit.buff_physical_reduction += msval * 0.01
					unit.buff_magic_reduction += msval * 0.01
				"damage_reduction":     unit.buff_damage_reduction += msval
				"heal_bonus":           unit.relic_heal_bonus += msval
				"counter_damage_bonus": unit.relic_counter_damage_bonus += msval
		if melt_attack_flat > 0:
			unit.buff_attack_flat += melt_attack_flat

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
		var def_bonus : int = int(relic_stats.get("defense", 0))
		if def_bonus > 0:
			unit.buff_physical_reduction += float(def_bonus) * 0.01
			unit.buff_magic_reduction += float(def_bonus) * 0.01
		unit.buff_magic_attack_flat += int(relic_stats.get("magic_attack", 0))

		var hp_delta = s.max_hp - old_max
		if hp_delta > 0: unit.hit_points += hp_delta
		if unit.hit_points > s.max_hp: unit.hit_points = s.max_hp

		unit.relic_first_attack_crit_available = bool(relic_effects.get("first_attack_crit", false))
		unit.relic_low_hp_damage_reduce = float(relic_effects.get("low_hp_damage_reduce", 0.0))
		unit.relic_kill_grants_extra_move = int(relic_effects.get("kill_grants_extra_move", 0))
		unit.relic_first_spell_free_available = bool(relic_effects.get("first_spell_free", false))
		unit.relic_turn_first_hit_regen = float(relic_effects.get("turn_first_hit_regen", 0.0))
		unit.relic_strength_scale_damage = float(relic_effects.get("strength_scale_damage", 0.0))
		unit.relic_counter_damage_bonus = float(relic_effects.get("counter_damage_bonus", 0.0))
		unit.relic_heal_bonus = float(relic_effects.get("heal_bonus", 0.0))
		unit.relic_auto_revive_available = bool(relic_effects.get("auto_revive_once", false))

		if unit.relic_first_attack_crit_available:
			unit.relic_first_attack_crit_remaining = 2 if GameState.is_relic_equipped_and_refined("relic_attack") else 1
		else:
			unit.relic_first_attack_crit_remaining = 0

		if unit.relic_first_spell_free_available:
			unit.relic_first_spell_free_remaining = 2 if GameState.is_relic_equipped_and_refined("relic_magic") else 1
		else:
			unit.relic_first_spell_free_remaining = 0

		unit.relic_low_hp_threshold = 0.4 if GameState.is_relic_equipped_and_refined("relic_defense") else 0.3
		unit.relic_phoenix_revive_attack_bonus = 0.2 if GameState.is_relic_equipped_and_refined("relic_phoenix") else 0.0

		unit.update_hp_label()

	_apply_flame_resonance()
	_apply_aura_buffs()
	_apply_affix_buffs()
	_apply_set_bonuses()
	_apply_cross_bonuses()
	_apply_fusion_battle_start()
	_apply_core_trait_auras()

	# ★ v5.0：防具连通组（最后应用，因为需要所有基础值已就位）
	_apply_connected_group_buffs()


func _sync_auras_to_units() -> void:
	pass


func _apply_flame_resonance() -> void:
	var resonance : Dictionary = LevelManager.current_resonance
	if resonance.is_empty(): return
	var rtype : String = resonance.get("type", "")
	var rvalue : Variant = resonance.get("value", 0)
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue
		match rtype:
			"attack_percent": unit.buff_attack_percent += float(rvalue)
			"crit_damage":    unit.buff_crit_damage_bonus += float(rvalue)
			"defense_flat":   unit.buff_physical_reduction += float(rvalue) * 0.01; unit.buff_magic_reduction += float(rvalue) * 0.01
			"heal_bonus":     unit.relic_heal_bonus += float(rvalue)


func _apply_aura_buffs() -> void:
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue
		for aid in unit.active_auras:
			if not unit.active_auras[aid]: continue
			_apply_aura_passive(unit, aid)


func _apply_aura_passive(unit : Unit, aura_id : String) -> void:
	var d : Dictionary = AuraManager.get_aura(aura_id)
	if d.is_empty(): return
	var params : Dictionary = d.get("params", {})
	match d.get("effect", ""):
		"attack_plus":
			unit.buff_attack_percent += float(params.get("attack_percent", 0.15))
		"damage_reduce_and_counter":
			unit.buff_damage_reduction += float(params.get("damage_reduction", 0.10))
			unit.relic_counter_damage_bonus += float(params.get("counter_bonus", 0.30))
		"flat_reduction":
			unit.buff_physical_reduction += float(params.get("physical_reduction", 0.10))
			unit.buff_magic_reduction += float(params.get("magic_reduction", 0.10))
		_:
			pass


func _apply_affix_buffs() -> void:
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue
		var hp_bonus : int = 0
		var move_bonus : int = 0
		var shield : int = 0
		for slot in unit.armor_slots:
			if slot == null: continue
			hp_bonus += slot.get_affix_value("hp_flat")
			move_bonus += slot.get_affix_value("move_flat")
			shield += slot.get_affix_value("start_shield")
		if hp_bonus > 0:
			unit.unit_stats.max_hp += hp_bonus
			unit.hit_points += hp_bonus
			unit.update_hp_label()
		if move_bonus > 0:
			unit.unit_stats.move_range += move_bonus
			unit.remaining_move += move_bonus
		if shield > 0:
			unit.buff_physical_reduction += float(shield) * 0.01
			unit.buff_magic_reduction += float(shield) * 0.01


func _apply_set_bonuses() -> void:
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue
		var active : Array = SetBonusManager.get_active_sets_for_unit(unit)
		for entry in active:
			var b : Dictionary = entry["bonus"]
			match b.get("effect", ""):
				"attack_percent":
					unit.buff_attack_percent += float(b.get("value", 0.0))
				"move_and_defense":
					unit.unit_stats.move_range += int(b.get("move", 0))
					unit.remaining_move += int(b.get("move", 0))
					unit.buff_physical_reduction += float(b.get("defense", 0)) * 0.01
					unit.buff_magic_reduction += float(b.get("defense", 0)) * 0.01
				"defense_flat":
					unit.buff_physical_reduction += float(b.get("value", 0)) * 0.01
					unit.buff_magic_reduction += float(b.get("value", 0)) * 0.01


func _apply_cross_bonuses():
	var active : Array = SetBonusManager.get_active_cross_bonuses()
	if active.is_empty(): return
	for entry in active:
		var b : Dictionary = entry["data"]
		var effect : String = b.get("effect", "")
		var value : Variant = b.get("value", 0)
		for unit in UnitManager.unit_list:
			if unit.unit_stats.team_id != 0: continue
			match effect:
				"attack_percent": unit.buff_attack_percent += float(value)
				"hp_flat":
					unit.unit_stats.max_hp += int(value)
					unit.hit_points += int(value)
					unit.update_hp_label()


func _apply_fusion_battle_start():
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue
		if unit.has_fusion_effect("ember_max_and_start"):
			SoulFireManager.add(2)
			break


func _apply_core_trait_auras():
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 1: continue
		for d in dirs:
			var near : Unit = UnitManager.get_unit_at_cell(unit.grid_cell + d)
			if near and near.has_core_trait("dragon_might") and near.unit_stats.team_id == 0:
				unit.buff_attack_percent -= 0.10
				break
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id != 0: continue
		for d in dirs:
			var near : Unit = UnitManager.get_unit_at_cell(unit.grid_cell + d)
			if near and near.has_core_trait("bulwark") and near != unit:
				unit.buff_damage_reduction += 0.15
				break


# ============================================================
#  ★ v5.0：防具连通组 buff
# ============================================================
## 说明：
##   - 按 GameState.party 的顺序构造 slots（保持玩家在 EquipmentConfig 里定的"插槽顺序"）
##   - 死掉/未出场的单位占位空槽（保持行对齐，跨单位连通自然断开）
##   - 战场单位的 armor_slots 用实时数据（事件可能改变装备）
##   - 连通 buff 独立轨：只加攻击% / 防御% / HP%，不与遗物/精炼/套装叠乘
func _apply_connected_group_buffs():
	if GameState.party.is_empty(): return

	# 1. 构造 slots：按 party 顺序，死掉的占空
	var slots : Array = []
	for i in range(GameState.party.size()):
		var pu : UnitData = GameState.party[i]
		var battle_unit : Unit = null
		for u in UnitManager.unit_list:
			if not is_instance_valid(u): continue
			if u.unit_stats.team_id != 0: continue
			if u.unit_stats.unit_name == pu.unit_name \
					and u.unit_stats.display_name == pu.display_name:
				battle_unit = u
				break

		if battle_unit == null or battle_unit.hit_points <= 0:
			var empty_slots : Array = []
			for j in range(pu.max_armor_slots):
				empty_slots.append(null)
			slots.append(empty_slots)
		else:
			slots.append(battle_unit.armor_slots)

	# 2. 计算连通组
	var groups : Array = ConnectedGroupCalculator.compute_groups(slots)
	if groups.is_empty(): return

	var bonus : Dictionary = ConnectedGroupCalculator.evaluate_groups(groups)

	# 3. 应用到所有活着的我方单位
	for u in UnitManager.unit_list:
		if not is_instance_valid(u): continue
		if u.unit_stats.team_id != 0: continue
		if u.hit_points <= 0: continue

		u.buff_attack_percent += bonus["attack_pct"]
		u.buff_physical_reduction += bonus["defense_pct"]
		u.buff_magic_reduction += bonus["defense_pct"]

		var hp_bonus : int = int(u.unit_stats.max_hp * bonus["hp_pct"])
		if hp_bonus > 0:
			u.unit_stats.max_hp += hp_bonus
			u.hit_points = mini(u.hit_points + hp_bonus, u.unit_stats.max_hp)
			u.update_hp_label()

	print("[连通组] 组数=%d，跨三=%d，攻击+%.1f%% 防御+%.1f%% HP+%.1f%%" % [
		bonus["total_groups"], bonus["cross_3_groups"],
		bonus["attack_pct"] * 100, bonus["defense_pct"] * 100, bonus["hp_pct"] * 100])


# ============================================================
#  回合开始钩子
# ============================================================
func _apply_turn_start_auras():
	var active_auras : Dictionary = {}
	for u in UnitManager.unit_list:
		if u.unit_stats.team_id != 0 or u.hit_points <= 0: continue
		for aid in u.active_auras:
			if u.active_auras[aid]: active_auras[aid] = true
	for aid in active_auras:
		_apply_turn_start_aura_effect(aid)


func _apply_turn_start_aura_effect(aid : String):
	var d : Dictionary = AuraManager.get_aura(aid)
	if d.is_empty(): return
	match d.get("effect", ""):
		"turn_start_gain_soul_fire":
			var gain : int = int(d.get("params", {}).get("soul_fire_gain", 1))
			SoulFireManager.add(gain)
		_: pass


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
