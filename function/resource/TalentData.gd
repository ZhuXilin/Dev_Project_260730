extends Resource
class_name TalentData

# ---- 词条ID ----
@export var id: String = ""

# ---- 显示名称 ----
@export var display_name: String = ""

# ---- 描述 ----
@export var description: String = ""

# ---- 所属流派 ----
@export var school: String = ""  # "勇猛" / "敏捷" / "奥秘"

# ---- 稀有度 ----
@export var rarity: String = "common"  # common / rare / epic / legendary

# ---- 积累阈值（回合数） ----
@export var accumulation_threshold: int = 3

# ---- 效果类型 ----
@export var effect_type: String = "attack"  # attack / defense / heal / control

# ---- 效果参数 ----
@export var effect_params: Dictionary = {}  # 不同词条有不同的参数结构

# ---- 图标路径（可选） ----
@export var icon_path: String = ""
