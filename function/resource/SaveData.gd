extends Resource
class_name SaveData

const CURRENT_VERSION = 10

@export var save_version: int = CURRENT_VERSION

# ---- 解锁 ----
@export var unlocked_units: Array = []
@export var unlocked_items: Array = []
@export var unlocked_relics: Array = []
@export var unlocked_talents: Array = []
@export var unlocked_recipes: Array = []
@export var unlocked_stories: Array = []

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

# ---- 魂火 ----
@export var soul_fire_current: int = 0
@export var soul_fire_altar_level: int = 0
@export var soul_fire_initial_level: int = 0
@export var unit_attr_cap: Dictionary = {}
@export var unit_attr_points: Dictionary = {}
@export var tag_purchase_count: Dictionary = {}

# ---- 光环（5A）----
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

# ============================================================
#  ★ 清档说明（第九批）
# ============================================================
# 下面两个字段已废弃，但**保留**以免 Godot 加载旧 .tres 时报
# "Property not found"。新档这两个字段永远是默认空值。
# 如需彻底清理，请做一次性数据迁移后再删除字段。
# ============================================================
## @deprecated 已不再使用；JSON.stringify 键顺序不稳定，无法可靠校验
@export var checksum: String = ""
## @deprecated 仅 v9 → v10 迁移用；v10 及以上不再写入
@export var temp_soul_legacy: int = 0

# ---- NPC 亲密度 ----
@export var npc_affinity: Dictionary = {}
