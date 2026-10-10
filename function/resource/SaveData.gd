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
@export var checksum: String = ""

# ★ 迁移用（批次 8）
@export var temp_soul_legacy: int = 0

@export var npc_affinity: Dictionary = {}

func compute_checksum() -> String:
	var data = {
		"music_volume": music_volume, "sound_volume": sound_volume,
		"game_speed": game_speed, "window_mode": window_mode, "window_size": window_size,
		"current_day": current_day, "visited_nodes": visited_nodes,
		"selected_node_id": selected_node_id, "main_unit_name": main_unit_name,
		"soul": soul, "cycle_start_soul": cycle_start_soul, "temp_gold": temp_gold,
		"soul_fire_current": soul_fire_current,
		"soul_fire_altar_level": soul_fire_altar_level,
		"soul_fire_initial_level": soul_fire_initial_level,
		"unit_attr_cap": unit_attr_cap, "unit_attr_points": unit_attr_points,
		"tag_purchase_count": tag_purchase_count,
		"unlocked_auras": unlocked_auras,
		"active_aura_research": active_aura_research,
		"aura_research_progress": aura_research_progress,
		"interrupt_state": interrupt_state, "battlefield_data": battlefield_data,
		"party_data": party_data,
		"unlocked_units": unlocked_units, "unlocked_items": unlocked_items,
		"unlocked_relics": unlocked_relics, "unlocked_talents": unlocked_talents,
		"unlocked_recipes": unlocked_recipes, "unlocked_stories": unlocked_stories,
		"current_faction": current_faction, "equipped_passives": equipped_passives,
		"unit_growth": unit_growth, "unit_blessings": unit_blessings,
		"talent_exp": talent_exp,
		"current_node_key": current_node_key, "map_snapshot": map_snapshot,
		"arena_target_talents": arena_target_talents,
		"arena_best_streak": arena_best_streak, "arena_clear_count": arena_clear_count,
		"arena_survival_clear": arena_survival_clear, "arena_survival_best": arena_survival_best,
		"arena_total_crystals": arena_total_crystals, "arena_total_runs": arena_total_runs,
		"tutorial_stage": tutorial_stage,
		"pending_sacrifice_rewards": pending_sacrifice_rewards,
		"pending_forge_rewards": pending_forge_rewards,
		"sacrifice_count": sacrifice_count, "shop_level": shop_level,
		"npc_dialogue_seen": npc_dialogue_seen, "npc_dialogue_flags": npc_dialogue_flags,
		"total_run_count": total_run_count, "total_dispatch_count": total_dispatch_count,
		"npc_affinity": npc_affinity,
	}
	return JSON.stringify(data, "  ").sha256_text()
