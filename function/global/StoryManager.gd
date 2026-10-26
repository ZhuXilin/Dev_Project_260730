extends Node

# ============================================================
#  StoryManager — 统一对话/事件触发
#  - trigger(type, context) 唯一入口
#  - npc_interact / forge_recall 计入 npc_interact_counts
#  - 所有 trigger 均计入 dialogue_play_counts
#  - 动态信息通过 {xxx} 占位符替换
#  - effect 应用结果存入 GameState
#  - v4.6：新增 NPC 头像缓存
# ============================================================

const AFFINITY_TIER_1 := 5
const AFFINITY_TIER_2 := 10
const AFFINITY_TIER_3 := 15

const INTERACT_TRIGGERS: Array = ["npc_interact", "forge_recall"]

var _npcs: Dictionary = {}
var _standalone: Dictionary = {}
var _dialogue_index: Dictionary = {}   # dialogue_id → {"dialogue": Dictionary, "npc_id": String}
var _npc_avatars: Dictionary = {}      # npc_id / 中文名 → avatar_id
var _npc_name_to_id: Dictionary = {}

func _ready() -> void:
	load_narrative()


func load_narrative() -> void:
	_npcs.clear()
	_standalone.clear()
	_dialogue_index.clear()
	_npc_avatars.clear()
	_npc_name_to_id.clear() # ★ 清理映射

	var path: String = Config.PATHS.NARRATIVE_DATA
	if not FileAccess.file_exists(path):
		push_error("[StoryManager] narrative.json 不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[StoryManager] 无法打开: " + path)
		return
	var text: String = f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		push_error("[StoryManager] narrative.json 解析失败")
		return

	_npcs = (data.get("npcs", {}) as Dictionary).duplicate(true)
	_standalone = (data.get("standalone", {}) as Dictionary).duplicate(true)
	
	# ★ 缓存 NPC 头像，并建立 中文名 -> npc_id 的映射
	for npc_id in _npcs:
		var npc_data: Dictionary = _npcs[npc_id]
		
		# 1. 建立名字到ID的映射
		var display_name := str(npc_data.get("name", ""))
		if display_name != "":
			_npc_name_to_id[display_name] = npc_id
			
		# 2. 缓存静态头像配置（支持通过 NPC ID 或中文名直接查）
		var avatar_id := str(npc_data.get("avatar", ""))
		if avatar_id != "":
			_npc_avatars[npc_id] = avatar_id
			if display_name != "":
				_npc_avatars[display_name] = avatar_id

	_rebuild_index()
	print("[StoryManager] 已加载 %d NPC / %d 独立对话 / 索引 %d 条" % [
		_npcs.size(), _standalone.size(), _dialogue_index.size()])


func _rebuild_index() -> void:
	for npc_id in _npcs:
		var npc: Dictionary = _npcs[npc_id]
		var default_t: String = str(npc.get("default_trigger_type", "npc_interact"))
		for d in npc.get("dialogues", []):
			if not (d is Dictionary):
				continue
			var did: String = str((d as Dictionary).get("id", ""))
			if did == "":
				continue
			if not (d as Dictionary).has("trigger_type"):
				(d as Dictionary)["trigger_type"] = default_t
			_dialogue_index[did] = {"dialogue": d, "npc_id": npc_id}
	for did in _standalone:
		_dialogue_index[did] = {"dialogue": {"id": did, "lines": _standalone[did]}, "npc_id": ""}


# ============================================================
#  核心接口
# ============================================================
func trigger(trigger_type: String, context: Dictionary = {}) -> bool:
	var candidates: Array = get_available_dialogues(trigger_type, context)
	if candidates.is_empty():
		return false
	var picked: Dictionary = candidates[0]
	_play_picked(picked, trigger_type, context)
	return true


func play_dialogue_by_id(dialogue_id: String) -> bool:
	if dialogue_id == "":
		return false
	if not _dialogue_index.has(dialogue_id):
		push_warning("[StoryManager] 未知对话 id: " + dialogue_id)
		return false
	var entry: Dictionary = _dialogue_index[dialogue_id]
	var d: Dictionary = entry["dialogue"]
	var lines: Array = d.get("lines", [])
	if lines.is_empty():
		return false
	var choices: Array = d.get("choices", [])
	if choices.is_empty():
		DialogueManager.start_inline_dialogue(lines)
	else:
		DialogueManager.start_inline_dialogue_with_choices(lines, choices)
	return true


