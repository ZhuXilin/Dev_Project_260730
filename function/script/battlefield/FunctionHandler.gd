class_name FunctionHandler
extends Node

var _bf : Node2D

func _init(bf: Node2D):
	_bf = bf


func apply_map_functions(team: int) -> void:
	var units_to_remove = []
	for unit in UnitManager.unit_list:
		if unit.unit_stats.team_id == team and unit.hit_points > 0:
			var cell = unit.grid_cell
			if _bf.map_functions.has(cell):
				var func_config = _bf.map_functions[cell]
				var event_id = func_config.get("event_id", "")
				if event_id == "":
					continue
				if not event_id.begins_with("hp_"):
					continue
				if EventManager.is_event_completed(event_id):
					continue
				if func_config.get("triggered", false):
					if func_config.get("triggered_by_unit") == unit:
						continue
				func_config["triggered"] = true
				func_config["triggered_by_unit"] = unit
				await EventManager.trigger_event(event_id, unit)
				if EventManager.is_event_completed(event_id):
					func_config["triggered"] = true
				else:
					func_config["triggered"] = false
					func_config["triggered_by_unit"] = null
				if unit.hit_points <= 0:
					units_to_remove.append(unit)

	for unit in units_to_remove:
		print(unit.unit_stats.unit_name + " 因陷阱死亡！")
		UnitManager.unregister_unit(unit)
		unit.queue_free()

	if units_to_remove.size() > 0:
		TurnManager.check_victory()

	print("=== 应用功能格效果完成 ===")


func on_dialogue_check(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	if unit.unit_stats.team_id != 0 or unit.hit_points <= 0:
		return

	var cell = unit.grid_cell
	if not _bf.map_functions.has(cell):
		return

	var func_config = _bf.map_functions[cell]

	if func_config.get("triggered", false):
		var trigger_unit = func_config.get("triggered_by_unit", null)
		if trigger_unit == unit:
			return
		else:
			func_config["triggered"] = false
			func_config["triggered_by_unit"] = null

	var event_id = func_config.get("event_id", "")
	if event_id == "":
		return

	if EventManager.is_event_completed(event_id):
		return

	var event_def = EventManager.get_event(event_id)
	if not event_def.is_empty():
		for action in event_def.get("actions", []):
			if action.get("type") in ["heal", "damage"]:
				print("HP 事件将在回合开始时触发，跳过待机触发: ", event_id)
				return

	func_config["triggered"] = true
	func_config["triggered_by_unit"] = unit

	await EventManager.trigger_event(event_id, unit)

	if EventManager.is_event_completed(event_id):
		func_config["triggered"] = true
	else:
		func_config["triggered"] = false
		func_config["triggered_by_unit"] = null


func clear_function_trigger(unit: Unit) -> void:
	if not is_instance_valid(unit):
		return
	var old_cell = unit.previous_grid_cell
	if _bf.map_functions.has(old_cell):
		var cfg = _bf.map_functions[old_cell]
		if cfg.get("triggered_by_unit") == unit:
			cfg["triggered"] = false
			cfg["triggered_by_unit"] = null
