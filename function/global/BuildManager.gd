extends Node
## ============================================================
##  BuildManager — v6 装备减负核心计算层（唯一出口）
## ============================================================
##  职责：
##   1. 流派机制定义与配色（承接 UIConst.BUILD_TAG_ORDER）
##   2. 单位流派槽名单（1 / 2 / 3）
##   3. 防具 → 流派映射、品质 → 机制 Lv 上限
##   4. 觉醒 / 并入 / 覆盖 的统一结算
##   5. 开局主动技能 roll 池（已选单位 compatible_units 并集）
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
##  v6.2 主动技能 × 流派共鸣
## ============================================================
##  口径（唯一）：单位身上有「共鸣流派 = 该流派」的主动技能时，
##  该流派的战斗机制按「有效 Lv = 防具 Lv + 1」结算，上限 4。
##  - 不新增第二套数值曲线：共鸣只借用已有的 Lv1~Lv4 机制表；
##  - 不叠层：同流派多个技能也只 +1；不占槽、不写存档；
##  - 技能标签写在 talents.json 的 resonance_school 字段；
##    下表只作旧数据 / 新建技能遗漏字段时的兜底。
const RESONANCE_LEVEL_BONUS: int = 1
const RESONANCE_MAX_LEVEL: int = 4
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
const FALLBACK_UPGRADE_COSTS: Array = [200, 500, 1200, 2500, 5000]
const FALLBACK_MERGE_COST: int = 200

var _econ: Dictionary = {}
var _shop: Dictionary = {}
var _forge: Dictionary = {}
## quality_level(0..5) -> {quality: weight}
var _quality_weights: Array = []


func _ready() -> void:
	_reload_config()


func _reload_config() -> void:
	_econ = GameConfigManager.get_file("economy_config.json")
	_shop = _econ.get("shop", {})
	_forge = _econ.get("forge", {})
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
	# ★ v6 口径：第 1 格留给开局 roll，第 2 格由转职（advanced_talent_inst）承载。
	#   旧 v5 的 default_talents（crit/block 等）会占住第 1 格，导致 roll 时无人可落位；
	#   新局必须先清空，否则 SkillRollUI 三个单位全灰。
	unit.talent_slots = [null]
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


## 技能 → 共鸣流派：优先读数据字段，缺失时读兜底表。
func get_school_of_skill(talent_id: String) -> String:
	if talent_id == "":
		return ""
	var data: TalentData = TalentManager.get_talent_data(talent_id)
	if data != null and is_school(data.resonance_school):
		return data.resonance_school
	return str(SCHOOL_BY_SKILL.get(talent_id, ""))


## 单位当前装备的主动技能 id（第 1 格 roll + 第 2 格转职；只读取用）。
func _unit_skill_ids(unit) -> Array:
	var ids: Array = []
	if unit == null:
		return ids
	var slots_v: Variant = null
	if unit is UnitData:
		slots_v = (unit as UnitData).talent_slots
	else:
		slots_v = unit.get("talent_slots")
	if slots_v is Array:
		for inst in (slots_v as Array):
			if inst == null:
				continue
			if inst is TalentInstance and not (inst as TalentInstance).is_active:
				continue
			var tid: String = str(inst.get("talent_id"))
			if tid != "" and not ids.has(tid):
				ids.append(tid)
	# ★ v6.8：第 2 格转职技能也参与流派共鸣
	var adv_v: Variant = unit.get("advanced_talent_inst")
	if adv_v is TalentInstance:
		var adv: TalentInstance = adv_v as TalentInstance
		if adv.is_active:
			var adv_tid: String = str(adv.talent_id)
			if adv_tid != "" and not ids.has(adv_tid):
				ids.append(adv_tid)
	return ids


func has_skill_resonance(unit, school: String) -> bool:
	if not is_school(school):
		return false
	for tid in _unit_skill_ids(unit):
		if get_school_of_skill(str(tid)) == school:
			return true
	return false


## 共鸣生效后的 Lv；无该机制返回 0，绝不为「只有技能没有防具」凭空开机制。
func get_effective_school_level(unit, school: String) -> int:
	var lv: int = get_school_level(_unit_data_of(unit), school)
	if lv <= 0:
		return 0
	if has_skill_resonance(unit, school):
		return mini(lv + RESONANCE_LEVEL_BONUS, RESONANCE_MAX_LEVEL)
	return lv


## 烈焰有效 Lv（战斗层旧接口，语义升级为含共鸣）。
func get_flame_level(unit) -> int:
	return get_effective_school_level(unit, "烈焰")


## 烈焰灼烧伤害倍率：Lv1 15% / Lv2 25% / Lv3 35% / Lv4 45%（按本次伤害）
func get_flame_burn_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.15 + 0.10 * float(mini(level, RESONANCE_MAX_LEVEL) - 1)


## 守护：受击反弹比例，触发格挡时翻倍（在 CombatManager 处理）
func get_guard_reflect_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.30 + 0.15 * float(mini(level, RESONANCE_MAX_LEVEL) - 1)


