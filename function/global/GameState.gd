extends Node

enum InterruptState { NONE, CAMP, MAP, BATTLEFIELD }

var shop_level : int = 0

var party_state : PartyState = PartyState.new()
var progress_state : ProgressState = ProgressState.new()
var resource_state : ResourceState = ResourceState.new()

const MAX_ARMOR_SLOTS_CAP : int = 4
const REFINE_COST : int = 150

# ============================================================
#  PartyState 转发
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

var unlocked_avatars : Dictionary:
	get: return resource_state.unlocked_avatars
	set(value): resource_state.unlocked_avatars = value

func init_passive_slots(): party_state.init_passive_slots()
func get_passives() -> Array: return party_state.get_passives()
func set_passive_at_slot(idx: int, value): party_state.set_passive_at_slot(idx, value)
func remove_passive_at_slot(idx: int): party_state.remove_passive_at_slot(idx)
func is_passive_full() -> bool: return party_state.is_passive_full()
func add_relic_to_passive_slot(inst: ItemInstance) -> bool:
	return party_state.add_relic_to_passive_slot(inst)
func get_relics_from_passives() -> Array: return party_state.get_relics_from_passives()

func add_aura_to_passive_slot(aura_id: String) -> bool:
	return party_state.add_aura_to_passive_slot(aura_id)
func get_auras_from_passives() -> Array:
	return party_state.get_auras_from_passives()
func is_aura_equipped(aura_id: String) -> bool:
	return party_state.is_aura_equipped(aura_id)

# ============================================================
#  ProgressState 转发
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
#  ResourceState 转发
# ============================================================
var soul : int:
	get: return resource_state.soul
	set(value): resource_state.soul = value
var temp_gold : int:
	get: return resource_state.temp_gold
	set(value): resource_state.temp_gold = value
var soul_fire_current : int:
	get: return resource_state.soul_fire_current
	set(value): resource_state.soul_fire_current = value
var soul_fire_altar_level : int:
	get: return resource_state.soul_fire_altar_level
	set(value): resource_state.soul_fire_altar_level = value
var soul_fire_initial_level : int:
	get: return resource_state.soul_fire_initial_level
	set(value): resource_state.soul_fire_initial_level = value
var unit_attr_cap : Dictionary:
	get: return resource_state.unit_attr_cap
	set(value): resource_state.unit_attr_cap = value
var unit_attr_points : Dictionary:
	get: return resource_state.unit_attr_points
	set(value): resource_state.unit_attr_points = value
var tag_purchase_count : Dictionary:
	get: return resource_state.tag_purchase_count
	set(value): resource_state.tag_purchase_count = value
var unlocked_auras : Array:
	get: return resource_state.unlocked_auras
	set(value): resource_state.unlocked_auras = value
var active_aura_research : Dictionary:
	get: return resource_state.active_aura_research
	set(value): resource_state.active_aura_research = value
var aura_research_progress : Dictionary:
	get: return resource_state.aura_research_progress
	set(value): resource_state.aura_research_progress = value
var cycle_start_soul : int:
	get: return resource_state.cycle_start_soul
	set(value): resource_state.cycle_start_soul = value
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
var current_reward_rare_datas : Array:
	get: return resource_state.current_reward_rare_datas
	set(value): resource_state.current_reward_rare_datas = value
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
var eligible_units : Array:
	get: return resource_state.eligible_units
	set(value): resource_state.eligible_units = value
var tutorial_stage : int:
	get: return resource_state.tutorial_stage
	set(value): resource_state.tutorial_stage = value
var pending_sacrifice_rewards : Array:
	get: return resource_state.pending_sacrifice_rewards
	set(value): resource_state.pending_sacrifice_rewards = value
var pending_forge_rewards : Array:
	get: return resource_state.pending_forge_rewards
	set(value): resource_state.pending_forge_rewards = value
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
var sacrifice_count : int:
	get: return resource_state.sacrifice_count
	set(value): resource_state.sacrifice_count = value
var current_node_unlock_relics : Array:
	get: return progress_state.current_node_unlock_relics
	set(value): progress_state.current_node_unlock_relics.assign(value)
