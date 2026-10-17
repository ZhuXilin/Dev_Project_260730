extends Resource
class_name MapData

enum ObjectiveType {
	ANNIHILATE,   # 全灭（默认）
	CAPTURE,      # 占领
	FLAG,         # 夺旗
	ASSAULT,      # 突进
}

@export var map_name : String = "默认地图"
@export var scene : PackedScene
@export var map_size : Vector2i = Vector2i(20, 15)
@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var spawn_points: Array[Vector2i] = []
@export var required_unit: String = ""

@export var unlock_relics: Array[String] = []
@export var unlock_units: Array[String] = []

@export var objective_type: ObjectiveType = ObjectiveType.ANNIHILATE
@export var objective_params: Dictionary = {}

@export var max_waves: int = 1
@export var reinforcement_count: int = 0
@export var reinforcement_pool: Array[String] = []

## v4.5：高收益节点奖励倍率（金币 / 魂火 / 魂 都乘）
@export var reward_multiplier: float = 1.0

## v4.5：高收益节点的负面代价——敌人最大 HP 倍率
@export var enemy_hp_multiplier: float = 1.0
