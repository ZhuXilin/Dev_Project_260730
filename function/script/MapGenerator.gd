extends Node
class_name MapGenerator

# 将参数 level_list 改为 _level_list（有意忽略）
static func generate_day(day: int, _level_list: Array[MapData] = []) -> MapLevelData:
	var data = MapLevelData.new()
	data.day = day
	var nodes: Array[MapNode] = []
	var root: MapNode = null

	match day:
		1, 2, 3:
			# 定义层索引
			const LAYER_START = 0
			const LAYER_BRANCH1 = 1
			const LAYER_JUNCTION1 = 2
			const LAYER_BRANCH2 = 3
			const LAYER_JUNCTION2 = 4
			const LAYER_BOSS = 5

			var y_start = 210
			var y_branch1 = 170
			var y_junction1 = 130
			var y_branch2 = 90
			var y_junction2 = 50
			var y_boss = 20
			var x_positions = [80, 130, 190, 240]

			# 起点
			root = _create_node(MapNode.NodeType.START, Vector2(160, y_start), LAYER_START)
			nodes.append(root)

			# 第一层分支
			var layer1_types = [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT
			]
			var layer1_nodes = _create_nodes(nodes, layer1_types, x_positions, y_branch1, LAYER_BRANCH1)

			# ---- 汇合节点①：CAMPFIRE ----
			var junction1 = _create_node(MapNode.NodeType.CAMPFIRE, Vector2(160, y_junction1), LAYER_JUNCTION1)
			nodes.append(junction1)

			# 连接
			for node in layer1_nodes:
				root.connected_nodes.append(node)
			for node in layer1_nodes:
				node.connected_nodes.append(junction1)

			# 第二层分支
			var layer2_types = [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT
			]
			var layer2_nodes = _create_nodes(nodes, layer2_types, x_positions, y_branch2, LAYER_BRANCH2)

			# ---- 汇合节点②：FINAL_PREP ----
			var junction2 = _create_node(MapNode.NodeType.FINAL_PREP, Vector2(160, y_junction2), LAYER_JUNCTION2)
			nodes.append(junction2)

			# 连接
			for node in layer2_nodes:
				junction1.connected_nodes.append(node)
			for node in layer2_nodes:
				node.connected_nodes.append(junction2)

			# Boss
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, y_boss), LAYER_BOSS)
			nodes.append(boss)
			junction2.connected_nodes.append(boss)

		_:
			# 默认测试地图
			root = _create_node(MapNode.NodeType.START, Vector2(160, 210), 0)
			var node1 = _create_node(MapNode.NodeType.NORMAL, Vector2(120, 165), 1)
			var node2 = _create_node(MapNode.NodeType.ELITE, Vector2(200, 165), 1)
			nodes.append(node1)
			nodes.append(node2)
			root.connected_nodes = [node1, node2]
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 120), 2)
			nodes.append(boss)
			node1.connected_nodes.append(boss)
			node2.connected_nodes.append(boss)

	# 为所有节点分配地图数据（由 LevelManager 按类型提供）
	_assign_map_data_to_all_nodes(nodes)

	data.nodes = nodes
	data.root_node = root
	data.map_name = "第%d天" % day
	return data

# ---- 辅助函数：创建节点列表 ----
static func _create_nodes(nodes: Array, types: Array, x_positions: Array, y: float, layer: int) -> Array[MapNode]:
	var result: Array[MapNode] = []
	for i in range(types.size()):
		var pos = Vector2(x_positions[i], y)
		var node = _create_node(types[i], pos, layer)
		nodes.append(node)
		result.append(node)
	return result

# ---- 创建单个节点 ----
static func _create_node(type: MapNode.NodeType, pos: Vector2, layer: int) -> MapNode:
	var node = MapNode.new()
	node.node_type = type
	node.position = pos
	node.layer = layer
	node.is_available = false
	node.is_visited = false
	return node

# ---- 为所有节点分配地图 ----
static func _assign_map_data_to_all_nodes(nodes: Array):
	for node in nodes:
		var map = LevelManager.get_map_for_node_type(node.node_type)
		if map:
			node.map_data = map
		else:
			node.map_data = _create_fallback_map_data(node.node_type)

# ---- 创建备用地图 ----
static func _create_fallback_map_data(_type: MapNode.NodeType) -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	return map
