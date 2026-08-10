extends Resource
class_name SaveData

# 玩家设置
@export var music_volume: float = 0.2
@export var sound_volume: float = 0.2
@export var game_speed: int = 0
@export var window_mode: int = 0          # 0=窗口, 1=全屏
@export var window_size: Vector2i = Vector2i(640, 480)

@export var soul: int = 0
@export var temp_soul: int = 0
@export var temp_gold: int = 0
@export var interrupt_state: int = 0
@export var battlefield_data: Dictionary = {}

# 游戏进度（不再存储 map_level_data）
@export var current_day: int = 1
@export var visited_nodes: Array = []     # 存储为排序后的键值对数组 [ [key, value], ... ]
@export var selected_node_id: String = ""
@export var main_unit_name: String = ""

# 队伍状态
@export var party_data: Array = []

# 元数据
@export var save_time: int = 0
@export var checksum: String = ""

func compute_checksum() -> String:
	var data = {
		"music_volume": music_volume,
		"sound_volume": sound_volume,
		"game_speed": game_speed,
		"window_mode": window_mode,
		"window_size": window_size,
		"current_day": current_day,
		"visited_nodes": visited_nodes,   # 已经是排序数组
		"selected_node_id": selected_node_id,
		"main_unit_name": main_unit_name,
		"party_data": party_data
	}
	return JSON.stringify(data, "  ").sha256_text()
