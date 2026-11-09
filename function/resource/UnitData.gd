extends Resource
class_name UnitData

@export var unit_name: String = "战士"
@export var display_name: String = ""
@export var faction: String = ""
@export var team_id: int = 0

@export var max_hp: int = 20
@export var hit_points: int = 20

@export var strength: int = 5
@export var dexterity: int = 5
@export var intelligence: int = 3
@export var faith: int = 3
@export var arcane: int = 3
@export var move_range: int = 5
@export var ignore_terrain_cost: bool = false

@export var physical_reduction: float = 0.0
@export var magic_reduction: float = 0.0

# ============================================================
#  ★ v4.8 武器彻底内联为单位固有属性
# ============================================================
@export var weapon_name: String = ""
@export var attack: float = 0.0
@export var weapon_quality: String = "common"
@export var attack_style: String = "standard"
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var weapon_category: String = ""
@export var modifier: Dictionary = {}
@export var physical_penetration: float = 0.0
@export var magic_penetration: float = 0.0
@export var heavy_attack: Dictionary = {}
@export var magic_attack: Dictionary = {}
@export var heal_effect: Dictionary = {}

@export var sacrifice_buff_sources : Array = []
@export var core_trait: String = ""
@export var is_boss: bool = false

@export var hidden_from_roster: bool = false
@export var boss_mechanic_id: String = ""
@export var boss_mechanic_params: Dictionary = {}
@export var boss_dialogue_hooks: Dictionary = {}
@export var phases: Array = []

@export var tags: Array[String] = []
@export var avatar: String = ""
var avatar_override: String = ""

# ---- 战斗 Buff ----
var buff_attack_percent : float = 0.0
var buff_crit_damage_bonus : float = 0.0
var buff_physical_reduction : float = 0.0
var buff_magic_reduction : float = 0.0
var buff_damage_reduction : float = 0.0
var buff_attack_flat : int = 0
var buff_magic_attack_flat : int = 0
var buff_lifesteal_percent : float = 0.0
var buff_defense_flat : int = 0

var relic_first_attack_crit_available : bool = false
var relic_low_hp_damage_reduce : float = 0.0
var relic_kill_grants_extra_move : int = 0
var relic_first_spell_free_available : bool = false
var relic_turn_first_hit_regen : float = 0.0
var relic_turn_first_hit_regen_used : bool = false
var relic_strength_scale_damage : float = 0.0
var relic_counter_damage_bonus : float = 0.0
var relic_heal_bonus : float = 0.0
var relic_auto_revive_available : bool = false
var relic_first_attack_crit_remaining : int = 0
var relic_first_spell_free_remaining : int = 0
var relic_low_hp_threshold : float = 0.3
var relic_phoenix_revive_attack_bonus : float = 0.0

var bleed_stacks : int = 0
var combo_last_target : String = ""
var combo_count : int = 0
var zeal_target : String = ""
var zeal_stacks : int = 0

@export var advanced_class: String = ""
@export var override_sprite_path: String = ""

@export var level: int = 1
@export var attack_range_bonus: int = 0
@export var static_physical_penetration: float = 0.0
@export var static_magic_penetration: float = 0.0
@export var static_crit_damage_bonus: float = 0.0

@export var is_dead: bool = false
@export var experience: int = 0

@export var armor_slots: Array = []
@export var max_armor_slots: int = 2
@export var talent_slots: Array = []
@export var max_talent_slots: int = 1

@export var advanced_talent_id : String = ""
var advanced_talent_inst : TalentInstance = null

@export var advancement: Dictionary = {
	"hp_bonus": 0, "atk_bonus": 0, "def_bonus": 0, "spd_bonus": 0
}

const VALID_BOSS_TRIGGERS : Array = ["initial", "hp_below", "on_death"]
const VALID_BOSS_HP_MODES : Array = ["full", "keep_ratio", "keep_absolute", "custom_ratio"]


