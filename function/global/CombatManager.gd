extends Node

var QUALITY_MULT : Dictionary = {"common":1.0,"rare":1.25,"epic":1.5,"legendary":1.8}
var CRIT_BASE_CHANCE : float = 0.05
var CRIT_PER_DEXTERITY : float = 0.005
var CRIT_CHANCE_BY_QUALITY : Dictionary = {"common":0.0,"rare":0.03,"epic":0.05,"legendary":0.08}
var CRIT_DAMAGE_MULT : float = 1.5
var REDUCTION_CAP : float = 0.75
var MIN_DAMAGE_FLOOR : float = 0.10
var FOLLOW_UP_DEX_GAP : int = 4

var DOUBLE_ATTACK_MULT : Array = [0.8, 0.9, 1.0]
var BLEED_DAMAGE_PERCENT : Array = [0.15, 0.20, 0.25]
var BLEED_MAX_STACKS : int = 5
var SPELL_CHAIN_MULT : Array = [0.8, 0.9, 1.0]
var COUNTER_BOOST_MULT : Array = [1.5, 1.75, 2.0]
var HEAL_BOOST_MULT : Array = [1.3, 1.5, 1.7]
var LIFESTEAL_PERCENT : Array = [0.2, 0.3, 0.4]
var COMBO_MULT_PER_HIT : Array = [0.15, 0.25, 0.35]
var BLOOD_RAGE_HEAL_PERCENT : Array = [0.15, 0.20, 0.25]
var ZEAL_PER_STACK : Array = [0.10, 0.15, 0.20]
var ZEAL_MAX_STACKS : int = 5

const PERFORMANCE_DURATION : float = 0.5
const LUNGE_DURATION : float = 0.15
const PRE_DAMAGE_DELAY : float = 0.10
const POST_DAMAGE_DELAY : float = 0.28
const EXTRA_HIT_DELAY : float = 0.15

func _ready():
	reload_config()

func reload_config():
	var cfg := GameConfigManager.get_file("combat_config.json")
	QUALITY_MULT = cfg.get("quality_mult", QUALITY_MULT).duplicate()
	CRIT_BASE_CHANCE = float(cfg.get("crit_base_chance", CRIT_BASE_CHANCE))
	CRIT_PER_DEXTERITY = float(cfg.get("crit_per_dexterity", CRIT_PER_DEXTERITY))
	CRIT_CHANCE_BY_QUALITY = cfg.get("crit_chance_by_quality", CRIT_CHANCE_BY_QUALITY).duplicate()
	CRIT_DAMAGE_MULT = float(cfg.get("crit_damage_mult", CRIT_DAMAGE_MULT))
	REDUCTION_CAP = float(cfg.get("reduction_cap", REDUCTION_CAP))
	MIN_DAMAGE_FLOOR = float(cfg.get("min_damage_floor", MIN_DAMAGE_FLOOR))
	FOLLOW_UP_DEX_GAP = int(cfg.get("follow_up_dex_gap", FOLLOW_UP_DEX_GAP))

	var tp : Dictionary = cfg.get("talent_params", {})
	DOUBLE_ATTACK_MULT = tp.get("double_attack_mult", DOUBLE_ATTACK_MULT).duplicate()
	BLEED_DAMAGE_PERCENT = tp.get("bleed_damage_percent", BLEED_DAMAGE_PERCENT).duplicate()
	BLEED_MAX_STACKS = int(tp.get("bleed_max_stacks", BLEED_MAX_STACKS))
	SPELL_CHAIN_MULT = tp.get("spell_chain_mult", SPELL_CHAIN_MULT).duplicate()
	COUNTER_BOOST_MULT = tp.get("counter_boost_mult", COUNTER_BOOST_MULT).duplicate()
	HEAL_BOOST_MULT = tp.get("heal_boost_mult", HEAL_BOOST_MULT).duplicate()
	LIFESTEAL_PERCENT = tp.get("lifesteal_percent", LIFESTEAL_PERCENT).duplicate()
	COMBO_MULT_PER_HIT = tp.get("combo_mult_per_hit", COMBO_MULT_PER_HIT).duplicate()
	BLOOD_RAGE_HEAL_PERCENT = tp.get("blood_rage_heal_percent", BLOOD_RAGE_HEAL_PERCENT).duplicate()
	ZEAL_PER_STACK = tp.get("zeal_per_stack", ZEAL_PER_STACK).duplicate()
	ZEAL_MAX_STACKS = int(tp.get("zeal_max_stacks", ZEAL_MAX_STACKS))
	print("[CombatManager] 已加载")

func get_active_skill_range_bonus(unit: Unit) -> int:
	if unit == null: return 0
	var ready_skills : Array = TalentManager.get_ready_active_skills(unit)
	var bonus : int = 0
	for skill_id in ready_skills:
		var data = TalentManager.get_talent_data(skill_id)
		if data:
			bonus = maxi(bonus, int(data.effect_params.get("range_bonus", 0)))
	return bonus

