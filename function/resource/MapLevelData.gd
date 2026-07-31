# MapLevelData.gd
extends Resource
class_name MapLevelData

@export var day: int                   # 第几天（1,2,3）
@export var nodes: Array[MapNode]     # 所有节点
@export var root_node: MapNode        # 起始节点
@export var background_texture: Texture2D
@export var map_name: String = ""

# 节点状态查询
func get_node_by_id(node_id: String) -> MapNode:
	for node in nodes:
		if node.node_id == node_id:
			return node
	return null

func get_available_nodes() -> Array[MapNode]:
	var result = []
	for node in nodes:
		if node.is_available and not node.is_visited:
			result.append(node)
	return result

func get_visited_nodes() -> Array[MapNode]:
	return nodes.filter(func(n): return n.is_visited)
