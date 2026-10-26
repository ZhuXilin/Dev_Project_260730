class_name PartyState
extends RefCounted

const MAX_PASSIVE_SLOTS : int = 4

var party : Array[UnitData] = []
var max_party_size : int = 3
var main_unit_name : String = ""
var main_unit_index : int = 0
var current_faction : String = ""

var equipped_passives : Array = []

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
	var battle_map : Dictionary = {}
	for bu in battle_units:
		if bu == null or not is_instance_valid(bu): continue
		var key = "%s|%s" % [bu.unit_stats.unit_name, bu.unit_stats.display_name]
		battle_map[key] = bu
	for party_unit in party:
		var key = "%s|%s" % [party_unit.unit_name, party_unit.display_name]
		if battle_map.has(key):
			var bu = battle_map[key]
			party_unit.hit_points = bu.hit_points
			party_unit.weapon_slot = bu.weapon_slot
			party_unit.armor_slots = bu.armor_slots.duplicate()
			party_unit.max_armor_slots = bu.max_armor_slots
		else:
			party_unit.hit_points = 0
			party_unit.is_dead = true

func init_passive_slots():
	equipped_passives.clear()
	for i in range(MAX_PASSIVE_SLOTS):
		equipped_passives.append(null)

func _ensure_passive_size():
	while equipped_passives.size() < MAX_PASSIVE_SLOTS:
		equipped_passives.append(null)
	while equipped_passives.size() > MAX_PASSIVE_SLOTS:
		equipped_passives.pop_back()

func get_passives() -> Array:
	_ensure_passive_size()
	return equipped_passives

func set_passive_at_slot(idx: int, value):
	if idx < 0 or idx >= MAX_PASSIVE_SLOTS: return
	_ensure_passive_size()
	equipped_passives[idx] = value

func remove_passive_at_slot(idx: int):
	set_passive_at_slot(idx, null)

func is_passive_full() -> bool:
	for p in get_passives():
		if p == null: return false
	return true

func add_relic_to_passive_slot(inst: ItemInstance) -> bool:
	_ensure_passive_size()
	for i in range(MAX_PASSIVE_SLOTS):
		if equipped_passives[i] == null:
			equipped_passives[i] = inst
			return true
	return false

func get_relics_from_passives() -> Array:
	var result = []
	for p in get_passives():
		if p is ItemInstance:
			result.append(p)
	return result

# ★ 光环占被动槽
func add_aura_to_passive_slot(aura_id: String) -> bool:
	if aura_id == "": return false
	_ensure_passive_size()
	for i in range(MAX_PASSIVE_SLOTS):
		var p : Variant = equipped_passives[i]
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aura_id:
			return false
	for i in range(MAX_PASSIVE_SLOTS):
		if equipped_passives[i] == null:
			equipped_passives[i] = {"type": "aura", "aura_id": aura_id}
			return true
	return false

func get_auras_from_passives() -> Array:
	var result : Array = []
	for p in get_passives():
		if p is Dictionary and p.get("type", "") == "aura":
			var aid : String = p.get("aura_id", "")
			if aid != "": result.append(aid)
	return result

func is_aura_equipped(aura_id: String) -> bool:
	if aura_id == "": return false
	for p in get_passives():
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aura_id:
			return true
	return false

func remove_aura_from_passives(aura_id: String) -> bool:
	if aura_id == "": return false
	for i in range(MAX_PASSIVE_SLOTS):
		var p : Variant = equipped_passives[i]
		if p is Dictionary and p.get("type", "") == "aura" and p.get("aura_id", "") == aura_id:
			equipped_passives[i] = null
			return true
	return false
