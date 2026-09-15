extends Node

# ============================================================
#  品质 → 攻击/防御乘数
# ============================================================
const QUALITY_MULT = {
	"common": 1.0,
	"rare": 1.25,
	"epic": 1.5,
	"legendary": 1.8,
}

## 力量 → 防御减免系数
const STRENGTH_DEF_FACTOR : float = 0.3

func get_attackable_targets(unit: Unit) -> Array:
	var weapon_data = unit.get_weapon_data()
	if not weapon_data: return []
	var max_range = weapon_data.attack_range
	var min_range = weapon_data.min_attack_range
	var is_healer = weapon_data.stats.get("heal_amount", 0) > 0
	
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

func calculate_damage(attacker: Unit, defender: Unit) -> int:
	var weapon_data = attacker.get_weapon_data()
	if not weapon_data:
		return 0

	# ---- 武器基础攻击（品质乘数 + 升级加成） ----
	var quality_mult = QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_bonus = 0
	if attacker.weapon_slot:
		upgrade_bonus = attacker.weapon_slot.upgrade_level
	var base_attack = (weapon_data.base_attack + upgrade_bonus) * quality_mult

	# ---- 属性补正 ----
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

	var total_attack = base_attack + atk_bonus

	# ---- 防御（防具防御 + 品质乘数 + 力量减免） ----
	var armor_defense = 0
	for slot in defender.armor_slots:
		if slot:
			var item_data = ItemManager.get_item_data(slot.item_id)
			if item_data:
				var armor_quality_mult = QUALITY_MULT.get(item_data.quality, 1.0)
				armor_defense += item_data.defense * armor_quality_mult
	var def_value = defender.unit_stats.strength * STRENGTH_DEF_FACTOR + armor_defense

	var damage = max(1, int(total_attack - def_value))
	return damage

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
	
	if _can_counter_attack(attacker, defender):
		await _execute_counter(attacker, defender)
	
	_finish_attack(attacker, defender)
	Globals.is_performing_action = false
	return true

func _execute_heal(attacker: Unit, defender: Unit) -> bool:
	if defender.unit_stats.team_id != attacker.unit_stats.team_id:
		print("错误：治疗不能对敌方！")
		Globals.is_performing_action = false
		return false
	
	var weapon_data = attacker.get_weapon_data()
	var heal_amount = weapon_data.heal_effect.get("base_heal", 0)
	var faith_bonus = attacker.unit_stats.faith * weapon_data.heal_effect.get("faith_multiplier", 1.0)
	var total_heal = int(heal_amount + faith_bonus)
	
	var old_hp = defender.hit_points
	defender.hit_points = min(defender.hit_points + total_heal, defender.unit_stats.max_hp)
	var actual_heal = defender.hit_points - old_hp
	print("治疗 ", actual_heal, " 点 HP")
	
	defender.update_hp_label()
	SignalBus.request_damage_popup.emit(defender.global_position, actual_heal, false, false, true)
	SoundManager.play_heal_sound()
	
	await get_tree().create_timer(MapConst.PERFORMANCE_DURATION).timeout
	_finish_attack(attacker, defender)
	Globals.is_performing_action = false
	return true

func _apply_damage_with_effects(defender: Unit, damage: int, attacker: Unit) -> bool:
	# ---- 词条：盾反（等级越高反弹越多） ----
	if TalentManager.is_talent_ready(defender, "parry"):
		var level = _get_effective_talent_level(defender, "parry")
		var reflect_mult = 0.5 + (level - 1) * 0.15   # Lv1=50% / Lv2=65% / Lv3=80%
		var parry_damage = int(damage * reflect_mult)
		attacker.apply_damage(parry_damage)
		SignalBus.request_damage_popup.emit(attacker.global_position, parry_damage, false, false, false)
		print("盾反触发！Lv.%d 反弹 %d 伤害" % [level, parry_damage])
		TalentManager.reset_talent(defender, "parry")
	
	# ---- 词条：格挡（等级越高减伤越多） ----
	if TalentManager.is_talent_ready(defender, "block"):
		var level = _get_effective_talent_level(defender, "block")
		var reduction = 0.5 + (level - 1) * 0.1       # Lv1=50% / Lv2=60% / Lv3=70%
		damage = int(damage * (1.0 - reduction))
		print("格挡触发！Lv.%d 减伤 %d%%" % [level, int(reduction * 100)])
		TalentManager.reset_talent(defender, "block")
	
	# ---- 词条：暴击（等级越高倍率越高） ----
	if TalentManager.is_talent_ready(attacker, "crit"):
		var level = _get_effective_talent_level(attacker, "crit")
		var crit_mult = 2.0 + (level - 1) * 0.5       # Lv1=2.0 / Lv2=2.5 / Lv3=3.0
		damage = int(damage * crit_mult)
		print("暴击触发！Lv.%d 倍率 %.1f" % [level, crit_mult])
		TalentManager.reset_talent(attacker, "crit")
	
	return defender.apply_damage(damage)


# ============================================================
#  词条等级：仅玩家单位享受等级加成
# ============================================================
func _get_effective_talent_level(unit: Unit, talent_id: String) -> int:
	if unit.unit_stats.team_id != 0:
		return 1   # 敌人不享受等级加成
	return TalentManager.get_talent_level(unit.unit_stats.unit_name, talent_id)

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
	print("反击伤害: ", counter_damage)
	
	var counter_hit_dir = (attacker.global_position - defender.global_position).normalized()
	attacker.play_hit_effect(counter_hit_dir, true)
	SignalBus.request_damage_popup.emit(attacker.global_position, counter_damage, false, false, false)
	SignalBus.request_screen_shake.emit(0.15, 4.0, counter_hit_dir)
	
	await get_tree().create_timer(MapConst.PERFORMANCE_DURATION).timeout
	
	var attacker_dead = attacker.apply_damage(counter_damage)
	if attacker_dead:
		print(attacker.unit_stats.unit_name + " 阵亡！")
		UnitManager.unregister_unit(attacker)
		attacker.queue_free()

func _finish_attack(attacker: Unit, _defender: Unit) -> void:
	attacker.mark_attacked()
	_show_menu_after_action(attacker)
	
func _show_menu_after_action(unit: Unit):
	if TurnManager.current_turn_team != TurnManager.Team.PLAYER:
		return
	if unit.unit_stats.team_id != 0:
		return
	print("行动后显示菜单: ", unit.unit_stats.unit_name)
	print("当前剩余移动: ", unit.remaining_move)
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
		return {
			"attack": weapon.stats.get("attack", 0) if weapon.stats else 0,
			"magic_attack": weapon.stats.get("magic_attack", 0) if weapon.stats else 0,
			"heal_amount": weapon.stats.get("heal_amount", 0) if weapon.stats else 0,
			"attack_range": weapon.attack_range,
			"min_attack_range": weapon.min_attack_range
		}
	else:
		return {
			"attack": 0,
			"magic_attack": 0,
			"heal_amount": 0,
			"attack_range": 0,
			"min_attack_range": 0
		}
