# UnitData.gd
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

@export var experience: int = 0
@export var level: int = 1

# ---- 装备系统 ----
@export var weapon_slot: ItemInstance = null
@export var armor_slots: Array = []      # 改为无类型 Array，可存储 null
@export var max_armor_slots: int = 2

# ---- 词条系统 ----
@export var talent_slots: Array = []        # 词条实例（ItemInstance 或 TalentInstance）
@export var max_talent_slots: int = 1

# ---- 新字段：职业成长（魂加点） ----
@export var advancement: Dictionary = {
	"hp_bonus": 0,
	"atk_bonus": 0,
	"def_bonus": 0,
	"spd_bonus": 0
}

# ============================================================
#  序列化 / 反序列化（v3）
# ============================================================

func to_dict() -> Dictionary:
	return {
		# ---- 基础属性 ----
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
		# ---- 装备（打包进 party_data） ----
		"weapon_slot": _item_instance_to_dict(weapon_slot),
		"armor_slots": _item_instance_array_to_array(armor_slots),
		# ---- 词条 ----
		"talent_slots": _talent_instance_array_to_array(talent_slots),
	}


static func from_dict(d: Dictionary) -> UnitData:
	var data := UnitData.new()

	# ---- 基础属性 ----
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

	if d.has("advancement") and d["advancement"] is Dictionary:
		data.advancement = d["advancement"].duplicate()

	# ---- 装备 ----
	data.weapon_slot = _dict_to_item_instance(d.get("weapon_slot", {}))
	data.armor_slots = _array_to_item_instance_array(d.get("armor_slots", []))

	# ---- 词条 ----
	data.talent_slots = _array_to_talent_instance_array(d.get("talent_slots", []))

	# ---- 补齐槽位数量 ----
	while data.armor_slots.size() < data.max_armor_slots:
		data.armor_slots.append(null)
	while data.talent_slots.size() < 1:
		data.talent_slots.append(null)

	return data


# ============================================================
#  内部辅助：ItemInstance ↔ Dictionary
# ============================================================
static func _item_instance_to_dict(inst: ItemInstance) -> Dictionary:
	if not inst:
		return {}
	return {
		"item_id": inst.item_id,
		"count": inst.count,
		"upgrade_level": inst.upgrade_level,   # ← 新增
	}

static func _dict_to_item_instance(d: Dictionary) -> ItemInstance:
	if not d or d.is_empty():
		return null
	var item_id = d.get("item_id", "")
	if item_id == "":
		return null
	var inst = ItemInstance.new()
	inst.item_id = item_id
	inst.count = d.get("count", 1)
	inst.upgrade_level = d.get("upgrade_level", 0)   # ← 新增
	return inst

static func _item_instance_array_to_array(arr: Array) -> Array:
	var result: Array = []
	for inst in arr:
		result.append(_item_instance_to_dict(inst))
	return result


static func _array_to_item_instance_array(arr: Array) -> Array:
	var result: Array = []
	for slot_dict in arr:
		if slot_dict is Dictionary and not slot_dict.is_empty():
			result.append(_dict_to_item_instance(slot_dict))
		else:
			result.append(null)
	return result


# ============================================================
#  内部辅助：TalentInstance ↔ Dictionary
# ============================================================

static func _talent_instance_to_dict(inst) -> Dictionary:
	if not inst or not (inst is TalentInstance):
		return {}
	if not inst.is_active:
		return {}
	return {
		"talent_id": inst.talent_id,
		"current_stack": inst.current_stack,
		"is_ready": inst.is_ready,
		"is_active": inst.is_active,
	}


static func _dict_to_talent_instance(d: Dictionary) -> TalentInstance:
	if not d or d.is_empty():
		return null
	var talent_id = d.get("talent_id", "")
	if talent_id == "":
		return null
	var inst = TalentInstance.new()
	inst.talent_id = talent_id
	inst.current_stack = d.get("current_stack", 0)
	inst.is_ready = d.get("is_ready", false)
	inst.is_active = d.get("is_active", true)
	return inst


static func _talent_instance_array_to_array(arr: Array) -> Array:
	var result: Array = []
	for inst in arr:
		result.append(_talent_instance_to_dict(inst))
	return result


static func _array_to_talent_instance_array(arr: Array) -> Array:
	var result: Array = []
	for slot_dict in arr:
		if slot_dict is Dictionary and not slot_dict.is_empty():
			result.append(_dict_to_talent_instance(slot_dict))
		else:
			result.append(null)
	return result
