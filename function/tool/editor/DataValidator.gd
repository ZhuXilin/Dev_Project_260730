class_name DataValidator
extends RefCounted

# ============================================================
#  DataValidator — 跨表数据一致性校验
#  独立运行：从磁盘读所有 JSON，检查引用完整性
# ============================================================

const UNIT_DATA_PATH : String = "res://content/data/unit_data.json"
const ITEM_DATA_PATH : String = "res://content/data/item_data.json"
const TALENT_DATA_PATH : String = "res://content/data/talents.json"
const RELIC_DATA_PATH : String = "res://content/data/relic_data.json"
const AFFIX_DATA_PATH : String = "res://content/data/affixes.json"
const SET_BONUS_PATH : String = "res://content/data/set_bonuses.json"
const AURA_DATA_PATH : String = "res://content/data/auras.json"
const RECIPE_PATH : String = "res://content/data/recipes.json"
const STORY_PATH : String = "res://content/data/stories.json"
const EVENT_PATH : String = "res://content/data/events.json"
const DIALOGUE_PATH : String = "res://content/data/dialogues.json"

const VALID_TAGS : Array = ["烈焰", "轮回", "灰烬", "守护", "献祭", "余烬"]
const VALID_CORE_TRAITS : Array = ["charge", "dragon_might", "bulwark"]
const VALID_CAP_ATTRS : Array = ["vitality", "strength", "dexterity", "intelligence", "faith", "arcane"]
const VALID_AFFIX_TYPES : Array = [
	"attack_flat", "defense_flat", "hp_flat", "crit_chance", "crit_damage",
	"dodge", "lifesteal", "counter", "soul_fire_gain", "heal_boost",
	"flame_damage", "move_flat", "turn_regen", "start_shield"
]
const VALID_UNLOCK_TYPES : Array = ["unit", "relic", "aura", "route", "talent", "transform_branch"]
const VALID_ACTION_TYPES : Array = [
	"dialog", "give_item", "heal", "damage", "wait",
	"complete", "unlock_unit", "unlock_talent",
	"unlock_equipment", "unlock_relics"
]
const VALID_QUALITIES : Array = ["common", "rare", "epic", "legendary"]
const MAX_CAP_LEVEL : int = 3

enum Level { ERROR, WARN }

var _results : Array = []      # {level, file, path, message}

# ---- 缓存 ----
var _unit_db : Dictionary = {}
var _item_db : Dictionary = {}
var _talent_db : Dictionary = {}
var _relic_db : Dictionary = {}
var _affix_db : Dictionary = {}
var _set_bonus_db : Dictionary = {}
var _aura_db : Dictionary = {}
var _recipe_db : Dictionary = {}
var _story_db : Dictionary = {}
var _event_db : Dictionary = {}
var _dialogue_db : Dictionary = {}


# ============================================================
#  入口
# ============================================================
func validate_all() -> Array:
	_results.clear()
	_load_all()
	_validate_units()
	_validate_items()
	_validate_talents()
	_validate_relics()
	_validate_affixes()
	_validate_set_bonuses()
	_validate_auras()
	_validate_recipes()
	_validate_stories()
	_validate_events()
	return _results


func get_error_count() -> int:
	var n : int = 0
	for r in _results:
		if r["level"] == Level.ERROR: n += 1
	return n


func get_warn_count() -> int:
	var n : int = 0
	for r in _results:
		if r["level"] == Level.WARN: n += 1
	return n


# ============================================================
#  数据加载
# ============================================================
func _load_all():
	_unit_db = _load_json(UNIT_DATA_PATH)
	_item_db = _load_json(ITEM_DATA_PATH)
	_talent_db = _load_json(TALENT_DATA_PATH)
	_relic_db = _load_json(RELIC_DATA_PATH)
	_affix_db = _load_json(AFFIX_DATA_PATH)
	_set_bonus_db = _load_json(SET_BONUS_PATH)
	_aura_db = _load_json(AURA_DATA_PATH)
	_recipe_db = _load_json(RECIPE_PATH)
	_story_db = _load_json(STORY_PATH)
	_event_db = _load_json(EVENT_PATH)
	_dialogue_db = _load_json(DIALOGUE_PATH)


