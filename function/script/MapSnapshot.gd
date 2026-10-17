class_name MapSnapshot
extends RefCounted

static func serialize(map_data: MapLevelData) -> Dictionary:
	if not map_data:
		return {}

	var snapshot = {
		"day": map_data.day,
		"map_name": map_data.map_name,
		"root_node_id": map_data.root_node.node_id if map_data.root_node else "",
		"nodes": []
	}

	for node in map_data.nodes:
		var node_dict = {
			"node_id": node.node_id,
			"node_type": node.node_type,
			"hidden_node_type": node.hidden_node_type,
			"position_x": node.position.x,
			"position_y": node.position.y,
			"layer": node.layer,
			"custom_label": node.custom_label,
			"reward": node.reward,
			"unlock_relics": node.unlock_relics.duplicate(),
			"unlock_units": node.unlock_units.duplicate(),
			"map_data": _serialize_map_data(node.map_data),
			"connected_node_ids": []
		}

		for conn in node.connected_nodes:
			node_dict["connected_node_ids"].append(conn.node_id)

		snapshot["nodes"].append(node_dict)

	return snapshot


static func _serialize_map_data(map_data: MapData) -> Dictionary:
	if not map_data:
		return {}

	var spawn_points_serialized : Array = []
	for sp in map_data.spawn_points:
		spawn_points_serialized.append([int(sp.x), int(sp.y)])

	# objective_params 里 Vector2i 需要转数组（JSON/Tres 里存不了 Vector2i）
	var params_serialized : Dictionary = {}
	for k in map_data.objective_params:
		var v : Variant = map_data.objective_params[k]
		if v is Vector2i:
			params_serialized[k] = [int(v.x), int(v.y)]
		elif v is Vector2:
			params_serialized[k] = [int(v.x), int(v.y)]
		else:
			params_serialized[k] = v

	return {
		"map_name": map_data.map_name,
		"scene_path": map_data.scene.resource_path if map_data.scene else "",
		"map_size_x": int(map_data.map_size.x),
		"map_size_y": int(map_data.map_size.y),
		"node_type": map_data.node_type,
		"spawn_points": spawn_points_serialized,
		"required_unit": map_data.required_unit,
		"unlock_relics": map_data.unlock_relics.duplicate(),
		"unlock_units": map_data.unlock_units.duplicate(),
		"objective_type": int(map_data.objective_type),
		"objective_params": params_serialized,
		"max_waves": int(map_data.max_waves),
		"reinforcement_count": int(map_data.reinforcement_count),
		"reinforcement_pool": map_data.reinforcement_pool.duplicate(),
	}


static func deserialize(snapshot: Dictionary) -> MapLevelData:
	if snapshot.is_empty():
		return null

	var map_data = MapLevelData.new()
	map_data.day = snapshot.get("day", 1)
	map_data.map_name = snapshot.get("map_name", "")

	var nodes: Array[MapNode] = []
	var node_by_id = {}

	for node_dict_v in snapshot.get("nodes", []):
		var node_dict: Dictionary = node_dict_v
		var node = MapNode.new()
		node.node_id = node_dict.get("node_id", "")
		node.node_type = node_dict.get("node_type", 0) as MapNode.NodeType
		node.hidden_node_type = int(node_dict.get("hidden_node_type", -1))
		node.position = Vector2(
			node_dict.get("position_x", 0),
			node_dict.get("position_y", 0)
		)
		node.layer = node_dict.get("layer", 0)
		node.custom_label = node_dict.get("custom_label", "")
		node.reward = node_dict.get("reward", {})

		var relic_arr: Array[String] = []
		var raw_relics: Array = node_dict.get("unlock_relics", [])
		for rid in raw_relics:
			if rid is String:
				relic_arr.append(rid)
		node.unlock_relics = relic_arr

		var unit_arr: Array[String] = []
		var raw_units: Array = node_dict.get("unlock_units", [])
		for uid in raw_units:
			if uid is String:
				unit_arr.append(uid)
		node.unlock_units = unit_arr

		node.is_visited = false
		node.is_available = false
		node.map_data = _deserialize_map_data(node_dict.get("map_data", {}))

		nodes.append(node)
		node_by_id[node.node_id] = node

	for node_dict_v in snapshot.get("nodes", []):
		var node_dict: Dictionary = node_dict_v
		var node = node_by_id.get(node_dict.get("node_id", ""))
		if not node:
			continue
		var conn_ids: Array = node_dict.get("connected_node_ids", [])
		for conn_id in conn_ids:
			var conn_node = node_by_id.get(conn_id)
			if conn_node and not node.connected_nodes.has(conn_node):
				node.connected_nodes.append(conn_node)

	map_data.nodes = nodes
	map_data.root_node = node_by_id.get(snapshot.get("root_node_id", ""))

	return map_data


