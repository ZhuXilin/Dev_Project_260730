extends Resource
class_name MapLayoutNode

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var random_pool: Array[MapNode.NodeType] = []
@export var position: Vector2 = Vector2.ZERO
@export var layer: int = 0
@export var connects_to: Array[int] = []

## 完成此节点时解锁的遗物 id 列表
@export var unlock_relics: Array[String] = []

## ★ 新增：完成此节点时解锁的单位 id 列表
## 场景：BOSS 节点配置 → 打完后解锁新单位（可切换主单位/阵营）
@export var unlock_units: Array[String] = []


func resolve_type() -> MapNode.NodeType:
	if random_pool.is_empty():
		return node_type
	return random_pool[randi() % random_pool.size()]
