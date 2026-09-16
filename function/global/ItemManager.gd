extends Node

var _item_db : Dictionary = {}   # id -> ItemData

func _ready():
	load_items()

func load_items():
	var path = Config.PATHS.ITEM_DATA
	if not FileAccess.file_exists(path):
		push_error("道具数据文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("JSON 解析失败或格式错误")
		return
	_item_db.clear()
	for key in data:
		var dict = data[key]
		var item = ItemData.new()
		item.id = dict.get("id", key)
		item.name = dict.get("name", "")
		item.type = dict.get("type", "")
		item.use_type = dict.get("use_type", "equipment")
		# 图标处理
		if dict.has("icon") and ResourceLoader.exists(dict.icon):
			item.icon = load(dict.icon)
		item.description = dict.get("description", "")
		item.category = dict.get("category", "")
		item.equipment_slot = dict.get("equipment_slot", "")
		item.price = dict.get("price", 0)
		
		# 新字段
		item.quality = dict.get("quality", "common")
		item.attack_style = dict.get("attack_style", "standard")
		item.base_attack = dict.get("base_attack", 0)
		item.attack_range = dict.get("attack_range", 1)
		item.min_attack_range = dict.get("min_attack_range", 1)
		item.modifier = dict.get("modifier", {})
		item.armor_type = dict.get("armor_type", "medium")
		item.defense = dict.get("defense", 0)
		item.slot_count = dict.get("slot_count", 1)
		item.unlock_cost = dict.get("unlock_cost", {})
		item.craft_cost = dict.get("craft_cost", 0)
		item.heavy_attack = dict.get("heavy_attack", {})
		item.magic_attack = dict.get("magic_attack", {})
		item.heal_effect = dict.get("heal_effect", {})
		item.legendary_effect = dict.get("legendary_effect", "")
		
		# 保留 stats / use_effect 字段（ItemData 类定义需要，实际不再使用）
		item.stats = dict.get("stats", {})
		item.use_effect = dict.get("use_effect", {})
		
		_item_db[item.id] = item
	print("成功加载 ", _item_db.size(), " 个道具")

func get_item_data(item_id: String) -> ItemData:
	return _item_db.get(item_id)

# ============================================================
#  分类获取（用于道具图鉴）
# ============================================================

func get_items_by_type(item_type: String) -> Array[ItemData]:
	var result = []
	for item_id in _item_db:
		var data = _item_db[item_id]
		if data.type == item_type and Globals.is_item_unlocked(item_id):
			result.append(data)
	return result

func get_weapons() -> Array[ItemData]:
	return get_items_by_type("weapon")

func get_armors() -> Array[ItemData]:
	return get_items_by_type("armor")

func get_relics() -> Array[ItemData]:
	return get_items_by_type("relic")

func get_all_item_ids() -> Array:
	return _item_db.keys()
