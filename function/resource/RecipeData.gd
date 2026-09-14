class_name RecipeData
extends Resource

@export var id: String = ""
@export var inputs: Array = []          # [String]
@export var unlock_cost: Dictionary = {}  # { 材料名: count }

static func from_dict(recipe_id: String, d: Dictionary) -> RecipeData:
	var r = RecipeData.new()
	r.id = recipe_id
	var raw_inputs = d.get("inputs", [])
	for i in raw_inputs:
		if i is String:
			r.inputs.append(i)
	r.unlock_cost = d.get("unlock_cost", {})
	return r
