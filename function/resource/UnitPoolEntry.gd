extends Resource
class_name UnitPoolEntry

# 基础单位索引
@export var unit_idx: int = 0:
	set(value):
		if unit_idx == value: return
		unit_idx = maxi(0, value)
		advanced_class_idx = 0
		if Engine.is_editor_hint():
			# ★ 核心修复：使用延迟刷新，防止在 Inspector 内联数组时引发死锁崩溃
			call_deferred("_notify_changed")

# 进阶职业索引（0 = 无）
@export var advanced_class_idx: int = 0

func _notify_changed():
	if is_instance_valid(self):
		notify_property_list_changed()

var unit_key: String:
	get:
		var keys = UnitDataManager.get_all_unit_ids()
		if unit_idx >= 0 and unit_idx < keys.size():
			return keys[unit_idx]
		return "swordsman"

var advanced_class_id: String:
	get:
		if advanced_class_idx <= 0: return ""
		var branches = _get_branches()
		var i = advanced_class_idx - 1
		if i >= 0 and i < branches.size():
			return str(branches[i].get("id", ""))
		return ""

func _get_branches() -> Array:
	var ud = UnitDataManager.get_unit_data(unit_key)
	if ud.is_empty(): return []
	var raw = ud.get("advanced_branches", [])
	var res = []
	for b in raw:
		if b is Dictionary:
			res.append(b)
	return res

func _validate_property(property: Dictionary) -> void:
	if property.name == "unit_idx":
		var items = []
		var keys = UnitDataManager.get_all_unit_ids()
		for k in keys:
			items.append(UnitDataManager.get_display_name(k))
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)
	elif property.name == "advanced_class_idx":
		var items = ["（无）"]
		var branches = _get_branches()
		for b in branches:
			items.append(str(b.get("name", b.get("id", ""))))
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(items)
