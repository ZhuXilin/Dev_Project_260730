class_name AbnormalManager
extends RefCounted

## ============================================================
##  AbnormalManager — 异常状态（v6.62y）
## ============================================================
##  设计口径（GameplayDesignDoc 5.4.1）：
##   施加流派给敌方上异常层 → 异常层本身是「全队易伤标记」，任何伤害都有小幅增益
##   → 消费流派攻击带异常目标时，引发大量伤害或特殊效果，并清层。
##
##  三层效果，各司其职：
##   1) 施加层：词条让攻击/受击/移动时给敌方上异常，概率随品质 + 流派有效 Lv 缩放。
##   2) 易伤层：每种异常每层给「全队任何伤害来源」小幅易伤（灼烧/冻寒 +3%，
##      灰烬附着 +2%），上限 3 层；不写存档、不占机制槽。
##   3) 消费层：消费词条持有者攻击带异常目标时引爆/融化/汲取，清层；
##      消费伤害 = 每层按施加者攻击的百分比 × 层数（远大于易伤）。
##
##  三条短链路（每种 1 施加 + 1 消费）：
##   灼烧     烈焰「灼热之刃」施加 → 余烬「引爆专精」消费（每层 12% 攻击，3 层 36%；epic+ 禁疗）
##   冻寒     守护「寒霜护甲」施加 → 烈焰「融雪」消费（每层 10% 攻击火焰伤害，3 层 30%；epic+ 减速）
##   灰烬附着 灰烬「余烬足迹」施加 → 轮回「魂火汲取」消费（每层 1 魂火 + 治疗最低血队友 3%）
##
##  献祭不新增异常：作为「对带异常目标额外 +5% 攻击」的收益者。
##  异常只在本场战斗有效，不写存档（数据挂在 Unit.abnormal_stacks）。
## ============================================================

const TYPE_BURN : String = "灼烧"
const TYPE_FROST : String = "冻寒"
const TYPE_ASH : String = "灰烬附着"
const ALL_TYPES : Array = [TYPE_BURN, TYPE_FROST, TYPE_ASH]

## ---- 施加层：层数 / 持续 ----
const MAX_STACKS : int = 3              # 基础上限 3 层（epic/legendary 变体可 +1）
const STACK_DURATION : int = 2          # 持续 2 回合，重复施加刷新时长但不叠加速度
const QUALITY_ORDER : Array = ["common", "rare", "epic", "legendary"]

## ---- 易伤层：全队任何伤害来源都吃 ----
const VULN_PER_STACK : Dictionary = {
	TYPE_BURN: 0.03,    # 灼烧：每层 +3%，3 层 +9%
	TYPE_FROST: 0.03,   # 冻寒：每层 +3%，3 层 +9%
	TYPE_ASH: 0.02,     # 灰烬附着：每层 +2%，3 层 +6%
}
const FROST_VULN_EPIC_BONUS : float = 0.02   # 寒霜护甲 epic+：冻寒易伤每层额外 +2%
const FROST_MOVE_PENALTY : int = 1           # 冻寒每层移动 -1
const FROST_MOVE_PENALTY_MAX : int = 2       # 移动惩罚封顶 -2，不跳过行动
const THAW_SLOW_ROUNDS : int = 2             # 融雪 epic+：融化后目标减速 2 回合

## ---- 消费层：每层按施加者攻击的百分比，随流派有效 Lv 每级 +2% ----
const CONSUME_BASE_RATIO : Dictionary = {
	TYPE_BURN: 0.12,    # 引爆：每层 12% 攻击，3 层 36%
	TYPE_FROST: 0.10,   # 融化：每层 10% 攻击火焰伤害，3 层 30%
}
const CONSUME_LEVEL_STEP : float = 0.02
const BURN_HEAL_BAN_ROUNDS : int = 1         # 引爆 epic+：禁疗 1 回合
## 魂火汲取：每层回 1 魂火；治疗最低血队友按品质 × 最大 HP 的百分比
const SOUL_DRAIN_HEAL_BY_QUALITY : Dictionary = {
	"common": 0.0, "rare": 0.03, "epic": 0.05, "legendary": 0.07,
}

