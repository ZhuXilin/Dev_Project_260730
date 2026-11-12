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
