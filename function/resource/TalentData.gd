extends Resource
class_name TalentData

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var school: String = ""
@export var rarity: String = ""
@export var accumulation_threshold: int = 3
@export var cooldown_after_trigger: int = 0
@export var effect_type: String = ""
@export var effect_params: Dictionary = {}
@export var icon_path: String = ""
@export var compatible_units: Array = []
@export var tutorial_stage: int = 0

# ---- 主动技能 ----
@export var is_active_skill: bool = false
@export var skill_cooldown: int = 0

# ---- 解锁信息 ----
@export var unlock_type: String = "default"
@export var soul_cost: int = 0
