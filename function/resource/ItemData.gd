extends Resource
class_name ItemData

@export var id: String
@export var name: String
@export var type: String          # "weapon", "armor", "relic", "heal", "cure", "buff", "attack"
@export var use_type: String      # "consumable", "equipment", "relic", "infinite"
@export var icon: Texture2D
@export var description: String
@export var category: String = "" # "sword", "spear", "axe", "bow", "staff", "shield", etc.

# 装备专用
@export var equipment_slot: String = ""   # "weapon", "armor", "relic"
@export var stats: Dictionary = {}        # 属性加成 { "attack": 2, "defense": 1, "magic_attack": 5, "heal_amount": 10, "move_range": 1 }

# 武器范围（仅当 equipment_slot == "weapon" 时有效）
@export var attack_range: int = 1
@export var min_attack_range: int = 1

# 消耗品效果
@export var use_effect: Dictionary = {}   # 用于消耗品
