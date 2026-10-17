class_name MapGenerator
extends Node

const NON_COMBAT_TYPES : Array = [
	MapNode.NodeType.TREASURE,
	MapNode.NodeType.FORGE,
	MapNode.NodeType.CHAPEL,
]

const COMBAT_TYPES : Array = [
	MapNode.NodeType.START,
	MapNode.NodeType.NORMAL,
	MapNode.NodeType.ELITE,
	MapNode.NodeType.BOSS,
]


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

		indices.sort_custom(func(a, b):
			var pa : Array = day_layout.nodes[a].random_pool
			var pb : Array = day_layout.nodes[b].random_pool
			var sa : int = pa.size() if not pa.is_empty() else 999
			var sb : int = pb.size() if not pb.is_empty() else 999
			return sa < sb
		)

		var used_types : Dictionary = {}
		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			if ln.random_pool.is_empty():
				used_types[ln.node_type] = true

		for idx in indices:
			var ln : MapLayoutNode = day_layout.nodes[idx]
			if ln.random_pool.is_empty():
				resolved_types[idx] = ln.node_type
				continue
			var available : Array = []
			for t in ln.random_pool:
				if not used_types.has(t):
					available.append(t)
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
		n.unlock_relics = ln.unlock_relics.duplicate()
		n.unlock_units = ln.unlock_units.duplicate()

		# 问号节点解析
		if n.node_type == MapNode.NodeType.QUESTION:
			n.hidden_node_type = _roll_question_node_type()

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

	# ★ 问号保底：每层至少一个非战斗结果
	_apply_question_guarantee(nodes)

	_assign_map_data_to_all_nodes(nodes)

	data.nodes = nodes
	data.root_node = root
	data.map_name = "第%d天" % day
	return data


# ============================================================
#  问号节点掷骰（战斗类型）
# ============================================================
static func _roll_question_node_type() -> int:
	var tag_weights : Dictionary = {}
	for ud in GameState.party:
		if ud.is_dead:
			continue
		for tag in ud.tags:
			tag_weights[tag] = tag_weights.get(tag, 0) + 1

	var top_tags : Array = []
	var sorted_tags = tag_weights.keys()
	sorted_tags.sort_custom(func(a, b): return tag_weights[a] > tag_weights[b])
	if sorted_tags.size() > 0:
		top_tags.append(sorted_tags[0])
	if sorted_tags.size() > 1:
		top_tags.append(sorted_tags[1])

	var pool : Array = [
		{"type": MapNode.NodeType.NORMAL,  "weight": 40, "tag": ""},
		{"type": MapNode.NodeType.ELITE,   "weight": 25, "tag": ""},
		{"type": MapNode.NodeType.TREASURE,"weight": 20, "tag": ""},
		{"type": MapNode.NodeType.FORGE,   "weight": 10, "tag": ""},
		{"type": MapNode.NodeType.CHAPEL,  "weight": 5,  "tag": ""},
	]

	for entry in pool:
		var t_type = entry["type"]
		var add_w = 0
		for t in top_tags:
			match t:
				"守护", "献祭":
					if t_type in [MapNode.NodeType.NORMAL, MapNode.NodeType.ELITE]:
						add_w += 15
					if t_type == MapNode.NodeType.CHAPEL:
						add_w += 10
				"烈焰", "灰烬":
					if t_type == MapNode.NodeType.ELITE:
						add_w += 20
					if t_type == MapNode.NodeType.TREASURE:
						add_w += 15
				"轮回", "余烬":
					if t_type == MapNode.NodeType.TREASURE:
						add_w += 10
					if t_type == MapNode.NodeType.FORGE:
						add_w += 15
		entry["weight"] += add_w

	var total : int = 0
	for entry in pool:
		total += entry["weight"]
	var roll : int = randi() % total
	var acc : int = 0
	for entry in pool:
		acc += entry["weight"]
		if roll < acc:
			return entry["type"]

	return MapNode.NodeType.NORMAL


