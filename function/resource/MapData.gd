extends Resource
class_name MapData

enum SupportedNodeType {
	START,
	CAMPFIRE,
	NORMAL,
	ELITE,
	SHOP,
	EVENT,
	BOSS,
	FINAL_PREP,
	ANY   # 通用，可分配给任何类型
}

@export var map_name : String = "默认地图"
@export var scene : PackedScene
@export var map_size : Vector2i = Vector2i(20, 15)
@export var node_type : SupportedNodeType = SupportedNodeType.ANY   # 新增
