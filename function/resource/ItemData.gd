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

# ---- 武器 ----
@export var quality: String = "common"
@export var attack_style: String = "standard"
@export var base_attack: int = 0
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var modifier: Dictionary = {}

# ---- 防具 ----
@export var armor_type: String = "medium"
@export var defense: int = 0
@export var slot_count: int = 1
@export var unlock_cost: Dictionary = {}
@export var craft_cost: int = 0

# ---- 特殊武器 ----
@export var heavy_attack: Dictionary = {}
@export var magic_attack: Dictionary = {}
@export var heal_effect: Dictionary = {}

@export var legendary_effect: String = ""

# ---- ★ 新增：升级数值 ----
# 结构：{ "max_level": 3, "attack_per_level": 2, "defense_per_level": 0,
#         "modifier_per_level": { "strength": 0.05 } }
@export var upgrade_stats: Dictionary = {}

# ---- 旧字段（保留） ----
@export var stats: Dictionary = {}
@export var use_effect: Dictionary = {}
@export var price: int = 0
