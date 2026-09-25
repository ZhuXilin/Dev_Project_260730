extends Resource
class_name MapLayoutNode

@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL
@export var position: Vector2 = Vector2.ZERO
@export var layer: int = 0
@export var connects_to: Array[int] = []
