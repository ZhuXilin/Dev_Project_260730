extends Resource
class_name ItemInstance

@export var item_id: String
@export var count: int = 1
@export var upgrade_level: int = 0
@export var affixes: Array = []

# ============================================================
#  ★ 新增：本实例的具体方向（Direction.Value 枚举值）
#  0 = 无箭头 / 1,2,4,8 = 单箭头 / 5,10 = 双直线 / 16,32 = 斜线
#  重 roll 时改这个字段，不动 ItemData
# ============================================================
@export var direction: int = 0


func has_affix(affix_type: String) -> bool:
	for a in affixes:
		var aid : String = a.get("id", "")
		var d : Dictionary = AffixManager.get_affix(aid)
		if d.get("type", "") == affix_type:
			return true
	return false


func get_affix_value(affix_type: String) -> int:
	var total : int = 0
	for a in affixes:
		var aid : String = a.get("id", "")
		var d : Dictionary = AffixManager.get_affix(aid)
		if d.get("type", "") == affix_type:
			total += int(a.get("value", 0))
	return total


func get_affix_value_float(affix_type: String) -> float:
	return float(get_affix_value(affix_type)) / 100.0


func get_sell_price() -> int:
	var data : ItemData = ItemManager.get_item_data(item_id)
	if not data:
		return 0
	if data.no_sell:
		return 0
	var base : int = int(data.price)
	if base <= 0:
		return 0
	var sell : int = int(base * 0.5)
	sell += affixes.size() * 50
	sell += upgrade_level * 30
	return maxi(sell, 10)


func duplicate_instance() -> ItemInstance:
	var inst := ItemInstance.new()
	inst.item_id = item_id
	inst.count = count
	inst.upgrade_level = upgrade_level
	inst.affixes = affixes.duplicate(true)
	inst.direction = direction
	return inst


## 便捷：本实例的箭头类型（"none"/"single"/"double"/"diagonal"）
func get_arrow_type() -> String:
	return Direction.get_arrow_type_name(direction)


func has_arrow() -> bool:
	return direction != Direction.Value.NONE


func is_double_arrow() -> bool:
	return Direction.is_double_arrow(direction)
