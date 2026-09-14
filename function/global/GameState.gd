extends Node

# ============================================================
#  中断状态枚举（保留在 GameState，逻辑定义）
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
#  属性转发：PartyState（零破坏）
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

var global_relics : Array:
	get: return party_state.global_relics
	set(value): party_state.global_relics = value

const MAX_RELIC_SLOTS : int = 3

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

# ============================================================
#  非转发字段（不属于任何 state）
# ============================================================
var pending_save_slot : int = -1

# ============================================================
#  队伍相关（转发到 party_state 方法）
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
#  遗物相关（转发到 party_state 方法）
# ============================================================
func init_relic_slots():
	party_state.init_relic_slots()

func add_global_relic(instance: ItemInstance) -> bool:
	return party_state.add_global_relic(instance)

func remove_global_relic_at_slot(slot_idx: int):
	party_state.remove_global_relic_at_slot(slot_idx)

func get_global_relics() -> Array:
	return party_state.get_global_relics()

func get_active_relics() -> Array:
	return party_state.get_active_relics()

func get_global_relic_stats() -> Dictionary:
	return party_state.get_global_relic_stats()

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
#  编排方法（跨 state，保留在 GameState）
# ============================================================
func start_new_cycle():
	temp_soul = 0
	temp_gold = 0
	cycle_start_soul = soul
	cycle_start_materials = materials.duplicate()

	for unit_data in party:
		unit_data.armor_slots.clear()
		unit_data.max_armor_slots = 2
		var default_weapon = UnitDataManager.get_default_weapon_id(unit_data.unit_name)
		if default_weapon != "":
			var inst = ItemInstance.new()
			inst.item_id = default_weapon
			inst.count = 1
			unit_data.weapon_slot = inst
		else:
			unit_data.weapon_slot = null
	init_relic_slots()

func finish_day():
	soul += temp_soul
	temp_soul = 0
	for unit_data in party:
		unit_data.armor_slots.append(null)
		unit_data.max_armor_slots += 1
	print("每天结束：soul=", soul, " temp_soul 已清零")

func finish_cycle():
	finish_day()

func abandon_cycle():
	temp_soul = 0
	temp_gold = 0

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
	init_relic_slots()
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
	init_relic_slots()
	current_faction = ""
	map_snapshot.clear()
	cycle_start_soul = 0
	cycle_start_materials.clear()

func abandon_and_return_to_camp():
	await Globals.show_cycle_reward()
	finish_day()
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
