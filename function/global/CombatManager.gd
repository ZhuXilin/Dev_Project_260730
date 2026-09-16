extends Node

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")

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

# ============================================================
#  词条等级参数
# ============================================================
## 二次攻击：额外攻击倍率 [Lv1, Lv2, Lv3]
const DOUBLE_ATTACK_MULT : Array = [0.8, 0.9, 1.0]

## 出血：触发伤害占 max_hp 比例
const BLEED_DAMAGE_PERCENT : Array = [0.15, 0.20, 0.25]
const BLEED_MAX_STACKS : int = 5

## 法术连击：额外施法倍率
const SPELL_CHAIN_MULT : Array = [0.8, 0.9, 1.0]

## 反击强化：反击伤害倍率
const COUNTER_BOOST_MULT : Array = [1.5, 1.75, 2.0]

## 治愈强化：治疗量倍率
const HEAL_BOOST_MULT : Array = [1.3, 1.5, 1.7]


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
		var val = 0
		match attr:
			"strength": val = attacker.unit_stats.strength
			"dexterity": val = attacker.unit_stats.dexterity
			"intelligence": val = attacker.unit_stats.intelligence
			"faith": val = attacker.unit_stats.faith
			"arcane": val = attacker.unit_stats.arcane
		atk_bonus += val * modifier[attr]

	var total_attack = base_attack + atk_bonus + attacker.unit_stats.buff_attack_flat
	total_attack *= (1.0 + attacker.unit_stats.buff_attack_percent)   # ← 加这行

	var armor_defense = 0
	for slot in defender.armor_slots:
		if slot:
			var item_data = ItemManager.get_item_data(slot.item_id)
			if item_data:
				var armor_quality_mult = QUALITY_MULT.get(item_data.quality, 1.0)
				armor_defense += item_data.defense * armor_quality_mult
	var def_value = defender.unit_stats.strength * STRENGTH_DEF_FACTOR + armor_defense
	def_value += defender.unit_stats.buff_defense_flat                      # ← 加这行

	var damage = max(1, int(total_attack - def_value))

	if defender.unit_stats.buff_damage_reduction > 0:                       # ← 加这 2 行
		damage = max(1, int(damage * (1.0 - defender.unit_stats.buff_damage_reduction)))

	return damage

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
	print("造成伤害: ", damage)

	var defeated = _apply_damage_with_effects(defender, damage, attacker)
	if defeated:
		print(defender.unit_stats.unit_name + " 阵亡！")
		UnitManager.unregister_unit(defender)
		defender.queue_free()
		_finish_attack(attacker, defender)
		Globals.is_performing_action = false
		return true

	# ---- 词条：二次攻击 ----
	if TalentManager.is_talent_ready(attacker, "double_attack"):
		var level = _get_effective_talent_level(attacker, "double_attack")
		var mult = DOUBLE_ATTACK_MULT[level - 1]
		var extra_damage = int(damage * mult)
		print("二次攻击触发！Lv.%d 额外 %d 伤害" % [level, extra_damage])
		TalentManager.reset_talent(attacker, "double_attack")

		await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
		# 二次攻击不再触发其他词条，直接造成伤害
		var extra_dead = defender.apply_damage(extra_damage)
		SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)
		if extra_dead:
			print(defender.unit_stats.unit_name + " 阵亡！")
			UnitManager.unregister_unit(defender)
			defender.queue_free()
			_finish_attack(attacker, defender)
			Globals.is_performing_action = false
			return true

	# ---- 词条：法术连击（法师额外施法） ----
	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "spellbook" or attacker.get_weapon_type() == "staff":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]

			# ---- 治疗武器 → 额外治疗 ----
			if attacker.get_weapon_type() == "staff":
				print("法术连击触发！Lv.%d 额外治疗" % level)
				TalentManager.reset_talent(attacker, "spell_chain")
				await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
				# 简化：额外治疗 = 治疗量 × mult（需要重算）
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
				# ---- 法术攻击 → 额外伤害 ----
				var extra_damage = int(damage * mult)
				print("法术连击触发！Lv.%d 额外 %d 伤害" % [level, extra_damage])
				TalentManager.reset_talent(attacker, "spell_chain")
				await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
				var extra_dead = defender.apply_damage(extra_damage)
				SignalBus.request_damage_popup.emit(defender.global_position, extra_damage, false, false, false)
				if extra_dead:
					print(defender.unit_stats.unit_name + " 阵亡！")
					UnitManager.unregister_unit(defender)
					defender.queue_free()
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

	# ---- 词条：暴击 ----
	if TalentManager.is_talent_ready(attacker, "crit"):
		var level = _get_effective_talent_level(attacker, "crit")
		var crit_mult = 2.0 + (level - 1) * 0.5
		crit_mult += attacker.unit_stats.buff_crit_damage_bonus   # ← 加这行
		damage = int(damage * crit_mult)
		print("暴击触发！Lv.%d 倍率 %.1f" % [level, crit_mult])
		TalentManager.reset_talent(attacker, "crit")

	# ---- 词条：出血（给目标累积层数） ----
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
					return true

	return defender.apply_damage(damage)


# ============================================================
#  等级读取（只有玩家单位享受等级加成）
# ============================================================
func _get_effective_talent_level(unit: Unit, talent_id: String) -> int:
	if unit.unit_stats.team_id != 0:
		return 1
	return TalentManager.get_talent_level(unit.unit_stats.unit_name, talent_id)


# ============================================================
#  反击
# ============================================================
func _can_counter_attack(attacker: Unit, defender: Unit) -> bool:
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

	# ---- 词条：反击强化 ----
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
