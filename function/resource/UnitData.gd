extends Resource
class_name UnitData

@export var unit_name: String = "战士"
@export var display_name: String = ""       # 个人姓名
@export var faction: String = ""            # 阵营
@export var team_id: int = 0
@export var max_hp: int = 20
@export var hit_points: int = 20
@export var defense: int = 3
@export var magic_defense: int = 0
@export var skill: int = 3
@export var speed: int = 4
@export var luck: int = 0
@export var move_range: int = 5
@export var ignore_terrain_cost: bool = false
@export var experience: int = 0
@export var level: int = 1
@export var inventory: Array[ItemInstance] = []   # 背包（消耗品、备用装备等）

# ---- 装备系统 ----
@export var weapon_slot: ItemInstance = null          # 武器
@export var armor_slots: Array[ItemInstance] = []    # 防具/饰品槽
@export var max_armor_slots: int = 2                 # 当前最大槽位数（每天+1）
