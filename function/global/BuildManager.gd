extends Node
## ============================================================
##  BuildManager — v6 装备减负核心计算层（唯一出口）
## ============================================================
##  职责：
##   1. 流派机制定义与配色（承接 UIConst.BUILD_TAG_ORDER）
##   2. 单位流派槽名单（1 / 2 / 3）
##   3. 防具 → 流派映射、品质 → 机制 Lv 上限
##   4. 觉醒 / 并入 / 覆盖 的统一结算
##   5. 开局主动技能 roll 池（v6.66 全技能通用：主动技能不绑定单位；
##      单位特化由 SoulFireIdentity 的燃烧/爆发身份表提供，费用3技能仍按阈值过滤）
##   6. 战后防具 roll（价格曲线复用 economy_config.json）
##
##  设计口径（与 EquipmentBuildRefactorSummary.md 一致）：
##   - 第一件同流派防具 = 觉醒完整机制，占 1 个流派槽
##   - 第 2/3/4 件同流派 = 并入升 Lv，不占新槽
##   - 品质决定机制 Lv 上限：common 1 / rare 2 / epic 3 / legendary 4
##   - 不同流派才占新槽，受单位 1/2/3 槽限制
##   - 底层 armor_slots 继续承载防具属性 / 词条，玩家层只看机制视图
## ============================================================

signal build_changed(unit_name: String)

## 六流派：名称 / 一句话机制 / 战斗接线点
const SCHOOLS: Dictionary = {
	"烈焰": {"mechanic": "攻击附带灼烧", "hook": "damage"},
	"轮回": {"mechanic": "击杀回 2 魂火", "hook": "kill"},
	"灰烬": {"mechanic": "移动后留下燃烧地块", "hook": "move"},
	"守护": {"mechanic": "格挡时反弹伤害", "hook": "block"},
	"献祭": {"mechanic": "每回合扣血换攻击", "hook": "turn_start"},
	"余烬": {"mechanic": "魂火耗尽时下击必暴", "hook": "crit"},
}
const SCHOOL_ORDER: Array = ["烈焰", "轮回", "灰烬", "守护", "献祭", "余烬"]

## ============================================================
##  流派机制 Lv 上限 + 技能流派倾向（原共鸣已删除，v6.72）
## ============================================================
##  v6.72：删除「技能让流派有效 Lv +1」的共鸣机制。
##  流派 Lv 现在只由防具机制决定（Lv1~4）；技能不再加 Lv。
##  下表保留为「技能流派倾向」的兜底，仅供软保底与方向提示使用，
##  不再参与任何战斗数值。主数据来自 talents.json 的 school_affinity 字段。
const SCHOOL_MECH_MAX_LEVEL: int = 4
const SCHOOL_BY_SKILL: Dictionary = {
	"active_fireball": "烈焰",
	"active_dragon_breath": "灰烬",
	"active_dive": "灰烬",
	"active_taunt": "守护",
	"active_charge": "献祭",
	"active_heavy_slash": "献祭",
	"active_mass_heal": "轮回",
	"active_pierce": "余烬",
	"active_snipe": "余烬",
	"active_cleave": "献祭",
	"active_guard_break": "余烬",
	"active_swift_shot": "灰烬",
	"active_whirlwind": "烈焰",
	"active_battle_cry": "守护",
	"active_soul_burn": "献祭",
	"active_magic_pierce": "余烬",
	"active_execute": "轮回",
}

## 单位流派槽名单（v6 冻结）。未列出的单位默认 2 槽。
const MECHANISM_SLOTS: Dictionary = {
	"armored": 1, "dragonborn": 1,
	"spearman": 2, "pegasus": 2, "archer": 2, "axeman": 2, "cleric": 2,
	"swordsman": 3, "mage": 3,
}
const DEFAULT_MECHANISM_SLOTS: int = 2

## 品质 → 机制 Lv 上限（v6.34：cap 前移一档，让 common 也能升到 Lv2，
##   解决早期 common 占 60% 却 cap=1 导致"同流派并入升 Lv"毫无反馈的痛点）
const QUALITY_CAP: Dictionary = {"common": 2, "rare": 3, "epic": 4, "legendary": 4}

## 价格兜底（读取 economy_config.json 失败时使用）
const FALLBACK_ROLL_BASE: int = 100
const FALLBACK_ROLL_STEP: int = 50
const FALLBACK_UPGRADE_COSTS: Array = [100, 300, 900, 1800, 3500]  # 魂栈商店等级（共用旧键，不动）
## ★ v6.72：防具 roll 品质升级独立曲线（跨场持久，第二天初中期到顶）
const FALLBACK_ROLL_UPGRADE_COSTS: Array = [150, 350, 650, 1000, 1400]
const FALLBACK_ROLL_COST_FLOOR: int = 30
## ★ v6.62z：每场战斗首次防具 roll 固定 50G（不参与 100+50n 递增）
const FIRST_ROLL_COST: int = 50
const FALLBACK_MERGE_COST: int = 200

var _econ: Dictionary = {}
var _shop: Dictionary = {}
var _forge: Dictionary = {}
## quality_level(0..5) -> {quality: weight}
var _quality_weights: Array = []

## ★ v6.70 方案E 软保底（隐藏概率修正）
var _pity_armor_miss_threshold: int = 2
var _pity_armor_boost_mult: float = 3.0
var _pity_skill_last_guarantee: bool = true
var _pity_max_day: int = 2
## 连续未出新流派次数（战斗内/本场会话有效，不写存档）
var _armor_no_new_school_streak: int = 0


func _ready() -> void:
	_reload_config()


func _reload_config() -> void:
	_econ = GameConfigManager.get_file("economy_config.json")
	_shop = _econ.get("shop", {})
	_forge = _econ.get("forge", {})
	var pity : Dictionary = _econ.get("soft_pity", {})
	_pity_armor_miss_threshold = maxi(1, int(pity.get("armor_miss_threshold", _pity_armor_miss_threshold)))
	_pity_armor_boost_mult = maxf(1.0, float(pity.get("armor_boost_mult", _pity_armor_boost_mult)))
	_pity_skill_last_guarantee = bool(pity.get("skill_last_roll_guarantee", _pity_skill_last_guarantee))
	_pity_max_day = maxi(0, int(pity.get("max_day", _pity_max_day)))
	_quality_weights = _shop.get("quality_weights", [])
	if _quality_weights.is_empty():
		_quality_weights = [
			{"common": 60, "rare": 30, "epic": 10, "legendary": 0},
			{"common": 45, "rare": 35, "epic": 18, "legendary": 2},
			{"common": 30, "rare": 40, "epic": 25, "legendary": 5},
			{"common": 15, "rare": 35, "epic": 40, "legendary": 10},
			{"common": 5, "rare": 25, "epic": 50, "legendary": 20},
			{"common": 0, "rare": 15, "epic": 50, "legendary": 35},
		]


# ============================================================
#  流派 / 槽位 / 品质
# ============================================================

func is_school(tag: String) -> bool:
	return SCHOOL_ORDER.has(tag)


func get_school_color(school: String) -> Color:
	return UIConst.BUILD_TAG_COLORS.get(school, UIConst.NO_TAG_COLOR)


func get_school_mechanic(school: String) -> String:
	var info: Dictionary = SCHOOLS.get(school, {})
	return str(info.get("mechanic", ""))


func get_mechanism_slots(unit_name: String) -> int:
	return int(MECHANISM_SLOTS.get(unit_name, DEFAULT_MECHANISM_SLOTS))


