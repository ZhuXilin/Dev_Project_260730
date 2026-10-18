extends Resource
class_name SaveData

const CURRENT_VERSION = 11

@export var save_version: int = CURRENT_VERSION

# ---- 解锁 ----
@export var unlocked_units: Array = []
@export var unlocked_items: Array = []
@export var unlocked_relics: Array = []
@export var unlocked_talents: Array = []
@export var unlocked_recipes: Array = []
@export var unlocked_stories: Array = []

@export var eligible_units: Array = []
@export var current_node_unlock_relics: Array = []
@export var current_node_unlock_units: Array = []

# ---- 设置 ----
@export var music_volume: float = 0.2
@export var sound_volume: float = 0.2
@export var game_speed: int = 0
@export var window_mode: int = 0
@export var window_size: Vector2i = Vector2i(640, 480)

# ---- 进度 ----
@export var current_day: int = 1
@export var visited_nodes: Array = []
@export var selected_node_id: String = ""
@export var main_unit_name: String = ""
@export var current_node_key: String = ""

# ---- 资源 ----
@export var soul: int = 0
@export var cycle_start_soul: int = 0
@export var temp_gold: int = 0
@export var keys: int = 0
@export var keys_bought: int = 0

# ---- 隐藏商人商品 ----
@export var pending_tag_pin: String = ""
@export var active_tag_pin: String = ""
@export var soul_fire_threshold_override: float = 0.0
## @deprecated v4.5 已删除重铸券；字段保留仅用于兼容旧档加载
@export var reforge_tickets: int = 0

# ---- 遗物精炼（v4.5）----
@export var relic_levels: Dictionary = {}

# ---- 魂火 ----
@export var soul_fire_current: int = 0
@export var soul_fire_altar_level: int = 0
@export var soul_fire_initial_level: int = 0
@export var unit_attr_cap: Dictionary = {}
@export var unit_attr_points: Dictionary = {}
@export var tag_purchase_count: Dictionary = {}

# ---- 光环 ----
@export var unlocked_auras: Array = []
@export var active_aura_research: Dictionary = {}
@export var aura_research_progress: Dictionary = {}

# ---- 新手 ----
@export var tutorial_stage: int = 0
@export var shop_level: int = 0

# ---- 成长 ----
@export var unit_growth: Dictionary = {}
@export var unit_blessings: Dictionary = {}
@export var talent_exp: Dictionary = {}

# ---- 队伍 ----
@export var party_data: Array = []
@export var equipped_passives: Array = []

# ---- 地图 ----
@export var interrupt_state: int = 0
@export var battlefield_data: Dictionary = {}
@export var map_snapshot: Dictionary = {}
@export var current_faction: String = ""

# ---- 斗技场 ----
@export var arena_target_talents: Dictionary = {}
@export var arena_best_streak: int = 0
@export var arena_clear_count: int = 0
@export var arena_survival_clear: int = 0
@export var arena_survival_best: int = 0
@export var arena_total_crystals: int = 0
@export var arena_total_runs: int = 0

# ---- 待领取 ----
@export var pending_sacrifice_rewards: Array = []
@export var pending_forge_rewards: Array = []
@export var sacrifice_count: int = 0

# ---- NPC ----
@export var npc_dialogue_seen: Dictionary = {}
@export var npc_dialogue_flags: Array = []
@export var total_run_count: int = 0
@export var total_dispatch_count: int = 0

# ---- 时间戳 ----
@export var save_time: int = 0

## @deprecated 已不再使用
@export var checksum: String = ""
## @deprecated 仅 v9 → v10 迁移用（v4.5 起不再写入，字段保留兼容旧档）
@export var temp_soul_legacy: int = 0

@export var npc_affinity: Dictionary = {}
@export var forge_whisper_state: Dictionary = {}