var current_node_unlock_units : Array:
	get: return progress_state.current_node_unlock_units
	set(value): progress_state.current_node_unlock_units.assign(value)
var npc_dialogue_seen : Dictionary:
	get: return resource_state.npc_dialogue_seen
	set(value): resource_state.npc_dialogue_seen = value
var npc_dialogue_flags : Array:
	get: return resource_state.npc_dialogue_flags
	set(value): resource_state.npc_dialogue_flags = value
var total_run_count : int:
	get: return resource_state.total_run_count
	set(value): resource_state.total_run_count = value
var total_dispatch_count : int:
	get: return resource_state.total_dispatch_count
	set(value): resource_state.total_dispatch_count = value
var keys : int:
	get: return resource_state.keys
	set(value): resource_state.keys = value
var keys_bought : int:
	get: return resource_state.keys_bought
	set(value): resource_state.keys_bought = value
var pending_tag_pin : String:
	get: return resource_state.pending_tag_pin
	set(value): resource_state.pending_tag_pin = value
var active_tag_pin : String:
	get: return resource_state.active_tag_pin
	set(value): resource_state.active_tag_pin = value
var soul_fire_threshold_override : float:
	get: return resource_state.soul_fire_threshold_override
	set(value): resource_state.soul_fire_threshold_override = value
var relic_levels: Dictionary:
	get: return resource_state.relic_levels
	set(value): resource_state.relic_levels = value
var npc_interact_counts: Dictionary:
	get: return resource_state.npc_interact_counts
	set(value): resource_state.npc_interact_counts = value
var dialogue_play_counts: Dictionary:
	get: return resource_state.dialogue_play_counts
	set(value): resource_state.dialogue_play_counts = value
var active_narrative_effects: Array:
	get: return resource_state.active_narrative_effects
	set(value): resource_state.active_narrative_effects = value
var revealed_intel: Array:
	get: return resource_state.revealed_intel
	set(value): resource_state.revealed_intel = value
var fusion_hints: Array:
	get: return resource_state.fusion_hints
	set(value): resource_state.fusion_hints = value
var unlocked_npc_avatars : Dictionary:
	get: return resource_state.unlocked_npc_avatars
	set(value): resource_state.unlocked_npc_avatars = value

func get_shop_tag_boost(tag: String) -> int:
	var total: int = 0
	for e in active_narrative_effects:
		if not (e is Dictionary): continue
		var ed: Dictionary = e
		if ed.get("type", "") == "shop_tag_weight_boost" and ed.get("tag", "") == tag:
			total += int(ed.get("amount", 0))
	return total

func clear_narrative_effects_for_new_run() -> void:
	active_narrative_effects.clear()
	revealed_intel.clear()
	fusion_hints.clear()

func is_relic_refined(relic_id: String) -> bool:
	return int(relic_levels.get(relic_id, 0)) >= 1

func refine_relic(relic_id: String) -> bool:
	if is_relic_refined(relic_id): return false
	if soul < REFINE_COST: return false
	soul -= REFINE_COST
	relic_levels[relic_id] = 1
	SaveManager.auto_save()
	AnalyticsLogger.record_relic_refine(relic_id)
	return true

var pending_save_slot : int = -1

func initialize_party(selected_units: Array[String], main_index: int):
	party_state.initialize_party(selected_units, main_index)

func get_party_units() -> Array[UnitData]: return party_state.get_party_units()
func get_main_unit() -> UnitData: return party_state.get_main_unit()
func sync_units_from_battlefield(battle_units: Array):
	party_state.sync_units_from_battlefield(battle_units)

func has_pending_sacrifice_rewards() -> bool:
	return not resource_state.pending_sacrifice_rewards.is_empty()
func has_pending_forge_rewards() -> bool:
	return not resource_state.pending_forge_rewards.is_empty()
func has_any_pending_rewards() -> bool:
	return has_pending_sacrifice_rewards() or has_pending_forge_rewards()
