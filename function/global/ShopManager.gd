extends Node

signal shop_updated

# ---- 商店状态 ----
var shop_items: Array = []   # 每个元素为 { "item_data": ItemData, "price": int } 或 null
var reset_count: int = 0

# ---- 常量 ----
const SHOP_SIZE = 6
const BASE_RESET_COST = 10
const RESET_STEP = 5

# ---- 获取重置费用 ----
func get_reset_cost() -> int:
	return BASE_RESET_COST + reset_count * RESET_STEP

# ---- 重置商店 ----
func reset_shop() -> int:
	var cost = get_reset_cost()
	if GameState.temp_gold < cost:
		print("ShopManager: 金币不足，需要 ", cost, "，当前 ", GameState.temp_gold)
		return -1   # 金币不足
	
	GameState.temp_gold -= cost
	reset_count += 1
	generate_shop_items()
	shop_updated.emit()
	print("ShopManager: 商店重置，花费 ", cost, "，剩余金币 ", GameState.temp_gold)
	return cost

# ---- 生成随机商店物品 ----
func generate_shop_items():
	shop_items.clear()
	
	var pool = []
	
	# 1. 收集武器和防具（ItemData 对象）
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["weapon", "armor"] and data.price > 0:
			pool.append({
				"item_data": data,
				"price": data.price
			})
	
	# 2. 收集遗物（从 RelicManager 获取字典，然后包装成 ItemData）
	for relic_id in RelicManager.get_unlocked_relics():
		var relic_dict = RelicManager.get_relic_data(relic_id)
		if not relic_dict.is_empty() and relic_dict.has("price"):
			var price = relic_dict.get("price", 0)
			if price > 0:
				var wrapper = ItemData.new()
				wrapper.id = relic_id
				wrapper.name = relic_dict.get("name", "未知遗物")
				var icon_path = relic_dict.get("icon", "")
				if icon_path != "" and ResourceLoader.exists(icon_path):
					wrapper.icon = load(icon_path)
				wrapper.type = "relic"
				wrapper.description = relic_dict.get("description", "")
				wrapper.price = price
				wrapper.stats = relic_dict.get("stats", {})
				pool.append({
					"item_data": wrapper,
					"price": price
				})
	
	# 3. 随机选取
	pool.shuffle()
	var selected = pool.slice(0, SHOP_SIZE)
	
	# 4. 补齐空位
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
	
	# 检查金币
	if GameState.temp_gold < price:
		return {"success": false, "reason": "not_enough_gold"}
	
	# 扣除金币
	GameState.temp_gold -= price
	
	# 从商店移除
	shop_items[index] = null
	shop_updated.emit()
	
	return {
		"success": true,
		"item_data": item_data,
		"price": price,
		"index": index
	}

# ---- 获取商店物品列表 ----
func get_shop_items() -> Array:
	return shop_items.duplicate()

# ---- 检查商店是否为空 ----
func is_shop_empty() -> bool:
	for entry in shop_items:
		if entry != null:
			return false
	return true

# ---- 获取有效物品池大小（用于调试） ----
func get_pool_size() -> int:
	var pool = []
	for item_id in Globals.unlocked_items:
		var data = ItemManager.get_item_data(item_id)
		if data and data.type in ["weapon", "armor"] and data.price > 0:
			pool.append(data)
	for relic_id in RelicManager.get_unlocked_relics():
		var data = RelicManager.get_relic_data(relic_id)
		if not data.is_empty() and data.get("price", 0) > 0:
			pool.append(data)
	return pool.size()
