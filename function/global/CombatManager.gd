extends Node

var QUALITY_MULT : Dictionary = {"common":1.0,"rare":1.25,"epic":1.5,"legendary":1.8}
var STRENGTH_DEF_FACTOR : float = 0.3
var CRIT_BASE_CHANCE : float = 0.05
var CRIT_PER_DEXTERITY : float = 0.005
var CRIT_CHANCE_BY_QUALITY : Dictionary = {"common":0.0,"rare":0.03,"epic":0.05,"legendary":0.08}
var CRIT_DAMAGE_MULT : float = 1.5

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
	STRENGTH_DEF_FACTOR = float(cfg.get("strength_def_factor", STRENGTH_DEF_FACTOR))
	CRIT_BASE_CHANCE = float(cfg.get("crit_base_chance", CRIT_BASE_CHANCE))
	CRIT_PER_DEXTERITY = float(cfg.get("crit_per_dexterity", CRIT_PER_DEXTERITY))
	CRIT_CHANCE_BY_QUALITY = cfg.get("crit_chance_by_quality", CRIT_CHANCE_BY_QUALITY).duplicate()
	CRIT_DAMAGE_MULT = float(cfg.get("crit_damage_mult", CRIT_DAMAGE_MULT))

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


# ============================================================
#  主动技能射程
# ============================================================
func get_active_skill_range_bonus(unit: Unit) -> int:
	if unit == null:
		return 0
	var ready_skills : Array = TalentManager.get_ready_active_skills(unit)
	var bonus : int = 0
	for skill_id in ready_skills:
		var data = TalentManager.get_talent_data(skill_id)
		if data:
			bonus = maxi(bonus, int(data.effect_params.get("range_bonus", 0)))
	return bonus


# ============================================================
#  目标查询（批次 5B：动态射程）
# ============================================================
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
			if dist < min_range or dist > max_range:
				continue
			var cell = unit.grid_cell + Vector2i(x, y)
			if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y:
				continue
			var target = UnitManager.get_unit_at_cell(cell)
			if not target or target.hit_points <= 0:
				continue
			if is_healer:
				if target.unit_stats.team_id == unit.unit_stats.team_id:
					targets.append(target)
			else:
				if target.unit_stats.team_id != unit.unit_stats.team_id:
					targets.append(target)

	if is_healer:
		targets.sort_custom(func(a, b):
			var loss_a = a.unit_stats.max_hp - a.hit_points
			var loss_b = b.unit_stats.max_hp - b.hit_points
			return loss_a > loss_b
		)
	else:
		targets.sort_custom(func(a, b):
			var da = abs(a.grid_cell.x - unit.grid_cell.x) + abs(a.grid_cell.y - unit.grid_cell.y)
			var db = abs(b.grid_cell.x - unit.grid_cell.x) + abs(b.grid_cell.y - unit.grid_cell.y)
			return da < db
		)
	return targets


func attempt_attack_after_move(unit: Unit):
	var targets = get_attackable_targets(unit)
	if targets.size() > 0:
		await execute_attack(unit, targets[0])


# ============================================================
#  伤害公式（批次 4/6A/8）
# ============================================================
func calculate_damage(attacker: Unit, defender: Unit) -> int:
	var weapon_data = attacker.get_weapon_data()
	if not weapon_data:
		return 0

	var quality_mult = QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_lv : int = attacker.weapon_slot.upgrade_level if attacker.weapon_slot else 0
	var base_attack : int = WeaponUpgradeHelper.get_effective_base_attack(weapon_data, upgrade_lv) * quality_mult

	var modifier = weapon_data.modifier
	var atk_bonus = 0.0
	for attr in modifier:
		var val = attacker.unit_stats.get_effective_attr(attr)
		atk_bonus += val * modifier[attr]

	var total_attack = base_attack + atk_bonus + attacker.buff_attack_flat
	if weapon_data.magic_attack.get("ignore_defense", false):
		total_attack += attacker.buff_magic_attack_flat
	total_attack *= (1.0 + attacker.buff_attack_percent)

	if attacker.relic_strength_scale_damage > 0.0:
		var str_val = attacker.unit_stats.get_effective_attr("strength")
		total_attack *= (1.0 + str_val * attacker.relic_strength_scale_damage)

	var armor_defense = 0
	for slot in defender.armor_slots:
		if slot:
			var item_data = ItemManager.get_item_data(slot.item_id)
			if item_data:
				var armor_quality_mult = QUALITY_MULT.get(item_data.quality, 1.0)
				var armor_lv : int = slot.upgrade_level
				armor_defense += WeaponUpgradeHelper.get_effective_defense(item_data, armor_lv) * armor_quality_mult
	var def_value = defender.unit_stats.get_effective_attr("strength") * STRENGTH_DEF_FACTOR + armor_defense
	def_value += defender.buff_defense_flat

	var damage = max(1, int(total_attack - def_value))

	# ★ 批次 6A：词条防御
	var def_armor_bonus : int = 0
	for slot in defender.armor_slots:
		if slot:
			def_armor_bonus += slot.get_affix_value("defense_flat")
	damage = max(1, damage - def_armor_bonus)

	# ★ 批次 6A：词条攻击
	var atk_affix_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot:
			atk_affix_bonus += slot.get_affix_value("attack_flat")
	damage += atk_affix_bonus

	# ★ 批次 8：枯竭受伤 +30%
	if defender.unit_stats.team_id == 0:
		var taken_mult : float = SoulFireManager.get_damage_taken_mult()
		if taken_mult > 1.0:
			damage = int(damage * taken_mult)

	if defender.buff_damage_reduction > 0:
		damage = max(1, int(damage * (1.0 - defender.buff_damage_reduction)))

	return damage


