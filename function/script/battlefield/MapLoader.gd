class_name MapLoader
extends RefCounted

var _bf : Node2D

func _init(bf: Node2D):
	_bf = bf


# ============================================================
#  公开入口
# ============================================================
func load_map(new_map_data: MapData) -> void:
	print("=== load_map 被调用 ===")
	if UnitManager.unit_list.is_empty() and GameState.party.is_empty():
		print("没有任何单位，生成测试单位")
		UnitSpawner.spawn_test_units(_bf, _bf.grid_to_world)
	if not new_map_data:
		print("地图数据为空，加载默认地图")
		load_default_map()
		return

	print("地图名称：", new_map_data.map_name)
	GameState.current_map_data = new_map_data
	_bf.current_node_type = new_map_data.node_type

	var map_pixel_rect : Rect2
	var tilemap : TileMapLayer = null
	var main_scene_instance : Node = null
	var used_rect : Rect2i = Rect2i()
	var spawn_points : Array[Vector2i] = []

	if new_map_data.scene:
		var scene_path = new_map_data.scene.resource_path
		print("加载场景：", scene_path)

		var scene = load(scene_path) as PackedScene
		if scene:
			main_scene_instance = scene.instantiate()
			if main_scene_instance:
				tilemap = _find_tilemap(main_scene_instance)
				if tilemap:
					_remove_old_terrain()

					main_scene_instance.name = "TerrainTileMap"
					_bf.add_child(main_scene_instance)
					_bf.move_child(main_scene_instance, 0)
					tilemap.z_index = -1
					used_rect = tilemap.get_used_rect()
					if used_rect.size.x > 0 and used_rect.size.y > 0:
						_bf.map_grid_size = used_rect.size
					else:
						_bf.map_grid_size = new_map_data.map_size
					TerrainManager.grid_size = _bf.map_grid_size
					TerrainManager.load_from_tilemap(tilemap, _bf.map_grid_size)
					_extract_map_unit_placers(main_scene_instance)

					spawn_points = _extract_spawn_points(main_scene_instance)
					if spawn_points.size() > 0:
						print("提取到出生点：", spawn_points)
				else:
					print("错误：场景中未找到 TileMapLayer，使用默认地形")
					if main_scene_instance:
						main_scene_instance.queue_free()
						main_scene_instance = null
			else:
				print("错误：无法实例化场景：", scene_path)
		else:
			print("错误：无法加载场景文件：", scene_path)

	if not tilemap:
		_remove_old_terrain()
		_generate_default_terrain(new_map_data.map_size)
		used_rect = Rect2i(Vector2i.ZERO, _bf.map_grid_size)
		map_pixel_rect = Rect2(Vector2.ZERO, new_map_data.map_size * MapConst.CELL_SIZE)
		_bf.menu_blocker.size = new_map_data.map_size * MapConst.CELL_SIZE
		_bf.menu_blocker.position = Vector2.ZERO
	else:
		map_pixel_rect = Rect2(
			used_rect.position * MapConst.CELL_SIZE,
			used_rect.size * MapConst.CELL_SIZE
		)
		_bf.menu_blocker.size = used_rect.size * MapConst.CELL_SIZE
		_bf.menu_blocker.position = used_rect.position * MapConst.CELL_SIZE

	_clear_units()

	var configs : Array[UnitConfig] = []
	if main_scene_instance:
		configs = UnitSpawner.extract_configs_from_node(main_scene_instance)
	if configs.size() > 0:
		print("从场景提取到 ", configs.size(), " 个固定单位")
		UnitSpawner.spawn_units_from_configs(_bf, configs, _bf.grid_to_world)
	else:
		print("场景中没有固定单位配置")

	if GameState.party.size() > 0 and spawn_points.size() > 0:
		print("使用队伍数据生成单位，队伍大小：", GameState.party.size(), "，出生点数：", spawn_points.size())
		UnitSpawner.spawn_party_from_gamestate(_bf, _bf.grid_to_world, spawn_points)
	else:
		if GameState.party.size() == 0:
			print("队伍为空")
		if spawn_points.size() == 0:
			print("没有出生点")

	if UnitManager.unit_list.is_empty():
		print("没有任何单位，生成测试单位")
		UnitSpawner.spawn_test_units(_bf, _bf.grid_to_world)

	for unit in UnitManager.unit_list:
		unit.position = _bf.grid_to_world(unit.grid_cell)
		unit.z_index = 1

	_bf.menu_blocker.z_index = 2
	_bf.camera_controller.set_map_boundary(map_pixel_rect)
	print("地图边界（像素）:", map_pixel_rect)

	center_camera_on_player()
	TurnManager.map_functions = _bf.map_functions
	print("地图加载完成：", new_map_data.map_name)


func load_default_map() -> void:
	print("加载默认测试地图")
	var default_map = MapData.new()
	default_map.map_name = "默认地图"
	default_map.scene = null
	default_map.map_size = MapConst.DEFAULT_MAP_SIZE
	load_map(default_map)


