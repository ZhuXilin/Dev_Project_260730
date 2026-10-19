extends Node

var _classes : Dictionary = {}         # class_id → AdvancedClassData
var _by_unit : Dictionary = {}         # unit_key → Array[AdvancedClassData]


func _ready():
	load_classes()


func load_classes():
	_classes.clear()
	_by_unit.clear()
	var all_units : Dictionary = UnitDataManager.get_all_unit_data()
	for unit_key in all_units:
		var unit_dict : Dictionary = all_units[unit_key]
		var branches : Variant = unit_dict.get("advanced_branches", [])
		if not (branches is Array) or (branches as Array).is_empty():
			continue
		var branch_list : Array = []
		for b in branches:
			if not (b is Dictionary):
				continue
			var adv : AdvancedClassData = AdvancedClassData.from_dict(b, unit_key)
			if adv.id == "":
				continue
			_classes[adv.id] = adv
			branch_list.append(adv)
		if not branch_list.is_empty():
			_by_unit[unit_key] = branch_list
	print("成功加载 ", _classes.size(), " 个进阶职业（覆盖 ", _by_unit.size(), " 个基础单位）")


func get_class_data(class_id: String) -> AdvancedClassData:
	return _classes.get(class_id)


## 返回该单位的可选分支（用于 HeroShrine 二选一 UI）
## 隐藏分支：只有剧情解锁（GameState.npc_dialogue_flags 中含对应 flag）才出现
func get_branches_for_unit(unit_type: String) -> Array:
	var key : String = UnitDataManager.normalize_unit_key(unit_type)
	var all_branches : Array = (_by_unit.get(key, []) as Array)
	var result : Array = []
	for adv in all_branches:
		if adv == null:
			continue
		if adv.hidden and not _is_branch_unlocked(adv.id):
			continue
		result.append(adv)
	return result


## 兼容旧接口：返回第一个分支（无分支时返回 null）
func get_class_for_unit(unit_type: String) -> AdvancedClassData:
	var branches : Array = get_branches_for_unit(unit_type)
	return branches[0] if not branches.is_empty() else null


func get_display_name(class_id: String) -> String:
	var c = get_class_data(class_id)
	return c.name if c else class_id


# ============================================================
#  隐藏分支解锁检查
# ============================================================
func _is_branch_unlocked(branch_id: String) -> bool:
	if branch_id == "":
		return false
	var suffix : String = "_" + branch_id
	for f in GameState.npc_dialogue_flags:
		if not (f is String):
			continue
		var s : String = f
		if s.begins_with("unlocked_") and s.ends_with(suffix):
			return true
	return false