# ============================================================
#  暴击（批次 6A）
# ============================================================
func _roll_crit(attacker: Unit) -> bool:
	var chance : float = CRIT_BASE_CHANCE
	chance += attacker.unit_stats.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
	var wdata = attacker.get_weapon_data()
	if wdata:
		chance += CRIT_CHANCE_BY_QUALITY.get(wdata.quality, 0.0)
	chance += attacker.get_total_affix_value_float("crit_chance")
	return randf() < chance


# ============================================================
#  主动技能消耗（批次 1）
# ============================================================
func _get_active_skill_cost(sdata) -> int:
	if sdata == null:
		return SoulFireManager.COST_SKILL_MIN
	var ep : Dictionary = sdata.effect_params if sdata.effect_params else {}
	var explicit : int = int(ep.get("soul_fire_cost", 0))
	if explicit > 0:
		return explicit
	if sdata.effect_type == "heal":
		return SoulFireManager.COST_SKILL_MAX
	return SoulFireManager.COST_SKILL_MIN


# ============================================================
#  攻击主流程
# ============================================================
func execute_attack(attacker: Unit, defender: Unit) -> bool:
	if attacker.get_equipped_weapon_id() == "":
		print("错误：攻击者没有装备武器")
		Globals.is_performing_action = false
		return false

	_face_each_other(attacker, defender)
	Globals.is_performing_action = true
	print(attacker.unit_stats.unit_name + " 攻击 " + defender.unit_stats.unit_name)

	if attacker.get_weapon_type() == "staff":
		await _execute_heal(attacker, defender)
		Globals.is_performing_action = false
		return true

	await _play_lunge_attack(attacker, defender)

	var damage = calculate_damage(attacker, defender)

	var active_skill_id : String = ""
	var active_skill_data = null
	var ready_skills : Array = TalentManager.get_ready_active_skills(attacker)
	if ready_skills.size() > 0:
		var sid : String = ready_skills[0]
		var sdata = TalentManager.get_talent_data(sid)
		if sdata:
			var cost : int = _get_active_skill_cost(sdata)
			if SoulFireManager.can_spend(cost):
				active_skill_id = sid
				active_skill_data = sdata
				print("[主动技能] %s 触发：%s（消耗 %d 魂火）" % [
					attacker.unit_stats.unit_name, sdata.display_name, cost])
			else:
				print("[主动技能] %s 魂火不足（需 %d，现有 %d）" % [
					attacker.unit_stats.unit_name, cost, SoulFireManager.current])

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
		var bonus = 1.0 + (attacker.zeal_stacks - 1) * per
		damage = int(damage * bonus)
		print("狂热触发！Lv.%d 第 %d 次攻击 倍率×%.2f" % [lv_zeal, attacker.zeal_stacks, bonus])
		TalentManager.reset_talent(attacker, "zeal")

	if attacker.combo_last_target == target_key:
		attacker.combo_count += 1
	else:
		attacker.combo_last_target = target_key
		attacker.combo_count = 1

	if attacker.combo_count > 1 and TalentManager.is_talent_ready(attacker, "combo"):
		var lv_combo = _get_effective_talent_level(attacker, "combo")
		var per_hit = COMBO_MULT_PER_HIT[clampi(lv_combo - 1, 0, COMBO_MULT_PER_HIT.size() - 1)]
		var bonus = 1.0 + (attacker.combo_count - 1) * per_hit
		damage = int(damage * bonus)
		print("连击触发！Lv.%d 第 %d 次攻击 倍率×%.2f" % [lv_combo, attacker.combo_count, bonus])
		TalentManager.reset_talent(attacker, "combo")

	var is_crit := false
	var crit_mult : float = CRIT_DAMAGE_MULT
	# ★ 批次 8：枯竭暴击伤害 +50%
	if attacker.unit_stats.team_id == 0:
		crit_mult += SoulFireManager.get_crit_damage_bonus()
	# ★ 批次 6A：词条暴击伤害
	crit_mult += attacker.get_total_affix_value_float("crit_damage")

	if force_crit:
		is_crit = true
		print("主动技能：强制暴击")
	elif TalentManager.is_talent_ready(attacker, "crit"):
		var lv_crit = _get_effective_talent_level(attacker, "crit")
		crit_mult = 2.0 + (lv_crit - 1) * 0.5 + attacker.buff_crit_damage_bonus
		crit_mult += attacker.get_total_affix_value_float("crit_damage")
		is_crit = true
		print("暴击词条触发！Lv.%d 倍率 %.1f" % [lv_crit, crit_mult])
		TalentManager.reset_talent(attacker, "crit")
	elif attacker.relic_first_attack_crit_available:
		crit_mult += attacker.buff_crit_damage_bonus
		is_crit = true
		attacker.relic_first_attack_crit_available = false
		print("力量遗物：首次攻击必暴击！")
	elif _roll_crit(attacker):
		crit_mult += attacker.buff_crit_damage_bonus
		is_crit = true
		print("暴击！倍率 %.2f" % crit_mult)

	if is_crit:
		damage = int(damage * crit_mult)

	if ignore_def and active_skill_data:
		var wdata_tmp = attacker.get_weapon_data()
		if wdata_tmp:
			var wd_lv : int = attacker.weapon_slot.upgrade_level if attacker.weapon_slot else 0
			var base_only = WeaponUpgradeHelper.get_effective_base_attack(wdata_tmp, wd_lv) * QUALITY_MULT.get(wdata_tmp.quality, 1.0)
			var atk_bonus_tmp = 0.0
			for attr in wdata_tmp.modifier:
				atk_bonus_tmp += attacker.unit_stats.get_effective_attr(attr) * wdata_tmp.modifier[attr]
			var no_def_dmg = int((base_only + atk_bonus_tmp + attacker.buff_attack_flat) * (1.0 + attacker.buff_attack_percent))
			no_def_dmg = int(no_def_dmg * float(active_skill_data.effect_params.get("damage_mult", 1.0)))
			if is_crit:
				no_def_dmg = int(no_def_dmg * crit_mult)
			damage = max(damage, no_def_dmg)

	if hp_cost_percent > 0.0:
		var hp_cost = int(attacker.unit_stats.max_hp * hp_cost_percent)
		attacker.hit_points = max(1, attacker.hit_points - hp_cost)
		attacker.update_hp_label()
		SignalBus.request_damage_popup.emit(attacker.global_position, hp_cost, false, false, false)
		print("龙息：消耗 %d HP" % hp_cost)

	await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout

	print("造成伤害: ", damage)

	var defeated = _apply_damage_with_effects(defender, damage, attacker, is_crit)

	# ★ 批次 5B：5 级武器眩晕
	if attacker.weapon_slot:
		var up_lv : int = attacker.weapon_slot.upgrade_level
		if WeaponUpgradeHelper.has_special_effect(up_lv):
			if randf() < WeaponUpgradeHelper.SPECIAL_EFFECT_CHANCE:
				defender.can_act_this_turn = false
				defender.set_gray(true)
				SignalBus.request_hint_override.emit("★ 眩晕！%s 无法行动" % defender.unit_stats.unit_name, 1.0)
				print("[武器特效] %s 眩晕了 %s" % [attacker.unit_stats.unit_name, defender.unit_stats.unit_name])

	# ★ 批次 6A：词条火焰附加伤害
	var flame_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot:
			flame_bonus += slot.get_affix_value("flame_damage")
	if flame_bonus > 0 and defender.hit_points > 0:
		var extra_flame_dead : bool = defender.apply_damage(flame_bonus)
		SignalBus.request_damage_popup.emit(defender.global_position, flame_bonus, false, false, false)
		print("[词条] 焚身：附加 %d 火焰伤害" % flame_bonus)
		if extra_flame_dead:
			defeated = true

	# ★ 批次 8：燃烧溅射
	var splash_sf : float = SoulFireManager.get_splash_percent()
	if splash_sf > 0.0 and attacker.unit_stats.team_id == 0 and defender.hit_points > 0:
		await _apply_burning_splash(attacker, defender, damage, splash_sf)

	# ★ 批次 5A：攻击后光环消耗
	_apply_aura_attack_cost(attacker)

	await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout

	# ★ 批次 5B：Boss 三形态拦截（已推迟，此处不接）

	if active_skill_data:
		if splash_percent > 0.0:
			await _apply_splash(attacker, defender, damage, splash_percent, is_crit)
		if aoe_percent > 0.0:
			await _apply_aoe(attacker, defender, damage, aoe_percent, is_crit)
		if taunt_rounds > 0:
			attacker.taunt_rounds = taunt_rounds
			var dirs_t = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
			for d in dirs_t:
				var c = attacker.grid_cell + d
				var e = UnitManager.get_unit_at_cell(c)
				if e and e.unit_stats.team_id != attacker.unit_stats.team_id and e.hit_points > 0:
					e.taunt_by = attacker
					e.taunt_rounds_left = taunt_rounds
			print("[嘲讽] %s 周围敌人下回合强制攻击他" % attacker.unit_stats.unit_name)
		TalentManager.consume_active_skill(attacker, active_skill_id)
		var skill_cost : int = _get_active_skill_cost(active_skill_data)
		SoulFireManager.spend(skill_cost)

	if defeated:
		print(defender.unit_stats.unit_name + " 阵亡！")
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
			print("吸血触发！Lv.%d 恢复 %d HP" % [lv_ls, actual])
		TalentManager.reset_talent(attacker, "lifesteal")

	# ---- 二次攻击 ----
	if TalentManager.is_talent_ready(attacker, "double_attack"):
		var level = _get_effective_talent_level(attacker, "double_attack")
		var mult = DOUBLE_ATTACK_MULT[level - 1]
		var extra_damage = int(damage * mult)
		print("二次攻击触发！Lv.%d 额外 %d 伤害" % [level, extra_damage])
		TalentManager.reset_talent(attacker, "double_attack")

		await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
		await _play_lunge_attack(attacker, defender)
		await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout

		var extra_dead = defender.apply_damage(extra_damage)
		_play_hurt_effect(defender, attacker)
		SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)

		await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout

		if extra_dead:
			print(defender.unit_stats.unit_name + " 阵亡！")
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

	# ---- 法术连击 ----
	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "spellbook" or attacker.get_weapon_type() == "staff":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]

			if attacker.get_weapon_type() == "staff":
				print("法术连击触发！Lv.%d 额外治疗" % level)
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
				print("法术连击触发！Lv.%d 额外 %d 伤害" % [level, extra_damage])
				TalentManager.reset_talent(attacker, "spell_chain")

				await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
				await _play_lunge_attack(attacker, defender)
				await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout

				var extra_dead = defender.apply_damage(extra_damage)
				_play_hurt_effect(defender, attacker)
				SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)

				await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout

				if extra_dead:
					print(defender.unit_stats.unit_name + " 阵亡！")
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

	# ---- 反击 ----
	if _can_counter_attack(attacker, defender):
		await _execute_counter(attacker, defender)

	var free_action : bool = _consume_first_spell_free(attacker)
	_finish_attack(attacker, defender, free_action)
	Globals.is_performing_action = false
	return true


