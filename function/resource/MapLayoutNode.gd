extends Resource
class_name MapLayoutNode

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var random_pool: Array[MapNode.NodeType] = []
@export var position: Vector2 = Vector2.ZERO
@export var layer: int = 0
@export var connects_to: Array[int] = []

@export var unlock_relics: Array[String] = []
@export var unlock_units: Array[String] = []

## ★ v6.58：胜利条件字段已移除——胜利目标唯一存于战场地图的 VictoryObjectiveTrigger。
## 地图节点只负责节点类型/波次/奖励；胜利条件跟着"地图"走，避免随机节点错配。

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