# ============================================================
#  内部：场景 / 地形
# ============================================================
func _clear_units() -> void:
	for child in _bf.get_children():
		if child is Unit:
			UnitManager.unregister_unit(child)
			child.queue_free()


func _remove_old_terrain() -> void:
	var old = _bf.get_node_or_null("TerrainTileMap")
	if old:
		_bf.remove_child(old)
		old.free()
		print("已清理旧地形节点")


func _find_tilemap(node: Node) -> TileMapLayer:
	if not node:
		return null
	if node is TileMapLayer:
		return node
	for child in node.get_children():
		var found = _find_tilemap(child)
		if found:
			return found
	return null


func _generate_default_terrain(map_size: Vector2i) -> void:
	_bf.map_grid_size = map_size
	TerrainManager.grid_size = map_size
	var grid = []
	for y in range(map_size.y):
		var row = []
		for x in range(map_size.x):
			row.append(TerrainManager.TerrainType.PLAIN)
		grid.append(row)
	TerrainManager.terrain_grid = grid
	print("生成默认平地地形，尺寸：", map_size)


# ============================================================
#  内部：功能格 / 出生点
# ============================================================
func _extract_map_unit_placers(node: Node) -> void:
	_bf.map_functions.clear()
	var battle_start_event = ""
	var tool_nodes : Array[Node] = []

	_find_tools(node, tool_nodes)

	for tool in tool_nodes:
		var cfg = tool.export_config()
		var cell : Vector2i
		if cfg is Dictionary:
			if cfg.has("position"):
				cell = cfg["position"]
			else:
				continue
		else:
			continue

		var entry = {"triggered": false}

		match cfg.get("type", ""):
			"event_trigger":
				var event_id = cfg.get("event_id", "")
				var relics : Array = cfg.get("unlock_relics", [])

				if event_id != "":
					entry["event_id"] = event_id
					_bf.map_functions[cell] = entry
					print("功能格: 位置 ", cell, " 事件ID: ", event_id)
				elif not relics.is_empty():
					var generated_id = "unlock_%d_%d" % [cell.x, cell.y]
					var actions = [{ "type": "unlock_relics", "relic_ids": relics }]
					EventManager.register_event(generated_id, { "actions": actions, "once": true })
					entry["event_id"] = generated_id
					_bf.map_functions[cell] = entry
					print("功能格: 位置 ", cell, " 自动解锁遗物: ", relics)

			"hp_function":
				var amount = cfg.get("hp_amount", 0)
				if amount != 0:
					var generated_id = "hp_%d_%d" % [cell.x, cell.y]
					var action_type = "heal" if amount > 0 else "damage"
					var actions = [{ "type": action_type, "amount": amount }]
					EventManager.register_event(generated_id, { "actions": actions, "once": false })
					entry["event_id"] = generated_id
					_bf.map_functions[cell] = entry
					print("功能格: 位置 ", cell, " HP事件: ", generated_id)

			"battle_start":
				var event_id = cfg.get("event_id", "")
				if event_id != "":
					battle_start_event = event_id
					print("战斗开始事件: ", event_id)

			_:
				pass

	_bf._battle_start_event_id = battle_start_event
	print("共提取 ", _bf.map_functions.size(), " 个功能格，战斗开始事件: ", battle_start_event)

	for tool in tool_nodes:
		if is_instance_valid(tool):
			tool.queue_free()


func _find_tools(node: Node, result: Array) -> void:
	if node is EventTrigger or node is HpFunction or node is BattleStartEvent:
		result.append(node)
	for child in node.get_children():
		_find_tools(child, result)


func _extract_spawn_points(node: Node) -> Array[Vector2i]:
	var points = []
	_find_spawn_points(node, points)
	points.sort_custom(func(a, b): return a["index"] < b["index"])
	var result : Array[Vector2i] = []
	for p in points:
		result.append(p["position"])
	return result


func _find_spawn_points(node: Node, result: Array) -> void:
	if node is UnitPlacerTool:
		var cfg = node.export_config()
		if cfg is Dictionary and cfg.get("type") == "spawn_point":
			result.append({
				"position": cfg["position"],
				"index": cfg["spawn_index"]
			})
	for child in node.get_children():
		_find_spawn_points(child, result)


# ============================================================
#  内部：相机
# ============================================================
func center_camera_on_player() -> void:
	var player_units = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == 0 and unit.hit_points > 0:
			player_units.append(unit)
	if player_units.size() > 0:
		var target_unit = player_units[0]
		var target_pos = _bf.grid_to_world(target_unit.grid_cell)
		target_pos = _bf.camera_controller.clamp_position(target_pos)
		_bf.camera_controller.smooth_move_to(target_pos, 0.0, true)
	else:
		var viewport_size = _bf.get_viewport().get_visible_rect().size
		var center = _bf.camera_controller.map_rect.position + _bf.camera_controller.map_rect.size / 2
		var target_pos = center - viewport_size / 2
		target_pos = _bf.camera_controller.clamp_position(target_pos)
		_bf.camera_controller.smooth_move_to(target_pos, 0.0, true)
