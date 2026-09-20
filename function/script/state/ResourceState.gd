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
#  防具配方解锁（铁砧酒馆）
# ============================================================
var unlocked_recipes : Array = []

# ---- 已阅故事（酒馆） ----
var unlocked_stories : Array = []

# ---- 斗技场词条经验（每个单位独立） ----
var talent_exp : Dictionary = {}

# ---- 斗技场目标词条（每个单位一个） ----
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
#  本轮基线（用于结算显示）
# ============================================================
var cycle_start_soul : int = 0
var cycle_start_materials : Dictionary = {}

# ============================================================
#  单次奖励记录（用于结算界面）
# ============================================================
var reward_items : Array = []
var current_reward_gold : int = 0
var current_reward_soul : int = 0
var current_reward_materials : Dictionary = {}

# ============================================================
#  精炼配方（炼金坊）
# ============================================================
var unlocked_refine_recipes : Array = []   # 已解锁的精炼配方 ID
var refined_items : Dictionary = {}         # { refine_id: count }

# ============================================================
#  方法（纯数据操作，不调用任何 autoload）
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