func _load_json(path : String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if not (data is Dictionary): return {}
	return data


# ============================================================
#  输出辅助
# ============================================================
func _error(file : String, path : String, message : String):
	_results.append({"level": Level.ERROR, "file": file, "path": path, "message": message})


func _warn(file : String, path : String, message : String):
	_results.append({"level": Level.WARN, "file": file, "path": path, "message": message})


# ============================================================
#  单位校验
# ============================================================
func _validate_units():
	var fname := "unit_data.json"
	for unit_key in _unit_db:
		var u : Dictionary = _unit_db[unit_key]
		if not (u is Dictionary): continue

		# default_weapon
		var dw : String = str(u.get("default_weapon", ""))
		if dw != "":
			if not _item_db.has(dw):
				_error(fname, "%s.default_weapon" % unit_key, "武器不存在: %s" % dw)
			elif _item_db[dw].get("type", "") != "weapon":
				_error(fname, "%s.default_weapon" % unit_key, "不是武器: %s" % dw)

		# default_armors
		var armors : Array = u.get("default_armors", [])
		for i in range(armors.size()):
			var aid : String = str(armors[i])
			if not _item_db.has(aid):
				_error(fname, "%s.default_armors[%d]" % [unit_key, i], "防具不存在: %s" % aid)
			elif _item_db[aid].get("type", "") != "armor":
				_error(fname, "%s.default_armors[%d]" % [unit_key, i], "不是防具: %s" % aid)

		# default_talents
		var talents : Array = u.get("default_talents", [])
		for i in range(talents.size()):
			var tid : String = str(talents[i])
			if not _talent_db.has(tid):
				_error(fname, "%s.default_talents[%d]" % [unit_key, i], "词条不存在: %s" % tid)

		# tags
		var tags : Array = u.get("tags", [])
		for i in range(tags.size()):
			var tag : String = str(tags[i])
			if tag not in VALID_TAGS:
				_warn(fname, "%s.tags[%d]" % [unit_key, i], "未知标签: %s" % tag)

		# core_trait
		var ct : String = str(u.get("core_trait", ""))
		if ct != "" and ct not in VALID_CORE_TRAITS:
			_warn(fname, "%s.core_trait" % unit_key, "未知核心特性: %s" % ct)

		# attr_cap_levels
		var cap : Variant = u.get("attr_cap_levels", [])
		if cap is Array:
			if (cap as Array).size() > MAX_CAP_LEVEL:
				_error(fname, "%s.attr_cap_levels" % unit_key,
					"级数超过 %d（当前 %d）" % [MAX_CAP_LEVEL, (cap as Array).size()])
			for lv_idx in range((cap as Array).size()):
				var lv_dict : Variant = (cap as Array)[lv_idx]
				if not (lv_dict is Dictionary): continue
				for k in (lv_dict as Dictionary):
					if k not in VALID_CAP_ATTRS:
						_warn(fname, "%s.attr_cap_levels[%d].%s" % [unit_key, lv_idx, k],
							"未知属性 key: %s" % k)

		# advanced_branches
		var branches : Array = u.get("advanced_branches", [])
		var seen_bid : Dictionary = {}
		for i in range(branches.size()):
			var b : Variant = branches[i]
			if not (b is Dictionary): continue
			var bid : String = str((b as Dictionary).get("id", ""))
			if bid == "":
				_error(fname, "%s.advanced_branches[%d].id" % [unit_key, i], "分支 id 为空")
			elif seen_bid.has(bid):
				_error(fname, "%s.advanced_branches[%d].id" % [unit_key, i], "分支 id 重复: %s" % bid)
			else:
				seen_bid[bid] = true

			var gt : String = str((b as Dictionary).get("granted_talent", ""))
			if gt != "" and not _talent_db.has(gt):
				_error(fname, "%s.advanced_branches[%d].granted_talent" % [unit_key, i],
					"特技不存在: %s" % gt)

			var sp : String = str((b as Dictionary).get("sprite_frames_path", ""))
			if sp != "" and not ResourceLoader.exists(sp):
				_warn(fname, "%s.advanced_branches[%d].sprite_frames_path" % [unit_key, i],
					"资源文件不存在: %s" % sp)

			var btags : Array = (b as Dictionary).get("tags", [])
			for j in range(btags.size()):
				var tag2 : String = str(btags[j])
				if tag2 not in VALID_TAGS:
					_warn(fname, "%s.advanced_branches[%d].tags[%d]" % [unit_key, i, j],
						"未知标签: %s" % tag2)


# ============================================================
#  装备校验
# ============================================================
func _validate_items():
	var fname := "item_data.json"
	for item_id in _item_db:
		var d : Variant = _item_db[item_id]
		if not (d is Dictionary): continue
		var dd : Dictionary = d

		# 品质
		var q : String = str(dd.get("quality", ""))
		if q != "" and q not in VALID_QUALITIES:
			_warn(fname, "%s.quality" % item_id, "未知品质: %s" % q)

		# 类型
		var t : String = str(dd.get("type", ""))
		if t != "" and t not in ["weapon", "armor", "relic"]:
			_warn(fname, "%s.type" % item_id, "未知类型: %s" % t)

		# fusion
		var fid : String = str(dd.get("fusion_id", ""))
		if fid != "":
			if not _item_db.has(fid):
				_error(fname, "%s.fusion_id" % item_id, "熔合产物不存在: %s" % fid)
			if str(dd.get("fusion_effect", "")) == "":
				_warn(fname, "%s.fusion_effect" % item_id, "有 fusion_id 但 fusion_effect 为空")

		# tags
		var tags : Array = dd.get("tags", [])
		for i in range(tags.size()):
			var tag : String = str(tags[i])
			if tag not in VALID_TAGS:
				_warn(fname, "%s.tags[%d]" % [item_id, i], "未知标签: %s" % tag)


# ============================================================
#  词条校验
# ============================================================
func _validate_talents():
	var fname := "talents.json"
	for tid in _talent_db:
		var t : Variant = _talent_db[tid]
		if not (t is Dictionary): continue
		var td : Dictionary = t

		# compatible_units
		var cu : Array = td.get("compatible_units", [])
		for i in range(cu.size()):
			var ukey : String = str(cu[i])
			if not _unit_db.has(ukey):
				_error(fname, "%s.compatible_units[%d]" % [tid, i], "单位不存在: %s" % ukey)

		# unlock_type
		var ut : String = str(td.get("unlock_type", "default"))
		if ut not in ["default", "soul", "story"]:
			_warn(fname, "%s.unlock_type" % tid, "未知解锁类型: %s" % ut)

		# 主动技能冷却
		if bool(td.get("is_active_skill", false)):
			if int(td.get("skill_cooldown", 0)) <= 0:
				_warn(fname, "%s.skill_cooldown" % tid, "主动技能冷却 ≤ 0")

		# soul 类型必须有 cost
		if ut == "soul" and int(td.get("soul_cost", 0)) <= 0:
			_warn(fname, "%s.soul_cost" % tid, "soul 类型词条 soul_cost ≤ 0")


# ============================================================
#  遗物校验
# ============================================================
const VALID_RELIC_EFFECTS : Array = [
	"first_attack_crit", "low_hp_damage_reduce", "kill_grants_extra_move",
	"first_spell_free", "turn_first_hit_regen", "strength_scale_damage",
	"counter_damage_bonus", "heal_bonus", "auto_revive_once"
]

func _validate_relics():
	var fname := "relic_data.json"
	for rid in _relic_db:
		var r : Variant = _relic_db[rid]
		if not (r is Dictionary): continue
		var rd : Dictionary = r
		var effects : Dictionary = rd.get("effects", {})
		for key in effects:
			if key not in VALID_RELIC_EFFECTS:
				_warn(fname, "%s.effects.%s" % [rid, key], "未知效果 key: %s" % key)


# ============================================================
#  词条池校验
# ============================================================
func _validate_affixes():
	var fname := "affixes.json"
	for aid in _affix_db:
		var a : Variant = _affix_db[aid]
		if not (a is Dictionary): continue
		var ad : Dictionary = a

		var t : String = str(ad.get("type", ""))
		if t != "" and t not in VALID_AFFIX_TYPES:
			_warn(fname, "%s.type" % aid, "未知词条类型: %s" % t)

		var q : String = str(ad.get("min_quality", ""))
		if q != "" and q not in VALID_QUALITIES:
			_warn(fname, "%s.min_quality" % aid, "未知品质: %s" % q)

		var tags : Array = ad.get("tags", [])
		for i in range(tags.size()):
			var tag : String = str(tags[i])
			if tag not in VALID_TAGS:
				_warn(fname, "%s.tags[%d]" % [aid, i], "未知标签: %s" % tag)

		var vmin : int = int(ad.get("value_min", 0))
		var vmax : int = int(ad.get("value_max", 0))
		if vmin > vmax:
			_error(fname, "%s" % aid, "value_min (%d) > value_max (%d)" % [vmin, vmax])


# ============================================================
#  套装校验
# ============================================================
func _validate_set_bonuses():
	var fname := "set_bonuses.json"
	for tag in _set_bonus_db:
		if tag == "cross_bonuses":
			var cb : Variant = _set_bonus_db[tag]
			if cb is Dictionary:
				for cid in (cb as Dictionary):
					var c : Variant = (cb as Dictionary)[cid]
					if not (c is Dictionary): continue
					var tags : Array = (c as Dictionary).get("tags", [])
					for i in range(tags.size()):
						var t2 : String = str(tags[i])
						if t2 not in VALID_TAGS:
							_warn(fname, "cross_bonuses.%s.tags[%d]" % [cid, i], "未知标签: %s" % t2)
		else:
			if tag not in VALID_TAGS:
				_warn(fname, tag, "未知标签: %s" % tag)


# ============================================================
#  光环校验
# ============================================================
func _validate_auras():
	var fname := "auras.json"
	for aid in _aura_db:
		var a : Variant = _aura_db[aid]
		if not (a is Dictionary): continue
		var ad : Dictionary = a
		var tag : String = str(ad.get("tag", ""))
		if tag != "" and tag not in VALID_TAGS:
			_warn(fname, "%s.tag" % aid, "未知标签: %s" % tag)


# ============================================================
#  配方校验
# ============================================================
func _validate_recipes():
	var fname := "recipes.json"
	for product_id in _recipe_db:
		# 产物存在？
		if not _item_db.has(product_id):
			_error(fname, product_id, "产物不存在: %s" % product_id)
			continue
		# 产物是防具？
		var pd : Variant = _item_db[product_id]
		if pd is Dictionary and (pd as Dictionary).get("type", "") != "armor":
			_warn(fname, product_id, "产物不是防具")

		# inputs
		var r : Variant = _recipe_db[product_id]
		if not (r is Dictionary): continue
		var inputs : Array = (r as Dictionary).get("inputs", [])
		if inputs.is_empty():
			_warn(fname, product_id, "配方没有输入")
		for i in range(inputs.size()):
			var iid : String = str(inputs[i])
			if not _item_db.has(iid):
				_error(fname, "%s.inputs[%d]" % [product_id, i], "输入不存在: %s" % iid)


# ============================================================
#  剧情校验
# ============================================================
func _validate_stories():
	var fname := "stories.json"
	for npc_id in _story_db:
		var npc : Variant = _story_db[npc_id]
		if not (npc is Dictionary): continue
		var nd : Dictionary = npc

		# 收集本 NPC 的所有对话 id
		var dlg_ids : Dictionary = {}
		var dialogues : Array = nd.get("dialogues", [])
		for i in range(dialogues.size()):
			var d : Variant = dialogues[i]
			if not (d is Dictionary): continue
			var did : String = str((d as Dictionary).get("id", ""))
			if did == "":
				_error(fname, "%s.dialogues[%d].id" % [npc_id, i], "对话 id 为空")
			elif dlg_ids.has(did):
				_error(fname, "%s.dialogues[%d].id" % [npc_id, i], "对话 id 重复: %s" % did)
			else:
				dlg_ids[did] = true

			# condition.after_dialogue 必须指向本 NPC 的对话
			var cond : Dictionary = (d as Dictionary).get("condition", {})
			var ad : String = str(cond.get("after_dialogue", ""))
			if ad != "" and not dlg_ids.has(ad):
				# 可能是后面才定义的对话，只警告
				_warn(fname, "%s.dialogues[%d].condition.after_dialogue" % [npc_id, i],
					"after_dialogue 指向未在本文档内出现的对话: %s" % ad)

		# unlocks
		var unlocks : Array = nd.get("unlocks", [])
		for i in range(unlocks.size()):
			var u : Variant = unlocks[i]
			if not (u is Dictionary): continue
			var ud : Dictionary = u
			var utype : String = str(ud.get("type", ""))
			var uid : String = str(ud.get("id", ""))

			if uid == "":
				_error(fname, "%s.unlocks[%d].id" % [npc_id, i], "unlock id 为空")
				continue

			match utype:
				"unit":
					if not _unit_db.has(uid):
						_error(fname, "%s.unlocks[%d]" % [npc_id, i], "单位不存在: %s" % uid)
				"relic":
					if not _relic_db.has(uid):
						_error(fname, "%s.unlocks[%d]" % [npc_id, i], "遗物不存在: %s" % uid)
				"aura":
					if not _aura_db.has(uid):
						_error(fname, "%s.unlocks[%d]" % [npc_id, i], "光环不存在: %s" % uid)
				"talent":
					if not _talent_db.has(uid):
						_error(fname, "%s.unlocks[%d]" % [npc_id, i], "词条不存在: %s" % uid)
				"route":
					if not DispatchManager.ROUTES.has(uid):
						_error(fname, "%s.unlocks[%d]" % [npc_id, i], "派遣路线不存在: %s" % uid)
				"transform_branch":
					if not _branch_exists(uid):
						_error(fname, "%s.unlocks[%d]" % [npc_id, i], "转职分支不存在: %s" % uid)
				_:
					_warn(fname, "%s.unlocks[%d].type" % [npc_id, i], "未知解锁类型: %s" % utype)

			# conditions.after_dialogue 必须指向本 NPC 的对话
			var ucond : Dictionary = ud.get("conditions", {})
			var uad : String = str(ucond.get("after_dialogue", ""))
			if uad != "" and not dlg_ids.has(uad):
				_error(fname, "%s.unlocks[%d].conditions.after_dialogue" % [npc_id, i],
					"after_dialogue 指向不存在的对话: %s" % uad)


func _branch_exists(branch_id : String) -> bool:
	for ukey in _unit_db:
		var u : Variant = _unit_db[ukey]
		if not (u is Dictionary): continue
		var branches : Array = (u as Dictionary).get("advanced_branches", [])
		for b in branches:
			if b is Dictionary and str((b as Dictionary).get("id", "")) == branch_id:
				return true
	return false


# ============================================================
#  事件校验
# ============================================================
func _validate_events():
	var fname := "events.json"
	for eid in _event_db:
		var e : Variant = _event_db[eid]
		if not (e is Dictionary): continue
		var ed : Dictionary = e
		var actions : Array = ed.get("actions", [])
		if actions.is_empty():
			_warn(fname, eid, "事件没有 actions")

		for i in range(actions.size()):
			var a : Variant = actions[i]
			if not (a is Dictionary): continue
			var ad : Dictionary = a
			var atype : String = str(ad.get("type", ""))

			if atype == "":
				_error(fname, "%s.actions[%d].type" % [eid, i], "action type 为空")
				continue

			if atype not in VALID_ACTION_TYPES:
				_warn(fname, "%s.actions[%d].type" % [eid, i], "未知 action 类型: %s" % atype)
				continue

			match atype:
				"dialog":
					var did : String = str(ad.get("dialog_id", ""))
					if did == "":
						_error(fname, "%s.actions[%d].dialog_id" % [eid, i], "dialog_id 为空")
					elif not _dialogue_db.has(did):
						_error(fname, "%s.actions[%d].dialog_id" % [eid, i], "对话不存在: %s" % did)
				"give_item":
					var iid : String = str(ad.get("item_id", ""))
					if iid == "":
						_error(fname, "%s.actions[%d].item_id" % [eid, i], "item_id 为空")
					elif not _item_db.has(iid) and not _relic_db.has(iid):
						_error(fname, "%s.actions[%d].item_id" % [eid, i], "物品不存在: %s" % iid)
				"unlock_unit":
					var us : Array = ad.get("units", [])
					if us.is_empty():
						_warn(fname, "%s.actions[%d].units" % [eid, i], "unlock_unit 没有 units")
					for j in range(us.size()):
						var ukey : String = str(us[j])
						if not _unit_db.has(ukey):
							_error(fname, "%s.actions[%d].units[%d]" % [eid, i, j],
								"单位不存在: %s" % ukey)
				"unlock_talent":
					var tid : String = str(ad.get("talent_id", ""))
					if tid != "" and not _talent_db.has(tid):
						_error(fname, "%s.actions[%d].talent_id" % [eid, i], "词条不存在: %s" % tid)
				"unlock_equipment":
					var eid2 : String = str(ad.get("item_id", ""))
					if eid2 != "" and not _item_db.has(eid2) and not _relic_db.has(eid2):
						_error(fname, "%s.actions[%d].item_id" % [eid, i], "物品不存在: %s" % eid2)
				"unlock_relics":
					_warn(fname, "%s.actions[%d]" % [eid, i],
						"unlock_relics action 已废弃（遗物统一走 BOSS 节点）")
