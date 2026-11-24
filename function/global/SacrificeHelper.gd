class_name SacrificeHelper
extends RefCounted

# ============================================================
#  SacrificeHelper — 熔铸（步 2 改造）
#  熔铸单位 → 产出该职业专属 buff 防具 → 进 pending_forge_rewards
#
#  修改：
#  熔铸单位时，该单位身上已装备的防具也会自动回收到
#  GameState.pending_forge_rewards（待领取区/背包），并清空原防具槽。
# ============================================================

static func get_melt_item_id(unit_name: String) -> String:
	return "melt_" + unit_name


# ============================================================
#  ★ v6.59 献祭赋能（熔铸新机制）
#  不再产出 buff 防具，而是把献祭单位的基础数值加到存活单位上，
#  存活单位"超级化"；献祭单位的装备/技能/流派冻结记录、暂不可用，
#  复活献祭单位时完整还原。
# ============================================================

## 可赋能的基础数值字段（含升级后数值，不含经验/等级——用户方案：经验等级保持不变）
const EMPOWER_STAT_KEYS : Array = [
	"max_hp", "strength", "dexterity", "intelligence", "faith", "move_range",
	"attack", "physical_reduction", "magic_reduction",
	"physical_penetration", "magic_penetration", "static_crit_damage_bonus",
]


## 执行赋能：source=被献祭单位，target=接受赋能的存活单位。
## 返回 {ok, stat_gains, source_key}。
static func empower_unit(source: UnitData, target: UnitData) -> Dictionary:
	var empty := {"ok": false, "stat_gains": {}, "source_key": ""}
	if source == null or target == null or source == target:
		return empty
	if source.is_dead or target.is_dead:
		return empty
	if target.is_empowered:
		return empty   # 已赋能单位不能再次作为接受者（也不能再次献祭，调用方拦截）

	# 1) 记录被献祭单位的完整快照（数值增量 + 被冻结的装备/技能/流派）
	var gains : Dictionary = {}
	for k in EMPOWER_STAT_KEYS:
		gains[k] = source.get(k)
	var snapshot : Dictionary = {
		"unit_name": source.unit_name,
		"display_name": source.display_name,
		"stat_gains": gains.duplicate(true),
		"level": source.level,
		"experience": source.experience,
		"armor_slots": UnitData._item_instance_array_to_array(source.armor_slots),
		"talent_slots": UnitData._talent_instance_array_to_array(source.talent_slots),
		"mechanisms": source.mechanisms.duplicate(true),
		"advanced_class": source.advanced_class,
		"advanced_talent_id": source.advanced_talent_id,
		"max_armor_slots": source.max_armor_slots,
	}
	target.empowerment_source = snapshot
	target.is_empowered = true

	# 2) 基础数值相加（含升级后数值；经验/等级保持不变）
	for k in EMPOWER_STAT_KEYS:
		var add : Variant = gains.get(k, 0)
		if add is int or add is float:
			target.set(k, target.get(k) + add)
	# HP 上限增加时当前 HP 同步增加，避免"超级化但残血"
	target.hit_points = mini(target.max_hp, target.hit_points + int(gains.get("max_hp", 0)))

	# 3) 记录献祭来源（沿用既有 key 机制，便于展示/统计）
	var key : String = UnitData.make_sacrifice_key(source)
	if not target.sacrifice_buff_sources.has(key):
		target.sacrifice_buff_sources.append(key)

	# 4) 冻结被献祭单位的装备/技能/流派（暂不可用，复活时恢复）
	source.armor_slots.clear()
	source.talent_slots.clear()
	source.mechanisms.clear()
	source.advanced_class = ""
	source.advanced_talent_id = ""
	source.advanced_talent_inst = null
	source.is_dead = true
	source.hit_points = 0

	GameState.sacrifice_count += 1
	AnalyticsLogger.record_sacrifice()
	SaveManager.auto_save()

	return {"ok": true, "stat_gains": gains, "source_key": key}


## 还原赋能：复活献祭单位时调用。empowered=被赋能单位，source=被复活的献祭单位。
## 返回是否还原成功。
static func restore_empowerment(empowered: UnitData, source: UnitData) -> bool:
	if empowered == null or source == null:
		return false
	if not empowered.is_empowered or empowered.empowerment_source.is_empty():
		return false
	var snap : Dictionary = empowered.empowerment_source
	# 确认这张快照确实属于要复活的单位
	if str(snap.get("unit_name", "")) != source.unit_name \
			or str(snap.get("display_name", "")) != source.display_name:
		return false

	# 1) 从被赋能单位扣回数值增量
	var gains : Dictionary = snap.get("stat_gains", {})
	for k in EMPOWER_STAT_KEYS:
		var add : Variant = gains.get(k, 0)
		if add is int or add is float:
			empowered.set(k, empowered.get(k) - add)
	empowered.hit_points = mini(empowered.hit_points, empowered.max_hp)
	# 2) 清赋能标记与来源记录
	empowered.is_empowered = false
	empowered.empowerment_source = {}
	var key : String = UnitData.make_sacrifice_key(source)
	empowered.sacrifice_buff_sources.erase(key)

	# 3) 把冻结的装备/技能/流派还原给复活的献祭单位
	var armor_raw : Variant = snap.get("armor_slots", [])
	source.armor_slots = UnitData._array_to_item_instance_array(armor_raw if armor_raw is Array else [])
	var talent_raw : Variant = snap.get("talent_slots", [])
	source.talent_slots = UnitData._array_to_talent_instance_array(talent_raw if talent_raw is Array else [])
	var mech_raw : Variant = snap.get("mechanisms", {})
	source.mechanisms = (mech_raw as Dictionary).duplicate(true) if mech_raw is Dictionary else {}
	source.advanced_class = str(snap.get("advanced_class", ""))
	source.advanced_talent_id = str(snap.get("advanced_talent_id", ""))
	source.max_armor_slots = int(snap.get("max_armor_slots", source.max_armor_slots))
	# 4) 复活
	source.is_dead = false
	source.hit_points = source.max_hp
	SaveManager.auto_save()
	return true