# ============================================================
#  燃烧溅射（批次 8）
# ============================================================
func _apply_burning_splash(attacker : Unit, center : Unit, base_damage : int, percent : float):
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d in dirs:
		var cell : Vector2i = center.grid_cell + d
		var t : Unit = UnitManager.get_unit_at_cell(cell)
		if not t or t.hit_points <= 0:
			continue
		if t.unit_stats.team_id == attacker.unit_stats.team_id:
			continue
		var splash_dmg : int = maxi(1, int(base_damage * percent))
		var dead : bool = _apply_damage_with_effects(t, splash_dmg, attacker, false)
		print("[燃烧溅射] %d 伤害给 %s" % [splash_dmg, t.unit_stats.unit_name])
		if dead:
			_on_kill(attacker, t)
			await _play_death_animation(t)
			UnitManager.unregister_unit(t)
			t.queue_free()


# ============================================================
#  光环攻击消耗（批次 5A）
# ============================================================
func _apply_aura_attack_cost(attacker : Unit):
	for aid in attacker.active_auras:
		if not attacker.active_auras[aid]:
			continue
		var d : Dictionary = AuraManager.get_aura(aid)
		if d.get("effect", "") != "attack_plus_and_consume":
			continue
		var cost : int = int(d.get("params", {}).get("soul_fire_cost_per_attack", 1))
		if SoulFireManager.current > 0:
			SoulFireManager.spend(cost)


