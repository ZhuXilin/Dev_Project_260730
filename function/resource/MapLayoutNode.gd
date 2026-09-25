extends Resource
class_name MapLayoutNode

## 节点类型（定死时用）
@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
## 随机池：非空时从池里随机抽一个作为实际类型
@export var random_pool: Array[MapNode.NodeType] = []
## 位置（编辑器自动计算，一般不用手填）
@export var position: Vector2 = Vector2.ZERO
## 层
@export var layer: int = 0
## 连接到哪些节点（数组索引）
@export var connects_to: Array[int] = []


## 返回实际节点类型（考虑随机池）
func resolve_type() -> MapNode.NodeType:
	if random_pool.is_empty():
		return node_type
	return random_pool[randi() % random_pool.size()]
