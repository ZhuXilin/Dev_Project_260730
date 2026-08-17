extends Node
class_name UnitSpawner

const UnitDataManagerClass = preload("res://function/script/UnitDataManager.gd")
const UNIT_PATH = Config.PATHS.UNIT_SCENE

static func extract_configs_from_node(node: Node) -> Array[UnitConfig]:
	var configs: Array[UnitConfig] = []
	_find_unit_placers(node, configs)
	return configs

static func _find_unit_placers(node: Node, configs: Array[UnitConfig]):
	if node is UnitPlacerTool:
		# 只收集固定单位模式，忽略出生点
		if node.placement_mode == UnitPlacerTool.PlacementMode.FIXED_UNIT:
			configs.append(node.export_config())
	# 递归遍历子节点
	for child in node.get_children():
		_find_unit_placers(child, configs)

static func spawn_units_from_configs(parent: Node, configs: Array[UnitConfig], grid_to_world_func: Callable):
	for cfg in configs:
		var stats = _create_unit_stats(cfg)
		var unit = load(UNIT_PATH).instantiate()
		unit.setup_unit(stats, cfg.position, cfg.initial_items)   # 直接使用 cfg.initial_items（已包含默认武器）
		parent.add_child(unit)
		unit.position = grid_to_world_func.call(cfg.position)
		UnitManager.register_unit(unit)

static func _create_unit_stats(cfg: UnitConfig) -> UnitData:
	var stats = UnitDataManager.get_default_stats(cfg.unit_name)
	stats.unit_name = cfg.unit_name
	stats.display_name = cfg.display_name if cfg.display_name != "" else cfg.unit_name
	stats.faction = cfg.faction
	cfg.apply_override(stats)
	stats.team_id = cfg.team_id
	if cfg.immobile and cfg.team_id == 1:
		stats.move_range = 0
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
	var count = min(party.size(), spawn_points.size())
	for i in range(count):
		var unit_data = party[i]
		var spawn_cell = spawn_points[i]
		var unit = load(UNIT_PATH).instantiate()
		unit.restore_from_unit_data(unit_data, spawn_cell)
		parent.add_child(unit)
		unit.position = grid_to_world_func.call(spawn_cell)
		UnitManager.register_unit(unit)
