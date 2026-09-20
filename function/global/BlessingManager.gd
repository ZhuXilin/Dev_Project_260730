class_name BlessingManager
extends RefCounted

const BLESSINGS : Array = [
	{
		"id": "blessing_vitality",
		"name": "生命祝福",
		"attr": "vitality",
		"attr_display": "最大HP",
		"levels": [1, 2, 3],
		"costs": [50, 200, 800],
	},
	{
		"id": "blessing_strength",
		"name": "力量祝福",
		"attr": "strength",
		"attr_display": "力量",
		"levels": [1, 2, 3],
		"costs": [50, 200, 800],
	},
	{
		"id": "blessing_dexterity",
		"name": "灵巧祝福",
		"attr": "dexterity",
		"attr_display": "灵巧",
		"levels": [1, 2, 3],
		"costs": [50, 200, 800],
	},
	{
		"id": "blessing_intelligence",
		"name": "智力祝福",
		"attr": "intelligence",
		"attr_display": "智力",
		"levels": [1, 2, 3],
		"costs": [50, 200, 800],
	},
	{
		"id": "blessing_faith",
		"name": "信仰祝福",
		"attr": "faith",
		"attr_display": "信仰",
		"levels": [1, 2, 3],
		"costs": [50, 200, 800],
	},
	{
		"id": "blessing_arcane",
		"name": "感应祝福",
		"attr": "arcane",
		"attr_display": "感应",
		"levels": [1, 2, 3],
		"costs": [50, 200, 800],
	},
]

const MAX_LEVEL : int = 3


static func get_all() -> Array:
	return BLESSINGS


static func get_blessing(blessing_id: String) -> Dictionary:
	for b in BLESSINGS:
		if b["id"] == blessing_id:
			return b
	return {}


static func get_available_for_unit(unit_type: String) -> Array:
	var key : String = UnitDataManager.normalize_unit_key(unit_type)
	var dict : Dictionary = UnitDataManager.get_unit_data(key)
	var avail : Array = dict.get("available_blessings", [])
	var result : Array = []
	for b in BLESSINGS:
		if b["attr"] in avail:
			result.append(b)
	return result


static func get_level(unit_type: String, blessing_id: String) -> int:
	var key : String = UnitDataManager.normalize_unit_key(unit_type)
	var dict : Dictionary = GameState.unit_blessings.get(key, {})
	return int(dict.get(blessing_id, 0))


static func get_bonus(unit_type: String, blessing_id: String) -> int:
	var b : Dictionary = get_blessing(blessing_id)
	if b.is_empty():
		return 0
	var lv : int = get_level(unit_type, blessing_id)
	if lv <= 0:
		return 0
	var levels : Array = b["levels"]
	return int(levels[clampi(lv - 1, 0, levels.size() - 1)])


static func get_next_cost(unit_type: String, blessing_id: String) -> int:
	var b : Dictionary = get_blessing(blessing_id)
	if b.is_empty():
		return -1
	var lv : int = get_level(unit_type, blessing_id)
	if lv >= MAX_LEVEL:
		return -1
	var costs : Array = b["costs"]
	return int(costs[lv])


static func can_upgrade(unit_type: String, blessing_id: String) -> bool:
	var cost : int = get_next_cost(unit_type, blessing_id)
	if cost < 0:
		return false
	return GameState.soul >= cost


static func upgrade(unit_type: String, blessing_id: String) -> bool:
	if not can_upgrade(unit_type, blessing_id):
		return false
	var cost : int = get_next_cost(unit_type, blessing_id)
	var key : String = UnitDataManager.normalize_unit_key(unit_type)
	GameState.soul -= cost
	if not GameState.unit_blessings.has(key):
		GameState.unit_blessings[key] = {}
	var cur : int = int(GameState.unit_blessings[key].get(blessing_id, 0))
	GameState.unit_blessings[key][blessing_id] = cur + 1
	return true


static func get_blessing_rank(unit_type: String) -> int:
	var total : int = 0
	for b in BLESSINGS:
		total += get_level(unit_type, b["id"])
	return total


static func get_max_blessing_rank(unit_type: String) -> int:
	var avail : Array = get_available_for_unit(unit_type)
	return avail.size() * MAX_LEVEL


static func apply_to_unit_data(unit_type: String, data: UnitData) -> void:
	for b in BLESSINGS:
		var attr : String = b["attr"]
		var bonus : int = get_bonus(unit_type, b["id"])
		if bonus == 0:
			continue
		match attr:
			"vitality":
				data.max_hp += bonus
				data.hit_points += bonus
			"strength":     data.strength += bonus
			"dexterity":    data.dexterity += bonus
			"intelligence": data.intelligence += bonus
			"faith":        data.faith += bonus
			"arcane":       data.arcane += bonus