func get_attackable_targets(unit: Unit) -> Array:
	var weapon_data = unit.get_weapon_data()
	if not weapon_data: return []
	var up_lv : int = unit.weapon_slot.upgrade_level if unit.weapon_slot else 0
	var max_range : int = WeaponUpgradeHelper.get_effective_attack_range(weapon_data, up_lv)
	var min_range : int = weapon_data.min_attack_range
	max_range += get_active_skill_range_bonus(unit)
	var is_healer = (weapon_data.category == "staff" or weapon_data.attack_style == "heal")
	var targets = []
	for x in range(-max_range, max_range+1):
		for y in range(-max_range, max_range+1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range: continue
			var cell = unit.grid_cell + Vector2i(x, y)
			if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y: continue
			var target = UnitManager.get_unit_at_cell(cell)
			if not target or target.hit_points <= 0: continue
			if is_healer:
				if target.unit_stats.team_id == unit.unit_stats.team_id: targets.append(target)
			else:
				if target.unit_stats.team_id != unit.unit_stats.team_id: targets.append(target)
	if is_healer:
		targets.sort_custom(func(a, b):
			return (a.unit_stats.max_hp - a.hit_points) > (b.unit_stats.max_hp - b.hit_points))
	else:
		targets.sort_custom(func(a, b):
			var da = abs(a.grid_cell.x - unit.grid_cell.x) + abs(a.grid_cell.y - unit.grid_cell.y)
			var db = abs(b.grid_cell.x - unit.grid_cell.x) + abs(b.grid_cell.y - unit.grid_cell.y)
			return da < db)
	return targets

func attempt_attack_after_move(unit: Unit):
	var targets = get_attackable_targets(unit)
	if targets.size() > 0:
		await execute_attack(unit, targets[0])

func _is_magic_attack(weapon_data: ItemData) -> bool:
	if weapon_data == null: return false
	if weapon_data.attack_style == "magic": return true
	if weapon_data.magic_attack.get("ignore_defense", false): return true
	return false

func _calc_reduction(defender: Unit, is_magic: bool) -> float:
	var s = defender.unit_stats
	var base : float = s.magic_reduction if is_magic else s.physical_reduction
	var armor_bonus : float = 0.0
	for slot in defender.armor_slots:
		if slot:
			var d : ItemData = ItemManager.get_item_data(slot.item_id)
			if d:
				var qm : float = QUALITY_MULT.get(d.quality, 1.0)
				armor_bonus += (d.magic_reduction if is_magic else d.physical_reduction) * qm

	var affix_bonus : float = 0.0
	for slot in defender.armor_slots:
		if slot:
			affix_bonus += float(slot.get_affix_value("defense_flat")) * 0.01

	var low_hp_bonus : float = 0.0
	if defender.relic_low_hp_damage_reduce > 0.0:
		var hp_ratio = float(defender.hit_points) / float(max(1, s.max_hp))
		if hp_ratio < defender.relic_low_hp_threshold:
			low_hp_bonus = defender.relic_low_hp_damage_reduce

	var buff_bonus : float = (defender.buff_magic_reduction if is_magic else defender.buff_physical_reduction)
	buff_bonus += defender.buff_damage_reduction

	var total : float = base + armor_bonus + affix_bonus + low_hp_bonus + buff_bonus
	return clampf(total, 0.0, REDUCTION_CAP)

func _calc_penetration(attacker: Unit, is_magic: bool) -> float:
	var wdata = attacker.get_weapon_data()
	if not wdata: return 0.0
	var w_pen : float = wdata.magic_penetration if is_magic else wdata.physical_penetration
	return w_pen

func calculate_damage(attacker: Unit, defender: Unit) -> int:
	var weapon_data = attacker.get_weapon_data()
	if not weapon_data: return 0
	var is_magic : bool = _is_magic_attack(weapon_data)
	var quality_mult : float = QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_lv : int = attacker.weapon_slot.upgrade_level if attacker.weapon_slot else 0
	var base_attack : float = WeaponUpgradeHelper.get_effective_base_attack(weapon_data, upgrade_lv) * quality_mult
	var modifier = weapon_data.modifier
	var atk_bonus = 0.0
	for attr in modifier:
		atk_bonus += attacker.unit_stats.get_effective_attr(attr) * modifier[attr]
	var total_attack = base_attack + atk_bonus + attacker.buff_attack_flat
	if is_magic: total_attack += attacker.buff_magic_attack_flat
	total_attack *= (1.0 + attacker.buff_attack_percent)
	if attacker.relic_strength_scale_damage > 0.0:
		var str_val = attacker.unit_stats.get_effective_attr("strength")
		total_attack *= (1.0 + str_val * attacker.relic_strength_scale_damage)

	var reduction : float = _calc_reduction(defender, is_magic)
	var penetration : float = _calc_penetration(attacker, is_magic)
	var effective_reduction : float = clampf(reduction - penetration, 0.0, 1.0)
	var damage_raw : float = total_attack * (1.0 - effective_reduction)
	var floor_raw : float = total_attack * MIN_DAMAGE_FLOOR
	var damage : int = max(1, int(max(damage_raw, floor_raw)))

	if not weapon_data.heavy_attack.is_empty():
		var mult : float = 1.0
		if attacker.has_core_trait("charge"):
			var per_stack : float = 0.2
			var max_mult : float = float(weapon_data.heavy_attack.get("charge_multiplier", 2.0))
			mult = minf(1.0 + per_stack * float(attacker.charge_stacks), max_mult)
		else:
			mult = float(weapon_data.heavy_attack.get("damage_multiplier", 1.0))
		damage = int(damage * mult)

	var atk_affix_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot: atk_affix_bonus += slot.get_affix_value("attack_flat")
	damage += atk_affix_bonus

	if defender.unit_stats.team_id == 0:
		var taken_mult : float = SoulFireManager.get_damage_taken_mult()
		if taken_mult > 1.0: damage = int(damage * taken_mult)
	return max(1, damage)

func _roll_crit(attacker: Unit) -> bool:
	var chance : float = CRIT_BASE_CHANCE
	chance += attacker.unit_stats.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
	var wdata = attacker.get_weapon_data()
	if wdata: chance += CRIT_CHANCE_BY_QUALITY.get(wdata.quality, 0.0)
	chance += attacker.get_total_affix_value_float("crit_chance")
	return randf() < chance

func _can_follow_up(attacker: Unit, defender: Unit) -> bool:
	if attacker == null or defender == null: return false
	if defender.hit_points <= 0: return false
	var atk_dex : int = attacker.unit_stats.get_effective_attr("dexterity")
	var def_dex : int = defender.unit_stats.get_effective_attr("dexterity")
	return atk_dex >= def_dex + FOLLOW_UP_DEX_GAP

func _get_active_skill_cost(sdata) -> int:
	if sdata == null: return SoulFireManager.COST_SKILL_MIN
	var ep : Dictionary = sdata.effect_params if sdata.effect_params else {}
	var explicit : int = int(ep.get("soul_fire_cost", 0))
	if explicit > 0: return explicit
	if sdata.effect_type == "heal": return SoulFireManager.COST_SKILL_MAX
	return SoulFireManager.COST_SKILL_MIN

func _try_boss_revive(defender : Unit, _attacker : Unit) -> bool:
	if not BossMechanicManager.on_boss_defeated(defender): return false
	SignalBus.request_screen_shake.emit(0.4, 8.0, Vector2.ZERO)
	return true

func execute_attack(attacker: Unit, defender: Unit, forced_skill_id: String = "") -> bool:
	if attacker.get_equipped_weapon_id() == "":
		Globals.is_performing_action = false
		return false
	_face_each_other(attacker, defender)
	Globals.is_performing_action = true

	if attacker.get_weapon_type() == "staff":
		await _execute_heal(attacker, defender, forced_skill_id)
		Globals.is_performing_action = false
		return true

	await _play_lunge_attack(attacker, defender)
	var damage = calculate_damage(attacker, defender)
	if attacker.has_core_trait("charge") and attacker.charge_stacks > 0:
		attacker.charge_stacks = 0

	var active_skill_id : String = ""
	var active_skill_data = null
	if forced_skill_id != "":
		var sdata = TalentManager.get_talent_data(forced_skill_id)
		if sdata:
			var cost : int = _get_active_skill_cost(sdata)
			if SoulFireManager.can_spend(cost):
				active_skill_id = forced_skill_id
				active_skill_data = sdata
			else:
				print("[主动技能] %s 魂火不足" % attacker.unit_stats.unit_name)

	var force_crit : bool = false
	var ignore_def : bool = false
	var splash_percent : float = 0.0
	var aoe_percent : float = 0.0
	var hp_cost_percent : float = 0.0
	var taunt_rounds : int = 0
	if active_skill_data:
		var ep : Dictionary = active_skill_data.effect_params
		damage = int(damage * float(ep.get("damage_mult", 1.0)))
		force_crit = bool(ep.get("force_crit", false))
		ignore_def = bool(ep.get("ignore_defense", false))
		splash_percent = float(ep.get("splash_percent", 0.0))
		aoe_percent = float(ep.get("aoe_percent", 0.0))
		hp_cost_percent = float(ep.get("hp_cost_percent", 0.0))
		taunt_rounds = int(ep.get("taunt_rounds", 0))

	var target_key = "%s_%d_%d" % [defender.unit_stats.unit_name, defender.grid_cell.x, defender.grid_cell.y]
	if attacker.zeal_target == target_key:
		attacker.zeal_stacks = mini(attacker.zeal_stacks + 1, ZEAL_MAX_STACKS)
	else:
		attacker.zeal_target = target_key
		attacker.zeal_stacks = 1
	if attacker.zeal_stacks > 1 and TalentManager.is_talent_ready(attacker, "zeal"):
		var lv_zeal = _get_effective_talent_level(attacker, "zeal")
		var per = ZEAL_PER_STACK[clampi(lv_zeal - 1, 0, ZEAL_PER_STACK.size() - 1)]
		damage = int(damage * (1.0 + (attacker.zeal_stacks - 1) * per))
		TalentManager.reset_talent(attacker, "zeal")

	if attacker.combo_last_target == target_key:
		attacker.combo_count += 1
	else:
		attacker.combo_last_target = target_key
		attacker.combo_count = 1
	if attacker.combo_count > 1 and TalentManager.is_talent_ready(attacker, "combo"):
		var lv_combo = _get_effective_talent_level(attacker, "combo")
		var per_hit = COMBO_MULT_PER_HIT[clampi(lv_combo - 1, 0, COMBO_MULT_PER_HIT.size() - 1)]
		damage = int(damage * (1.0 + (attacker.combo_count - 1) * per_hit))
		TalentManager.reset_talent(attacker, "combo")

	var is_crit := false
	var crit_mult : float = CRIT_DAMAGE_MULT
	if attacker.unit_stats.team_id == 0: crit_mult += SoulFireManager.get_crit_damage_bonus()
	crit_mult += attacker.get_total_affix_value_float("crit_damage")

	if force_crit:
		is_crit = true
	elif TalentManager.is_talent_ready(attacker, "crit"):
		var lv_crit = _get_effective_talent_level(attacker, "crit")
		crit_mult = 2.0 + (lv_crit - 1) * 0.5 + attacker.buff_crit_damage_bonus
		crit_mult += attacker.get_total_affix_value_float("crit_damage")
		is_crit = true
		TalentManager.reset_talent(attacker, "crit")
	elif attacker.relic_first_attack_crit_remaining > 0:
		crit_mult += attacker.buff_crit_damage_bonus
		is_crit = true
		attacker.relic_first_attack_crit_remaining -= 1
		if attacker.relic_first_attack_crit_remaining <= 0:
			attacker.relic_first_attack_crit_available = false
	elif _roll_crit(attacker):
		crit_mult += attacker.buff_crit_damage_bonus
		is_crit = true

	if is_crit: damage = int(damage * crit_mult)

	if hp_cost_percent > 0.0:
		var hp_cost = int(attacker.unit_stats.max_hp * hp_cost_percent)
		attacker.hit_points = max(1, attacker.hit_points - hp_cost)
		attacker.update_hp_label()
		SignalBus.request_damage_popup.emit(attacker.global_position, hp_cost, false, false, false)

	await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout
	var defeated = _apply_damage_with_effects(defender, damage, attacker, is_crit)

	if attacker.weapon_slot:
		var up_lv : int = attacker.weapon_slot.upgrade_level
		if WeaponUpgradeHelper.has_special_effect(up_lv):
			if randf() < WeaponUpgradeHelper.SPECIAL_EFFECT_CHANCE:
				defender.can_act_this_turn = false
				defender.set_gray(true)
				SignalBus.request_hint_override.emit("★ 眩晕！%s 无法行动" % defender.unit_stats.unit_name, 1.0)

	var flame_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot: flame_bonus += slot.get_affix_value("flame_damage")
	if flame_bonus > 0 and defender.hit_points > 0:
		var extra_flame_dead : bool = defender.apply_damage(flame_bonus)
		SignalBus.request_damage_popup.emit(defender.global_position, flame_bonus, false, false, false)
		if extra_flame_dead: defeated = true

	var splash_sf : float = SoulFireManager.get_splash_percent()
	if splash_sf > 0.0 and attacker.unit_stats.team_id == 0 and defender.hit_points > 0:
		await _apply_burning_splash(attacker, defender, damage, splash_sf)

	await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout
	if not _is_alive(attacker):
		Globals.is_performing_action = false
		return true

	if active_skill_data:
		if splash_percent > 0.0: await _apply_splash(attacker, defender, damage, splash_percent, is_crit)
		if aoe_percent > 0.0: await _apply_aoe(attacker, defender, damage, aoe_percent, is_crit)
		if taunt_rounds > 0:
			attacker.taunt_rounds = taunt_rounds
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var c = attacker.grid_cell + d
				var e = UnitManager.get_unit_at_cell(c)
				if e and e.unit_stats.team_id != attacker.unit_stats.team_id and e.hit_points > 0:
					e.taunt_by = attacker
					e.taunt_rounds_left = taunt_rounds
		TalentManager.consume_active_skill(attacker, active_skill_id)
		SoulFireManager.spend(_get_active_skill_cost(active_skill_data))

	if defeated:
		if _try_boss_revive(defender, attacker):
			_finish_attack(attacker, defender)
			Globals.is_performing_action = false
			return true
		var cleave_triggered := _on_kill(attacker, defender)
		await _play_death_animation(defender)
		UnitManager.unregister_unit(defender)
		defender.queue_free()
		if cleave_triggered:
			_show_menu_after_action(attacker)
			Globals.is_performing_action = false
			return true
		_finish_attack(attacker, defender)
		Globals.is_performing_action = false
		return true

	if TalentManager.is_talent_ready(attacker, "lifesteal"):
		var lv_ls = _get_effective_talent_level(attacker, "lifesteal")
		var pct = LIFESTEAL_PERCENT[clampi(lv_ls - 1, 0, LIFESTEAL_PERCENT.size() - 1)]
		pct += attacker.buff_lifesteal_percent
		var heal = int(damage * pct)
		var old_hp = attacker.hit_points
		attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
		var actual = attacker.hit_points - old_hp
		if actual > 0:
			attacker.update_hp_label()
			SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)
		TalentManager.reset_talent(attacker, "lifesteal")

	if TalentManager.is_talent_ready(attacker, "double_attack"):
		var level = _get_effective_talent_level(attacker, "double_attack")
		var mult = DOUBLE_ATTACK_MULT[level - 1]
		var extra_damage = int(damage * mult)
		TalentManager.reset_talent(attacker, "double_attack")
		await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
		if not _is_alive(attacker):
			Globals.is_performing_action = false
			return true
		await _play_lunge_attack(attacker, defender)
		await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout
		var extra_dead = defender.apply_damage(extra_damage)
		_play_hurt_effect(defender, attacker)
		SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)
		await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout
		if extra_dead:
			if _try_boss_revive(defender, attacker):
				_finish_attack(attacker, defender)
				Globals.is_performing_action = false
				return true
			var cleave_triggered := _on_kill(attacker, defender)
			await _play_death_animation(defender)
			UnitManager.unregister_unit(defender)
			defender.queue_free()
			if cleave_triggered:
				_show_menu_after_action(attacker)
				Globals.is_performing_action = false
				return true
			_finish_attack(attacker, defender)
			Globals.is_performing_action = false
			return true

	if not _is_alive(attacker):
		Globals.is_performing_action = false
		return true

	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "spellbook" or attacker.get_weapon_type() == "staff":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]
			if attacker.get_weapon_type() == "staff":
				TalentManager.reset_talent(attacker, "spell_chain")
				await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
				var weapon_data = attacker.get_weapon_data()
				var base_heal = weapon_data.heal_effect.get("base_heal", 0)
				var faith_bonus = attacker.unit_stats.faith * weapon_data.heal_effect.get("faith_multiplier", 1.0)
				var extra_heal = int((base_heal + faith_bonus) * mult)
				var old_hp = defender.hit_points
				defender.hit_points = min(defender.hit_points + extra_heal, defender.unit_stats.max_hp)
				var actual = defender.hit_points - old_hp
				defender.update_hp_label()
				SignalBus.request_damage_popup.emit(defender.global_position, actual, false, false, true)
			else:
				var extra_damage = int(damage * mult)
				TalentManager.reset_talent(attacker, "spell_chain")
				await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
				if not _is_alive(attacker):
					Globals.is_performing_action = false
					return true
				await _play_lunge_attack(attacker, defender)
				await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout
				var extra_dead = defender.apply_damage(extra_damage)
				_play_hurt_effect(defender, attacker)
				SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)
				await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout
				if extra_dead:
					if _try_boss_revive(defender, attacker):
						_finish_attack(attacker, defender)
						Globals.is_performing_action = false
						return true
					var cleave_triggered := _on_kill(attacker, defender)
					await _play_death_animation(defender)
					UnitManager.unregister_unit(defender)
					defender.queue_free()
					if cleave_triggered:
						_show_menu_after_action(attacker)
						Globals.is_performing_action = false
						return true
					_finish_attack(attacker, defender)
					Globals.is_performing_action = false
					return true

	if not _is_alive(attacker):
		Globals.is_performing_action = false
		return true

	# ★ v4.6 追击
	if _is_alive(attacker) and _is_alive(defender) and _can_follow_up(attacker, defender):
		var follow_dmg : int = calculate_damage(attacker, defender)
		await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
		if _is_alive(attacker):
			await _play_lunge_attack(attacker, defender)
			await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout
			var follow_dead = defender.apply_damage(follow_dmg)
			_play_hurt_effect(defender, attacker)
			SignalBus.request_damage_popup.emit(defender.global_position, follow_dmg, false, false, false)
			await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout
			if follow_dead:
				if not _try_boss_revive(defender, attacker):
					_on_kill(attacker, defender)
					await _play_death_animation(defender)
					UnitManager.unregister_unit(defender)
					defender.queue_free()

	if _can_counter_attack(attacker, defender):
		await _execute_counter(attacker, defender)
	if not _is_alive(attacker):
		Globals.is_performing_action = false
		return true

	var free_action : bool = _consume_first_spell_free(attacker)
	_finish_attack(attacker, defender, free_action)
	Globals.is_performing_action = false
	return true