## 轮回：击杀额外回魂火（_on_kill 已有命中 +1，此处是额外量）
func get_cycle_soul_gain(level: int) -> int:
	if level <= 0:
		return 0
	return mini(level + 1, 5)


## 献祭：回合开始扣血比例 / 本回合攻击加成
func get_sacrifice_hp_cost_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.03 + 0.01 * float(mini(level, RESONANCE_MAX_LEVEL) - 1)


func get_sacrifice_attack_bonus(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.10 + 0.05 * float(mini(level, RESONANCE_MAX_LEVEL) - 1)


## 灰烬：移动后在起点留下燃烧地块，敌人踩中受伤（一次性）
func get_ash_tile_damage(level: int) -> int:
	if level <= 0:
		return 0
	return 3 + 2 * (mini(level, RESONANCE_MAX_LEVEL) - 1)


## 余烬：魂火耗尽后下一次攻击必暴，并追加暴伤
func get_ember_crit_bonus(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.10 * float(mini(level, RESONANCE_MAX_LEVEL))


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



## BuildViewer / 提示统一文案
func get_effective_mechanic_text(unit, school: String) -> String:
	var base: int = get_school_level(_unit_data_of(unit), school)
	var eff: int = get_effective_school_level(unit, school)
	if base <= 0:
		return ""
	if eff > base:
		return "%s Lv%d（共鸣 +1）· %s" % [school, eff, get_school_mechanic(school)]
	return "%s Lv%d · %s" % [school, eff, get_school_mechanic(school)]


# ============================================================
#  觉醒 / 并入 / 覆盖结算
# ============================================================

## 把一件防具的"机制贡献"应用到单位。
## 返回 Dictionary：
##   {result: "awaken"|"merge"|"full"|"plain", school, level, cap, replaced}
##  "full" 表示流派槽已满且是新流派，需要玩家选择覆盖 / 放弃（不自动执行）。
func apply_armor(unit: UnitData, item_id: String, quality: String, forced_school: String = "") -> Dictionary:
	var school := forced_school if forced_school != "" else get_school_of_item(item_id)
	var cap := get_quality_cap(quality)
	if school == "" or not unit:
		# 无流派防具（熔铸专属等）：仅作为普通属性防具
		_append_armor_instance(unit, item_id)
		return {"result": "plain", "school": "", "level": 0, "cap": cap, "replaced": ""}

	var mechs: Dictionary = _ensure_mechanisms(unit)
	if mechs.has(school):
		# 并入升 Lv，不占新槽
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
		_append_armor_instance(unit, item_id)
		build_changed.emit(unit.unit_name)
		# ★ v6.34（B1）：升 Lv 跨过 2/4 质变阈值才发觉醒反馈，普通并入不刷屏
		if _crossed_breakthrough(old_level, level):
			SignalBus.build_awakened.emit(unit, school, level, get_school_color(school))
		return {"result": "merge", "school": school, "level": level, "cap": new_cap, "replaced": ""}

	var used := mechs.size()
	var slots := get_mechanism_slots(unit.unit_name)
	if used >= slots:
		return {"result": "full", "school": school, "level": 0, "cap": cap, "replaced": ""}

	mechs[school] = {"level": 1, "cap": cap, "count": 1}
	_append_armor_instance(unit, item_id)
	build_changed.emit(unit.unit_name)
	# ★ v6.34（B1）：首次觉醒即仪式反馈
	SignalBus.build_awakened.emit(unit, school, 1, get_school_color(school))
	return {"result": "awaken", "school": school, "level": 1, "cap": cap, "replaced": ""}


## 升 Lv 是否跨过 2/4 质变阈值
func _crossed_breakthrough(old_lv: int, new_lv: int) -> bool:
	return (old_lv < BREAKTHROUGH_LV2 and new_lv >= BREAKTHROUGH_LV2) or \
		(old_lv < BREAKTHROUGH_LV4 and new_lv >= BREAKTHROUGH_LV4)


## 满槽时覆盖某流派：移除被覆盖流派，觉醒新流派。0G。
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
		if slot_inst and get_school_of_item(slot_inst.item_id) == school_to_remove:
			unit.armor_slots[i] = null
	build_changed.emit(unit.unit_name)
	var applied := apply_armor(unit, item_id, quality, forced_school)
	applied["replaced"] = school_to_remove
	return applied


## 把防具实例塞进底层 armor_slots（供战斗层读属性 / 词条）。
## 玩家层不操作该数组；满则扩展，永不因物理槽拒绝。
func _append_armor_instance(unit: UnitData, item_id: String) -> void:
	if not unit:
		return
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = 1
	var idx := unit.armor_slots.find(null)
	if idx >= 0:
		unit.armor_slots[idx] = inst
	else:
		unit.armor_slots.append(inst)


## 公开：挂一件无流派防具（熔铸专属等），供熔铸面板调用
func append_plain_armor(unit: UnitData, item_id: String) -> void:
	_append_armor_instance(unit, item_id)


# ============================================================
#  单位成长：战斗累计经验 → 战后自动升级
# ============================================================

## 升到下一级所需经验（按当前等级递增；目标每局净增 1~2 级）
func exp_to_next_level(current_level: int) -> int:
	return 60 + maxi(0, current_level - 1) * 40


## 战斗贡献折算经验：胜利基础 + 评级加成
func battle_exp_reward(node_type: int, rating: String) -> int:
	var base := 40
	match node_type:
		MapNode.NodeType.START:   base = 40
		MapNode.NodeType.NORMAL:  base = 60
		MapNode.NodeType.ELITE:   base = 90
		MapNode.NodeType.BOSS:    base = 120
		_:                        base = 40
	var bonus : int = int({"S": 30, "A": 15, "B": 0, "C": 0}.get(rating, 0))
	return base + bonus


## 战后给单个单位加经验并自动升级；返回本次升到的等级
func grant_exp_and_auto_level(unit: UnitData, amount: int) -> int:
	if unit == null or unit.is_dead:
		return unit.level if unit else 0
	unit.experience += maxi(0, amount)
	var guard := 0
	while guard < 10:
		guard += 1
		var need := exp_to_next_level(unit.level)
		if unit.experience < need or unit.level >= 6:
			break
		unit.experience -= need
		unit.apply_level_up()
	return unit.level


# ============================================================
#  开局主动技能 roll 池
# ============================================================

## 已选单位 compatible_units 的并集（去重、保序），只取主动技能。
func build_skill_pool(unit_names: Array) -> Array:
	TalentManager.load_talent_data()   # 确保技能库已加载
	var pool: Array = []
	for uname in unit_names:
		var key := UnitDataManager.normalize_unit_key(str(uname))
		for tid in TalentManager._talent_db.keys():
			var data: TalentData = TalentManager._talent_db[tid]
			if not data or not data.is_active_skill:
				continue
			if key in data.compatible_units and not pool.has(data.id):
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
		if data and data.is_active_skill and unit_key in data.compatible_units:
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
				if str(u) in data.compatible_units:
					cover += 1
		min_cover = mini(min_cover, cover)
	return min_cover


## 从当前队伍找单位数据（roll 时排除第 1 格已被占用的单位）
func _find_party_unit(unit_key: String) -> UnitData:
	for ud in GameState.party:
		if ud != null and UnitDataManager.normalize_unit_key(ud.unit_name) == unit_key:
			return ud
	return null


func _has_empty_skill_slot(unit_key: String) -> bool:
	var ud := _find_party_unit(unit_key)
	if ud == null:
		return true   # 找不到数据时保持旧行为，避免误伤其他调用
	return ud.talent_slots.is_empty() or ud.talent_slots[0] == null


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
					slot_free = (ud.talent_slots.is_empty() or ud.talent_slots[0] == null)
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
	return result


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
			if data and data.is_active_skill and str(u) in data.compatible_units:
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
			if str(u) in _compatible_units_of(str(sid)):
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
	return data.compatible_units if data.compatible_units != null else []


## 某技能对某单位是否可落位（兼容 + 该单位尚未占用第 1 技能格）
func can_place_skill(unit: UnitData, talent_id: String) -> bool:
	if not unit:
		return false
	var adv := str(unit.advanced_class)
	if not TalentManager.is_talent_compatible_with_unit(talent_id, unit.unit_name, adv):
		return false
	# 第 1 格空 = 未被 roll 技能占用
	return unit.talent_slots.is_empty() or unit.talent_slots[0] == null


## 把 roll 到的主动技能写入单位第 1 格（锁定，不提供互换）
func place_skill(unit: UnitData, talent_id: String) -> bool:
	if not can_place_skill(unit, talent_id):
		return false
	var inst := TalentInstance.new()
	inst.talent_id = talent_id
	inst.is_active = true
	inst.locked = true   # ★ roll 技能选定离手
	var tdata := TalentManager.get_talent_data(talent_id)
	if tdata and tdata.is_active_skill:
		inst.is_ready = true
	while unit.talent_slots.size() < 1:
		unit.talent_slots.append(null)
	unit.talent_slots[0] = inst
	return true


# ============================================================
#  战后防具 roll
# ============================================================

func get_roll_cost(roll_count_in_session: int) -> int:
	var base := int(_shop.get("base_reset_cost", FALLBACK_ROLL_BASE))
	var step := int(_shop.get("reset_step", FALLBACK_ROLL_STEP))
	return base + step * maxi(0, roll_count_in_session)


func get_upgrade_cost(quality_level: int) -> int:
	var costs: Array = _shop.get("upgrade_costs", FALLBACK_UPGRADE_COSTS)
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
	var weights: Dictionary = _quality_weights[lv]
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
	var item_id := str(candidates[randi() % candidates.size()])
	var school := get_school_of_item(item_id)
	return {
		"item_id": item_id,
		"quality": quality,
		"school": school,
		"name": ItemManager.get_item_data(item_id).name,
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
