extends Resource
class_name MapLayoutNode

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var random_pool: Array[MapNode.NodeType] = []
@export var position: Vector2 = Vector2.ZERO
@export var layer: int = 0
@export var connects_to: Array[int] = []

## ★ 完成此节点时解锁的遗物 id 列表
@export var unlock_relics: Array[String] = []


func resolve_type() -> MapNode.NodeType:
	if random_pool.is_empty():
		return node_type
	return random_pool[randi() % random_pool.size()]
