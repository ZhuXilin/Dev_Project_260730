extends Node

# ============================================================
#  中断状态枚举
# ============================================================
enum InterruptState {
	NONE,
	CAMP,
	MAP,
	BATTLEFIELD,
}

# ============================================================
#  三个状态对象
# ============================================================
var party_state : PartyState = PartyState.new()
var progress_state : ProgressState = ProgressState.new()
var resource_state : ResourceState = ResourceState.new()

# ============================================================
#  常量
# ============================================================
const MAX_ARMOR_SLOTS_CAP : int = 4
const ARMOR_STORAGE_SIZE : int = 6

# ============================================================
#  属性转发：PartyState
# ============================================================
var party : Array[UnitData]:
	get: return party_state.party
	set(value): party_state.party = value

var max_party_size : int:
	get: return party_state.max_party_size
	set(value): party_state.max_party_size = value

var main_unit_name : String:
	get: return party_state.main_unit_name
	set(value): party_state.main_unit_name = value

var main_unit_index : int:
	get: return party_state.main_unit_index
	set(value): party_state.main_unit_index = value

var current_faction : String:
	get: return party_state.current_faction
	set(value): party_state.current_faction = value

var equipped_passives : Array:
	get: return party_state.equipped_passives
	set(value): party_state.equipped_passives = value

func init_passive_slots():
	party_state.init_passive_slots()

func get_passives() -> Array:
	return party_state.get_passives()

func set_passive_at_slot(idx: int, value):
	party_state.set_passive_at_slot(idx, value)

func remove_passive_at_slot(idx: int):
	party_state.remove_passive_at_slot(idx)

func is_passive_full() -> bool:
	return party_state.is_passive_full()

func add_relic_to_passive_slot(inst: ItemInstance) -> bool:
	return party_state.add_relic_to_passive_slot(inst)

func add_refine_to_passive_slot(refine_id: String) -> bool:
	return party_state.add_refine_to_passive_slot(refine_id)

func get_relics_from_passives() -> Array:
	return party_state.get_relics_from_passives()

func get_refines_from_passives() -> Array:
	return party_state.get_refines_from_passives()

func clear_refine_passives():
	party_state.clear_refine_passives()

# ============================================================
#  属性转发：ProgressState
# ============================================================
var current_day : int:
	get: return progress_state.current_day
	set(value): progress_state.current_day = value

var current_map_index : int:
	get: return progress_state.current_map_index
	set(value): progress_state.current_map_index = value

var visited_nodes : Dictionary:
	get: return progress_state.visited_nodes
	set(value): progress_state.visited_nodes = value

var current_node_key : String:
	get: return progress_state.current_node_key
	set(value): progress_state.current_node_key = value

var is_map_mode : bool:
	get: return progress_state.is_map_mode
	set(value): progress_state.is_map_mode = value

var resume_node_id : String:
	get: return progress_state.resume_node_id
	set(value): progress_state.resume_node_id = value

var last_selected_node_type : int:
	get: return progress_state.last_selected_node_type
	set(value): progress_state.last_selected_node_type = value

var should_advance_day : bool:
	get: return progress_state.should_advance_day
	set(value): progress_state.should_advance_day = value

var cached_map_level_data : MapLevelData:
	get: return progress_state.cached_map_level_data
	set(value): progress_state.cached_map_level_data = value

var cached_day : int:
	get: return progress_state.cached_day
	set(value): progress_state.cached_day = value

var current_map_data : MapData:
	get: return progress_state.current_map_data
	set(value): progress_state.current_map_data = value

var map_snapshot : Dictionary:
	get: return progress_state.map_snapshot
	set(value): progress_state.map_snapshot = value

var interrupt_state : InterruptState:
	get: return progress_state.interrupt_state as InterruptState
	set(value): progress_state.interrupt_state = value

var battlefield_data : Dictionary:
	get: return progress_state.battlefield_data
	set(value): progress_state.battlefield_data = value

# ============================================================
#  属性转发：ResourceState
# ============================================================
var soul : int:
	get: return resource_state.soul
	set(value): resource_state.soul = value

var temp_soul : int:
	get: return resource_state.temp_soul
	set(value): resource_state.temp_soul = value

var temp_gold : int:
	get: return resource_state.temp_gold
	set(value): resource_state.temp_gold = value

var materials : Dictionary:
	get: return resource_state.materials
	set(value): resource_state.materials = value

var cycle_start_soul : int:
	get: return resource_state.cycle_start_soul
	set(value): resource_state.cycle_start_soul = value

var cycle_start_materials : Dictionary:
	get: return resource_state.cycle_start_materials
	set(value): resource_state.cycle_start_materials = value

var reward_items : Array:
	get: return resource_state.reward_items
	set(value): resource_state.reward_items = value

var current_reward_gold : int:
	get: return resource_state.current_reward_gold
	set(value): resource_state.current_reward_gold = value

var current_reward_soul : int:
	get: return resource_state.current_reward_soul
	set(value): resource_state.current_reward_soul = value

