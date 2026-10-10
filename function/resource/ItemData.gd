extends Resource
class_name ItemData

@export var id: String
@export var name: String
@export var type: String
@export var use_type: String
@export var icon: Texture2D
@export var description: String
@export var category: String = ""
@export var equipment_slot: String = ""

@export var quality: String = "common"
@export var attack_style: String = "standard"
@export var base_attack: int = 0
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var modifier: Dictionary = {}

@export var armor_type: String = "medium"
@export var defense: int = 0
@export var slot_count: int = 1
@export var unlock_cost: Dictionary = {}
@export var craft_cost: int = 0

@export var heavy_attack: Dictionary = {}
@export var magic_attack: Dictionary = {}
@export var heal_effect: Dictionary = {}

@export var legendary_effect: String = ""

@export var upgrade_stats: Dictionary = {}

@export var stats: Dictionary = {}
@export var use_effect: Dictionary = {}
@export var price: int = 0

# ★ 批次 3：装备标签
@export var tags: Array[String] = []

# ★ 批次 4：熔合产物
@export var fusion_id: String = ""
@export var fusion_effect: String = ""