# ...（其余 _execute_heal / _apply_burning_splash / _play_lunge_attack / _play_hurt_effect / _play_death_animation / _on_kill / _apply_splash / _apply_aoe / _apply_damage_with_effects / _consume_first_spell_free / _try_revive / _get_effective_talent_level / _can_counter_attack / _execute_counter / _is_alive / _finish_attack / _show_menu_after_action / _post_attack_check / _face_each_other / get_unit_attack_stats 保持上一轮完整版本一致）

func _execute_heal(attacker: Unit, defender: Unit, forced_skill_id: String = "") -> bool:
	if defender.unit_stats.team_id != attacker.unit_stats.team_id:
		Globals.is_performing_action = false
		return false
	var weapon_data = attacker.get_weapon_data()
	var heal_amount = weapon_data.heal_effect.get("base_heal", 0)
	var faith_bonus = attacker.unit_stats.faith * weapon_data.heal_effect.get("faith_multiplier", 1.0)
	var total_heal = int(heal_amount + faith_bonus)
	if attacker.relic_heal_bonus > 0.0: total_heal = int(total_heal * (1.0 + attacker.relic_heal_bonus))
	var heal_affix_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot: heal_affix_bonus += slot.get_affix_value_float("heal_boost")
	total_heal = int(total_heal * (1.0 + heal_affix_bonus))
	if TalentManager.is_talent_ready(attacker, "heal_boost"):
		var level = _get_effective_talent_level(attacker, "heal_boost")
		total_heal = int(total_heal * HEAL_BOOST_MULT[level - 1])
		TalentManager.reset_talent(attacker, "heal_boost")
	var old_hp = defender.hit_points
	defender.hit_points = min(defender.hit_points + total_heal, defender.unit_stats.max_hp)
	var actual_heal = defender.hit_points - old_hp
	defender.update_hp_label()
	SignalBus.request_damage_popup.emit(defender.global_position, actual_heal, false, false, true)
	SoundManager.play_heal_sound()
	if forced_skill_id != "":
		var skill_data = TalentManager.get_talent_data(forced_skill_id)
		if skill_data:
			var mass_pct = float(skill_data.effect_params.get("mass_heal_percent", 0.0))
			if mass_pct > 0.0:
				var cost : int = _get_active_skill_cost(skill_data)
				if SoulFireManager.can_spend(cost):
					var mass_heal = int(actual_heal * mass_pct)
					for u in UnitManager.unit_list:
						if u.unit_stats.team_id != attacker.unit_stats.team_id: continue
						if u == defender or u.hit_points <= 0: continue
						var old = u.hit_points
						u.hit_points = mini(u.hit_points + mass_heal, u.unit_stats.max_hp)
						var real = u.hit_points - old
						if real > 0:
							u.update_hp_label()
							SignalBus.request_damage_popup.emit(u.global_position, real, false, false, true)
					TalentManager.consume_active_skill(attacker, forced_skill_id)
					SoulFireManager.spend(cost)
	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
	var free_action : bool = _consume_first_spell_free(attacker)
	_finish_attack(attacker, defender, free_action)
	Globals.is_performing_action = false
	return true

