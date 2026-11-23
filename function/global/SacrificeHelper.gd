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