# ============================================================
#  攻击者前冲
# ============================================================
func _play_lunge_attack(attacker: Unit, defender: Unit) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	if not attacker.animated_sprite:
		return

	var snd_tween = attacker.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(
		func(): SoundManager.play_attack_sound()
	).set_delay(LUNGE_DURATION * 0.35)

	var mat = attacker.animated_sprite.material as ShaderMaterial
	if not mat:
		await get_tree().create_timer(0.08, true, false, true).timeout
		return

	var dir = (defender.global_position - attacker.global_position)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()

	mat.set_shader_parameter("hit_offset_amount", dir * 6.0)
	mat.set_shader_parameter("hit_duration", LUNGE_DURATION)
	mat.set_shader_parameter("hit_elapsed", 0.0)
	mat.set_shader_parameter("hit_flash_color", Color.WHITE)
	mat.set_shader_parameter("hit_enable_flash", false)

	var tween = attacker.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_method(
		func(val):
			if is_instance_valid(mat):
				mat.set_shader_parameter("hit_elapsed", val),
		0.0, LUNGE_DURATION, LUNGE_DURATION
	)
	tween.tween_callback(func():
		if is_instance_valid(mat):
			mat.set_shader_parameter("hit_elapsed", 0.0)
			mat.set_shader_parameter("hit_offset_amount", Vector2.ZERO)
	)
	await tween.finished


