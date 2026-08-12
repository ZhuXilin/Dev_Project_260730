extends Node

const SAVE_DIR = "user://saves/"
const SLOT_COUNT = 5
const MapSceneClass = preload("res://function/script/MapScene.gd")

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

	# ---- 版本迁移（若存档版本低于当前版本） ----
	if save.save_version < SaveData.CURRENT_VERSION:
		print("存档版本 %d 低于当前版本 %d，执行迁移" % [save.save_version, SaveData.CURRENT_VERSION])
		save = _migrate_save_data(save, save.save_version)
		# 迁移后立即保存回文件
		var err = ResourceSaver.save(save, path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("迁移后保存失败：", err)
			return false
		print("存档已迁移至版本 %d" % SaveData.CURRENT_VERSION)

	# ---- 校验（含兼容旧存档） ----
	if not _validate_save(save):
		print("校验失败，尝试兼容旧存档...")
		if save.get("map_level_data") != null:
			# 旧存档迁移：清空 visited_nodes（用空数组）
			save.visited_nodes = []
			save.checksum = save.compute_checksum()
			if not _validate_save(save):
				push_error("迁移后仍校验失败，存档可能已损坏")
				return false
		else:
			push_error("无法兼容的旧存档，请删除")
			return false

	# ---- 应用数据 ----
	_apply_save_data(save)

	# ---- 更新当前槽 ----
	current_slot = slot
	Globals.pending_save_slot = -1

	load_completed.emit(slot, true)
	print("存档加载成功: 槽", slot)
	return true

# ===== 构建存档数据 =====
# SaveManager.gd
func _build_save_data() -> SaveData:
	var save = SaveData.new()
	
	# ---- 版本号 ----
	save.save_version = SaveData.CURRENT_VERSION
	
	# ---- 玩家设置 ----
	save.music_volume = Globals.music_volume
	save.sound_volume = Globals.sound_volume
	save.game_speed = Globals.game_speed
	var mode = DisplayServer.window_get_mode()
	save.window_mode = 1 if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else 0
	save.window_size = DisplayServer.window_get_size()
	
	# ---- 游戏进度（包含资源） ----
	save.current_day = GameState.current_day
	save.main_unit_name = GameState.main_unit_name
	save.soul = GameState.soul               # 永久魂
	save.temp_soul = GameState.temp_soul     # 本轮临时魂
	save.temp_gold = GameState.temp_gold     # 本轮临时金币
	save.interrupt_state = GameState.interrupt_state
	save.battlefield_data = GameState.battlefield_data   # 预留战场数据
	
	# ---- 地图进度（visited_nodes 转为排序数组） ----
	var sorted_visited = []
	for key in GameState.visited_nodes.keys():
		sorted_visited.append([key, GameState.visited_nodes[key]])
	sorted_visited.sort()
	save.visited_nodes = sorted_visited
	
	# ---- 选中节点ID ----
	var map_scene = _get_map_scene()
	if map_scene and map_scene.has_method("get_selected_node_id"):
		save.selected_node_id = map_scene.get_selected_node_id()
	else:
		save.selected_node_id = GameState.resume_node_id
	
	# ---- 队伍数据 ----
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
	
	# ---- 元数据 ----
	save.save_time = Time.get_unix_time_from_system()
	save.checksum = save.compute_checksum()
	
	# ---- 调试打印 ----
	print("存档构建完成：temp_gold=", save.temp_gold, " temp_soul=", save.temp_soul)
	save.unlocked_units = Globals.unlocked_units.duplicate()
	return save

# ===== 应用存档数据 =====
# SaveManager.gd
func _apply_save_data(save: SaveData):
	# ---- 恢复玩家设置 ----
	Globals.music_volume = save.music_volume
	Globals.sound_volume = save.sound_volume
	Globals.set_game_speed(save.game_speed)
	if save.window_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(save.window_size)

	# ---- 恢复游戏进度 ----
	GameState.current_day = save.current_day
	LevelManager.current_day = save.current_day - 1
	GameState.main_unit_name = save.main_unit_name
	GameState.resume_node_id = save.selected_node_id

	# ---- 恢复资源 ----
	GameState.soul = save.soul
	GameState.temp_soul = save.temp_soul
	GameState.temp_gold = save.temp_gold
	GameState.interrupt_state = save.interrupt_state
	GameState.battlefield_data = save.battlefield_data

	# ---- 恢复单位解锁状态 ----
	Globals.unlocked_units = save.unlocked_units.duplicate()
	print("单位解锁状态已恢复：", Globals.unlocked_units)

	# ---- 恢复 visited_nodes ----
	GameState.visited_nodes.clear()
	if save.visited_nodes is Array:
		for pair in save.visited_nodes:
			if pair is Array and pair.size() == 2:
				GameState.visited_nodes[pair[0]] = pair[1]

	# ---- 清除地图缓存 ----
	GameState.cached_map_level_data = null
	GameState.cached_day = save.current_day

	# ---- 恢复队伍 ----
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

	LevelManager.current_level_index = 0
	LevelManager.is_map_mode = true

	if GameState.party.is_empty():
		GameState.current_map_data = null
		
	# ---- 恢复单位解锁状态，并与默认值合并 ----
	var defaults = Globals.unlock_config.get("default_unlocked", ["剑士", "枪兵", "斧兵"])
	var combined = save.unlocked_units.duplicate()
	for u in defaults:
		if u not in combined:
			combined.append(u)
	Globals.unlocked_units = combined
	print("单位解锁状态已恢复（合并默认值）：", Globals.unlocked_units)
	print("存档数据已恢复：temp_gold=", GameState.temp_gold, " temp_soul=", GameState.temp_soul)

# ===== 校验 =====
func _validate_save(save: SaveData) -> bool:
	if not save:
		return false
	var computed = save.compute_checksum()
	return computed == save.checksum

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
		"soul": save.soul   # 新增：返回永久魂
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

func _migrate_save_data(save: SaveData, from_version: int) -> SaveData:
	var migrated = save
	# 从旧版本逐级升级
	if from_version < 1:
		# 示例：若曾在版本1中添加新字段，此处处理旧数据转换
		# 但当前版本为1，无需额外转换
		pass

	# 更新版本号并重新计算校验和
	migrated.save_version = SaveData.CURRENT_VERSION
	migrated.checksum = migrated.compute_checksum()
	return migrated
