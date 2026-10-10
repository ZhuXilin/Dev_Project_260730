extends Node

signal shop_updated

var shop_items: Array = []
var reset_count: int = 0
var _context : EquipContext = null

var SHOP_SIZE : int = 9
var BASE_RESET_COST : int = 100
var RESET_STEP : int = 50
var SHOP_MAX_LEVEL : int = 5
var SHOP_UPGRADE_COSTS : Array = [200, 500, 1200, 2500, 5000]
var QUALITY_WEIGHTS : Array = []
var RARE_GUARANTEE_LEVEL : int = 3
var EPIC_GUARANTEE_LEVEL : int = 5


func _ready():
	reload_config()


func reload_config():
	var cfg : Dictionary = GameConfigManager.get_value("economy_config.json", "shop", {})
	SHOP_SIZE = int(cfg.get("size", 9))
	BASE_RESET_COST = int(cfg.get("base_reset_cost", 100))
	RESET_STEP = int(cfg.get("reset_step", 50))
	SHOP_MAX_LEVEL = int(cfg.get("max_level", 5))
	SHOP_UPGRADE_COSTS = cfg.get("upgrade_costs", [200, 500, 1200, 2500, 5000]).duplicate()
	QUALITY_WEIGHTS = cfg.get("quality_weights", []).duplicate()
	if QUALITY_WEIGHTS.is_empty():
		QUALITY_WEIGHTS = [{"common": 60, "rare": 30, "epic": 10, "legendary": 0}]
	RARE_GUARANTEE_LEVEL = int(cfg.get("rare_guarantee_level", 3))
	EPIC_GUARANTEE_LEVEL = int(cfg.get("epic_guarantee_level", 5))


# ============================================================
#  上下文
# ============================================================
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
	if _context: return _context.get_gold()
	return EconomyManager.get_temp_gold()


func _subtract_gold(amount: int) -> bool:
	if _context: return _context.subtract_gold(amount)
	if EconomyManager.get_temp_gold() < amount: return false
	EconomyManager.subtract_temp_gold(amount)
	return true


func is_arena_context() -> bool:
	return _context != null and _context.get_context_id() == "arena"


# ============================================================
#  刷新商店（批次 1）
# ============================================================
func get_reset_cost() -> int:
	return BASE_RESET_COST + reset_count * RESET_STEP


func get_reset_cost_text() -> String:
	if is_arena_context():
		return "%dG" % get_reset_cost()
	return "%d 魂火" % SoulFireManager.COST_SHOP_RESET


func reset_shop() -> int:
	var cost = get_reset_cost()
	if is_arena_context():
		if _get_gold() < cost: return -1
		if not _subtract_gold(cost): return -1
	else:
		if not SoulFireManager.spend(SoulFireManager.COST_SHOP_RESET): return -1
	reset_count += 1
	generate_shop_items()
	shop_updated.emit()
	return cost


# ============================================================
#  标签权重（批次 3）
# ============================================================
func _get_team_tag_weights() -> Dictionary:
	var weights : Dictionary = {}
	for ud in GameState.party:
		if ud.is_dead: continue
		for tag in ud.tags:
			weights[tag] = weights.get(tag, 0) + 3
	for tag in GameState.tag_purchase_count:
		weights[tag] = weights.get(tag, 0) + int(GameState.tag_purchase_count[tag])
	return weights


func _get_top_tags(weights : Dictionary, n : int = 2) -> Array:
	var arr : Array = []
	for k in weights:
		arr.append({"tag": k, "weight": weights[k]})
	arr.sort_custom(func(a, b): return a["weight"] > b["weight"])
	var result : Array = []
	for i in range(mini(n, arr.size())):
		result.append(arr[i]["tag"])
	return result


# ============================================================
#  生成商品（批次 3：标签权重）
# ============================================================
func generate_shop_items():
	shop_items.clear()
	var lv : int = _get_shop_level()
	var weights : Dictionary = QUALITY_WEIGHTS[clampi(lv, 0, SHOP_MAX_LEVEL)]

	var tag_weights : Dictionary = _get_team_tag_weights()
	var top_tags : Array = _get_top_tags(tag_weights, 2)

	var all_pools : Dictionary = {"common": [], "rare": [], "epic": [], "legendary": []}
	var tag_pools : Dictionary = {}
	for tag in top_tags:
		tag_pools[tag] = {"common": [], "rare": [], "epic": [], "legendary": []}

	for item_id in _get_pool_ids():
		var data : ItemData = ItemManager.get_item_data(item_id)
		if not data: continue
		if data.type != "armor": continue
		if data.price <= 0: continue
		var q : String = data.quality
		if not all_pools.has(q): continue
		all_pools[q].append(data)
		for tag in data.tags:
			if tag_pools.has(tag):
				tag_pools[tag][q].append(data)

	var total_weight : int = 0
	for q in weights:
		total_weight += int(weights[q])
	if total_weight <= 0:
		total_weight = 100

	var order : Array = ["common", "rare", "epic", "legendary"]

	for i in range(SHOP_SIZE):
		var quality : String = "common"
		var roll : int = randi() % total_weight
		var acc : int = 0
		for q in order:
			acc += int(weights[q])
			if roll < acc:
				quality = q
				break

		if lv >= EPIC_GUARANTEE_LEVEL and quality == "common": quality = "epic"
		elif lv >= RARE_GUARANTEE_LEVEL and quality == "common": quality = "rare"

		var use_tag_pool : bool = (randf() < 0.8) and not top_tags.is_empty()
		var pool : Array = []

		if use_tag_pool:
			for tag in top_tags:
				pool.append_array(tag_pools[tag].get(quality, []))
			if pool.is_empty(): use_tag_pool = false

		if not use_tag_pool:
			pool = all_pools.get(quality, [])

		var target_idx : int = order.find(quality)
		while pool.is_empty() and target_idx > 0:
			target_idx -= 1
			pool = all_pools.get(order[target_idx], [])
		if pool.is_empty():
			shop_items.append(null)
			continue

		var pick : ItemData = pool[randi() % pool.size()]
		shop_items.append({"item_data": pick, "price": pick.price})


# ============================================================
#  购买（批次 3：累加标签）
# ============================================================
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

	# ★ 累加标签
	for tag in item_data.tags:
		GameState.tag_purchase_count[tag] = GameState.tag_purchase_count.get(tag, 0) + 1

	shop_items[index] = null
	shop_updated.emit()
	return {"success": true, "item_data": item_data, "price": price, "index": index}


func get_shop_items() -> Array: return shop_items.duplicate()

func is_shop_empty() -> bool:
	for entry in shop_items:
		if entry != null: return false
	return true


# ============================================================
#  商店升级
# ============================================================
func get_shop_level() -> int: return _get_shop_level()

func get_upgrade_cost() -> int:
	var lv : int = _get_shop_level()
	if lv >= SHOP_MAX_LEVEL: return -1
	if lv >= SHOP_UPGRADE_COSTS.size(): return -1
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
	if _context: return _context.get_shop_level()
	return 0

func _set_shop_level(level: int) -> void:
	if _context: _context.set_shop_level(level)
