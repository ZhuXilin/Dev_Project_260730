extends Node

var _auras : Dictionary = {}
var ACCEL_COST : int = 50

func _ready():
	load_auras()
	_load_config()

func load_auras():
	var path : String = Config.PATHS.AURA_DATA
	if not FileAccess.file_exists(path):
		push_error("光环数据不存在: " + path); return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary): return
	_auras = data
	print("[AuraManager] 加载 %d 个光环" % _auras.size())

func _load_config():
	var cfg : Dictionary = GameConfigManager.get_file("economy_config.json")
	ACCEL_COST = int(cfg.get("aura_research", {}).get("accel_cost", 50))

func get_aura(aura_id: String) -> Dictionary:
	return _auras.get(aura_id, {})

func get_all_ids() -> Array:
	return _auras.keys()

func get_display_name(aura_id: String) -> String:
	return get_aura(aura_id).get("name", aura_id)

func is_unlocked(aura_id: String) -> bool:
	return aura_id in GameState.unlocked_auras

func is_researching(aura_id: String) -> bool:
	return GameState.active_aura_research.get("aura_id", "") == aura_id

func get_research_progress(aura_id: String) -> int:
	return int(GameState.aura_research_progress.get(aura_id, 0))

func get_research_time(aura_id: String) -> int:
	return int(get_aura(aura_id).get("research_time", 2))

func get_unlock_cost(aura_id: String) -> int:
	return int(get_aura(aura_id).get("unlock_cost", 100))

func start_research(aura_id: String) -> bool:
	if is_unlocked(aura_id): return false
	if is_researching(aura_id): return false
	if not GameState.active_aura_research.is_empty(): return false
	var cost : int = get_unlock_cost(aura_id)
	if GameState.soul < cost: return false
	GameState.soul -= cost
	GameState.active_aura_research = {"aura_id": aura_id}
	GameState.aura_research_progress[aura_id] = 0
	SaveManager.auto_save()
	return true

func advance_research():
	var aid : String = GameState.active_aura_research.get("aura_id", "")
	if aid == "": return
	var cur : int = get_research_progress(aid) + 1
	var need : int = get_research_time(aid)
	GameState.aura_research_progress[aid] = cur
	if cur >= need: _finish_research(aid)
	SaveManager.auto_save()

func accelerate_research() -> bool:
	var aid : String = GameState.active_aura_research.get("aura_id", "")
	if aid == "": return false
	if GameState.soul < ACCEL_COST: return false
	GameState.soul -= ACCEL_COST
	var cur : int = get_research_progress(aid) + 1
	var need : int = get_research_time(aid)
	GameState.aura_research_progress[aid] = cur
	if cur >= need: _finish_research(aid)
	SaveManager.auto_save()
	return true

func _finish_research(aura_id: String):
	if aura_id not in GameState.unlocked_auras:
		GameState.unlocked_auras.append(aura_id)
	GameState.active_aura_research = {}

## 战场内点击使用光环：立即生效，然后从被动槽中移除（用完即毁）
func use_aura_in_battle(aura_id: String) -> bool:
	if aura_id == "" or not aura_id in GameState.get_auras_from_passives():
		return false

	var d : Dictionary = get_aura(aura_id)
	if d.is_empty():
		return false

	var params : Dictionary = d.get("params", {})
	var effect_type : String = d.get("effect", "")

	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u.unit_stats.team_id != 0 or u.hit_points <= 0:
			continue

		u.active_auras[aura_id] = true

		match effect_type:
			"attack_plus":
				u.buff_attack_percent += float(params.get("attack_percent", 0.15))
			"damage_reduce_and_counter":
				u.buff_damage_reduction += float(params.get("damage_reduction", 0.10))
				u.relic_counter_damage_bonus += float(params.get("counter_bonus", 0.30))
			"flat_reduction":
				u.buff_physical_reduction += float(params.get("physical_reduction", 0.10))
				u.buff_magic_reduction += float(params.get("magic_reduction", 0.10))
			"turn_start_gain_soul_fire", "kill_gain_soul_fire", "kill_heal_percent":
				# 这些由 TurnManager/CombatManager 根据 active_auras 钩子自动触发
				pass

	# 用完即毁：从被动槽中移除
	GameState.remove_aura_from_passives(aura_id)
	SaveManager.auto_save()

	print("[AuraManager] 光环已激活并消耗: " + aura_id)
	return true
