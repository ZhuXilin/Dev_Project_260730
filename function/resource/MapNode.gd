extends Resource
class_name MapNode

enum NodeType {
	START,
	NORMAL,
	ELITE,
	SHOP,
	EVENT,
	BOSS,
	FORGE,
}

static var _node_counter : int = 0

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var position: Vector2
@export var map_data: MapData
@export var node_id: String = ""
@export var is_visited: bool = false
@export var is_available: bool = false
@export var custom_label: String = ""
@export var layer: int = 0
@export var reward: Dictionary = {}    # ← 新增

var connected_nodes: Array = []
var is_completed: bool = false

func _init():
	if node_id.is_empty():
		_node_counter += 1
		node_id = "node_%d_%d" % [Time.get_ticks_msec(), _node_counter]