func _apply_burning_splash(attacker : Unit, center : Unit, base_damage : int, percent : float):
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var t : Unit = UnitManager.get_unit_at_cell(center.grid_cell + d)
		if not t or t.hit_points <= 0: continue
		if t.unit_stats.team_id == attacker.unit_stats.team_id: continue
		var splash_dmg : int = maxi(1, int(base_damage * percent))
		var dead : bool = _apply_damage_with_effects(t, splash_dmg, attacker, false)
		if dead:
			if _try_boss_revive(t, attacker): continue
			_on_kill(attacker, t)
			await _play_death_animation(t)
			UnitManager.unregister_unit(t)
			t.queue_free()

func _play_lunge_attack(attacker: Unit, defender: Unit) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender): return
	if not attacker.animated_sprite: return
	var snd_tween = attacker.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(func(): SoundManager.play_attack_sound()).set_delay(LUNGE_DURATION * 0.35)
	var mat = attacker.animated_sprite.material as ShaderMaterial
	if not mat:
		await get_tree().create_timer(0.08, true, false, true).timeout
		return
	var dir = (defender.global_position - attacker.global_position)
	if dir.length() < 0.001: return
	dir = dir.normalized()
	mat.set_shader_parameter("hit_offset_amount", dir * 6.0)
	mat.set_shader_parameter("hit_duration", LUNGE_DURATION)
	mat.set_shader_parameter("hit_elapsed", 0.0)
	mat.set_shader_parameter("hit_flash_color", Color.WHITE)
	mat.set_shader_parameter("hit_enable_flash", false)
	var tween = attacker.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_method(func(val):
		if is_instance_valid(mat): mat.set_shader_parameter("hit_elapsed", val),
		0.0, LUNGE_DURATION, LUNGE_DURATION)
	tween.tween_callback(func():
		if is_instance_valid(mat):
			mat.set_shader_parameter("hit_elapsed", 0.0)
			mat.set_shader_parameter("hit_offset_amount", Vector2.ZERO))
	await tween.finished