## ---- DOT：每层每回合基础伤害（冻寒不跳伤害） ----
const DOT_BASE_PER_STACK : Dictionary = {TYPE_BURN: 2, TYPE_ASH: 1}

## ---- 献祭收益者：对带异常目标额外攻击 ----
const SACRIFICE_VULN_ATTACK_BONUS : float = 0.05


## 扫描单位所有防具词条，聚合出该单位的异常能力。
## 返回 {type: {
##   apply_chance, apply_stacks, apply_cap, apply_quality,
##   consume_value, consume_quality, consume_school, level, school
## }}
static func get_profile(unit: Unit) -> Dictionary:
	var out : Dictionary = {}
	if unit == null or unit.unit_stats == null:
		return out
	var slots : Array = unit.unit_stats.armor_slots
	for slot in slots:
		if slot == null:
			continue
		var inst : ItemInstance = slot as ItemInstance
		if inst == null:
			continue
		for a in inst.affixes:
			if not (a is Dictionary):
				continue
			var aid : String = str((a as Dictionary).get("id", ""))
			var d : Dictionary = AffixManager.get_affix(aid)
			if d.is_empty():
				continue
			var abv : Variant = d.get("abnormal", null)
			if not (abv is Dictionary):
				continue
			var ab : Dictionary = abv as Dictionary
			var t : String = str(ab.get("type", ""))
			if not ALL_TYPES.has(t):
				continue
			var school : String = str(ab.get("school", ""))
			var role : String = str(ab.get("role", ""))
			var lvl : int = BuildManager.get_effective_school_level(unit, school)
			var val : int = int((a as Dictionary).get("value", 0))
			var quality : String = str((a as Dictionary).get("quality", ""))
			if quality == "" or not QUALITY_ORDER.has(quality):
				quality = _quality_from_value(d, val)
			if not out.has(t):
				out[t] = {
					"apply_chance": 0, "apply_stacks": 0, "apply_cap": 0,
					"apply_quality": "common",
					"consume_value": 0, "consume_quality": "common", "consume_school": "",
					"level": 0, "school": school,
				}
			var e : Dictionary = out[t]
			if role == "apply":
				# 施加概率 = 词条基础（品质分档）+ 流派有效 Lv × 5%
				var chance : int = val + lvl * 5
				if chance > int(e["apply_chance"]):
					e["apply_chance"] = chance
					e["apply_quality"] = quality
				# 层数：1 + (Lv≥3 ? 1 : 0)，epic/legendary 上限 +1（不超过 4）
				var stacks : int = 1 + (1 if lvl >= 3 else 0)
				if stacks > int(e["apply_stacks"]):
					e["apply_stacks"] = stacks
				var cap : int = MAX_STACKS + (1 if quality in ["epic", "legendary"] else 0)
				e["apply_cap"] = maxi(int(e["apply_cap"]), cap)
			elif role == "consume":
				# 消费强度分档值（引爆/融雪为伤害加成%，魂火汲取按品质映射治疗）
				if val > int(e["consume_value"]):
					e["consume_value"] = val
					e["consume_quality"] = quality
					e["consume_school"] = school
			e["level"] = maxi(int(e["level"]), lvl)
			out[t] = e
	return out


## 旧存档/旧词条实例没有 quality 字段时，按 quality_values 反推档位。
static func _quality_from_value(d: Dictionary, value: int) -> String:
	var qv : Variant = d.get("quality_values", null)
	if not (qv is Dictionary):
		return "common"
	var best : String = "common"
	for q in QUALITY_ORDER:
		if (qv as Dictionary).has(q) and value >= int((qv as Dictionary)[q]):
			best = str(q)
	return best