func reset_combat_buffs():
	buff_attack_percent = 0.0
	buff_crit_damage_bonus = 0.0
	buff_physical_reduction = 0.0
	buff_magic_reduction = 0.0
	buff_damage_reduction = 0.0
	buff_attack_flat = 0
	buff_magic_attack_flat = 0
	buff_lifesteal_percent = 0.0
	buff_defense_flat = 0
	relic_first_attack_crit_available = false
	relic_low_hp_damage_reduce = 0.0
	relic_kill_grants_extra_move = 0
	relic_first_spell_free_available = false
	relic_turn_first_hit_regen = 0.0
	relic_turn_first_hit_regen_used = false
	relic_strength_scale_damage = 0.0
	relic_counter_damage_bonus = 0.0
	relic_heal_bonus = 0.0
	relic_auto_revive_available = false
	relic_first_attack_crit_remaining = 0
	relic_first_spell_free_remaining = 0
	relic_low_hp_threshold = 0.3
	relic_phoenix_revive_attack_bonus = 0.0
	bleed_stacks = 0
	combo_last_target = ""
	combo_count = 0
	zeal_target = ""
	zeal_stacks = 0


static func normalize_phases(raw: Variant) -> Array:
	var result: Array = []
	if not (raw is Array): return result
	var arr: Array = raw
	for i in range(arr.size()):
		var p: Variant = arr[i]
		if not (p is Dictionary): continue
		var d: Dictionary = p
		var trig: String = str(d.get("trigger", "on_death"))
		if trig not in VALID_BOSS_TRIGGERS: trig = "on_death"
		var hp_mode: String = str(d.get("hp_mode", "full"))
		if hp_mode not in VALID_BOSS_HP_MODES: hp_mode = "full"
		var mp_raw: Variant = d.get("mechanic_params", {})
		var ov_raw: Variant = d.get("override", {})
		var phase: Dictionary = {
			"form_unit_id": str(d.get("form_unit_id", d.get("form", ""))),
			"trigger": trig,
			"threshold": clampf(float(d.get("threshold", 0.5)), 0.05, 0.95),
			"hp_mode": hp_mode,
			"min_hp": maxi(0, int(d.get("min_hp", 1))),
			"reset_turn_state": bool(d.get("reset_turn_state", false)),
			"preserve_buffs": bool(d.get("preserve_buffs", true)),
			"mechanic_id": str(d.get("mechanic_id", "")),
			"mechanic_params": (mp_raw as Dictionary).duplicate(true) if mp_raw is Dictionary else {},
			"override": (ov_raw as Dictionary).duplicate(true) if ov_raw is Dictionary else {}
		}
		if i == 0:
			phase["trigger"] = "initial"
			phase["hp_mode"] = "full"
		result.append(phase)
	return result


func get_armor_modifier_bonus() -> Dictionary:
	var bonus : Dictionary = {}
	for slot_v in armor_slots:
		if slot_v == null: continue
		var slot : ItemInstance = slot_v
		var data : ItemData = ItemManager.get_item_data(slot.item_id)
		if not data: continue
		for key in data.modifier:
			var cur : int = int(bonus.get(key, 0))
			var add : int = int(data.modifier[key])
			bonus[key] = cur + add
	return bonus

func count_used_armor_slots() -> int:
	var used : int = 0
	for slot_v in armor_slots:
		if slot_v != null: used += 1
	return used

func can_equip_armor(_item_id: String, exclude_slot_idx: int = -1) -> bool:
	if exclude_slot_idx >= 0 and exclude_slot_idx < armor_slots.size(): return true
	for slot_v in armor_slots:
		if slot_v == null: return true
	return false

func get_effective_attr(attr_name: String) -> int:
	var base : int = 0
	match attr_name:
		"strength":     base = strength
		"dexterity":    base = dexterity
		"intelligence": base = intelligence
		"faith":        base = faith
		"arcane":       base = arcane
		"move_range":   base = move_range
		"max_hp":       base = max_hp
		_:              return 0
	var bonus : Dictionary = get_armor_modifier_bonus()
	var bonus_val : int = int(bonus.get(attr_name, 0))
	return base + bonus_val

func apply_level_up() -> bool:
	if level >= 6 or is_dead: return false
	var idx : int = level - 1
	var attr : Dictionary = UnitDataManager.get_attr_cap_level_bonus(unit_name, idx)
	for k in attr:
		match k:
			"vitality", "max_hp":
				var v : int = int(attr[k])
				max_hp += v
				hit_points += v
			"strength":     strength += int(attr[k])
			"dexterity":    dexterity += int(attr[k])
			"intelligence": intelligence += int(attr[k])
			"faith":        faith += int(attr[k])
			"arcane":       arcane += int(attr[k])
			"move_range":   move_range += int(attr[k])

	var mech : Dictionary = UnitDataManager.get_level_mechanics(unit_name, idx)
	for mk in mech:
		if not bool(mech[mk]): continue
		match mk:
			"range_plus_1":                 attack_range_bonus += 1
			"move_plus_1":                  move_range += 1
			"crit_damage_plus_20":          static_crit_damage_bonus += 0.20
			"physical_penetration_plus_10": static_physical_penetration += 0.10
			"magic_penetration_plus_10":    static_magic_penetration += 0.10
	level += 1
	return true