func clear_pending_sacrifice_rewards(): resource_state.pending_sacrifice_rewards.clear()
func clear_pending_forge_rewards(): resource_state.pending_forge_rewards.clear()
func clear_all_pending_rewards():
	resource_state.pending_sacrifice_rewards.clear()
	resource_state.pending_forge_rewards.clear()

var npc_affinity : Dictionary:
	get: return resource_state.npc_affinity
	set(value): resource_state.npc_affinity = value

func is_unit_dead(unit_name: String, display_name: String) -> bool:
	for ud in party:
		if ud.unit_name == unit_name and ud.display_name == display_name:
			return ud.is_dead
	return false


func revive_all_units():
	for ud in party:
		if ud.is_dead:
			ud.is_dead = false
			ud.hit_points = ud.max_hp
	for m in party:
		m.sacrifice_buff_sources.clear()

func get_alive_party() -> Array:
	var result : Array = []
	for ud in party:
		if not ud.is_dead: result.append(ud)
	return result

func get_dead_party() -> Array:
	var result : Array = []
	for ud in party:
		if ud.is_dead: result.append(ud)
	return result

func has_any_dead_unit() -> bool:
	for ud in party:
		if ud.is_dead: return true
	return false

func get_global_relic_stats() -> Dictionary:
	var bonus = {}
	for relic in get_relics_from_passives():
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty(): continue
		var stats = data.get("stats", {})
		for key in stats:
			bonus[key] = bonus.get(key, 0) + stats[key]
	return bonus

func is_relic_equipped_and_refined(relic_id : String) -> bool:
	if not is_relic_refined(relic_id): return false
	for relic in get_relics_from_passives():
		if relic.item_id == relic_id: return true
	return false

func get_global_relic_effects() -> Dictionary:
	var effects := {}
	var equipped_ids : Dictionary = {}
	for relic in get_relics_from_passives():
		var data = RelicManager.get_relic_data(relic.item_id)
		if data.is_empty(): continue
		equipped_ids[relic.item_id] = true
		var e : Dictionary = data.get("effects", {})
		for key in e:
			var add = e[key]
			if not effects.has(key):
				effects[key] = add
			else:
				var cur = effects[key]
				if cur is bool and add is bool: effects[key] = cur or add
				elif cur is int and add is int: effects[key] = cur + add
				elif cur is float or add is float: effects[key] = float(cur) + float(add)
				else: effects[key] = add
	if equipped_ids.has("relic_speed") and is_relic_refined("relic_speed"):
		effects["kill_grants_extra_move"] = int(effects.get("kill_grants_extra_move", 2)) + 1
	if equipped_ids.has("relic_health") and is_relic_refined("relic_health"):
		effects["turn_first_hit_regen"] = 0.5
	if equipped_ids.has("relic_strength") and is_relic_refined("relic_strength"):
		effects["strength_scale_damage"] = 0.03
	if equipped_ids.has("relic_dexterity") and is_relic_refined("relic_dexterity"):
		effects["counter_damage_bonus"] = 0.8
	if equipped_ids.has("relic_faith") and is_relic_refined("relic_faith"):
		effects["heal_bonus"] = 0.8
	return effects

func reset_progress(): progress_state.reset_progress()
func undo_battle_entry(): progress_state.undo_battle_entry()
func add_reward_item(item_id: String): resource_state.add_reward_item(item_id)
func clear_reward_items(): resource_state.clear_reward_items()
func clear_current_reward():
	resource_state.clear_current_reward()
	current_reward_rare_datas.clear()