func _play_hurt_effect(defender: Unit, attacker: Unit) -> void:
	if not is_instance_valid(defender): return
	var hit_dir = Vector2(1, 0)
	if is_instance_valid(attacker):
		var d = defender.global_position - attacker.global_position
		if d.length() > 0.001: hit_dir = d.normalized()
	defender.play_hit_effect(hit_dir, true)
	SignalBus.request_screen_shake.emit(0.15, 4.0, hit_dir)
	var snd_tween = defender.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(func(): SoundManager.play_hit_sound()).set_delay(MapConst.HIT_OFFSET_DURATION * 0.35)

func _play_death_animation(unit: Unit) -> void:
	if not is_instance_valid(unit): return
	var snd_tween = unit.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(func(): SoundManager.play_death_sound()).set_delay(0.05)
	var hp_label = unit.get_node_or_null("HPLabel")
	if hp_label: hp_label.visible = false
	if not unit.animated_sprite: return
	var mat = unit.animated_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("hit_flash_color", Color(1.0, 1.0, 1.0))
		mat.set_shader_parameter("hit_duration", 1.0)
		mat.set_shader_parameter("hit_elapsed", 0.0)
		mat.set_shader_parameter("hit_offset_amount", Vector2.ZERO)
		for i in range(3):
			mat.set_shader_parameter("hit_enable_flash", true)
			await get_tree().create_timer(0.08, true, false, true).timeout
			mat.set_shader_parameter("hit_enable_flash", false)
			await get_tree().create_timer(0.08, true, false, true).timeout
		mat.set_shader_parameter("hit_enable_flash", false)
	unit.animated_sprite.visible = false
	await get_tree().create_timer(0.1, true, false, true).timeout