func to_dict() -> Dictionary:
	var d: Dictionary = {
		"unit_name": unit_name, "display_name": display_name,
		"faction": faction, "team_id": team_id, "avatar": avatar,
		"max_hp": max_hp, "hit_points": hit_points,
		"strength": strength, "dexterity": dexterity, "intelligence": intelligence,
		"faith": faith, "arcane": arcane, "move_range": move_range,
		"physical_reduction": physical_reduction, "magic_reduction": magic_reduction,
		"ignore_terrain_cost": ignore_terrain_cost, "experience": experience, "level": level,
		"attack_range_bonus": attack_range_bonus, "static_physical_penetration": static_physical_penetration,
		"static_magic_penetration": static_magic_penetration, "static_crit_damage_bonus": static_crit_damage_bonus,
		"max_armor_slots": max_armor_slots, "max_talent_slots": max_talent_slots,
		"advancement": advancement.duplicate(), "armor_slots": _item_instance_array_to_array(armor_slots),
		"talent_slots": _talent_instance_array_to_array(talent_slots),
		"advanced_class": advanced_class, "advanced_talent_id": advanced_talent_id,
		"override_sprite_path": override_sprite_path, "avatar_override": avatar_override,
		"is_dead": is_dead, "sacrifice_buff_sources": sacrifice_buff_sources.duplicate(),
		"tags": tags.duplicate(), "core_trait": core_trait, "is_boss": is_boss,
		"hidden_from_roster": hidden_from_roster, "boss_mechanic_id": boss_mechanic_id,
		"boss_mechanic_params": boss_mechanic_params.duplicate(true),
		"boss_dialogue_hooks": boss_dialogue_hooks.duplicate(true), "phases": normalize_phases(phases),

		"weapon_name": weapon_name, "attack": attack, "weapon_quality": weapon_quality,
		"attack_style": attack_style, "attack_range": attack_range, "min_attack_range": min_attack_range,
		"weapon_category": weapon_category, "modifier": modifier.duplicate(true),
		"physical_penetration": physical_penetration, "magic_penetration": magic_penetration,
		"heavy_attack": heavy_attack.duplicate(true), "magic_attack": magic_attack.duplicate(true),
		"heal_effect": heal_effect.duplicate(true),
	}
	return d


