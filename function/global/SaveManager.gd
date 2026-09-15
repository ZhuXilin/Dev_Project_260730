extends Node

const SAVE_DIR = "user://saves/"
const SLOT_COUNT = 5
const MapSceneClass = preload(Config.PATHS.MAP_SCENE_SCRIPT)

signal save_completed(slot: int)
signal load_completed(slot: int, success: bool)

var current_slot: int = -1   # 当前使用的存档槽，-1 表示无

func _ready():
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ===== 保存 =====
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

	current_slot = slot
	print("存档已保存 (槽", slot, ", ", "自动" if auto else "手动", ")")
	save_completed.emit(slot)
	return true

# ===== 加载 =====
func load_game(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("无效存档槽: ", slot)
		return false

	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path):
		push_error("存档不存在: ", path)
		return false

	var save = load(path) as SaveData
	if not save:
		push_error("无法加载存档: ", path)
		return false

	# ---- 版本检查：低于当前版本直接升级版本号 ----
	# 注意：v3 起不再提供 v2 数据迁移，只更新版本号让后续保存用新格式
	if save.save_version < SaveData.CURRENT_VERSION:
		print("存档版本 %d 低于当前版本 %d，更新版本号" % [save.save_version, SaveData.CURRENT_VERSION])
		save.save_version = SaveData.CURRENT_VERSION
		save.checksum = save.compute_checksum()
		var err = ResourceSaver.save(save, path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("版本更新后保存失败：", err)
			return false

	# ---- checksum 校验 ----
	if not _validate_save(save):
		push_error("存档校验失败，可能已损坏: ", path)
		return false

	# ---- 应用数据 ----
	_apply_save_data(save)

	current_slot = slot
	Globals.pending_save_slot = -1

	load_completed.emit(slot, true)
	print("存档加载成功: 槽", slot)
	return true

# ===== 构建存档数据 =====
func _build_save_data() -> SaveData:
	var save = SaveData.new()
	save.save_version = SaveData.CURRENT_VERSION

	# ---- 音量 / 窗口 ----
	save.music_volume = Globals.music_volume
	save.sound_volume = Globals.sound_volume
	save.game_speed = Globals.game_speed

	var mode = DisplayServer.window_get_mode()
	save.window_mode = 1 if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else 0
	save.window_size = DisplayServer.window_get_size()

	# ---- 游戏进度 ----
	save.current_day = GameState.current_day
	save.main_unit_name = GameState.main_unit_name
	save.soul = GameState.soul
	save.cycle_start_soul = GameState.cycle_start_soul
	save.cycle_start_materials = GameState.cycle_start_materials.duplicate()
	save.temp_soul = GameState.temp_soul
	save.temp_gold = GameState.temp_gold
	save.materials = GameState.materials.duplicate()
	save.interrupt_state = GameState.interrupt_state
	save.battlefield_data = GameState.battlefield_data
	save.current_faction = GameState.current_faction
	save.current_node_key = GameState.current_node_key
	save.map_snapshot = GameState.map_snapshot.duplicate(true)

	# ---- visited_nodes 排序后存为二维数组 ----
	var sorted_visited = []
	for key in GameState.visited_nodes.keys():
		sorted_visited.append([key, GameState.visited_nodes[key]])
	sorted_visited.sort()
	save.visited_nodes = sorted_visited

	save.selected_node_id = GameState.resume_node_id

	# ---- 队伍数据（v3：整个 UnitData.to_dict 打包） ----
	save.party_data = []
	for unit_data in GameState.party:
		save.party_data.append(unit_data.to_dict())

	# ---- 全局遗物（空槽保留为 ""） ----
	var relics = []
	for relic in GameState.global_relics:
		if relic != null:
			relics.append(relic.item_id)
		else:
			relics.append("")
	save.global_relics = relics

	# ---- 解锁数据 ----
	save.unlocked_units = Globals.unlocked_units.duplicate()
	save.unlocked_items = Globals.unlocked_items.duplicate()
	save.unlocked_relics = RelicManager.get_unlocked_relics()
	save.unlocked_talents = Globals.unlocked_talents.duplicate()
	save.unlocked_recipes = GameState.unlocked_recipes.duplicate()
	save.unlocked_stories = GameState.unlocked_stories.duplicate()
	save.unit_growth = GameState.unit_growth.duplicate(true)
	save.arena_target_talents = GameState.arena_target_talents.duplicate(true)
	save.arena_best_streak = GameState.arena_best_streak
	save.talent_exp = GameState.talent_exp.duplicate(true)

	save.save_time = Time.get_unix_time_from_system()
	save.checksum = save.compute_checksum()
	return save

# ===== 应用存档数据 =====
func _apply_save_data(save: SaveData):
	# ---- 音量 / 速度 / 窗口 ----
	Globals.music_volume = save.music_volume
	Globals.sound_volume = save.sound_volume
	Globals.set_game_speed(save.game_speed)

	if save.window_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(save.window_size)

	# ---- 游戏进度 ----
	GameState.current_day = save.current_day
	LevelManager.current_day = save.current_day - 1
	GameState.main_unit_name = save.main_unit_name
	GameState.resume_node_id = save.selected_node_id
	GameState.soul = save.soul
	GameState.cycle_start_soul = save.cycle_start_soul
	GameState.cycle_start_materials = save.cycle_start_materials.duplicate()
	GameState.temp_soul = save.temp_soul
	GameState.temp_gold = save.temp_gold
	GameState.materials = save.materials.duplicate()
	GameState.interrupt_state = save.interrupt_state as GameState.InterruptState
	GameState.battlefield_data = save.battlefield_data
	GameState.current_faction = save.current_faction
	GameState.current_node_key = save.current_node_key
	GameState.map_snapshot = save.map_snapshot.duplicate(true)
	GameState.arena_target_talents = save.arena_target_talents.duplicate(true)
	GameState.arena_best_streak = save.arena_best_streak
	GameState.talent_exp = save.talent_exp.duplicate(true)

	# ---- 恢复 visited_nodes ----
	GameState.visited_nodes.clear()
	if save.visited_nodes is Array:
		for pair in save.visited_nodes:
			if pair is Array and pair.size() == 2:
				GameState.visited_nodes[pair[0]] = pair[1]

	# ---- 恢复队伍数据（v3：直接 from_dict） ----
	GameState.party.clear()
	for d in save.party_data:
		if d is Dictionary:
			var data = UnitData.from_dict(d)
			GameState.party.append(data)

	# ---- 恢复全局遗物（还原 null 空槽） ----
	GameState.global_relics.clear()
	for relic_id in save.global_relics:
		if relic_id != "":
			var inst = ItemInstance.new()
			inst.item_id = relic_id
			inst.count = 1
			GameState.global_relics.append(inst)
		else:
			GameState.global_relics.append(null)

	# 补全到 MAX_RELIC_SLOTS
	while GameState.global_relics.size() < 3:
		GameState.global_relics.append(null)

	# ---- 解锁数据 ----
	RelicManager.set_unlocked_relics(save.unlocked_relics)
	Globals.unlocked_units = save.unlocked_units.duplicate()
	Globals.unlocked_items = save.unlocked_items.duplicate()
	Globals.unlocked_talents = save.unlocked_talents.duplicate()
	GameState.unlocked_recipes = save.unlocked_recipes.duplicate()
	GameState.unlocked_stories = save.unlocked_stories.duplicate()
	GameState.unit_growth = save.unit_growth.duplicate(true)

	if Globals.unlocked_items.is_empty():
		Globals.unlocked_items = Globals.item_unlocked_items.duplicate()

	# ---- 关卡管理器状态 ----
	LevelManager.current_level_index = 0
	LevelManager.is_map_mode = true
	Globals.is_map_mode = true

	# ---- 未完成战斗：撤销节点访问标记，让玩家可重新进入 ----
	if GameState.current_node_key != "":
		print("读档：检测到未完成的战斗节点 ", GameState.current_node_key, "，节点可重新进入")
		GameState.visited_nodes.erase(GameState.current_node_key)
		GameState.current_node_key = ""

# ===== 校验 =====
func _validate_save(save: SaveData) -> bool:
	if not save:
		return false
	if save.save_version <= 0:
		return false
	return true

func load_save_data(slot: int) -> SaveData:
	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SaveData

func is_map_data_valid(save: SaveData) -> bool:
	return not save.party_data.is_empty()

func clean_invalid_progress(slot: int):
	var save = load_save_data(slot)
	if not save:
		return
	save.visited_nodes = []
	save.current_day = 1
	save.selected_node_id = ""
	save.interrupt_state = 1
	save.temp_soul = 0
	save.temp_gold = 0
	save.checksum = save.compute_checksum()
	var path = _get_slot_path(slot)
	ResourceSaver.save(save, path, ResourceSaver.FLAG_COMPRESS)

# ===== 路径 =====
func _get_slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.tres" % slot

# ===== 获取 MapScene =====
func _get_map_scene():
	var scene = get_tree().current_scene
	if scene and scene is MapSceneClass:
		return scene
	return null

# ===== 自动存档 =====
func auto_save():
	if current_slot == -1:
		save_game(0, true)
	else:
		save_game(current_slot, true)	

# ===== 辅助函数 =====
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
		"party": save.party_data.size(),
		"soul": save.soul
	}

func delete_save(slot: int):
	var path = _get_slot_path(slot)
	if ResourceLoader.exists(path):
		DirAccess.remove_absolute(path)
		if current_slot == slot:
			current_slot = -1

func find_empty_slot() -> int:
	for i in range(SLOT_COUNT):
		if not has_save(i):
			return i
	return -1

func reset_current_slot():
	current_slot = -1
