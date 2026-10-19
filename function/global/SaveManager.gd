extends Node

const SAVE_DIR = "user://saves/"
const SLOT_COUNT = 5
const MapSceneClass = preload(Config.PATHS.MAP_SCENE_SCRIPT)

signal save_completed(slot: int)
signal load_completed(slot: int, success: bool)

var current_slot: int = -1
var suppress_save : bool = false


func _ready():
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func save_game(slot: int, auto: bool = false) -> bool:
	if suppress_save:
		return false
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("无效存档槽: " + str(slot)); return false
	var save = _build_save_data()
	if not save: return false
	save.save_time = Time.get_unix_time_from_system()
	# ★ 第九批：不再计算 checksum —— JSON.stringify 的键顺序不稳定，
	# 每次加载都会误报"checksum 不匹配"。单人游戏手改存档无副作用。
	# save.checksum 字段保留（兼容旧档），但不再写入新值。
	var path = _get_slot_path(slot)
	var err = ResourceSaver.save(save, path)
	if err != OK:
		push_error("保存失败: " + path); return false
	current_slot = slot
	print("存档已保存 (槽", slot, ", ", "自动" if auto else "手动", ")")
	save_completed.emit(slot)
	return true


func auto_save():
	if suppress_save: return
	if current_slot == -1: save_game(0, true)
	else: save_game(current_slot, true)


func load_game(slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		push_error("无效存档槽: " + str(slot)); return false
	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path):
		push_error("存档不存在: " + path); return false
	var save = load(path) as SaveData
	if not save:
		push_error("无法加载存档: " + path); return false

	if not _validate_save(save):
		push_error("存档校验失败: " + path); return false

	_apply_save_data(save)
	current_slot = slot
	Globals.pending_save_slot = -1
	load_completed.emit(slot, true)
	return true


