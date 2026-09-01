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
@export var max_talent_slots: int = 2

# ---- 新字段：职业成长（魂加点） ----
@export var advancement: Dictionary = {
	"hp_bonus": 0,
	"atk_bonus": 0,
	"def_bonus": 0,
	"spd_bonus": 0
}
