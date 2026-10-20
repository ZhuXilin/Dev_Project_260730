extends Node

# ★ 现在完全作为路由分发器，数据散落在各个 Manager 中
func get_flavor(category: String, id: String) -> String:
	match category:
		"units":
			return str(UnitDataManager.get_unit_data(id).get("flavor", ""))
		"items":
			var item = ItemManager.get_item_data(id)
			return item.flavor if item else ""
		"relics":
			return str(RelicManager.get_relic_data(id).get("flavor", ""))
		"talents":
			var tdata = TalentManager.get_talent_data(id)
			return tdata.flavor if tdata else ""
		"auras":
			return str(AuraManager.get_aura(id).get("flavor", ""))
	return ""

func is_narrative_mode() -> bool:
	return Globals.info_mode == Globals.InfoMode.NARRATIVE