func _on_kill(attacker: Unit, _defender: Unit) -> bool:
	if not is_instance_valid(attacker): return false
	if TalentManager.is_talent_ready(attacker, "blood_rage"):
		var lv = _get_effective_talent_level(attacker, "blood_rage")
		var pct = BLOOD_RAGE_HEAL_PERCENT[clampi(lv - 1, 0, BLOOD_RAGE_HEAL_PERCENT.size() - 1)]
		var heal = int(attacker.unit_stats.max_hp * pct)
		var old_hp = attacker.hit_points
		attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
		var actual = attacker.hit_points - old_hp
		if actual > 0:
			attacker.update_hp_label()
			SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)
		TalentManager.reset_talent(attacker, "blood_rage")

	var cleave_triggered := false
	if TalentManager.is_talent_ready(attacker, "cleave"):
		attacker.has_attacked = false
		attacker.has_acted = false
		attacker.movement_after_attack = false
		TalentManager.reset_talent(attacker, "cleave")
		cleave_triggered = true

	if attacker.relic_kill_grants_extra_move > 0:
		attacker.remaining_move += attacker.relic_kill_grants_extra_move
		attacker.has_moved = false

	for aid in attacker.active_auras:
		if not attacker.active_auras[aid]: continue
		_apply_aura_kill_effect(attacker, aid)

	var bonus_sf : int = 0
	for slot in attacker.armor_slots:
		if slot: bonus_sf += slot.get_affix_value("soul_fire_gain")
	if bonus_sf > 0: SoulFireManager.add(bonus_sf)

	var active_sets : Array = SetBonusManager.get_active_sets_for_unit(attacker)
	for entry in active_sets:
		var b : Dictionary = entry["bonus"]
		if b.get("effect", "") == "kill_heal":
			var heal_pct : float = float(b.get("value", 0.15))
			var heal : int = int(attacker.unit_stats.max_hp * heal_pct)
			var old : int = attacker.hit_points
			attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
			var actual2 : int = attacker.hit_points - old
			if actual2 > 0:
				attacker.update_hp_label()
				SignalBus.request_damage_popup.emit(attacker.global_position, actual2, false, false, true)

	var cross_bonuses : Array = SetBonusManager.get_active_cross_bonuses()
	for entry in cross_bonuses:
		var cb : Dictionary = entry.get("data", {})
		if cb.get("effect", "") == "kill_soul_fire":
			var val : int = int(cb.get("value", 0))
			if val > 0: SoulFireManager.add(val)

	if attacker.unit_stats.team_id == 0: SoulFireManager.on_kill()
	return cleave_triggered

