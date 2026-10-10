extends Node

# ============================================================
#  AuraManager — 光环系统（研究 + 激活）
#  - 局外：灰烬铁匠研究，需 2-3 局完成，可花魂加速
#  - 局内：熔炉节点花魂火购买，占用遗物槽
# ============================================================

var _auras : Dictionary = {}

# ★ 加速成本（从 economy_config.json 读）
var ACCEL_COST : int = 50


func _ready():
	load_auras()
	_load_config()


func load_auras():
	var path : String = Config.PATHS.AURA_DATA
	if not FileAccess.file_exists(path):
		push_error("光环数据不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_error("光环 JSON 解析失败")
		return
	_auras = data
	print("[AuraManager] 加载 %d 个光环" % _auras.size())


func _load_config():
	var cfg : Dictionary = GameConfigManager.get_file("economy_config.json")
	var aura_cfg : Dictionary = cfg.get("aura_research", {})
	ACCEL_COST = int(aura_cfg.get("accel_cost", 50))
	print("[AuraManager] 加速成本 = %d 魂" % ACCEL_COST)


# ============================================================
#  查询
# ============================================================
func get_aura(aura_id: String) -> Dictionary:
	return _auras.get(aura_id, {})


func get_all_ids() -> Array:
	return _auras.keys()


func get_display_name(aura_id: String) -> String:
	var d : Dictionary = get_aura(aura_id)
	return d.get("name", aura_id)


# ============================================================
#  研究系统
# ============================================================
func is_unlocked(aura_id: String) -> bool:
	return aura_id in GameState.unlocked_auras


func is_researching(aura_id: String) -> bool:
	return GameState.active_aura_research.get("aura_id", "") == aura_id


func get_research_progress(aura_id: String) -> int:
	return int(GameState.aura_research_progress.get(aura_id, 0))


func get_research_time(aura_id: String) -> int:
	var d : Dictionary = get_aura(aura_id)
	return int(d.get("research_time", 2))


func get_unlock_cost(aura_id: String) -> int:
	var d : Dictionary = get_aura(aura_id)
	return int(d.get("unlock_cost", 100))


## 开始研究（消耗解锁费 + 记录进行中）
func start_research(aura_id: String) -> bool:
	if is_unlocked(aura_id):
		return false
	if is_researching(aura_id):
		return false
	if not GameState.active_aura_research.is_empty():
		return false
	var cost : int = get_unlock_cost(aura_id)
	if GameState.soul < cost:
		return false
	GameState.soul -= cost
	GameState.active_aura_research = {"aura_id": aura_id}
	GameState.aura_research_progress[aura_id] = 0
	SaveManager.auto_save()
	print("[Aura] 开始研究：%s（花费 %d 魂）" % [aura_id, cost])
	return true


## 每局结束时推进（GameState.finish_cycle 调用）
func advance_research():
	var aid : String = GameState.active_aura_research.get("aura_id", "")
	if aid == "":
		return
	var cur : int = get_research_progress(aid) + 1
	var need : int = get_research_time(aid)
	GameState.aura_research_progress[aid] = cur
	print("[Aura] 研究进度：%s %d/%d" % [aid, cur, need])
	if cur >= need:
		_finish_research(aid)
	SaveManager.auto_save()


## 花魂加速 1 局
func accelerate_research() -> bool:
	var aid : String = GameState.active_aura_research.get("aura_id", "")
	if aid == "":
		return false
	if GameState.soul < ACCEL_COST:
		return false
	GameState.soul -= ACCEL_COST
	var cur : int = get_research_progress(aid) + 1
	var need : int = get_research_time(aid)
	GameState.aura_research_progress[aid] = cur
	print("[Aura] 加速研究：%s %d/%d（花费 %d 魂）" % [aid, cur, need, ACCEL_COST])
	if cur >= need:
		_finish_research(aid)
	SaveManager.auto_save()
	return true


func _finish_research(aura_id: String):
	if aura_id not in GameState.unlocked_auras:
		GameState.unlocked_auras.append(aura_id)
	GameState.active_aura_research = {}
	print("[Aura] 研究完成：%s" % aura_id)
