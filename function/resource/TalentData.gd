extends Resource
class_name TalentData

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var school: String = ""
@export var rarity: String = ""
@export var accumulation_threshold: int = 3
@export var cooldown_after_trigger: int = 0     # ★ 新增
@export var effect_type: String = ""
@export var effect_params: Dictionary = {}
@export var icon_path: String = ""
@export var compatible_units: Array = []

# ---- 解锁信息 ----
@export var unlock_type: String = "default"
@export var soul_cost: int = 0
