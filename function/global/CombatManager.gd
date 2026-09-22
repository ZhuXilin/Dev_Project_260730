extends Node

const PERFORMANCE_DURATION : float = 0.5

# ---- 品质 → 攻防乘数 ----
const QUALITY_MULT = {
	"common": 1.0,
	"rare": 1.25,
	"epic": 1.5,
	"legendary": 1.8,
}

# ---- 力量 → 防御减免系数 ----
const STRENGTH_DEF_FACTOR : float = 0.3

# ---- 暴击系统 ----
const CRIT_BASE_CHANCE : float = 0.05
const CRIT_PER_DEXTERITY : float = 0.005
const CRIT_CHANCE_BY_QUALITY : Dictionary = {
	"common": 0.0,
	"rare": 0.03,
	"epic": 0.05,
	"legendary": 0.08,
}
const CRIT_DAMAGE_MULT : float = 1.5

# ============================================================
#  词条等级参数
# ============================================================
const DOUBLE_ATTACK_MULT : Array = [0.8, 0.9, 1.0]
const BLEED_DAMAGE_PERCENT : Array = [0.15, 0.20, 0.25]
const BLEED_MAX_STACKS : int = 5
const SPELL_CHAIN_MULT : Array = [0.8, 0.9, 1.0]
const COUNTER_BOOST_MULT : Array = [1.5, 1.75, 2.0]
const HEAL_BOOST_MULT : Array = [1.3, 1.5, 1.7]
const LIFESTEAL_PERCENT : Array = [0.2, 0.3, 0.4]
const COMBO_MULT_PER_HIT : Array = [0.15, 0.25, 0.35]

# ---- 连锁词条参数 ----
const BLOOD_RAGE_HEAL_PERCENT : Array = [0.15, 0.20, 0.25]
const ZEAL_PER_STACK : Array = [0.10, 0.15, 0.20]
const ZEAL_MAX_STACKS : int = 5


# ============================================================
#  目标查询
# ============================================================
func get_attackable_targets(unit: Unit) -> Array:
	var weapon_data = unit.get_weapon_data()
	if not weapon_data: return []
	var max_range = weapon_data.attack_range
	var min_range = weapon_data.min_attack_range
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
#  伤害公式
# ============================================================
func calculate_damage(attacker: Unit, defender: Unit) -> int:
	var weapon_data = attacker.get_weapon_data()
	if not weapon_data:
		return 0

	var quality_mult = QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_bonus = 0
	if attacker.weapon_slot:
		upgrade_bonus = attacker.weapon_slot.upgrade_level
	var base_attack = (weapon_data.base_attack + upgrade_bonus) * quality_mult

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
				armor_defense += item_data.defense * armor_quality_mult
	var def_value = defender.unit_stats.get_effective_attr("strength") * STRENGTH_DEF_FACTOR + armor_defense
	def_value += defender.buff_defense_flat

	var damage = max(1, int(total_attack - def_value))

	if defender.buff_damage_reduction > 0:
		damage = max(1, int(damage * (1.0 - defender.buff_damage_reduction)))

	return damage


