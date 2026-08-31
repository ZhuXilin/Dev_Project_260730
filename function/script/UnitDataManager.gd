class_name UnitDataManager
extends RefCounted

# ---- 武器类别显示名称映射 ----
static var _weapon_category_display: Dictionary = {
	"sword": "剑",
	"spear": "枪",
	"axe": "斧",
	"bow": "弓",
	"shield": "盾",
	"crossbow": "弩",
	"staff": "法杖",
	"spellbook": "魔法书",
	"dragonstone": "龙石"
}

static var _unit_data_cache: Dictionary = {}
static var _data_loaded: bool = false

static func _load_unit_data():
	if _data_loaded:
		return
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

static func get_unit_data(unit_name: String) -> Dictionary:
	_load_unit_data()
	return _unit_data_cache.get(unit_name, {})

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

static func get_display_name(unit_name: String) -> String:
	var data = get_unit_data(unit_name)
	return data.get("display_name", unit_name)

static func get_faction(unit_name: String) -> String:
	return get_unit_data(unit_name).get("faction", "")

static func get_description(unit_name: String) -> String:
	return get_unit_data(unit_name).get("description", "")

static func get_weapon_category_display(category: String) -> String:
	return _weapon_category_display.get(category, category)

static func create_unit_data(unit_name: String) -> UnitData:
	var dict = get_unit_data(unit_name)
	var data = get_default_stats(unit_name)
	data.unit_name = unit_name
	data.display_name = dict.get("display_name", unit_name)
	data.faction = dict.get("faction", "")
	data.team_id = 0
	data.experience = 0
	data.level = 1
	
	var default_weapon = get_default_weapon_id(unit_name)
	if default_weapon != "":
		var inst = ItemInstance.new()
		inst.item_id = default_weapon
		inst.count = 1
		data.weapon_slot = inst
	
	data.armor_slots = [null, null]
	data.max_armor_slots = 2
	return data

static func get_display_name_from_unit(unit: Unit) -> String:
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var faction = unit.unit_stats.faction if unit.unit_stats.faction != "" else "无"
	return "%s|%s|%s" % [display_name, faction, unit.unit_stats.unit_name]