# ============================================================
#  构建
# ============================================================
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
	save.current_faction = GameState.current_faction
	save.current_node_key = GameState.current_node_key
	save.map_snapshot = GameState.map_snapshot.duplicate(true)
	save.shop_level = GameState.shop_level

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

	save.soul = GameState.soul
	save.keys = GameState.keys
	save.keys_bought = GameState.keys_bought
	save.pending_tag_pin = GameState.pending_tag_pin
	save.active_tag_pin = GameState.active_tag_pin
	save.soul_fire_threshold_override = GameState.soul_fire_threshold_override
	save.cycle_start_soul = GameState.cycle_start_soul
	save.temp_gold = GameState.temp_gold

	# ★ v4.5：遗物精炼
	save.relic_levels = GameState.relic_levels.duplicate(true)

	save.soul_fire_current = SoulFireManager.current
	save.soul_fire_altar_level = SoulFireManager.altar_level
	save.soul_fire_initial_level = GameState.soul_fire_initial_level
	save.unit_attr_cap = GameState.unit_attr_cap.duplicate(true)
	save.unit_attr_points = GameState.unit_attr_points.duplicate(true)
	save.tag_purchase_count = GameState.tag_purchase_count.duplicate(true)

	save.unlocked_auras = GameState.unlocked_auras.duplicate()
	save.active_aura_research = GameState.active_aura_research.duplicate(true)
	save.aura_research_progress = GameState.aura_research_progress.duplicate(true)

	save.interrupt_state = GameState.interrupt_state
	save.battlefield_data = GameState.battlefield_data

	save.unlocked_units = Globals.unlocked_units.duplicate()
	save.unlocked_items = Globals.unlocked_items.duplicate()
	save.unlocked_relics = RelicManager.get_unlocked_relics()
	save.unlocked_talents = Globals.unlocked_talents.duplicate()
	save.unlocked_recipes = GameState.unlocked_recipes.duplicate()
	save.unlocked_stories = GameState.unlocked_stories.duplicate()

	save.eligible_units = GameState.eligible_units.duplicate()
	save.current_node_unlock_relics = GameState.current_node_unlock_relics.duplicate()
	save.current_node_unlock_units = GameState.current_node_unlock_units.duplicate()

	save.unit_growth = GameState.unit_growth.duplicate(true)
	save.unit_blessings = GameState.unit_blessings.duplicate(true)
	save.talent_exp = GameState.talent_exp.duplicate(true)

	save.arena_target_talents = GameState.arena_target_talents.duplicate(true)
	save.arena_best_streak = GameState.arena_best_streak
	save.arena_clear_count = GameState.arena_clear_count
	save.arena_survival_clear = GameState.arena_survival_clear
	save.arena_survival_best = GameState.arena_survival_best
	save.arena_total_crystals = GameState.arena_total_crystals
	save.arena_total_runs = GameState.arena_total_runs

	save.pending_sacrifice_rewards = []
	for inst in GameState.pending_sacrifice_rewards:
		save.pending_sacrifice_rewards.append(_serialize_item_instance(inst))
	save.pending_forge_rewards = []
	for inst in GameState.pending_forge_rewards:
		save.pending_forge_rewards.append(_serialize_item_instance(inst))
	save.sacrifice_count = GameState.sacrifice_count
	save.tutorial_stage = GameState.tutorial_stage

	save.npc_dialogue_seen = GameState.npc_dialogue_seen.duplicate(true)
	save.npc_dialogue_flags = GameState.npc_dialogue_flags.duplicate()
	save.total_run_count = GameState.total_run_count
	save.total_dispatch_count = GameState.total_dispatch_count
	save.npc_affinity = GameState.npc_affinity.duplicate(true)
	GameState.npc_interact_counts = _safe_dict(save.npc_interact_counts)
	GameState.dialogue_play_counts = _safe_dict(save.dialogue_play_counts)
	GameState.active_narrative_effects = _safe_array(save.active_narrative_effects)
	GameState.revealed_intel = _safe_array(save.revealed_intel)
	GameState.fusion_hints = _safe_array(save.fusion_hints)

	save.save_time = Time.get_unix_time_from_system()
	return save


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
	GameState.current_faction = save.current_faction
	GameState.current_node_key = save.current_node_key
	GameState.map_snapshot = _safe_dict(save.map_snapshot)
	GameState.shop_level = save.shop_level

	GameState.visited_nodes.clear()
	if save.visited_nodes is Array:
		for pair in save.visited_nodes:
			if pair is Array and pair.size() == 2:
				GameState.visited_nodes[pair[0]] = pair[1]

	GameState.party.clear()
	for d in save.party_data:
		if d is Dictionary:
			GameState.party.append(UnitData.from_dict(d))

	GameState.init_passive_slots()
	var arr = save.equipped_passives
	if arr is Array:
		for i in range(min(arr.size(), 4)):
			GameState.set_passive_at_slot(i, _deserialize_passive(arr[i]))

	GameState.soul = save.soul
	GameState.keys = save.keys
	GameState.keys_bought = save.keys_bought
	GameState.pending_tag_pin = save.pending_tag_pin
	GameState.active_tag_pin = save.active_tag_pin
	GameState.soul_fire_threshold_override = save.soul_fire_threshold_override
	GameState.cycle_start_soul = save.cycle_start_soul
	GameState.temp_gold = save.temp_gold

	# ★ v4.5：遗物精炼
	GameState.relic_levels = _safe_dict(save.relic_levels)

	SoulFireManager.current = save.soul_fire_current
	SoulFireManager.altar_level = save.soul_fire_altar_level
	GameState.soul_fire_initial_level = save.soul_fire_initial_level

	GameState.unit_attr_cap = _safe_dict(save.unit_attr_cap)
	GameState.unit_attr_points = _safe_dict(save.unit_attr_points)
	GameState.tag_purchase_count = _safe_dict(save.tag_purchase_count)

	GameState.unlocked_auras = _safe_array(save.unlocked_auras)
	GameState.active_aura_research = _safe_dict(save.active_aura_research)
	GameState.aura_research_progress = _safe_dict(save.aura_research_progress)

	GameState.interrupt_state = save.interrupt_state as GameState.InterruptState
	GameState.battlefield_data = _safe_dict(save.battlefield_data)

	RelicManager.set_unlocked_relics(_safe_array(save.unlocked_relics))
	Globals.unlocked_units = _filter_valid_unit_keys(_safe_array(save.unlocked_units))
	Globals.unlocked_items = _safe_array(save.unlocked_items)

	if Globals.unlocked_units.is_empty():
		print("[SaveManager] unlocked_units 为空，回退默认解锁")
		Globals._load_unlock_config()

	GameState.tutorial_stage = save.tutorial_stage
	if save.unlocked_talents.is_empty():
		Globals.reload_talent_unlock()
	else:
		Globals.unlocked_talents = _safe_array(save.unlocked_talents)

	GameState.unlocked_recipes = _safe_array(save.unlocked_recipes)
	GameState.unlocked_stories = _safe_array(save.unlocked_stories)

	GameState.eligible_units = _filter_valid_unit_keys(_safe_array(save.eligible_units))
	GameState.current_node_unlock_relics = _safe_string_array(save.current_node_unlock_relics)
	GameState.current_node_unlock_units = _safe_string_array(save.current_node_unlock_units)

	GameState.unit_growth = _safe_dict(save.unit_growth)
	GameState.unit_blessings = _safe_dict(save.unit_blessings)
	GameState.talent_exp = _safe_dict(save.talent_exp)

	GameState.arena_target_talents = _safe_dict(save.arena_target_talents)
	GameState.arena_best_streak = save.arena_best_streak
	GameState.arena_clear_count = save.arena_clear_count
	GameState.arena_survival_clear = save.arena_survival_clear
	GameState.arena_survival_best = save.arena_survival_best
	GameState.arena_total_crystals = save.arena_total_crystals
	GameState.arena_total_runs = save.arena_total_runs

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

	GameState.sacrifice_count = save.sacrifice_count

	GameState.npc_dialogue_seen = _safe_dict(save.npc_dialogue_seen)
	GameState.npc_dialogue_flags = _safe_array(save.npc_dialogue_flags)
	GameState.total_run_count = save.total_run_count
	GameState.total_dispatch_count = save.total_dispatch_count
	GameState.npc_affinity = _safe_dict(save.npc_affinity)

	if Globals.unlocked_items.is_empty():
		Globals.unlocked_items = Globals.item_unlocked_items.duplicate()

	LevelManager.current_level_index = 0
	LevelManager.is_map_mode = true
	Globals.is_map_mode = true

	if GameState.current_node_key != "":
		GameState.visited_nodes.erase(GameState.current_node_key)
		GameState.current_node_key = ""