# ============================================================
#  暴击判定
# ============================================================
func _roll_crit(attacker: Unit) -> bool:
	var chance : float = CRIT_BASE_CHANCE
	chance += attacker.unit_stats.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
	var wdata = attacker.get_weapon_data()
	if wdata:
		chance += CRIT_CHANCE_BY_QUALITY.get(wdata.quality, 0.0)
	return randf() < chance


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

	# ---- 治疗武器 ----
	if attacker.get_weapon_type() == "staff":
		await _execute_heal(attacker, defender)
		Globals.is_performing_action = false
		return true

	var damage = calculate_damage(attacker, defender)

	# ★ 主动技能触发
	var active_skill_id : String = ""
	var active_skill_data = null
	var ready_skills : Array = TalentManager.get_ready_active_skills(attacker)
	if ready_skills.size() > 0:
		active_skill_id = ready_skills[0]
		active_skill_data = TalentManager.get_talent_data(active_skill_id)
		print("[主动技能] %s 触发：%s" % [attacker.unit_stats.unit_name, active_skill_data.display_name])

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

	# 狂热：连续攻击同一目标累积
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

	# 连击（旧 combo）
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

	# 暴击判定
	var is_crit := false
	var crit_mult : float = CRIT_DAMAGE_MULT

	if force_crit:
		is_crit = true
		print("主动技能：强制暴击")
	elif TalentManager.is_talent_ready(attacker, "crit"):
		var lv_crit = _get_effective_talent_level(attacker, "crit")
		crit_mult = 2.0 + (lv_crit - 1) * 0.5 + attacker.buff_crit_damage_bonus
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

	# 主动技能：无视防御（重算）
	if ignore_def and active_skill_data:
		var wdata_tmp = attacker.get_weapon_data()
		if wdata_tmp:
			var base_only = (wdata_tmp.base_attack + (attacker.weapon_slot.upgrade_level if attacker.weapon_slot else 0)) * QUALITY_MULT.get(wdata_tmp.quality, 1.0)
			var atk_bonus_tmp = 0.0
			for attr in wdata_tmp.modifier:
				atk_bonus_tmp += attacker.unit_stats.get_effective_attr(attr) * wdata_tmp.modifier[attr]
			var no_def_dmg = int((base_only + atk_bonus_tmp + attacker.buff_attack_flat) * (1.0 + attacker.buff_attack_percent))
			no_def_dmg = int(no_def_dmg * float(active_skill_data.effect_params.get("damage_mult", 1.0)))
			if is_crit:
				no_def_dmg = int(no_def_dmg * crit_mult)
			damage = max(damage, no_def_dmg)

	# 主动技能：消耗自身 HP
	if hp_cost_percent > 0.0:
		var hp_cost = int(attacker.unit_stats.max_hp * hp_cost_percent)
		attacker.hit_points = max(1, attacker.hit_points - hp_cost)
		attacker.update_hp_label()
		SignalBus.request_damage_popup.emit(attacker.global_position, hp_cost, false, false, false)
		print("龙息：消耗 %d HP" % hp_cost)

	print("造成伤害: ", damage)

	var defeated = _apply_damage_with_effects(defender, damage, attacker)

	# 主动技能后效
	if active_skill_data:
		if splash_percent > 0.0:
			_apply_splash(attacker, defender, damage, splash_percent)
		if aoe_percent > 0.0:
			_apply_aoe(attacker, defender, damage, aoe_percent)
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

	if defeated:
		print(defender.unit_stats.unit_name + " 阵亡！")
		_on_kill(attacker, defender)
		UnitManager.unregister_unit(defender)
		defender.queue_free()

		# ★ 检查 cleave 是否触发
		if not attacker.has_attacked:
			# cleave 已重置状态，跳过 _finish_attack
			Globals.is_performing_action = false
			return true

		_finish_attack(attacker, defender)
		Globals.is_performing_action = false
		return true

	# ---- 词条：吸血 ----
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

	# ---- 词条：二次攻击 ----
	if TalentManager.is_talent_ready(attacker, "double_attack"):
		var level = _get_effective_talent_level(attacker, "double_attack")
		var mult = DOUBLE_ATTACK_MULT[level - 1]
		var extra_damage = int(damage * mult)
		print("二次攻击触发！Lv.%d 额外 %d 伤害" % [level, extra_damage])
		TalentManager.reset_talent(attacker, "double_attack")

		await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
		var extra_dead = defender.apply_damage(extra_damage)
		SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)
		if extra_dead:
			print(defender.unit_stats.unit_name + " 阵亡！")
			_on_kill(attacker, defender)
			UnitManager.unregister_unit(defender)
			defender.queue_free()

			# ★ 检查 cleave
			if not attacker.has_attacked:
				Globals.is_performing_action = false
				return true

			_finish_attack(attacker, defender)
			Globals.is_performing_action = false
			return true

	# ---- 词条：法术连击 ----
	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "spellbook" or attacker.get_weapon_type() == "staff":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]

			if attacker.get_weapon_type() == "staff":
				print("法术连击触发！Lv.%d 额外治疗" % level)
				TalentManager.reset_talent(attacker, "spell_chain")
				await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
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
				await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
				var extra_dead = defender.apply_damage(extra_damage)
				SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)
				if extra_dead:
					print(defender.unit_stats.unit_name + " 阵亡！")
					_on_kill(attacker, defender)
					UnitManager.unregister_unit(defender)
					defender.queue_free()

					# ★ 检查 cleave
					if not attacker.has_attacked:
						Globals.is_performing_action = false
						return true

					_finish_attack(attacker, defender)
					Globals.is_performing_action = false
					return true

	# ---- 反击 ----
	if _can_counter_attack(attacker, defender):
		await _execute_counter(attacker, defender)

	_finish_attack(attacker, defender)
	Globals.is_performing_action = false
	return true