static func from_dict(d: Dictionary) -> UnitData:
	var data := UnitData.new()
	data.unit_name = d.get("unit_name", "swordsman")
	data.display_name = d.get("display_name", "")
	data.faction = d.get("faction", "")
	data.team_id = d.get("team_id", 0)
	data.avatar = str(d.get("avatar", ""))
	data.max_hp = d.get("max_hp", 20)
	data.hit_points = d.get("hit_points", data.max_hp)
	data.strength = d.get("strength", 5)
	data.dexterity = d.get("dexterity", 5)
	data.intelligence = d.get("intelligence", 3)
	data.faith = d.get("faith", 3)
	data.arcane = d.get("arcane", 3)
	data.move_range = d.get("move_range", 5)
	data.physical_reduction = float(d.get("physical_reduction", 0.0))
	data.magic_reduction = float(d.get("magic_reduction", 0.0))
	data.ignore_terrain_cost = d.get("ignore_terrain_cost", false)
	data.experience = d.get("experience", 0)
	data.level = int(d.get("level", 1))
	data.attack_range_bonus = int(d.get("attack_range_bonus", 0))
	data.static_physical_penetration = float(d.get("static_physical_penetration", 0.0))
	data.static_magic_penetration = float(d.get("static_magic_penetration", 0.0))
	data.static_crit_damage_bonus = float(d.get("static_crit_damage_bonus", 0.0))
	data.max_armor_slots = d.get("max_armor_slots", 2)
	data.max_talent_slots = d.get("max_talent_slots", 1)
	data.core_trait = d.get("core_trait", "")
	data.is_boss = d.get("is_boss", false)
	data.hidden_from_roster = bool(d.get("hidden_from_roster", false))
	data.boss_mechanic_id = str(d.get("boss_mechanic_id", ""))
	var bmp: Variant = d.get("boss_mechanic_params", {})
	data.boss_mechanic_params = (bmp as Dictionary).duplicate(true) if bmp is Dictionary else {}
	var bdh: Variant = d.get("boss_dialogue_hooks", {})
	data.boss_dialogue_hooks = (bdh as Dictionary).duplicate(true) if bdh is Dictionary else {}
	data.phases = normalize_phases(d.get("phases", []))

	var adv_raw = d.get("advanced_class", "")
	if adv_raw is String: data.advanced_class = adv_raw
	elif adv_raw is Dictionary: data.advanced_class = str((adv_raw as Dictionary).get("id", ""))
	else: data.advanced_class = ""
	
	data.advanced_talent_id = d.get("advanced_talent_id", "")
	data.override_sprite_path = d.get("override_sprite_path", "")
	data.avatar_override = d.get("avatar_override", "")
	data.is_dead = d.get("is_dead", false)

	var buff_arr : Variant = d.get("sacrifice_buff_sources", [])
	data.sacrifice_buff_sources = (buff_arr as Array).duplicate() if buff_arr is Array else []

	data.tags.clear()
	var tags_v : Variant = d.get("tags", [])
	if tags_v is Array:
		for t in tags_v:
			if t is String: data.tags.append(t)
	if data.advanced_class == "": data.advanced_talent_id = ""
	if d.has("advancement") and d["advancement"] is Dictionary:
		data.advancement = (d["advancement"] as Dictionary).duplicate()

	var armor_arr : Array = []
	if d.has("armor_slots") and d["armor_slots"] is Array: armor_arr = d["armor_slots"]
	data.armor_slots = _array_to_item_instance_array(armor_arr)
	var talent_arr : Array = []
	if d.has("talent_slots") and d["talent_slots"] is Array: talent_arr = d["talent_slots"]
	data.talent_slots = _array_to_talent_instance_array(talent_arr)
	while data.armor_slots.size() < data.max_armor_slots: data.armor_slots.append(null)
	while data.talent_slots.size() < 1: data.talent_slots.append(null)

	data.advanced_talent_inst = null
	if data.advanced_talent_id != "":
		var t_inst := TalentInstance.new()
		t_inst.talent_id = data.advanced_talent_id
		t_inst.is_active = true
		var tdata = TalentManager.get_talent_data(data.advanced_talent_id)
		if tdata and tdata.is_active_skill: t_inst.is_ready = true
		data.advanced_talent_inst = t_inst

	# ★ 读取纯战斗属性
	data.weapon_name = str(d.get("weapon_name", ""))
	data.attack = float(d.get("attack", 0.0))
	data.weapon_quality = str(d.get("weapon_quality", "common"))
	data.attack_style = str(d.get("attack_style", "standard"))
	data.attack_range = int(d.get("attack_range", 1))
	data.min_attack_range = int(d.get("min_attack_range", 1))
	data.weapon_category = str(d.get("weapon_category", ""))
	var wm_raw : Variant = d.get("modifier", {})
	data.modifier = (wm_raw as Dictionary).duplicate(true) if wm_raw is Dictionary else {}
	data.physical_penetration = float(d.get("physical_penetration", 0.0))
	data.magic_penetration = float(d.get("magic_penetration", 0.0))
	var wh_raw : Variant = d.get("heavy_attack", {})
	data.heavy_attack = (wh_raw as Dictionary).duplicate(true) if wh_raw is Dictionary else {}
	var wma_raw : Variant = d.get("magic_attack", {})
	data.magic_attack = (wma_raw as Dictionary).duplicate(true) if wma_raw is Dictionary else {}
	var whe_raw : Variant = d.get("heal_effect", {})
	data.heal_effect = (whe_raw as Dictionary).duplicate(true) if whe_raw is Dictionary else {}

	# ★ 旧档迁移：若只有 weapon_id（旧版），则去查表补全基础战斗属性
	if data.weapon_name == "" and d.has("weapon_id") and d["weapon_id"] != "":
		var wdata = ItemManager.get_item_data(d["weapon_id"])
		if wdata:
			data.weapon_name = wdata.name
			data.attack = wdata.base_attack
			data.weapon_quality = wdata.quality
			data.attack_style = wdata.attack_style
			data.attack_range = wdata.attack_range
			data.min_attack_range = wdata.min_attack_range
			data.weapon_category = wdata.category
			data.modifier = wdata.modifier.duplicate(true)
			data.physical_penetration = wdata.physical_penetration
			data.magic_penetration = wdata.magic_penetration
			data.heavy_attack = wdata.heavy_attack.duplicate(true)
			data.magic_attack = wdata.magic_attack.duplicate(true)
			data.heal_effect = wdata.heal_effect.duplicate(true)
			if OS.is_debug_build():
				print("[UnitData] 旧档迁移武器概念：%s → 单位固有属性" % data.weapon_name)

	return data


