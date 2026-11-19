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

## 单位流派槽名单（v6 冻结）。未列出的单位默认 2 槽。
const MECHANISM_SLOTS: Dictionary = {
	"armored": 1, "dragonborn": 1,
	"spearman": 2, "pegasus": 2, "archer": 2, "axeman": 2, "cleric": 2,
	"swordsman": 3, "mage": 3,
}
const DEFAULT_MECHANISM_SLOTS: int = 2

## 品质 → 机制 Lv 上限
const QUALITY_CAP: Dictionary = {"common": 1, "rare": 2, "epic": 3, "legendary": 4}

## 价格兜底（读取 economy_config.json 失败时使用）
const FALLBACK_ROLL_BASE: int = 100
const FALLBACK_ROLL_STEP: int = 50
const FALLBACK_UPGRADE_COSTS: Array = [200, 500, 1200, 2500, 5000]
const FALLBACK_MERGE_COST: int = 200
const FALLBACK_REFORGE_COST: int = 500

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

static func is_school(tag: String) -> bool:
	return SCHOOL_ORDER.has(tag)


static func get_school_color(school: String) -> Color:
	return UIConst.BUILD_TAG_COLORS.get(school, UIConst.NO_TAG_COLOR)


static func get_school_mechanic(school: String) -> String:
	var info: Dictionary = SCHOOLS.get(school, {})
	return str(info.get("mechanic", ""))


static func get_mechanism_slots(unit_name: String) -> int:
	return int(MECHANISM_SLOTS.get(unit_name, DEFAULT_MECHANISM_SLOTS))


## 新局重置一个单位的 v6 build 状态：清空机制、按名单重置流派槽上限。
static func reset_unit_build(unit: UnitData) -> void:
	if not unit:
		return
	unit.mechanisms = {}
	unit.max_armor_slots = get_mechanism_slots(unit.unit_name)


static func get_quality_cap(quality: String) -> int:
	return int(QUALITY_CAP.get(quality, 1))


static func get_mechanic_lv_text(school: String, level: int) -> String:
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

static func _ensure_mechanisms(unit: UnitData) -> Dictionary:
	if not unit:
		return {}
	if not (unit.mechanisms is Dictionary):
		unit.mechanisms = {}
	return unit.mechanisms


## 返回 [{school, level, cap, count, color, mechanic, text}, ...]，按 SCHOOL_ORDER 排序
static func get_unit_mechanisms(unit: UnitData) -> Array:
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


static func get_used_mechanism_slots(unit: UnitData) -> int:
	return get_unit_mechanisms(unit).size()


static func has_school(unit: UnitData, school: String) -> bool:
	if not unit:
		return false
	return _ensure_mechanisms(unit).has(school)


static func get_school_level(unit: UnitData, school: String) -> int:
	if not unit:
		return 0
	var mechs: Dictionary = _ensure_mechanisms(unit)
	if not mechs.has(school):
		return 0
	var entry: Dictionary = mechs[school]
	return int(entry.get("level", 0)) if entry is Dictionary else 0


## 战斗单位 / UnitData 的烈焰机制 Lv（战斗层唯一接线口）
static func get_flame_level(unit) -> int:
	if unit == null:
		return 0
	var ud: UnitData = null
	if unit is UnitData:
		ud = unit
	else:
		var stats_variant: Variant = unit.get("unit_stats")
		if stats_variant is UnitData:
			ud = stats_variant
	return get_school_level(ud, "烈焰")


## 烈焰灼烧伤害倍率：Lv1 15% / Lv2 25% / Lv3 35% / Lv4 45%（按攻击力）
static func get_flame_burn_ratio(level: int) -> float:
	if level <= 0:
		return 0.0
	return 0.15 + 0.10 * float(level - 1)


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
		return {"result": "merge", "school": school, "level": level, "cap": new_cap, "replaced": ""}

	var used := mechs.size()
	var slots := get_mechanism_slots(unit.unit_name)
	if used >= slots:
		return {"result": "full", "school": school, "level": 0, "cap": cap, "replaced": ""}

	mechs[school] = {"level": 1, "cap": cap, "count": 1}
	_append_armor_instance(unit, item_id)
	build_changed.emit(unit.unit_name)
	return {"result": "awaken", "school": school, "level": 1, "cap": cap, "replaced": ""}


## 满槽时覆盖某流派：移除被覆盖流派，觉醒新流派。0G。
func overwrite_school(unit: UnitData, school_to_remove: String, item_id: String, quality: String, forced_school: String = "") -> Dictionary:
	if not unit:
		return {"result": "full", "school": "", "level": 0, "replaced": ""}
	var mechs: Dictionary = _ensure_mechanisms(unit)
	var school := forced_school if forced_school != "" else get_school_of_item(item_id)
	if not mechs.has(school_to_remove):
		return apply_armor(unit, item_id, quality, forced_school)
	mechs.erase(school_to_remove)
	build_changed.emit(unit.unit_name)
	var applied := apply_armor(unit, item_id, quality, forced_school)
	applied["replaced"] = school_to_remove
	return applied


