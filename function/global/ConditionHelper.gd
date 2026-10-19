class_name ConditionHelper
extends RefCounted

# ============================================================
#  ConditionHelper — 统一 condition 检查
#  支持两类来源：
#    1) context（trigger 时传入，如 node_type / is_boss / shop_tag_hint）
#    2) 全局状态（GameState 中的持久字段）
#  约定：
#    - npc_id 用于查 npc_interact_counts / npc_dialogue_seen
#    - 空 npc_id 时跳过 npc 相关检查（standalone 对话）
# ============================================================

## 检查一个 condition Dictionary 是否满足。
## cond 为空 → true。
## context 里的字段优先级：context[key] > GameState 对应字段。
static func check(cond: Dictionary, context: Dictionary, npc_id: String = "") -> bool:
	if cond.is_empty():
		return true

	# ---- 通用数值检查 ----
	if not _check_num(cond, "min_run_count", ">=", _read_num(context, "total_run_count", GameState.total_run_count)):
		return false
	if not _check_num(cond, "min_dispatch_count", ">=", GameState.total_dispatch_count):
		return false
	if not _check_num(cond, "min_arena_clear", ">=", GameState.arena_clear_count):
		return false
	if not _check_num(cond, "min_altar_level", ">=", SoulFireManager.altar_level):
		return false
	if not _check_num(cond, "min_initial_level", ">=", GameState.soul_fire_initial_level):
		return false
	if not _check_num(cond, "min_weapon_max_level", ">=", _get_max_weapon_level()):
		return false
	if not _check_num(cond, "min_dialogue_count", ">=", _get_seen_count(npc_id)):
		return false
	if not _check_num(cond, "tutorial_stage_gte", ">=", GameState.tutorial_stage):
		return false
	if not _check_num(cond, "tutorial_stage_lt", "<", GameState.tutorial_stage):
		return false

	# ---- NPC 交互次数 ----
	if npc_id != "":
		var interact_count: int = int(GameState.npc_interact_counts.get(npc_id, 0))
		if not _check_num(cond, "min_npc_interact_count", ">=", interact_count):
			return false
		if not _check_num(cond, "max_npc_interact_count", "<=", interact_count):
			return false

	# ---- 单条对话播放次数（由 StoryManager 传入 dialogue_id）----
	# 该检查在 StoryManager._is_playable() 里做，这里不重复

	# ---- 地图上下文（battle_start / map_enter 等触发时传入）----
	if not _check_context(cond, context, "node_type", "eq"):
		return false
	if not _check_context_bool(cond, context, "is_boss"):
		return false
	if not _check_context_bool(cond, context, "is_elite"):
		return false
	if not _check_context_bool(cond, context, "is_start"):
		return false
	if not _check_context(cond, context, "current_day", "eq"):
		return false
	if not _check_context_str(cond, context, "map_name"):
		return false

	# ---- 队伍标签 ----
	if cond.has("team_has_tag"):
		var want_tag: String = str(cond["team_has_tag"])
		var tags: Array = context.get("team_tags", _collect_team_tags())
		if not (want_tag in tags):
			return false
	if cond.has("team_has_no_tag"):
		var no_tag: String = str(cond["team_has_no_tag"])
		var tags2: Array = context.get("team_tags", _collect_team_tags())
		if no_tag in tags2:
			return false

	# ---- 必须先看过某条对话 ----
	if cond.has("after_dialogue"):
		var ad: String = str(cond["after_dialogue"])
		if not _has_seen_dialogue(npc_id, ad):
			return false

	# ---- flags ----
	if cond.has("flags"):
		var flags: Variant = cond["flags"]
		if flags is Array:
			for f in flags:
				if not (str(f) in GameState.npc_dialogue_flags):
					return false

	# ---- 队伍标签计数（用于 forge 低语 whisper_keeper_ember_fusion）----
	if cond.has("min_tag_count"):
		var tc: Variant = cond["min_tag_count"]
		if tc is Dictionary:
			var tag: String = str((tc as Dictionary).get("tag", ""))
			var need: int = int((tc as Dictionary).get("count", 0))
			var have: int = 0
			for ud in GameState.party:
				if ud.is_dead:
					continue
				if tag in ud.tags:
					have += 1
			if have < need:
				return false

	return true


static func _check_num(cond: Dictionary, key: String, op: String, actual: int) -> bool:
	if not cond.has(key):
		return true
	var target: int = int(cond[key])
	match op:
		">=": return actual >= target
		"<=": return actual <= target
		"<":  return actual < target
		">":  return actual > target
		"==": return actual == target
	return true


static func _check_context(cond: Dictionary, context: Dictionary, key: String, op: String) -> bool:
	if not cond.has(key):
		return true
	if not context.has(key):
		# 触发场景没有这个字段 → 视为不匹配（地图条件对话不会被普通触发命中）
		return false
	var target: int = int(cond[key])
	var actual: int = int(context[key])
	return actual == target if op == "eq" else true


static func _check_context_bool(cond: Dictionary, context: Dictionary, key: String) -> bool:
	if not cond.has(key):
		return true
	return bool(context.get(key, false)) == bool(cond[key])


static func _check_context_str(cond: Dictionary, context: Dictionary, key: String) -> bool:
	if not cond.has(key):
		return true
	return str(context.get(key, "")) == str(cond[key])


static func _read_num(context: Dictionary, key: String, fallback: int) -> int:
	return int(context.get(key, fallback))


static func _collect_team_tags() -> Array:
	var tags: Array = []
	for ud in GameState.party:
		if ud.is_dead:
			continue
		for t in ud.tags:
			if not (t in tags):
				tags.append(t)
	return tags


static func _get_seen_count(npc_id: String) -> int:
	if npc_id == "":
		return 0
	return (GameState.npc_dialogue_seen.get(npc_id, []) as Array).size()


static func _has_seen_dialogue(npc_id: String, dialogue_id: String) -> bool:
	if npc_id == "":
		return false
	var seen: Array = GameState.npc_dialogue_seen.get(npc_id, [])
	return dialogue_id in seen


static func _get_max_weapon_level() -> int:
	var max_lv: int = 0
	for unit_key in GameState.unit_growth:
		var d: Dictionary = GameState.unit_growth[unit_key]
		for k in d:
			if k.begins_with("weapon_lv_"):
				max_lv = maxi(max_lv, int(d[k]))
	return max_lv
