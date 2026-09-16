extends Node

var _recipes : Dictionary = {}

func _ready():
	load_recipes()


func load_recipes():
	var path = Config.PATHS.REFINE_RECIPES
	if not FileAccess.file_exists(path):
		push_error("精炼配方文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("精炼配方 JSON 解析失败")
		return
	_recipes = data
	print("成功加载 ", _recipes.size(), " 个精炼配方")


func get_recipe(refine_id: String) -> Dictionary:
	return _recipes.get(refine_id, {})


func get_all_recipes() -> Array:
	var result : Array = []
	for key in _recipes:
		result.append(_recipes[key])
	return result


func get_all_ids() -> Array:
	var ids : Array = []
	for key in _recipes:
		ids.append(key)
	return ids


# ============================================================
#  解锁
# ============================================================
func is_recipe_unlocked(refine_id: String) -> bool:
	return refine_id in GameState.unlocked_refine_recipes


func can_unlock_recipe(refine_id: String) -> bool:
	var recipe = get_recipe(refine_id)
	if recipe.is_empty():
		return false
	var unlock_cost = recipe.get("unlock_cost", {})
	for mat in unlock_cost:
		if GameState.get_material(mat) < unlock_cost[mat]:
			return false
	return true


func unlock_recipe(refine_id: String) -> bool:
	if is_recipe_unlocked(refine_id):
		return false
	if not can_unlock_recipe(refine_id):
		return false
	var recipe = get_recipe(refine_id)
	var unlock_cost = recipe.get("unlock_cost", {})
	for mat in unlock_cost:
		GameState.materials[mat] -= unlock_cost[mat]
	GameState.unlocked_refine_recipes.append(refine_id)
	SaveManager.auto_save()
	print("解锁精炼配方: ", refine_id)
	return true


# ============================================================
#  精炼
# ============================================================
func can_craft(refine_id: String) -> bool:
	if not is_recipe_unlocked(refine_id):
		return false
	var recipe = get_recipe(refine_id)
	if recipe.is_empty():
		return false
	var cost = recipe.get("craft_cost", {})
	for mat in cost:
		if GameState.get_material(mat) < cost[mat]:
			return false
	return true


func craft(refine_id: String) -> bool:
	if not can_craft(refine_id):
		return false
	var recipe = get_recipe(refine_id)
	var cost = recipe.get("craft_cost", {})
	for mat in cost:
		GameState.materials[mat] -= cost[mat]
	GameState.refined_items[refine_id] = GameState.refined_items.get(refine_id, 0) + 1
	SaveManager.auto_save()
	print("精炼成功: ", refine_id)
	return true


# ============================================================
#  查询
# ============================================================
func get_count(refine_id: String) -> int:
	return int(GameState.refined_items.get(refine_id, 0))


func get_effect(refine_id: String) -> Dictionary:
	var recipe = get_recipe(refine_id)
	return recipe.get("effect", {})
