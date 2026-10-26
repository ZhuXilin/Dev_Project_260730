extends Resource
class_name ItemData

@export var id: String
@export var name: String
@export var type: String
@export var use_type: String
@export var icon: Texture2D
@export var description: String
@export var flavor: String = ""
@export var category: String = ""
@export var equipment_slot: String = ""

@export var quality: String = "common"
@export var attack_style: String = "standard"
@export var base_attack: int = 0
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var modifier: Dictionary = {}

@export var physical_penetration: float = 0.0
@export var magic_penetration: float = 0.0

@export var armor_type: String = "medium"
@export var defense: int = 0          # 废弃字段（不参与计算）
@export var physical_reduction: float = 0.0
@export var magic_reduction: float = 0.0
@export var slot_count: int = 1
@export var craft_cost: int = 0

@export var heavy_attack: Dictionary = {}
@export var magic_attack: Dictionary = {}
@export var heal_effect: Dictionary = {}

@export var legendary_effect: String = ""  # 废弃字段

@export var upgrade_stats: Dictionary = {}

@export var stats: Dictionary = {}
@export var use_effect: Dictionary = {}
@export var price: int = 0

@export var tags: Array[String] = []

@export var fusion_id: String = ""
@export var fusion_effect: String = ""