var current_reward_materials : Dictionary:
	get: return resource_state.current_reward_materials
	set(value): resource_state.current_reward_materials = value

var unlocked_recipes : Array:
	get: return resource_state.unlocked_recipes
	set(value): resource_state.unlocked_recipes = value

var unlocked_stories : Array:
	get: return resource_state.unlocked_stories
	set(value): resource_state.unlocked_stories = value

var unit_growth : Dictionary:
	get: return resource_state.unit_growth
	set(value): resource_state.unit_growth = value

var unit_blessings : Dictionary:
	get: return resource_state.unit_blessings
	set(value): resource_state.unit_blessings = value

var talent_exp : Dictionary:
	get: return resource_state.talent_exp
	set(value): resource_state.talent_exp = value

var arena_target_talents : Dictionary:
	get: return resource_state.arena_target_talents
	set(value): resource_state.arena_target_talents = value

var unlocked_refine_recipes : Array:
	get: return resource_state.unlocked_refine_recipes
	set(value): resource_state.unlocked_refine_recipes = value

var refined_items : Dictionary:
	get: return resource_state.refined_items
	set(value): resource_state.refined_items = value

var tutorial_stage : int:
	get: return resource_state.tutorial_stage
	set(value): resource_state.tutorial_stage = value

var armor_storage : Array:
	get: return resource_state.armor_storage
	set(value): resource_state.armor_storage = value

# ---- 斗技场统计 ----
var arena_best_streak : int:
	get: return resource_state.arena_best_streak
	set(value): resource_state.arena_best_streak = value

var arena_clear_count : int:
	get: return resource_state.arena_clear_count
	set(value): resource_state.arena_clear_count = value

var arena_survival_clear : int:
	get: return resource_state.arena_survival_clear
	set(value): resource_state.arena_survival_clear = value

var arena_survival_best : int:
	get: return resource_state.arena_survival_best
	set(value): resource_state.arena_survival_best = value

var arena_total_crystals : int:
	get: return resource_state.arena_total_crystals
	set(value): resource_state.arena_total_crystals = value

var arena_total_runs : int:
	get: return resource_state.arena_total_runs
	set(value): resource_state.arena_total_runs = value

# ============================================================
#  非转发字段
# ============================================================
var pending_save_slot : int = -1

# ============================================================
#  队伍相关
# ============================================================
func initialize_party(selected_units: Array[String], main_index: int):
	party_state.initialize_party(selected_units, main_index)

func get_party_units() -> Array[UnitData]:
	return party_state.get_party_units()

func get_main_unit() -> UnitData:
	return party_state.get_main_unit()

func sync_units_from_battlefield(battle_units: Array):
	party_state.sync_units_from_battlefield(battle_units)

# ============================================================
#  防具仓库
# ============================================================
func init_armor_storage():
	resource_state.armor_storage.clear()
	for i in range(ARMOR_STORAGE_SIZE):
		resource_state.armor_storage.append(null)

func add_armor_to_storage(inst: ItemInstance) -> bool:
	if inst == null:
		return false
	if resource_state.armor_storage.size() < ARMOR_STORAGE_SIZE:
		init_armor_storage()
	for i in range(resource_state.armor_storage.size()):
		if resource_state.armor_storage[i] == null:
			resource_state.armor_storage[i] = inst
			return true
	return false

func is_armor_storage_full() -> bool:
	if resource_state.armor_storage.is_empty():
		return false
	for s in resource_state.armor_storage:
		if s == null:
			return false
	return true

func count_free_storage_slots() -> int:
	var n : int = 0
	for s in resource_state.armor_storage:
		if s == null:
			n += 1
	return n

func remove_armor_from_storage(idx: int):
	if idx < 0 or idx >= resource_state.armor_storage.size():
		return
	resource_state.armor_storage[idx] = null

# ============================================================
#  永久死亡 / 复活
# ============================================================
func is_unit_dead(unit_name: String, display_name: String) -> bool:
	for ud in party:
		if ud.unit_name == unit_name and ud.display_name == display_name:
			return ud.is_dead
	return false

func revive_unit(unit_name: String, display_name: String) -> bool:
	for ud in party:
		if ud.unit_name == unit_name and ud.display_name == display_name:
			if not ud.is_dead:
				return false
			ud.is_dead = false
			ud.hit_points = ud.max_hp
			print("[复活] %s 满血复活" % ud.display_name)
			return true
	return false

func revive_all_units():
	for ud in party:
		if ud.is_dead:
			ud.is_dead = false
			ud.hit_points = ud.max_hp
			print("[复活] %s 满血复活" % ud.display_name)

func get_alive_party() -> Array:
	var result : Array = []
	for ud in party:
		if not ud.is_dead:
			result.append(ud)
	return result

func get_dead_party() -> Array:
	var result : Array = []
	for ud in party:
		if ud.is_dead:
			result.append(ud)
	return result

func has_any_dead_unit() -> bool:
	for ud in party:
		if ud.is_dead:
			return true
	return false

