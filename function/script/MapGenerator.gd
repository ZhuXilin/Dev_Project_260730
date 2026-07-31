extends Node
class_name MapGenerator

static func generate_day(day: int, level_list: Array[MapData] = []) -> MapLevelData:
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
			root.custom_label = "起点"

			# 第一层分支（4条路线）
			var layer1_types = [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT
			]
			var layer1_labels = ["精英路线", "战斗路线", "均衡路线", "事件路线"]
			var layer1_nodes = _create_labeled_nodes(nodes, layer1_types, layer1_labels, x_positions, y_branch1, LAYER_BRANCH1)

			# 汇合节点①
			var junction1 = _create_node(MapNode.NodeType.EVENT, Vector2(160, y_junction1), LAYER_JUNCTION1)
			junction1.custom_label = "汇合点①"
			nodes.append(junction1)

			# 连接起点 → 第一层
			for node in layer1_nodes:
				root.connected_nodes.append(node)

			# 连接第一层 → 汇合①
			for node in layer1_nodes:
				node.connected_nodes.append(junction1)

			# 第二层分支（4条路线）
			var layer2_types = [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT
			]
			var layer2_labels = ["精英路线", "战斗路线", "均衡路线", "事件路线"]
			var layer2_nodes = _create_labeled_nodes(nodes, layer2_types, layer2_labels, x_positions, y_branch2, LAYER_BRANCH2)

			# 汇合节点②
			var junction2 = _create_node(MapNode.NodeType.EVENT, Vector2(160, y_junction2), LAYER_JUNCTION2)
			junction2.custom_label = "汇合点②"
			nodes.append(junction2)

			# 连接汇合① → 第二层
			for node in layer2_nodes:
				junction1.connected_nodes.append(node)

			# 连接第二层 → 汇合②
			for node in layer2_nodes:
				node.connected_nodes.append(junction2)

			# Boss
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, y_boss), LAYER_BOSS)
			boss.custom_label = "Boss"
			nodes.append(boss)

			# 连接汇合② → Boss
			junction2.connected_nodes.append(boss)

		_:
			# 默认测试地图（以防万一）
			root = _create_node(MapNode.NodeType.START, Vector2(160, 210), 0)
			root.custom_label = "起点"
			var node1 = _create_node(MapNode.NodeType.NORMAL, Vector2(120, 165), 1)
			node1.custom_label = "战斗"
			var node2 = _create_node(MapNode.NodeType.ELITE, Vector2(200, 165), 1)
			node2.custom_label = "精英"
			nodes.append(node1)
			nodes.append(node2)
			root.connected_nodes = [node1, node2]
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 120), 2)
			boss.custom_label = "Boss"
			nodes.append(boss)
			node1.connected_nodes.append(boss)
			node2.connected_nodes.append(boss)

	if root:
		nodes.append(root)

	if not level_list.is_empty():
		_assign_map_data(nodes, level_list, day)

	data.nodes = nodes
	data.root_node = root
	data.map_name = "第%d天" % day
	return data

# ---- 辅助函数：创建带标签的节点列表 ----
static func _create_labeled_nodes(nodes: Array, types: Array, labels: Array, x_positions: Array, y: float, layer: int) -> Array[MapNode]:
	var result: Array[MapNode] = []
	for i in range(types.size()):
		var pos = Vector2(x_positions[i], y)
		var node = _create_node(types[i], pos, layer)
		node.custom_label = labels[i]
		nodes.append(node)
		result.append(node)
	return result

# ---- 创建单个节点（必须传入 layer） ----
static func _create_node(type: MapNode.NodeType, pos: Vector2, layer: int) -> MapNode:
	var node = MapNode.new()
	node.node_type = type
	node.position = pos
	node.layer = layer
	node.is_available = false
	node.is_visited = false
	return node

# ---- 连接两层（按顺序一一对应） ----
static func _connect_layers(from_nodes: Array[MapNode], to_nodes: Array[MapNode]):
	var min_count = min(from_nodes.size(), to_nodes.size())
	for i in range(min_count):
		from_nodes[i].connected_nodes.append(to_nodes[i])

# ---- 分配地图数据到战斗节点 ----
static func _assign_map_data(nodes: Array, _level_list: Array[MapData], _day: int):
	var battle_nodes = nodes.filter(func(n):
		return n.node_type in [
			MapNode.NodeType.NORMAL,
			MapNode.NodeType.ELITE,
			MapNode.NodeType.BOSS
		]
	)
	for node in battle_nodes:
		var map = LevelManager.get_map_for_node_type(node.node_type)
		if map:
			node.map_data = map
		else:
			node.map_data = _create_fallback_map_data(node.node_type)

# ---- 创建备用地图 ----
static func _create_fallback_map_data(_type: MapNode.NodeType) -> MapData:
	var map = MapData.new()
	map.map_name = "测试战斗"
	var cfg = UnitConfig.new()
	cfg.unit_name = "剑士"
	cfg.team_id = 0
	cfg.position = Vector2i(10, 10)
	map.unit_configs.append(cfg)
	var enemy_cfg = UnitConfig.new()
	enemy_cfg.unit_name = "斧兵"
	enemy_cfg.team_id = 1
	enemy_cfg.position = Vector2i(5, 5)
	map.unit_configs.append(enemy_cfg)
	return map
