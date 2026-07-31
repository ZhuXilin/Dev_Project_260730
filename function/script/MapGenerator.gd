extends Node
class_name MapGenerator

static func generate_day(day: int, level_list: Array[MapData] = []) -> MapLevelData:
	var data = MapLevelData.new()
	data.day = day
	var nodes: Array[MapNode] = []
	var root: MapNode = null

	match day:
		1:
			root = _create_node(MapNode.NodeType.START, Vector2(160, 210))
			var layer1 = _create_layer_nodes(nodes, [
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL
			], Vector2(80, 165), Vector2(160, 165), Vector2(240, 165))
			_connect_layers([root], layer1)
			
			var layer2 = _create_layer_nodes(nodes, [
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT
			], Vector2(80, 120), Vector2(160, 120), Vector2(240, 120))
			_connect_layers(layer1, layer2)
			
			var layer3 = _create_layer_nodes(nodes, [
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.NORMAL
			], Vector2(80, 75), Vector2(160, 75), Vector2(240, 75))
			_connect_layers(layer2, layer3)
			
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 30))
			nodes.append(boss)
			_connect_layers(layer3, [boss])
			
		2:
			root = _create_node(MapNode.NodeType.CAMPFIRE, Vector2(160, 210))
			var layer1 = _create_layer_nodes(nodes, [
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL
			], Vector2(80, 165), Vector2(160, 165), Vector2(240, 165))
			_connect_layers([root], layer1)
			
			var layer2 = _create_layer_nodes(nodes, [
				MapNode.NodeType.SHOP,
				MapNode.NodeType.EVENT,
				MapNode.NodeType.ELITE
			], Vector2(80, 120), Vector2(160, 120), Vector2(240, 120))
			_connect_layers(layer1, layer2)
			
			var layer3 = _create_layer_nodes(nodes, [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.NORMAL,
				MapNode.NodeType.ELITE
			], Vector2(80, 75), Vector2(160, 75), Vector2(240, 75))
			_connect_layers(layer2, layer3)
			
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 30))
			nodes.append(boss)
			_connect_layers(layer3, [boss])
			
		3:
			root = _create_node(MapNode.NodeType.CAMPFIRE, Vector2(160, 210))
			var layer1 = _create_layer_nodes(nodes, [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.ELITE,
				MapNode.NodeType.ELITE
			], Vector2(80, 165), Vector2(160, 165), Vector2(240, 165))
			_connect_layers([root], layer1)
			
			var layer2 = _create_layer_nodes(nodes, [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.ELITE,
				MapNode.NodeType.ELITE
			], Vector2(80, 120), Vector2(160, 120), Vector2(240, 120))
			_connect_layers(layer1, layer2)
			
			var layer3 = _create_layer_nodes(nodes, [
				MapNode.NodeType.ELITE,
				MapNode.NodeType.ELITE,
				MapNode.NodeType.ELITE
			], Vector2(80, 75), Vector2(160, 75), Vector2(240, 75))
			_connect_layers(layer2, layer3)
			
			var prep = _create_node(MapNode.NodeType.FINAL_PREP, Vector2(160, 30))
			nodes.append(prep)
			_connect_layers(layer3, [prep])
			
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 15))
			nodes.append(boss)
			prep.connected_nodes.append(boss)
		_:
			root = _create_node(MapNode.NodeType.START, Vector2(160, 210))
			var node = _create_node(MapNode.NodeType.NORMAL, Vector2(160, 165))
			nodes.append(node)
			root.connected_nodes.append(node)
			var boss = _create_node(MapNode.NodeType.BOSS, Vector2(160, 120))
			nodes.append(boss)
			node.connected_nodes.append(boss)

	if root:
		nodes.insert(0, root)  # 将起点放到最前面，确保它获得第一个地图数据

	if not level_list.is_empty():
		_assign_map_data(nodes, level_list, day)

	data.nodes = nodes
	data.root_node = root
	data.map_name = "第%d天" % day
	return data

static func _create_node(type: MapNode.NodeType, pos: Vector2) -> MapNode:
	var node = MapNode.new()
	node.node_type = type
	node.position = pos
	node.is_available = false
	node.is_visited = false
	return node

static func _create_layer_nodes(nodes: Array, types: Array, pos1: Vector2, pos2: Vector2, pos3: Vector2) -> Array[MapNode]:
	var result: Array[MapNode] = []
	for i in range(3):
		var pos = [pos1, pos2, pos3][i]
		var node = _create_node(types[i], pos)
		nodes.append(node)
		result.append(node)
	return result

static func _connect_layers(from_nodes: Array[MapNode], to_nodes: Array[MapNode]):
	for from in from_nodes:
		for to in to_nodes:
			from.connected_nodes.append(to)

static func _assign_map_data(nodes: Array, level_list: Array[MapData], _day: int):
	var battle_nodes = nodes.filter(func(n):
		return n.node_type in [
			MapNode.NodeType.START,
			MapNode.NodeType.NORMAL,
			MapNode.NodeType.ELITE,
			MapNode.NodeType.BOSS
		]
	)
	print("=== 分配地图数据，战斗节点数：", battle_nodes.size(), "，可用地图数：", level_list.size())
	var idx = 0
	for node in battle_nodes:
		if idx < level_list.size():
			node.map_data = level_list[idx]
			print("  节点 ", node.node_type, " 分配地图：", level_list[idx].map_name)
			idx += 1
		else:
			node.map_data = _create_fallback_map_data(node.node_type)
			print("  节点 ", node.node_type, " 使用备用地图（测试战斗）")

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
