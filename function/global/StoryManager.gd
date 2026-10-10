extends Node

# ============================================================
#  StoryManager — NPC 对话与剧情解锁 + 亲密度
# ============================================================

var _stories : Dictionary = {}

const AFFINITY_TIER_1 : int = 5
const AFFINITY_TIER_2 : int = 10
const AFFINITY_TIER_3 : int = 15


func _ready():
	load_stories()


func load_stories():
	var path = Config.PATHS.STORY_DATA
	if not FileAccess.file_exists(path):
		push_error("故事数据文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("故事 JSON 解析失败")
		return
	_stories = data
	print("成功加载 ", _stories.size(), " 个 NPC 剧情")


func get_npc(npc_id: String) -> Dictionary:
	return _stories.get(npc_id, {})


# ============================================================
#  对话池
# ============================================================
func get_next_dialogue(npc_id: String) -> Dictionary:
	var npc : Dictionary = get_npc(npc_id)
	if npc.is_empty(): return {}
	var dialogues : Array = npc.get("dialogues", [])
	var candidates : Array = []
	for d in dialogues:
		if not (d is Dictionary): continue
		var did : String = d.get("id", "")
		if did == "" or _is_seen(npc_id, did): continue
		if not _check_conditions(d.get("condition", {})): continue
		candidates.append(d)
	if candidates.is_empty(): return {}
	candidates.sort_custom(func(a, b):
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	return candidates[0]


func play_next_dialogue(npc_id: String) -> bool:
	var d : Dictionary = get_next_dialogue(npc_id)
	if d.is_empty(): return false
	var did : String = d.get("id", "")
	mark_seen(npc_id, did)

	var lines : Array = d.get("lines", [])
	if lines.is_empty(): return false
	var choices : Array = d.get("choices", [])
	if choices.is_empty():
		DialogueManager.start_inline_dialogue(lines)
	else:
		DialogueManager.start_inline_dialogue_with_choices(lines, choices)
	return true


func mark_seen(npc_id: String, dialogue_id: String) -> void:
	if not GameState.npc_dialogue_seen.has(npc_id):
		GameState.npc_dialogue_seen[npc_id] = []
	var arr : Array = GameState.npc_dialogue_seen[npc_id]
	if dialogue_id not in arr:
		arr.append(dialogue_id)
		# ★ 方向 6：亲密度 +1
		var cur : int = int(GameState.npc_affinity.get(npc_id, 0))
		GameState.npc_affinity[npc_id] = cur + 1
		print("[NPC] %s 亲密度 %d → %d" % [npc_id, cur, cur + 1])
		_check_affinity_milestone(npc_id, cur, cur + 1)
		SaveManager.auto_save()


func record_choice(_npc_id: String, flag: String) -> void:
	if flag == "": return
	if flag not in GameState.npc_dialogue_flags:
		GameState.npc_dialogue_flags.append(flag)


func has_flag(flag: String) -> bool:
	return flag in GameState.npc_dialogue_flags


# ============================================================
#  亲密度查询
# ============================================================
func get_affinity(npc_id: String) -> int:
	return int(GameState.npc_affinity.get(npc_id, 0))


func get_affinity_tier(npc_id: String) -> int:
	var a : int = get_affinity(npc_id)
	if a >= AFFINITY_TIER_3: return 3
	if a >= AFFINITY_TIER_2: return 2
	if a >= AFFINITY_TIER_1: return 1
	return 0


func _check_affinity_milestone(npc_id: String, old_v: int, new_v: int):
	# 触达 5 / 10 / 15 时打印
	var milestones : Array = [AFFINITY_TIER_1, AFFINITY_TIER_2, AFFINITY_TIER_3]
	for m in milestones:
		if old_v < m and new_v >= m:
			print("[NPC] %s 亲密度达到 %d，解锁新效果" % [npc_id, m])


# ============================================================
#  解锁
# ============================================================
func check_and_apply_unlocks(npc_id: String) -> Array:
	var npc : Dictionary = get_npc(npc_id)
	if npc.is_empty(): return []
	var unlocks : Array = npc.get("unlocks", [])
	var newly : Array = []
	for u in unlocks:
		if not (u is Dictionary): continue
		if _is_unlock_done(npc_id, u.get("id", "")): continue
		if not _check_unlock_conditions(npc_id, u.get("conditions", {})): continue
		if _apply_unlock(npc_id, u):
			newly.append(u)
	return newly


# ============================================================
#  内部
# ============================================================
func _is_seen(npc_id: String, dialogue_id: String) -> bool:
	if not GameState.npc_dialogue_seen.has(npc_id): return false
	return dialogue_id in GameState.npc_dialogue_seen[npc_id]


func _get_seen_count(npc_id: String) -> int:
	if not GameState.npc_dialogue_seen.has(npc_id): return 0
	return (GameState.npc_dialogue_seen[npc_id] as Array).size()


func _check_conditions(cond: Dictionary) -> bool:
	if cond.is_empty(): return true
	if cond.has("min_run_count") and GameState.total_run_count < int(cond["min_run_count"]): return false
	if cond.has("min_altar_level") and SoulFireManager.altar_level < int(cond["min_altar_level"]): return false
	if cond.has("min_initial_level") and GameState.soul_fire_initial_level < int(cond["min_initial_level"]): return false
	if cond.has("min_weapon_max_level"):
		if _get_max_weapon_level() < int(cond["min_weapon_max_level"]): return false
	if cond.has("min_arena_clear") and GameState.arena_clear_count < int(cond["min_arena_clear"]): return false
	if cond.has("min_dispatch_count") and GameState.total_dispatch_count < int(cond["min_dispatch_count"]): return false
	if cond.has("flags"):
		for f in cond["flags"]:
			if not has_flag(f): return false
	return true


func _get_max_weapon_level() -> int:
	var max_lv : int = 0
	for unit_key in GameState.unit_growth:
		var d : Dictionary = GameState.unit_growth[unit_key]
		for k in d:
			if k.begins_with("weapon_lv_"):
				max_lv = maxi(max_lv, int(d[k]))
	return max_lv


func _check_unlock_conditions(npc_id: String, cond: Dictionary) -> bool:
	if cond.is_empty(): return true
	if cond.has("min_altar_level") and SoulFireManager.altar_level < int(cond["min_altar_level"]): return false
	if cond.has("min_initial_level") and GameState.soul_fire_initial_level < int(cond["min_initial_level"]): return false
	if cond.has("min_weapon_max_level"):
		if _get_max_weapon_level() < int(cond["min_weapon_max_level"]): return false
	if cond.has("min_dispatch_count") and GameState.total_dispatch_count < int(cond["min_dispatch_count"]): return false
	if cond.has("min_arena_clear") and GameState.arena_clear_count < int(cond["min_arena_clear"]): return false
	if cond.has("min_run_count") and GameState.total_run_count < int(cond["min_run_count"]): return false
	if cond.has("min_dialogue_count"):
		if _get_seen_count(npc_id) < int(cond["min_dialogue_count"]): return false
	if cond.has("flags"):
		for f in cond["flags"]:
			if not has_flag(f): return false
	return true


func _is_unlock_done(npc_id: String, unlock_id: String) -> bool:
	if unlock_id == "": return false
	var key : String = "%s_%s" % [npc_id, unlock_id]
	return has_flag("unlocked_" + key)


func _apply_unlock(npc_id: String, u: Dictionary) -> bool:
	var utype : String = u.get("type", "")
	var uid : String = u.get("id", "")
	if uid == "" or utype == "":
		return false
	match utype:
		"unit":
			Globals.unlock_unit(uid)
		"relic":
			RelicManager.unlock_relic(uid)
		"aura":
			pass
		"transform_branch":
			pass
		_:
			push_warning("[StoryManager] 未知解锁类型: " + utype)
			return false

	record_choice(npc_id, "unlocked_" + npc_id + "_" + uid)
	SaveManager.auto_save()
	print("[Story] %s 解锁：%s (%s)" % [npc_id, uid, utype])
	return true
