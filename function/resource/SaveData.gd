extends Resource
class_name SaveData

# 玩家设置
@export var music_volume: float = 0.2
@export var sound_volume: float = 0.2
@export var game_speed: int = 0
@export var window_mode: int = 0          # 0=窗口, 1=全屏
@export var window_size: Vector2i = Vector2i(640, 480)

# 游戏进度
@export var current_day: int = 1
@export var map_level_data: MapLevelData = null
@export var selected_node_id: String = ""
@export var main_unit_name: String = ""

# 队伍状态 - 改为通用 Array 类型，避免类型不匹配
@export var party_data: Array = []        # 实际存储 Dictionary 元素

# 元数据
@export var save_time: int = 0
@export var checksum: String = ""

# 校验和计算（保持不变）
func compute_checksum() -> String:
	var data = {
		"music_volume": music_volume,
		"sound_volume": sound_volume,
		"game_speed": game_speed,
		"window_mode": window_mode,
		"window_size": window_size,
		"current_day": current_day,
		"selected_node_id": selected_node_id,
		"main_unit_name": main_unit_name,
		"party_data": party_data,
		"map_level_data": _hash_map_data(map_level_data)
	}
	return JSON.stringify(data, "  ").sha256_text()

func _hash_map_data(data: MapLevelData) -> String:
	if not data:
		return ""
	var info = {
		"day": data.day,
		"nodes": data.nodes.map(func(n): return {
			"id": n.node_id,
			"type": n.node_type,
			"visited": n.is_visited,
			"available": n.is_available,
			"pos": [n.position.x, n.position.y],
			"layer": n.layer
		})
	}
	return JSON.stringify(info, "  ").sha256_text()