static func _deserialize_map_data(data: Dictionary) -> MapData:
	if data.is_empty():
		return null

	var map = MapData.new()
	map.map_name = data.get("map_name", "")
	map.map_size = Vector2i(
		int(data.get("map_size_x", MapConst.DEFAULT_MAP_SIZE.x)),
		int(data.get("map_size_y", MapConst.DEFAULT_MAP_SIZE.y))
	)
	map.node_type = data.get("node_type", MapNode.NodeType.NORMAL) as MapNode.NodeType
	map.required_unit = data.get("required_unit", "")

	var spawn_points: Array[Vector2i] = []
	var raw_sp: Array = data.get("spawn_points", [])
	for sp in raw_sp:
		if sp is Array and sp.size() == 2:
			spawn_points.append(Vector2i(int(sp[0]), int(sp[1])))
		elif sp is Vector2i:
			spawn_points.append(sp)
		elif sp is Vector2:
			spawn_points.append(Vector2i(int(sp.x), int(sp.y)))
	map.spawn_points = spawn_points

	var relic_arr : Array[String] = []
	var raw_relics: Array = data.get("unlock_relics", [])
	for rid in raw_relics:
		if rid is String:
			relic_arr.append(rid)
	map.unlock_relics = relic_arr

	var unit_arr : Array[String] = []
	var raw_units: Array = data.get("unlock_units", [])
	for uid in raw_units:
		if uid is String:
			unit_arr.append(uid)
	map.unlock_units = unit_arr

	# ★ v4.4：目标字段
	map.objective_type = int(data.get("objective_type", 0)) as MapData.ObjectiveType
	var params_raw : Dictionary = data.get("objective_params", {})
	map.objective_params = {}
	for k in params_raw:
		var v : Variant = params_raw[k]
		# 约定：[int, int] 或 [float, float] 视为 Vector2i
		if v is Array and (v as Array).size() == 2:
			var arr : Array = v
			var t0 : int = typeof(arr[0])
			var t1 : int = typeof(arr[1])
			var is_num0 : bool = (t0 == TYPE_INT or t0 == TYPE_FLOAT)
			var is_num1 : bool = (t1 == TYPE_INT or t1 == TYPE_FLOAT)
			if is_num0 and is_num1:
				map.objective_params[k] = Vector2i(int(arr[0]), int(arr[1]))
				continue
		if typeof(v) == TYPE_FLOAT:
			map.objective_params[k] = int(v)
		else:
			map.objective_params[k] = v

	map.max_waves = maxi(1, int(data.get("max_waves", 1)))
	map.reinforcement_count = maxi(0, int(data.get("reinforcement_count", 0)))
	var raw_pool : Array = data.get("reinforcement_pool", [])
	var pool_arr : Array[String] = []
	for pid in raw_pool:
		if pid is String and (pid as String) != "":
			pool_arr.append(pid)
	map.reinforcement_pool = pool_arr

	var scene_path = data.get("scene_path", "")

	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene = load(scene_path) as PackedScene
		if scene:
			map.scene = scene
		else:
			print("警告：无法加载场景 ", scene_path)

	return map