func _apply_aura_kill_effect(attacker : Unit, aura_id : String):
	var d : Dictionary = AuraManager.get_aura(aura_id)
	if d.is_empty(): return
	var params : Dictionary = d.get("params", {})
	match d.get("effect", ""):
		"kill_gain_soul_fire":
			var gain : int = int(params.get("soul_fire_gain", 1))
			SoulFireManager.add(gain)
		"kill_heal_percent":
			var pct : float = float(params.get("heal_percent", 0.15))
			var heal : int = int(attacker.unit_stats.max_hp * pct)
			var old : int = attacker.hit_points
			attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
			var actual : int = attacker.hit_points - old
			if actual > 0:
				attacker.update_hp_label()
				SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)

func _apply_splash(attacker: Unit, defender: Unit, base_damage: int, percent: float, is_crit: bool = false) -> void:
	var behind = defender.grid_cell + (defender.grid_cell - attacker.grid_cell)
	var splash_target = UnitManager.get_unit_at_cell(behind)
	if not splash_target or splash_target.hit_points <= 0: return
	if splash_target.unit_stats.team_id == attacker.unit_stats.team_id: return
	var splash_dmg = int(base_damage * percent)
	var dead = _apply_damage_with_effects(splash_target, splash_dmg, attacker, is_crit)
	if dead:
		if _try_boss_revive(splash_target, attacker): return
		_on_kill(attacker, splash_target)
		await _play_death_animation(splash_target)
		UnitManager.unregister_unit(splash_target)
		splash_target.queue_free()

func _apply_aoe(attacker: Unit, center: Unit, base_damage: int, percent: float, is_crit: bool = false) -> void:
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var target = UnitManager.get_unit_at_cell(center.grid_cell + d)
		if not target or target.hit_points <= 0: continue
		if target.unit_stats.team_id == attacker.unit_stats.team_id: continue
		var aoe_dmg = int(base_damage * percent)
		var dead = _apply_damage_with_effects(target, aoe_dmg, attacker, is_crit)
		if dead:
			if _try_boss_revive(target, attacker): continue
			_on_kill(attacker, target)
			await _play_death_animation(target)
			UnitManager.unregister_unit(target)
			target.queue_free()

func _apply_damage_with_effects(defender: Unit, damage: int, attacker: Unit, is_crit: bool = false) -> bool:
	if TalentManager.is_talent_ready(defender, "parry"):
		var level = _get_effective_talent_level(defender, "parry")
		var reflect_mult = 0.5 + (level - 1) * 0.15
		var parry_base = calculate_damage(defender, attacker)
		var parry_damage = max(1, int(parry_base * reflect_mult))
		attacker.apply_damage(parry_damage)
		SignalBus.request_damage_popup.emit(attacker.global_position, parry_damage, false, false, false)
		TalentManager.reset_talent(defender, "parry")

	if TalentManager.is_talent_ready(defender, "block"):
		var level = _get_effective_talent_level(defender, "block")
		var reduction = 0.5 + (level - 1) * 0.1
		damage = int(damage * (1.0 - reduction))
		TalentManager.reset_talent(defender, "block")

	if TalentManager.is_talent_ready(attacker, "bleed"):
		if defender.unit_stats.team_id != attacker.unit_stats.team_id:
			defender.bleed_stacks += 1
			TalentManager.reset_talent(attacker, "bleed")
			if defender.bleed_stacks >= BLEED_MAX_STACKS:
				var level = _get_effective_talent_level(attacker, "bleed")
				var percent = BLEED_DAMAGE_PERCENT[level - 1]
				var bleed_damage = int(defender.unit_stats.max_hp * percent)
				SignalBus.request_damage_popup.emit(defender.global_position, bleed_damage, false, false, false)
				var bleed_dead = defender.apply_damage(bleed_damage)
				defender.bleed_stacks = 0
				if bleed_dead:
					if _try_revive(defender): return false
					return true

	if BossMechanicManager:
		damage = BossMechanicManager.modify_damage_to_boss(attacker, defender, damage)

	var defeated = defender.apply_damage(damage)
	SignalBus.request_damage_popup.emit(defender.global_position, damage, is_crit, false, false)
	_play_hurt_effect(defender, attacker)

	var ls_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot: ls_bonus += slot.get_affix_value_float("lifesteal")
	if ls_bonus > 0.0 and damage > 0:
		var heal : int = int(damage * ls_bonus)
		var old : int = attacker.hit_points
		attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
		var actual : int = attacker.hit_points - old
		if actual > 0:
			attacker.update_hp_label()
			SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)

	if not defeated and defender.relic_turn_first_hit_regen > 0.0 and not defender.relic_turn_first_hit_regen_used:
		var regen = int(damage * defender.relic_turn_first_hit_regen)
		if regen > 0:
			defender.hit_points = mini(defender.hit_points + regen, defender.unit_stats.max_hp)
			defender.update_hp_label()
			SignalBus.request_damage_popup.emit(defender.global_position, regen, false, false, true)
		defender.relic_turn_first_hit_regen_used = true

	if defeated and defender.relic_auto_revive_available:
		defender.hit_points = defender.unit_stats.max_hp
		defender.update_hp_label()
		SignalBus.request_damage_popup.emit(defender.global_position, defender.hit_points, false, false, true)
		defender.relic_auto_revive_available = false
		if defender.relic_phoenix_revive_attack_bonus > 0.0:
			defender.buff_attack_percent += defender.relic_phoenix_revive_attack_bonus
		return false

	if defeated and _try_revive(defender): return false
	return defeated

