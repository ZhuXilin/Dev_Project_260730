extends Resource
class_name MapData

@export var map_name : String = "默认地图"
@export var scene : PackedScene
@export var map_size : Vector2i = Vector2i(20, 15)
@export var node_type: MapNode.NodeType = MapNode.NodeType.NORMAL   # 改为枚举类型
@export var spawn_points: Array[Vector2i] = []
@export var required_unit: String = ""