func _play_hurt_effect(defender: Unit, attacker: Unit) -> void:
	if not is_instance_valid(defender):
		return
	var hit_dir = Vector2(1, 0)
	if is_instance_valid(attacker):
		var d = defender.global_position - attacker.global_position
		if d.length() > 0.001:
			hit_dir = d.normalized()
	defender.play_hit_effect(hit_dir, true)
	SignalBus.request_screen_shake.emit(0.15, 4.0, hit_dir)

	var snd_tween = defender.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(
		func(): SoundManager.play_hit_sound()
	).set_delay(MapConst.HIT_OFFSET_DURATION * 0.35)


func _play_death_animation(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return

	var snd_tween = unit.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(
		func(): SoundManager.play_death_sound()
	).set_delay(0.05)

	var hp_label = unit.get_node_or_null("HPLabel")
	if hp_label:
		hp_label.visible = false

	if not unit.animated_sprite:
		return

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


# ============================================================
#  击杀连锁（批次 5A/5B/6A/6B/8）
# ============================================================
func _on_kill(attacker: Unit, _defender: Unit) -> bool:
	if not is_instance_valid(attacker):
		return false

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
			print("血怒触发！Lv.%d 恢复 %d HP" % [lv, actual])
		TalentManager.reset_talent(attacker, "blood_rage")

	var cleave_triggered := false
	if TalentManager.is_talent_ready(attacker, "cleave"):
		attacker.has_attacked = false
		attacker.has_acted = false
		attacker.movement_after_attack = false
		print("连斩触发！可再次行动")
		TalentManager.reset_talent(attacker, "cleave")
		cleave_triggered = true

	if attacker.relic_kill_grants_extra_move > 0:
		attacker.remaining_move += attacker.relic_kill_grants_extra_move
		attacker.has_moved = false
		print("疾风遗物：额外移动 %d 格" % attacker.relic_kill_grants_extra_move)

	# ★ 批次 5A：光环击杀效果
	for aid in attacker.active_auras:
		if not attacker.active_auras[aid]:
			continue
		_apply_aura_kill_effect(attacker, aid)

	# ★ 批次 6A：词条击杀回魂火
	var bonus_sf : int = 0
	for slot in attacker.armor_slots:
		if slot:
			bonus_sf += slot.get_affix_value("soul_fire_gain")
	if bonus_sf > 0:
		SoulFireManager.add(bonus_sf)
		print("[词条] 余烬：击杀 +%d 魂火" % bonus_sf)

	# ★ 批次 6B：套装击杀回血
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
				print("[套装] 血之回响 +%d HP" % actual2)

	# ★ 批次 8：魂火归零回魂火
	if attacker.unit_stats.team_id == 0:
		SoulFireManager.on_kill()

	return cleave_triggered


func _apply_aura_kill_effect(attacker : Unit, aura_id : String):
	var d : Dictionary = AuraManager.get_aura(aura_id)
	if d.is_empty():
		return
	var params : Dictionary = d.get("params", {})
	match d.get("effect", ""):
		"kill_gain_soul_fire":
			var gain : int = int(params.get("soul_fire_gain", 1))
			SoulFireManager.add(gain)
			print("[光环] %s：击杀 +%d 魂火" % [d.get("name", aura_id), gain])
		"kill_heal_percent":
			var pct : float = float(params.get("heal_percent", 0.15))
			var heal : int = int(attacker.unit_stats.max_hp * pct)
			var old : int = attacker.hit_points
			attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
			var actual : int = attacker.hit_points - old
			if actual > 0:
				attacker.update_hp_label()
				SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)
				print("[光环] %s：击杀 +%d HP" % [d.get("name", aura_id), actual])


