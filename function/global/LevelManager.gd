extends Node

signal all_levels_completed()
signal all_days_completed()
signal flame_resonance_rolled(resonance: Dictionary)

const UNIT_LEVEL_MAP_PATH = "res://content/scenes/levels/UnitLevelMap.tres"
const DEFAULT_FACTION = "王国"

var _config: UnitLevelMapConfig = null
var _current_entry: UnitLevelMapEntry = null
var _day_levels: Array = []
var current_level_index: int = 0
var is_map_mode: bool = false
var current_day: int = 0

# ★ 批次 1：火焰共鸣
var current_resonance : Dictionary = {}
var _resonance_pool : Array = [
	{"type": "attack_percent",    "value": 0.05, "display": "攻击 +5%"},
	{"type": "soul_fire_max",     "value": 1,    "display": "魂火上限 +1"},
	{"type": "soul_fire_initial", "value": 1,    "display": "初始魂火 +1"},
	{"type": "crit_damage",       "value": 0.10, "display": "暴击伤害 +10%"},
	{"type": "defense_flat",      "value": 1,    "display": "防御 +1"},
	{"type": "heal_bonus",        "value": 0.15, "display": "治疗量 +15%"},
]


func _ready():
	_load_config()
	_reload_all_levels()


func _load_config():
	if not ResourceLoader.exists(UNIT_LEVEL_MAP_PATH):
		push_error("UnitLevelMap.tres 不存在！")
		return
	_config = load(UNIT_LEVEL_MAP_PATH)
	if not _config:
		push_error("UnitLevelMap.tres 加载失败！")


func _get_entry_for_faction(faction: String) -> UnitLevelMapEntry:
	if not _config: return null
	for entry in _config.entries:
		if entry.faction == faction:
			return entry
	return _config.default_entry


func _reload_all_levels():
	var faction = GameState.current_faction
	if faction == "":
		faction = DEFAULT_FACTION
	_current_entry = _get_entry_for_faction(faction)
	if not _current_entry:
		push_error("[LevelManager] 没有找到阵营 %s 的关卡配置！" % faction)
		return

	_day_levels.clear()
	var day_resources = [_current_entry.day1, _current_entry.day2, _current_entry.day3]
	for res in day_resources:
		if res and res is LevelListResource:
			_day_levels.append(res.levels.duplicate())
		else:
			_day_levels.append([])
	print("已加载阵营 %s 的关卡，每天关卡数: %s" % [faction, _day_levels.map(func(arr): return arr.size())])


func get_current_day_levels() -> Array[MapData]:
	if current_day < 0 or current_day >= _day_levels.size():
		return []
	return _day_levels[current_day]


func get_levels_for_day(day: int) -> Array:
	if day < 1 or day > 3:
		return []
	return _day_levels[day - 1]


func get_current_layout() -> MapLayout:
	if _current_entry == null:
		return null
	return _current_entry.layout


func get_map_for_node_type(node_type: int, main_unit: String = "") -> MapData:
	var day_levels = get_current_day_levels()
	if day_levels.is_empty():
		var fallback = _create_fallback_map_data()
		fallback.node_type = node_type
		return fallback
	var filtered = day_levels.filter(func(m):
		return m.required_unit == "" or m.required_unit == main_unit
	)
	if filtered.is_empty():
		filtered = day_levels.filter(func(m): return m.required_unit == "")
	if filtered.is_empty():
		var fallback = _create_fallback_map_data()
		fallback.node_type = node_type
		return fallback
	var type_filtered = filtered.filter(func(m):
		return m.node_type == node_type
	)
	if type_filtered.is_empty():
		type_filtered = filtered.filter(func(m):
			return m.node_type == MapNode.NodeType.NORMAL
		)
	if type_filtered.is_empty():
		return _clone_map_data(filtered[0], node_type)
	return _clone_map_data(type_filtered[0], node_type)


func get_random_map_for_node_type(node_type: int, main_unit: String = "") -> MapData:
	var maps = get_random_maps_for_node_type(node_type, 1, main_unit)
	if maps.is_empty(): return null
	return maps[0]


func get_random_maps_for_node_type(node_type: int, count: int, main_unit: String = "") -> Array:
	var result : Array = []
	if count <= 0: return result
	var day_levels = get_current_day_levels()
	if day_levels.is_empty(): return result
	var filtered = day_levels.filter(func(m):
		return m.required_unit == "" or m.required_unit == main_unit
	)
	if filtered.is_empty():
		filtered = day_levels.filter(func(m): return m.required_unit == "")
	if filtered.is_empty(): return result
	var type_filtered = filtered.filter(func(m):
		return m.node_type == node_type
	)
	if type_filtered.is_empty(): return result
	var pool = type_filtered.duplicate()
	pool.shuffle()
	for i in range(count):
		if i < pool.size():
			result.append(_clone_map_data(pool[i], node_type))
		else:
			pool.shuffle()
			result.append(_clone_map_data(pool[i % pool.size()], node_type))
	return result


func _clone_map_data(src: MapData, node_type: int) -> MapData:
	var copy = MapData.new()
	copy.map_name = src.map_name
	copy.scene = src.scene
	copy.map_size = src.map_size
	copy.node_type = node_type
	copy.spawn_points = src.spawn_points.duplicate()
	copy.required_unit = src.required_unit
	return copy


# ============================================================
#  流程控制
# ============================================================
func advance_day() -> bool:
	current_day += 1
	if current_day >= 3:
		all_days_completed.emit()
		return false
	GameState.visited_nodes.clear()
	GameState.cached_map_level_data = null
	GameState.cached_day = -1
	_roll_flame_resonance()   # ★ 批次 1
	return true


func start_game():
	GameState.reset_progress()
	current_level_index = 0
	current_day = 0
	is_map_mode = true
	Globals.is_map_mode = true
	_roll_flame_resonance()   # ★ 批次 1
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
	current_resonance = {}   # ★ 批次 1


# ============================================================
#  火焰共鸣（批次 1）
# ============================================================
func _roll_flame_resonance():
	if _resonance_pool.is_empty():
		current_resonance = {}
		return
	var pick : Dictionary = _resonance_pool[randi() % _resonance_pool.size()]
	current_resonance = pick.duplicate()
	print("[火焰共鸣] 第 %d 天：%s" % [current_day + 1, pick.get("display", "")])
	flame_resonance_rolled.emit(current_resonance)
