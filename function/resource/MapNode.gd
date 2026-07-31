# MapNode.gd
extends Resource
class_name MapNode

enum NodeType {
	START,          # 起点（选初始装备）
	CAMPFIRE,       # 篝火（休息点）
	NORMAL,         # 普通怪
	ELITE,          # 精英怪
	SHOP,           # 商店
	EVENT,          # 事件
	BOSS,           # Boss
	FINAL_PREP      # 最终备战席
}

@export var node_type: NodeType
@export var position: Vector2          # 在画布上的位置（像素）
@export var map_data: MapData          # 对应的关卡数据（如果是战斗节点）
@export var node_id: String = ""       # 唯一标识，用于状态持久化
@export var is_visited: bool = false
@export var is_available: bool = false

# 连接关系（由生成器填充）
var connected_nodes: Array[MapNode] = []

# 是否已完成（已通过）
var is_completed: bool = false

func _init():
	if node_id.is_empty():
		node_id = "node_%d_%d" % [Time.get_ticks_msec(), randi()]
