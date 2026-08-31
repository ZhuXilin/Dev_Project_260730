extends Node
class_name TalentManager

# ---- 词条数据缓存 ----
static var _talent_db: Dictionary = {}
static var _talent_data_loaded: bool = false


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
