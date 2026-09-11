class_name MapSnapshot
extends RefCounted

# ---- 序列化：MapLevelData → 纯 Dictionary（无任何 Resource 对象） ----
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
			"position_x": node.position.x,
			"position_y": node.position.y,
			"layer": node.layer,
			"custom_label": node.custom_label,
			"map_data": _serialize_map_data(node.map_data),
			"connected_node_ids": []
		}
		
		for conn in node.connected_nodes:
			node_dict["connected_node_ids"].append(conn.node_id)
		
		snapshot["nodes"].append(node_dict)
	
	return snapshot

# ---- MapData → Dictionary（只存纯数据，不存 Resource） ----
static func _serialize_map_data(map_data: MapData) -> Dictionary:
	if not map_data:
		return {}
	
	var spawn_points_serialized = []
	for sp in map_data.spawn_points:
		spawn_points_serialized.append([sp.x, sp.y])
	
	return {
		"map_name": map_data.map_name,
		"scene_path": map_data.scene.resource_path if map_data.scene else "",
		"map_size_x": map_data.map_size.x,
		"map_size_y": map_data.map_size.y,
		"node_type": map_data.node_type,
		"spawn_points": spawn_points_serialized,
		"required_unit": map_data.required_unit
	}

# ---- 反序列化：Dictionary → MapLevelData ----
static func deserialize(snapshot: Dictionary) -> MapLevelData:
	if snapshot.is_empty():
		return null
	
	var map_data = MapLevelData.new()
	map_data.day = snapshot.get("day", 1)
	map_data.map_name = snapshot.get("map_name", "")
	
	var nodes: Array[MapNode] = []
	var node_by_id = {}
	
	# 第一遍：创建节点
	for node_dict in snapshot.get("nodes", []):
		var node = MapNode.new()
		node.node_id = node_dict.get("node_id", "")
		node.node_type = node_dict.get("node_type", 0)
		node.position = Vector2(
			node_dict.get("position_x", 0),
			node_dict.get("position_y", 0)
		)
		node.layer = node_dict.get("layer", 0)
		node.custom_label = node_dict.get("custom_label", "")
		node.is_visited = false
		node.is_available = false
		node.map_data = _deserialize_map_data(node_dict.get("map_data", {}))
		
		nodes.append(node)
		node_by_id[node.node_id] = node
	
	# 第二遍：恢复连接
	for node_dict in snapshot.get("nodes", []):
		var node = node_by_id.get(node_dict.get("node_id", ""))
		if not node:
			continue
		for conn_id in node_dict.get("connected_node_ids", []):
			var conn_node = node_by_id.get(conn_id)
			if conn_node and not node.connected_nodes.has(conn_node):
				node.connected_nodes.append(conn_node)
	
	map_data.nodes = nodes
	map_data.root_node = node_by_id.get(snapshot.get("root_node_id", ""))
	
	return map_data

# ---- Dictionary → MapData ----
static func _deserialize_map_data(data: Dictionary) -> MapData:
	if data.is_empty():
		return null
	
	var map = MapData.new()
	map.map_name = data.get("map_name", "")
	map.map_size = Vector2i(
		data.get("map_size_x", 20),
		data.get("map_size_y", 15)
	)
	map.node_type = data.get("node_type", MapNode.NodeType.NORMAL)
	map.required_unit = data.get("required_unit", "")
	
	# ---- 恢复 spawn_points ----
	var spawn_points: Array[Vector2i] = []
	for sp in data.get("spawn_points", []):
		if sp is Array and sp.size() == 2:
			spawn_points.append(Vector2i(int(sp[0]), int(sp[1])))
	map.spawn_points = spawn_points
	
	# ---- 恢复 scene（从路径加载 PackedScene） ----
	var scene_path = data.get("scene_path", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene = load(scene_path) as PackedScene
		if scene:
			map.scene = scene
		else:
			print("警告：无法加载场景 ", scene_path)
	
	return map
