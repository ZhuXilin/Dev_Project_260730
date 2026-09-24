extends Node

signal shop_updated

var shop_items: Array = []
var reset_count: int = 0
var _context : EquipContext = null

const SHOP_SIZE = 9
const BASE_RESET_COST = 100
const RESET_STEP = 50

# ---- 商店升级（6 级：Lv0-Lv5）----
const SHOP_MAX_LEVEL : int = 5
const SHOP_UPGRADE_COSTS : Array = [200, 500, 1200, 2500, 5000]

# 品质权重（按商店等级）：common / rare / epic / legendary
const QUALITY_WEIGHTS : Array = [
	{"common": 60, "rare": 30, "epic": 10, "legendary": 0},   # Lv0
	{"common": 45, "rare": 35, "epic": 18, "legendary": 2},   # Lv1
	{"common": 30, "rare": 40, "epic": 25, "legendary": 5},   # Lv2
	{"common": 15, "rare": 35, "epic": 40, "legendary": 10},  # Lv3（保底 rare）
	{"common": 5,  "rare": 25, "epic": 50, "legendary": 20},  # Lv4（保底 rare）
	{"common": 0,  "rare": 15, "epic": 50, "legendary": 35},  # Lv5（保底 epic）
]

const RARE_GUARANTEE_LEVEL : int = 3
const EPIC_GUARANTEE_LEVEL : int = 5


func set_context(ctx: EquipContext):
	_context = ctx


func _get_pool_ids() -> Array:
	if _context and _context.get_context_id() == "arena":
		return ItemManager.get_all_item_ids()
	var pool : Array = Globals.unlocked_items.duplicate()
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
	var lv : int = _get_shop_level()
	var weights : Dictionary = QUALITY_WEIGHTS[clampi(lv, 0, SHOP_MAX_LEVEL)]

	# 收集各品质防具池
	var pools : Dictionary = {"common": [], "rare": [], "epic": [], "legendary": []}
	for item_id in _get_pool_ids():
		var data : ItemData = ItemManager.get_item_data(item_id)
		if not data: continue
		if data.type != "armor": continue
		if data.price <= 0: continue
		var q : String = data.quality
		if not pools.has(q): continue
		pools[q].append(data)

	var total_weight : int = 0
	for q in weights:
		total_weight += int(weights[q])
	if total_weight <= 0:
		total_weight = 100

	var order : Array = ["common", "rare", "epic", "legendary"]

	for i in range(SHOP_SIZE):
		# 按权重抽品质
		var quality : String = "common"
		var roll : int = randi() % total_weight
		var acc : int = 0
		for q in order:
			acc += int(weights[q])
			if roll < acc:
				quality = q
				break

		# ★ 保底
		if lv >= EPIC_GUARANTEE_LEVEL and quality == "common":
			quality = "epic"
		elif lv >= RARE_GUARANTEE_LEVEL and quality == "common":
			quality = "rare"

		# 池子空则降级
		var target_idx : int = order.find(quality)
		var pool : Array = pools.get(quality, [])
		while pool.is_empty() and target_idx > 0:
			target_idx -= 1
			pool = pools.get(order[target_idx], [])
		if pool.is_empty():
			shop_items.append(null)
			continue
		var pick : ItemData = pool[randi() % pool.size()]
		shop_items.append({"item_data": pick, "price": pick.price})


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


# ============================================================
#  商店升级
# ============================================================
func get_shop_level() -> int:
	return _get_shop_level()


func get_upgrade_cost() -> int:
	var lv : int = _get_shop_level()
	if lv >= SHOP_MAX_LEVEL:
		return -1
	return SHOP_UPGRADE_COSTS[lv]


func can_upgrade_shop() -> bool:
	var cost : int = get_upgrade_cost()
	if cost < 0: return false
	return _get_gold() >= cost


func upgrade_shop() -> bool:
	if not can_upgrade_shop(): return false
	var cost : int = get_upgrade_cost()
	if not _subtract_gold(cost): return false
	_set_shop_level(_get_shop_level() + 1)
	generate_shop_items()
	shop_updated.emit()
	return true


func _get_shop_level() -> int:
	if _context:
		return _context.get_shop_level()
	return 0


func _set_shop_level(level: int) -> void:
	if _context:
		_context.set_shop_level(level)