## 新局重置一个单位的 v6 build 状态：清空机制、按名单重置流派槽上限。
func reset_unit_build(unit: UnitData) -> void:
	if not unit:
		return
	unit.mechanisms = {}
	unit.max_armor_slots = get_mechanism_slots(unit.unit_name)
	unit.basic_enhancements = []   # ★ v6.71：清空上一轮的普攻强化模板
	# ★ v6.71：第 1 格常驻单位的「基础魂火技能」（特质层，不可被配装移除、可被 roll 强化/替换）。
	#   第 2 格仍由转职（advanced_talent_inst）承载。基础技能来自 unit_data.json.base_soul_skill。
	unit.talent_slots = []
	if unit.base_soul_skill != "" and TalentManager.get_talent_data(unit.base_soul_skill) != null:
		var base_inst := TalentInstance.new()
		base_inst.talent_id = unit.base_soul_skill
		base_inst.is_active = true
		base_inst.is_ready = true
		base_inst.is_base = true
		base_inst.locked = false   # 基础技能可被引擎/roll 替换，但配装 UI 不允许手改（is_base 拦截）
		unit.talent_slots.append(base_inst)
	else:
		# 无基础技能配置（敌方/旧档）→ 留空，走旧的 roll 落位
		unit.talent_slots.append(null)
	unit.max_talent_slots = 1


func get_quality_cap(quality: String) -> int:
	return int(QUALITY_CAP.get(quality, 1))


func get_mechanic_lv_text(school: String, level: int) -> String:
	var mech := get_school_mechanic(school)
	if level <= 1:
		return "觉醒 · %s" % mech
	return "%s Lv%d · %s" % [school, level, mech]


## 防具 item_id → 流派名；无流派标签返回空串
func get_school_of_item(item_id: String) -> String:
	var data: ItemData = ItemManager.get_item_data(item_id)
	if not data:
		return ""
	for tag in data.tags:
		if is_school(str(tag)):
			return str(tag)
	return ""


## ★ v6.53：词条即流派——从词条 tags 推导流派（fallback 到防具本身 tags）。
##   优先取第一个词条的流派 tag；多词条时按 SCHOOL_ORDER 优先级取"最靠前"的流派，
##   保证同一件防具判定稳定。
func get_school_of_affixes(affixes: Array, fallback_item_id: String = "") -> String:
	var found : Array = []
	for a in affixes:
		if not (a is Dictionary):
			continue
		var data : Dictionary = AffixManager.get_affix(str(a.get("id", "")))
		for tag in data.get("tags", []):
			var t : String = str(tag)
			if is_school(t) and not found.has(t):
				found.append(t)
	# ★ v6.54 方案A：专精防具（affix_schools 非空）优先取锁定池内的流派，
	#   避免"防具锁守护、词条是灰烬护体(灰烬+守护)"时判定打架。
	var fallback_data : ItemData = ItemManager.get_item_data(fallback_item_id)
	var locked : Array = fallback_data.affix_schools if fallback_data != null else []
	if not locked.is_empty():
		for school in SCHOOL_ORDER:
			if found.has(school) and locked.has(school):
				return school
	for school in SCHOOL_ORDER:
		if found.has(school):
			return school
	# 词条无流派（罕见，如旧存档）→ 回退防具 tag
	return get_school_of_item(fallback_item_id)


func get_school_of_instance(inst: ItemInstance) -> String:
	if inst == null:
		return ""
	return get_school_of_affixes(inst.affixes, inst.item_id)


# ============================================================
#  机制视图（从 UnitData.mechanisms 读取，玩家层唯一数据源）
# ============================================================

func _ensure_mechanisms(unit: UnitData) -> Dictionary:
	if not unit:
		return {}
	if not (unit.mechanisms is Dictionary):
		unit.mechanisms = {}
	return unit.mechanisms


## 返回 [{school, level, cap, count, color, mechanic, text}, ...]，按 SCHOOL_ORDER 排序
func get_unit_mechanisms(unit: UnitData) -> Array:
	var result: Array = []
	if not unit:
		return result
	var mechs: Dictionary = _ensure_mechanisms(unit)
	for school in SCHOOL_ORDER:
		if not mechs.has(school):
			continue
		var entry: Dictionary = mechs[school]
		if not (entry is Dictionary):
			continue
		var level := int(entry.get("level", 1))
		result.append({
			"school": school,
			"level": level,
			"cap": int(entry.get("cap", 1)),
			"count": int(entry.get("count", 1)),
			"color": get_school_color(school),
			"mechanic": get_school_mechanic(school),
			"text": get_mechanic_lv_text(school, level),
		})
	return result


func get_used_mechanism_slots(unit: UnitData) -> int:
	return get_unit_mechanisms(unit).size()


func has_school(unit: UnitData, school: String) -> bool:
	if not unit:
		return false
	return _ensure_mechanisms(unit).has(school)


func get_school_level(unit: UnitData, school: String) -> int:
	if not unit:
		return 0
	var mechs: Dictionary = _ensure_mechanisms(unit)
	if not mechs.has(school):
		return 0
	var entry: Dictionary = mechs[school]
	return int(entry.get("level", 0)) if entry is Dictionary else 0


# ============================================================
#  战斗层统一入口：有效 Lv 与六流派机制数值表
# ============================================================

## Unit / UnitData 都接受；战斗层只认这里给出的有效 Lv。
func _unit_data_of(unit) -> UnitData:
	if unit == null:
		return null
	if unit is UnitData:
		return unit as UnitData
	var v: Variant = unit.get("unit_stats")
	if v is UnitData:
		return v as UnitData
	return null


## 技能 → 流派倾向（纯数据，v6.72）：仅供软保底挑选/roll 卡方向提示，
##   不再参与任何战斗数值（共鸣已删除）。优先读数据字段，缺失读兜底表。
func get_school_of_skill(talent_id: String) -> String:
	if talent_id == "":
		return ""
	var data: TalentData = TalentManager.get_talent_data(talent_id)
	if data != null and is_school(data.school_affinity):
		return data.school_affinity
	return str(SCHOOL_BY_SKILL.get(talent_id, ""))


## 流派有效 Lv（v6.72：= 防具机制 Lv，共鸣 +1 已删除）。
##   保留此函数壳是为了战斗层几十处调用点无需改动；语义现在是"直接返回防具 Lv"。
func get_effective_school_level(unit, school: String) -> int:
	return get_school_level(_unit_data_of(unit), school)


## 烈焰有效 Lv（战斗层旧接口）。
func get_flame_level(unit) -> int:
	return get_effective_school_level(unit, "烈焰")


## 烈焰灼烧伤害倍率：Lv1 15% / Lv2 25% / Lv3 35% / Lv4 45%（按本次伤害）
func get_flame_burn_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.15 + 0.10 * float(mini(level, SCHOOL_MECH_MAX_LEVEL) - 1)


## 守护：受击反弹比例，触发格挡时翻倍（在 CombatManager 处理）
func get_guard_reflect_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.30 + 0.15 * float(mini(level, SCHOOL_MECH_MAX_LEVEL) - 1)


## 轮回：击杀额外回魂火（_on_kill 已有命中 +1，此处是额外量）
func get_cycle_soul_gain(level: int) -> int:
	if level <= 0:
		return 0
	return mini(level + 1, 5)


## 献祭：回合开始扣血比例 / 本回合攻击加成
func get_sacrifice_hp_cost_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.03 + 0.01 * float(mini(level, SCHOOL_MECH_MAX_LEVEL) - 1)