## 把防具实例塞进底层 armor_slots（供战斗层读属性 / 词条）。
## 玩家层不操作该数组；满则扩展，永不因物理槽拒绝。
static func _append_armor_instance(unit: UnitData, item_id: String) -> void:
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
static func append_plain_armor(unit: UnitData, item_id: String) -> void:
	_append_armor_instance(unit, item_id)


# ============================================================
#  单位成长：战斗累计经验 → 战后自动升级
# ============================================================

## 升到下一级所需经验（按当前等级递增；目标每局净增 1~2 级）
static func exp_to_next_level(current_level: int) -> int:
	return 60 + maxi(0, current_level - 1) * 40


## 战斗贡献折算经验：胜利基础 + 评级加成
static func battle_exp_reward(node_type: int, rating: String) -> int:
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
static func grant_exp_and_auto_level(unit: UnitData, amount: int) -> int:
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


## 某单位可装备的全部主动技能 id（随机打乱，增加每局变化）
static func _compatible_active_skills(unit_key: String) -> Array:
	var list: Array = []
	for tid in TalentManager._talent_db.keys():
		var data := TalentManager._talent_db[tid] as TalentData
		if data and data.is_active_skill and unit_key in data.compatible_units:
			list.append(str(data.id))
	list.shuffle()
	return list


## 按候选数从少到多排序（单位数很少，O(n²) 选择排序即可，避免 lambda 推断问题）
static func _sorted_by_candidate_count(units: Array, cand: Dictionary) -> Array:
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
static func _match_units_to_skills(units: Array, cand: Dictionary) -> Dictionary:
	var order := _sorted_by_candidate_count(units, cand)
	var best: Dictionary = {}
	var assign: Dictionary = {}
	var used: Dictionary = {}
	_match_bt(order, 0, cand, assign, used, best)
	return best


static func _match_bt(order: Array, idx: int, cand: Dictionary, assign: Dictionary, used: Dictionary, best: Dictionary) -> void:
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


## roll count 次主动技能：先按单位做匹配，保证存在一套"每个单位各得一个可装备技能"的分配，
## 再把这套技能打乱顺序返回。杜绝"roll 出无人能装的技能 → 跳过 → 单位无技能"。
func roll_active_skills(unit_names: Array, count: int = 3) -> Array:
	TalentManager.load_talent_data()
	var units: Array = []
	for uname in unit_names:
		var key := UnitDataManager.normalize_unit_key(str(uname))
		if not units.has(key):
			units.append(key)

	var cand: Dictionary = {}
	for u in units:
		cand[u] = _compatible_active_skills(str(u))

	var assign := _match_units_to_skills(units, cand)
	var result: Array = []
	for u in assign:
		result.append(str(assign[u]))
	result.shuffle()
	if result.size() > count:
		result = result.slice(0, count)
	return result


## 落位安全检查：把 talent_id 给 unit 后，剩余单位是否仍能被剩余技能覆盖。
## remaining_unit_names / remaining_skill_ids 均为尚未落位的单位与技能（含当前这一个）。
static func is_safe_placement(unit: UnitData, talent_id: String, remaining_unit_names: Array, remaining_skill_ids: Array) -> bool:
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


## 某技能对某单位是否可落位（兼容 + 该单位尚未占用第 1 技能格）
static func can_place_skill(unit: UnitData, talent_id: String) -> bool:
	if not unit:
		return false
	var adv := str(unit.advanced_class)
	if not TalentManager.is_talent_compatible_with_unit(talent_id, unit.unit_name, adv):
		return false
	# 第 1 格空 = 未被 roll 技能占用
	return unit.talent_slots.is_empty() or unit.talent_slots[0] == null


## 把 roll 到的主动技能写入单位第 1 格（锁定，不提供互换）
static func place_skill(unit: UnitData, talent_id: String) -> bool:
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


static func get_merge_cost() -> int:
	# 单例方法无法读 _forge，走实例接口；保留静态兜底
	return FALLBACK_MERGE_COST


func get_merge_cost_instance() -> int:
	return int(_forge.get("craft_cost", FALLBACK_MERGE_COST))


func get_reforge_cost() -> int:
	return int(_forge.get("reforge_cost", FALLBACK_REFORGE_COST))


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


## 重铸流派：保留品质与词条，只改流派。返回新的 school。
static func reforge_school(from_school: String) -> String:
	var pool: Array = []
	for s in SCHOOL_ORDER:
		if s != from_school:
			pool.append(s)
	if pool.is_empty():
		return from_school
	return str(pool[randi() % pool.size()])


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
