extends Resource
class_name MapNode

enum NodeType {
	START,
	NORMAL,
	ELITE,
	TREASURE,
	BOSS,
	FORGE,
	CHAPEL,
	QUESTION, # ★ 新增：问号节点
}

static var _node_counter : int = 0

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var hidden_node_type: int = -1 # ★ 新增：如果是 QUESTION，这里记录真实类型
@export var position: Vector2
@export var map_data: MapData
@export var node_id: String = ""
@export var is_visited: bool = false
@export var is_available: bool = false
@export var custom_label: String = ""
@export var layer: int = 0
@export var reward: Dictionary = {}

@export var unlock_relics: Array[String] = []
@export var unlock_units: Array[String] = []

var connected_nodes: Array = []
var is_completed: bool = false

func _init():
	if node_id.is_empty():
		_node_counter += 1
		node_id = "node_%d_%d" % [Time.get_ticks_msec(), _node_counter]