func get_sacrifice_attack_bonus(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.10 + 0.05 * float(mini(level, SCHOOL_MECH_MAX_LEVEL) - 1)


## 灰烬：移动后在起点留下燃烧地块，敌人踩中受伤（一次性）
func get_ash_tile_damage(level: int) -> int:
	if level <= 0:
		return 0
	return 3 + 2 * (mini(level, SCHOOL_MECH_MAX_LEVEL) - 1)


## 余烬：魂火耗尽后下一次攻击必暴，并追加暴伤
func get_ember_crit_bonus(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.10 * float(mini(level, SCHOOL_MECH_MAX_LEVEL))


# ============================================================
#  ★ v6.34：Lv 阈值质变（B2）——Lv2/Lv4 解锁定性能力，而非纯数值。
#   战斗层各钩子通过 has_breakthrough(unit, school, key) 读取。
# ============================================================
const BREAKTHROUGH_LV2: int = 2
const BREAKTHROUGH_LV4: int = 4

## 某流派在当前有效 Lv 下是否解锁了指定质变能力。
## key 见下表：flame_stack / flame_spread / guard_lifesteal / guard_teamshield /
##   cycle_heal / cycle_reset / ash_persist / ash_burst /
##   sacrifice_shieldfirst / sacrifice_rage / ember_pierce / ember_burnout
func has_breakthrough(unit, school: String, key: String) -> bool:
	var lv := get_effective_school_level(unit, school)
	match key:
		"flame_stack", "guard_lifesteal", "cycle_heal", "ash_persist", "sacrifice_shieldfirst", "ember_pierce":
			return lv >= BREAKTHROUGH_LV2
		"flame_spread", "guard_teamshield", "cycle_reset", "ash_burst", "sacrifice_rage", "ember_burnout":
			return lv >= BREAKTHROUGH_LV4
	return false


## 取某单位所有已解锁的质变 key（供 UI 展示）
func get_breakthroughs(unit, school: String) -> Array:
	var eff := get_effective_school_level(unit, school)
	var keys: Array = []
	if eff <= 0:
		return keys
	var all: Dictionary = {
		"烈焰": ["flame_stack", "flame_spread"],
		"守护": ["guard_lifesteal", "guard_teamshield"],
		"轮回": ["cycle_heal", "cycle_reset"],
		"灰烬": ["ash_persist", "ash_burst"],
		"献祭": ["sacrifice_shieldfirst", "sacrifice_rage"],
		"余烬": ["ember_pierce", "ember_burnout"],
	}
	for k in all.get(school, []):
		if has_breakthrough(unit, school, k):
			keys.append(k)
	return keys



## BuildViewer / 提示统一文案（v6.72：共鸣 +1 已删除，只显示防具机制 Lv）
func get_effective_mechanic_text(unit, school: String) -> String:
	var lv: int = get_school_level(_unit_data_of(unit), school)
	if lv <= 0:
		return ""
	return "%s Lv%d · %s" % [school, lv, get_school_mechanic(school)]


# ============================================================
#  觉醒 / 并入 / 覆盖结算
# ============================================================

## 把一件防具的"机制贡献"应用到单位。
## 返回 Dictionary：
##   {result: "awaken"|"merge"|"full"|"plain", school, level, cap, replaced}
##  "full" 表示流派槽已满且是新流派，需要玩家选择覆盖 / 放弃（不自动执行）。
## ★ v6.54：封顶补偿——把新防具词条注入该流派代表防具（按 id 去重，避免叠同一条）。
##   返回实际注入条数。找不到代表件时返回 0（此时仍不算浪费：Lv 已满且词条无处可挂，属数据边界）。
## ★ v6.62z：封顶「注入词条」选项的落点——把新防具词条写入机制槽对应的代表防具，
##   Lv 不变（只换词条，不改机制）。按 id 去重，返回实际注入条数。
##   slot_idx 传 -1 时自动找该流派代表件；每场战斗限 1 次由 ArmorRollUI 门控。
func inject_affixes(unit: UnitData, school: String, affixes: Array, slot_idx: int = -1) -> int:
	if unit == null or school == "" or affixes.is_empty():
		return 0
	var target : ItemInstance = null
	if slot_idx >= 0 and slot_idx < unit.armor_slots.size():
		var sv : Variant = unit.armor_slots[slot_idx]
		if sv is ItemInstance and get_school_of_instance(sv as ItemInstance) == school:
			target = sv as ItemInstance
	if target == null:
		for slot in unit.armor_slots:
			var inst : ItemInstance = slot as ItemInstance
			if inst != null and get_school_of_instance(inst) == school:
				target = inst
				break
	if target == null:
		return 0
	var existing : Dictionary = {}
	for a in target.affixes:
		if a is Dictionary:
			existing[str(a.get("id", ""))] = true
	var added : int = 0
	for a in affixes:
		if not (a is Dictionary):
			continue
		var aid : String = str(a.get("id", ""))
		if aid == "" or existing.has(aid):
			continue
		target.affixes.append(a.duplicate())
		existing[aid] = true
		added += 1
	if added > 0:
		build_changed.emit(unit.unit_name)
	return added


func _inject_affixes_to_school(unit: UnitData, school: String, affixes: Array) -> int:
	var target : ItemInstance = null
	for slot in unit.armor_slots:
		var inst : ItemInstance = slot as ItemInstance
		if inst != null and get_school_of_instance(inst) == school:
			target = inst
			break
	if target == null:
		return 0
	var existing : Dictionary = {}
	for a in target.affixes:
		if a is Dictionary:
			existing[str(a.get("id", ""))] = true
	var added : int = 0
	for a in affixes:
		if not (a is Dictionary):
			continue
		var aid : String = str(a.get("id", ""))
		if aid == "" or existing.has(aid):
			continue
		target.affixes.append(a.duplicate())
		existing[aid] = true
		added += 1
	return added


func apply_armor(unit: UnitData, item_id: String, quality: String, forced_school: String = "", affixes: Array = []) -> Dictionary:
	# ★ v6.53：流派由词条决定（词条即流派）；fallback 防具 tag 兼容熔铸专属等无词条件
	var school := forced_school if forced_school != "" else get_school_of_affixes(affixes, item_id)
	var cap := get_quality_cap(quality)
	if school == "" or not unit:
		# ★ v6.55：无流派防具也要占物理槽，满槽时拒绝（否则越界后战斗被裁掉）
		if _append_armor_instance(unit, item_id, affixes):
			return {"result": "plain", "school": "", "level": 0, "cap": cap, "replaced": ""}
		return {"result": "full", "school": "", "level": 0, "cap": cap, "replaced": ""}

	var mechs: Dictionary = _ensure_mechanisms(unit)
	if mechs.has(school):
		# ★ v6.53 强化：并入只升机制 Lv，不 append 实例、不改已有防具词条
		var entry: Dictionary = mechs[school]
		if not (entry is Dictionary):
			entry = {}
		var old_level := int(entry.get("level", 1))
		var count := int(entry.get("count", 1)) + 1
		var old_cap := int(entry.get("cap", 1))
		var new_cap := maxi(old_cap, cap)
		var level := mini(count, new_cap)
		entry["count"] = count
		entry["cap"] = new_cap
		entry["level"] = level
		mechs[school] = entry
		# ★ v6.62z：封顶判定改为「Lv 未真正提升」。cap 已取 max(旧cap, 新cap)，
		#   高品质防具强化低品质槽时 cap 提升、Lv 可继续升——这种不算封顶，照常强化。
		var level_raised : bool = level > old_level
		var was_capped : bool = not level_raised
		# ★ v6.62z：封顶不再自动注入/静默浪费——由 ArmorRollUI 弹「返还金币 / 注入词条」二选一。
		#   这里只标记 capped，不改词条；玩家选择注入时才调用 inject_affixes。
		build_changed.emit(unit.unit_name)
		if level_raised and _crossed_breakthrough(old_level, level):
			SignalBus.build_awakened.emit(unit, school, level, get_school_color(school))
		return {"result": "merge", "school": school, "level": level, "cap": new_cap,
				"replaced": "", "capped": was_capped, "level_raised": level_raised,
				"affixes_injected": 0}

	var used := mechs.size()
	var slots := unit.max_armor_slots
	# ★ v6.55：双重校验——流派数未满，但物理槽（含无流派防具）已满也要拒绝
	var used_phys : int = unit.count_used_armor_slots()
	if used >= slots or used_phys >= slots:
		return {"result": "full", "school": school, "level": 0, "cap": cap, "replaced": ""}

	mechs[school] = {"level": 1, "cap": cap, "count": 1}
	if not _append_armor_instance(unit, item_id, affixes):
		# 写入失败则回滚机制，避免出现"机制已觉醒但没有防具"的口径脱节
		mechs.erase(school)
		return {"result": "full", "school": school, "level": 0, "cap": cap, "replaced": ""}
	build_changed.emit(unit.unit_name)
	SignalBus.build_awakened.emit(unit, school, 1, get_school_color(school))
	return {"result": "awaken", "school": school, "level": 1, "cap": cap, "replaced": ""}


## 升 Lv 是否跨过 2/4 质变阈值
func _crossed_breakthrough(old_lv: int, new_lv: int) -> bool:
	return (old_lv < BREAKTHROUGH_LV2 and new_lv >= BREAKTHROUGH_LV2) or \
		(old_lv < BREAKTHROUGH_LV4 and new_lv >= BREAKTHROUGH_LV4)


## 满槽时覆盖某流派：移除被覆盖流派，觉醒新流派。0G。
## ★ v6.53 转向：替换指定槽位的流派，100% 继承旧流派等级，用新防具词条。
##   新流派以旧流派 Lv/cap/count 起步（不归零），新实例带 affixes。
func overwrite_at_slot(unit: UnitData, slot_idx: int, school_to_remove: String, item_id: String, quality: String, affixes: Array = [], inherit_level: int = 1) -> Dictionary:
	if not unit:
		return {"result": "full", "school": "", "level": 0, "replaced": ""}
	var mechs: Dictionary = _ensure_mechanisms(unit)
	var old := mechs.get(school_to_remove, {}) as Dictionary
	var lvl : int = maxi(1, inherit_level if not old.is_empty() else 1)
	var cap : int = maxi(int(old.get("cap", 1)), get_quality_cap(quality))
	var count : int = maxi(1, int(old.get("count", 1)))
	# 移除被替换流派的所有实例（避免套装/词条口径脱节）
	for i in range(unit.armor_slots.size() - 1, -1, -1):
		var sv = unit.armor_slots[i]
		if sv == null:
			continue
		var sinst : ItemInstance = sv as ItemInstance
		if sinst and get_school_of_instance(sinst) == school_to_remove:
			unit.armor_slots[i] = null
	var new_school : String = get_school_of_affixes(affixes, item_id)
	mechs.erase(school_to_remove)
	if new_school != "":
		mechs[new_school] = {"level": lvl, "cap": cap, "count": count}
	# 把新防具（带新词条）放进玩家点击的那个槽
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	if not affixes.is_empty():
		inst.affixes = affixes.duplicate()
	if slot_idx >= 0 and slot_idx < unit.armor_slots.size():
		unit.armor_slots[slot_idx] = inst
	else:
		var free := unit.armor_slots.find(null)
		if free >= 0: unit.armor_slots[free] = inst
		else: unit.armor_slots.append(inst)
	build_changed.emit(unit.unit_name)
	return {"result": "overwrite", "school": new_school, "level": lvl, "cap": cap, "replaced": school_to_remove}


func overwrite_school(unit: UnitData, school_to_remove: String, item_id: String, quality: String, forced_school: String = "") -> Dictionary:
	if not unit:
		return {"result": "full", "school": "", "level": 0, "replaced": ""}
	var mechs: Dictionary = _ensure_mechanisms(unit)
	if not mechs.has(school_to_remove):
		return apply_armor(unit, item_id, quality, forced_school)
	mechs.erase(school_to_remove)
	# ★ v6.34：同步移除 armor_slots 中属于被覆盖流派的防具实例，
	#   否则 SetBonusManager 按 armor_slots 统计 tag 时，被覆盖的流派仍在贡献套装/词条，
	#   造成"机制视图已删、底层数据还在"的口径脱节。
	for i in range(unit.armor_slots.size() - 1, -1, -1):
		var slot_v = unit.armor_slots[i]
		if slot_v == null:
			continue
		var slot_inst: ItemInstance = slot_v as ItemInstance
		if slot_inst and get_school_of_instance(slot_inst) == school_to_remove:
			unit.armor_slots[i] = null
	build_changed.emit(unit.unit_name)
	var applied := apply_armor(unit, item_id, quality, forced_school)
	applied["replaced"] = school_to_remove
	return applied


## 把防具实例塞进底层 armor_slots（供战斗层读属性 / 词条）。
## ★ v6.55 修复"落第二槽后防具掉了"：绝不越界 append 到 max_armor_slots 之外。
##   旧实现无空位就 append 到第3位，玩家可见槽只显示前2个，
##   进战斗时 Unit.restore_from_unit_data 的 pop_back 把第3件裁掉、同步后永久丢失。
## 返回 bool：true=写入成功，false=槽位已满拒绝写入。
func _append_armor_instance(unit: UnitData, item_id: String, affixes: Array = []) -> bool:
	if not unit:
		return false
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	# ★ v6.53：落位时带上 roll 出的词条（词条即流派，且词条数值要生效）
	if not affixes.is_empty():
		inst.affixes = affixes.duplicate()
	# 只在可见槽位范围内找空位
	var limit : int = mini(unit.armor_slots.size(), unit.max_armor_slots)
	for i in range(limit):
		if unit.armor_slots[i] == null:
			unit.armor_slots[i] = inst
			return true
	# 数组还没到上限才扩容；已满则拒绝，绝不越界
	if unit.armor_slots.size() < unit.max_armor_slots:
		unit.armor_slots.append(inst)
		return true
	push_warning("[BuildManager] 防具槽已满(%d)，拒绝写入 %s" % [unit.max_armor_slots, item_id])
	return false


## 公开：挂一件无流派防具（熔铸专属等），供熔铸面板调用
func append_plain_armor(unit: UnitData, item_id: String) -> bool:
	return _append_armor_instance(unit, item_id)


# ============================================================
#  单位成长：击杀得经验 → 自动升级（v6.61 起经验唯一来源）
# ============================================================

const LEVEL_CAP: int = 6   ## 单位等级上限（UI 显示 / 升级封顶统一口径）

## 升到下一级所需经验（按当前等级递增）
func exp_to_next_level(current_level: int) -> int:
	return 60 + maxi(0, current_level - 1) * 40


## 到下一级还差多少经验（UI 显示用；满级返回 0）
func exp_to_next_remaining(unit: UnitData) -> int:
	if unit == null or unit.level >= LEVEL_CAP:
		return 0
	return maxi(0, exp_to_next_level(unit.level) - unit.experience)


## v6.61：战后额外经验已移除——经验唯一来源是击杀（grant_kill_exp）。
## 旧的 battle_exp_reward(node_type, rating) 已删除。

## 给单个单位加经验并自动升级；返回本次升到的等级。
## 每次升级发 SignalBus.request_level_up_popup，战场据此播仪式感。
func grant_exp_and_auto_level(unit: UnitData, amount: int) -> int:
	if unit == null or unit.is_dead:
		return unit.level if unit else 0
	unit.experience += maxi(0, amount)
	var guard := 0
	while guard < 10:
		guard += 1
		var need := exp_to_next_level(unit.level)
		if unit.experience < need or unit.level >= LEVEL_CAP:
			break
		unit.experience -= need
		if unit.apply_level_up():
			SignalBus.request_level_up_popup.emit(unit.unit_name, unit.level)
	return unit.level


## ★ v6.58：击杀经验——从被击杀单位的 exp 字段取值给击杀者。
## victim 是敌方 Unit/UnitData；exp 由 unit_data.json 按强度配置。
func grant_kill_exp(killer: UnitData, victim_exp: int) -> int:
	if killer == null or killer.is_dead or victim_exp <= 0:
		return killer.level if killer else 0
	return grant_exp_and_auto_level(killer, victim_exp)


# ============================================================
#  开局主动技能 roll 池
# ============================================================

## 开局主动技能 roll 池（v6.66 全技能通用：所有主动技能对全部单位开放，
##   仍按单位阈值过滤费用3技能；单位特化见 SoulFireIdentity）。去重、保序。
func build_skill_pool(unit_names: Array) -> Array:
	TalentManager.load_talent_data()   # 确保技能库已加载
	var pool: Array = []
	for uname in unit_names:
		var key := UnitDataManager.normalize_unit_key(str(uname))
		for tid in TalentManager._talent_db.keys():
			var data: TalentData = TalentManager._talent_db[tid]
			if not data or not data.is_active_skill:
				continue
			if TalentManager.is_talent_compatible_with_unit(data.id, key) and not pool.has(data.id) \
					and _skill_cost_allowed_for_unit(data.id, key):
				pool.append(data.id)
	return pool


## 某技能能被给定单位列表中的几个单位装备
func compatible_count_for(talent_id: String, unit_names: Array) -> int:
	var units: Array = _compatible_units_of(talent_id)
	var n: int = 0
	for uname in unit_names:
		var key := UnitDataManager.normalize_unit_key(str(uname))
		if key in units:
			n += 1
	return n


## 高兼容优先的技能池：优先返回能被多个剩余单位装备的技能，
## 让轮盘转出的每张卡天然有多个落点，避免"技能—单位 1 对 1"。
## min_cover=2 表示只收兼容≥2个单位的技能；不足时由调用方降级补单兼容技能。
func build_skill_pool_ranked(unit_names: Array, min_cover: int = 2) -> Array:
	var all := build_skill_pool(unit_names)
	var ranked: Array = []
	for sid in all:
		if compatible_count_for(str(sid), unit_names) >= min_cover:
			ranked.append(str(sid))
	return ranked


## 某单位可装备的全部主动技能 id（随机打乱，增加每局变化）
func _compatible_active_skills(unit_key: String) -> Array:
	var list: Array = []
	for tid in TalentManager._talent_db.keys():
		var data := TalentManager._talent_db[tid] as TalentData
		if data and data.is_active_skill \
				and TalentManager.is_talent_compatible_with_unit(data.id, unit_key) \
				and _skill_cost_allowed_for_unit(data.id, unit_key):
			list.append(str(data.id))
	list.shuffle()
	return list


## 按候选数从少到多排序（单位数很少，O(n²) 选择排序即可，避免 lambda 推断问题）
func _sorted_by_candidate_count(units: Array, cand: Dictionary) -> Array:
	var arr: Array = units.duplicate()
	for i in range(arr.size()):
		for j in range(i + 1, arr.size()):
			var ci: int = (cand.get(arr[i], []) as Array).size()
			var cj: int = (cand.get(arr[j], []) as Array).size()
			if cj < ci:
				var tmp: Variant = arr[i]
				arr[i] = arr[j]
				arr[j] = tmp
	return arr


## 二分图回溯匹配：给 units 中每个单位分配一个互不相同的技能。
## cand: unit_key -> 候选技能 id 数组；返回 {unit_key: talent_id}（尽量多匹配）。
func _match_units_to_skills(units: Array, cand: Dictionary) -> Dictionary:
	var order := _sorted_by_candidate_count(units, cand)
	var best: Dictionary = {}
	var assign: Dictionary = {}
	var used: Dictionary = {}
	_match_bt(order, 0, cand, assign, used, best)
	return best


func _match_bt(order: Array, idx: int, cand: Dictionary, assign: Dictionary, used: Dictionary, best: Dictionary) -> void:
	if assign.size() > best.size():
		best.clear()
		for k in assign:
			best[k] = assign[k]
	if idx >= order.size():
		return
	var u: String = str(order[idx])
	for tid in (cand.get(u, []) as Array):
		var sid: String = str(tid)
		if used.has(sid):
			continue
		used[sid] = true
		assign[u] = sid
		_match_bt(order, idx + 1, cand, assign, used, best)
		assign.erase(u)
		used.erase(sid)
		# 已找到覆盖全部单位的匹配，无需再搜
		if best.size() >= order.size():
			return


## 枚举前 limit 套"覆盖全部单位"的匹配，供 roll 挑选冗余度最高的一套。
## 只保留完整匹配（assign.size()==units.size()），避免半匹配混入。
func _enumerate_matchings(units: Array, cand: Dictionary, limit: int) -> Array:
	var order := _sorted_by_candidate_count(units, cand)
	var results: Array = []
	var assign: Dictionary = {}
	var used: Dictionary = {}
	_enum_bt(order, 0, cand, assign, used, results, limit)
	return results


func _enum_bt(order: Array, idx: int, cand: Dictionary, assign: Dictionary, used: Dictionary, results: Array, limit: int) -> void:
	if results.size() >= limit:
		return
	if idx >= order.size():
		if assign.size() == order.size():
			results.append(assign.duplicate())
		return
	var u: String = str(order[idx])
	for tid in (cand.get(u, []) as Array):
		var sid: String = str(tid)
		if used.has(sid):
			continue
		used[sid] = true
		assign[u] = sid
		_enum_bt(order, idx + 1, cand, assign, used, results, limit)
		assign.erase(u)
		used.erase(sid)
		if results.size() >= limit:
			return


## 一套匹配中，每张技能卡可被几个"已选单位"装备。
## 返回 min_cover（最窄那张卡的单位数），越大表示每张卡的选择越多。
func _matching_min_cover(matching: Dictionary, all_units: Array) -> int:
	var skills: Array = []
	for u in matching:
		skills.append(str(matching[u]))
	if skills.is_empty():
		return 0
	var min_cover: int = 9999
	for sid in skills:
		var data := TalentManager.get_talent_data(sid)
		var cover: int = 0
		if data:
			for u in all_units:
				if TalentManager.is_talent_compatible_with_unit(str(sid), str(u)):
					cover += 1
		min_cover = mini(min_cover, cover)
	return min_cover


## 从当前队伍找单位数据（roll 时排除第 1 格已被占用的单位）
func _find_party_unit(unit_key: String) -> UnitData:
	for ud in GameState.party:
		if ud != null and UnitDataManager.normalize_unit_key(ud.unit_name) == unit_key:
			return ud
	return null


## ★ v6.71：该单位是否还能接受一次 roll 落位。
##   开局 slot0 是基础技能（可替换）；一旦落过 roll（soul_skill 替换 或 basic_attack 强化）
##   就不再接受第二次。basic_attack 不占 slot0，但用 basic_enhancements 标记"已 roll 过"。
func is_skill_slot_replaceable(unit: UnitData) -> bool:
	if unit == null:
		return false
	# 已用 basic_attack 模板强化过普攻 → 本次 roll 机会已用
	if not unit.basic_enhancements.is_empty():
		return false
	if unit.talent_slots.is_empty() or unit.talent_slots[0] == null:
		return true
	var inst = unit.talent_slots[0]
	if inst is TalentInstance:
		return (inst as TalentInstance).is_base
	return false


func _has_empty_skill_slot(unit_key: String) -> bool:
	var ud := _find_party_unit(unit_key)
	if ud == null:
		return true   # 找不到数据时保持旧行为，避免误伤其他调用
	return is_skill_slot_replaceable(ud)


## roll count 次主动技能：先按单位做匹配，保证存在一套"每个单位各得一个可装备技能"的分配，
## 再把这套技能打乱顺序返回。杜绝"roll 出无人能装的技能 → 跳过 → 单位无技能"。
func roll_active_skills(unit_names: Array, count: int = 3, unit_data_override: Array = []) -> Array:
	TalentManager.load_talent_data()
	var units: Array = []
	for uname in unit_names:
		var key := UnitDataManager.normalize_unit_key(str(uname))
		# ★ v6 修复：默认词条/旧档可能占住第 1 格，这类单位不能参与 roll 匹配，
		#   否则会 roll 出一个"唯一兼容者技能格已满"的死卡。
		# ★ v6.16：Arena 单单位注入——用注入对象的槽位状态，不从 GameState.party 查，
		#   避免主线队伍里同名单位已占格导致竞技场单位被误排除（空池秒关）。
		var slot_free: bool = true
		if not unit_data_override.is_empty():
			for ud in unit_data_override:
				if ud != null and UnitDataManager.normalize_unit_key(str(ud.unit_name)) == key:
					slot_free = is_skill_slot_replaceable(ud)   # ★ v6.71：基础技能槽可被 roll 替换
					break
		else:
			slot_free = _has_empty_skill_slot(key)
		if not units.has(key) and slot_free:
			units.append(key)

	var cand: Dictionary = {}
	for u in units:
		cand[u] = _compatible_active_skills(str(u))

	# ★ v6.17：不再取"第一套"完美匹配（那会组成紧耦合技能集，每张卡只有一个落点）。
	#   枚举多套完整匹配，挑"最窄技能卡也能被最多单位装备"的一套，
	#   让每张 roll 出的技能卡都有更多可选单位，同时仍保证无人无技能。
	var candidates: Array = _enumerate_matchings(units, cand, 240)
	var assign: Dictionary = {}
	if candidates.is_empty():
		assign = _match_units_to_skills(units, cand)
	else:
		var best_cover: int = -1
		var best_idx: int = 0
		for i in range(candidates.size()):
			var m: Dictionary = candidates[i]
			var cover: int = _matching_min_cover(m, units)
			if cover > best_cover:
				best_cover = cover
				best_idx = i
		assign = candidates[best_idx]

	var result: Array = []
	for u in assign:
		result.append(str(assign[u]))
	result.shuffle()
	if result.size() > count:
		result = result.slice(0, count)
	# ★ v6.70 方案E：软保底——开局技能最后一次 roll 优先保证至少一张能衔接
	#   已有消费链的技能（流派倾向 ∈ 队伍已觉醒流派）。仅窗口期内、且未满足时替换末张。
	if _pity_skill_last_guarantee and _is_pity_window() and result.size() > 0:
		var owned: Dictionary = _owned_school_set()
		var has_chain: bool = false
		for tid in result:
			var s: String = get_school_of_skill(str(tid))
			if s != "" and owned.has(s):
				has_chain = true
				break
		if not has_chain and not owned.is_empty():
			# 末张对应的落位单位必须仍兼容替换技能，避免保底制造死卡。
			var last_sid: String = str(result[result.size() - 1])
			var target_key: String = ""
			for u in assign:
				if str(assign[u]) == last_sid:
					target_key = str(u)
					break
			var rep: String = _find_chain_skill(owned, [target_key] if target_key != "" else units, result)
			if rep != "" and not result.has(rep):
				result[result.size() - 1] = rep
	return result


## ★ v6.70：找一个流派倾向属于已觉醒流派、且兼容本次 roll 单位的技能（软保底替换用）。
func _find_chain_skill(owned: Dictionary, units: Array, exclude: Array) -> String:
	TalentManager.load_talent_data()
	var fallback: String = ""
	for tid in TalentManager._talent_db.keys():
		var sid: String = str(tid)
		if exclude.has(sid):
			continue
		var data: TalentData = TalentManager._talent_db[tid]
		if data == null or not data.is_active_skill:
			continue
		var s: String = get_school_of_skill(sid)
		if s == "" or not owned.has(s):
			continue
		for u in units:
			var key: String = str(u)
			if TalentManager.is_talent_compatible_with_unit(sid, key) \
					and _skill_cost_allowed_for_unit(sid, key):
				return sid
		if fallback == "":
			fallback = sid
	return fallback


## 落位安全检查：把 talent_id 给 unit 后，剩余单位是否仍能被剩余技能覆盖。
## remaining_unit_names / remaining_skill_ids 均为尚未落位的单位与技能（含当前这一个）。
func is_safe_placement(unit: UnitData, talent_id: String, remaining_unit_names: Array, remaining_skill_ids: Array) -> bool:
	if not can_place_skill(unit, talent_id):
		return false
	# 剩余单位（排除当前单位）
	var left_units: Array = []
	for un in remaining_unit_names:
		var key := UnitDataManager.normalize_unit_key(str(un))
		if key != UnitDataManager.normalize_unit_key(unit.unit_name):
			left_units.append(key)
	if left_units.is_empty():
		return true
	# 剩余技能（消耗掉当前技能一次）
	var left_skills: Array = []
	var consumed := false
	for tid in remaining_skill_ids:
		var sid: String = str(tid)
		if not consumed and sid == talent_id:
			consumed = true
			continue
		left_skills.append(sid)
	# 剩余单位必须各能分到一个剩余技能
	var cand: Dictionary = {}
	for u in left_units:
		var lst: Array = []
		for sid in left_skills:
			var data := TalentManager.get_talent_data(sid)
			if data and data.is_active_skill \
					and TalentManager.is_talent_compatible_with_unit(str(sid), str(u)) \
					and _skill_cost_allowed_for_unit(str(sid), str(u)):
				lst.append(str(sid))
		cand[u] = lst
	var assign := _match_units_to_skills(left_units, cand)
	return assign.size() >= left_units.size()


## ★ v6.18：贴合"老虎机逐轮重 roll"模型的落位判定。
## 当前 SkillRollUI 每轮都从全体技能池重新 roll（不是一次性发完固定几张），
## 因此落位时不必用"剩余那几张固定技能"去精确覆盖——那是旧模型的过紧约束，
## 会把每张技能卡的可落位单位压到只剩 1 个（1 对 1）。
## 新口径：只要 ①目标兼容且第 1 格空；②把该技能给目标后，
## 其余每个空槽单位在"全体技能池"里都能分到一个互不相同的可装备技能（二分匹配），
## 就允许落位。这样每张卡通常有 2~4 个可选单位，同时仍杜绝任何单位最终无技能。
func can_place_with_future(unit: UnitData, talent_id: String, remaining_unit_names: Array) -> bool:
	if not can_place_skill(unit, talent_id):
		return false
	# 剩余单位（排除当前目标）
	var left_units: Array = []
	for un in remaining_unit_names:
		var key := UnitDataManager.normalize_unit_key(str(un))
		if key != UnitDataManager.normalize_unit_key(unit.unit_name):
			left_units.append(key)
	if left_units.is_empty():
		return true
	# 从全体主动技能池为每个剩余单位建候选（当前技能已被目标占用，排除掉）
	var all_pool: Array = _all_active_skill_ids()
	var cand: Dictionary = {}
	for u in left_units:
		var lst: Array = []
		for sid in all_pool:
			if str(sid) == talent_id:
				continue
			if str(u) in _compatible_units_of(str(sid)) \
					and _skill_cost_allowed_for_unit(str(sid), str(u)):
				lst.append(str(sid))
		cand[u] = lst
	var assign := _match_units_to_skills(left_units, cand)
	return assign.size() >= left_units.size()


## 全体主动技能 id（去重）
func _all_active_skill_ids() -> Array:
	TalentManager.load_talent_data()
	var out: Array = []
	for tid in TalentManager._talent_db.keys():
		var data := TalentManager._talent_db[tid] as TalentData
		if data and data.is_active_skill and not out.has(str(data.id)):
			out.append(str(data.id))
	return out


func _compatible_units_of(talent_id: String) -> Array:
	var data := TalentManager.get_talent_data(talent_id)
	if data == null:
		return []
	var cu: Array = data.compatible_units if data.compatible_units != null else []
	# ★ v6.66：全技能通用——兼容列表为空的主动技能视为全部玩家单位可装。
	if cu.is_empty() and data.is_active_skill:
		return ["swordsman", "mage", "cleric", "armored", "archer",
				"spearman", "pegasus", "axeman", "dragonborn"]
	return cu


## ★ v6.66：费用3技能只配阈值≥4的单位（快爆型阈值3单位永远在爆发态，
##   费用3技能会让它失去"普通释放窗口"，故从这类单位的 roll 池排除）。
##   数据源：技能 effect_params.soul_fire_cost == 3；单位阈值走 SoulFireIdentity。
func _skill_cost_allowed_for_unit(talent_id: String, unit_key: String) -> bool:
	var data := TalentManager.get_talent_data(talent_id)
	if data == null:
		return false
	var ep: Dictionary = data.effect_params if data.effect_params != null else {}
	var cost: int = int(ep.get("soul_fire_cost", 0))
	if cost <= 0:
		cost = 3 if data.effect_type == "heal" else 2
	if cost < 3:
		return true
	var threshold: int = SoulFireIdentity.get_burst_threshold(unit_key)
	return threshold >= 4


## 某技能对某单位是否可落位（兼容 + 该单位尚未占用第 1 技能格）
func can_place_skill(unit: UnitData, talent_id: String) -> bool:
	if not unit:
		return false
	var adv := str(unit.advanced_class)
	if not TalentManager.is_talent_compatible_with_unit(talent_id, unit.unit_name, adv):
		return false
	# ★ v6.66：费用3技能不落阈值3（快爆）单位
	var key := UnitDataManager.normalize_unit_key(str(unit.unit_name))
	if not _skill_cost_allowed_for_unit(talent_id, key):
		return false
	# ★ v6.71：anchor=basic_attack 的模板只做普攻强化（被动），不占技能位，
	#   但仍要求该单位的本次 roll 机会未用（避免同一单位被 roll 两次）。
	var tdata := TalentManager.get_talent_data(talent_id)
	var anchor : String = tdata.get_anchor() if tdata else "soul_skill"
	if anchor == "basic_attack":
		return is_skill_slot_replaceable(unit) and not unit.basic_enhancements.has(talent_id)
	# 第 1 格为空或仍是基础魂火技能 = 可被 roll 强化/替换
	return is_skill_slot_replaceable(unit)


## 把 roll 到的技能按锚点落到单位：
##   soul_skill   → 替换第 1 格基础魂火技能（技能按钮内容）
##   basic_attack → 记入 basic_enhancements（普攻被动强化，不占按钮）
##   both         → 两者都做
func place_skill(unit: UnitData, talent_id: String) -> bool:
	if not can_place_skill(unit, talent_id):
		return false
	var tdata := TalentManager.get_talent_data(talent_id)
	var anchor : String = tdata.get_anchor() if tdata else "soul_skill"
	if anchor == "":
		anchor = "soul_skill"
	# 普攻强化：记入被动增强列表，不写技能位
	if anchor == "basic_attack":
		if not unit.basic_enhancements.has(talent_id):
			unit.basic_enhancements.append(talent_id)
		return true
	# soul_skill / both：写第 1 格技能位（替换基础技能）
	var inst := TalentInstance.new()
	inst.talent_id = talent_id
	inst.is_active = true
	inst.locked = true   # ★ roll 技能选定离手
	if tdata and tdata.is_active_skill:
		inst.is_ready = true
	inst.roll_anchor = anchor
	inst.is_base = false
	while unit.talent_slots.size() < 1:
		unit.talent_slots.append(null)
	unit.talent_slots[0] = inst
	# both：额外再加一份普攻强化
	if anchor == "both" and not unit.basic_enhancements.has(talent_id):
		unit.basic_enhancements.append(talent_id)
	return true


# ============================================================
#  战后防具 roll
# ============================================================

func get_roll_cost(roll_count_in_session: int) -> int:
	var base := int(_shop.get("base_reset_cost", FALLBACK_ROLL_BASE))
	var step := int(_shop.get("reset_step", FALLBACK_ROLL_STEP))
	var n := maxi(0, roll_count_in_session)
	# ★ v6.62z：每场首次 roll 固定 50G，不参与 100+50n 递增；离开结算重置计数。
	#   _roll_count 是 ArmorRollUI 的场结算内成员，UI 关闭即销毁，天然实现"离开结算重置"。
	# ★ v6.59：老虎机遗物——定额筹码（价格不随连续 roll 递增）
	var sm: Dictionary = GameState.get_slot_machine_relic_effects()
	var cost : float
	if n == 0:
		cost = float(FIRST_ROLL_COST)
	else:
		if bool(sm.get("roll_no_price_growth", false)):
			n = 0
		cost = float(base + step * n)
	# ★ 节俭之轮：花费 -N（效果值存 0.2 表示 20%）
	var discount := float(sm.get("roll_cost_discount", 0.0))
	if discount > 0.0:
		cost *= (1.0 - clampf(discount, 0.0, 0.9))
	# ★ v6.65：经济上限——任何折扣后成本仍 ≥30G（防止集齐经济遗物后无限廉价 roll）。
	var floor_cost := int(_shop.get("roll_cost_floor", FALLBACK_ROLL_COST_FLOOR))
	return maxi(floor_cost, int(round(cost)))


## ★ v6.59：老虎机遗物——每次 roll 后的金币返还（ArmorRollUI 调用）
func get_roll_gold_rebate(cost_paid: int) -> int:
	var sm: Dictionary = GameState.get_slot_machine_relic_effects()
	var rate := float(sm.get("roll_gold_rebate", 0.0))
	if rate <= 0.0: return 0
	return maxi(0, int(round(float(cost_paid) * clampf(rate, 0.0, 1.0))))


## ★ v6.72：防具 roll 品质升级用独立曲线 roll_upgrade_costs，
##   与魂栈商店等级 upgrade_costs 分离（后者保持不变）。
func get_upgrade_cost(quality_level: int) -> int:
	var costs: Array = _shop.get("roll_upgrade_costs", FALLBACK_ROLL_UPGRADE_COSTS)
	if quality_level < 0 or quality_level >= costs.size():
		return -1
	return int(costs[quality_level])


func get_max_quality_level() -> int:
	return maxi(0, int(_shop.get("max_level", 5)))


func get_merge_cost() -> int:
	# 单例方法无法读 _forge，走实例接口；保留静态兜底
	return FALLBACK_MERGE_COST


func get_merge_cost_instance() -> int:
	return int(_forge.get("craft_cost", FALLBACK_MERGE_COST))


## 按品质权重表抽一个品质；quality_level 为 0..5 级
func roll_quality(quality_level: int) -> String:
	var lv := clampi(quality_level, 0, _quality_weights.size() - 1)
	var weights: Dictionary = (_quality_weights[lv] as Dictionary).duplicate()
	# ★ v6.59：命运透镜——高品质权重翻倍（rare/epic/legendary）
	var sm: Dictionary = GameState.get_slot_machine_relic_effects()
	if int(sm.get("roll_high_quality_boost", 0)) > 0:
		for hq in ["rare", "epic", "legendary"]:
			if weights.has(hq):
				weights[hq] = int(weights[hq]) * 2
	var total := 0
	for q in weights:
		total += int(weights[q])
	if total <= 0:
		return "common"
	var pick := randi() % total
	var acc := 0
	for q in QUALITY_CAP:
		acc += int(weights.get(q, 0))
		if pick < acc:
			return q
	return "common"


## roll 一件防具，返回 {item_id, quality, school, name, mechanic}
## ★ v6.70：新局重置软保底计数（不写存档）。
func reset_soft_pity() -> void:
	_armor_no_new_school_streak = 0

## ★ v6.70：软保底窗口——仅当前天数 <= max_day 时生效（第一天到第二天之间）。
func _is_pity_window() -> bool:
	if _pity_max_day <= 0:
		return true
	return GameState.current_day <= _pity_max_day

## ★ v6.70：队伍已觉醒流派集合（从 UnitData.mechanisms 读取）。
##   ★ v6.71 修复：get_unit_mechanisms 返回 Array[Dictionary]，必须取 s["school"]，
##     旧代码 owned[str(s)] 把整个字典字符串化当 key，导致 owned.has("烈焰") 恒 false，
##     技能/防具两处软保底全部空转。
func _owned_school_set() -> Dictionary:
	var owned: Dictionary = {}
	for u in GameState.get_party_units():
		if u == null:
			continue
		for s in get_unit_mechanisms(u):
			if s is Dictionary:
				var school_name : String = str((s as Dictionary).get("school", ""))
				if school_name != "":
					owned[school_name] = true
	return owned

func roll_armor(quality_level: int) -> Dictionary:
	var quality := roll_quality(quality_level)
	var candidates: Array = []
	for iid in ItemManager.get_all_item_ids():
		var data: ItemData = ItemManager.get_item_data(iid)
		if not data:
			continue
		if (data.type == "armor" or data.equipment_slot == "armor") and data.quality == quality:
			if str(data.id).begins_with("melt_"):
				continue
			candidates.append(iid)
	if candidates.is_empty():
		# 该品质无防具时降级到 common 池
		for iid in ItemManager.get_all_item_ids():
			var d: ItemData = ItemManager.get_item_data(iid)
			if d and (d.type == "armor" or d.equipment_slot == "armor") and not str(d.id).begins_with("melt_"):
				candidates.append(iid)
		quality = "common"
	if candidates.is_empty():
		return {}
	# ★ v6.70 方案E：软保底——连续 N 次未出新流派时，给"队伍尚未觉醒流派"的防具加权。
	#   隐藏概率修正，不改 UI 文案与规则表述；窗口仅在 max_day 之前。
	var weighted: Array = []
	var pity_active: bool = _is_pity_window() and _armor_no_new_school_streak >= _pity_armor_miss_threshold
	var owned_schools: Dictionary = _owned_school_set()
	if pity_active:
		for iid in candidates:
			var d: ItemData = ItemManager.get_item_data(iid)
			if d == null:
				continue
			# ★ v6.72：sid 未使用（加权只用 tags），删除避免 UNUSED_VARIABLE 警告
			var locked: Array = d.affix_schools if d.affix_schools is Array else []
			var pool_tags: Array = locked if not locked.is_empty() else d.tags
			var fresh: bool = false
			for t in pool_tags:
				if is_school(str(t)) and not owned_schools.has(str(t)):
					fresh = true
					break
			if fresh:
				for _w in range(int(_pity_armor_boost_mult * 2.0)):
					weighted.append(iid)
			else:
				weighted.append(iid)
	var item_id: String = ""
	if weighted.is_empty():
		item_id = str(candidates[randi() % candidates.size()])
	else:
		item_id = str(weighted[randi() % weighted.size()])
	var idata : ItemData = ItemManager.get_item_data(item_id)
	var affixes : Array = [] if idata != null and idata.no_affix else AffixManager.roll_affixes(quality, idata.tags if idata != null else [], idata.affix_schools if idata != null else [])
	var school := get_school_of_affixes(affixes, item_id)
	# 更新连续未出新流派计数
	if school != "" and not owned_schools.has(school):
		_armor_no_new_school_streak = 0
	else:
		_armor_no_new_school_streak += 1
	return {
		"item_id": item_id,
		"quality": quality,
		"school": school,
		"affixes": affixes,
		"name": idata.name if idata != null else item_id,
		"mechanic": get_school_mechanic(school),
	}


## v6.3：给老虎机提供一池可选防具（每个条目都是一次合法 roll 结果）
func get_armor_roll_pool(quality_level: int, count: int = 8) -> Array:
	var entries: Array = []
	var seen: Dictionary = {}
	var guard: int = 0
	while entries.size() < count and guard < count * 20:
		guard += 1
		var rolled: Dictionary = roll_armor(quality_level)
		if rolled.is_empty():
			break
		var iid := str(rolled.get("item_id", ""))
		if seen.has(iid):
			continue
		seen[iid] = true
		var data: ItemData = ItemManager.get_item_data(iid)
		var school := str(rolled.get("school", ""))
		var color := Color(0.82, 0.82, 0.86)
		if school != "":
			color = get_school_color(school)
		var quality := str(rolled.get("quality", "common"))
		# ★ v6.20：轮盘符号直接带流派文字 —— 玩家转动时就能看到"哪个流派"，
		#   配合流派色（color）形成文字+颜色双重识别，避免"铁甲"这类看不出流派的名字。
		var base_name := str(rolled.get("name", iid))
		var display_name := ("【%s】%s" % [school, base_name]) if school != "" else base_name
		entries.append({
			"id": iid,
			"item_id": iid,
			"name": display_name,
			"quality": quality,
			"school": school,
			"mechanic": str(rolled.get("mechanic", "")),
			"color": color,
			"icon": data.icon if data != null else null,
		})

	# ★ v6.59：流派罗盘——目标流派条目在池里重复 N 份，提高轮盘停在该流派的概率
	var sm: Dictionary = GameState.get_slot_machine_relic_effects()
	var boost := float(sm.get("roll_school_boost", 0.0))
	var target_school := str(sm.get("roll_school_target", ""))
	if boost > 0.0 and target_school != "":
		var extra_count := clampi(int(boost), 1, 4)
		var originals : Array = entries.duplicate()
		for e in originals:
			if str(e.get("school", "")) == target_school:
				for _i in range(extra_count):
					if entries.size() >= count * 3: break
					entries.append((e as Dictionary).duplicate(true))

	# ★ v6.34：品质保底——若整池全是 common，强制把第一个条目替换为一件 rare+ 防具，
	#   避免早期 8 个候选全是 Lv 上限低的价值重复项。重 roll 保证 item_id 与 quality 一致。
	var has_high: bool = false
	for e in entries:
		if str(e.get("quality", "common")) != "common":
			has_high = true
			break
	if not has_high and not entries.is_empty():
		var hi: Dictionary = {}
		for attempt in range(30):
			var q: String = ["rare", "epic", "legendary"][randi() % 3]
			var r: Dictionary = roll_armor(_quality_index_for(q))
			if not r.is_empty() and str(r.get("quality", "common")) != "common" and not seen.has(str(r.get("item_id", ""))):
				hi = r
				break
		if not hi.is_empty():
			var hd: ItemData = ItemManager.get_item_data(str(hi.get("item_id", "")))
			var hs: String = str(hi.get("school", ""))
			var hcolor := get_school_color(hs) if hs != "" else Color(0.82, 0.82, 0.86)
			entries[0] = {
				"id": str(hi.get("item_id", "")),
				"item_id": str(hi.get("item_id", "")),
				"name": ("【%s】%s" % [hs, str(hi.get("name", ""))]) if hs != "" else str(hi.get("name", "")),
				"quality": str(hi.get("quality", "rare")),
				"school": hs,
				"mechanic": str(hi.get("mechanic", "")),
				"color": hcolor,
				"icon": hd.icon if hd != null else null,
			}
	return entries


## 品质字符串 → quality_level 索引（用于保底重 roll）
func _quality_index_for(q: String) -> int:
	match q:
		"rare": return 2
		"epic": return 4
		"legendary": return 5
	return 0


## 重铸流派：保留品质与词条，只改流派。返回新的 school。
# ============================================================
#  遗物生命周期（光环并入）
# ============================================================

## relic / aura id → "persistent" | "consumable"
## 口径：只有直接产出魂火的原光环做消耗型，其余全部持续型。
const CONSUMABLE_RELICS: Array = ["aura_ember", "aura_cycle"]


func get_relic_lifetime(relic_id: String) -> String:
	var data: Dictionary = RelicManager.get_relic_data(relic_id)
	var lt := str(data.get("lifetime", ""))
	if lt == "persistent" or lt == "consumable":
		return lt
	return "consumable" if CONSUMABLE_RELICS.has(relic_id) else "persistent"


func is_consumable_relic(relic_id: String) -> bool:
	return get_relic_lifetime(relic_id) == "consumable"
