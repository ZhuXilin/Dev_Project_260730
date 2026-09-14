extends Node

var _recipes : Dictionary = {}   # id -> RecipeData

func _ready():
	load_recipes()

func load_recipes():
	var path = Config.PATHS.RECIPE_DATA
	if not FileAccess.file_exists(path):
		push_error("配方数据文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("配方 JSON 解析失败")
		return
	_recipes.clear()
	for key in data:
		if data[key] is Dictionary:
			_recipes[key] = RecipeData.from_dict(key, data[key])
	print("成功加载 ", _recipes.size(), " 个配方")

func get_recipe(recipe_id: String) -> RecipeData:
	return _recipes.get(recipe_id)

func get_all_recipes() -> Array:
	var result : Array = []
	for key in _recipes:
		result.append(_recipes[key])
	return result

## 返回所有配方中输入数量的最大值（用于动态生成插槽）
func get_max_inputs() -> int:
	var max_n = 2
	for r in _recipes.values():
		if r.inputs.size() > max_n:
			max_n = r.inputs.size()
	return max_n

## 根据输入的防具 ID 列表匹配配方（顺序无关）
## 返回匹配的配方 ID，无匹配返回 ""
func match_recipe(input_ids: Array) -> String:
	if input_ids.is_empty():
		return ""
	var sorted_inputs = input_ids.duplicate()
	sorted_inputs.sort()

	for recipe_id in _recipes:
		var r : RecipeData = _recipes[recipe_id]
		if r.inputs.size() != sorted_inputs.size():
			continue
		var sorted_recipe = r.inputs.duplicate()
		sorted_recipe.sort()
		if sorted_recipe == sorted_inputs:
			return recipe_id
	return ""
