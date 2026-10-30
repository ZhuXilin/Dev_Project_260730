extends Node

var QUALITY_MULT : Dictionary = {"common":1.0,"rare":1.25,"epic":1.5,"legendary":1.8}
var CRIT_BASE_CHANCE : float = 0.05
var CRIT_PER_DEXTERITY : float = 0.005
var CRIT_CHANCE_BY_QUALITY : Dictionary = {"common":0.0,"rare":0.03,"epic":0.05,"legendary":0.08}
var CRIT_DAMAGE_MULT : float = 1.5
var CRIT_DAMAGE_CAP : float = 2.0
var REDUCTION_CAP : float = 0.75
var MIN_DAMAGE_FLOOR : float = 0.10
var FOLLOW_UP_DEX_GAP : int = 4
var FOLLOW_UP_DAMAGE_MULT : float = 0.6

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

const DEBUG_DAMAGE_LOG : bool = true

func _ready():
	reload_config()

func reload_config():
	var cfg := GameConfigManager.get_file("combat_config.json")
	QUALITY_MULT = cfg.get("quality_mult", QUALITY_MULT).duplicate()
	CRIT_BASE_CHANCE = float(cfg.get("crit_base_chance", CRIT_BASE_CHANCE))
	CRIT_PER_DEXTERITY = float(cfg.get("crit_per_dexterity", CRIT_PER_DEXTERITY))
	CRIT_CHANCE_BY_QUALITY = cfg.get("crit_chance_by_quality", CRIT_CHANCE_BY_QUALITY).duplicate()
	CRIT_DAMAGE_MULT = float(cfg.get("crit_damage_mult", CRIT_DAMAGE_MULT))
	CRIT_DAMAGE_CAP = float(cfg.get("crit_damage_cap", CRIT_DAMAGE_CAP))
	REDUCTION_CAP = float(cfg.get("reduction_cap", REDUCTION_CAP))
	MIN_DAMAGE_FLOOR = float(cfg.get("min_damage_floor", MIN_DAMAGE_FLOOR))
	FOLLOW_UP_DEX_GAP = int(cfg.get("follow_up_dex_gap", FOLLOW_UP_DEX_GAP))
	FOLLOW_UP_DAMAGE_MULT = float(cfg.get("follow_up_damage_mult", FOLLOW_UP_DAMAGE_MULT))

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

	var heal_targets : Array = []
	var attack_targets : Array = []
	for x in range(-max_range, max_range+1):
		for y in range(-max_range, max_range+1):
			var dist = abs(x) + abs(y)
			if dist < min_range or dist > max_range: continue
			var cell = unit.grid_cell + Vector2i(x, y)
			if cell.x < 0 or cell.x >= TerrainManager.grid_size.x or cell.y < 0 or cell.y >= TerrainManager.grid_size.y: continue
			var target = UnitManager.get_unit_at_cell(cell)
			if not target or target.hit_points <= 0: continue
			if is_healer:
				if target.unit_stats.team_id == unit.unit_stats.team_id:
					heal_targets.append(target)
				else:
					attack_targets.append(target)
			else:
				if target.unit_stats.team_id != unit.unit_stats.team_id:
					attack_targets.append(target)

	if is_healer:
		var wounded = heal_targets.filter(func(t): return t.hit_points < t.unit_stats.max_hp)
		if not wounded.is_empty():
			wounded.sort_custom(func(a, b):
				return (a.unit_stats.max_hp - a.hit_points) > (b.unit_stats.max_hp - b.hit_points))
			return wounded
		if not attack_targets.is_empty():
			attack_targets.sort_custom(func(a, b):
				var da = abs(a.grid_cell.x - unit.grid_cell.x) + abs(a.grid_cell.y - unit.grid_cell.y)
				var db = abs(b.grid_cell.x - unit.grid_cell.x) + abs(b.grid_cell.y - unit.grid_cell.y)
				return da < db)
			return attack_targets
		return []

	attack_targets.sort_custom(func(a, b):
		var da = abs(a.grid_cell.x - unit.grid_cell.x) + abs(a.grid_cell.y - unit.grid_cell.y)
		var db = abs(b.grid_cell.x - unit.grid_cell.x) + abs(b.grid_cell.y - unit.grid_cell.y)
		return da < db)
	return attack_targets

func attempt_attack_after_move(unit: Unit):
	var targets = get_attackable_targets(unit)
	if targets.size() > 0:
		await execute_attack(unit, targets[0])


