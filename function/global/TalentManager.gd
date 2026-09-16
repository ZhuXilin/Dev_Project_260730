extends Node
class_name TalentManager

# ============================================================
#  词条数据缓存
# ============================================================
static var _talent_db: Dictionary = {}
static var _talent_data_loaded: bool = false


static func load_talent_data():
	if _talent_data_loaded:
		return
	_talent_data_loaded = true
	var path = Config.PATHS.TALENT_DATA
	if not FileAccess.file_exists(path):
		push_error("词条数据文件不存在: ", path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("词条 JSON 解析失败")
		return

	for key in data:
		var dict = data[key]
		var talent = TalentData.new()
		talent.id = dict.get("id", key)
		talent.display_name = dict.get("display_name", key)
		talent.description = dict.get("description", "")
		talent.school = dict.get("school", "")
		talent.rarity = dict.get("rarity", "common")
		talent.accumulation_threshold = dict.get("accumulation_threshold", 3)
		talent.effect_type = dict.get("effect_type", "attack")
		talent.effect_params = dict.get("effect_params", {})
		talent.icon_path = dict.get("icon", "")
		talent.compatible_units = dict.get("compatible_units", [])
		talent.unlock_type = dict.get("unlock_type", "default")
		talent.soul_cost = int(dict.get("soul_cost", 0))
		_talent_db[talent.id] = talent

	print("成功加载 ", _talent_db.size(), " 个词条")


static func get_talent_data(talent_id: String) -> TalentData:
	load_talent_data()
	return _talent_db.get(talent_id)


static func get_talents_by_school(school: String) -> Array[TalentData]:
	load_talent_data()
	var result = []
	for talent in _talent_db.values():
		if talent.school == school:
			result.append(talent)
	return result


static func get_all_talent_ids() -> Array:
	load_talent_data()
	var ids : Array = []
	for key in _talent_db:
		ids.append(key)
	ids.sort()
	return ids


# ============================================================
#  解锁查询
# ============================================================
static func get_default_unlocked_talents() -> Array:
	load_talent_data()
	var result : Array = []
	for tid in _talent_db:
		if _talent_db[tid].unlock_type == "default":
			result.append(tid)
	return result


static func get_soul_unlockable_talents() -> Dictionary:
	# 返回 { talent_id: soul_cost }
	load_talent_data()
	var result : Dictionary = {}
	for tid in _talent_db:
		if _talent_db[tid].unlock_type == "soul":
			result[tid] = _talent_db[tid].soul_cost
	return result


static func get_story_locked_talents() -> Array:
	load_talent_data()
	var result : Array = []
	for tid in _talent_db:
		if _talent_db[tid].unlock_type == "story":
			result.append(tid)
	return result


static func get_soul_cost(talent_id: String) -> int:
	var data = get_talent_data(talent_id)
	if not data:
		return -1
	if data.unlock_type != "soul":
		return -1
	return data.soul_cost


# ============================================================
#  战斗触发
# ============================================================
static func is_talent_ready(unit: Unit, talent_id: String) -> bool:
	var inst = unit.get_talent_instance(talent_id)
	return inst and inst.is_ready and inst.is_active


static func reset_talent(unit: Unit, talent_id: String):
	var inst = unit.get_talent_instance(talent_id)
	if inst:
		inst.reset()


# ============================================================
#  兼容性
# ============================================================
static func get_talent_compatible_units(talent_id: String) -> Array:
	load_talent_data()
	var data = _talent_db.get(talent_id)
	if not data:
		return []
	return data.compatible_units if data.compatible_units != null else []


static func is_talent_compatible_with_unit(talent_id: String, unit_name: String) -> bool:
	var compatible = get_talent_compatible_units(talent_id)
	if compatible.is_empty():
		return true
	var key = UnitDataManager.normalize_unit_key(unit_name)
	return key in compatible


# ============================================================
#  斗技场：经验 / 等级（阶梯升级）
# ============================================================
const EXP_THRESHOLDS : Array = [0, 100, 300, 600]
const MAX_TALENT_LEVEL : int = 3
const MAX_TALENT_EXP : int = 600


static func get_talent_exp(unit_type: String, talent_id: String) -> int:
	var unit_dict = GameState.talent_exp.get(unit_type, {})
	return int(unit_dict.get(talent_id, 0))


static func get_talent_level(unit_type: String, talent_id: String) -> int:
	var cur_exp = get_talent_exp(unit_type, talent_id)
	if cur_exp >= 300:
		return 3
	if cur_exp >= 100:
		return 2
	return 1


static func get_talent_exp_in_level(unit_type: String, talent_id: String) -> int:
	var cur_exp = get_talent_exp(unit_type, talent_id)
	if cur_exp >= 600:
		return 300
	if cur_exp >= 300:
		return cur_exp - 300
	if cur_exp >= 100:
		return cur_exp - 100
	return cur_exp


static func get_level_required_exp(unit_type: String, talent_id: String) -> int:
	var cur_exp = get_talent_exp(unit_type, talent_id)
	if cur_exp >= 300:
		return 300
	if cur_exp >= 100:
		return 200
	return 100


static func is_talent_max_level(unit_type: String, talent_id: String) -> bool:
	return get_talent_exp(unit_type, talent_id) >= MAX_TALENT_EXP


static func add_talent_exp(unit_type: String, talent_id: String, amount: int) -> int:
	if amount <= 0:
		return 0
	var old_exp = get_talent_exp(unit_type, talent_id)
	var new_exp = mini(old_exp + amount, MAX_TALENT_EXP)
	var actual = new_exp - old_exp
	if actual <= 0:
		return 0
	if not GameState.talent_exp.has(unit_type):
		GameState.talent_exp[unit_type] = {}
	GameState.talent_exp[unit_type][talent_id] = new_exp
	return actual
