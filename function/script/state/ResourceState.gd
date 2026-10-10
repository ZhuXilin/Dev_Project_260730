class_name ResourceState
extends RefCounted

# ============================================================
#  ResourceState — 全局状态分区（批次 1,3,4,5A,5B,8）
# ============================================================
var npc_affinity : Dictionary = {}   # npc_id → int

# ---- 资源 ----
var soul : int = 0
var temp_gold : int = 0

# ---- 魂火 ----
var soul_fire_current : int = 0
var soul_fire_altar_level : int = 0
var soul_fire_initial_level : int = 0
var unit_attr_cap : Dictionary = {}
var unit_attr_points : Dictionary = {}       # ★ 批次 4
var tag_purchase_count : Dictionary = {}     # ★ 批次 3

# ---- 光环（批次 5A）----
var unlocked_auras : Array = []
var active_aura_research : Dictionary = {}
var aura_research_progress : Dictionary = {}

# ---- 成长 ----
var unit_growth : Dictionary = {}
var unit_blessings : Dictionary = {}

# ---- 解锁 ----
var unlocked_recipes : Array = []
var unlocked_stories : Array = []
var talent_exp : Dictionary = {}
var arena_target_talents : Dictionary = {}

# ---- 斗技场统计 ----
var arena_best_streak : int = 0
var arena_clear_count : int = 0
var arena_survival_clear : int = 0
var arena_survival_best : int = 0
var arena_total_crystals : int = 0
var arena_total_runs : int = 0

# ---- 本轮基线 ----
var cycle_start_soul : int = 0

# ---- 单次奖励 ----
var reward_items : Array = []
var current_reward_gold : int = 0
var current_reward_soul : int = 0
var current_reward_materials : Dictionary = {}
var current_reward_rare_datas : Array = []

# ---- 新手 ----
var tutorial_stage : int = 0

# ---- 待领取 ----
var pending_sacrifice_rewards : Array = []
var pending_forge_rewards : Array = []
var sacrifice_count : int = 0

# ---- NPC 对话 ----
var npc_dialogue_seen : Dictionary = {}
var npc_dialogue_flags : Array = []
var total_run_count : int = 0
var total_dispatch_count : int = 0


func add_reward_item(item_id: String):
	if item_id not in reward_items:
		reward_items.append(item_id)


func clear_reward_items():
	reward_items.clear()


func clear_current_reward():
	current_reward_gold = 0
	current_reward_soul = 0
	current_reward_materials = {}
	current_reward_rare_datas.clear()
