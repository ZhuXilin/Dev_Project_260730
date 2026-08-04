extends Node

signal all_levels_completed()
signal all_days_completed()

const LEVEL_LIST_PATH : String = Config.PATHS.LEVEL_LIST

var current_level_index : int = 0
var _levels : Array[MapData] = []
var _days_levels: Array = []
var _levels_by_type: Dictionary = {}
var _type_index: Dictionary = {}
var is_map_mode: bool = false
var current_day: int = 0   # 0表示第1天，内部从0开始

func _ready():
	_load_level_list()

func _load_level_list():
	const LevelListScript = preload("res://function/resource/LevelList.gd")
	if not ResourceLoader.exists(LEVEL_LIST_PATH):
		push_error("关卡列表文件不存在：", LEVEL_LIST_PATH)
		_use_fallback_levels()
		return
	var level_list = load(LEVEL_LIST_PATH)
	if not level_list:
		push_error("无法加载关卡列表资源：", LEVEL_LIST_PATH)
		_use_fallback_levels()
		return
	if level_list is LevelListScript:
		_levels = level_list.levels
		print("成功加载关卡列表，共 ", _levels.size(), " 关")
		_group_levels_by_type()
		_group_levels_by_day()
	else:
		push_error("关卡列表资源类型错误，期望 LevelList 类型：", LEVEL_LIST_PATH)
		_use_fallback_levels()

func _use_fallback_levels():
	print("使用硬编码默认关卡（仅用于测试）")
	_levels = []
	var fallback_map = load("res://content/maps/Level01.tres") as MapData
	if fallback_map:
		_levels.append(fallback_map)
	_group_levels_by_type()
	_group_levels_by_day()

func _group_levels_by_type():
	_levels_by_type.clear()
	_type_index.clear()
	
	for type in range(8):
		_levels_by_type[type] = []
		_type_index[type] = 0
	
	for map_res in _levels:
		var type = MapNode.NodeType.NORMAL
		if map_res.node_type != null:
			type = map_res.node_type as MapNode.NodeType
		if not _levels_by_type.has(type):
			_levels_by_type[type] = []
		_levels_by_type[type].append(map_res)
	
	print("=== 按类型分组 ===")
	for type in _levels_by_type:
		if _levels_by_type[type].size() > 0:
			print("  类型 ", type, "：", _levels_by_type[type].size(), " 个地图")

func _group_levels_by_day():
	_days_levels.clear()
	var per_day = 3
	var total = _levels.size()
	for day in range(3):
		var start = day * per_day
		var end = min(start + per_day, total)
		var day_levels: Array[MapData] = []
		for i in range(start, end):
			day_levels.append(_levels[i])
		_days_levels.append(day_levels)
	while _days_levels.size() < 3:
		var last = _days_levels[-1] if not _days_levels.is_empty() else []
		_days_levels.append(last.duplicate())
	print("已按天分组：", _days_levels.size(), "天，每天", _days_levels[0].size(), "个关卡")

func get_levels_for_day(day: int) -> Array:
	if day >= 1 and day <= _days_levels.size():
		return _days_levels[day-1]
	return []

func get_map_for_node_type(node_type: int, main_unit: String = "") -> MapData:
	var all_maps = _levels_by_type.get(node_type, [])
	var filtered = all_maps.filter(func(m): return m.required_unit == "" or m.required_unit == main_unit)
	if filtered.is_empty():
		filtered = all_maps.filter(func(m): return m.required_unit == "")
	if filtered.is_empty():
		return _create_fallback_map_data()
	var idx = _type_index.get(node_type, 0)
	var result = filtered[idx % filtered.size()]
	_type_index[node_type] = (idx + 1) % filtered.size()
	return result

func _create_fallback_map_data() -> MapData:
	var m = MapData.new()
	m.map_name = "备用地图"
	m.map_size = Vector2i(20, 15)
	m.node_type = MapNode.NodeType.NORMAL
	return m

func get_current_day_levels() -> Array:
	return get_levels_for_day(current_day + 1)

func advance_day() -> bool:
	current_day += 1
	print("advance_day: current_day=", current_day)
	if current_day >= 3:
		all_days_completed.emit()
		return false
	GameState.visited_nodes.clear()
	GameState.cached_map_level_data = null
	GameState.cached_day = -1
	return true
	
func start_game():
	if _days_levels.is_empty() or _days_levels[0].is_empty():
		push_error("没有可用的关卡！")
		return
	current_level_index = 0
	current_day = 0
	is_map_mode = true
	Globals.is_map_mode = true
	GameState.visited_nodes.clear()
	get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")

func load_map(map_data: MapData):
	if not map_data:
		push_error("尝试加载空地图数据")
		return
	Globals.reset_all_game_state()
	GameState.current_map_data = map_data
	Globals.is_map_mode = true
	get_tree().change_scene_to_file("res://content/scenes/levels/Battlefield.tscn")

func on_victory():
	current_level_index += 1
	if current_level_index < _levels.size():
		if is_map_mode:
			get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")
		else:
			load_current_level()
	else:
		emit_signal("all_levels_completed")
		get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func on_defeat():
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func is_last_level() -> bool:
	if _levels.size() == 0:
		return true
	return current_level_index == _levels.size() - 1

func load_current_level():
	if current_level_index < _levels.size():
		Globals.reset_all_game_state()
		GameState.current_map_data = _levels[current_level_index]
		get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")
	else:
		emit_signal("all_levels_completed")
		get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
