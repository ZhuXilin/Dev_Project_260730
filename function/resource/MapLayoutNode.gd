extends Resource
class_name MapLayoutNode

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var random_pool: Array[MapNode.NodeType] = []
@export var position: Vector2 = Vector2.ZERO
@export var layer: int = 0
@export var connects_to: Array[int] = []

@export var unlock_relics: Array[String] = []
@export var unlock_units: Array[String] = []

@export var objective_type: MapData.ObjectiveType = MapData.ObjectiveType.ANNIHILATE
@export var objective_params: Dictionary = {}

## v4.7：允许该节点动态分配目标（默认关闭）。
@export var allow_dynamic_objective: bool = false

## v4.7：动态目标的候选池（ObjectiveType 整数值，空=全部）。
@export var dynamic_objective_pool: Array[int] = []

@export var max_waves: int = 1
@export var reinforcement_count: int = 0

@export var reward_multiplier: float = 1.0
@export var enemy_hp_multiplier: float = 1.0

## v4.5：战斗强度等级（0 = 无，1 = I，2 = II，3 = III）
@export var intensity: int = 0

func resolve_type() -> MapNode.NodeType:
	if random_pool.is_empty():
		return node_type
	return random_pool[randi() % random_pool.size()]
