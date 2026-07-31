extends Node

signal all_levels_completed()

const LEVEL_LIST_PATH : String = "res://content/scenes/levels/LevelList.tres"

var current_level_index : int = 0
var _levels : Array[MapData] = []
var _days_levels: Array = []  # 每个元素是 Array[MapData]（无嵌套泛型）
var is_map_mode: bool = false
var visited_nodes: Array = []  # 存储已访问节点的 node_id

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
	_group_levels_by_day()

# ---- 按天分组 ----
func _group_levels_by_day():
	_days_levels.clear()
	var per_day = 3  # 每天3个战斗节点
	var total = _levels.size()
	for day in range(3):
		var start = day * per_day
		var end = min(start + per_day, total)
		var day_levels: Array[MapData] = []  # 这里使用一维数组泛型是合法的
		for i in range(start, end):
			day_levels.append(_levels[i])
		_days_levels.append(day_levels)
	# 如果某些天不够，填充重复或生成默认
	while _days_levels.size() < 3:
		var last = _days_levels[-1] if not _days_levels.is_empty() else []
		# 由于 last 是 Array，使用 duplicate() 复制
		_days_levels.append(last.duplicate())
	print("已按天分组：", _days_levels.size(), "天，每天", _days_levels[0].size(), "个关卡")

# ---- 获取某天的关卡列表 ----
func get_levels_for_day(day: int) -> Array:
	if day >= 1 and day <= _days_levels.size():
		return _days_levels[day-1]
	return []

# ---- 游戏启动（进入地图） ----
func start_game():
	if _days_levels.is_empty() or _days_levels[0].is_empty():
		push_error("没有可用的关卡！")
		return
	current_level_index = 0
	is_map_mode = true
	Globals.is_map_mode = true
	get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")

# ---- 加载关卡（战斗场景） ----
func load_map(map_data: MapData):
	if not map_data:
		push_error("尝试加载空地图数据")
		return
	Globals.reset_all_game_state()
	Globals.current_map_data = map_data
	Globals.is_map_mode = true
	get_tree().change_scene_to_file("res://content/scenes/levels/Battlefield.tscn")

# ---- 胜利处理（地图模式） ----
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
		Globals.current_map_data = _levels[current_level_index]
		get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")
	else:
		emit_signal("all_levels_completed")
		get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
