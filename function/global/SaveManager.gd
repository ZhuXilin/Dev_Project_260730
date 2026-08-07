extends Node

const SAVE_DIR = "user://saves/"
const SLOT_COUNT = 5
const MapSceneClass = preload("res://function/script/MapScene.gd")

signal save_completed(slot: int)
signal load_completed(slot: int, success: bool)

var current_slot: int = -1   # 当前使用的存档槽，-1 表示无

func _ready():
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_game(slot: int, auto: bool = false) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("无效存档槽: ", slot)
		return false

	var save = _build_save_data()
	if not save:
		return false

	save.save_time = Time.get_unix_time_from_system()
	save.checksum = save.compute_checksum()

	var path = _get_slot_path(slot)
	var err = ResourceSaver.save(save, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("保存失败: ", path, " 错误码: ", err)
		return false

	# 更新当前存档槽
	current_slot = slot

	print("存档已保存 (槽", slot, ", ", "自动" if auto else "手动", ")")
	save_completed.emit(slot)
	return true

func load_game(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false

	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path):
		push_error("存档不存在: ", path)
		return false

	var save = load(path) as SaveData
	if not save:
		push_error("无法加载存档: ", path)
		return false

	if not _validate_save(save):
		push_error("存档校验失败，可能已损坏")
		return false

	_apply_save_data(save)
	# 更新当前存档槽
	current_slot = slot

	load_completed.emit(slot, true)
	return true

func _build_save_data() -> SaveData:
	var save = SaveData.new()

	# 设置
	save.music_volume = Globals.music_volume
	save.sound_volume = Globals.sound_volume
	save.game_speed = Globals.game_speed
	var mode = DisplayServer.window_get_mode()
	save.window_mode = 1 if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else 0
	save.window_size = DisplayServer.window_get_size()

	# 进度
	save.current_day = GameState.current_day
	save.main_unit_name = GameState.main_unit_name
	if GameState.cached_map_level_data:
		save.map_level_data = GameState.cached_map_level_data.duplicate(true)
	else:
		save.map_level_data = null

	var map_scene = _get_map_scene()
	if map_scene and map_scene.has_method("get_selected_node_id"):
		save.selected_node_id = map_scene.get_selected_node_id()
	else:
		save.selected_node_id = ""

	# 队伍
	save.party_data = []
	for unit_data in GameState.party:
		var dict = {
			"unit_name": unit_data.unit_name,
			"hp": unit_data.hit_points,
			"inventory": []
		}
		for inst in unit_data.inventory:
			dict["inventory"].append(inst.item_id)
		save.party_data.append(dict)

	return save

func _apply_save_data(save: SaveData):
	# 设置
	Globals.music_volume = save.music_volume
	Globals.sound_volume = save.sound_volume
	Globals.set_game_speed(save.game_speed)
	if save.window_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(save.window_size)

	# 进度
	GameState.current_day = save.current_day
	GameState.main_unit_name = save.main_unit_name
	GameState.cached_map_level_data = save.map_level_data
	GameState.cached_day = save.current_day
	GameState.resume_node_id = save.selected_node_id

	# 队伍
	GameState.party.clear()
	for dict in save.party_data:
		var data = UnitData.new()
		data.unit_name = dict["unit_name"]
		data.hit_points = dict["hp"]
		var stats = UnitDataManager.get_default_stats(data.unit_name)
		data.max_hp = stats.max_hp
		data.defense = stats.defense
		data.magic_defense = stats.magic_defense
		data.skill = stats.skill
		data.speed = stats.speed
		data.luck = stats.luck
		data.move_range = stats.move_range
		data.ignore_terrain_cost = stats.ignore_terrain_cost
		for item_id in dict["inventory"]:
			var inst = ItemInstance.new()
			inst.item_id = item_id
			inst.count = 1
			data.inventory.append(inst)
		if data.inventory.size() > 0:
			data.equipped_weapon = data.inventory[0].item_id
		GameState.party.append(data)

func _validate_save(save: SaveData) -> bool:
	if not save:
		return false
	var computed = save.compute_checksum()
	return computed == save.checksum

func _get_slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.tres" % slot

func _get_map_scene():
	var scene = get_tree().current_scene
	if scene and scene is MapSceneClass:
		return scene
	return null

# ===== 自动存档：覆盖当前存档槽 =====
func auto_save():
	if current_slot == -1:
		# 如果从未保存/加载，则覆写槽0
		save_game(0, true)
	else:
		save_game(current_slot, true)

# ===== 其他辅助函数 =====
func has_save(slot: int) -> bool:
	return ResourceLoader.exists(_get_slot_path(slot))

func get_save_info(slot: int) -> Dictionary:
	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path):
		return {}
	var save = load(path) as SaveData
	if not save:
		return {}
	return {
		"time": save.save_time,
		"day": save.current_day,
		"main_unit": save.main_unit_name,
		"party": save.party_data.size()
	}

func delete_save(slot: int):
	var path = _get_slot_path(slot)
	if ResourceLoader.exists(path):
		DirAccess.remove_absolute(path)
		if current_slot == slot:
			current_slot = -1   # 如果删除的是当前槽，重置