# ============================================================
#  击杀连锁
# ============================================================
func _on_kill(attacker: Unit, _defender: Unit):
	if not is_instance_valid(attacker):
		return

	# ---- 血怒：击杀回 HP ----
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

	# ---- 连斩：击杀后本回合可再攻击一次 ----
	if TalentManager.is_talent_ready(attacker, "cleave"):
		attacker.has_attacked = false
		attacker.has_acted = false
		attacker.movement_after_attack = false
		print("连斩触发！可再次行动")
		TalentManager.reset_talent(attacker, "cleave")

	# ---- 疾风遗物：击杀后再移动 ----
	if attacker.relic_kill_grants_extra_move > 0:
		attacker.remaining_move += attacker.relic_kill_grants_extra_move
		attacker.has_moved = false
		print("疾风遗物：额外移动 %d 格" % attacker.relic_kill_grants_extra_move)

func _apply_splash(attacker: Unit, defender: Unit, base_damage: int, percent: float):
	var dir = defender.grid_cell - attacker.grid_cell
	var behind = defender.grid_cell + dir
	var splash_target = UnitManager.get_unit_at_cell(behind)
	if not splash_target or splash_target.hit_points <= 0:
		return
	if splash_target.unit_stats.team_id == attacker.unit_stats.team_id:
		return
	var splash_dmg = int(base_damage * percent)
	var dead = _apply_damage_with_effects(splash_target, splash_dmg, attacker)
	SignalBus.request_damage_popup.emit(splash_target.global_position, splash_dmg, false, false, false)
	print("[贯穿] 溅射 %d 伤害给 %s" % [splash_dmg, splash_target.unit_stats.unit_name])
	if dead:
		_on_kill(attacker, splash_target)
		UnitManager.unregister_unit(splash_target)
		splash_target.queue_free()


func _apply_aoe(attacker: Unit, center: Unit, base_damage: int, percent: float):
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d in dirs:
		var cell = center.grid_cell + d
		var target = UnitManager.get_unit_at_cell(cell)
		if not target or target.hit_points <= 0:
			continue
		if target.unit_stats.team_id == attacker.unit_stats.team_id:
			continue
		var aoe_dmg = int(base_damage * percent)
		var dead = _apply_damage_with_effects(target, aoe_dmg, attacker)
		SignalBus.request_damage_popup.emit(target.global_position, aoe_dmg, false, false, false)
		print("[火球] AOE %d 伤害给 %s" % [aoe_dmg, target.unit_stats.unit_name])
		if dead:
			_on_kill(attacker, target)
			UnitManager.unregister_unit(target)
			target.queue_free()


# ============================================================
#  治疗
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

	# ---- 词条：治愈强化 ----
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

	# ★ 主动技能：群体治愈
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
	_finish_attack(attacker, defender)
	Globals.is_performing_action = false
	return true


