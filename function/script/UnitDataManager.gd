class_name UnitDataManager
extends RefCounted

# ---- 武器类型常量 ----
const WEAPON_SWORD = 0
const WEAPON_SPEAR = 1
const WEAPON_AXE = 2
const WEAPON_BOW = 3
const WEAPON_MAGIC = 4
const WEAPON_HEAL = 5
const WEAPON_DRAGONSTONE = 6

# ---- 武器命中补正 ----
const WEAPON_HIT = {
	WEAPON_SWORD: 80,
	WEAPON_SPEAR: 70,
	WEAPON_AXE: 60,
	WEAPON_BOW: 80,
	WEAPON_MAGIC: 70,
	WEAPON_HEAL: 0,
	WEAPON_DRAGONSTONE: 70
}

# ---- 武器暴击补正 ----
const WEAPON_CRIT = {
	WEAPON_SWORD: 5,
	WEAPON_SPEAR: 3,
	WEAPON_AXE: 2,
	WEAPON_BOW: 0,
	WEAPON_MAGIC: 3,
	WEAPON_HEAL: 0,
	WEAPON_DRAGONSTONE: 3
}

# ---- 武器类别显示名称映射 ----
const WEAPON_CATEGORY_DISPLAY = {
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

# ---- 显示格式常量 ----
const DISPLAY_SEPARATOR = "|"

# ---- 单位职业枚举 ----
enum UnitClass {
	SWORDSMAN,
	SPEARMAN,
	AXEMAN,
	ARCHER,
	PEGASUS,
	MAGE,
	CLERIC,
	DRAGONBORN,
	ARMORED
}

# ---- 职业数据统一配置 ----
const UNIT_CLASS_DATA = {
	"剑士": {
		"default_weapon": "iron_sword",
		"allowed_categories": ["sword"],
		"class_enum": UnitClass.SWORDSMAN
	},
	"枪兵": {
		"default_weapon": "steel_spear",
		"allowed_categories": ["spear", "sword"],
		"class_enum": UnitClass.SPEARMAN
	},
	"斧兵": {
		"default_weapon": "battle_axe",
		"allowed_categories": ["axe"],
		"class_enum": UnitClass.AXEMAN
	},
	"弓兵": {
		"default_weapon": "longbow",
		"allowed_categories": ["bow", "crossbow"],
		"class_enum": UnitClass.ARCHER
	},
	"飞马": {
		"default_weapon": "steel_spear",
		"allowed_categories": ["spear", "sword"],
		"class_enum": UnitClass.PEGASUS
	},
	"法师": {
		"default_weapon": "fire_spellbook",
		"allowed_categories": ["spellbook"],
		"class_enum": UnitClass.MAGE
	},
	"修女": {
		"default_weapon": "healing_staff",
		"allowed_categories": ["staff"],
		"class_enum": UnitClass.CLERIC
	},
	"龙人": {
		"default_weapon": "fire_dragonstone",
		"allowed_categories": ["dragonstone"],
		"class_enum": UnitClass.DRAGONBORN
	},
	"重甲兵": {
		"default_weapon": "iron_sword",
		"allowed_categories": ["sword", "spear"],
		"class_enum": UnitClass.ARMORED
	}
}

# ---- 静态数据缓存 ----
static var _unit_data_cache: Dictionary = {}
static var _data_loaded: bool = false
static var _default_data: Dictionary = {
	"max_hp": 20,
	"strength": 5,
	"magic_attack": 0,
	"magic_defense": 0,
	"defense": 0,
	"move_range": 5,
	"weapon_type": WEAPON_SWORD,
	"skill": 3,
	"speed": 4,
	"luck": 0,
	"attack_range": 1,
	"min_attack_range": 1,
	"ignore_terrain_cost": false,
	"sprite_frames_path": ""
}

# ============================================================
#  JSON 加载
# ============================================================
static func _load_unit_data():
	if _data_loaded:
		return
	_data_loaded = true
	var path = Config.PATHS.UNIT_DATA
	if not FileAccess.file_exists(path):
		push_error("单位数据 JSON 文件不存在: ", path)
		_unit_data_cache = {}
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("JSON 解析失败，使用空数据")
		_unit_data_cache = {}
		return
	_unit_data_cache = data

# ============================================================
#  数据查询
# ============================================================
static func get_unit_data(unit_name: String) -> Dictionary:
	_load_unit_data()
	return _unit_data_cache.get(unit_name, _default_data.duplicate())

static func get_sprite_frames_path(unit_name: String) -> String:
	return get_unit_data(unit_name).get("sprite_frames_path", "")

static func get_default_stats(unit_name: String) -> UnitData:
	var data = UnitData.new()
	var dict = get_unit_data(unit_name)
	data.max_hp = dict["max_hp"]
	data.defense = dict["defense"]
	data.magic_defense = dict["magic_defense"]
	data.move_range = dict["move_range"]
	data.skill = dict["skill"]
	data.speed = dict["speed"]
	data.luck = dict["luck"]
	data.ignore_terrain_cost = dict.get("ignore_terrain_cost", false)
	return data

static func get_weapon_category_display(category: String) -> String:
	return WEAPON_CATEGORY_DISPLAY.get(category, category)

# ============================================================
#  职业相关（用于特殊攻击识别）
# ============================================================
static func get_unit_class(unit_name: String) -> int:
	var data = UNIT_CLASS_DATA.get(unit_name)
	return data.class_enum if data else -1

static func get_default_weapon_id(unit_name: String) -> String:
	var data = UNIT_CLASS_DATA.get(unit_name)
	return data.default_weapon if data else ""

static func get_allowed_weapon_categories(unit_name: String) -> Array[String]:
	var data = UNIT_CLASS_DATA.get(unit_name)
	if data:
		return data.allowed_categories.duplicate() as Array[String]
	return [] as Array[String]

static func is_unit_class(unit_name: String, target_class: int) -> bool:
	return get_unit_class(unit_name) == target_class

# ============================================================
#  显示名称
# ============================================================
static func get_display_name(unit_name: String) -> String:
	var data = get_unit_data(unit_name)
	var display_name = data.get("display_name", unit_name)
	var faction = data.get("faction", "")
	if faction == "":
		faction = "无"
	return "%s%s%s%s%s" % [display_name, DISPLAY_SEPARATOR, faction, DISPLAY_SEPARATOR, unit_name]

static func get_display_name_from_unit(unit: Unit) -> String:
	var display_name = unit.unit_stats.display_name if unit.unit_stats.display_name != "" else unit.unit_stats.unit_name
	var faction = unit.unit_stats.faction if unit.unit_stats.faction != "" else "无"
	return "%s%s%s%s%s" % [display_name, DISPLAY_SEPARATOR, faction, DISPLAY_SEPARATOR, unit.unit_stats.unit_name]
