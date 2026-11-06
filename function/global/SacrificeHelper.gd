class_name SacrificeHelper
extends RefCounted

# ============================================================
#  SacrificeHelper — 熔铸（步 2 改造）
#  熔铸单位 → 产出该职业专属 buff 防具 → 进 pending_forge_rewards
#  ============================================================

static func get_melt_item_id(unit_name: String) -> String:
	return "melt_" + unit_name


static func do_sacrifice(_party: Array, unit: UnitData) -> Dictionary:
	unit.is_dead = true
	unit.hit_points = 0

	GameState.sacrifice_count += 1
	# ★ 数据埋点 — 熔铸
	AnalyticsLogger.record_sacrifice()

	var melt_id : String = get_melt_item_id(unit.unit_name)
	var melt_data : ItemData = ItemManager.get_item_data(melt_id)
	if melt_data == null:
		push_warning("[熔铸] 未找到 %s 的熔铸防具 %s，本次不产出防具" % [unit.unit_name, melt_id])
		SaveManager.auto_save()
		return {
			"melt_item_id": "",
			"melt_item_name": "",
		}

	var inst : ItemInstance = ItemInstance.new()
	inst.item_id = melt_id
	inst.count = 1
	GameState.pending_forge_rewards.append(inst)

	SaveManager.auto_save()

	return {
		"melt_item_id": melt_id,
		"melt_item_name": melt_data.name,
	}
