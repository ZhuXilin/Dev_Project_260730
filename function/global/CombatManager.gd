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

# ★ v6.71：Build 觉醒技已删除（其流派全场质变由魂火爆发 + unit 身份 burst_trait 接管）

const PERFORMANCE_DURATION : float = 0.5
const LUNGE_DURATION : float = 0.15
const PRE_DAMAGE_DELAY : float = 0.10
const POST_DAMAGE_DELAY : float = 0.28
const EXTRA_HIT_DELAY : float = 0.15

const DEBUG_DAMAGE_LOG : bool = true

# ★ v6.2 灰烬：本场战斗的燃烧地块（cell -> {damage, team, owner, expire_clock}）
const ASH_TILE_MAX : int = 12
var ash_tiles : Dictionary = {}
var ash_turn_clock : int = 0

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
		if data == null:
			continue
		# ★ v6.17：射程加成必须同时满足"技能就绪 + 魂火付得起"。
		#   旧实现只看就绪，导致魂火不足时预览显示"可攻击"（射程+2），
		#   松手后 _show_attack_menu 因 can_spend 过滤掉技能、普攻又被射程限制，
		#   total_options==0 只弹提示不攻击——表现为"拖拽攻击有时不生效"。
		#   这里与菜单的 can_spend 口径统一，魂火不足时不再虚增预览射程。
		if not SoulFireManager.can_spend(_get_active_skill_cost(data)):
			continue
		bonus = maxi(bonus, int(data.effect_params.get("range_bonus", 0)))
	return bonus


func get_attackable_targets(unit: Unit) -> Array:
	var s = unit.unit_stats
	if s == null or s.weapon_name == "": return []

	var max_range : int = s.attack_range + unit.bonus_attack_range
	var min_range : int = s.min_attack_range
	max_range += get_active_skill_range_bonus(unit)
	var is_healer = (s.weapon_category == "staff" or s.attack_style == "heal")

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


func _is_magic_attack(s: UnitData) -> bool:
	if s == null: return false
	if s.attack_style == "magic": return true
	if s.weapon_category == "staff": return true
	if s.magic_attack.get("ignore_defense", false): return true
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
	# ★ v6.66：守护团队减伤（全队共享，1 回合）
	buff_bonus += defender.guard_team_dr
	# ★ v6.64：重甲燃烧态身份增益——受击减伤（数据项 damage_reduction）
	if SoulFireManager.get_state() == SoulFireManager.State.BURNING:
		var bt : Dictionary = SoulFireIdentity.get_burn_trait(defender.unit_stats.unit_name, defender.unit_stats.advanced_class)
		buff_bonus += float(bt.get("damage_reduction", 0.0))

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
	var s = attacker.unit_stats
	var weapon_pen : float = s.magic_penetration if is_magic else s.physical_penetration

	var affix_pen : float = 0.0
	if is_magic:
		affix_pen = attacker.get_total_affix_value_float("magic_penetration")
	else:
		affix_pen = attacker.get_total_affix_value_float("physical_penetration")

	var temp_pen : float = attacker.temp_magic_penetration if is_magic else attacker.temp_physical_penetration
	var static_pen : float = attacker.bonus_static_magic_penetration if is_magic else attacker.bonus_static_physical_penetration

	return weapon_pen + affix_pen + temp_pen + static_pen


func calculate_damage(attacker: Unit, defender: Unit, apply_heavy: bool = true) -> int:
	var s = attacker.unit_stats
	if s.weapon_name == "": return 0

	var is_magic : bool = _is_magic_attack(s)
	var quality_mult : float = QUALITY_MULT.get(s.weapon_quality, 1.0)
	var base_attack : float = s.attack * quality_mult
	var modifier = s.modifier
	var atk_bonus = 0.0
	for attr in modifier:
		atk_bonus += s.get_effective_attr(attr) * modifier[attr]
	var total_attack = base_attack + atk_bonus + attacker.buff_attack_flat
	if is_magic: total_attack += attacker.buff_magic_attack_flat
	total_attack *= (1.0 + attacker.buff_attack_percent + attacker.school_sacrifice_attack_bonus)
	if attacker.relic_strength_scale_damage > 0.0:
		var str_val = s.get_effective_attr("strength")
		total_attack *= (1.0 + str_val * attacker.relic_strength_scale_damage)

	var ignore_def : bool = s.magic_attack.get("ignore_defense", false)
	var effective_reduction : float = 0.0
	if not ignore_def:
		var reduction : float = _calc_reduction(defender, is_magic)
		var penetration : float = _calc_penetration(attacker, is_magic)
		effective_reduction = clampf(reduction - penetration, 0.0, 1.0)

	var damage_raw : float = total_attack * (1.0 - effective_reduction)
	# ★ v6.62y：易伤层（全队通用）——灼烧/冻寒每层 +3%、灰烬附着每层 +2%，上限 3 层。
	#   任何伤害来源都吃：普攻/技能/DOT/反击/溅射/灰烬地块都走这条公式。
	var abnormal_vuln : float = AbnormalManager.get_damage_taken_bonus(defender)
	if abnormal_vuln > 0.0:
		damage_raw *= (1.0 + abnormal_vuln)
	# ★ v6.62y：献祭收益者——对带异常目标额外 +5% 攻击
	var sacrifice_abn_bonus : float = AbnormalManager.get_sacrifice_abnormal_bonus(attacker, defender)
	if sacrifice_abn_bonus > 0.0:
		damage_raw *= (1.0 + sacrifice_abn_bonus)
	var floor_raw : float = total_attack * MIN_DAMAGE_FLOOR
	var damage : int = max(1, int(max(damage_raw, floor_raw)))

	if apply_heavy and not s.heavy_attack.is_empty():
		var mult : float = 1.0
		if attacker.has_core_trait("charge"):
			var per_stack : float = 0.2
			var max_mult : float = float(s.heavy_attack.get("charge_multiplier", 2.0))
			mult = minf(1.0 + per_stack * float(attacker.charge_stacks), max_mult)
		else:
			mult = float(s.heavy_attack.get("damage_multiplier", 1.0))
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
	var s = attacker.unit_stats
	if s.weapon_name == "": return 1

	var is_magic : bool = _is_magic_attack(s)
	var quality_mult : float = QUALITY_MULT.get(s.weapon_quality, 1.0)
	var base_attack : float = s.attack * quality_mult
	var modifier = s.modifier
	var atk_bonus : float = 0.0
	for attr in modifier:
		atk_bonus += s.get_effective_attr(attr) * modifier[attr]
	var total_attack : float = base_attack + atk_bonus + attacker.buff_attack_flat
	if is_magic:
		total_attack += attacker.buff_magic_attack_flat
	total_attack *= (1.0 + attacker.buff_attack_percent + attacker.school_sacrifice_attack_bonus)
	if attacker.relic_strength_scale_damage > 0.0:
		var str_val : int = s.get_effective_attr("strength")
		total_attack *= (1.0 + str_val * attacker.relic_strength_scale_damage)

	var damage : int = max(1, int(total_attack))

	if apply_heavy and not s.heavy_attack.is_empty():
		var mult : float = 1.0
		if attacker.has_core_trait("charge"):
			var per_stack : float = 0.2
			var max_mult : float = float(s.heavy_attack.get("charge_multiplier", 2.0))
			mult = minf(1.0 + per_stack * float(attacker.charge_stacks), max_mult)
		else:
			mult = float(s.heavy_attack.get("damage_multiplier", 1.0))
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
	var s = attacker.unit_stats
	chance += s.get_effective_attr("dexterity") * CRIT_PER_DEXTERITY
	if s.weapon_name != "":
		chance += CRIT_CHANCE_BY_QUALITY.get(s.weapon_quality, 0.0)
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
	# ★ v6.72：优先读新字段 cost（兼容旧 effect_params.soul_fire_cost），
	#   让 v6.71 全量迁移的字段真正生效。
	if sdata is TalentData:
		var new_cost : int = (sdata as TalentData).get_cost()
		if new_cost > 0: return new_cost
	var ep : Dictionary = sdata.effect_params if sdata.effect_params else {}
	var explicit : int = int(ep.get("soul_fire_cost", 0))
	if explicit > 0: return explicit
	if sdata.effect_type == "heal": return SoulFireManager.COST_SKILL_MAX
	return SoulFireManager.COST_SKILL_MIN


## 主动技能结算：把就绪状态转为冷却。
## 魂火已在 execute_attack 技能确认时预扣（v5.9），此处不再重复扣，
## 否则会二次扣费、且被命中/击杀收益抵消成"看不到消耗"。
## 击杀 / 攻击者阵亡等分支会提前 return，必须在每条 return 路径显式调用，
## 否则技能不进冷却，可无限连发（v5.8 修复）。
func _settle_active_skill(attacker: Unit, skill_id: String, sdata) -> void:
	if skill_id == "" or sdata == null:
		return
	if is_instance_valid(attacker):
		TalentManager.consume_active_skill(attacker, skill_id)

func _try_boss_revive(defender : Unit, _attacker : Unit) -> bool:
	if not BossMechanicManager.on_boss_defeated(defender): return false
	SignalBus.request_screen_shake.emit(0.4, 8.0, Vector2.ZERO)
	return true


