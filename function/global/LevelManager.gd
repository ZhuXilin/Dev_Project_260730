extends Node

signal all_levels_completed()
signal all_days_completed()

const UNIT_LEVEL_MAP_PATH = "res://content/scenes/levels/UnitLevelMap.tres"
const DEFAULT_UNIT = "枪兵"

var _config: UnitLevelMapConfig = null
var _current_entry: UnitLevelMapEntry = null
var _day_levels: Array = []   # 三天的关卡列表，每个元素是 Array[MapData]
var current_level_index: int = 0
var is_map_mode: bool = false
var current_day: int = 0   # 0 表示第一天

# ===================== 生命周期 =====================
func _ready():
	_load_config()
	_reload_all_levels()

# ===================== 加载配置文件 =====================
func _load_config():
	if ResourceLoader.exists(UNIT_LEVEL_MAP_PATH):
		_config = load(UNIT_LEVEL_MAP_PATH)
		if not _config:
			push_error("UnitLevelMap 加载失败，创建默认配置")
			_create_default_config()
	else:
		print("UnitLevelMap.tres 不存在，创建默认配置")
		_create_default_config()

func _create_default_config():
	_config = UnitLevelMapConfig.new()
	
	# 默认条目
	var default_entry = UnitLevelMapEntry.new()
	default_entry.unit_name = "默认"
	default_entry.day1 = _create_empty_level_list()
	default_entry.day2 = _create_empty_level_list()
	default_entry.day3 = _create_empty_level_list()
	_config.default_entry = default_entry
	
	# 枪兵条目（示例）
	var gun_entry = UnitLevelMapEntry.new()
	gun_entry.unit_name = "枪兵"
	gun_entry.day1 = _create_empty_level_list()
	gun_entry.day2 = _create_empty_level_list()
	gun_entry.day3 = _create_empty_level_list()
	_config.entries.append(gun_entry)
	
	# 保存到文件
	ResourceSaver.save(_config, UNIT_LEVEL_MAP_PATH)
	print("已创建默认 UnitLevelMap.tres，请编辑后重新运行。")

func _create_empty_level_list() -> LevelListResource:
	var list = LevelListResource.new()
	list.levels = []
	return list

# ===================== 根据单位获取条目 =====================
func _get_entry_for_unit(unit_name: String) -> UnitLevelMapEntry:
	if not _config:
		return null
	for entry in _config.entries:
		if entry.unit_name == unit_name:
			return entry
	return _config.default_entry

# ===================== 重新加载所有天的关卡 =====================
func _reload_all_levels():
	var unit_name = GameState.main_unit_name
	if unit_name == "":
		unit_name = DEFAULT_UNIT

	_current_entry = _get_entry_for_unit(unit_name)
	if not _current_entry:
		push_error("未找到单位 %s 的关卡配置，使用默认条目" % unit_name)
		_current_entry = _config.default_entry if _config else null
	if not _current_entry:
		push_error("默认条目也为空，创建临时条目")
		_current_entry = UnitLevelMapEntry.new()
		_current_entry.day1 = _create_empty_level_list()
		_current_entry.day2 = _create_empty_level_list()
		_current_entry.day3 = _create_empty_level_list()

	_day_levels.clear()
	var day_resources = [_current_entry.day1, _current_entry.day2, _current_entry.day3]
	for res in day_resources:
		if res and res is LevelListResource:
			_day_levels.append(res.levels.duplicate())
		else:
			_day_levels.append([])
	print("已加载三天关卡，每天关卡数: ", _day_levels.map(func(arr): return arr.size()))

# ===================== 对外接口 =====================
func get_current_day_levels() -> Array[MapData]:
	if current_day < 0 or current_day >= _day_levels.size():
		return []
	return _day_levels[current_day]

func get_levels_for_day(day: int) -> Array:
	if day < 1 or day > 3:
		return []
	return _day_levels[day - 1]

# 按类型获取地图（用于 MapGenerator）
func get_map_for_node_type(node_type: int, main_unit: String = "") -> MapData:
	var day_levels = get_current_day_levels()
	if day_levels.is_empty():
		var fallback = _create_fallback_map_data()
		fallback.node_type = node_type
		return fallback

	# 按 required_unit 过滤
	var filtered = day_levels.filter(func(m):
		return m.required_unit == "" or m.required_unit == main_unit
	)
	if filtered.is_empty():
		filtered = day_levels.filter(func(m): return m.required_unit == "")
	if filtered.is_empty():
		var fallback = _create_fallback_map_data()
		fallback.node_type = node_type
		return fallback

	# 按 node_type 过滤
	var type_filtered = filtered.filter(func(m):
		return m.node_type == node_type
	)
	if type_filtered.is_empty():
		type_filtered = filtered.filter(func(m):
			return m.node_type == MapNode.NodeType.NORMAL
		)
	if type_filtered.is_empty():
		# 返回第一个并设置类型
		var result = filtered[0]
		result.node_type = node_type
		return result
	return type_filtered[0]

# 推进天数
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

# ===================== 游戏流程控制 =====================
# LevelManager.gd
func start_game():
	# 重置进度（保留队伍，队伍已由 UnitSelectUI 初始化）
	GameState.reset_progress()
	current_level_index = 0
	current_day = 0
	is_map_mode = true
	Globals.is_map_mode = true
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
	var levels = get_current_day_levels()
	if current_level_index < levels.size():
		if is_map_mode:
			get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")
		else:
			load_current_level()
	else:
		emit_signal("all_levels_completed")
		get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func on_defeat():
	GameState.reset_all()
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func is_last_level() -> bool:
	var levels = get_current_day_levels()
	return levels.size() > 0 and current_level_index == levels.size() - 1

func load_current_level():
	var levels = get_current_day_levels()
	if current_level_index < levels.size():
		Globals.reset_all_game_state()
		GameState.current_map_data = levels[current_level_index]
		get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")
	else:
		emit_signal("all_levels_completed")
		get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

# ===================== 辅助 =====================
func _create_fallback_map_data() -> MapData:
	var m = MapData.new()
	m.map_name = "备用地图"
	m.map_size = Vector2i(20, 15)
	m.node_type = MapNode.NodeType.NORMAL
	return m

func reset():
	current_day = 0
	current_level_index = 0
	is_map_mode = false