# ============================================================
#  溅射
# ============================================================
func _apply_splash(attacker: Unit, defender: Unit, base_damage: int, percent: float, is_crit: bool = false) -> void:
	var dir = defender.grid_cell - attacker.grid_cell
	var behind = defender.grid_cell + dir
	var splash_target = UnitManager.get_unit_at_cell(behind)
	if not splash_target or splash_target.hit_points <= 0:
		return
	if splash_target.unit_stats.team_id == attacker.unit_stats.team_id:
		return
	var splash_dmg = int(base_damage * percent)
	var dead = _apply_damage_with_effects(splash_target, splash_dmg, attacker, is_crit)
	print("[贯穿] 溅射 %d 伤害给 %s" % [splash_dmg, splash_target.unit_stats.unit_name])
	if dead:
		_on_kill(attacker, splash_target)
		await _play_death_animation(splash_target)
		UnitManager.unregister_unit(splash_target)
		splash_target.queue_free()


func _apply_aoe(attacker: Unit, center: Unit, base_damage: int, percent: float, is_crit: bool = false) -> void:
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d in dirs:
		var cell = center.grid_cell + d
		var target = UnitManager.get_unit_at_cell(cell)
		if not target or target.hit_points <= 0:
			continue
		if target.unit_stats.team_id == attacker.unit_stats.team_id:
			continue
		var aoe_dmg = int(base_damage * percent)
		var dead = _apply_damage_with_effects(target, aoe_dmg, attacker, is_crit)
		print("[火球] AOE %d 伤害给 %s" % [aoe_dmg, target.unit_stats.unit_name])
		if dead:
			_on_kill(attacker, target)
			await _play_death_animation(target)
			UnitManager.unregister_unit(target)
			target.queue_free()


# ============================================================
#  治疗（批次 6A）
# ============================================================
func _execute_heal(attacker: Unit, defender: Unit) -> bool:
	if defender.unit_stats.team_id != attacker.unit_stats.team_id:
		print("错误：治疗不能对敌方！")
		Globals.is_performing_action = false
		return false

	var weapon_data = attacker.get_weapon_data()
	var heal_amount = weapon_data.heal_effect.get("base_heal", 0)
	var faith_bonus = attacker.unit_stats.faith * weapon_data.heal_effect.get("faith_multiplier", 1.0)
	var total_heal = int(heal_amount + faith_bonus)

	if attacker.relic_heal_bonus > 0.0:
		total_heal = int(total_heal * (1.0 + attacker.relic_heal_bonus))

	# ★ 批次 6A：词条治疗
	var heal_affix_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot:
			heal_affix_bonus += slot.get_affix_value_float("heal_boost")
	total_heal = int(total_heal * (1.0 + heal_affix_bonus))

	if TalentManager.is_talent_ready(attacker, "heal_boost"):
		var level = _get_effective_talent_level(attacker, "heal_boost")
		var mult = HEAL_BOOST_MULT[level - 1]
		total_heal = int(total_heal * mult)
		print("治愈强化触发！Lv.%d 治疗量 ×%.1f" % [level, mult])
		TalentManager.reset_talent(attacker, "heal_boost")

	var old_hp = defender.hit_points
	defender.hit_points = min(defender.hit_points + total_heal, defender.unit_stats.max_hp)
	var actual_heal = defender.hit_points - old_hp
	print("治疗 ", actual_heal, " 点 HP")

	defender.update_hp_label()
	SignalBus.request_damage_popup.emit(defender.global_position, actual_heal, false, false, true)
	SoundManager.play_heal_sound()

	var ready_heal : Array = TalentManager.get_ready_active_skills(attacker)
	for skill_id in ready_heal:
		var skill_data = TalentManager.get_talent_data(skill_id)
		if not skill_data:
			continue
		var mass_pct = float(skill_data.effect_params.get("mass_heal_percent", 0.0))
		if mass_pct <= 0.0:
			continue
		var mass_heal = int(actual_heal * mass_pct)
		for u in UnitManager.unit_list:
			if u.unit_stats.team_id != attacker.unit_stats.team_id:
				continue
			if u == defender or u.hit_points <= 0:
				continue
			var old = u.hit_points
			u.hit_points = mini(u.hit_points + mass_heal, u.unit_stats.max_hp)
			var real = u.hit_points - old
			if real > 0:
				u.update_hp_label()
				SignalBus.request_damage_popup.emit(u.global_position, real, false, false, true)
		print("[群体治愈] 其他友军回复 %d HP" % mass_heal)
		TalentManager.consume_active_skill(attacker, skill_id)
		break

	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout

	var free_action : bool = _consume_first_spell_free(attacker)
	_finish_attack(attacker, defender, free_action)
	Globals.is_performing_action = false
	return true