func get_available_dialogues(trigger_type: String, context: Dictionary) -> Array:
	var result: Array = []
	for npc_id in _npcs:
		var npc: Dictionary = _npcs[npc_id]
		for d in npc.get("dialogues", []):
			if not (d is Dictionary):
				continue
			var dd: Dictionary = d
			var t: String = str(dd.get("trigger_type", "npc_interact"))
			if t != trigger_type:
				continue
			if not ConditionHelper.check(dd.get("condition", {}), context, npc_id):
				continue
			if not _is_playable(dd):
				continue
			result.append({"dialogue": dd, "npc_id": npc_id})
	result.sort_custom(func(a, b):
		return int((a.dialogue as Dictionary).get("priority", 0)) \
			> int((b.dialogue as Dictionary).get("priority", 0))
	)
	return result


func get_npc_interact_count(npc_id: String) -> int:
	return int(GameState.npc_interact_counts.get(npc_id, 0))


func get_npc_avatar_id(speaker_or_npc_id: String) -> String:
	# 1. 将中文名统一解析为 npc_id
	var target_id := speaker_or_npc_id
	if _npc_name_to_id.has(speaker_or_npc_id):
		target_id = _npc_name_to_id[speaker_or_npc_id]
		
	# 2. 优先读取事件覆盖的头像
	if GameState.unlocked_npc_avatars.has(target_id):
		return str(GameState.unlocked_npc_avatars[target_id])
		
	# 3. 兜底读取静态配置
	return _npc_avatars.get(speaker_or_npc_id, "")


# ============================================================
#  内部
# ============================================================
func _is_playable(d: Dictionary) -> bool:
	if bool(d.get("repeatable", false)):
		return true
	var did: String = str(d.get("id", ""))
	var play_count: int = int(GameState.dialogue_play_counts.get(did, 0))
	var max_count: int = int((d.get("condition", {}) as Dictionary).get("max_dialogue_play_count", 1))
	return play_count < max_count


func _play_picked(picked: Dictionary, trigger_type: String, context: Dictionary) -> void:
	var d: Dictionary = picked["dialogue"]
	var npc_id: String = str(picked["npc_id"])

	var lines: Array = _resolve_placeholders(d.get("lines", []), context)
	var choices: Array = _resolve_placeholders(d.get("choices", []), context)

	if lines.is_empty():
		return
	if choices.is_empty():
		DialogueManager.start_inline_dialogue(lines)
	else:
		DialogueManager.start_inline_dialogue_with_choices(lines, choices)

	_record_play(d, npc_id, trigger_type)
	_apply_effect(d.get("effect", {}))


func _resolve_placeholders(data: Array, context: Dictionary) -> Array:
	if data.is_empty() or context.is_empty():
		return data
	var out: Array = []
	for item in data:
		if item is Dictionary:
			var copy: Dictionary = (item as Dictionary).duplicate(true)
			for key in ["text", "speaker"]:
				if copy.has(key) and copy[key] is String:
					copy[key] = _replace_in_text(copy[key], context)
			out.append(copy)
		else:
			out.append(item)
	return out


