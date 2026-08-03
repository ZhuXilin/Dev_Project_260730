extends Resource
class_name MapData

@export var map_name : String = "默认地图"
@export var scene : PackedScene
@export var map_size : Vector2i = Vector2i(20, 15)
@export var node_type : int = MapNode.NodeType.NORMAL   # 直接使用 MapNode 的枚举
@export var spawn_points: Array[Vector2i] = []
@export var required_unit: String = ""
