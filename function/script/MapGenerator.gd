class_name MapGenerator
extends Node

static func generate_day(day: int, _level_list: Array[MapData] = []) -> MapLevelData:
	randomize()
	var data = MapLevelData.new()
	data.day = day
	var nodes: Array[MapNode] = []
	var root: MapNode = null

	match day:
		1, 2:
			# 5 层 8 节点
			var x_left   = 110
			var x_right  = 210
			var x_center = 160

			# Layer 0: START
			root = _create_node(MapNode.NodeType.START, Vector2(x_center, 220), 0)
			nodes.append(root)

			# Layer 1: NORMAL ×2（固定类型，地图随机）
			var n1 = _create_node(MapNode.NodeType.NORMAL, Vector2(x_left,  175), 1)
			var n2 = _create_node(MapNode.NodeType.NORMAL, Vector2(x_right, 175), 1)
			nodes.append(n1)
			nodes.append(n2)

			# Layer 2: SHOP
			var shop = _create_node(MapNode.NodeType.SHOP, Vector2(x_center, 130), 2)
			nodes.append(shop)

			# Layer 3: ELITE + EVENT（左右随机）
			var elite_left = (randi() % 2 == 0)
			var e1 = _create_node(
				MapNode.NodeType.ELITE if elite_left else MapNode.NodeType.EVENT,
				Vector2(x_left, 85), 3)
			var e2 = _create_node(
				MapNode.NodeType.EVENT if elite_left else MapNode.NodeType.ELITE,
				Vector2(x_right, 85), 3)
			nodes.append(e1)
			nodes.append(e2)

			# Layer 4: FORGE
			var forge = _create_node(MapNode.NodeType.FORGE, Vector2(x_center, 45), 4)
			nodes.append(forge)

			# Layer 5: BOSS
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(x_center, 15), 5)
			nodes.append(boss)

			# 连接
			root.connected_nodes = [n1, n2]
			n1.connected_nodes = [shop]
			n2.connected_nodes = [shop]
			shop.connected_nodes = [e1, e2]
			e1.connected_nodes = [forge]
			e2.connected_nodes = [forge]
			forge.connected_nodes = [boss]

		3:
			# Day3：铁匠铺（整备）→ BOSS
			root = _create_node(MapNode.NodeType.FORGE, Vector2(160, 150), 0)
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 60), 1)
			nodes.append(root)
			nodes.append(boss)
			root.connected_nodes = [boss]
			root.is_available = true

		_:
			# 兜底测试地图
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

	_assign_map_data_to_all_nodes(nodes)

	data.nodes = nodes
	data.root_node = root
	data.map_name = "第%d天" % day
	return data


static func _create_node(type: MapNode.NodeType, pos: Vector2, layer: int) -> MapNode:
	var node = MapNode.new()
	node.node_type = type
	node.position = pos
	node.layer = layer
	node.is_available = false
	node.is_visited = false
	return node

static func _assign_map_data_to_all_nodes(nodes: Array):
	var combat_nodes_by_type : Dictionary = {}
	print("=== _assign_map_data_to_all_nodes 开始 ===")
	for node in nodes:
		print("  节点: type=%d, layer=%d" % [node.node_type, node.layer])
		if node.node_type in [
			MapNode.NodeType.SHOP,
			MapNode.NodeType.FORGE,
			MapNode.NodeType.EVENT,
		]:
			var placeholder = MapData.new()
			placeholder.node_type = node.node_type
			node.map_data = placeholder
			continue

		if not combat_nodes_by_type.has(node.node_type):
			combat_nodes_by_type[node.node_type] = []
		combat_nodes_by_type[node.node_type].append(node)

	for node_type in combat_nodes_by_type:
		var group : Array = combat_nodes_by_type[node_type]
		var maps : Array = LevelManager.get_random_maps_for_node_type(
			node_type, group.size(), GameState.main_unit_name
		)
		print("类型 %d 组大小 %d → 拿到 %d 张地图:" % [node_type, group.size(), maps.size()])
		for i in range(group.size()):
			if i < maps.size():
				group[i].map_data = maps[i]
			else:
				group[i].map_data = _create_fallback_map_data(node_type)

static func _create_fallback_map_data(_type: MapNode.NodeType) -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	return map