func _replace_in_text(text: String, context: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var result: String = text
	for key in context:
		var token: String = "{" + str(key) + "}"
		if result.contains(token):
			result = result.replace(token, str(context[key]))
	return result


func _record_play(d: Dictionary, npc_id: String, trigger_type: String) -> void:
	var did: String = str(d.get("id", ""))
	if did != "":
		var pc: Dictionary = GameState.dialogue_play_counts
		pc[did] = int(pc.get(did, 0)) + 1

	if trigger_type in INTERACT_TRIGGERS and npc_id != "":
		var nc: Dictionary = GameState.npc_interact_counts
		nc[npc_id] = int(nc.get(npc_id, 0)) + 1

	if npc_id != "":
		if not GameState.npc_dialogue_seen.has(npc_id):
			GameState.npc_dialogue_seen[npc_id] = []
		if did != "":
			var seen: Array = GameState.npc_dialogue_seen[npc_id]
			if not (did in seen):
				seen.append(did)
				
	# ★ v4.6：记录亲密度（暂缓实装，但保留接口扩展位）

	SaveManager.auto_save()


func _apply_effect(effect: Dictionary) -> void:
	if effect.is_empty():
		return
	var t: String = str(effect.get("type", ""))
	var params: Dictionary = effect.get("params", {})
	match t:
		"shop_tag_weight_boost":
			GameState.active_narrative_effects.append({
				"type": t,
				"tag": str(params.get("tag", "")),
				"amount": int(params.get("amount", 0)),
			})
		"reveal_boss_intel":
			var txt: String = str(params.get("text", ""))
			if txt != "" and not (txt in GameState.revealed_intel):
				GameState.revealed_intel.append(txt)
		"fusion_hint":
			var h: String = str(params.get("hint", ""))
			if h != "" and not (h in GameState.fusion_hints):
				GameState.fusion_hints.append(h)
		"grant_flag":
			var flag: String = str(params.get("flag", ""))
			if flag != "" and not (flag in GameState.npc_dialogue_flags):
				GameState.npc_dialogue_flags.append(flag)
		"unlock_relic":
			var rid: String = str(params.get("relic_id", ""))
			if rid != "":
				RelicManager.unlock_relic(rid)
		"unlock_route":
			var route_id: String = str(params.get("route_id", ""))
			if route_id != "":
				DispatchManager.unlock_route(route_id)
		_:
			pass


# ============================================================
#  兼容接口
# ============================================================
func play_next_dialogue(npc_id: String) -> bool:
	var ctx: Dictionary = {
		"npc_id": npc_id,
		"current_day": GameState.current_day,
		"total_run_count": GameState.total_run_count,
		"npc_interact_count": get_npc_interact_count(npc_id),
	}
	return trigger("npc_interact", ctx)


func check_and_apply_unlocks(npc_id: String) -> Array:
	var result: Array = []
	if not _npcs.has(npc_id):
		return result
	var npc: Dictionary = _npcs[npc_id]
	for u in npc.get("unlocks", []):
		if not (u is Dictionary):
			continue
		var ud: Dictionary = u
		var uid: String = str(ud.get("id", ""))
		if uid == "":
			continue
		if _is_unlock_done(npc_id, uid):
			continue
		if not _check_unlock_conditions(npc_id, ud.get("conditions", {})):
			continue
		if _apply_unlock(npc_id, ud):
			result.append(ud)
	return result


func has_dialogue(dialogue_id: String) -> bool:
	return _dialogue_index.has(dialogue_id)


func _is_unlock_done(npc_id: String, unlock_id: String) -> bool:
	var flag: String = "unlocked_%s_%s" % [npc_id, unlock_id]
	return flag in GameState.npc_dialogue_flags


func _check_unlock_conditions(npc_id: String, cond: Dictionary) -> bool:
	if cond.is_empty():
		return true
	if cond.has("after_dialogue"):
		var seen: Array = GameState.npc_dialogue_seen.get(npc_id, [])
		if not (str(cond["after_dialogue"]) in seen):
			return false
	if cond.has("min_dialogue_count"):
		var seen_count: int = (GameState.npc_dialogue_seen.get(npc_id, []) as Array).size()
		if seen_count < int(cond["min_dialogue_count"]):
			return false
	return ConditionHelper.check(cond, {}, npc_id)


func _apply_unlock(npc_id: String, u: Dictionary) -> bool:
	var utype: String = str(u.get("type", ""))
	var uid: String = str(u.get("id", ""))
	if utype == "" or uid == "":
		return false
	match utype:
		"unit":
			Globals.make_unit_eligible(uid)
		"relic":
			RelicManager.unlock_relic(uid)
		"aura":
			if uid not in GameState.unlocked_auras:
				GameState.unlocked_auras.append(uid)
		"route":
			DispatchManager.unlock_route(uid)
		"talent":
			Globals.unlock_talent(uid)
		"transform_branch":
			pass
		_:
			return false
	var flag: String = "unlocked_%s_%s" % [npc_id, uid]
	if not (flag in GameState.npc_dialogue_flags):
		GameState.npc_dialogue_flags.append(flag)
	SaveManager.auto_save()
	return true


func record_choice(_npc_id: String, flag: String) -> void:
	if flag == "":
		return
	if not (flag in GameState.npc_dialogue_flags):
		GameState.npc_dialogue_flags.append(flag)


func has_flag(flag: String) -> bool:
	return flag in GameState.npc_dialogue_flags


func get_affinity(npc_id: String) -> int:
	return int(GameState.npc_affinity.get(npc_id, 0))