## 查询：某单位是否处于"被赋能"状态（UI 拦截再次献祭/转职用）
static func is_empowered(unit: UnitData) -> bool:
	return unit != null and unit.is_empowered


## ★ 生成熔铸奖励的"数值+词条"说明文本，供确认弹窗展示判断是否值得。
##   item_data 的 description 已由策划写好数值文案（如"攻击 +5，攻击 +20%"），
##   这里再补结构化的减伤/特效，确保玩家一眼看清收益。
static func describe_melt_reward(item_id: String) -> String:
	var data: ItemData = ItemManager.get_item_data(item_id)
	if data == null:
		return "（无数值信息）"
	var lines: Array = []
	# 1) 策划描述（已含核心数值词条）
	if data.description != "":
		lines.append(data.description)
	# 2) 结构化特效（melt_armor_effect）——description 未覆盖的补上
	var eff: Dictionary = data.melt_armor_effect
	if not eff.is_empty():
		var bits: Array = []
		var special_type := str(eff.get("special_type", ""))
		var special_value := float(eff.get("special_value", 0.0))
		if special_type != "" and special_value != 0.0:
			var label := _effect_label(special_type)
			bits.append("%s +%d%%" % [label, int(special_value * 100.0)])
		if not bits.is_empty():
			var extra := " / ".join(bits)
			if lines.is_empty() or not str(lines[0]).contains(extra):
				lines.append(extra)
	# 3) 减伤
	var reductions: Array = []
	if data.physical_reduction > 0.0:
		reductions.append("物减 +%d%%" % int(data.physical_reduction * 100.0))
	if data.magic_reduction > 0.0:
		reductions.append("魔减 +%d%%" % int(data.magic_reduction * 100.0))
	if not reductions.is_empty():
		lines.append(" / ".join(reductions))
	if lines.is_empty():
		return "（该防具无额外数值）"
	return "\n".join(lines)


static func _effect_label(effect_type: String) -> String:
	match effect_type:
		"attack_percent":     return "攻击"
		"attack_flat":        return "攻击"
		"crit_damage_bonus":  return "暴伤"
		"crit_chance":        return "暴击"
		"damage_reduction":   return "减伤"
		"heal_bonus":         return "治疗"
		"lifesteal":          return "吸血"
		"counter_bonus":      return "反击"
		_:                    return effect_type


static func do_sacrifice(_party: Array, unit: UnitData) -> Dictionary:
	if unit == null:
		return {
			"melt_item_id": "",
			"melt_item_name": "",
			"reclaimed_count": 0,
			"reclaimed_item_ids": [],
		}

	# --------------------------------------------------------
	# 1. 先回收该单位已装备的所有防具到待领取区
	#    注意：必须在标记死亡 / 后续同步之前处理，
	#    避免防具仍挂在已死亡单位身上。
	# --------------------------------------------------------
	var reclaimed_count: int = 0
	var reclaimed_item_ids: Array = []

	for i in range(unit.armor_slots.size()):
		var inst = unit.armor_slots[i]
		if inst == null:
			continue

		GameState.pending_forge_rewards.append(inst)
		reclaimed_item_ids.append(inst.item_id)
		unit.armor_slots[i] = null
		reclaimed_count += 1

	# --------------------------------------------------------
	# 2. 标记单位死亡
	# --------------------------------------------------------
	unit.is_dead = true
	unit.hit_points = 0

	GameState.sacrifice_count += 1
	# ★ 数据埋点 — 熔铸
	AnalyticsLogger.record_sacrifice()

	# --------------------------------------------------------
	# 3. 生成该单位的熔铸专属防具
	# --------------------------------------------------------
	var melt_id: String = get_melt_item_id(unit.unit_name)
	var melt_data: ItemData = ItemManager.get_item_data(melt_id)

	if melt_data == null:
		push_warning("[熔铸] 未找到 %s 的熔铸防具 %s，本次不产出防具" % [unit.unit_name, melt_id])
		SaveManager.auto_save()
		return {
			"melt_item_id": "",
			"melt_item_name": "",
			"reclaimed_count": reclaimed_count,
			"reclaimed_item_ids": reclaimed_item_ids,
		}

	var melt_inst: ItemInstance = ItemInstance.new()
	melt_inst.item_id = melt_id
	melt_inst.count = 1
	GameState.pending_forge_rewards.append(melt_inst)

	SaveManager.auto_save()

	return {
		"melt_item_id": melt_id,
		"melt_item_name": melt_data.name,
		"reclaimed_count": reclaimed_count,
		"reclaimed_item_ids": reclaimed_item_ids,
	}
