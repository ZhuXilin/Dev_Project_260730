extends Node

signal shop_updated

var shop_items: Array = []
var reset_count: int = 0
var _context : EquipContext = null

const SHOP_SIZE = 6
const BASE_RESET_COST = 100
const RESET_STEP = 5
const LEGENDARY_CHANCE : float = 0.05

func set_context(ctx: EquipContext):
	_context = ctx

# ---- 池子来源 ----
func _get_pool_ids() -> Array:
	# ★ Arena：全池（含未解锁，可提前体验）
	if _context and _context.get_context_id() == "arena":
		return ItemManager.get_all_item_ids()

	# ★ 主游戏：只卖已解锁
	var pool : Array = Globals.unlocked_items.duplicate()
	# 合并防具解锁（防具走 unlocked_recipes）
	for recipe_id in GameState.unlocked_recipes:
		if recipe_id not in pool:
			pool.append(recipe_id)
	return pool

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
	for item_id in _get_pool_ids():
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["weapon", "armor"] and data.price > 0:
			pool.append({"item_data": data, "price": data.price})
	pool.shuffle()
	var selected = pool.slice(0, SHOP_SIZE)

	# ★ 5% 概率出 legendary
	if randf() < LEGENDARY_CHANCE:
		var legendary_pool : Array = []
		for item_id in ItemManager.get_all_item_ids():
			var data = ItemManager.get_item_data(item_id)
			if data and data.type in ["weapon", "armor"] and data.quality == "legendary" and data.price > 0:
				legendary_pool.append({"item_data": data, "price": data.price})
		if legendary_pool.size() > 0:
			var pick = legendary_pool[randi() % legendary_pool.size()]
			selected.insert(0, pick)
			print("[Shop] ★ 稀有上架：", pick["item_data"].name)

	while selected.size() < SHOP_SIZE:
		selected.append(null)
	shop_items = selected.slice(0, SHOP_SIZE)

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