func start_new_cycle():
	total_run_count += 1
	temp_gold = 0
	shop_level = 0
	sacrifice_count = 0
	cycle_start_soul = soul
	keys = 0
	if pending_tag_pin != "":
		active_tag_pin = pending_tag_pin
		pending_tag_pin = ""
	else:
		active_tag_pin = ""
	soul_fire_threshold_override = 0.0
	for unit_data in party:
		unit_data.sacrifice_buff_sources.clear()
		unit_data.armor_slots.clear()
		unit_data.max_armor_slots = 2
		unit_data.is_dead = false
		var default_weapon = UnitDataManager.get_default_weapon_id(unit_data.unit_name)
		if default_weapon != "":
			var inst = ItemInstance.new()
			inst.item_id = default_weapon
			inst.count = 1
			unit_data.weapon_slot = inst
		else:
			unit_data.weapon_slot = null
	init_passive_slots()
	clear_all_pending_rewards()
	SoulFireManager.reset_for_new_run()
	if BossMechanicManager:
		BossMechanicManager.setup_for_node(false)
	clear_narrative_effects_for_new_run()
	SaveManager.auto_save()
	AnalyticsLogger.begin_run()


func finish_day(grant_slot: bool = true):
	soul += SoulFireManager.settle()
	if grant_slot:
		for unit_data in party:
			if unit_data.max_armor_slots < MAX_ARMOR_SLOTS_CAP:
				unit_data.armor_slots.append(null)
				unit_data.max_armor_slots += 1

func finish_cycle():
	finish_day(false)
	revive_all_units()
	if tutorial_stage < 3:
		tutorial_stage += 1
		Globals.reload_talent_unlock()
	AnalyticsLogger.finish_run(true)

func abandon_cycle():
	temp_gold = 0

func abandon_and_return_to_camp():
	AnalyticsLogger.finish_run(false)
	SoulFireManager.settle()
	await Globals.show_cycle_reward()
	finish_day(false)
	abandon_cycle()
	reset_all()
	interrupt_state = InterruptState.CAMP
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file(Config.PATHS.CAMP)

func show_abandon_confirmation(parent: Node):
	Globals.show_confirm(parent,
		"确定放弃本局游戏吗？进度将丢失，已获得的临时资源将丢弃。",
		"放弃", "取消",
		abandon_and_return_to_camp,
		func(): pass)

func _reset_common():
	party.clear()
	main_unit_name = ""
	visited_nodes.clear()
	current_day = 1
	resume_node_id = ""
	should_advance_day = false
	cached_map_level_data = null
	cached_day = -1
	current_map_data = null
	last_selected_node_type = -1
	temp_gold = 0
	interrupt_state = InterruptState.NONE
	init_passive_slots()
	clear_all_pending_rewards()
	current_faction = ""
	map_snapshot.clear()
	cycle_start_soul = 0
	sacrifice_count = 0
	shop_level = 0

func reset_for_new_cycle():
	_reset_common()
	LevelManager.reset()

func reset_all():
	_reset_common()
	current_map_index = 0
	is_map_mode = false
	LevelManager.reset()

var current_aura_candidates : Array = []

func refresh_aura_candidates():
	var equipped : Array = get_auras_from_passives()
	var pool : Array = []
	for aid in unlocked_auras:
		if aid in equipped: continue
		pool.append(aid)
	pool.shuffle()
	var picked : Array = []
	for i in range(mini(3, pool.size())):
		picked.append(pool[i])
	current_aura_candidates = picked

func remove_aura_candidate(aid: String):
	current_aura_candidates.erase(aid)

func apply_relic_stats_to_unit(_unit_data: UnitData): pass

func get_unit_avatar(unit_name: String) -> String:
	if unlocked_avatars.has(unit_name):
		return unlocked_avatars[unit_name]
	return UnitDataManager.get_unit_data(unit_name).get("avatar", "")

func set_unit_avatar(unit_name: String, avatar_id: String):
	unlocked_avatars[unit_name] = avatar_id
	SaveManager.auto_save()
	for u in UnitManager.unit_list:
		if u.unit_stats.unit_name == unit_name:
			u.unit_stats.avatar = avatar_id

func get_npc_avatar(npc_id: String) -> String:
	return str(unlocked_npc_avatars.get(npc_id, ""))

func set_npc_avatar(npc_id: String, avatar_id: String):
	if npc_id == "" or avatar_id == "": return
	unlocked_npc_avatars[npc_id] = avatar_id
	SaveManager.auto_save()

func remove_aura_from_passives(aura_id: String) -> bool:
	return party_state.remove_aura_from_passives(aura_id)