# ============================================================
#  伤害应用 + 词条效果（批次 5B/6A/8）
# ============================================================
func _apply_damage_with_effects(defender: Unit, damage: int, attacker: Unit, is_crit: bool = false) -> bool:
	if TalentManager.is_talent_ready(defender, "parry"):
		var level = _get_effective_talent_level(defender, "parry")
		var reflect_mult = 0.5 + (level - 1) * 0.15
		var parry_damage = int(damage * reflect_mult)
		attacker.apply_damage(parry_damage)
		SignalBus.request_damage_popup.emit(attacker.global_position, parry_damage, false, false, false)
		print("盾反触发！Lv.%d 反弹 %d 伤害" % [level, parry_damage])
		TalentManager.reset_talent(defender, "parry")

	if TalentManager.is_talent_ready(defender, "block"):
		var level = _get_effective_talent_level(defender, "block")
		var reduction = 0.5 + (level - 1) * 0.1
		damage = int(damage * (1.0 - reduction))
		print("格挡触发！Lv.%d 减伤 %d%%" % [level, int(reduction * 100)])
		TalentManager.reset_talent(defender, "block")

	if TalentManager.is_talent_ready(attacker, "bleed"):
		if defender.unit_stats.team_id != attacker.unit_stats.team_id:
			defender.bleed_stacks += 1
			print("出血累积！%s 当前 %d 层" % [defender.unit_stats.unit_name, defender.bleed_stacks])
			TalentManager.reset_talent(attacker, "bleed")

			if defender.bleed_stacks >= BLEED_MAX_STACKS:
				var level = _get_effective_talent_level(attacker, "bleed")
				var percent = BLEED_DAMAGE_PERCENT[level - 1]
				var bleed_damage = int(defender.unit_stats.max_hp * percent)
				print("出血爆发！%d 层触发 %d 伤害" % [BLEED_MAX_STACKS, bleed_damage])
				SignalBus.request_damage_popup.emit(defender.global_position, bleed_damage, false, false, false)
				var bleed_dead = defender.apply_damage(bleed_damage)
				defender.bleed_stacks = 0
				if bleed_dead:
					if _try_revive(defender):
						return false
					return true

	if defender.relic_low_hp_damage_reduce > 0.0:
		var hp_ratio = float(defender.hit_points) / float(defender.unit_stats.max_hp)
		if hp_ratio < 0.3:
			damage = max(1, int(damage * (1.0 - defender.relic_low_hp_damage_reduce)))
			print("守护遗物：低血量减伤 %d%%" % int(defender.relic_low_hp_damage_reduce * 100))

	var defeated = defender.apply_damage(damage)

	SignalBus.request_damage_popup.emit(defender.global_position, damage, is_crit, false, false)
	_play_hurt_effect(defender, attacker)

	# ★ 批次 6A：吸血词条
	var ls_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot:
			ls_bonus += slot.get_affix_value_float("lifesteal")
	if ls_bonus > 0.0 and damage > 0:
		var heal : int = int(damage * ls_bonus)
		var old : int = attacker.hit_points
		attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
		var actual : int = attacker.hit_points - old
		if actual > 0:
			attacker.update_hp_label()
			SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)
			print("[词条] 吸血 +%d" % actual)

	if not defeated and defender.relic_turn_first_hit_regen > 0.0 and not defender.relic_turn_first_hit_regen_used:
		var regen = int(damage * defender.relic_turn_first_hit_regen)
		if regen > 0:
			defender.hit_points = mini(defender.hit_points + regen, defender.unit_stats.max_hp)
			defender.update_hp_label()
			SignalBus.request_damage_popup.emit(defender.global_position, regen, false, false, true)
			print("生命遗物：本回合首次受伤回复 %d HP" % regen)
		defender.relic_turn_first_hit_regen_used = true

	if defeated and defender.relic_auto_revive_available:
		defender.hit_points = defender.unit_stats.max_hp
		defender.update_hp_label()
		SignalBus.request_damage_popup.emit(defender.global_position, defender.hit_points, false, false, true)
		defender.relic_auto_revive_available = false
		print("[凤凰之羽] %s 满血复活" % defender.unit_stats.unit_name)
		return false

	if defeated and _try_revive(defender):
		return false

	return defeated