# ============================================================
#  ★ 问号保底：每层至少一个非战斗结果
# ============================================================
static func _apply_question_guarantee(nodes: Array) -> void:
	# 按层分组
	var by_layer : Dictionary = {}
	for n in nodes:
		if not by_layer.has(n.layer):
			by_layer[n.layer] = []
		by_layer[n.layer].append(n)

	for layer_key in by_layer:
		var layer_nodes : Array = by_layer[layer_key]

		# 1. 该层已有显式非战斗节点？跳过
		var has_explicit_non_combat : bool = false
		for n in layer_nodes:
			if n.node_type in NON_COMBAT_TYPES:
				has_explicit_non_combat = true
				break
		if has_explicit_non_combat:
			continue

		# 2. 收集该层所有 QUESTION 节点
		var question_nodes : Array = []
		for n in layer_nodes:
			if n.node_type == MapNode.NodeType.QUESTION:
				question_nodes.append(n)
		if question_nodes.is_empty():
			continue

		# 3. QUESTION 解析后是否已有非战斗？
		var has_non_combat_question : bool = false
		for n in question_nodes:
			if n.hidden_node_type in NON_COMBAT_TYPES:
				has_non_combat_question = true
				break
		if has_non_combat_question:
			continue

		# 4. 全战斗 → 强制把其中一个 QUESTION 改为非战斗
		var target : MapNode = question_nodes[randi() % question_nodes.size()]
		target.hidden_node_type = _roll_non_combat_question_type()
		print("[MapGenerator] 问号保底：layer %d 强制 QUESTION → %s" % [
			layer_key, MapConst.get_node_display_name(target.hidden_node_type)])


# ============================================================
#  保底专用：非战斗 QUESTION 类型掷骰
# ============================================================
static func _roll_non_combat_question_type() -> int:
	var tag_weights : Dictionary = {}
	for ud in GameState.party:
		if ud.is_dead:
			continue
		for tag in ud.tags:
			tag_weights[tag] = tag_weights.get(tag, 0) + 1

	var pool : Array = [
		{"type": MapNode.NodeType.TREASURE, "weight": 70},
		{"type": MapNode.NodeType.FORGE,    "weight": 30},
	]

	for entry in pool:
		if entry["type"] == MapNode.NodeType.TREASURE:
			if tag_weights.has("守护") or tag_weights.has("献祭"):
				entry["weight"] += 15
		elif entry["type"] == MapNode.NodeType.FORGE:
			if tag_weights.has("轮回") or tag_weights.has("余烬"):
				entry["weight"] += 15

	var total : int = 0
	for entry in pool:
		total += entry["weight"]
	var roll : int = randi() % total
	var acc : int = 0
	for entry in pool:
		acc += entry["weight"]
		if roll < acc:
			return entry["type"]
	return MapNode.NodeType.TREASURE


# ============================================================
#  节点创建
# ============================================================
static func _create_node(type: MapNode.NodeType, pos: Vector2, layer: int) -> MapNode:
	var node = MapNode.new()
	node.node_type = type
	node.position = pos
	node.layer = layer
	node.is_available = false
	node.is_visited = false
	node.node_id = "L%d_X%d_Y%d" % [layer, int(pos.x * 10.0), int(pos.y * 10.0)]
	return node


# ============================================================
#  地图数据分配
# ============================================================
static func _assign_map_data_to_all_nodes(nodes: Array):
	var combat_nodes_by_type : Dictionary = {}
	for node in nodes:
		var real_type : int = node.node_type
		if node.node_type == MapNode.NodeType.QUESTION and node.hidden_node_type != -1:
			real_type = node.hidden_node_type

		if real_type in NON_COMBAT_TYPES:
			var placeholder = MapData.new()
			placeholder.node_type = real_type
			node.map_data = placeholder
			continue

		if not combat_nodes_by_type.has(real_type):
			combat_nodes_by_type[real_type] = []
		combat_nodes_by_type[real_type].append(node)

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
