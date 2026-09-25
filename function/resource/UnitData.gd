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
## 熔铸 buff 来源列表（每个元素是提供 buff 的熔铸单位 key）
@export var sacrifice_buff_sources : Array = []

# ---- 战斗 Buff（临时，不入档） ----
var buff_attack_percent : float = 0.0
var buff_crit_damage_bonus : float = 0.0
var buff_defense_flat : int = 0
var buff_damage_reduction : float = 0.0
var buff_attack_flat : int = 0
var buff_magic_attack_flat : int = 0

# ---- 转职 ----
@export var advanced_class: String = ""
@export var override_sprite_path: String = ""

func reset_combat_buffs():
	buff_attack_percent = 0.0
	buff_crit_damage_bonus = 0.0
	buff_defense_flat = 0
	buff_damage_reduction = 0.0
	buff_attack_flat = 0
	buff_magic_attack_flat = 0

# ---- 死亡状态（本三天流程内）----
@export var is_dead: bool = false

@export var experience: int = 0
@export var level: int = 1

# ---- 装备系统 ----
@export var weapon_slot: ItemInstance = null
@export var armor_slots: Array = []
@export var max_armor_slots: int = 2

# ---- 词条系统 ----
@export var talent_slots: Array = []
@export var max_talent_slots: int = 1

# ---- 职业特技（转职授予，不占普通词条槽） ----
@export var advanced_talent_id : String = ""
var advanced_talent_inst : TalentInstance = null

# ---- 职业成长（魂加点） ----
@export var advancement: Dictionary = {
	"hp_bonus": 0,
	"atk_bonus": 0,
	"def_bonus": 0,
	"spd_bonus": 0
}

# ============================================================
#  装备 modifier 汇总
# ============================================================

## 汇总所有防具的 modifier 加成
## 返回 { "strength": 2, "dexterity": 1, ... }
func get_armor_modifier_bonus() -> Dictionary:
	var bonus : Dictionary = {}
	for slot_v in armor_slots:
		if slot_v == null:
			continue
		var slot : ItemInstance = slot_v
		var data : ItemData = ItemManager.get_item_data(slot.item_id)
		if not data:
			continue
		for key in data.modifier:
			var cur : int = int(bonus.get(key, 0))
			var add : int = int(data.modifier[key])
			bonus[key] = cur + add
	return bonus


## 计算已占用的防具格数（考虑 slot_count）
func count_used_armor_slots() -> int:
	var used : int = 0
	for slot_v in armor_slots:
		if slot_v != null: used += 1
	return used


## 是否还能装下指定防具
func can_equip_armor(_item_id: String, exclude_slot_idx: int = -1) -> bool:
	if exclude_slot_idx >= 0 and exclude_slot_idx < armor_slots.size():
		return true
	for slot_v in armor_slots:
		if slot_v == null: return true
	return false


## 返回含防具 modifier 加成的最终属性（取整）
## attr_name ∈ {strength, dexterity, intelligence, faith, arcane, move_range, max_hp}
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


# ============================================================
#  序列化 / 反序列化（v3）
# ============================================================

func to_dict() -> Dictionary:
	return {
		"unit_name": unit_name,
		"display_name": display_name,
		"faction": faction,
		"team_id": team_id,
		"max_hp": max_hp,
		"hit_points": hit_points,
		"strength": strength,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"faith": faith,
		"arcane": arcane,
		"move_range": move_range,
		"ignore_terrain_cost": ignore_terrain_cost,
		"experience": experience,
		"level": level,
		"max_armor_slots": max_armor_slots,
		"max_talent_slots": max_talent_slots,
		"advancement": advancement.duplicate(),
		"weapon_slot": _item_instance_to_dict(weapon_slot),
		"armor_slots": _item_instance_array_to_array(armor_slots),
		"talent_slots": _talent_instance_array_to_array(talent_slots),
		"advanced_class": advanced_class,
		"advanced_talent_id": advanced_talent_id,
		"override_sprite_path": override_sprite_path,
		"is_dead": is_dead,
		"sacrifice_buff_sources": sacrifice_buff_sources.duplicate(),
	}