## 攻击命中后，按施加端概率给目标挂异常。
static func apply_from_attack(attacker: Unit, defender: Unit) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	if attacker.unit_stats.team_id == defender.unit_stats.team_id:
		return
	var profile : Dictionary = get_profile(attacker)
	for t in ALL_TYPES:
		var e : Dictionary = profile.get(t, {})
		var chance : int = int(e.get("apply_chance", 0))
		if chance <= 0 or chance < randi() % 100:
			continue
		var stacks : int = maxi(1, int(e.get("apply_stacks", 1)))
		_add_stack(defender, t, stacks, attacker, int(e.get("level", 0)),
				str(e.get("apply_quality", "common")), int(e.get("apply_cap", MAX_STACKS)))
		# legendary 灼热之刃：施加时立即跳一次易伤（即时小额伤害，让 legendary 单件就有感）
		if t == TYPE_BURN and str(e.get("apply_quality", "common")) == "legendary" \
				and defender.hit_points > 0:
			var pop : int = maxi(1, int(float(attacker.unit_stats.attack) * 0.15))
			SignalBus.request_damage_popup.emit(defender.global_position, pop, false, false, false)
			if defender.apply_damage(pop):
				CombatManager._on_kill(attacker, defender)


## 受击时按防守方「寒霜护甲」概率给攻击方上冻寒（守护流派：挨打上冻寒）。
static func apply_frost_on_hit(defender: Unit, attacker: Unit) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker):
		return
	if defender.unit_stats.team_id == attacker.unit_stats.team_id:
		return
	var e : Dictionary = get_profile(defender).get(TYPE_FROST, {})
	var chance : int = int(e.get("apply_chance", 0))
	if chance <= 0 or chance < randi() % 100:
		return
	var stacks : int = maxi(1, int(e.get("apply_stacks", 1)))
	_add_stack(attacker, TYPE_FROST, stacks, defender, int(e.get("level", 0)),
			str(e.get("apply_quality", "common")), int(e.get("apply_cap", MAX_STACKS)))


## 外部强制挂层（不掷概率）：爆发附加 / 技能固定效果用。
static func apply_burn_stacks(source: Unit, target: Unit, stacks: int) -> void:
	if not is_instance_valid(source) or not is_instance_valid(target) or stacks <= 0:
		return
	_add_stack(target, TYPE_BURN, stacks, source,
		BuildManager.get_effective_school_level(source, "烈焰"), "epic", MAX_STACKS)


## 给目标加层（外部也可直接调用，如受击触发的冻寒）。
static func _add_stack(unit: Unit, type: String, stacks: int, source: Unit, level: int,
		quality: String = "common", cap: int = MAX_STACKS) -> void:
	if not is_instance_valid(unit) or not ALL_TYPES.has(type) or stacks <= 0:
		return
	var cur : Dictionary = unit.abnormal_stacks.get(type, {})
	var limit : int = maxi(MAX_STACKS, maxi(int(cur.get("cap", MAX_STACKS)), cap))
	var n : int = mini(limit, int(cur.get("stacks", 0)) + stacks)
	unit.abnormal_stacks[type] = {
		"stacks": n,
		"source": source,
		"level": maxi(int(cur.get("level", 0)), level),
		"quality": quality,
		"cap": limit,
		"turns": STACK_DURATION,  # 刷新持续时间，不叠加时长
	}
	unit.refresh_abnormal_icons()


## 每回合自然衰减 1 层。
static func _decay_one(unit: Unit, type: String) -> void:
	if not is_instance_valid(unit) or not unit.abnormal_stacks.has(type):
		return
	var e : Dictionary = unit.abnormal_stacks[type]
	var n : int = int(e.get("stacks", 0)) - 1
	if n <= 0:
		unit.abnormal_stacks.erase(type)
	else:
		e["stacks"] = n
		unit.abnormal_stacks[type] = e
	unit.refresh_abnormal_icons()


static func get_stacks(unit: Unit, type: String) -> int:
	if not is_instance_valid(unit):
		return 0
	var e : Dictionary = unit.abnormal_stacks.get(type, {})
	return int(e.get("stacks", 0))


static func total_stacks(unit: Unit) -> int:
	var n : int = 0
	for t in ALL_TYPES:
		n += get_stacks(unit, t)
	return n


static func clear_stacks(unit: Unit, type: String = "") -> void:
	if not is_instance_valid(unit):
		return
	if type == "":
		unit.abnormal_stacks.clear()
	else:
		unit.abnormal_stacks.erase(type)
	unit.refresh_abnormal_icons()


