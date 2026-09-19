extends Node

const COST_PER_CLASS : int = 800

var _classes : Dictionary = {}
var _by_unit : Dictionary = {}

func _ready():
	load_classes()

func load_classes():
	_classes.clear()
	_by_unit.clear()
	var all_units : Dictionary = UnitDataManager.get_all_unit_data()
	for unit_key in all_units:
		var unit_dict : Dictionary = all_units[unit_key]
		var adv_dict : Variant = unit_dict.get("advanced_class", null)
		if not (adv_dict is Dictionary) or (adv_dict as Dictionary).is_empty():
			continue
		var adv : AdvancedClassData = AdvancedClassData.from_dict(adv_dict, unit_key)
		if adv.id == "":
			continue
		_classes[adv.id] = adv
		_by_unit[unit_key] = adv
	print("成功加载 ", _classes.size(), " 个进阶职业（覆盖 ", _by_unit.size(), " 个基础单位）")

func get_class_data(class_id: String) -> AdvancedClassData:
	return _classes.get(class_id)

func get_class_for_unit(unit_type: String) -> AdvancedClassData:
	var key : String = UnitDataManager.normalize_unit_key(unit_type)
	return _by_unit.get(key, null)

func get_cost_per_class() -> int:
	return COST_PER_CLASS

func get_display_name(class_id: String) -> String:
	var c = get_class_data(class_id)
	return c.name if c else class_id
