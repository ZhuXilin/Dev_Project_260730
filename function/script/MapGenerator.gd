class_name MapGenerator
extends Node

# ============================================================
#  入口：布局驱动
# ============================================================
static func generate_day(day: int, layout: MapLayout, _level_list: Array[MapData] = []) -> MapLevelData:
	if layout == null:
		push_error("[MapGenerator] layout 为空")
		return null
	if not layout.has_day(day):
		push_error("[MapGenerator] 布局缺少 day=%d" % day)
		return null
	return _generate_from_layout(day, layout.get_day(day))


# ============================================================
#  布局驱动
# ============================================================
static func _generate_from_layout(day: int, day_layout: MapLayoutDay) -> MapLevelData:
	randomize()
	var data = MapLevelData.new()
	data.day = day

	var nodes: Array[MapNode] = []

	# ---- 按层分组 ----
	var by_layer : Dictionary = {}
	for i in range(day_layout.nodes.size()):
		var ln : MapLayoutNode = day_layout.nodes[i]
		if not by_layer.has(ln.layer):
			by_layer[ln.layer] = []
		by_layer[ln.layer].append(i)

	# ---- 逐层解析类型（同层不重复） ----
	var resolved_types : Array = []
	resolved_types.resize(day_layout.nodes.size())

	for layer_key in by_layer:
		var indices : Array = by_layer[layer_key]
		
		# ★ 按 pool 大小升序处理（pool 小的优先占坑）
		indices.sort_custom(func(a, b):
			var pa : Array = day_layout.nodes[a].random_pool
			var pb : Array = day_layout.nodes[b].random_pool
			var sa : int = pa.size() if not pa.is_empty() else 999
			var sb : int = pb.size() if not pb.is_empty() else 999
			return sa < sb
		)
		
		# 1. 先收集本层已使用的类型（固定节点的类型优先占用）
		var used_types : Dictionary = {}
		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			if ln.random_pool.is_empty():
				used_types[ln.node_type] = true

		# 2. 逐个处理
		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			if ln.random_pool.is_empty():
				resolved_types[idx] = ln.node_type
				continue
			# 从 pool 中排除已用的类型
			var available : Array = []
			for t in ln.random_pool:
				if not used_types.has(t):
					available.append(t)
			# 池子耗尽 → 允许重复
			if available.is_empty():
				available = ln.random_pool.duplicate()
			var pick : int = available[randi() % available.size()]
			resolved_types[idx] = pick
			used_types[pick] = true

	# ---- 创建节点 ----
	for i in range(day_layout.nodes.size()):
		var ln : MapLayoutNode = day_layout.nodes[i]
		var actual_type : int = resolved_types[i]
		var n : MapNode = _create_node(actual_type as MapNode.NodeType, ln.position, ln.layer)
		nodes.append(n)

	# ---- 建立连接 ----
	for i in range(day_layout.nodes.size()):
		var layout_node : MapLayoutNode = day_layout.nodes[i]
		var from_node : MapNode = nodes[i]
		for target_idx in layout_node.connects_to:
			if target_idx < 0 or target_idx >= nodes.size():
				push_warning("[MapGenerator] day=%d node[%d] 的 connects_to 越界: %d" % [day, i, target_idx])
				continue
			var to_node : MapNode = nodes[target_idx]
			if not from_node.connected_nodes.has(to_node):
				from_node.connected_nodes.append(to_node)

	# ---- 找根节点 ----
	var root: MapNode = null
	for n in nodes:
		if n.layer == 0:
			root = n
			break
	if root == null and not nodes.is_empty():
		root = nodes[0]

	# ---- TREASURE 节点：roll 奖励 ----
	for n in nodes:
		if n.node_type == MapNode.NodeType.TREASURE:
			n.reward = TreasureRewardManager.roll_reward(day)

	_assign_map_data_to_all_nodes(nodes)

	data.nodes = nodes
	data.root_node = root
	data.map_name = "第%d天" % day
	return data


# ============================================================
#  工具
# ============================================================
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
	for node in nodes:
		if node.node_type in [
			MapNode.NodeType.SHOP,
			MapNode.NodeType.FORGE,
			MapNode.NodeType.TREASURE,
			MapNode.NodeType.CHAPEL,
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
		for i in range(group.size()):
			if i < maps.size():
				group[i].map_data = maps[i]
			else:
				group[i].map_data = _create_fallback_map_data(node_type)


static func _create_fallback_map_data(_type: MapNode.NodeType) -> MapData:
	var map = MapData.new()
	map.map_name = "备用地图"
	return map
