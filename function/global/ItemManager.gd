extends Node

signal item_acquired(item_id, count)
signal item_used(item_id, unit)

var _item_db : Dictionary = {}   # id -> ItemData
var _inventory : Dictionary = {} # id -> count (仅消耗品计数，无限型为1表示拥有)

func _ready():
	load_items()
	load_inventory()
	# ---- 若库存为空，从 Globals 加载默认道具 ----
	if _inventory.is_empty() and Globals.default_items:
		var defaults = Globals.default_items
		for item_id in defaults:
			add_item(item_id, defaults[item_id])
		print("已从默认配置加载道具")

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
		item.id = dict.get("id", key)  # 如果id缺失，用key代替
		item.name = dict.get("name", "")
		item.type = dict.get("type", "")
		item.use_type = dict.get("use_type", "consumable")
		item.use_effect = dict.get("use_effect", {})
		if dict.has("icon") and ResourceLoader.exists(dict.icon):
			item.icon = load(dict.icon)
		else:
			item.icon = null
		item.effect = dict.get("effect", {})
		item.description = dict.get("description", "")
		item.category = dict.get("category", "")
		# 武器专用字段
		item.weapon_attack = dict.get("weapon_attack", 0)
		item.weapon_magic_attack = dict.get("weapon_magic_attack", 0)
		item.weapon_heal_amount = dict.get("weapon_heal_amount", 0)
		item.weapon_attack_range = dict.get("weapon_attack_range", 1)
		item.weapon_min_attack_range = dict.get("weapon_min_attack_range", 1)
		item.weapon_type = dict.get("weapon_type", -1)
		_item_db[item.id] = item
	print("成功加载 ", _item_db.size(), " 个道具")

func get_item_data(item_id: String) -> ItemData:
	return _item_db.get(item_id)

func add_item(item_id: String, count: int = 1):
	if not _item_db.has(item_id):
		return
	var data = _item_db[item_id]
	if data.use_type == "infinite":
		_inventory[item_id] = 1
	else:
		_inventory[item_id] = _inventory.get(item_id, 0) + count
	item_acquired.emit(item_id, count)

func get_item_count(item_id: String) -> int:
	return _inventory.get(item_id, 0)

func has_item(item_id: String) -> bool:
	return _inventory.get(item_id, 0) > 0

func use_item(item_id: String, unit: Unit) -> bool:
	if not has_item(item_id):
		return false
	var data = _item_db[item_id]
	# 应用效果（根据类型不同）
	_apply_effect(data, unit)
	# 减少库存（若消耗型）
	if data.use_type == "consumable":
		_inventory[item_id] -= 1
		if _inventory[item_id] <= 0:
			_inventory.erase(item_id)
	item_used.emit(item_id, unit)
	return true

func use_item_on_target(item_id: String, user: Unit, target: Unit) -> bool:
	# 在单位库存中查找该道具的第一个实例
	var inst = user.find_first_instance(item_id)
	if not inst:
		print("单位库存中没有道具: ", item_id)
		return false

	var data = _item_db.get(item_id)
	if not data or data.use_effect.is_empty():
		print("道具数据缺失或无效")
		return false

	var effect = data.use_effect   # ---- 确保 effect 在此处定义 ----
	var eff_type = effect.get("type", "")
	match eff_type:
		"heal":
			var heal_amt = effect.get("value", 0)
			var old_hp = target.hit_points
			target.hit_points = min(target.hit_points + heal_amt, target.unit_stats.max_hp)
			var actual_heal = target.hit_points - old_hp
			target.update_hp_label()
			SignalBus.request_damage_popup.emit(target.global_position, actual_heal, false, false, true)
			SoundManager.play_heal_sound()
		"damage":
			var dmg = effect.get("value", 0)
			var old_hp = target.hit_points
			target.apply_damage(dmg)
			var actual_dmg = old_hp - target.hit_points
			if actual_dmg > 0:
				SignalBus.request_damage_popup.emit(target.global_position, actual_dmg, false, false, false)
				SoundManager.play_hit_sound()
			if target.hit_points <= 0:
				UnitManager.unregister_unit(target)
				target.queue_free()
				TurnManager.check_victory()
		"cure":
			# 解除状态（暂略）
			pass
		"buff":
			# 应用增益（暂略）
			pass
		_:
			print("未知效果类型: ", eff_type)
			return false

	# 消耗道具（从单位库存移除该实例）
	if data.use_type == "consumable":
		user.remove_instance(inst)

	item_used.emit(item_id, user)
	print("道具使用成功")
	return true

func _apply_effect(data: ItemData, unit: Unit):
	match data.type:
		"heal":
			var heal_amt = data.effect.get("hp", 0)
			unit.hit_points = min(unit.hit_points + heal_amt, unit.unit_stats.max_hp)
			unit.update_hp_label()
			# 显示飘字
			SignalBus.request_damage_popup.emit(unit.global_position, heal_amt, false, false, true)
		"cure":
			# 解除状态（若实现状态系统）
			pass
		"buff":
			# 添加buff（需实现buff系统）
			pass
		"attack":
			# 使用攻击道具（需实现范围伤害）
			pass
		"weapon":
			# 装备武器（需实现装备系统）
			pass

func get_all_items() -> Dictionary:
	return _inventory.duplicate()

# 存档/读档（可接入存档系统）
func save_inventory():
	# 保存到文件或全局
	pass
func load_inventory():
	pass