func _is_magic_attack(weapon_data: ItemData) -> bool:
	if weapon_data == null: return false
	if weapon_data.attack_style == "magic": return true
	if weapon_data.category == "staff": return true
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

	# ★ v4.6：地形减伤（与面板减伤加法叠加，受 75% 上限约束）
	var terrain_bonus : float = 0.0
	if defender != null and defender.grid_cell.x >= 0 and defender.grid_cell.y >= 0:
		var t : int = TerrainManager.get_terrain(defender.grid_cell)
		var td : Dictionary = TerrainManager.TERRAIN_DATA.get(t, {})
		terrain_bonus = float(td.get("magic_reduction" if is_magic else "physical_reduction", 0.0))

	var shred : float = 0.0
	if not is_magic:
		shred = defender.buff_defense_shred

	var total : float = base + armor_bonus + affix_bonus + low_hp_bonus + buff_bonus + terrain_bonus - shred
	return clampf(total, 0.0, REDUCTION_CAP)


func _calc_penetration(attacker: Unit, is_magic: bool) -> float:
	if attacker == null:
		return 0.0
	var wdata = attacker.get_weapon_data()
	var weapon_pen : float = 0.0
	if wdata:
		weapon_pen = wdata.magic_penetration if is_magic else wdata.physical_penetration

	var affix_pen : float = 0.0
	if is_magic:
		affix_pen = attacker.get_total_affix_value_float("magic_penetration")
	else:
		affix_pen = attacker.get_total_affix_value_float("physical_penetration")

	var temp_pen : float = attacker.temp_magic_penetration if is_magic else attacker.temp_physical_penetration

	return weapon_pen + affix_pen + temp_pen


func calculate_damage(attacker: Unit, defender: Unit, apply_heavy: bool = true) -> int:
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

	var ignore_def : bool = weapon_data.magic_attack.get("ignore_defense", false)
	var effective_reduction : float = 0.0
	if not ignore_def:
		var reduction : float = _calc_reduction(defender, is_magic)
		var penetration : float = _calc_penetration(attacker, is_magic)
		effective_reduction = clampf(reduction - penetration, 0.0, 1.0)

	var damage_raw : float = total_attack * (1.0 - effective_reduction)
	var floor_raw : float = total_attack * MIN_DAMAGE_FLOOR
	var damage : int = max(1, int(max(damage_raw, floor_raw)))

	if apply_heavy and not weapon_data.heavy_attack.is_empty():
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


