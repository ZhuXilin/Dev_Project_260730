extends Resource
class_name MapNode

enum NodeType {
	START, # ★ v6.47：已废弃占位（保留以维持后续枚举整数值/存档兼容），不再作为可配置节点类型
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
var is_passed: bool = false

## ★ v6.58：胜利目标类型（从本节点 map_data.scene 的 VictoryObjectiveTrigger 预读）。
## 仅用于地图界面标记显示；实际判胜仍以战场加载的 trigger 为准。
## 非 @export：运行时派生数据，不进存档/编辑器资源。
var objective_type: int = MapData.ObjectiveType.ANNIHILATE

func _init():
	if node_id.is_empty():
		_node_counter += 1
		node_id = "node_%d_%d" % [Time.get_ticks_msec(), _node_counter]
