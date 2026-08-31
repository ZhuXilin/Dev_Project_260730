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

# ---- 新增武器字段 ----
@export var quality: String = "common"      # common/rare/epic/legendary
@export var attack_style: String = "standard"
@export var base_attack: int = 0
@export var attack_range: int = 1
@export var min_attack_range: int = 1
@export var modifier: Dictionary = {}       # { "strength": 0.6, ... }

# ---- 新增防具字段 ----
@export var armor_type: String = "medium"   # light/medium/heavy/robe
@export var defense: int = 0
@export var slot_count: int = 1
@export var unlock_cost: Dictionary = {}    # { "粗铁": 5, ... }
@export var craft_cost: int = 0

# ---- 特殊武器类型 ----
@export var heavy_attack: Dictionary = {}   # { "damage_multiplier": 1.4, "charge_multiplier": 2.0 }
@export var magic_attack: Dictionary = {}   # { "ignore_defense": true }
@export var heal_effect: Dictionary = {}    # { "base_heal": 10, "faith_multiplier": 1.0 }

# ---- 传说特效 ----
@export var legendary_effect: String = ""

# ---- 旧有字段 ----
@export var stats: Dictionary = {}
@export var use_effect: Dictionary = {}
@export var price: int = 0
