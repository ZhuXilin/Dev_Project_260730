class_name UnitDataManager
extends RefCounted

static var GROWTH_HP_PER_POINT : int = 1
static var _growth_loaded : bool = false

static func _ensure_growth_config():
	if _growth_loaded: return
	_growth_loaded = true
	GROWTH_HP_PER_POINT = int(GameConfigManager.get_value("progression_config.json", "growth_hp_per_point", 1))


static var _weapon_category_display: Dictionary = {
	"sword": "剑", "spear": "枪", "axe": "斧", "bow": "弓",
	"shield": "盾", "crossbow": "弩", "staff": "法杖",
	"spellbook": "魔法书", "dragonstone": "龙石"
}

static var _unit_display_name: Dictionary = {
	"swordsman": "剑士", "spearman": "枪兵", "axeman": "斧兵",
	"archer": "弓兵", "pegasus": "飞马", "mage": "法师",
	"cleric": "修女", "dragonborn": "龙人", "armored": "重甲兵"
}

static var _cn_to_en_unit: Dictionary = {
	"剑士": "swordsman", "枪兵": "spearman", "斧兵": "axeman",
	"弓兵": "archer", "飞马": "pegasus", "法师": "mage",
	"修女": "cleric", "龙人": "dragonborn", "重甲兵": "armored"
}

static var _unit_data_cache: Dictionary = {}
static var _data_loaded: bool = false


