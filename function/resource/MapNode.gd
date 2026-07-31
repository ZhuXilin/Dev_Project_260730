extends Resource
class_name MapNode

enum NodeType {
	START, CAMPFIRE, NORMAL, ELITE, SHOP, EVENT, BOSS, FINAL_PREP
}

@export var node_type: NodeType
@export var position: Vector2
@export var map_data: MapData
@export var node_id: String = ""
@export var is_visited: bool = false
@export var is_available: bool = false
@export var custom_label: String = ""
@export var layer: int = 0           # 新增：层索引

var connected_nodes: Array[MapNode] = []
var is_completed: bool = false

func _init():
	if node_id.is_empty():
		node_id = "node_%d_%d" % [Time.get_ticks_msec(), randi()]