func _try_revive(defender: Unit) -> bool:
	if not TalentManager.is_talent_ready(defender, "revive"):
		return false
	defender.hit_points = defender.unit_stats.max_hp
	defender.update_hp_label()
	SignalBus.request_damage_popup.emit(defender.global_position, defender.hit_points, false, false, true)
	print("复活触发！%s 满血复活" % defender.unit_stats.unit_name)
	TalentManager.reset_talent(defender, "revive")
	return true


# ============================================================
#  等级读取
# ============================================================
func _get_effective_talent_level(unit: Unit, talent_id: String) -> int:
	if unit.unit_stats.team_id != 0:
		return 1
	return TalentManager.get_talent_level(unit.unit_stats.unit_name, talent_id)


# ============================================================
#  反击（批次 6A）
# ============================================================
func _can_counter_attack(attacker: Unit, defender: Unit) -> bool:
	if not defender.can_counter():
		return false

	var def_weapon_type = defender.get_weapon_type()
	if def_weapon_type == "" or def_weapon_type == "staff":
		return false

	var defender_weapon = defender.get_weapon_data()
	if not defender_weapon:
		return false

	var def_min_range = defender_weapon.min_attack_range
	var def_max_range = defender_weapon.attack_range
	var dist = abs(defender.grid_cell.x - attacker.grid_cell.x) + abs(defender.grid_cell.y - attacker.grid_cell.y)

	return dist >= def_min_range and dist <= def_max_range


func _execute_counter(attacker: Unit, defender: Unit) -> void:
	print(defender.unit_stats.unit_name + " 反击!")
	var counter_damage = calculate_damage(defender, attacker)

	if defender.relic_counter_damage_bonus > 0.0:
		counter_damage = int(counter_damage * (1.0 + defender.relic_counter_damage_bonus))

	# ★ 批次 6A：词条反击加成
	var counter_bonus : float = 0.0
	for slot in defender.armor_slots:
		if slot:
			counter_bonus += slot.get_affix_value_float("counter")
	counter_damage = int(counter_damage * (1.0 + counter_bonus))

	if TalentManager.is_talent_ready(defender, "counter_boost"):
		var level = _get_effective_talent_level(defender, "counter_boost")
		var mult = COUNTER_BOOST_MULT[level - 1]
		counter_damage = int(counter_damage * mult)
		print("反击强化触发！Lv.%d 倍率 ×%.2f" % [level, mult])
		TalentManager.reset_talent(defender, "counter_boost")

	print("反击伤害: ", counter_damage)

	await _play_lunge_attack(defender, attacker)
	await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout

	var attacker_dead = attacker.apply_damage(counter_damage)
	_play_hurt_effect(attacker, defender)
	SignalBus.request_damage_popup.emit(attacker.global_position, counter_damage, false, false, false)

	await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout

	if attacker_dead:
		print(attacker.unit_stats.unit_name + " 阵亡！")
		_on_kill(defender, attacker)
		await _play_death_animation(attacker)
		UnitManager.unregister_unit(attacker)
		attacker.queue_free()


# ============================================================
#  首次施法免费
# ============================================================
func _consume_first_spell_free(attacker: Unit) -> bool:
	if attacker == null:
		return false
	if not attacker.relic_first_spell_free_available:
		return false
	var wt : String = attacker.get_weapon_type()
	if wt != "spellbook" and wt != "staff":
		return false
	attacker.relic_first_spell_free_available = false
	print("[魔力遗物] %s 首次施法免费" % attacker.unit_stats.unit_name)
	return true


# ============================================================
#  攻击结束处理
# ============================================================
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
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if unit.unit_stats.team_id != 0:
		return
	if unit.remaining_move < 0:
		unit.remaining_move = 0

	if unit.has_acted or not unit.can_act_this_turn:
		TurnManager.finish_unit_action(unit)
		InputManager.selected_unit = null
		InputManager.interaction_phase = InputManager.Phase.IDLE
		return

	InputManager.selected_unit = unit
	InputManager.interaction_phase = InputManager.Phase.IDLE
	SignalBus.request_show_info.emit(unit)


func _face_each_other(attacker: Unit, defender: Unit):
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
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
		return {
			"attack": 0, "magic_attack": 0, "heal_amount": 0,
			"attack_range": 0, "min_attack_range": 0, "attack_style": "standard"
		}
