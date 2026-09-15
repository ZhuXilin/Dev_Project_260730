extends Resource
class_name SaveData

const CURRENT_VERSION = 3

@export var save_version: int = CURRENT_VERSION

@export var unlocked_units: Array = []
@export var unlocked_items: Array = []
@export var unlocked_relics: Array = []

@export var music_volume: float = 0.2
@export var sound_volume: float = 0.2
@export var game_speed: int = 0
@export var window_mode: int = 0
@export var window_size: Vector2i = Vector2i(640, 480)

# ---- 游戏进度 ----
@export var current_day: int = 1
@export var visited_nodes: Array = []
@export var selected_node_id: String = ""
@export var main_unit_name: String = ""
@export var current_node_key: String = ""

@export var soul: int = 0
@export var cycle_start_soul: int = 0
@export var cycle_start_materials: Dictionary = {}
@export var temp_soul: int = 0
@export var temp_gold: int = 0

# ---- 单位属性成长（魂之祭坛） ----
@export var unit_growth: Dictionary = {}

@export var talent_exp: Dictionary = {}

@export var materials: Dictionary = {
	"粗铁": 0,
	"精钢": 0,
	"秘银": 0,
	"龙鳞": 0
}

@export var unlocked_armors: Array = []
@export var unlocked_stories: Array = []

@export var attribute_points: Dictionary = {
	"strength": 0,
	"dexterity": 0,
	"intelligence": 0,
	"faith": 0,
	"arcane": 0
}
@export var total_attr_points_gained: int = 0
@export var available_attr_points: int = 0

@export var unit_advancement: Dictionary = {}

@export var interrupt_state: int = 0
@export var battlefield_data: Dictionary = {}

@export var party_data: Array = []
@export var current_faction: String = ""

@export var global_relics: Array = []

@export var save_time: int = 0
@export var checksum: String = ""

@export var difficulty_level: int = 0
@export var highest_cleared_difficulty: int = 0

@export var arena_target_talents: Dictionary = {}

# ---- 新增词条存档 ----
@export var unlocked_talents: Array = []

# ---- 防具配方解锁（铁砧酒馆） ----
@export var unlocked_recipes: Array = []

# ---- 地图快照（保存节点布局，不含循环引用） ----
@export var map_snapshot: Dictionary = {}

func compute_checksum() -> String:
	var data = {
		"music_volume": music_volume,
		"sound_volume": sound_volume,
		"game_speed": game_speed,
		"window_mode": window_mode,
		"window_size": window_size,
		"current_day": current_day,
		"visited_nodes": visited_nodes,
		"selected_node_id": selected_node_id,
		"main_unit_name": main_unit_name,
		"soul": soul,
		"cycle_start_soul": cycle_start_soul,
		"cycle_start_materials": cycle_start_materials,
		"temp_soul": temp_soul,
		"temp_gold": temp_gold,
		"interrupt_state": interrupt_state,
		"battlefield_data": battlefield_data,
		"party_data": party_data,
		"unlocked_units": unlocked_units,
		"unlocked_items": unlocked_items,
		"unlocked_relics": unlocked_relics,
		"current_faction": current_faction,
		"global_relics": global_relics,
		"materials": materials,
		"unit_growth": unit_growth,
		"unlocked_armors": unlocked_armors,
		"unlocked_stories": unlocked_stories,
		"attribute_points": attribute_points,
		"total_attr_points_gained": total_attr_points_gained,
		"available_attr_points": available_attr_points,
		"unit_advancement": unit_advancement,
		"difficulty_level": difficulty_level,
		"highest_cleared_difficulty": highest_cleared_difficulty,
		"unlocked_talents": unlocked_talents,
		"unlocked_recipes": unlocked_recipes,
		"current_node_key": current_node_key,
		"map_snapshot": map_snapshot,
		"arena_target_talents": arena_target_talents,
		"talent_exp": talent_exp,
	}
	return JSON.stringify(data, "  ").sha256_text()
