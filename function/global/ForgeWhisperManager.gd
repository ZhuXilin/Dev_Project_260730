extends Node

# ============================================================
#  ForgeWhisperManager — FORGE 低语（v4.5）
#  - 每局首次进 FORGE 抽 1 条
#  - 可跳过、可手动重看
#  - effect：shop_tag_weight_boost / reveal_boss_intel / fusion_hint
#            / grant_flag / unlock_relic / unlock_route / none
#  - condition 支持：min_run_count / min_altar_level / min_initial_level
#    / min_weapon_max_level / min_dispatch_count / min_arena_clear
#    / flags / min_tag_count
#  - v4.5：状态持久化 + 汇总展示
# ============================================================

var _whispers : Dictionary = {}
var _current : Dictionary = {}
var _shown_this_run : bool = false
var _active_effects : Array = []
var _revealed_intel : Array = []
var _fusion_hints : Array = []


func _ready():
	load_whispers()


func load_whispers():
	var path : String = Config.PATHS.FORGE_WHISPER_DATA
	if not FileAccess.file_exists(path):
		push_warning("[ForgeWhisper] 数据不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		push_warning("[ForgeWhisper] 解析失败")
		return
	_whispers = data
	print("[ForgeWhisper] 加载 %d 条低语" % _whispers.size())


# ============================================================
#  局生命周期
# ============================================================
func reset_for_new_run():
	_current = {}
	_shown_this_run = false
	_active_effects.clear()
	_revealed_intel.clear()
	_fusion_hints.clear()


func should_show_this_run() -> bool:
	return not _shown_this_run


# ============================================================
#  抽取
# ============================================================
func pick_for_current_run() -> Dictionary:
	if _current.is_empty():
		_current = _pick_by_condition()
		_shown_this_run = true
		if not _current.is_empty():
			_apply_effect(_current)
	return _current.duplicate(true)


func get_current_whisper() -> Dictionary:
	return _current.duplicate(true)


# ============================================================
#  查询
# ============================================================
func get_active_effects() -> Array:
	return _active_effects.duplicate()


func get_revealed_intel() -> Array:
	return _revealed_intel.duplicate()


func get_fusion_hints() -> Array:
	return _fusion_hints.duplicate()


func add_revealed_intel(text : String) -> void:
	if text == "":
		return
	if not (text in _revealed_intel):
		_revealed_intel.append(text)


func get_shop_tag_boost(tag : String) -> int:
	var total : int = 0
	for e in _active_effects:
		if e.get("type", "") != "shop_tag_weight_boost":
			continue
		if e.get("tag", "") == tag:
			total += int(e.get("amount", 0))
	return total


# ============================================================
#  状态序列化（存档用）
# ============================================================
func export_state() -> Dictionary:
	return {
		"current": _current.duplicate(true),
		"shown_this_run": _shown_this_run,
		"active_effects": _active_effects.duplicate(true),
		"revealed_intel": _revealed_intel.duplicate(),
		"fusion_hints": _fusion_hints.duplicate(),
	}


func import_state(d : Dictionary) -> void:
	if d.is_empty():
		return
	_current = d.get("current", {})
	if _current is Dictionary:
		_current = _current.duplicate(true)
	else:
		_current = {}
	_shown_this_run = bool(d.get("shown_this_run", false))
	_active_effects = d.get("active_effects", [])
	if _active_effects is Array:
		_active_effects = _active_effects.duplicate(true)
	else:
		_active_effects = []
	_revealed_intel = d.get("revealed_intel", [])
	if _revealed_intel is Array:
		_revealed_intel = _revealed_intel.duplicate()
	else:
		_revealed_intel = []
	_fusion_hints = d.get("fusion_hints", [])
	if _fusion_hints is Array:
		_fusion_hints = _fusion_hints.duplicate()
	else:
		_fusion_hints = []


# ============================================================
#  内部
# ============================================================
func _pick_by_condition() -> Dictionary:
	var candidates : Array = []
	for wid in _whispers:
		var d : Dictionary = _whispers[wid]
		var cond : Dictionary = d.get("condition", {})
		if not _check_condition(cond):
			continue
		candidates.append(d)
	if candidates.is_empty():
		return {}

	candidates.sort_custom(func(a, b):
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)

	var top_priority : int = int(candidates[0].get("priority", 0))
	var top_pool : Array = []
	for c in candidates:
		if int(c.get("priority", 0)) == top_priority:
			top_pool.append(c)

	if top_pool.is_empty():
		return {}
	return top_pool[randi() % top_pool.size()].duplicate(true)


func _check_condition(cond : Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("min_run_count") and GameState.total_run_count < int(cond["min_run_count"]):
		return false
	if cond.has("min_altar_level") and SoulFireManager.altar_level < int(cond["min_altar_level"]):
		return false
	if cond.has("min_initial_level") and GameState.soul_fire_initial_level < int(cond["min_initial_level"]):
		return false
	if cond.has("min_weapon_max_level"):
		var max_lv : int = _get_max_weapon_level()
		if max_lv < int(cond["min_weapon_max_level"]):
			return false
	if cond.has("min_dispatch_count") and GameState.total_dispatch_count < int(cond["min_dispatch_count"]):
		return false
	if cond.has("min_arena_clear") and GameState.arena_clear_count < int(cond["min_arena_clear"]):
		return false
	if cond.has("flags"):
		for flag in cond["flags"]:
			if not (flag in GameState.npc_dialogue_flags):
				return false
	# v4.5 新增：队伍标签计数条件
	# 格式：{"tag": "余烬", "count": 2}
	if cond.has("min_tag_count"):
		var tc : Variant = cond["min_tag_count"]
		if tc is Dictionary:
			var tag : String = str((tc as Dictionary).get("tag", ""))
			var need : int = int((tc as Dictionary).get("count", 0))
			var have : int = 0
			for ud in GameState.party:
				if ud.is_dead:
					continue
				if tag in ud.tags:
					have += 1
			if have < need:
				return false
	return true


func _get_max_weapon_level() -> int:
	var max_lv : int = 0
	for unit_key in GameState.unit_growth:
		var d : Dictionary = GameState.unit_growth[unit_key]
		for k in d:
			if k.begins_with("weapon_lv_"):
				max_lv = maxi(max_lv, int(d[k]))
	return max_lv


func _apply_effect(whisper : Dictionary):
	var effect : Dictionary = whisper.get("effect", {})
	if effect.is_empty():
		return
	var t : String = effect.get("type", "none")
	var params : Dictionary = effect.get("params", {})
	match t:
		"shop_tag_weight_boost":
			_active_effects.append({
				"type": "shop_tag_weight_boost",
				"tag": str(params.get("tag", "")),
				"amount": int(params.get("amount", 0)),
				"source": str(whisper.get("id", "")),
			})
		"reveal_boss_intel":
			var txt : String = str(params.get("text", ""))
			if txt != "" and not (txt in _revealed_intel):
				_revealed_intel.append(txt)
		"fusion_hint":
			var h : String = str(params.get("hint", ""))
			if h != "" and not (h in _fusion_hints):
				_fusion_hints.append(h)
		# v4.5 新增：低语可给 flag / 解锁内容
		"grant_flag":
			var flag : String = str(params.get("flag", ""))
			if flag != "" and not (flag in GameState.npc_dialogue_flags):
				GameState.npc_dialogue_flags.append(flag)
				print("[ForgeWhisper] 授予 flag：%s" % flag)
		"unlock_relic":
			var rid : String = str(params.get("relic_id", ""))
			if rid != "":
				RelicManager.unlock_relic(rid)
				print("[ForgeWhisper] 解锁遗物：%s" % rid)
		"unlock_route":
			var route_id : String = str(params.get("route_id", ""))
			if route_id != "":
				DispatchManager.unlock_route(route_id)
				print("[ForgeWhisper] 解锁派遣路线：%s" % route_id)
		_:
			pass
