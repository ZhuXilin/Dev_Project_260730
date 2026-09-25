class_name MapGenerator
extends Node

# ============================================================
#  入口：布局驱动
# ============================================================
static func generate_day(day: int, layout: MapLayout, _level_list: Array[MapData] = []) -> MapLevelData:
	if layout == null:
		push_error("[MapGenerator] layout 为空，请为 UnitLevelMapEntry 挂载 MapLayout")
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

	# ---- 第一遍：创建节点（用随机池解析类型）----
	for layout_node in day_layout.nodes:
		var actual_type : MapNode.NodeType = layout_node.resolve_type()
		var n : MapNode = _create_node(actual_type, layout_node.position, layout_node.layer)
		nodes.append(n)

	# ---- 第二遍：建立连接 ----
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

	# ---- 找根节点：layer 0 的第一个 ----
	var root: MapNode = null
	for n in nodes:
		if n.layer == 0:
			root = n
			break
	if root == null and not nodes.is_empty():
		root = nodes[0]

	# ---- EVENT 节点：roll 奖励 ----
	for n in nodes:
		if n.node_type == MapNode.NodeType.EVENT:
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
			MapNode.NodeType.EVENT,
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