func _consume_first_spell_free(attacker: Unit) -> bool:
	if attacker == null: return false
	if not attacker.relic_first_spell_free_available: return false
	if attacker.relic_first_spell_free_remaining <= 0:
		attacker.relic_first_spell_free_available = false
		return false
	var wt : String = attacker.get_weapon_type()
	if wt != "spellbook" and wt != "staff": return false
	attacker.relic_first_spell_free_remaining -= 1
	if attacker.relic_first_spell_free_remaining <= 0:
		attacker.relic_first_spell_free_available = false
	return true

func _try_revive(defender: Unit) -> bool:
	if not TalentManager.is_talent_ready(defender, "revive"): return false
	defender.hit_points = defender.unit_stats.max_hp
	defender.update_hp_label()
	SignalBus.request_damage_popup.emit(defender.global_position, defender.hit_points, false, false, true)
	TalentManager.reset_talent(defender, "revive")
	return true

func _get_effective_talent_level(unit: Unit, talent_id: String) -> int:
	if unit.unit_stats.team_id != 0: return 1
	return TalentManager.get_talent_level(unit.unit_stats.unit_name, talent_id)

func _can_counter_attack(attacker: Unit, defender: Unit) -> bool:
	if not defender.can_counter(): return false
	var def_weapon_type = defender.get_weapon_type()
	if def_weapon_type == "" or def_weapon_type == "staff": return false
	var defender_weapon = defender.get_weapon_data()
	if not defender_weapon: return false
	var def_min_range = defender_weapon.min_attack_range
	var def_max_range = defender_weapon.attack_range
	var dist = abs(defender.grid_cell.x - attacker.grid_cell.x) + abs(defender.grid_cell.y - attacker.grid_cell.y)
	return dist >= def_min_range and dist <= def_max_range

func _execute_counter(attacker: Unit, defender: Unit) -> void:
	var counter_damage = calculate_damage(defender, attacker)
	if defender.relic_counter_damage_bonus > 0.0:
		counter_damage = int(counter_damage * (1.0 + defender.relic_counter_damage_bonus))
	var counter_bonus : float = 0.0
	for slot in defender.armor_slots:
		if slot: counter_bonus += slot.get_affix_value_float("counter")
	counter_damage = int(counter_damage * (1.0 + counter_bonus))
	if TalentManager.is_talent_ready(defender, "counter_boost"):
		var level = _get_effective_talent_level(defender, "counter_boost")
		counter_damage = int(counter_damage * COUNTER_BOOST_MULT[level - 1])
		TalentManager.reset_talent(defender, "counter_boost")
	await _play_lunge_attack(defender, attacker)
	await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout
	var attacker_dead = attacker.apply_damage(counter_damage)
	_play_hurt_effect(attacker, defender)
	SignalBus.request_damage_popup.emit(attacker.global_position, counter_damage, false, false, false)
	await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout
	if attacker_dead:
		if _try_boss_revive(attacker, defender): return
		_on_kill(defender, attacker)
		await _play_death_animation(attacker)
		UnitManager.unregister_unit(attacker)
		attacker.queue_free()

func _is_alive(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.hit_points > 0

func _finish_attack(attacker: Unit, _defender: Unit, free_action: bool = false) -> void:
	if free_action:
		attacker.has_attacked = true
		attacker.has_acted = false
		attacker.movement_after_attack = true
	else:
		attacker.mark_attacked()
	_post_attack_check(attacker)

func _show_menu_after_action(unit: Unit):
	_post_attack_check(unit)

func _post_attack_check(unit: Unit):
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER: return
	if unit.unit_stats.team_id != 0: return
	if unit.remaining_move < 0: unit.remaining_move = 0
	if unit.has_acted or not unit.can_act_this_turn:
		TurnManager.finish_unit_action(unit)
		InputManager.selected_unit = null
		InputManager.interaction_phase = InputManager.Phase.IDLE
		return
	InputManager.selected_unit = unit
	InputManager.interaction_phase = InputManager.Phase.IDLE
	SignalBus.request_show_info.emit(unit)

func _face_each_other(attacker: Unit, defender: Unit):
	if not is_instance_valid(attacker) or not is_instance_valid(defender): return
	var dir = defender.grid_cell - attacker.grid_cell
	if dir.x != 0:
		attacker.set_facing_direction(Vector2(sign(dir.x), 0))
		defender.set_facing_direction(Vector2(-sign(dir.x), 0))

func get_unit_attack_stats(unit: Unit) -> Dictionary:
	var weapon = unit.get_weapon_data()
	if weapon and weapon.type == "weapon":
		var quality_mult = QUALITY_MULT.get(weapon.quality, 1.0)
		var stats = {
			"attack": int(weapon.base_attack * quality_mult),
			"attack_range": weapon.attack_range,
			"min_attack_range": weapon.min_attack_range,
			"attack_style": weapon.attack_style,
		}
		if weapon.magic_attack.get("ignore_defense", false):
			stats["magic_attack"] = int(weapon.base_attack * quality_mult)
		if not weapon.heal_effect.is_empty():
			stats["heal_amount"] = weapon.heal_effect.get("base_heal", 0)
		return stats
	else:
		return {"attack": 0, "magic_attack": 0, "heal_amount": 0,
			"attack_range": 0, "min_attack_range": 0, "attack_style": "standard"}
