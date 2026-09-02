extends Resource
class_name SaveData

const CURRENT_VERSION = 2

# ---- 版本 ----
@export var save_version: int = CURRENT_VERSION

# ---- 解锁数据 ----
@export var unlocked_units: Array = []
@export var unlocked_items: Array = []
@export var unlocked_relics: Array = []

# ---- 玩家设置 ----
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
@export var map_level_data: MapLevelData

# ---- 资源 ----
@export var soul: int = 0
@export var temp_soul: int = 0
@export var temp_gold: int = 0

# ---- 材料 ----
@export var materials: Dictionary = {
	"粗铁": 0,
	"精钢": 0,
	"秘银": 0,
	"龙鳞": 0
}

# ---- 永久解锁 ----
@export var unlocked_armors: Array = []          # 已解锁防具配方ID
@export var unlocked_stories: Array = []         # 已解锁剧情片段ID

# ---- 属性分配 ----
@export var attribute_points: Dictionary = {
	"strength": 0,
	"dexterity": 0,
	"intelligence": 0,
	"faith": 0,
	"arcane": 0
}
@export var total_attr_points_gained: int = 0
@export var available_attr_points: int = 0

# ---- 单位加点 ----
@export var unit_advancement: Dictionary = {}    # {"剑士": {"hp": 2, "atk": 1}, ...}

# ---- 游戏状态 ----
@export var interrupt_state: int = 0
@export var battlefield_data: Dictionary = {}

# ---- 队伍状态 ----
@export var party_data: Array = []
@export var current_faction: String = ""

# ---- 装备数据 ----
@export var party_equipment: Array = []
@export var global_relics: Array = []

# ---- 元数据 ----
@export var save_time: int = 0
@export var checksum: String = ""

# ---- 终局数据 ----
@export var difficulty_level: int = 0
@export var highest_cleared_difficulty: int = 0
@export var unlocked_talents: Array = []   # 已解锁词条ID列表
@export var party_talents: Array = []      # 单位词条装备 [{"unit_name": "剑士", "talents": ["crit"]}]

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
		"temp_soul": temp_soul,
		"temp_gold": temp_gold,
		"interrupt_state": interrupt_state,
		"battlefield_data": battlefield_data,
		"party_data": party_data,
		"unlocked_units": unlocked_units,
		"unlocked_items": unlocked_items,
		"unlocked_relics": unlocked_relics,
		"current_faction": current_faction,
		"party_equipment": party_equipment,
		"global_relics": global_relics,
		"map_level_data": map_level_data.resource_path if map_level_data else "",
		"materials": materials,
		"unlocked_armors": unlocked_armors,
		"unlocked_stories": unlocked_stories,
		"attribute_points": attribute_points,
		"total_attr_points_gained": total_attr_points_gained,
		"available_attr_points": available_attr_points,
		"unit_advancement": unit_advancement,
		"difficulty_level": difficulty_level,
		"highest_cleared_difficulty": highest_cleared_difficulty
	}
	return JSON.stringify(data, "  ").sha256_text()