static func _load_unit_data():
	if _data_loaded: return
	_data_loaded = true
	var path = Config.PATHS.UNIT_DATA
	if not FileAccess.file_exists(path):
		push_error("单位数据 JSON 文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("JSON 解析失败")
		return
	_unit_data_cache = data


static func _normalize_unit_key(unit_name: String) -> String:
	return _cn_to_en_unit.get(unit_name, unit_name)


static func normalize_unit_key(unit_name: String) -> String:
	return _normalize_unit_key(unit_name)


static func get_unit_data(unit_name: String) -> Dictionary:
	_load_unit_data()
	var key = _normalize_unit_key(unit_name)
	return _unit_data_cache.get(key, {})


static func get_all_unit_data() -> Dictionary:
	_load_unit_data()
	return _unit_data_cache


static func get_sprite_frames_path(unit_name: String) -> String:
	return get_unit_data(unit_name).get("sprite_frames_path", "")


static func get_default_stats(unit_name: String) -> UnitData:
	var dict = get_unit_data(unit_name)
	var data = UnitData.new()
	data.max_hp = dict.get("max_hp", 20)
	data.strength = dict.get("strength", 5)
	data.dexterity = dict.get("dexterity", 5)
	data.intelligence = dict.get("intelligence", 3)
	data.faith = dict.get("faith", 3)
	data.arcane = dict.get("arcane", 3)
	data.move_range = dict.get("move_range", 5)
	data.ignore_terrain_cost = dict.get("ignore_terrain_cost", false)
	return data


static func get_default_weapon_id(unit_name: String) -> String:
	return get_unit_data(unit_name).get("default_weapon", "")


static func get_sacrifice_buff(unit_name: String) -> Dictionary:
	return get_unit_data(unit_name).get("sacrifice_buff", {})


static func get_sacrifice_buff_display(unit_name: String) -> String:
	var buff : Dictionary = get_sacrifice_buff(unit_name)
	if buff.is_empty(): return ""
	return buff.get("display", "")


static func get_display_name(unit_name: String) -> String:
	var key = _normalize_unit_key(unit_name)
	var data = get_unit_data(key)
	if data.is_empty():
		return _unit_display_name.get(key, key)
	var display = data.get("display_name", "")
	if display == "":
		display = _unit_display_name.get(key, key)
	return display


static func get_display_name_full(unit_name: String) -> String:
	var key = _normalize_unit_key(unit_name)
	var data = get_unit_data(key)
	if data.is_empty():
		return unit_name + "|未知|未知"
	var display = data.get("display_name", "")
	if display == "":
		display = _unit_display_name.get(key, key)
	var faction = data.get("faction", "无")
	var type_name = _unit_display_name.get(key, key)
	return "%s|%s|%s" % [display, faction, type_name]


static func get_faction(unit_name: String) -> String:
	return get_unit_data(unit_name).get("faction", "")


static func get_description(unit_name: String) -> String:
	return get_unit_data(unit_name).get("description", "")


static func get_weapon_category_display(category: String) -> String:
	return _weapon_category_display.get(category, category)


static func get_all_unit_ids() -> Array:
	_load_unit_data()
	var ids : Array = []
	for key in _unit_data_cache.keys():
		ids.append(key)
	ids.sort()
	return ids


# ============================================================
#  创建单位（完整函数）
# ============================================================
static func create_unit_data(unit_name: String) -> UnitData:
	var key = _normalize_unit_key(unit_name)
	var dict = get_unit_data(key)
	var data = get_default_stats(key)
	data.unit_name = key
	data.display_name = dict.get("display_name", "")
	if data.display_name == "":
		data.display_name = _unit_display_name.get(key, key)
	data.faction = dict.get("faction", "")
	data.team_id = 0
	data.experience = 0
	data.level = 1

	# ★ 批次 2：单位标签
	data.tags.clear()
	var tags_raw : Variant = dict.get("tags", [])
	if tags_raw is Array:
		for t in tags_raw:
			if t is String:
				data.tags.append(t)

	# ★ 方向 7：单位核心特性
	data.core_trait = dict.get("core_trait", "")

	# 默认武器
	var default_weapon = get_default_weapon_id(key)
	if default_weapon != "":
		var inst = ItemInstance.new()
		inst.item_id = default_weapon
		inst.count = 1
		# ★ 应用武器升级（批次 5B 局外武器升级）
		if GameState.unit_growth.has(key):
			var lv : int = int(GameState.unit_growth[key].get("weapon_lv_" + default_weapon, 0))
			inst.upgrade_level = lv
		data.weapon_slot = inst

	# 默认特技
	data.talent_slots.clear()
	var default_talents = dict.get("default_talents", [])
	var talent_cap : int = int(dict.get("max_talent_slots", 1))
	for talent_id in default_talents:
		if data.talent_slots.size() >= talent_cap:
			break
		var talent_inst = TalentInstance.new()
		talent_inst.talent_id = talent_id
		talent_inst.current_stack = 0
		talent_inst.is_active = true
		var tdata = TalentManager.get_talent_data(talent_id)
		if tdata and tdata.is_active_skill:
			talent_inst.is_ready = true
			talent_inst.cooldown_remaining = 0
		else:
			talent_inst.is_ready = false
		data.talent_slots.append(talent_inst)
	while data.talent_slots.size() < talent_cap:
		data.talent_slots.append(null)

	data.armor_slots = [null, null]
	data.max_armor_slots = 2
	data.max_talent_slots = talent_cap

	# ★ 批次 4：应用属性加点
	_apply_attr_points_to_unit(key, data)
	return data


static func _apply_attr_points_to_unit(unit_key: String, data: UnitData):
	var points_dict : Dictionary = GameState.unit_attr_points.get(unit_key, {})
	if points_dict.is_empty():
		return
	for attr_key in points_dict:
		var pts : int = int(points_dict[attr_key])
		if pts <= 0: continue
		_apply_one_attr(data, attr_key, pts)
	print("[加点] %s 已应用：%s" % [unit_key, points_dict])


static func _apply_one_attr(data: UnitData, attr_key: String, amount: int):
	match attr_key:
		"vitality":
			data.max_hp += amount
			data.hit_points += amount
		"strength":     data.strength += amount
		"dexterity":    data.dexterity += amount
		"intelligence": data.intelligence += amount
		"faith":        data.faith += amount
		"arcane":       data.arcane += amount
		"move_range":   data.move_range += amount


# ============================================================
#  辅助（批次 4）
# ============================================================
static func get_total_attr_points(unit_key: String) -> int:
	var total : int = 0
	var d : Dictionary = GameState.unit_attr_points.get(unit_key, {})
	for k in d:
		total += int(d[k])
	return total


static func get_attr_points_for(unit_key: String, attr_key: String) -> int:
	var d : Dictionary = GameState.unit_attr_points.get(unit_key, {})
	return int(d.get(attr_key, 0))


static func get_attr_cap(unit_key: String) -> int:
	const LEVELS : Array[int] = [0, 2, 5, 8, 12, 16, 20, 25]
	var lv : int = int(GameState.unit_attr_cap.get(unit_key, 0))
	return LEVELS[clampi(lv, 0, LEVELS.size() - 1)]


static func get_display_name_from_unit(unit: Unit) -> String:
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var faction = unit.unit_stats.faction if unit.unit_stats.faction != "" else "无"
	return "%s|%s|%s" % [display_name, faction, unit.unit_stats.unit_name]


static func get_unit_type_display_name(unit_name: String) -> String:
	var key = _normalize_unit_key(unit_name)
	return _unit_display_name.get(key, key)


static func apply_growth(stats: UnitData, unit_type: String) -> void:
	if GameState.unit_growth.is_empty(): return
	if not GameState.unit_growth.has(unit_type): return
	var g = GameState.unit_growth[unit_type]
	stats.max_hp += int(g.get("vitality", 0)) * GROWTH_HP_PER_POINT
	stats.strength += int(g.get("strength", 0))
	stats.dexterity += int(g.get("dexterity", 0))
	stats.intelligence += int(g.get("intelligence", 0))
	stats.faith += int(g.get("faith", 0))
	stats.arcane += int(g.get("arcane", 0))