func execute_attack(attacker: Unit, defender: Unit, forced_skill_id: String = "") -> bool:
	if attacker.get_equipped_weapon_id() == "":
		Globals.is_performing_action = false
		return false

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
		if defender.hit_points >= defender.unit_stats.max_hp:
			Globals.is_performing_action = false
			SoundManager.play_cancel_sound()
			SignalBus.request_hint_override.emit("目标未受伤", 1.0)
			return false
		await _execute_heal(attacker, defender, forced_skill_id)
		Globals.is_performing_action = false
		return true

	# ★ v5.0：删除旧的"每次攻击 +1 魂火"，改为命中/击杀分别结算
	# if attacker.unit_stats.team_id == 0:
	#     SoulFireManager.add(1)

	# ★ v5.9：主动技能先确认并预扣魂火，再播放攻击动画。
	#   旧实现在攻击结算末尾才扣，而命中(+1)/击杀(+3)收益在它之前结算：
	#   狙击这类高伤技能经常直接击杀，+3 正好抵消 -3，魂火条看起来完全没变。
	#   前移后 HUD 会先减少，之后命中/击杀再补回，玩家能明确看到消耗。
	# ★ v6.64：魂火 ≥3 时技能自动爆发——但不再替换 skill_id，而是保留原技能 + burst_requested 标志。
	#   爆发 = 原技能效果（保留功能）× 爆发倍率 + 单位/转职特有附加 + 清空魂火 + 结束行动。
	#   治疗技能同样有爆发形态（群体治疗/净化/回魂火），不再被排除。
	var burst_threshold : int = SoulFireIdentity.get_burst_threshold(attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
	var burst_requested : bool = forced_skill_id != "" \
		and attacker.unit_stats.team_id == 0 \
		and SoulFireManager.current >= burst_threshold
	# 兼容旧入口：显式 soul_fire_burst 视作请求爆发，但没有原技能可保留 → 退化为普攻形态的爆发
	if forced_skill_id == "soul_fire_burst":
		burst_requested = true
		forced_skill_id = ""

	var has_skill : bool = false
	var active_skill_id : String = ""
	var active_skill_data = null
	var is_soul_fire_burst : bool = false
	var burst_cost : int = 0

	if forced_skill_id != "":
		var sdata = TalentManager.get_talent_data(forced_skill_id)
		if sdata:
			if sdata.effect_type == "heal" and defender.unit_stats.team_id != attacker.unit_stats.team_id:
				print("[主动技能] %s 是治疗技能，不能对敌人释放，已回退为普攻" % sdata.display_name)
			else:
				active_skill_id = forced_skill_id
				active_skill_data = sdata   # ★ v6.64：爆发也保留原技能，溅射/AOE/嘲讽/治疗照常生效
				has_skill = true
				if burst_requested:
					burst_cost = SoulFireManager.current
					is_soul_fire_burst = true
					# 爆发消耗全部魂火（不在此 spend，稍后与倍率一起结算）
					SignalBus.request_hint_override.emit(
						"%s · 爆发（消耗 %d 魂火）" % [sdata.display_name, burst_cost], 1.2)
				else:
					var cost : int = _get_active_skill_cost(sdata)
					if SoulFireManager.can_spend(cost):
						SoulFireManager.spend(cost)
						SignalBus.request_hint_override.emit(
							"%s 消耗 %d 魂火" % [sdata.display_name, cost], 1.2)
					else:
						print("[主动技能] %s 魂火不足" % attacker.unit_stats.unit_name)
						SignalBus.request_hint_override.emit(
							"魂火不足（需 %d），本次改为普通攻击" % cost, 1.2)
	elif burst_requested:
		# 无原技能的旧入口：退化为普攻形态爆发
		burst_cost = SoulFireManager.current
		is_soul_fire_burst = true

	await _play_lunge_attack(attacker, defender)

	var s = attacker.unit_stats
	var heavy_mult : float = 1.0
	if not s.heavy_attack.is_empty():
		if attacker.has_core_trait("charge"):
			heavy_mult = minf(1.0 + 0.2 * float(attacker.charge_stacks), float(s.heavy_attack.get("charge_multiplier", 2.0)))
		else:
			heavy_mult = float(s.heavy_attack.get("damage_multiplier", 1.0))

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

	# ★ v6.70e：敌人蓄力意图释放——就绪时本次主攻击按倍率加成并消费。
	#   放在 calculate_damage 之后、技能/暴击倍率之前，避免被反击/追击重复消费。
	if attacker.unit_stats.team_id == 1 and attacker.intent_ready:
		var release_mult: float = EnemyIntentManager.consume_release_mult(attacker)
		if release_mult > 1.0:
			damage = int(float(damage) * release_mult)

	# ★ v6.71：初始 roll 的普攻强化模板（anchor=basic_attack/both）——被动结算，不占按钮。
	#   只吃 damage_mult（倍率），不额外消耗魂火、不进冷却、不触发异常。
	#   穿透/必暴类效果沿用技能按钮路径（anchor=soul_skill），避免与临时穿透清零时序冲突。
	var basic_enh : Array = attacker.unit_stats.basic_enhancements if attacker.unit_stats else []
	for enh_id in basic_enh:
		var edata := TalentManager.get_talent_data(str(enh_id))
		if edata == null: continue
		var eep : Dictionary = edata.effect_params if edata.effect_params is Dictionary else {}
		var emult : float = float(eep.get("damage_mult", 1.0))
		if emult > 1.0:
			damage = int(damage * emult)

	if active_skill_data:
		var ep : Dictionary = active_skill_data.effect_params
		if bool(ep.get("ignore_defense", false)):
			damage = _calculate_damage_ignore_defense(attacker, defender, false)

	# ★ v6.72h-P0：提前取身份爆发词条，供穿甲重算与后续爆发附加共用（一次查询、两处消费）。
	var burst_trait : Dictionary = {}
	attacker.set_meta("burst_reset_pending", false)
	if is_soul_fire_burst:
		burst_trait = SoulFireIdentity.get_burst_trait(
			attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
		# ★ v6.72h-P0：斧手爆发击杀再动——必须在击杀结算前预置。
		#   此前写在 _apply_burst_trait_effects 内（defeated 分支之后），击杀时永远赶不上 _on_kill。
		if bool(burst_trait.get("reset_action_on_kill", false)):
			var once_ok : bool = not bool(burst_trait.get("per_battle_once", false)) \
					or not attacker.get_meta("burst_reset_used", false)
			attacker.set_meta("burst_reset_pending", once_ok)

	# ★ v6.72h-P0：弓手爆发穿甲（身份 ignore_reduction）——按配置比例无视目标减伤重算主伤害。
	#   is_soul_fire_burst 为爆发态；已走完全无视的技能不重复处理。
	if is_soul_fire_burst and not burst_trait.is_empty():
		var ignore_ratio : float = float(burst_trait.get("ignore_reduction", 0.0))
		if ignore_ratio > 0.0 and is_instance_valid(defender):
			var was_magic : bool = _is_magic_attack(attacker.unit_stats)
			var eff_reduction : float = clampf(_calc_reduction(defender, was_magic) * (1.0 - ignore_ratio), 0.0, 1.0)
			var atk_raw : float = attacker.unit_stats.attack * QUALITY_MULT.get(attacker.unit_stats.weapon_quality, 1.0)
			damage = maxi(1, int(atk_raw * (1.0 - eff_reduction)))
			SignalBus.request_hint_override.emit("穿甲 · 无视 %d%% 减伤" % int(ignore_ratio * 100.0), 0.9)

	attacker.temp_physical_penetration = 0.0
	attacker.temp_magic_penetration = 0.0

	if active_skill_data:
		var ep2 : Dictionary = active_skill_data.effect_params
		var skill_mult : float = float(ep2.get("damage_mult", 1.0))
		# ★ v6.64：法师燃烧态身份增益——技能伤害 +20%
		if SoulFireManager.get_state() == SoulFireManager.State.BURNING:
			var bt : Dictionary = SoulFireIdentity.get_burn_trait(attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
			skill_mult *= (1.0 + float(bt.get("damage_bonus", 0.0)))
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

	if is_soul_fire_burst:
		var bc : Dictionary = SoulFireIdentity.get_burst_config()
		var per_soul : float = float(bc.get("extra_damage_per_soulfire", 0.15))
		var flat_soul : int = int(bc.get("flat_damage_per_soulfire", 3))
		# 爆发倍率：额外伤害按消耗魂火数缩放
		var extra_dmg = int(attacker.unit_stats.attack * per_soul * burst_cost) + flat_soul * burst_cost
		# 单位特有爆发附加：damage_multiplier（如斧手 200% 斩击）；词条已在上方提前取好
		var trait_mult : float = float(burst_trait.get("damage_multiplier", 1.0))
		damage = int((damage + extra_dmg) * maxf(trait_mult, 1.0))

		# 强制暴击（爆发倍率的一部分）
		if bool(bc.get("force_crit", true)):
			force_crit = true

		# 清空魂火
		SoulFireManager.spend(burst_cost)

	# ★ v6.68：夹击——目标四周≥2 名攻击方阵营单位时主伤害加成；
	#   仅修正本次主伤害，不施加异常，也不影响溅射/AOE（位置后果口径）。
	var flank_bonus : float = PositionManager.flanking_bonus(attacker, defender)
	if flank_bonus > 0.0:
		damage = int(float(damage) * (1.0 + flank_bonus))
		SignalBus.request_hint_override.emit(PositionManager.flanking_hint(), 0.9)

	# ★ v6.2 余烬：魂火恢复后重新装填「下一次必暴」
	if attacker.unit_stats.team_id == 0 and not SoulFireManager.is_exhausted():
		attacker.ember_crit_consumed = false

	var is_crit := false
	# ★ v6.62z：删除通用枯竭暴伤——低魂火/归零不提供暴伤增益。
	#   余烬「魂火耗尽下击必暴」在下方独立分支保留（流派机制）。
	var crit_mult : float = CRIT_DAMAGE_MULT
	crit_mult += attacker.get_total_affix_value_float("crit_damage")
	crit_mult += attacker.static_crit_damage_bonus

	var crit_talent_triggered : bool = false
	if force_crit:
		# v5.1：魂火爆发也走统一暴伤通道（烈焰 tier2 质变 crit_damage 写入 buff_crit_damage_bonus）
		# 之前只有普通/遗物/天赋暴击读该字段，爆发时烈焰 4 件套暴伤不生效
		crit_mult += attacker.buff_crit_damage_bonus
		is_crit = true
	elif TalentManager.is_talent_ready(attacker, "crit"):
		var lv_crit = _get_effective_talent_level(attacker, "crit")
		var cdata = TalentManager.get_talent_data("crit")
		var base_mult : float = 1.5
		if cdata:
			base_mult = float(cdata.effect_params.get("damage_multiplier", 1.5))
		crit_mult = base_mult + (lv_crit - 1) * 0.25 + attacker.buff_crit_damage_bonus
		crit_mult += attacker.get_total_affix_value_float("crit_damage")
		crit_mult += attacker.static_crit_damage_bonus
		is_crit = true
		crit_talent_triggered = true
		TalentManager.reset_talent(attacker, "crit")
	elif attacker.relic_first_attack_crit_remaining > 0:
		crit_mult += attacker.buff_crit_damage_bonus
		is_crit = true
		attacker.relic_first_attack_crit_remaining -= 1
		if attacker.relic_first_attack_crit_remaining <= 0:
			attacker.relic_first_attack_crit_available = false
	elif attacker.unit_stats.team_id == 0 and SoulFireManager.is_exhausted() \
			and not attacker.ember_crit_consumed \
			and BuildManager.get_effective_school_level(attacker, "余烬") > 0:
		# ★ v6.2 余烬：魂火耗尽后下一次攻击必暴（含共鸣有效 Lv）
		var ember_lv := BuildManager.get_effective_school_level(attacker, "余烬")
		crit_mult += BuildManager.get_ember_crit_bonus(ember_lv)
		is_crit = true
		attacker.ember_crit_consumed = true
		SignalBus.request_hint_override.emit("余烬 · 魂火耗尽，本次必暴", 1.0)
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
	await _wait_dialogue()

	# ★ v5.0：主伤害命中但未击杀 → on_hit(1)
	#   击杀由下方 defeated 分支的 _on_kill(1) 统一处理（互斥）
	if attacker.unit_stats.team_id == 0 and not defeated:
		SoulFireManager.on_hit(1)

	# 被动火焰伤害（flame_damage 词条）——被动效果，不计入 on_hit
	var flame_bonus : int = 0
	for slot in attacker.armor_slots:
		if slot: flame_bonus += slot.get_affix_value("flame_damage")
	if flame_bonus > 0 and defender.hit_points > 0:
		var extra_flame_dead : bool = defender.apply_damage(flame_bonus)
		SignalBus.request_damage_popup.emit(defender.global_position, flame_bonus, false, false, false)
		if extra_flame_dead: defeated = true

	# BURNING 状态被动溅射——被动效果，不计入 on_hit
	var splash_sf : float = SoulFireManager.get_splash_percent()
	if splash_sf > 0.0 and attacker.unit_stats.team_id == 0 and defender.hit_points > 0:
		await _apply_burning_splash(attacker, defender, damage, splash_sf)

	# ★ v6.72h-P0：燃烧态直线贯穿（弓手 pierce_targets / 枪兵 second_target_multiplier）
	if is_soul_fire_burst == false and SoulFireManager.get_state() == SoulFireManager.State.BURNING \
			and attacker.unit_stats.team_id == 0 and is_instance_valid(defender):
		await _apply_burning_pierce(attacker, defender, damage)

	# ★ v6.72h-P0：龙裔燃烧态锥形龙息（breath_multiplier）——对目标相邻敌人追加伤害
	if is_soul_fire_burst == false and SoulFireManager.get_state() == SoulFireManager.State.BURNING \
			and attacker.unit_stats.team_id == 0 and is_instance_valid(defender) and defender.hit_points > 0:
		var bt_breath : Dictionary = SoulFireIdentity.get_burn_trait(
			attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
		var breath_mult : float = float(bt_breath.get("breath_multiplier", 0.0))
		if breath_mult > 0.0:
			await _apply_aoe(attacker, defender, damage, breath_mult, false)
			SignalBus.request_hint_override.emit("龙息 · 锥形 %d%% 追加" % int(breath_mult * 100.0), 0.8)

	await get_tree().create_timer(POST_DAMAGE_DELAY, true, false, true).timeout
	await _wait_dialogue()

	if defeated:
		if _try_boss_revive(defender, attacker):
			# ★ v5.0：boss 变形复活 → 算命中不算击杀
			attacker.set_meta("burst_reset_pending", false)
			if attacker.unit_stats.team_id == 0:
				SoulFireManager.on_hit(1)
			_settle_active_skill(attacker, active_skill_id, active_skill_data)
			_finish_attack(attacker, defender)
			Globals.is_performing_action = false
			return true

		# ★ v5.0：真击杀，_on_kill 内部统一 on_kill(1)
		var cleave_triggered: bool = await _on_kill(attacker, defender)
		await _play_death_animation(defender)
		UnitManager.unregister_unit(defender)
		defender.queue_free()
		_settle_active_skill(attacker, active_skill_id, active_skill_data)
		if cleave_triggered:
			_show_menu_after_action(attacker)
			Globals.is_performing_action = false
			return true
		_finish_attack(attacker, defender)
		Globals.is_performing_action = false
		return true

	if not _is_alive(attacker) or not _is_alive(defender):
		_settle_active_skill(attacker, active_skill_id, active_skill_data)
		Globals.is_performing_action = false
		return true

	if active_skill_data:
		if splash_percent > 0.0: await _apply_splash(attacker, defender, damage, splash_percent, is_crit)
		if aoe_percent > 0.0: await _apply_aoe(attacker, defender, damage, aoe_percent, is_crit)
		# ★ v6.64：爆发=true 时叠加单位/转职特有的爆发附加（横扫 / AOE灼烧 / 团队治疗 / 嘲讽）
		if is_soul_fire_burst and not burst_trait.is_empty():
			await _apply_burst_trait_effects(attacker, defender, damage, is_crit, burst_trait)
		if taunt_rounds > 0:
			attacker.taunt_rounds = taunt_rounds
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var c = attacker.grid_cell + d
				var e = UnitManager.get_unit_at_cell(c)
				if e and e.unit_stats.team_id != attacker.unit_stats.team_id and e.hit_points > 0:
					e.taunt_by = attacker
					e.taunt_rounds_left = taunt_rounds
		_settle_active_skill(attacker, active_skill_id, active_skill_data)

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
		await _wait_dialogue()
		if not _is_alive(attacker) or not _is_alive(defender):
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
				# ★ v5.0：boss 变形复活 → 算命中
				if attacker.unit_stats.team_id == 0:
					SoulFireManager.on_hit(1)
				_finish_attack(attacker, defender)
				Globals.is_performing_action = false
				return true
			var cleave_triggered: bool = await _on_kill(attacker, defender)
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
		else:
			# ★ v5.0：额外攻击命中但未击杀
			if attacker.unit_stats.team_id == 0:
				SoulFireManager.on_hit(1)

	if not _is_alive(attacker) or not _is_alive(defender):
		Globals.is_performing_action = false
		return true

	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "spellbook":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]
			var extra_damage = int(damage * mult)
			TalentManager.reset_talent(attacker, "spell_chain")
			await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
			await _wait_dialogue()
			if not _is_alive(attacker) or not _is_alive(defender):
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
					# ★ v5.0：boss 变形复活 → 算命中
					if attacker.unit_stats.team_id == 0:
						SoulFireManager.on_hit(1)
					_finish_attack(attacker, defender)
					Globals.is_performing_action = false
					return true
				var cleave_triggered: bool = await _on_kill(attacker, defender)
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
			else:
				# ★ v5.0：法术连击命中但未击杀
				if attacker.unit_stats.team_id == 0:
					SoulFireManager.on_hit(1)

	if not _is_alive(attacker) or not _is_alive(defender):
		Globals.is_performing_action = false
		return true

	if _is_alive(attacker) and _is_alive(defender) and _can_follow_up(attacker, defender):
		var follow_dmg : int = int(calculate_damage(attacker, defender) * FOLLOW_UP_DAMAGE_MULT)
		await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
		await _wait_dialogue()
		if _is_alive(attacker) and _is_alive(defender):
			await _play_lunge_attack(attacker, defender)
			await get_tree().create_timer(PRE_DAMAGE_DELAY, true, false, true).timeout
			if not is_instance_valid(defender):
				Globals.is_performing_action = false
				return true
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
				else:
					# ★ v5.0：boss 变形复活 → 算命中
					if attacker.unit_stats.team_id == 0:
						SoulFireManager.on_hit(1)
			else:
				# ★ v5.0：追击命中但未击杀
				if attacker.unit_stats.team_id == 0:
					SoulFireManager.on_hit(1)

	# ★ 反击 / 收尾前确认双方对象仍有效（追击击杀会 queue_free defender，
	#   跨 await 后成为 freed 对象，传给类型化 Unit 参数会在调用处直接报错）
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		Globals.is_performing_action = false
		return true
	if _can_counter_attack(attacker, defender):
		await _execute_counter(attacker, defender)
	if not _is_alive(attacker) or not _is_alive(defender):
		Globals.is_performing_action = false
		return true

	var free_action : bool = _consume_first_spell_free(attacker)
	# 如果是魂火爆发，绝对不允许“免费行动”（比如某些法术的被动），强制结束该单位回合
	if is_soul_fire_burst:
		attacker.has_acted = true
		attacker.has_moved = true
		attacker.can_act_this_turn = false

	_finish_attack(attacker, defender, free_action)
	Globals.is_performing_action = false
	return true


func _execute_heal(attacker: Unit, defender: Unit, forced_skill_id: String = "") -> bool:
	if defender.unit_stats.team_id != attacker.unit_stats.team_id:
		Globals.is_performing_action = false
		return false

	if defender.hit_points >= defender.unit_stats.max_hp:
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("目标未受伤", 1.0)
		Globals.is_performing_action = false
		return false

	# ★ v6.62y：引爆 epic+ 禁疗——目标在禁疗回合内无法接受主动治疗（被动吸血/再生不受影响）。
	if defender.no_heal_rounds > 0:
		SoundManager.play_cancel_sound()
		SignalBus.request_hint_override.emit("目标被禁疗", 1.0)
		Globals.is_performing_action = false
		return false

	var total_heal : int = get_expected_heal_amount(attacker, defender)
	# ★ v6.64：牧师燃烧态身份增益——治疗量 +30%
	if SoulFireManager.get_state() == SoulFireManager.State.BURNING:
		var bt : Dictionary = SoulFireIdentity.get_burn_trait(attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
		total_heal = int(total_heal * (1.0 + float(bt.get("heal_bonus", 0.0))))
		# 治疗时给目标回魂火（牧师魂火引擎）
		var sfo : int = int(bt.get("soulfire_on_heal", 0))
		if sfo > 0:
			SoulFireManager.add(sfo)

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
			var cost : int = _get_active_skill_cost(skill_data)
			# ★ v6.72：治疗技能付费成功后就进冷却（不再只在 mass_heal_percent>0 分支写），
			#   否则未来新增单体主动治疗技能时冷却永远不生效。
			if mass_pct <= 0.0 and SoulFireManager.can_spend(cost):
				TalentManager.consume_active_skill(attacker, forced_skill_id)
				SoulFireManager.spend(cost)
			if mass_pct > 0.0:
				if SoulFireManager.can_spend(cost):
					TalentManager.consume_active_skill(attacker, forced_skill_id)
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
					SoulFireManager.spend(cost)
					SignalBus.request_hint_override.emit(
						"%s 消耗 %d 魂火" % [skill_data.display_name, cost], 1.2)
				else:
					SignalBus.request_hint_override.emit(
						"魂火不足（需 %d），%s 群疗未发动" % [cost, skill_data.display_name], 1.2)

	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout

	if TalentManager.is_talent_ready(attacker, "spell_chain"):
		if attacker.get_weapon_type() == "staff":
			var level = _get_effective_talent_level(attacker, "spell_chain")
			var mult = SPELL_CHAIN_MULT[level - 1]
			TalentManager.reset_talent(attacker, "spell_chain")
			await get_tree().create_timer(EXTRA_HIT_DELAY, true, false, true).timeout
			if not _is_alive(attacker) or not is_instance_valid(defender):
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
	# ★ 在 unit 被 free 之前先捕获 team_id（值拷贝），避免 tween 延迟回调时访问失效对象
	var team_id : int = unit.unit_stats.team_id
	var snd_tween = unit.create_tween()
	snd_tween.set_ignore_time_scale(true)
	snd_tween.tween_callback(func(): SoundManager.play_death_sound(team_id)).set_delay(0.05)
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
	# ★ v6.57：判胜提到早退之前——即使攻击者已失效（如连锁反击致死），
	#   也要排队一次胜利判定。v6.17 的判定原在早退后，攻击者失效时会漏判。
	#   （v6.57 起 Unit.apply_damage 也会在 HP 归零时兜底判胜，此处是双保险）
	if TurnManager and TurnManager.is_battle_ready():
		TurnManager.call_deferred("check_victory")
	if not is_instance_valid(attacker): return false

	# ★ v6.59：阵型系统已移除（见 FormationManager），不再重算

	if is_instance_valid(_defender) and _defender.unit_stats.team_id == 1:
		ItemBattlefieldManager.try_spawn_orb(_defender.grid_cell)

	if is_instance_valid(_defender) and _defender.unit_stats.is_boss:
		var hook_id : String = str(_defender.unit_stats.boss_dialogue_hooks.get("on_death", ""))
		if hook_id != "" and StoryManager.play_dialogue_by_id(hook_id):
			await _await_dialogue_with_timeout()

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
	# ★ v6.72h-P0：斧手爆发击杀再动（reset_action_on_kill/per_battle_once）
	if attacker.get_meta("burst_reset_pending", false):
		attacker.set_meta("burst_reset_pending", false)
		attacker.set_meta("burst_reset_used", true)
		attacker.has_attacked = false
		attacker.has_acted = false
		attacker.movement_after_attack = false
		SignalBus.request_hint_override.emit("斩杀再动 · %s 可再行动" % attacker.unit_stats.unit_name, 1.0)

	if attacker.relic_kill_grants_extra_move > 0:
		attacker.remaining_move += attacker.relic_kill_grants_extra_move
		attacker.has_moved = false

	# ★ v6.35：光环已并入遗物（relic_data.json 的 aura_* + effects），独立光环击杀效果已移除。

	var bonus_sf : int = 0
	for slot in attacker.armor_slots:
		if slot: bonus_sf += slot.get_affix_value("soul_fire_gain")
	if bonus_sf > 0: SoulFireManager.add(bonus_sf)

	# v5.1：献祭套装吸血统一走 damage_lifesteal（见 _apply_damage_with_effects），
	# 旧的 kill_heal 分支已移除，避免命名分裂与重复回血。

	var cross_bonuses : Array = SetBonusManager.get_active_cross_bonuses()
	for entry in cross_bonuses:
		var cb : Dictionary = entry.get("data", {})
		if cb.get("effect", "") == "kill_soul_fire":
			var val : int = int(cb.get("value", 0))
			if val > 0: SoulFireManager.add(val)

	# ★ v6.33：击杀走 on_kill（配置 kill=3 / 多杀+2 / 触底反弹+1），
	#   而非 on_hit(1)——后者只是命中收益，旧实现让击杀魂火配置完全失效。
	#   其余 8 处 on_hit(1) 均为"命中未击杀"分支，保持不变。
	if attacker.unit_stats.team_id == 0:
		# ★ v6.58：击杀得经验——按被击杀敌人的强度(exp，来自 unit_data.json)给击杀者。
		#   升级会在 grant_exp_and_auto_level 内发信号，战场播升级仪式感。
		var kill_exp : int = _defender.unit_stats.kill_exp if is_instance_valid(_defender) and _defender.unit_stats != null else 0
		if kill_exp > 0:
			BuildManager.grant_kill_exp(attacker.unit_stats, kill_exp)
		# ★ v6.2 轮回：击杀额外回魂火（与基础击杀收益分开结算，玩家能看到两段收益）
		var cycle_lv := BuildManager.get_effective_school_level(attacker, "轮回")
		if cycle_lv > 0:
			var cycle_gain : int = BuildManager.get_cycle_soul_gain(cycle_lv)
			SoulFireManager.add(cycle_gain)
			SignalBus.request_hint_override.emit("轮回 · 击杀回 %d 魂火" % cycle_gain, 0.9)
			# ★ v6.66：轮回团队价值显性——Lv≥1 击杀即治疗最低血队友（4%HP），Lv2 质变 8%。
			var ally := _lowest_hp_ally(attacker)
			if ally != null:
				var heal_ratio : float = 0.08 if BuildManager.has_breakthrough(attacker, "轮回", "cycle_heal") else 0.04
				var heal := maxi(1, int(ally.unit_stats.max_hp * heal_ratio))
				ally.hit_points = mini(ally.hit_points + heal, ally.unit_stats.max_hp)
				SignalBus.request_damage_popup.emit(ally.global_position, heal, false, false, true)
		# ★ v6.70 方案A：钩子遗物「轮回余烬」——轮回击杀回魂火时给最近存活敌人挂灼烧，
		#   把轮回(施加端)与余烬(消费端)在同一时间轴上咬合，形成乘法式协同。
		if attacker.relic_cycle_kill_burn > 0:
			var near: Unit = _nearest_enemy(attacker)
			if near != null:
				AbnormalManager.apply_burn_stacks(attacker, near, attacker.relic_cycle_kill_burn)
				SignalBus.request_hint_override.emit("轮回余烬 · %s 灼烧" % near.unit_stats.unit_name, 0.8)
		SoulFireManager.on_kill(1)
		# ★ v6.59：F3 轮回链阵型效果已移除（轮回自身击杀回魂火仍保留）
	return cleave_triggered


# ★ v6.71：Build 觉醒技已删除。流派全场质变由魂火爆发（burst_requested）
#   + 单位身份 burst_trait（SoulFireIdentity）接管；防具 build 回归被动机制层。


## 找同队中"当前 HP 比例最低且存活"的队友（用于轮回 Lv2 治疗质变）
func _lowest_hp_ally(unit: Unit) -> Unit:
	if not is_instance_valid(unit):
		return null
	var best: Unit = null
	var best_ratio: float = 2.0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u.hit_points <= 0:
			continue
		if u.unit_stats.team_id != unit.unit_stats.team_id:
			continue
		var ratio: float = float(u.hit_points) / float(maxi(1, u.unit_stats.max_hp))
		if ratio < best_ratio:
			best_ratio = ratio
			best = u
	return best


## ★ v6.70 方案A：找离 origin 最近的存活敌对单位（用于"轮回击杀溅灼烧"钩子）。
func _nearest_enemy(origin: Unit) -> Unit:
	if not is_instance_valid(origin):
		return null
	var best: Unit = null
	var best_dist: int = 2147483647
	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u.hit_points <= 0:
			continue
		if u.unit_stats.team_id == origin.unit_stats.team_id:
			continue
		var d: int = absi(u.grid_cell.x - origin.grid_cell.x) + absi(u.grid_cell.y - origin.grid_cell.y)
		if d < best_dist:
			best_dist = d
			best = u
	return best


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


func _apply_burning_splash(attacker : Unit, center : Unit, base_damage : int, percent : float):
	# ★ v5.0：BURNING 被动溅射不奖励魂火（被动效果，避免滚雪球）
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var t : Unit = UnitManager.get_unit_at_cell(center.grid_cell + d)
		if not t or t.hit_points <= 0: continue
		if t.unit_stats.team_id == attacker.unit_stats.team_id: continue
		var splash_dmg : int = maxi(1, int(base_damage * percent))
		var dead : bool = _apply_damage_with_effects(t, splash_dmg, attacker, false, false)
		await _wait_dialogue()
		if dead:
			if _try_boss_revive(t, attacker): continue
			_on_kill(attacker, t)
			await _play_death_animation(t)
			UnitManager.unregister_unit(t)
			t.queue_free()


## ★ v6.72h-P0：燃烧态直线贯穿——弓手 pierce_targets / 枪兵 second_target_multiplier。
##   沿攻击者→目标的主轴方向，对目标身后第 1..N 格的第一个敌人追加伤害。
func _apply_burning_pierce(attacker: Unit, target: Unit, base_damage: int) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return
	var bt : Dictionary = SoulFireIdentity.get_burn_trait(attacker.unit_stats.unit_name, attacker.unit_stats.advanced_class)
	var pierce_n : int = maxi(0, int(bt.get("pierce_targets", 0)))
	var second_mult : float = float(bt.get("second_target_multiplier", 0.0))
	if pierce_n <= 0 and second_mult <= 0.0:
		return
	var diff : Vector2i = target.grid_cell - attacker.grid_cell
	var dir : Vector2i = Vector2i.ZERO
	if absi(diff.x) >= absi(diff.y):
		dir = Vector2i(1 if diff.x >= 0 else -1, 0)
	else:
		dir = Vector2i(0, 1 if diff.y >= 0 else -1)
	if dir == Vector2i.ZERO:
		return
	var hit_count : int = maxi(pierce_n, 1 if second_mult > 0.0 else 0)
	var dmg : int = maxi(1, int(base_damage * (second_mult if second_mult > 0.0 else 0.5)))
	var found : int = 0
	for step in range(1, hit_count + 2):
		var cell : Vector2i = target.grid_cell + dir * step
		var t : Unit = UnitManager.get_unit_at_cell(cell)
		if t == null or not is_instance_valid(t) or t.hit_points <= 0:
			continue
		if t.unit_stats.team_id == attacker.unit_stats.team_id:
			continue
		var dead : bool = _apply_damage_with_effects(t, dmg, attacker, false, false)
		await _wait_dialogue()
		SignalBus.request_hint_override.emit("贯穿 · %s 受 %d 伤害" % [t.unit_stats.unit_name, dmg], 0.8)
		if dead:
			_on_kill(attacker, t)
			await _play_death_animation(t)
			UnitManager.unregister_unit(t)
			t.queue_free()
		found += 1
		if found >= hit_count:
			break


func _apply_splash(attacker: Unit, defender: Unit, base_damage: int, percent: float, is_crit: bool = false) -> void:
	var behind = defender.grid_cell + (defender.grid_cell - attacker.grid_cell)
	var splash_target = UnitManager.get_unit_at_cell(behind)
	if not splash_target or splash_target.hit_points <= 0: return
	if splash_target.unit_stats.team_id == attacker.unit_stats.team_id: return
	var splash_dmg = int(base_damage * percent)
	var dead = _apply_damage_with_effects(splash_target, splash_dmg, attacker, is_crit, false)
	await _wait_dialogue()
	# ★ v5.0：贯穿溅射命中但未击杀 → on_hit
	if attacker.unit_stats.team_id == 0 and not dead:
		SoulFireManager.on_hit(1)
	if dead:
		if _try_boss_revive(splash_target, attacker):
			if attacker.unit_stats.team_id == 0:
				SoulFireManager.on_hit(1)
			return
		_on_kill(attacker, splash_target)
		await _play_death_animation(splash_target)
		UnitManager.unregister_unit(splash_target)
		splash_target.queue_free()


## ★ v6.64：单位/转职特有的爆发附加效果。
##   只处理有现成接口的字段；击退/眩晕/护盾/再行动/破甲等字段在数据里保留为设计口径，
##   待对应系统接入后再消费，此处安全忽略，不影响爆发主流程。
func _apply_burst_trait_effects(attacker: Unit, defender: Unit, base_damage: int, is_crit: bool, cfg: Dictionary) -> void:
	if not is_instance_valid(attacker) or cfg.is_empty():
		return
	# ★ v6.72h-P0：身份表此前配了但无消费的字段，逐项补实现。
	# 0) 净化（牧师爆发 cleanse）：清自身异常层数 + 禁疗/减速负面，给全队也清 1 层。
	var cleanse : int = int(cfg.get("cleanse", 0))
	if cleanse > 0:
		for u in UnitManager.unit_list:
			if not is_instance_valid(u) or u.unit_stats.team_id != attacker.unit_stats.team_id:
				continue
			for _i in range(cleanse):
				# 优先清灼烧/冻寒/灰烬（异常层数），再清禁疗回合
				var types : Array = AbnormalManager.ALL_TYPES
				var cleared : bool = false
				for t in types:
					if AbnormalManager.get_stacks(u, str(t)) > 0:
						AbnormalManager.clear_stacks(u, str(t))
						cleared = true
						break
				if not cleared and u.no_heal_rounds > 0:
					u.no_heal_rounds -= 1
					cleared = true
				if not cleared and u.abnormal_slow_rounds > 0:
					u.abnormal_slow_rounds = maxi(0, u.abnormal_slow_rounds - 1)
					break
		SignalBus.request_hint_override.emit("净化 · 全队清除 %d 层负面" % cleanse, 1.0)
	# 1) 相邻横扫（剑士：对目标相邻敌人追加伤害）
	var adj : float = float(cfg.get("adjacent_multiplier", 0.0))
	if adj > 0.0 and is_instance_valid(defender):
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var t : Unit = UnitManager.get_unit_at_cell(defender.grid_cell + d)
			if t == null or t.hit_points <= 0: continue
			if t.unit_stats.team_id == attacker.unit_stats.team_id: continue
			var dmg : int = maxi(1, int(base_damage * adj))
			var dead : bool = _apply_damage_with_effects(t, dmg, attacker, is_crit, false)
			await _wait_dialogue()
			if dead:
				_on_kill(attacker, t)
				await _play_death_animation(t)
				UnitManager.unregister_unit(t)
				t.queue_free()
	# 2) 范围爆炸 + 灼烧层数（法师/龙裔）
	var aoe : float = float(cfg.get("aoe_multiplier", 0.0))
	if aoe > 0.0 and is_instance_valid(defender):
		await _apply_aoe(attacker, defender, base_damage, aoe, is_crit)
	var burn_stacks : int = int(cfg.get("burn_stacks", 0))
	if burn_stacks > 0 and is_instance_valid(defender) and defender.hit_points > 0:
		AbnormalManager.apply_burn_stacks(attacker, defender, burn_stacks)
	# 3) 团队治疗 + 回魂火（牧师爆发）
	var team_heal : float = float(cfg.get("team_heal_ratio", 0.0))
	if team_heal > 0.0:
		for u in UnitManager.unit_list:
			if not is_instance_valid(u) or u.hit_points <= 0: continue
			if u.unit_stats.team_id != attacker.unit_stats.team_id: continue
			var heal : int = int(u.unit_stats.max_hp * team_heal)
			var old_hp : int = u.hit_points
			u.hit_points = mini(u.hit_points + heal, u.unit_stats.max_hp)
			var actual : int = u.hit_points - old_hp
			if actual > 0:
				u.update_hp_label()
				SignalBus.request_damage_popup.emit(u.global_position, actual, false, false, true)
	var sf_gain : int = int(cfg.get("soulfire_gain", 0))
	if sf_gain > 0:
		SoulFireManager.add(sf_gain)
	# 4) 嘲讽（重甲爆发站场）
	var taunt : int = int(cfg.get("taunt_rounds", 0))
	if taunt > 0:
		attacker.taunt_rounds = taunt
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var e : Unit = UnitManager.get_unit_at_cell(attacker.grid_cell + d)
			if e != null and e.hit_points > 0 and e.unit_stats.team_id != attacker.unit_stats.team_id:
				e.taunt_by = attacker
				e.taunt_rounds_left = taunt
	# 5) 减伤强化（重甲燃烧/爆发近似"护盾"，用现有 buff_damage_reduction）
	var dr : float = float(cfg.get("shield_damage_reduction", 0.0))
	if dr > 0.0:
		var cap : float = float(SoulFireIdentity.get_burst_config().get("shield_reduction_cap", 0.75))
		attacker.buff_damage_reduction = minf(attacker.buff_damage_reduction + dr, cap)
	# 6) ★ v6.68：击退 / 撞墙 / 连撞 / 危险地形——从攻击者指向目标的主轴方向推开。
	#    GridPushManager 只产出伤害事件；这里统一结算，全部 trigger_abnormal=false。
	var kb : int = int(cfg.get("knockback", 0))
	if kb > 0 and is_instance_valid(defender) and defender.hit_points > 0:
		var diff : Vector2i = defender.grid_cell - attacker.grid_cell
		var dir : Vector2i = Vector2i.ZERO
		if absi(diff.x) >= absi(diff.y):
			dir = Vector2i(1 if diff.x >= 0 else -1, 0)
		else:
			dir = Vector2i(0, 1 if diff.y >= 0 else -1)
		if dir != Vector2i.ZERO:
			var kb_res: Dictionary = await GridPushManager.push(attacker, defender, kb, dir)
			var events: Array = kb_res.get("events", [])
			var hints: Array[String] = []
			# ★ v6.70e：位置后果 P0——被推动(位移≥1格)即打断敌人蓄力意图。
			#   主目标不一定出现在 events（只有撞墙/撞单位/危险地形才有事件），
			#   所以用 kb_res.moved 单独判定主目标，事件里再判连撞受害者。
			if int(kb_res.get("moved", 0)) > 0:
				if EnemyIntentManager.interrupt_on_push(defender, attacker):
					hints.append("⚡ %s 蓄力被打断" % defender.unit_stats.unit_name)
			for ev_v in events:
				if not (ev_v is Dictionary):
					continue
				var ev: Dictionary = ev_v as Dictionary
				var victim_v: Variant = ev.get("unit", null)
				if not (victim_v is Unit):
					continue
				var victim: Unit = victim_v as Unit
				if not is_instance_valid(victim) or victim.hit_points <= 0:
					continue
				var source: Unit = attacker
				var source_v: Variant = ev.get("source", null)
				if source_v is Unit and is_instance_valid(source_v as Unit):
					source = source_v as Unit
				var dmg: int = int(ev.get("damage", 0))
				if dmg > 0:
					match str(ev.get("kind", "")):
						"wall":
							hints.append("撞墙！额外 %d 伤害" % dmg)
						"unit_collision":
							hints.append("连撞！%s 受 %d 伤害" % [victim.unit_stats.unit_name, dmg])
						"danger":
							hints.append("推入危险地形！额外 %d 伤害" % dmg)
					await apply_position_damage(victim, dmg, source)
				var st: int = int(ev.get("stun", 0))
				if st > 0 and is_instance_valid(victim) and victim.hit_points > 0:
					victim.stun_rounds = maxi(victim.stun_rounds, st)
				# ★ v6.70e：连撞受害者同样会打断蓄力
				if EnemyIntentManager.interrupt_on_push(victim, source):
					hints.append("⚡ %s 蓄力被打断" % victim.unit_stats.unit_name)
			if hints.size() > 0:
				SignalBus.request_hint_override.emit(hints[hints.size() - 1], 0.9)
	# 7) ★ v6.72h-P0：飞马爆发眩晕（stun_rounds）
	var bstun : int = int(cfg.get("stun_rounds", 0))
	if bstun > 0 and is_instance_valid(defender) and defender.hit_points > 0:
		defender.stun_rounds = maxi(defender.stun_rounds, bstun)
		SignalBus.request_hint_override.emit("眩晕 · %s 跳过 %d 回合" % [defender.unit_stats.unit_name, bstun], 0.9)
	# 8) ★ v6.72h-P0：弓手爆发破甲（armor_break）——给目标挂破甲 debuff
	if bool(cfg.get("armor_break", false)) and is_instance_valid(defender) and defender.hit_points > 0:
		var shred_cap : float = 0.5
		defender.buff_defense_shred = minf(defender.buff_defense_shred + 0.3, shred_cap)
		SignalBus.request_hint_override.emit("破甲 · %s 减防 30%%" % defender.unit_stats.unit_name, 0.9)
	# 9) ★ v6.72h-P0：灰烬剑圣爆发引爆灼烧（detonate_burn）——消费目标灼烧层造成追加伤害
	if bool(cfg.get("detonate_burn", false)) and is_instance_valid(defender) and defender.hit_points > 0:
		var burn_n : int = AbnormalManager.get_stacks(defender, AbnormalManager.TYPE_BURN)
		if burn_n > 0:
			var det_dmg : int = maxi(1, int(base_damage * 0.25 * burn_n))
			AbnormalManager.clear_stacks(defender, AbnormalManager.TYPE_BURN)
			var det_dead : bool = _apply_damage_with_effects(defender, det_dmg, attacker, false, false)
			SignalBus.request_hint_override.emit("引爆 · %d 层灼烧 → %d 伤害" % [burn_n, det_dmg], 0.9)
			if det_dead:
				_on_kill(attacker, defender)
				await _play_death_animation(defender)
				UnitManager.unregister_unit(defender)
				defender.queue_free()
				return
	# 10) ★ v6.72h-P0：龙裔爆发留灰烬地块（leave_ash_tile）——目标格留下燃烧地块
	if bool(cfg.get("leave_ash_tile", false)) and is_instance_valid(defender):
		var lv : int = BuildManager.get_effective_school_level(attacker, "灰烬")
		var dmg : int = BuildManager.get_ash_tile_damage(maxi(1, lv))
		ash_tiles[defender.grid_cell] = {
			"damage": dmg, "team": attacker.unit_stats.team_id,
			"owner": attacker, "expire_clock": ash_turn_clock + 2,
		}
		while ash_tiles.size() > ASH_TILE_MAX:
			ash_tiles.erase(ash_tiles.keys()[0])
		SignalBus.request_hint_override.emit("龙息 · 留下燃烧地块（%d 伤害）" % dmg, 0.9)
	# 11) ★ v6.72h-P0：狂战士爆发多段突进（hit_count/hit_multiplier）——追加 N-1 段
	var hit_count : int = maxi(1, int(cfg.get("hit_count", 1)))
	var hit_mult : float = float(cfg.get("hit_multiplier", 1.0))
	if hit_count > 1 and hit_mult > 0.0 and is_instance_valid(defender) and defender.hit_points > 0:
		for _i in range(hit_count - 1):
			if not is_instance_valid(defender) or defender.hit_points <= 0:
				break
			var seg_dmg : int = maxi(1, int(base_damage * hit_mult))
			var seg_dead : bool = _apply_damage_with_effects(defender, seg_dmg, attacker, false, false)
			await _wait_dialogue()
			if seg_dead:
				_on_kill(attacker, defender)
				await _play_death_animation(defender)
				UnitManager.unregister_unit(defender)
				defender.queue_free()
				return
	# 12) 击杀再动已在 execute_attack 击杀结算前预置（见 burst_trait 读取处），此处不再写 meta。


func _apply_aoe(attacker: Unit, center: Unit, base_damage: int, percent: float, is_crit: bool = false) -> void:
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var target = UnitManager.get_unit_at_cell(center.grid_cell + d)
		if not target or target.hit_points <= 0: continue
		if target.unit_stats.team_id == attacker.unit_stats.team_id: continue
		var aoe_dmg = int(base_damage * percent)
		var dead = _apply_damage_with_effects(target, aoe_dmg, attacker, is_crit, false)
		await _wait_dialogue()
		# ★ v5.0：AOE 命中但未击杀 → on_hit
		if attacker.unit_stats.team_id == 0 and not dead:
			SoulFireManager.on_hit(1)
		if dead:
			if _try_boss_revive(target, attacker):
				if attacker.unit_stats.team_id == 0:
					SoulFireManager.on_hit(1)
				continue
			_on_kill(attacker, target)
			await _play_death_animation(target)
			UnitManager.unregister_unit(target)
			target.queue_free()


## ★ v6.63：trigger_abnormal 控制异常施加/消费——只有普攻/技能主伤害触发；
##   溅射 / AOE / 追击 / 反击只算附加伤害，不触发异常（体系的统一出口约束）。
func _apply_damage_with_effects(defender: Unit, damage: int, attacker: Unit, is_crit: bool = false, trigger_abnormal: bool = true) -> bool:
	if defender.unit_stats.team_id == 0 and defender.get_meta("gm_god", false):
		damage = 0

	# ★ v6.59：F2 铁壁护卫阵型效果已移除

	if TalentManager.is_talent_ready(defender, "parry"):
		var level = _get_effective_talent_level(defender, "parry")
		var reflect_mult = 0.5 + (level - 1) * 0.15
		var parry_base = calculate_damage(defender, attacker)
		var parry_damage = max(1, int(parry_base * reflect_mult))
		attacker.apply_damage(parry_damage)
		SignalBus.request_damage_popup.emit(attacker.global_position, parry_damage, false, false, false)
		TalentManager.reset_talent(defender, "parry")

	var blocked : bool = false
	if TalentManager.is_talent_ready(defender, "block"):
		blocked = true
		var level = _get_effective_talent_level(defender, "block")
		var reduction = 0.5 + (level - 1) * 0.1
		damage = int(damage * (1.0 - reduction))
		TalentManager.reset_talent(defender, "block")

	# ★ v6.2 守护：受击反弹；格挡生效的当次反弹翻倍。
	#   直接扣血，不再递归调用本函数，避免互相反弹死循环。
	if is_instance_valid(attacker) and damage > 0 \
			and defender.unit_stats.team_id != attacker.unit_stats.team_id:
		var guard_lv := BuildManager.get_effective_school_level(defender, "守护")
		if guard_lv > 0:
			var reflect_ratio : float = BuildManager.get_guard_reflect_ratio(guard_lv)
			if blocked:
				reflect_ratio *= 2.0
			var reflect_dmg : int = maxi(1, int(damage * reflect_ratio))
			attacker.apply_damage(reflect_dmg)
			SignalBus.request_damage_popup.emit(attacker.global_position, reflect_dmg, false, false, false)
			# ★ v6.34（B2）守护 Lv2 质变：反弹同时为自身回血（反弹量 50%）
			if BuildManager.has_breakthrough(defender, "守护", "guard_lifesteal"):
				var ls := maxi(1, int(reflect_dmg * 0.5))
				defender.hit_points = mini(defender.hit_points + ls, defender.unit_stats.max_hp)
				SignalBus.request_damage_popup.emit(defender.global_position, ls, false, false, true)
			# ★ v6.66：守护团队价值——受击时全队获得 1 回合减伤（守护是团队护盾）。
			var team_dr : float = 0.05 * float(guard_lv)
			for u in UnitManager.unit_list:
				if not is_instance_valid(u) or u.hit_points <= 0:
					continue
				if u.unit_stats.team_id == defender.unit_stats.team_id:
					u.guard_team_dr = maxf(u.guard_team_dr, team_dr)
					u.guard_team_dr_rounds = 2
			SignalBus.request_hint_override.emit("守护 · 全队减伤 %d%%（1 回合）" % int(team_dr * 100.0), 0.8)
			if DEBUG_DAMAGE_LOG:
				print("[守护] Lv%d 反弹 %s → %d%s" % [
					guard_lv, attacker.unit_stats.unit_name, reflect_dmg,
					"（格挡翻倍）" if blocked else ""])
			# ★ v6.59：F5 余烬引爆阵型效果已移除

	# ★ v6.72h-P0：重甲燃烧态身份反弹（burn_trait.reflect）——独立于守护流派，不递归。
	if is_instance_valid(attacker) and damage > 0 \
			and defender.unit_stats.team_id != attacker.unit_stats.team_id \
			and SoulFireManager.get_state() == SoulFireManager.State.BURNING \
			and defender.unit_stats.team_id == 0:
		var bt_reflect : Dictionary = SoulFireIdentity.get_burn_trait(
			defender.unit_stats.unit_name, defender.unit_stats.advanced_class)
		var rr : float = float(bt_reflect.get("reflect", 0.0))
		if rr > 0.0:
			var rd : int = maxi(1, int(damage * rr))
			attacker.apply_damage(rd)
			SignalBus.request_damage_popup.emit(attacker.global_position, rd, false, false, false)
			SignalBus.request_hint_override.emit("重甲 · 反伤 %d" % rd, 0.7)

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

	var old_hp : int = defender.hit_points

	var defeated = defender.apply_damage(damage)
	SignalBus.request_damage_popup.emit(defender.global_position, damage, is_crit, false, false)
	_play_hurt_effect(defender, attacker)

	# ★ v6 烈焰样板：攻击附带灼烧（按本次伤害的比例追加一次无视减伤的伤害）
	#   机制 Lv 由 BuildManager 从防具流派并入结果计算；一件即生效、同流派并入升 Lv。
	if not defeated and is_instance_valid(attacker) and damage > 0 \
		and defender.unit_stats.team_id != attacker.unit_stats.team_id:
		var flame_lv := BuildManager.get_flame_level(attacker)
		if flame_lv > 0:
			var burn : int = maxi(1, int(damage * BuildManager.get_flame_burn_ratio(flame_lv)))
			if DEBUG_DAMAGE_LOG:
				print("[烈焰] Lv%d 灼烧 %s → %d" % [
					flame_lv, defender.unit_stats.unit_name, burn])
			SignalBus.request_damage_popup.emit(defender.global_position, burn, false, false, false)
			var burn_dead := defender.apply_damage(burn)
			if burn_dead:
				if not _try_revive(defender):
					defeated = true
			# ★ v6.59：F1 燎原阵型效果已移除（烈焰自身灼烧仍保留）

	# ★ v6.62y / v6.63：异常状态——只由普攻/技能主伤害触发施加/消费；
	#   溅射 / AOE / 追击 / 反击传 trigger_abnormal=false，只结算附加伤害。
	if trigger_abnormal and not defeated and is_instance_valid(attacker) and damage > 0 \
			and defender.unit_stats.team_id != attacker.unit_stats.team_id:
		# 消费端优先：目标已有对应异常且攻击方有消费词条时引爆（DOT 击杀归引爆者）
		var consume_dmg : int = AbnormalManager.consume_on_attack(attacker, defender)
		if consume_dmg > 0 and defender.hit_points <= 0:
			defeated = true
			if not _try_revive(defender):
				return true
		# 施加端：按概率给目标挂层（放在消费之后，避免刚上的层被自己立刻引爆吃掉）
		AbnormalManager.apply_from_attack(attacker, defender)
		# 受击端：守护「寒霜护甲」按概率给攻击方上冻寒
		AbnormalManager.apply_frost_on_hit(defender, attacker)

	if BossMechanicManager and BossMechanicManager.has_method("process_damage_phase"):
		var phase_result: Dictionary = BossMechanicManager.process_damage_phase(defender, attacker, damage, old_hp)
		if phase_result.get("prevent_death", false):
			defeated = false
		elif defender.hit_points > 0:
			defeated = false

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
		# v5.1：吸血走统一出口（tier 后的值），命名统一为 damage_lifesteal
		var pct : float = SetBonusManager.get_unit_set_effect_value(attacker, "damage_lifesteal")
		if pct > 0.0:
			var heal : int = int(damage * pct)
			if heal > 0:
				var prev_hp : int = attacker.hit_points
				attacker.hit_points = mini(attacker.hit_points + heal, attacker.unit_stats.max_hp)
				var actual : int = attacker.hit_points - prev_hp
				if actual > 0:
					attacker.update_hp_label()
					SignalBus.request_damage_popup.emit(attacker.global_position, actual, false, false, true)

	return defeated


## ★ v6.68：位置后果伤害统一出口（撞墙 / 连撞 / 危险地形）。
##   不触发异常、不触发异常消费，只算附加伤害；击杀归属 source，死亡清理与主伤害同口径。
func apply_position_damage(victim: Unit, damage: int, source: Unit) -> void:
	if not is_instance_valid(victim) or victim.hit_points <= 0 or damage <= 0:
		return
	var real_source: Unit = source
	if not is_instance_valid(real_source):
		real_source = victim
	var defeated: bool = _apply_damage_with_effects(victim, damage, real_source, false, false)
	if not defeated:
		return
	if _try_boss_revive(victim, real_source):
		return
	_on_kill(real_source, victim)
	await _play_death_animation(victim)
	if not is_instance_valid(victim):
		return
	UnitManager.unregister_unit(victim)
	victim.queue_free()


# ============================================================
#  ★ v6.2 灰烬：移动留下燃烧地块
# ============================================================

func reset_ash_tiles() -> void:
	ash_tiles.clear()
	ash_turn_clock = 0


func tick_ash_tiles() -> void:
	ash_turn_clock += 1
	var expired: Array = []
	for cell in ash_tiles:
		var tile: Dictionary = ash_tiles[cell]
		if int(tile.get("expire_clock", 0)) <= ash_turn_clock:
			expired.append(cell)
	for cell in expired:
		ash_tiles.erase(cell)


func drop_ash_tile(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	var lv := BuildManager.get_effective_school_level(unit, "灰烬")
	if lv <= 0:
		return
	var origin: Vector2i = unit.previous_grid_cell
	if origin == unit.grid_cell:
		return
	var dmg: int = BuildManager.get_ash_tile_damage(lv)
	var expire : int = ash_turn_clock + 2
	# ★ v6.59：F6 灰烬火墙阵型效果已移除（灰烬自身燃烧地块仍保留）
	ash_tiles[origin] = {
		"damage": dmg,
		"team": unit.unit_stats.team_id,
		"owner": unit,
		"expire_clock": expire,
	}
	while ash_tiles.size() > ASH_TILE_MAX:
		ash_tiles.erase(ash_tiles.keys()[0])
	SignalBus.request_hint_override.emit(
		"灰烬 · 起点留下燃烧地块（%d 伤害）" % dmg, 0.9)


func trigger_ash_tile(unit: Unit) -> void:
	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return
	var cell: Vector2i = unit.grid_cell
	if not ash_tiles.has(cell):
		return
	var tile: Dictionary = ash_tiles[cell]
	if int(tile.get("team", -1)) == unit.unit_stats.team_id:
		# ★ v6.66：灰烬团队价值——友方踩自己的燃烧地块回 1 魂火（地块是团队资源）。
		if unit.unit_stats.team_id == 0:
			SoulFireManager.add(1)
			SignalBus.request_hint_override.emit("灰烬 · 队友借火回 1 魂火", 0.8)
		ash_tiles.erase(cell)
		return
	ash_tiles.erase(cell)
	var dmg: int = int(tile.get("damage", 0))
	if dmg <= 0:
		return
	var dead: bool = unit.apply_damage(dmg)
	SignalBus.request_damage_popup.emit(unit.global_position, dmg, false, false, false)
	# ★ v6.59：F6 灰烬火墙附加 DoT 已移除
	if dead:
		var owner_v: Variant = tile.get("owner", null)
		if owner_v is Unit and is_instance_valid(owner_v as Unit):
			_on_kill(owner_v as Unit, unit)
		UnitManager.unregister_unit(unit)
		unit.queue_free()


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
	# ★ v6.68：被夹击（四周≥2 名攻击方单位）时无法反击
	if PositionManager.flanking_denies_counter() and PositionManager.is_flanked(defender, attacker):
		return false
	var def_weapon_type = defender.get_weapon_type()
	if def_weapon_type == "" or def_weapon_type == "staff": return false
	# ★ v4.8：武器内联 unit_stats，无武器直接不能反击
	if defender.unit_stats.weapon_name == "": return false
	var def_min_range : int = defender.get_effective_min_attack_range()
	var def_max_range : int = defender.get_effective_attack_range()
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
		if _try_boss_revive(attacker, defender):
			# ★ v5.0：反击把 boss 打到变形复活 → 反击方算命中
			if defender.unit_stats.team_id == 0:
				SoulFireManager.on_hit(1)
			return
		_on_kill(defender, attacker)   # 内部 on_kill(1)（team 0 时）
		await _play_death_animation(attacker)
		UnitManager.unregister_unit(attacker)
		attacker.queue_free()
	else:
		# ★ v5.0：反击命中但未击杀 → 反击方算命中
		if defender.unit_stats.team_id == 0:
			SoulFireManager.on_hit(1)
		# ★ v6.70 方案A：钩子遗物「霜铁反噬」——守护反击命中后给攻击者挂冻寒，
		#   让守护(施加端)与烈焰「融雪」(消费端)在反击链路咬合。
		if defender.relic_counter_frost > 0:
			AbnormalManager._add_stack(attacker, AbnormalManager.TYPE_FROST,
				defender.relic_counter_frost, defender,
				BuildManager.get_effective_school_level(defender, "守护"), "epic", AbnormalManager.MAX_STACKS)
			SignalBus.request_hint_override.emit("霜铁反噬 · %s 冻寒" % attacker.unit_stats.unit_name, 0.8)


## 参数故意不写 Unit 类型：execute_attack 是一长串 await，
## 期间 attacker/defender 可能被连锁击杀并 queue_free。
## 若参数是类型化的 Unit，GDScript 会在调用处就对已释放对象做类型检查并报错
## （"previously freed ... not a subclass of expected class"），
## 函数体里的 is_instance_valid 根本没机会执行。改成无类型后由函数内自己判活。
func _is_alive(u) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	return u.hit_points > 0

func _wait_dialogue() -> void:
	while Globals.is_dialogue_active:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return

## v5.11：等待对话结束，带超时兜底 + 信号竞态保护（对齐 Battlefield._await_dialogue_with_timeout）。
## 覆盖三种会永久挂起、进而锁死战斗输入的场景：
##  1) play_dialogue_by_id 返回 true 但 DialogueUI 未加载 → dialogue_finished 永不发出
##  2) dialogue_finished 在 await 建立前就发出 → 永远等不到该信号
##  3) 对话被其他系统中途打断/重置 → 信号丢失
func _await_dialogue_with_timeout(timeout_sec: float = 6.0) -> void:
	if not Globals.is_dialogue_active:
		return
	# GDScript lambda 按值捕获，用单元素字典做 holder 获得引用语义（避免 CONFUSABLE_CAPTURE_REASSIGNMENT）
	var holder : Dictionary = {"finished": false}
	var on_finished := func(): holder["finished"] = true
	if not DialogueManager.dialogue_finished.is_connected(on_finished):
		DialogueManager.dialogue_finished.connect(on_finished, CONNECT_ONE_SHOT)

	var start_ms : int = Time.get_ticks_msec()
	var timeout_ms : int = int(timeout_sec * 1000.0)
	while not holder["finished"] and Globals.is_dialogue_active:
		if not is_instance_valid(self):
			break
		if Time.get_ticks_msec() - start_ms > timeout_ms:
			push_warning("[CombatManager] 击杀对话等待超时(%ds)，强制关闭以避免输入锁死" % int(timeout_sec))
			DialogueManager.reset()
			Globals.is_dialogue_active = false
			break
		await get_tree().process_frame
	if DialogueManager.dialogue_finished.is_connected(on_finished):
		DialogueManager.dialogue_finished.disconnect(on_finished)

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
	# ★ v6.72：技能释放后冷却数已变化——先清 hover info 缓存再刷新，
	#   否则鼠标停在同一单位时 _on_request_show_info 会 early-return，看不到新倒数。
	SignalBus.request_hide_info.emit()
	SignalBus.request_show_info.emit(unit)


func _face_each_other(attacker: Unit, defender: Unit):
	if not is_instance_valid(attacker) or not is_instance_valid(defender): return
	var dir = defender.grid_cell - attacker.grid_cell
	if dir.x != 0:
		attacker.set_facing_direction(Vector2(sign(dir.x), 0))
		defender.set_facing_direction(Vector2(-sign(dir.x), 0))


func get_unit_attack_stats(unit: Unit) -> Dictionary:
	var s = unit.unit_stats
	if s == null or s.weapon_name == "":
		return {"attack": 0, "magic_attack": 0, "heal_amount": 0,
			"attack_range": 0, "min_attack_range": 0, "attack_style": "standard"}

	var quality_mult : float = QUALITY_MULT.get(s.weapon_quality, 1.0)
	var stats = {
		"attack": int(s.attack * quality_mult),
		"attack_range": s.attack_range + unit.bonus_attack_range,
		"min_attack_range": s.min_attack_range,
		"attack_style": s.attack_style,
	}
	if s.magic_attack.get("ignore_defense", false):
		stats["magic_attack"] = int(s.attack * quality_mult)
	if not s.heal_effect.is_empty():
		stats["heal_amount"] = s.heal_effect.get("base_heal", 0)
	return stats


func _calc_staff_heal(attacker: Unit, defender: Unit) -> int:
	var s = attacker.unit_stats
	if s.weapon_name == "":
		return 0

	var base_pct : float = float(s.heal_effect.get("base_heal_percent", 0.0))
	if base_pct > 0.0:
		var faith_pct : float = float(s.heal_effect.get("faith_percent_per_point", 0.01))
		var heal_pct : float = base_pct + s.faith * faith_pct
		return maxi(1, int(defender.unit_stats.max_hp * heal_pct))

	var base_heal : int = int(s.heal_effect.get("base_heal", 0))
	var faith_bonus : float = s.faith * float(s.heal_effect.get("faith_multiplier", 1.0))
	return maxi(1, int(base_heal + faith_bonus))


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

	var heal_amount : int = get_expected_emergency_heal(attacker, target)
	var old_hp : int = target.hit_points

	if attacker.relic_heal_bonus > 0.0:
		heal_amount = int(heal_amount * (1.0 + attacker.relic_heal_bonus))
	var heal_affix_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot: heal_affix_bonus += slot.get_affix_value_float("heal_boost")
	heal_amount = int(heal_amount * (1.0 + heal_affix_bonus))

	target.hit_points = mini(target.hit_points + heal_amount, target.unit_stats.max_hp)
	var actual : int = target.hit_points - old_hp

	target.update_hp_label()
	SignalBus.request_damage_popup.emit(target.global_position, actual, false, false, true)
	SignalBus.request_hint_override.emit("急救 +%d（-%d 魂火）" % [actual, cost], 1.5)
	SoundManager.play_heal_sound()

	attacker.mark_attacked()
	_finish_attack(attacker, target)

	await get_tree().create_timer(PERFORMANCE_DURATION, true, false, true).timeout
	Globals.is_performing_action = false
	return true


func get_expected_emergency_heal(attacker: Unit, target: Unit) -> int:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return 0
	var heal_pct : float = 0.5
	var heal_amount : int = maxi(1, int(target.unit_stats.max_hp * heal_pct))
	if attacker.relic_heal_bonus > 0.0:
		heal_amount = int(heal_amount * (1.0 + attacker.relic_heal_bonus))
	var affix_bonus : float = 0.0
	for slot in attacker.armor_slots:
		if slot:
			affix_bonus += slot.get_affix_value_float("heal_boost")
	heal_amount = int(heal_amount * (1.0 + affix_bonus))
	return heal_amount
