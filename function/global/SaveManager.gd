extends Node

const SAVE_DIR = "user://saves/"
const SLOT_COUNT = 5
const MapSceneClass = preload(Config.PATHS.MAP_SCENE_SCRIPT)

signal save_completed(slot: int)
signal load_completed(slot: int, success: bool)

var current_slot: int = -1

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

	if save.save_version < SaveData.CURRENT_VERSION:
		print("存档版本 %d 低于当前版本 %d，开始迁移" % [save.save_version, SaveData.CURRENT_VERSION])
		_migrate_save(save)
		save.save_version = SaveData.CURRENT_VERSION
		save.checksum = save.compute_checksum()
		var err = ResourceSaver.save(save, path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("版本更新后保存失败：", err)
			return false

	if not _validate_save(save):
		push_error("存档校验失败，可能已损坏: ", path)
		return false

	_apply_save_data(save)

	current_slot = slot
	Globals.pending_save_slot = -1

	load_completed.emit(slot, true)
	print("存档加载成功: 槽", slot)
	return true


# ===== 版本迁移 =====
func _migrate_save(save: SaveData):
	var v : int = save.save_version

	if v < 6:
		save.tutorial_stage = 3
		print("  [迁移] v5 → v6：tutorial_stage 设为 3")

	if v < 7:
		print("  [迁移] v6 → v7")

	if v < 8:
		save.pending_sacrifice_rewards = []
		save.pending_forge_rewards = []
		print("  [迁移] v7 → v8：移除 armor_storage，初始化待领取区")


# ===== 构建存档数据 =====
func _build_save_data() -> SaveData:
	var save = SaveData.new()
	save.save_version = SaveData.CURRENT_VERSION

	save.music_volume = Globals.music_volume
	save.sound_volume = Globals.sound_volume
	save.game_speed = Globals.game_speed

	var mode = DisplayServer.window_get_mode()
	save.window_mode = 1 if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else 0
	save.window_size = DisplayServer.window_get_size()

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

	var sorted_visited = []
	for key in GameState.visited_nodes.keys():
		sorted_visited.append([key, GameState.visited_nodes[key]])
	sorted_visited.sort()
	save.visited_nodes = sorted_visited

	save.selected_node_id = GameState.resume_node_id

	save.party_data = []
	for unit_data in GameState.party:
		save.party_data.append(unit_data.to_dict())

	save.equipped_passives = []
	for p in GameState.get_passives():
		save.equipped_passives.append(_serialize_passive(p))

	save.pending_sacrifice_rewards = []
	for inst in GameState.pending_sacrifice_rewards:
		save.pending_sacrifice_rewards.append(_serialize_item_instance(inst))

	save.pending_forge_rewards = []
	for inst in GameState.pending_forge_rewards:
		save.pending_forge_rewards.append(_serialize_item_instance(inst))

	save.unlocked_units = Globals.unlocked_units.duplicate()
	save.unlocked_items = Globals.unlocked_items.duplicate()
	save.unlocked_relics = RelicManager.get_unlocked_relics()
	save.unlocked_talents = Globals.unlocked_talents.duplicate()
	save.unlocked_recipes = GameState.unlocked_recipes.duplicate()
	save.unlocked_stories = GameState.unlocked_stories.duplicate()
	save.unlocked_refine_recipes = GameState.unlocked_refine_recipes.duplicate()
	save.refined_items = GameState.refined_items.duplicate()
	save.unit_growth = GameState.unit_growth.duplicate(true)
	save.unit_blessings = GameState.unit_blessings.duplicate(true)
	save.arena_target_talents = GameState.arena_target_talents.duplicate(true)
	save.arena_best_streak = GameState.arena_best_streak
	save.talent_exp = GameState.talent_exp.duplicate(true)
	save.tutorial_stage = GameState.tutorial_stage

	save.save_time = Time.get_unix_time_from_system()
	save.checksum = save.compute_checksum()
	return save

# ===== 应用存档数据 =====
func _apply_save_data(save: SaveData):
	Globals.music_volume = save.music_volume
	Globals.sound_volume = save.sound_volume
	Globals.set_game_speed(save.game_speed)

	if save.window_mode == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(save.window_size)

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

	GameState.visited_nodes.clear()
	if save.visited_nodes is Array:
		for pair in save.visited_nodes:
			if pair is Array and pair.size() == 2:
				GameState.visited_nodes[pair[0]] = pair[1]

	GameState.party.clear()
	for d in save.party_data:
		if d is Dictionary:
			var data = UnitData.from_dict(d)
			GameState.party.append(data)

	GameState.init_passive_slots()
	var arr = save.equipped_passives
	if arr is Array:
		for i in range(min(arr.size(), 4)):
			GameState.set_passive_at_slot(i, _deserialize_passive(arr[i]))

	# ★ 待领取奖励
	GameState.pending_sacrifice_rewards.clear()
	if save.pending_sacrifice_rewards is Array:
		for d in save.pending_sacrifice_rewards:
			var inst = _deserialize_item_instance(d)
			if inst != null:
				GameState.pending_sacrifice_rewards.append(inst)

	GameState.pending_forge_rewards.clear()
	if save.pending_forge_rewards is Array:
		for d in save.pending_forge_rewards:
			var inst = _deserialize_item_instance(d)
			if inst != null:
				GameState.pending_forge_rewards.append(inst)

	RelicManager.set_unlocked_relics(save.unlocked_relics if save.unlocked_relics else [])
	Globals.unlocked_units = (save.unlocked_units if save.unlocked_units else []).duplicate()
	Globals.unlocked_items = (save.unlocked_items if save.unlocked_items else []).duplicate()

	GameState.tutorial_stage = save.tutorial_stage
	if save.unlocked_talents.is_empty():
		Globals.reload_talent_unlock()
		print("[SaveManager] 存档缺 unlocked_talents，按 stage=%d 重算" % GameState.tutorial_stage)
	else:
		Globals.unlocked_talents = save.unlocked_talents.duplicate()

	GameState.unlocked_recipes = (save.unlocked_recipes if save.unlocked_recipes else []).duplicate()
	GameState.unlocked_stories = (save.unlocked_stories if save.unlocked_stories else []).duplicate()
	GameState.unlocked_refine_recipes = (save.unlocked_refine_recipes if save.unlocked_refine_recipes else []).duplicate()
	GameState.refined_items = (save.refined_items if save.refined_items else {}).duplicate()
	GameState.unit_growth = (save.unit_growth if save.unit_growth else {}).duplicate(true)
	GameState.unit_blessings = (save.unit_blessings if save.unit_blessings else {}).duplicate(true)

	if Globals.unlocked_items.is_empty():
		Globals.unlocked_items = Globals.item_unlocked_items.duplicate()

	LevelManager.current_level_index = 0
	LevelManager.is_map_mode = true
	Globals.is_map_mode = true

	if GameState.current_node_key != "":
		print("读档：检测到未完成的战斗节点 ", GameState.current_node_key, "，节点可重新进入")
		GameState.visited_nodes.erase(GameState.current_node_key)
		GameState.current_node_key = ""

# ===== 序列化辅助 =====
func _serialize_item_instance(inst) -> Dictionary:
	if inst == null:
		return {}
	if inst is ItemInstance:
		return {
			"item_id": inst.item_id,
			"count": inst.count,
			"upgrade_level": inst.upgrade_level,
		}
	return {}

func _deserialize_item_instance(d) -> Variant:
	if not (d is Dictionary) or d.is_empty():
		return null
	var item_id : String = d.get("item_id", "")
	if item_id == "":
		return null
	var inst = ItemInstance.new()
	inst.item_id = item_id
	inst.count = d.get("count", 1)
	inst.upgrade_level = d.get("upgrade_level", 0)
	return inst

func _serialize_passive(entry) -> Dictionary:
	if entry == null:
		return {"type": "empty"}
	if entry is ItemInstance:
		return {"type": "relic", "item_id": entry.item_id}
	if entry is Dictionary and entry.has("refine_id"):
		return {"type": "refine", "refine_id": entry.get("refine_id", "")}
	return {"type": "empty"}

func _deserialize_passive(d) -> Variant:
	if not (d is Dictionary):
		return null
	var t = d.get("type", "empty")
	if t == "relic":
		var item_id = d.get("item_id", "")
		if item_id == "":
			return null
		var inst = ItemInstance.new()
		inst.item_id = item_id
		inst.count = 1
		return inst
	elif t == "refine":
		var refine_id = d.get("refine_id", "")
		if refine_id == "":
			return null
		return {"refine_id": refine_id, "count": 1}
	return null

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

# ===== 辅助 =====
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