# ============================================================
#  遗物/被动统计
# ============================================================
func get_global_relic_stats() -> Dictionary:
	var bonus = {}
	for relic in get_relics_from_passives():
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty():
			continue
		var stats = data.get("stats", {})
		for key in stats:
			bonus[key] = bonus.get(key, 0) + stats[key]
	return bonus


func get_global_relic_effects() -> Dictionary:
	var effects := {}
	for relic in get_relics_from_passives():
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty():
			continue
		var e : Dictionary = data.get("effects", {})
		for key in e:
			var add = e[key]
			if not effects.has(key):
				effects[key] = add
			else:
				var cur = effects[key]
				if cur is bool and add is bool:
					effects[key] = cur or add
				elif cur is int and add is int:
					effects[key] = cur + add
				elif cur is float or add is float:
					effects[key] = float(cur) + float(add)
				else:
					effects[key] = add
	return effects

# ============================================================
#  进度相关
# ============================================================
func reset_progress():
	progress_state.reset_progress()

func undo_battle_entry():
	progress_state.undo_battle_entry()

# ============================================================
#  资源相关
# ============================================================
func add_material(material_name: String, amount: int):
	resource_state.add_material(material_name, amount)
	SaveManager.auto_save()

func get_material(material_name: String) -> int:
	return resource_state.get_material(material_name)

func get_all_materials() -> Dictionary:
	return resource_state.get_all_materials()

func reset_materials():
	resource_state.reset_materials()

func add_reward_item(item_id: String):
	resource_state.add_reward_item(item_id)

func clear_reward_items():
	resource_state.clear_reward_items()

func clear_current_reward():
	resource_state.clear_current_reward()

# ============================================================
#  编排方法
# ============================================================
func start_new_cycle():
	temp_soul = 0
	temp_gold = 0
	cycle_start_soul = soul
	cycle_start_materials = materials.duplicate()

	for unit_data in party:
		unit_data.armor_slots.clear()
		unit_data.max_armor_slots = 2
		unit_data.is_dead = false   # ★ 新循环，重置死亡状态
		var default_weapon = UnitDataManager.get_default_weapon_id(unit_data.unit_name)
		if default_weapon != "":
			var inst = ItemInstance.new()
			inst.item_id = default_weapon
			inst.count = 1
			unit_data.weapon_slot = inst
		else:
			unit_data.weapon_slot = null
	init_passive_slots()
	init_armor_storage()   # ★ 新循环，清空仓库


func finish_day(grant_slot: bool = true):
	soul += temp_soul
	temp_soul = 0
	if grant_slot:
		for unit_data in party:
			if unit_data.max_armor_slots < MAX_ARMOR_SLOTS_CAP:
				unit_data.armor_slots.append(null)
				unit_data.max_armor_slots += 1
	print("每天结束：soul=", soul, " 槽位上限=", MAX_ARMOR_SLOTS_CAP)


func finish_cycle():
	# ★ 三天完成：只合并资源，不 +1 槽
	finish_day(false)
	# ★ 全员复活
	revive_all_units()
	# ★ 推进新手阶段
	if tutorial_stage < 3:
		tutorial_stage += 1
		Globals.reload_talent_unlock()
		print("[Tutorial] 新手阶段 → %d（已重载词条解锁）" % tutorial_stage)


func abandon_cycle():
	temp_soul = 0
	temp_gold = 0


func abandon_and_return_to_camp():
	await Globals.show_cycle_reward()
	finish_day(false)
	abandon_cycle()
	reset_all()
	interrupt_state = InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file(Config.PATHS.CAMP)


func show_abandon_confirmation(parent: Node):
	Globals.show_confirm(
		parent,
		"确定放弃本局游戏吗？进度将丢失，已获得的临时资源将丢弃。",
		"放弃",
		"取消",
		abandon_and_return_to_camp,
		func(): pass
	)


func reset_for_new_cycle():
	party.clear()
	main_unit_name = ""
	visited_nodes.clear()
	current_day = 1
	cached_map_level_data = null
	cached_day = -1
	resume_node_id = ""
	should_advance_day = false
	current_map_data = null
	last_selected_node_type = -1
	LevelManager.current_day = 0
	LevelManager.current_level_index = 0
	temp_soul = 0
	temp_gold = 0
	interrupt_state = InterruptState.NONE
	init_passive_slots()
	init_armor_storage()
	current_faction = ""
	map_snapshot.clear()
	cycle_start_soul = 0
	cycle_start_materials.clear()


func reset_all():
	party.clear()
	main_unit_name = ""
	visited_nodes.clear()
	current_day = 1
	current_map_index = 0
	is_map_mode = false
	should_advance_day = false
	resume_node_id = ""
	cached_map_level_data = null
	cached_day = -1
	current_map_data = null
	last_selected_node_type = -1
	LevelManager.reset()
	temp_soul = 0
	temp_gold = 0
	interrupt_state = InterruptState.NONE
	init_passive_slots()
	init_armor_storage()
	current_faction = ""
	map_snapshot.clear()
	cycle_start_soul = 0
	cycle_start_materials.clear()


func apply_relic_stats_to_unit(_unit_data: UnitData):
	pass
