extends Node

signal shop_updated

var shop_items: Array = []
var reset_count: int = 0
var _context : EquipContext = null

const SHOP_SIZE = 6
const BASE_RESET_COST = 100
const RESET_STEP = 5

func set_context(ctx: EquipContext):
	_context = ctx

func _get_gold() -> int:
	if _context:
		return _context.get_gold()
	return EconomyManager.get_temp_gold()

func _subtract_gold(amount: int) -> bool:
	if _context:
		return _context.subtract_gold(amount)
	if EconomyManager.get_temp_gold() < amount:
		return false
	EconomyManager.subtract_temp_gold(amount)
	return true

func get_reset_cost() -> int:
	return BASE_RESET_COST + reset_count * RESET_STEP

func reset_shop() -> int:
	var cost = get_reset_cost()
	if _get_gold() < cost:
		return -1
	if not _subtract_gold(cost):
		return -1
	reset_count += 1
	generate_shop_items()
	shop_updated.emit()
	return cost

func generate_shop_items():
	shop_items.clear()
	var pool = []
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["weapon", "armor"] and data.price > 0:
			pool.append({"item_data": data, "price": data.price})
	pool.shuffle()
	var selected = pool.slice(0, SHOP_SIZE)
	while selected.size() < SHOP_SIZE:
		selected.append(null)
	shop_items = selected

func buy_shop_item(index: int) -> Dictionary:
	if index < 0 or index >= shop_items.size():
		return {"success": false, "reason": "invalid_index"}
	var entry = shop_items[index]
	if entry == null:
		return {"success": false, "reason": "empty_slot"}
	var item_data = entry["item_data"]
	var price = entry["price"]
	if _get_gold() < price:
		return {"success": false, "reason": "not_enough_gold"}
	if not _subtract_gold(price):
		return {"success": false, "reason": "not_enough_gold"}
	shop_items[index] = null
	shop_updated.emit()
	return {"success": true, "item_data": item_data, "price": price, "index": index}

func get_shop_items() -> Array:
	return shop_items.duplicate()

func is_shop_empty() -> bool:
	for entry in shop_items:
		if entry != null:
			return false
	return true
