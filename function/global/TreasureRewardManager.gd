class_name TreasureRewardManager
extends RefCounted

static var _data : Dictionary = {}
static var _loaded : bool = false


static func _load():
	if _loaded:
		return
	_loaded = true
	var path = Config.PATHS.TREASURE_REWARDS
	if not FileAccess.file_exists(path):
		push_error("宝箱奖励数据文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed is Dictionary:
		push_error("宝箱奖励 JSON 解析失败")
		return
	_data = parsed
	print("成功加载宝箱奖励池，天数: ", _data.keys())


## 随机滚一个奖励（返回深拷贝）
## day <= 1 → day1 池；day >= 2 → day2 池
static func roll_reward(day: int) -> Dictionary:
	_load()
	var key = "day1" if day <= 1 else "day2"
	var pool = _data.get(key, [])
	if pool.is_empty():
		return {}
	var idx = randi() % pool.size()
	return pool[idx].duplicate(true)