func _calculate_damage_ignore_defense(attacker: Unit, defender: Unit, apply_heavy: bool = true) -> int:
	if attacker == null or defender == null:
		return 0
	var weapon_data = attacker.get_weapon_data()
	if not weapon_data:
		return 1
	var is_magic : bool = _is_magic_attack(weapon_data)
	var quality_mult : float = QUALITY_MULT.get(weapon_data.quality, 1.0)
	var upgrade_lv : int = attacker.weapon_slot.upgrade_level if attacker.weapon_slot else 0
	var base_attack : float = WeaponUpgradeHelper.get_effective_base_attack(weapon_data, upgrade_lv) * quality_mult
	var modifier = weapon_data.modifier
	var atk_bonus : float = 0.0
	for attr in modifier:
		atk_bonus += attacker.unit_stats.get_effective_attr(attr) * modifier[attr]
	var total_attack : float = base_attack + atk_bonus + attacker.buff_attack_flat
	if is_magic:
		total_attack += attacker.buff_magic_attack_flat
	total_attack *= (1.0 + attacker.buff_attack_percent)
	if attacker.relic_strength_scale_damage > 0.0:
		var str_val : int = attacker.unit_stats.get_effective_attr("strength")
		total_attack *= (1.0 + str_val * attacker.relic_strength_scale_damage)

	var damage : int = max(1, int(total_attack))

	if apply_heavy and not weapon_data.heavy_attack.is_empty():
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
		if slot:
			atk_affix_bonus += slot.get_affix_value("attack_flat")
	damage += atk_affix_bonus

	if defender.unit_stats.team_id == 0:
		var taken_mult : float = SoulFireManager.get_damage_taken_mult()
		if taken_mult > 1.0:
			damage = int(damage * taken_mult)

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

	# ★ 友军保护：非 staff 打友军 = 攻击，禁止
	if defender.unit_stats.team_id == attacker.unit_stats.team_id:
		if attacker.get_weapon_type() != "staff":
			Globals.is_performing_action = false
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("不能攻击友军", 1.0)
			return false

	_face_each_other(attacker, defender)
	Globals.is_performing_action = true

	if attacker.get_weapon_type() == "staff" \
			and defender.unit_stats.team_id == attacker.unit_stats.team_id:
		# 满血友军拦截
		if defender.hit_points >= defender.unit_stats.max_hp:
			Globals.is_performing_action = false
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("目标未受伤", 1.0)
			return false
		await _execute_heal(attacker, defender, forced_skill_id)
		Globals.is_performing_action = false
		return true

	await _play_lunge_attack(attacker, defender)

	var has_skill : bool = false
	var active_skill_id : String = ""
	var active_skill_data = null
	if forced_skill_id != "":
		var sdata = TalentManager.get_talent_data(forced_skill_id)
		if sdata:
			# ★ v4.6：治疗型技能只能对友军释放，对敌人时拒绝（走普攻）
			if sdata.effect_type == "heal" and defender.unit_stats.team_id != attacker.unit_stats.team_id:
				print("[主动技能] %s 是治疗技能，不能对敌人释放，已回退为普攻" % sdata.display_name)
			else:
				var cost : int = _get_active_skill_cost(sdata)
				if SoulFireManager.can_spend(cost):
					active_skill_id = forced_skill_id
					active_skill_data = sdata
					has_skill = true
				else:
					print("[主动技能] %s 魂火不足" % attacker.unit_stats.unit_name)

	var heavy_mult : float = 1.0
	var wdata = attacker.get_weapon_data()
	if wdata and not wdata.heavy_attack.is_empty():
		if attacker.has_core_trait("charge"):
			heavy_mult = minf(1.0 + 0.2 * float(attacker.charge_stacks), float(wdata.heavy_attack.get("charge_multiplier", 2.0)))
		else:
			heavy_mult = float(wdata.heavy_attack.get("damage_multiplier", 1.0))

	var force_crit : bool = false
	var splash_percent : float = 0.0
	var aoe_percent : float = 0.0
	var hp_cost_percent : float = 0.0
	var taunt_rounds : int = 0
	if active_skill_data:
		var ep0 : Dictionary = active_skill_data.effect_params
		attacker.temp_physical_penetration = float(ep0.get("physical_penetration", 0.0))
		attacker.temp_magic_penetration = float(ep0.get("magic_penetration", 0.0))
		force_crit = bool(ep0.get("force_crit", false))
		splash_percent = float(ep0.get("splash_percent", 0.0))
		aoe_percent = float(ep0.get("aoe_percent", 0.0))
		hp_cost_percent = float(ep0.get("hp_cost_percent", 0.0))
		taunt_rounds = int(ep0.get("taunt_rounds", 0))

	var damage = calculate_damage(attacker, defender, not has_skill)

	if active_skill_data:
		var ep : Dictionary = active_skill_data.effect_params
		if bool(ep.get("ignore_defense", false)):
			damage = _calculate_damage_ignore_defense(attacker, defender, false)

	attacker.temp_physical_penetration = 0.0
	attacker.temp_magic_penetration = 0.0

	if active_skill_data:
		var ep2 : Dictionary = active_skill_data.effect_params
		var skill_mult : float = float(ep2.get("damage_mult", 1.0))
		damage = int(damage * maxf(skill_mult, heavy_mult))

	if attacker.has_core_trait("charge") and attacker.charge_stacks > 0:
		attacker.charge_stacks = 0

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
	if attacker.unit_stats.team_id == 0:
		crit_mult += SoulFireManager.get_crit_damage_bonus()
	crit_mult += attacker.get_total_affix_value_float("crit_damage")

	var crit_talent_triggered : bool = false
	if force_crit:
		is_crit = true
	elif TalentManager.is_talent_ready(attacker, "crit"):
		var lv_crit = _get_effective_talent_level(attacker, "crit")
		var cdata = TalentManager.get_talent_data("crit")
		var base_mult : float = 1.5
		if cdata:
			base_mult = float(cdata.effect_params.get("damage_multiplier", 1.5))
		crit_mult = base_mult + (lv_crit - 1) * 0.25 + attacker.buff_crit_damage_bonus
		crit_mult += attacker.get_total_affix_value_float("crit_damage")
		is_crit = true
		crit_talent_triggered = true
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

	crit_mult = minf(crit_mult, CRIT_DAMAGE_CAP)

	if is_crit:
		var anti_crit : float = clampf(defender.get_total_affix_value_float("anti_crit"), 0.0, 0.8)
		var effective_crit_mult : float = 1.0 + (crit_mult - 1.0) * (1.0 - anti_crit)
		damage = int(damage * effective_crit_mult)

		if crit_talent_triggered:
			var cdata2 = TalentManager.get_talent_data("crit")
			var shred : float = 0.20
			var shred_cap : float = 0.50
			if cdata2:
				shred = float(cdata2.effect_params.get("defense_shred", 0.20))
				shred_cap = float(cdata2.effect_params.get("shred_cap", 0.50))
			defender.buff_defense_shred = minf(defender.buff_defense_shred + shred, shred_cap)
			SignalBus.request_hint_override.emit(
				"★ %s 物减 -%d%%（累积 -%d%%）" % [
					defender.unit_stats.unit_name,
					int(shred * 100),
					int(defender.buff_defense_shred * 100)
				], 1.0)

	if hp_cost_percent > 0.0:
		var hp_cost = int(attacker.unit_stats.max_hp * hp_cost_percent)
		attacker.hit_points = max(1, attacker.hit_points - hp_cost)
		attacker.update_hp_label()
		SignalBus.request_damage_popup.emit(attacker.global_position, hp_cost, false, false, false)

	if DEBUG_DAMAGE_LOG:
		print("[伤害链] %s → %s | heavy=%.2f | crit=%s(%.2f) | skill=%s | 最终=%d" % [
			attacker.unit_stats.unit_name, defender.unit_stats.unit_name,
			heavy_mult, is_crit, crit_mult, active_skill_id if active_skill_id != "" else "-",
			damage
		])

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

	# ★ 修正 A：spell_chain 在 execute_attack 中只处理「法术书」的额外伤害链。
	#   staff 走到此处意味着"staff 打敌人"（治疗场景已在函数开头提前返回），
	#   原代码用治疗量给敌人回血属于逻辑 bug，已移除。staff 的 spell_chain 由 _execute_heal 处理。
	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "spellbook":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]
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

	if _is_alive(attacker) and _is_alive(defender) and _can_follow_up(attacker, defender):
		var follow_dmg : int = int(calculate_damage(attacker, defender) * FOLLOW_UP_DAMAGE_MULT)
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


