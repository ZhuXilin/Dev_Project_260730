extends Node

signal shop_updated

# ---- 商店状态 ----
var shop_items: Array = []   # 每个元素为 { "item_data": ItemData, "price": int } 或 null
var reset_count: int = 0

# ---- 常量 ----
const SHOP_SIZE = 6
const BASE_RESET_COST = 100
const RESET_STEP = 5

# ---- 获取重置费用 ----
func get_reset_cost() -> int:
	return BASE_RESET_COST + reset_count * RESET_STEP

# ---- 重置商店 ----
func reset_shop() -> int:
	var cost = get_reset_cost()
	if EconomyManager.get_temp_gold() < cost:
		return -1
	EconomyManager.subtract_temp_gold(cost)
	reset_count += 1
	generate_shop_items()
	shop_updated.emit()
	return cost

# ---- 生成随机商店物品 ----
func generate_shop_items():
	shop_items.clear()
	var pool = []
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["weapon", "armor"] and data.price > 0:
			pool.append({"item_data": data, "price": data.price})
	for relic_id in RelicManager.get_unlocked_relics():
		var relic_dict = RelicManager.get_relic_data(relic_id)
		if not relic_dict.is_empty() and relic_dict.has("price"):
			var price = relic_dict.get("price", 0)
			if price > 0:
				var wrapper = ItemData.new()
				wrapper.id = relic_id
				wrapper.name = relic_dict.get("name", "未知遗物")
				wrapper.type = "relic"
				wrapper.price = price
				var icon_path = relic_dict.get("icon", "")
				if icon_path != "" and ResourceLoader.exists(icon_path):
					wrapper.icon = load(icon_path)
				pool.append({"item_data": wrapper, "price": price})
	pool.shuffle()
	var selected = pool.slice(0, SHOP_SIZE)
	while selected.size() < SHOP_SIZE:
		selected.append(null)
	shop_items = selected

# ---- 购买商品 ----
func buy_shop_item(index: int) -> Dictionary:
	if index < 0 or index >= shop_items.size():
		return {"success": false, "reason": "invalid_index"}
	var entry = shop_items[index]
	if entry == null:
		return {"success": false, "reason": "empty_slot"}
	var item_data = entry["item_data"]
	var price = entry["price"]
	if EconomyManager.get_temp_gold() < price:
		return {"success": false, "reason": "not_enough_gold"}
	EconomyManager.subtract_temp_gold(price)
	shop_items[index] = null
	shop_updated.emit()
	return {"success": true, "item_data": item_data, "price": price, "index": index}

# ---- 获取商店物品列表 ----
func get_shop_items() -> Array:
	return shop_items.duplicate()

# ---- 检查商店是否为空 ----
func is_shop_empty() -> bool:
	for entry in shop_items:
		if entry != null:
			return false
	return true
