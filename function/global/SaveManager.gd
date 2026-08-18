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
func _build_save_data() -> SaveData:
	var save = SaveData.new()
	# ---- 版本 ----
	save.save_version = SaveData.CURRENT_VERSION
	save.unlocked_items = Globals.unlocked_items.duplicate()
	save.unlocked_relics = Globals.unlocked_relics.duplicate()
	
	# ---- 玩家设置 ----
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
	save.temp_soul = GameState.temp_soul
	save.temp_gold = GameState.temp_gold
	save.interrupt_state = GameState.interrupt_state
	save.battlefield_data = GameState.battlefield_data
	save.current_faction = GameState.current_faction
	
	# ---- 地图进度 ----
	var sorted_visited = []
	for key in GameState.visited_nodes.keys():
		sorted_visited.append([key, GameState.visited_nodes[key]])
	sorted_visited.sort()
	save.visited_nodes = sorted_visited
	save.selected_node_id = GameState.resume_node_id
	save.map_level_data = GameState.cached_map_level_data
	
	# ---- 队伍数据（不再包含 inventory） ----
	save.party_data = []
	save.party_equipment = []
	for unit_data in GameState.party:
		var dict = {
			"unit_name": unit_data.unit_name,
			"display_name": unit_data.display_name,
			"faction": unit_data.faction,
			"hp": unit_data.hit_points
		}
		save.party_data.append(dict)
		
		var equip_dict = {
			"weapon": unit_data.weapon_slot.item_id if unit_data.weapon_slot else "",
			"armor_slots": [],
			"max_armor_slots": unit_data.max_armor_slots
		}
		for slot in unit_data.armor_slots:
			equip_dict["armor_slots"].append(slot.item_id if slot else "")
		save.party_equipment.append(equip_dict)
	
	# ---- 全局遗物 ----
	var relics = []
	for relic in GameState.global_relics:
		relics.append(relic.item_id)
	save.global_relics = relics
	
	# ---- 解锁数据 ----
	save.unlocked_units = Globals.unlocked_units.duplicate()
	save.unlocked_items = Globals.unlocked_items.duplicate()
	save.unlocked_relics = Globals.unlocked_relics.duplicate()
	
	# ---- 元数据 ----
	save.save_time = Time.get_unix_time_from_system()
	save.checksum = save.compute_checksum()
	
	print("存档构建完成")
	return save

# ===== 应用存档数据 =====
func _apply_save_data(save: SaveData):
	# ---- 玩家设置 ----
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
	GameState.temp_soul = save.temp_soul
	GameState.temp_gold = save.temp_gold
	GameState.interrupt_state = save.interrupt_state
	GameState.battlefield_data = save.battlefield_data
	GameState.current_faction = save.current_faction

	# ---- 地图进度 ----
	GameState.visited_nodes.clear()
	if save.visited_nodes is Array:
		for pair in save.visited_nodes:
			if pair is Array and pair.size() == 2:
				GameState.visited_nodes[pair[0]] = pair[1]
	GameState.cached_map_level_data = save.map_level_data
	GameState.cached_day = save.current_day

	# ---- 恢复队伍（不再恢复 inventory） ----
	GameState.party.clear()
	for i in range(save.party_data.size()):
		var dict = save.party_data[i]
		var data = UnitData.new()
		data.unit_name = dict["unit_name"]
		data.display_name = dict.get("display_name", dict["unit_name"])
		data.faction = dict.get("faction", "")
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
		
		# 恢复装备（若存在）
		if i < save.party_equipment.size():
			var equip_dict = save.party_equipment[i]
			# 武器
			if equip_dict["weapon"] != "":
				var inst = ItemInstance.new()
				inst.item_id = equip_dict["weapon"]
				inst.count = 1
				data.weapon_slot = inst
			else:
				data.weapon_slot = null
			# 防具
			data.armor_slots.clear()
			for slot_id in equip_dict["armor_slots"]:
				if slot_id != "":
					var inst = ItemInstance.new()
					inst.item_id = slot_id
					inst.count = 1
					data.armor_slots.append(inst)
				else:
					data.armor_slots.append(null)
			data.max_armor_slots = equip_dict.get("max_armor_slots", 2)
		
		# 兼容旧存档：如果存档有 inventory 且没有武器，尝试从 inventory 恢复武器
		if not data.weapon_slot and dict.has("inventory"):
			for item_id in dict["inventory"]:
				var item_data = ItemManager.get_item_data(item_id)
				if item_data and item_data.equipment_slot == "weapon":
					var inst = ItemInstance.new()
					inst.item_id = item_id
					inst.count = 1
					data.weapon_slot = inst
					break
		
		GameState.party.append(data)

	# ---- 恢复全局遗物 ----
	GameState.global_relics.clear()
	for relic_id in save.global_relics:
		var inst = ItemInstance.new()
		inst.item_id = relic_id
		inst.count = 1
		GameState.global_relics.append(inst)

	# ---- 解锁数据 ----
	Globals.unlocked_units = save.unlocked_units.duplicate()
	Globals.unlocked_items = save.unlocked_items.duplicate()
	Globals.unlocked_relics = save.unlocked_relics.duplicate()
	
	# 如果存档中没有任何解锁道具，补充默认
	if Globals.unlocked_items.is_empty():
		Globals.unlocked_items = Globals.item_unlocked_items.duplicate()
		
	LevelManager.current_level_index = 0
	LevelManager.is_map_mode = true

	print("存档数据已恢复")

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
	if from_version < 1:
		# 清理旧存档中的 inventory 数据（如果有）
		for i in range(migrated.party_data.size()):
			var dict = migrated.party_data[i]
			if dict.has("inventory"):
				dict.erase("inventory")
		# 如果有 unlocked_relics 字段不存在，添加空数组（但旧版本可能没有，我们不管）
		# 重新计算校验和
		migrated.checksum = migrated.compute_checksum()
	
	migrated.save_version = SaveData.CURRENT_VERSION
	return migrated
