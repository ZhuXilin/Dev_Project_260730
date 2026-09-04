extends Node
class_name TalentManager

# ---- 词条数据缓存 ----
static var _talent_db: Dictionary = {}
static var _talent_data_loaded: bool = false

# TalentManager.gd
static func load_talent_data():
	if _talent_data_loaded:
		return
	_talent_data_loaded = true
	var path = "res://content/data/talents.json"
	if not FileAccess.file_exists(path):
		print("词条数据文件不存在: ", path)
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
		
		# ---- ✨新增：读取兼容单位列表 ----
		talent.compatible_units = dict.get("compatible_units", [])
		
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


# ---- 新增：词条触发状态检查 ----
static func is_talent_ready(unit: Unit, talent_id: String) -> bool:
	var inst = unit.get_talent_instance(talent_id)
	return inst and inst.is_ready and inst.is_active


# ---- 新增：重置词条积累 ----
static func reset_talent(unit: Unit, talent_id: String):
	var inst = unit.get_talent_instance(talent_id)
	if inst:
		inst.reset()

# ---- 获取词条可装备的单位类型列表 ----
static func get_talent_compatible_units(talent_id: String) -> Array:
	var data = _talent_db.get(talent_id)
	if not data:
		return []
	return data.compatible_units if data.compatible_units != null else []

# ---- 检查单位是否可以装备该词条 ----
static func is_talent_compatible_with_unit(talent_id: String, unit_name: String) -> bool:
	var compatible = get_talent_compatible_units(talent_id)
	if compatible.is_empty():
		return true
	var key = _normalize_unit_key(unit_name)
	return key in compatible

# ---- 规范化单位键名（中文→英文） ----
static func _normalize_unit_key(unit_name: String) -> String:
	var cn_to_en = {
		"剑士": "swordsman",
		"枪兵": "spearman",
		"斧兵": "axeman",
		"弓兵": "archer",
		"飞马": "pegasus",
		"法师": "mage",
		"修女": "cleric",
		"龙人": "dragonborn",
		"重甲兵": "armored"
	}
	return cn_to_en.get(unit_name, unit_name)