## 回合开始结算：DOT（灼烧/灰烬附着，冻寒不跳伤害）+ 持续回合倒计时。
## DOT 击杀归施加者：复用 CombatManager._on_kill(source, victim)，与灰烬地块口径一致。
static func tick_dot(unit: Unit) -> void:
	if not is_instance_valid(unit) or unit.hit_points <= 0:
		return
	for t in ALL_TYPES:
		var e : Dictionary = unit.abnormal_stacks.get(t, {})
		if e.is_empty():
			continue
		var n : int = int(e.get("stacks", 0))
		if n <= 0:
			continue
		# 易伤层对所有伤害生效——DOT 也吃易伤
		if DOT_BASE_PER_STACK.has(t):
			var src : Unit = e.get("source", null) as Unit
			var lvl : int = int(e.get("level", 0))
			var per : int = int(DOT_BASE_PER_STACK.get(t, 1)) + lvl
			var dmg : int = maxi(1, int(float(per * n) * (1.0 + get_damage_taken_bonus(unit))))
			SignalBus.request_damage_popup.emit(unit.global_position, dmg, false, false, false)
			var dead : bool = unit.apply_damage(dmg)
			# 每回合掉 1 层
			_decay_one(unit, t)
			if dead and is_instance_valid(src) and src.unit_stats.team_id != unit.unit_stats.team_id:
				CombatManager._on_kill(src, unit)
			if dead:
				return
		else:
			_decay_one(unit, t)
		# 持续时间 -1，到期全清（刷新只重置倒计时，不叠加时长）
		var cur : Dictionary = unit.abnormal_stacks.get(t, {})
		if cur.is_empty():
			continue
		var turns : int = int(cur.get("turns", STACK_DURATION)) - 1
		if turns <= 0:
			unit.abnormal_stacks.erase(t)
		else:
			cur["turns"] = turns
			unit.abnormal_stacks[t] = cur
		unit.refresh_abnormal_icons()
	# 禁疗/减速倒计时由 TurnManager 在「目标所属队伍回合结束」时统一递减（见 start_turn）。


## 消费端：攻击时对目标身上的异常做引爆/融化/魂火汲取。
## 伤害按「施加者攻击 × 每层比例 × 层数」计算，消费后清该异常层。
static func consume_on_attack(attacker: Unit, defender: Unit) -> int:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return 0
	if attacker.unit_stats.team_id == defender.unit_stats.team_id:
		return 0
	var profile : Dictionary = get_profile(attacker)
	var total : int = 0
	for t in ALL_TYPES:
		var pd : Dictionary = profile.get(t, {})
		var consume_value : int = int(pd.get("consume_value", 0))
		if consume_value <= 0:
			continue
		var n : int = get_stacks(defender, t)
		if n <= 0:
			continue
		var q : String = str(pd.get("consume_quality", "common"))
		var lvl : int = int(pd.get("level", 0))
		var skip_consume : bool = false
		if t == TYPE_BURN or t == TYPE_FROST:
			var base_ratio : float = float(CONSUME_BASE_RATIO.get(t, 0.10)) + float(lvl) * CONSUME_LEVEL_STEP
			var quality_bonus : float = float(consume_value) / 100.0
			var atk : float = float(attacker.unit_stats.attack) + float(attacker.buff_attack_flat)
			var dmg : int = maxi(1, int(atk * base_ratio * (1.0 + quality_bonus) * float(n)))
			SignalBus.request_damage_popup.emit(defender.global_position, dmg, true, false, false)
			var dead : bool = defender.apply_damage(dmg)
			if dead:
				CombatManager._on_kill(attacker, defender)   # 消费击杀归消费流派
			total += dmg
			# epic+ 特殊效果（锦上添花，不是唯一价值）
			if q in ["epic", "legendary"]:
				if t == TYPE_BURN:
					# 引爆：目标禁疗 1 回合
					defender.no_heal_rounds = maxi(defender.no_heal_rounds, BURN_HEAL_BAN_ROUNDS)
				else:
					# 融化：目标减速 2 回合（移动 -1，仍不跳过行动）
					defender.abnormal_slow_rounds = maxi(defender.abnormal_slow_rounds, THAW_SLOW_ROUNDS)
			# legendary 融雪：融化后刷新 1 层灼烧
			if t == TYPE_FROST and q == "legendary":
				_add_stack(defender, TYPE_BURN, 1, attacker, lvl, "legendary", MAX_STACKS)
			# legendary 引爆：每场首次不耗层
			if t == TYPE_BURN and q == "legendary" and not attacker.abnormal_free_detonate_used:
				attacker.abnormal_free_detonate_used = true
				skip_consume = true
		elif t == TYPE_ASH:
			# 轮回「魂火汲取」：每层回 1 魂火 + 治疗最低血队友（按品质比例）
			var gained : int = SoulFireManager.add(n)
			total += gained
			var heal_ratio : float = float(SOUL_DRAIN_HEAL_BY_QUALITY.get(q, 0.0))
			if heal_ratio > 0.0:
				var ally : Unit = find_lowest_hp_ally(attacker)
				if is_instance_valid(ally) and ally.hit_points < ally.unit_stats.max_hp:
					var heal : int = maxi(1, int(float(ally.unit_stats.max_hp) * heal_ratio * float(n)))
					_heal_unit(ally, heal)
					# legendary 魂火汲取：额外治疗 1 次
					if q == "legendary":
						_heal_unit(ally, heal)
		if not skip_consume:
			defender.abnormal_stacks.erase(t)
			defender.refresh_abnormal_icons()
	return total


