extends Resource
class_name ItemData

@export var id: String
@export var name: String
@export var type: String          # "weapon", "armor", "relic", "heal", "cure", "buff", "attack"
@export var use_type: String      # "consumable", "equipment", "relic", "infinite"
@export var icon: Texture2D
@export var description: String
@export var category: String = "" # "sword", "spear", "axe", "bow", "staff", "shield", etc.
@export var equipment_slot: String = ""   # "weapon", "armor", "relic"
@export var stats: Dictionary = {}        # 属性加成
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var use_effect: Dictionary = {}   # 消耗品效果
@export var price: int = 0                # 商店价格
