extends Node

signal all_levels_completed()

const LEVEL_LIST_PATH : String = "res://content/scenes/levels/LevelList.tres"

var current_level_index : int = 0
var _levels : Array[MapData] = []

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
	else:
		push_error("关卡列表资源类型错误，期望 LevelList 类型：", LEVEL_LIST_PATH)
		_use_fallback_levels()

func _use_fallback_levels():
	print("使用硬编码默认关卡（仅用于测试）")
	_levels = []
	var fallback_map = load("res://content/maps/Level01.tres") as MapData
	if fallback_map:
		_levels.append(fallback_map)

func start_game():
	if _levels.size() == 0:
		push_error("没有配置任何关卡！")
		return
	current_level_index = 0
	load_current_level()

# ===== 修改此函数：先跳转至 Loading 场景 =====
func load_current_level():
	if current_level_index < _levels.size():
		# ---- 重置全局状态 ----
		Globals.reset_all_game_state()
		Globals.current_map_data = _levels[current_level_index]
		
		# ---- 重置事件和对话管理器 ----
		EventManager.clear_completed()
		DialogueManager.reset()
		
		# 切换到 Loading 场景
		get_tree().change_scene_to_file("res://content/scenes/ui/Loading.tscn")
	else:
		emit_signal("all_levels_completed")
		get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")

func on_victory():
	current_level_index += 1
	if current_level_index < _levels.size():
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
