class_name ResourceState
extends RefCounted

# ---- 永久 / 临时资源 ----
var soul : int = 0
var temp_soul : int = 0
var temp_gold : int = 0

# ---- 材料 ----
var materials : Dictionary = {
	"粗铁": 0,
	"精钢": 0,
	"秘银": 0,
	"龙鳞": 0
}

# ---- 防具配方解锁（铁砧酒馆） ----
var unlocked_recipes : Array = []

# ---- 本轮基线（用于结算显示） ----
var cycle_start_soul : int = 0
var cycle_start_materials : Dictionary = {}

# ---- 单次奖励记录（用于结算界面） ----
var reward_items : Array = []
var current_reward_gold : int = 0
var current_reward_soul : int = 0
var current_reward_materials : Dictionary = {}

func add_material(material_name: String, amount: int):
	if materials.has(material_name):
		materials[material_name] += amount
	else:
		materials[material_name] = amount
	print("材料增加: ", material_name, " +", amount, " (当前: ", materials[material_name], ")")
	SaveManager.auto_save()

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
