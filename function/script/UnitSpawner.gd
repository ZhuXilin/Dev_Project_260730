extends Node
class_name UnitSpawner

const UNIT_PATH = Config.PATHS.UNIT_SCENE


static func extract_configs_from_node(node: Node) -> Array[UnitConfig]:
	var configs: Array[UnitConfig] = []
	_find_unit_placers(node, configs)
	return configs


static func _find_unit_placers(node: Node, configs: Array[UnitConfig]):
	if node is UnitPlacerTool:
		var mode : int = node.placement_mode
		if mode == UnitPlacerTool.PlacementMode.FIXED_UNIT \
				or mode == UnitPlacerTool.PlacementMode.RANDOM_POOL:
			configs.append(node.export_config())
	for child in node.get_children():
		_find_unit_placers(child, configs)


# ============================================================
#  随机池：按 pool_key 分组，取组内第一个非空 enemy_pool 作为权威池
# ============================================================
static func _build_pool_map(configs: Array[UnitConfig]) -> Dictionary:
	# 返回 { pool_key: Array[String] }
	# 对于 pool_key == "" 的格子不进入此 map（直接用自身 enemy_pool）
	var pool_map : Dictionary = {}
	for cfg in configs:
		if not cfg.is_random_pool: continue
		if cfg.pool_key == "": continue
		if pool_map.has(cfg.pool_key): continue
		if not cfg.enemy_pool.is_empty():
			pool_map[cfg.pool_key] = cfg.enemy_pool.duplicate()
	return pool_map


static func _roll_enemy_for_config(cfg: UnitConfig, pool_map: Dictionary) -> String:
	var pool : Array = []
	if cfg.pool_key != "" and pool_map.has(cfg.pool_key):
		pool = pool_map[cfg.pool_key]
	elif not cfg.enemy_pool.is_empty():
		pool = cfg.enemy_pool
	if pool.is_empty():
		push_warning("[UnitSpawner] RANDOM_POOL 格子没有可用池子，pos=%s pool_key=%s" % [
			str(cfg.position), cfg.pool_key])
		return ""
	return pool[randi() % pool.size()]


static func spawn_units_from_configs(parent: Node, configs: Array[UnitConfig], grid_to_world_func: Callable):
	var pool_map : Dictionary = _build_pool_map(configs)

	for cfg in configs:
		var actual_name : String = cfg.unit_name
		if cfg.is_random_pool:
			actual_name = _roll_enemy_for_config(cfg, pool_map)
			if actual_name == "":
				continue  # 没池子，跳过

		var stats = _create_unit_stats(cfg, actual_name)
		var unit = load(UNIT_PATH).instantiate()
		unit.setup_unit(stats, cfg.position, cfg.initial_items)
		# ★ 把波次写到 Unit 的 meta，WaveManager 会读取
		unit.set_meta("wave", cfg.wave)
		parent.add_child(unit)
		unit.position = grid_to_world_func.call(cfg.position)
		UnitManager.register_unit(unit)


static func _create_unit_stats(cfg: UnitConfig, actual_unit_name: String = "") -> UnitData:
	var name_key : String = actual_unit_name if actual_unit_name != "" else cfg.unit_name
	var stats = UnitDataManager.get_default_stats(name_key)
	stats.unit_name = name_key
	# RANDOM_POOL 抽出来的名字才是权威名字，忽略作者预填的 display_name
	if cfg.is_random_pool:
		stats.display_name = name_key
	else:
		stats.display_name = cfg.display_name if cfg.display_name != "" else name_key
	stats.faction = cfg.faction
	cfg.apply_override(stats)
	stats.team_id = cfg.team_id
	stats.is_boss = cfg.is_boss
	if cfg.immobile and cfg.team_id == 1:
		stats.move_range = 0

	if cfg.team_id == 1 and GameState.current_map_data != null:
		var mult := 1.0
		if cfg.is_boss:
			mult = 2.0
		else:
			match GameState.current_map_data.node_type:
				MapNode.NodeType.ELITE: mult = 1.5
				MapNode.NodeType.BOSS:  mult = 1.2
				_: mult = 1.0
		var extra_hp : float = maxf(1.0, GameState.current_map_data.enemy_hp_multiplier)
		stats.max_hp = int(stats.max_hp * mult * extra_hp)
		stats.hit_points = stats.max_hp

		var day_mult : float = 1.0
		match GameState.current_day:
			1: day_mult = 0.8
			2: day_mult = 1.0
			3: day_mult = 1.2
			_: day_mult = 1.0
		stats.strength = maxi(1, int(stats.strength * day_mult))
		stats.dexterity = maxi(1, int(stats.dexterity * day_mult))

	return stats


static func spawn_test_units(parent: Node, grid_to_world_func: Callable):
	var configs: Array[UnitConfig] = []

	var p1 = UnitConfig.new()
	p1.unit_name = "剑士"
	p1.team_id = 0
	p1.position = Vector2i(15, 10)
	configs.append(p1)

	var p2 = UnitConfig.new()
	p2.unit_name = "枪兵"
	p2.team_id = 0
	p2.position = Vector2i(15, 11)
	configs.append(p2)

	var e1 = UnitConfig.new()
	e1.unit_name = "枪兵"
	e1.team_id = 1
	e1.position = Vector2i(3, 3)
	configs.append(e1)

	var e2 = UnitConfig.new()
	e2.unit_name = "斧兵"
	e2.team_id = 1
	e2.position = Vector2i(3, 4)
	configs.append(e2)

	spawn_units_from_configs(parent, configs, grid_to_world_func)


static func spawn_party_from_gamestate(parent: Node, grid_to_world_func: Callable, spawn_points: Array[Vector2i]):
	var party = GameState.get_party_units()
	var alive : Array = []
	for u in party:
		if not u.is_dead:
			alive.append(u)

	var count = min(alive.size(), spawn_points.size())

	if alive.is_empty():
		print("[UnitSpawner] 警告：全队阵亡，无法生成单位")
		return

	print("=== UnitSpawner: 队伍装备状态（存活 %d/%d） ===" % [alive.size(), party.size()])
	for i in range(alive.size()):
		var u = alive[i]
		var weapon_id = u.weapon_slot.item_id if u.weapon_slot else "无"
		print("单位 ", i, ": ", u.unit_name, " 武器: ", weapon_id)
	print("================================")

	for i in range(count):
		var unit_data = alive[i]
		var spawn_cell = spawn_points[i]
		# ★ v4.6：出战前强制满血（三重保险之一）
		unit_data.hit_points = unit_data.max_hp
		var unit = load(UNIT_PATH).instantiate()
		unit.restore_from_unit_data(unit_data, spawn_cell)

		var weapon_id = unit.weapon_slot.item_id if unit.weapon_slot else "无"
		print("恢复后单位 ", i, ": ", unit.unit_stats.unit_name, " 武器: ", weapon_id)

		parent.add_child(unit)
		unit.position = grid_to_world_func.call(spawn_cell)
		UnitManager.register_unit(unit)
