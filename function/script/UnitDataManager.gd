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

# ---- 单位中文名映射（英文→中文） ----
static var _unit_display_name: Dictionary = {
	"swordsman": "剑士",
	"spearman": "枪兵",
	"axeman": "斧兵",
	"archer": "弓兵",
	"pegasus": "飞马",
	"mage": "法师",
	"cleric": "修女",
	"dragonborn": "龙人",
	"armored": "重甲兵"
}

# ---- 中文→英文映射（用于兼容中文输入/旧存档） ----
static var _cn_to_en_unit: Dictionary = {
	"剑士": "swordsman",
	"枪兵": "spearman",
	"斧兵": "axeman",
	"弓兵": "archer",
	"飞马": "pegasus",
	"法师": "mage",
	"修女": "cleric",
	"龙人": "dragonborn",
	"重甲兵": "armored"
}

static var _unit_data_cache: Dictionary = {}
static var _data_loaded: bool = false


# ============================================================
#  数据加载
# ============================================================

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


# ============================================================
#  核心数据查询
# ============================================================

# ---- 规范化单位键名（中文→英文） ----
static func _normalize_unit_key(unit_name: String) -> String:
	return _cn_to_en_unit.get(unit_name, unit_name)


static func get_unit_data(unit_name: String) -> Dictionary:
	_load_unit_data()
	var key = _normalize_unit_key(unit_name)
	return _unit_data_cache.get(key, {})


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


# ============================================================
#  显示名称（用于UI）
# ============================================================

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


# ============================================================
#  单位数据创建
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
	
	var default_weapon = get_default_weapon_id(key)
	if default_weapon != "":
		var inst = ItemInstance.new()
		inst.item_id = default_weapon
		inst.count = 1
		data.weapon_slot = inst
	
	data.armor_slots = [null, null]
	data.max_armor_slots = 2
	return data


# ============================================================
#  从Unit实例获取显示信息
# ============================================================

static func get_display_name_from_unit(unit: Unit) -> String:
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var faction = unit.unit_stats.faction if unit.unit_stats.faction != "" else "无"
	return "%s|%s|%s" % [display_name, faction, unit.unit_stats.unit_name]