## 治疗（走禁疗检查）：禁疗期间不生效。
static func _heal_unit(unit: Unit, amount: int) -> void:
	if not is_instance_valid(unit) or amount <= 0 or unit.no_heal_rounds > 0:
		return
	var old : int = unit.hit_points
	unit.hit_points = mini(unit.hit_points + amount, unit.unit_stats.max_hp)
	var actual : int = unit.hit_points - old
	if actual > 0:
		unit.update_hp_label()
		SignalBus.request_damage_popup.emit(unit.global_position, actual, false, false, true)


## 找同队中「当前 HP 比例最低且存活」的队友（魂火汲取治疗目标）。
static func find_lowest_hp_ally(unit: Unit) -> Unit:
	if not is_instance_valid(unit):
		return null
	var best : Unit = null
	var best_ratio : float = 2.0
	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u.hit_points <= 0:
			continue
		if u.unit_stats.team_id != unit.unit_stats.team_id:
			continue
		var ratio : float = float(u.hit_points) / float(maxi(1, u.unit_stats.max_hp))
		if ratio < best_ratio:
			best_ratio = ratio
			best = u
	return best


## 易伤层（全队通用）：目标身上每种异常的每层都让「所有伤害来源」多打一点。
## 覆盖普攻、技能、DOT、反击、溅射、灰烬地块——凡走 CombatManager 伤害公式的都吃。
static func get_damage_taken_bonus(defender: Unit) -> float:
	if not is_instance_valid(defender):
		return 0.0
	var total : float = 0.0
	for t in ALL_TYPES:
		var n : int = get_stacks(defender, t)
		if n <= 0:
			continue
		var per : float = float(VULN_PER_STACK.get(t, 0.0))
		if t == TYPE_FROST:
			var e : Dictionary = defender.abnormal_stacks.get(t, {})
			if str(e.get("quality", "common")) in ["epic", "legendary"]:
				per += FROST_VULN_EPIC_BONUS
		total += float(n) * per
	return total


## 献祭收益者：目标带任意异常层时，献祭流派单位对其攻击额外 +5%。
static func get_sacrifice_abnormal_bonus(attacker: Unit, defender: Unit) -> float:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return 0.0
	if BuildManager.get_effective_school_level(attacker, "献祭") <= 0:
		return 0.0
	return SACRIFICE_VULN_ATTACK_BONUS if total_stacks(defender) > 0 else 0.0


## 竞技场 1v1 无移动，灰烬附着不生效；只保留灼烧+引爆（冻寒只减速不硬控）。
static func is_type_active(type: String, arena_mode: bool) -> bool:
	if arena_mode and type == TYPE_ASH:
		return false
	return ALL_TYPES.has(type)