# ============================================================
#  类型安全辅助
# ============================================================
static func _safe_dict(v : Variant) -> Dictionary:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	return {}

static func _safe_array(v : Variant) -> Array:
	if v is Array:
		return (v as Array).duplicate()
	return []


static func _safe_string_array(v : Variant) -> Array[String]:
	var result : Array[String] = []
	if v is Array:
		for item in v:
			if item is String and (item as String) != "":
				result.append(item)
	return result


static func _filter_valid_unit_keys(keys: Array) -> Array:
	var result : Array = []
	for k in keys:
		if not (k is String) or k == "":
			continue
		var key : String = UnitDataManager.normalize_unit_key(k)
		if UnitDataManager.get_unit_data(key).is_empty():
			continue
		if key not in result:
			result.append(key)
	return result


# ============================================================
#  序列化辅助
# ============================================================
func _serialize_item_instance(inst) -> Dictionary:
	if inst == null: return {}
	if inst is ItemInstance:
		return {
			"item_id": inst.item_id, "count": inst.count,
			"upgrade_level": inst.upgrade_level,
			"affixes": inst.affixes.duplicate(true),
		}
	return {}


func _deserialize_item_instance(d) -> Variant:
	if not (d is Dictionary) or d.is_empty(): return null
	var item_id : String = d.get("item_id", "")
	if item_id == "": return null
	var inst = ItemInstance.new()
	inst.item_id = item_id
	inst.count = d.get("count", 1)
	inst.upgrade_level = d.get("upgrade_level", 0)
	var af : Variant = d.get("affixes", [])
	if af is Array:
		inst.affixes.clear()
		for a in af:
			if a is Dictionary:
				inst.affixes.append({"id": a.get("id", ""), "value": int(a.get("value", 0))})
	return inst


func _serialize_passive(entry) -> Dictionary:
	if entry == null: return {"type": "empty"}
	if entry is ItemInstance:
		return {"type": "relic", "item_id": entry.item_id}
	if entry is Dictionary and entry.get("type", "") == "aura":
		return {"type": "aura", "aura_id": entry.get("aura_id", "")}
	return {"type": "empty"}


func _deserialize_passive(d) -> Variant:
	if not (d is Dictionary): return null
	var t = d.get("type", "empty")
	if t == "relic":
		var item_id = d.get("item_id", "")
		if item_id == "": return null
		var inst = ItemInstance.new()
		inst.item_id = item_id; inst.count = 1
		return inst
	if t == "aura":
		var aid = d.get("aura_id", "")
		if aid == "": return null
		return {"type": "aura", "aura_id": aid}
	return null


# ============================================================
#  校验（★ 第九批：只校验版本，不再校验 checksum）
# ============================================================
func _validate_save(save: SaveData) -> bool:
	if not save: return false
	if save.save_version <= 0: return false
	return true


func load_save_data(slot: int) -> SaveData:
	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path): return null
	return load(path) as SaveData


func is_map_data_valid(save: SaveData) -> bool:
	return not save.party_data.is_empty()


func clean_invalid_progress(slot: int):
	var save = load_save_data(slot)
	if not save: return
	save.visited_nodes = []
	save.current_day = 1
	save.selected_node_id = ""
	save.interrupt_state = 1
	save.temp_gold = 0
	# ★ 第九批：不再算 checksum
	ResourceSaver.save(save, _get_slot_path(slot))


func _get_slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.tres" % slot


func _get_map_scene():
	var scene = get_tree().current_scene
	if scene and scene is MapSceneClass: return scene
	return null


func has_save(slot: int) -> bool:
	return ResourceLoader.exists(_get_slot_path(slot))


func get_save_info(slot: int) -> Dictionary:
	var path = _get_slot_path(slot)
	if not ResourceLoader.exists(path): return {}
	var save = load(path) as SaveData
	if not save: return {}
	return {
		"time": save.save_time, "day": save.current_day,
		"main_unit": save.main_unit_name,
		"party": save.party_data.size(), "soul": save.soul
	}


func delete_save(slot: int):
	var path = _get_slot_path(slot)
	if ResourceLoader.exists(path):
		DirAccess.remove_absolute(path)
		if current_slot == slot: current_slot = -1


func find_empty_slot() -> int:
	for i in range(SLOT_COUNT):
		if not has_save(i): return i
	return -1


func reset_current_slot():
	current_slot = -1