func _execute_heal(attacker: Unit, defender: Unit, forced_skill_id: String = "") -> bool:
	if defender.unit_stats.team_id != attacker.unit_stats.team_id:
		Globals.is_performing_action = false
		return false

	# ★ 满血直接拒绝：播取消音 + 提示 + 不消耗行动
	if defender.hit_points >= defender.unit_stats.max_hp:
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("目标未受伤", 1.0)
		Globals.is_performing_action = false
		return false

	var total_heal : int = get_expected_heal_amount(attacker, defender)

	if TalentManager.is_talent_ready(attacker, "heal_boost"):
		TalentManager.reset_talent(attacker, "heal_boost")

	var old_hp = defender.hit_points
	defender.hit_points = mini(defender.hit_points + total_heal, defender.unit_stats.max_hp)
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

	# ★ 修正 B：staff 的 spell_chain 二次治疗（真正治疗友军时触发）
	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "staff":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]
			TalentManager.reset_talent(attacker, "spell_chain")
			await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
			if not _is_alive(attacker):
				Globals.is_performing_action = false
				return true
			var base_heal_val : int = _calc_staff_heal(attacker, defender)
			var extra_heal : int = int(base_heal_val * mult)
			var old_hp2 : int = defender.hit_points
			defender.hit_points = mini(defender.hit_points + extra_heal, defender.unit_stats.max_hp)
			var actual2 : int = defender.hit_points - old_hp2
			if actual2 > 0:
				defender.update_hp_label()
				SignalBus.request_damage_popup.emit(defender.global_position, actual2, false, false, true)

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

	# ★ 敌方死亡生成血球
	if is_instance_valid(_defender) and _defender.unit_stats.team_id == 1:
		ItemBattlefieldManager.try_spawn_orb(_defender.grid_cell)

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

	if DEBUG_DAMAGE_LOG:
		print("[伤害] %s → %s | 最终=%d | HP %d→%d | 攻方武器=%s" % [
			attacker.unit_stats.unit_name if attacker else "环境",
			defender.unit_stats.unit_name,
			damage, defender.hit_points, max(0, defender.hit_points - damage),
			attacker.get_equipped_weapon_id() if attacker else "-"
		])

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
	
	if damage > 0 and is_instance_valid(attacker):
		var active_sets : Array = SetBonusManager.get_active_sets_for_unit(attacker)
		for entry in active_sets:
			var b : Dictionary = entry["bonus"]
			if b.get("effect", "") == "damage_lifesteal":
				var pct : float = float(b.get("value", 0.0))
				var heal : int = int(damage * pct)
				if heal > 0:
					var old_hp : int = attacker.hit_points
					attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
					var actual : int = attacker.hit_points - old_hp
					if actual > 0:
						attacker.update_hp_label()
						SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)
	
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


