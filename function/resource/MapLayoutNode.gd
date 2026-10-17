extends Resource
class_name MapLayoutNode

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var random_pool: Array[MapNode.NodeType] = []
@export var position: Vector2 = Vector2.ZERO
@export var layer: int = 0
@export var connects_to: Array[int] = []

## 完成此节点时解锁的遗物 id 列表
@export var unlock_relics: Array[String] = []

## 完成此节点时解锁的单位 id 列表
@export var unlock_units: Array[String] = []

## v4.4：胜利目标（仅战斗节点/问号节点有效）
@export var objective_type: MapData.ObjectiveType = MapData.ObjectiveType.ANNIHILATE

## 胜利目标参数（Dictionary，序列化到 .tres 时直接用类型）
## - CAPTURE: { "target_cell": Vector2i(10, 7), "hold_turns": 3 }
## - FLAG:    { "flag_cell": Vector2i(15, 7), "goal_cell": Vector2i(1, 7) }
## - ASSAULT: { "target_unit_name": "dragonborn" }
@export var objective_params: Dictionary = {}

## 波次与增援（与 MapData 对应）
@export var max_waves: int = 1
@export var reinforcement_count: int = 0

func resolve_type() -> MapNode.NodeType:
	if random_pool.is_empty():
		return node_type
	return random_pool[randi() % random_pool.size()]
