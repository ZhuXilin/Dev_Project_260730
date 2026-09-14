class_name PartyState
extends RefCounted

const MAX_RELIC_SLOTS : int = 3

# ---- 队伍 ----
var party : Array[UnitData] = []
var max_party_size : int = 3
var main_unit_name : String = ""
var main_unit_index : int = 0
var current_faction : String = ""

# ---- 遗物槽 ----
var global_relics : Array = []   # Array[ItemInstance] / null

func initialize_party(selected_units: Array[String], main_index: int):
	party.clear()
	for unit_name in selected_units:
		party.append(UnitDataManager.create_unit_data(unit_name))
	main_unit_index = main_index
	main_unit_name = selected_units[main_index] if selected_units.size() > main_index else ""

func get_party_units() -> Array[UnitData]:
	return party

func get_main_unit() -> UnitData:
	if party.size() > main_unit_index:
		return party[main_unit_index]
	return null

func sync_units_from_battlefield(battle_units: Array):
	for i in range(min(party.size(), battle_units.size())):
		var battle_unit = battle_units[i]
		var party_unit = party[i]
		party_unit.hit_points = battle_unit.hit_points
		party_unit.weapon_slot = battle_unit.weapon_slot
		party_unit.armor_slots = battle_unit.armor_slots.duplicate()
		party_unit.max_armor_slots = battle_unit.max_armor_slots

# ---- 遗物 ----
func init_relic_slots():
	global_relics.clear()
	for i in range(MAX_RELIC_SLOTS):
		global_relics.append(null)

func add_global_relic(instance: ItemInstance) -> bool:
	while global_relics.size() < MAX_RELIC_SLOTS:
		global_relics.append(null)
	for i in range(MAX_RELIC_SLOTS):
		if global_relics[i] == null:
			global_relics[i] = instance
			return true
	return false

func remove_global_relic_at_slot(slot_idx: int):
	if slot_idx >= 0 and slot_idx < global_relics.size():
		global_relics[slot_idx] = null

func get_global_relics() -> Array:
	return global_relics.duplicate()

func get_active_relics() -> Array:
	var result = []
	for r in global_relics:
		if r != null:
			result.append(r)
	return result