static func _item_instance_to_dict(inst: ItemInstance) -> Dictionary:
	if not inst: return {}
	return {
		"item_id": inst.item_id,
		"count": inst.count,
		"upgrade_level": inst.upgrade_level,
		"affixes": inst.affixes.duplicate(true),
		"direction": inst.direction,
	}
	

static func _dict_to_item_instance(d: Dictionary) -> ItemInstance:
	if d.is_empty(): return null
	var item_id : String = d.get("item_id", "")
	if item_id == "": return null
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = d.get("count", 1)
	inst.upgrade_level = d.get("upgrade_level", 0)
	var af : Variant = d.get("affixes", [])
	if af is Array:
		inst.affixes.clear()
		for a in af:
			if a is Dictionary:
				inst.affixes.append({"id": a.get("id", ""), "value": int(a.get("value", 0))})
	inst.direction = int(d.get("direction", 0))
	return inst

static func _item_instance_array_to_array(arr: Array) -> Array:
	var result : Array = []
	for inst in arr: result.append(_item_instance_to_dict(inst))
	return result

static func _array_to_item_instance_array(arr: Array) -> Array:
	var result : Array = []
	for slot_dict_v in arr:
		if slot_dict_v is Dictionary and not (slot_dict_v as Dictionary).is_empty(): result.append(_dict_to_item_instance(slot_dict_v))
		else: result.append(null)
	return result

static func _talent_instance_to_dict(inst) -> Dictionary:
	if not inst or not (inst is TalentInstance) or not (inst as TalentInstance).is_active: return {}
	return {"talent_id": inst.talent_id, "current_stack": inst.current_stack, "is_ready": inst.is_ready, "is_active": inst.is_active}

static func _dict_to_talent_instance(d: Dictionary) -> TalentInstance:
	if d.is_empty(): return null
	var talent_id : String = d.get("talent_id", "")
	if talent_id == "": return null
	var inst := TalentInstance.new()
	inst.talent_id = talent_id
	inst.current_stack = d.get("current_stack", 0)
	inst.is_ready = d.get("is_ready", false)
	inst.is_active = d.get("is_active", true)
	return inst

static func _talent_instance_array_to_array(arr: Array) -> Array:
	var result : Array = []
	for inst in arr: result.append(_talent_instance_to_dict(inst))
	return result

static func _array_to_talent_instance_array(arr: Array) -> Array:
	var result : Array = []
	for slot_dict_v in arr:
		if slot_dict_v is Dictionary and not (slot_dict_v as Dictionary).is_empty(): result.append(_dict_to_talent_instance(slot_dict_v))
		else: result.append(null)
	return result

func get_sacrifice_buff_count() -> int: return sacrifice_buff_sources.size()

func get_sacrifice_buffs() -> Dictionary:
	var result : Dictionary = {}
	for src_key in sacrifice_buff_sources:
		var parts : PackedStringArray = String(src_key).split("|")
		if parts.size() < 1: continue
		var buff : Dictionary = UnitDataManager.get_sacrifice_buff(parts[0])
		if buff.is_empty(): continue
		var btype : String = buff.get("type", "")
		var bvalue : float = buff.get("value", 0.0)
		if btype == "": continue
		result[btype] = result.get(btype, 0.0) + bvalue
	return result

static func make_sacrifice_key(unit: UnitData) -> String:
	return "%s|%s" % [unit.unit_name, unit.display_name]