# ============================================================
#  伤害应用 + 词条效果
# ============================================================
func _apply_damage_with_effects(defender: Unit, damage: int, attacker: Unit) -> bool:
	# ---- 词条：盾反 ----
	if TalentManager.is_talent_ready(defender, "parry"):
		var level = _get_effective_talent_level(defender, "parry")
		var reflect_mult = 0.5 + (level - 1) * 0.15
		var parry_damage = int(damage * reflect_mult)
		attacker.apply_damage(parry_damage)
		SignalBus.request_damage_popup.emit(attacker.global_position, parry_damage, false, false, false)
		print("盾反触发！Lv.%d 反弹 %d 伤害" % [level, parry_damage])
		TalentManager.reset_talent(defender, "parry")

	# ---- 词条：格挡 ----
	if TalentManager.is_talent_ready(defender, "block"):
		var level = _get_effective_talent_level(defender, "block")
		var reduction = 0.5 + (level - 1) * 0.1
		damage = int(damage * (1.0 - reduction))
		print("格挡触发！Lv.%d 减伤 %d%%" % [level, int(reduction * 100)])
		TalentManager.reset_talent(defender, "block")

	# ---- 词条：出血 ----
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

	# ---- 守护遗物：HP < 30% 减伤 ----
	if defender.relic_low_hp_damage_reduce > 0.0:
		var hp_ratio = float(defender.hit_points) / float(defender.unit_stats.max_hp)
		if hp_ratio < 0.3:
			damage = max(1, int(damage * (1.0 - defender.relic_low_hp_damage_reduce)))
			print("守护遗物：低血量减伤 %d%%" % int(defender.relic_low_hp_damage_reduce * 100))

	var defeated = defender.apply_damage(damage)

	# ---- 生命遗物：每回合首次受伤回血 ----
	if not defeated and defender.relic_turn_first_hit_regen > 0.0 and not defender.relic_turn_first_hit_regen_used:
		var regen = int(damage * defender.relic_turn_first_hit_regen)
		if regen > 0:
			defender.hit_points = mini(defender.hit_points + regen, defender.unit_stats.max_hp)
			defender.update_hp_label()
			SignalBus.request_damage_popup.emit(defender.global_position, regen, false, false, true)
			print("生命遗物：本回合首次受伤回复 %d HP" % regen)
		defender.relic_turn_first_hit_regen_used = true

	# ★ ---- 凤凰之羽（遗物）：首次阵亡满血复活 ----
	if defeated and defender.relic_auto_revive_available:
		defender.hit_points = defender.unit_stats.max_hp
		defender.update_hp_label()
		SignalBus.request_damage_popup.emit(defender.global_position, defender.hit_points, false, false, true)
		defender.relic_auto_revive_available = false
		print("[凤凰之羽] %s 满血复活" % defender.unit_stats.unit_name)
		return false

	# ---- 词条：复活 ----
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
#  反击
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

	if TalentManager.is_talent_ready(defender, "counter_boost"):
		var level = _get_effective_talent_level(defender, "counter_boost")
		var mult = COUNTER_BOOST_MULT[level - 1]
		counter_damage = int(counter_damage * mult)
		print("反击强化触发！Lv.%d 倍率 ×%.2f" % [level, mult])
		TalentManager.reset_talent(defender, "counter_boost")

	print("反击伤害: ", counter_damage)

	var counter_hit_dir = (attacker.global_position - defender.global_position).normalized()
	attacker.play_hit_effect(counter_hit_dir, true)
	SignalBus.request_damage_popup.emit(attacker.global_position, counter_damage, false, false, false)
	SignalBus.request_screen_shake.emit(0.15, 4.0, counter_hit_dir)

	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout

	var attacker_dead = attacker.apply_damage(counter_damage)
	if attacker_dead:
		print(attacker.unit_stats.unit_name + " 阵亡！")
		_on_kill(defender, attacker)
		UnitManager.unregister_unit(attacker)
		attacker.queue_free()


# ============================================================
#  辅助
# ============================================================
func _finish_attack(attacker: Unit, _defender: Unit) -> void:
	attacker.mark_attacked()
	_show_menu_after_action(attacker)


func _show_menu_after_action(unit: Unit):
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if unit.unit_stats.team_id != 0:
		return
	if unit.remaining_move < 0:
		unit.remaining_move = 0
	InputManager.selected_unit = unit
	InputManager.interaction_phase = InputManager.Phase.MENU
	SignalBus.request_show_menu.emit(unit)


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