static func from_dict(d: Dictionary) -> UnitData:
	var data := UnitData.new()

	data.unit_name = d.get("unit_name", "swordsman")
	data.display_name = d.get("display_name", "")
	data.faction = d.get("faction", "")
	data.team_id = d.get("team_id", 0)
	data.max_hp = d.get("max_hp", 20)
	data.hit_points = d.get("hit_points", data.max_hp)
	data.strength = d.get("strength", 5)
	data.dexterity = d.get("dexterity", 5)
	data.intelligence = d.get("intelligence", 3)
	data.faith = d.get("faith", 3)
	data.arcane = d.get("arcane", 3)
	data.move_range = d.get("move_range", 5)
	data.ignore_terrain_cost = d.get("ignore_terrain_cost", false)
	data.experience = d.get("experience", 0)
	data.level = d.get("level", 1)
	data.max_armor_slots = d.get("max_armor_slots", 2)
	data.max_talent_slots = d.get("max_talent_slots", 1)
	data.advanced_class = d.get("advanced_class", "")
	data.advanced_talent_id = d.get("advanced_talent_id", "")     # ★ 新增
	data.override_sprite_path = d.get("override_sprite_path", "")
	data.is_dead = d.get("is_dead", false)
	var buff_arr : Variant = d.get("sacrifice_buff_sources", [])
	if buff_arr is Array:
		data.sacrifice_buff_sources = (buff_arr as Array).duplicate()
	else:
		data.sacrifice_buff_sources = []

	# ★ 自净：advanced_class 为空时，强制清空 advanced_talent_id（修旧档污染）
	if data.advanced_class == "":
		data.advanced_talent_id = ""

	if d.has("advancement"):
		var adv_v : Variant = d["advancement"]
		if adv_v is Dictionary:
			data.advancement = (adv_v as Dictionary).duplicate()

	var weapon_dict : Dictionary = {}
	if d.has("weapon_slot"):
		var w_v : Variant = d["weapon_slot"]
		if w_v is Dictionary:
			weapon_dict = w_v
	data.weapon_slot = _dict_to_item_instance(weapon_dict)

	var armor_arr : Array = []
	if d.has("armor_slots"):
		var a_v : Variant = d["armor_slots"]
		if a_v is Array:
			armor_arr = a_v
	data.armor_slots = _array_to_item_instance_array(armor_arr)

	var talent_arr : Array = []
	if d.has("talent_slots"):
		var t_v : Variant = d["talent_slots"]
		if t_v is Array:
			talent_arr = t_v
	data.talent_slots = _array_to_talent_instance_array(talent_arr)

	while data.armor_slots.size() < data.max_armor_slots:
		data.armor_slots.append(null)
	while data.talent_slots.size() < 1:
		data.talent_slots.append(null)

	# ★ 构造运行时职业特技实例
	data.advanced_talent_inst = null
	if data.advanced_talent_id != "":
		var t_inst := TalentInstance.new()
		t_inst.talent_id = data.advanced_talent_id
		t_inst.is_active = true
		var tdata = TalentManager.get_talent_data(data.advanced_talent_id)
		if tdata and tdata.is_active_skill:
			t_inst.is_ready = true
			t_inst.cooldown_remaining = 0
		data.advanced_talent_inst = t_inst

	return data


# ============================================================
#  内部辅助
# ============================================================
static func _item_instance_to_dict(inst: ItemInstance) -> Dictionary:
	if not inst:
		return {}
	return {
		"item_id": inst.item_id,
		"count": inst.count,
		"upgrade_level": inst.upgrade_level,
	}

static func _dict_to_item_instance(d: Dictionary) -> ItemInstance:
	if d.is_empty():
		return null
	var item_id : String = d.get("item_id", "")
	if item_id == "":
		return null
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = d.get("count", 1)
	inst.upgrade_level = d.get("upgrade_level", 0)
	return inst

static func _item_instance_array_to_array(arr: Array) -> Array:
	var result : Array = []
	for inst in arr:
		result.append(_item_instance_to_dict(inst))
	return result


static func _array_to_item_instance_array(arr: Array) -> Array:
	var result : Array = []
	for slot_dict_v in arr:
		var slot_dict : Variant = slot_dict_v
		if slot_dict is Dictionary and not (slot_dict as Dictionary).is_empty():
			result.append(_dict_to_item_instance(slot_dict))
		else:
			result.append(null)
	return result


static func _talent_instance_to_dict(inst) -> Dictionary:
	if not inst or not (inst is TalentInstance):
		return {}
	var t_inst : TalentInstance = inst
	if not t_inst.is_active:
		return {}
	return {
		"talent_id": t_inst.talent_id,
		"current_stack": t_inst.current_stack,
		"is_ready": t_inst.is_ready,
		"is_active": t_inst.is_active,
	}


static func _dict_to_talent_instance(d: Dictionary) -> TalentInstance:
	if d.is_empty():
		return null
	var talent_id : String = d.get("talent_id", "")
	if talent_id == "":
		return null
	var inst := TalentInstance.new()
	inst.talent_id = talent_id
	inst.current_stack = d.get("current_stack", 0)
	inst.is_ready = d.get("is_ready", false)
	inst.is_active = d.get("is_active", true)
	return inst


static func _talent_instance_array_to_array(arr: Array) -> Array:
	var result : Array = []
	for inst in arr:
		result.append(_talent_instance_to_dict(inst))
	return result


static func _array_to_talent_instance_array(arr: Array) -> Array:
	var result : Array = []
	for slot_dict_v in arr:
		var slot_dict : Variant = slot_dict_v
		if slot_dict is Dictionary and not (slot_dict as Dictionary).is_empty():
			result.append(_dict_to_talent_instance(slot_dict))
		else:
			result.append(null)
	return result

## 当前熔铸 buff 层数
func get_sacrifice_buff_count() -> int:
	return sacrifice_buff_sources.size()


## 汇总所有熔铸 buff（按类型求和）
func get_sacrifice_buffs() -> Dictionary:
	var result : Dictionary = {}
	for src_key in sacrifice_buff_sources:
		var parts : PackedStringArray = String(src_key).split("|")
		if parts.size() < 1: continue
		var src_unit_name : String = parts[0]      # ★ 改名，避免 shadowing
		var buff : Dictionary = UnitDataManager.get_sacrifice_buff(src_unit_name)
		if buff.is_empty(): continue
		var btype : String = buff.get("type", "")
		var bvalue : float = buff.get("value", 0.0)
		if btype == "": continue
		result[btype] = result.get(btype, 0.0) + bvalue
	return result


## 生成"熔铸单位"的唯一 key（用于追踪）
static func make_sacrifice_key(unit: UnitData) -> String:
	return "%s|%s" % [unit.unit_name, unit.display_name]