## 修女基础治疗量：目标 max_hp × (基础% + faith × 每点%)
## 新格式：heal_effect = { "base_heal_percent": 0.2, "faith_percent_per_point": 0.01 }
## 兼容旧格式：heal_effect = { "base_heal": 8, "faith_multiplier": 1.0 }
func _calc_staff_heal(attacker: Unit, defender: Unit) -> int:
	var weapon_data = attacker.get_weapon_data()
	if weapon_data == null:
		return 0
	var base_pct : float = float(weapon_data.heal_effect.get("base_heal_percent", 0.0))
	if base_pct > 0.0:
		var faith_pct : float = float(weapon_data.heal_effect.get("faith_percent_per_point", 0.01))
		var heal_pct : float = base_pct + attacker.unit_stats.faith * faith_pct
		return maxi(1, int(defender.unit_stats.max_hp * heal_pct))
	# 旧格式回退
	var base_heal : int = int(weapon_data.heal_effect.get("base_heal", 0))
	var faith_bonus : float = attacker.unit_stats.faith * float(weapon_data.heal_effect.get("faith_multiplier", 1.0))
	return maxi(1, int(base_heal + faith_bonus))


## 获取包含遗物、词条、天赋在内的最终治疗量（供预估面板和实际执行共用）
func get_expected_heal_amount(attacker: Unit, defender: Unit) -> int:
	var total_heal : int = _calc_staff_heal(attacker, defender)
	
	if attacker.relic_heal_bonus > 0.0:
		total_heal = int(total_heal * (1.0 + attacker.relic_heal_bonus))
		
	var heal_affix_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot: heal_affix_bonus += slot.get_affix_value_float("heal_boost")
	total_heal = int(total_heal * (1.0 + heal_affix_bonus))
	
	if TalentManager.is_talent_ready(attacker, "heal_boost"):
		var level = _get_effective_talent_level(attacker, "heal_boost")
		total_heal = int(total_heal * HEAL_BOOST_MULT[level - 1])
		
	return total_heal
	

## 急救：任何单位可用，消耗行动 + 魂火，治疗受伤友军。
## 返回 true 表示施放成功。
func execute_emergency_heal(attacker: Unit, target: Unit) -> bool:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	if attacker.unit_stats.team_id != 0 or target.unit_stats.team_id != 0:
		return false
	if target.hit_points >= target.unit_stats.max_hp:
		SignalBus.request_hint_override.emit("目标未受伤", 1.0)
		return false

	var cost : int = SoulFireManager.get_emergency_heal_cost()
	if not SoulFireManager.can_spend(cost):
		SignalBus.request_hint_override.emit("魂火不足（需 %d）" % cost, 1.2)
		return false

	SoulFireManager.spend(cost)

	Globals.is_performing_action = true

	var heal_pct : float = 0.5 # ★ 改成固定 50%
	var heal_amount : int = maxi(1, int(target.unit_stats.max_hp * heal_pct))

	# 受遗物 / 词条加成
	if attacker.relic_heal_bonus > 0.0:
		heal_amount = int(heal_amount * (1.0 + attacker.relic_heal_bonus))
	var heal_affix_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot: heal_affix_bonus += slot.get_affix_value_float("heal_boost")
	heal_amount = int(heal_amount * (1.0 + heal_affix_bonus))

	var old_hp : int = target.hit_points
	target.hit_points = mini(target.hit_points + heal_amount, target.unit_stats.max_hp)
	var actual : int = target.hit_points - old_hp

	target.update_hp_label()
	SignalBus.request_damage_popup.emit(target.global_position, actual, false, false, true)
	SignalBus.request_hint_override.emit("急救 +%d（-%d 魂火）" % [actual, cost], 1.5)
	SoundManager.play_heal_sound()

	# 消耗行动
	attacker.mark_attacked()
	_finish_attack(attacker, target)

	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
	Globals.is_performing_action = false
	return true
