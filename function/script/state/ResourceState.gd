class_name ResourceState
extends RefCounted

# ============================================================
#  永久 / 临时资源
# ============================================================
var soul : int = 0
var temp_soul : int = 0
var temp_gold : int = 0

# ============================================================
#  材料
# ============================================================
var materials : Dictionary = {
	"粗铁": 0,
	"精钢": 0,
	"秘银": 0,
	"龙鳞": 0
}

var unit_growth : Dictionary = {}
var unit_blessings : Dictionary = {}

# ============================================================
#  防具配方解锁
# ============================================================
var unlocked_recipes : Array = []
var unlocked_stories : Array = []
var talent_exp : Dictionary = {}
var arena_target_talents : Dictionary = {}

# ============================================================
#  斗技场统计
# ============================================================
var arena_best_streak : int = 0
var arena_clear_count : int = 0
var arena_survival_clear : int = 0
var arena_survival_best : int = 0
var arena_total_crystals : int = 0
var arena_total_runs : int = 0

# ============================================================
#  本轮基线
# ============================================================
var cycle_start_soul : int = 0
var cycle_start_materials : Dictionary = {}

# ============================================================
#  单次奖励记录
# ============================================================
var reward_items : Array = []
var current_reward_gold : int = 0
var current_reward_soul : int = 0
var current_reward_materials : Dictionary = {}

# ============================================================
#  精炼配方
# ============================================================
var unlocked_refine_recipes : Array = []
var refined_items : Dictionary = {}

# ============================================================
#  新手阶段
# ============================================================
var tutorial_stage : int = 0

# ============================================================
#  待领取奖励（熔铸 / 合成）
# ============================================================
var pending_sacrifice_rewards : Array = []   # 元素：ItemInstance
var pending_forge_rewards : Array = []       # 元素：ItemInstance

# ============================================================
#  方法
# ============================================================
func add_material(material_name: String, amount: int):
	if materials.has(material_name):
		materials[material_name] += amount
	else:
		materials[material_name] = amount

func get_material(material_name: String) -> int:
	return materials.get(material_name, 0)

func get_all_materials() -> Dictionary:
	return materials.duplicate()

func reset_materials():
	for key in materials.keys():
		materials[key] = 0

func add_reward_item(item_id: String):
	if item_id not in reward_items:
		reward_items.append(item_id)

func clear_reward_items():
	reward_items.clear()

func clear_current_reward():
	current_reward_gold = 0
	current_reward_soul = 0
	current_reward_materials = {}
