extends Node
class_name TalentManager

# ============================================================
#  词条数据缓存
# ============================================================
static var _talent_db: Dictionary = {}
static var _talent_data_loaded: bool = false


# ============================================================
#  数据加载
# ============================================================
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


# ============================================================
#  词条触发状态（战斗中）
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
#  斗技场：词条经验 / 等级（阶梯升级）
# ============================================================
## 累计经验阈值：索引 = 等级-1，值 = 该等级起始经验
##   Lv1: [0, 100)      → 0-99
##   Lv2: [100, 300)    → 100-299
##   Lv3: [300, 600)    → 300-599
##   MAX: [600, ∞)      → 600+
const EXP_THRESHOLDS : Array = [0, 100, 300, 600]

const MAX_TALENT_LEVEL : int = 3
const MAX_TALENT_EXP : int = 600


## 获取某单位某词条的当前累计经验
static func get_talent_exp(unit_type: String, talent_id: String) -> int:
	var unit_dict = GameState.talent_exp.get(unit_type, {})
	return int(unit_dict.get(talent_id, 0))


## 根据累计经验推导等级（1-3）
static func get_talent_level(unit_type: String, talent_id: String) -> int:
	var exp = get_talent_exp(unit_type, talent_id)
	if exp >= 300:
		return 3
	if exp >= 100:
		return 2
	return 1


## 当前等级内的经验进度
static func get_talent_exp_in_level(unit_type: String, talent_id: String) -> int:
	var exp = get_talent_exp(unit_type, talent_id)
	if exp >= 600:
		return 300
	if exp >= 300:
		return exp - 300
	if exp >= 100:
		return exp - 100
	return exp


## 当前等级升下一级所需经验
static func get_level_required_exp(unit_type: String, talent_id: String) -> int:
	var exp = get_talent_exp(unit_type, talent_id)
	if exp >= 300:
		return 300
	if exp >= 100:
		return 200
	return 100


## 是否满级
static func is_talent_max_level(unit_type: String, talent_id: String) -> bool:
	return get_talent_exp(unit_type, talent_id) >= MAX_TALENT_EXP


## 增加经验（返回实际增加量）
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
