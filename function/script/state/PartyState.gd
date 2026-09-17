class_name PartyState
extends RefCounted

const MAX_PASSIVE_SLOTS : int = 4

# ---- 队伍 ----
var party : Array[UnitData] = []
var max_party_size : int = 3
var main_unit_name : String = ""
var main_unit_index : int = 0
var current_faction : String = ""

# ---- 被动槽（遗物 + 精炼，共 4 格） ----
# 元素：null / ItemInstance（遗物）/ Dictionary {"refine_id": "xxx", "count": 1}
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
	for i in range(min(party.size(), battle_units.size())):
		var battle_unit = battle_units[i]
		var party_unit = party[i]
		party_unit.hit_points = battle_unit.hit_points
		party_unit.weapon_slot = battle_unit.weapon_slot
		party_unit.armor_slots = battle_unit.armor_slots.duplicate()
		party_unit.max_armor_slots = battle_unit.max_armor_slots

# ============================================================
#  被动槽
# ============================================================
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
	if idx < 0 or idx >= MAX_PASSIVE_SLOTS:
		return
	_ensure_passive_size()
	equipped_passives[idx] = value

func remove_passive_at_slot(idx: int):
	set_passive_at_slot(idx, null)

func is_passive_full() -> bool:
	for p in get_passives():
		if p == null:
			return false
	return true

# ---- 加遗物（找第一个空槽） ----
func add_relic_to_passive_slot(inst: ItemInstance) -> bool:
	_ensure_passive_size()
	for i in range(MAX_PASSIVE_SLOTS):
		if equipped_passives[i] == null:
			equipped_passives[i] = inst
			return true
	return false

# ---- 加精炼（找第一个空槽） ----
func add_refine_to_passive_slot(refine_id: String) -> bool:
	_ensure_passive_size()
	for i in range(MAX_PASSIVE_SLOTS):
		if equipped_passives[i] == null:
			equipped_passives[i] = {"refine_id": refine_id, "count": 1}
			return true
	return false

# ---- 过滤：只取遗物 ----
func get_relics_from_passives() -> Array:
	var result = []
	for p in get_passives():
		if p is ItemInstance:
			result.append(p)
	return result

# ---- 过滤：只取精炼 ----
func get_refines_from_passives() -> Array:
	var result = []
	for p in get_passives():
		if p is Dictionary and p.has("refine_id"):
			result.append(p)
	return result

# ---- 清空所有精炼（战斗后调用） ----
func clear_refine_passives():
	_ensure_passive_size()
	for i in range(MAX_PASSIVE_SLOTS):
		var p = equipped_passives[i]
		if p is Dictionary and p.has("refine_id"):
			equipped_passives[i] = null
