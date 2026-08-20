extends Node

signal relic_unlocked(relic_id: String)

var _relic_db: Dictionary = {}      # relic_id -> Dictionary
var _unlocked_relics: Array = []    # 已解锁的 relic_id 列表
# 删除 _default_granted 变量

func _ready():
	load_relics()
	load_unlock_config()

func load_relics():
	var path = "res://content/data/relic_data.json"
	if not FileAccess.file_exists(path):
		push_error("遗物数据文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("遗物 JSON 解析失败")
		return
	_relic_db = data
	print("成功加载 ", _relic_db.size(), " 个遗物")

func load_unlock_config():
	var path = "res://content/data/relic_unlock.json"
	if not FileAccess.file_exists(path):
		_unlocked_relics = ["relic_attack", "relic_defense"]
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data and data is Dictionary:
		var raw = data.get("default_unlocked", [])
		_unlocked_relics = []
		for item in raw:
			if item is String:
				_unlocked_relics.append(item)
		# 不再读取 default_granted
	else:
		_unlocked_relics = ["relic_attack", "relic_defense"]

func get_relic_data(relic_id: String) -> Dictionary:
	return _relic_db.get(relic_id, {})

func get_all_relic_data() -> Dictionary:
	return _relic_db.duplicate()

func is_relic_unlocked(relic_id: String) -> bool:
	return relic_id in _unlocked_relics

func get_unlocked_relics() -> Array:
	return _unlocked_relics.duplicate()

func get_all_relic_ids() -> Array:
	var ids: Array = []
	for key in _relic_db.keys():
		ids.append(key)
	return ids

# 删除 get_default_granted_relics() 方法

func unlock_relic(relic_id: String):
	if relic_id in _unlocked_relics:
		return
	if not _relic_db.has(relic_id):
		print("警告：遗物数据不存在: ", relic_id)
		return
	_unlocked_relics.append(relic_id)
	relic_unlocked.emit(relic_id)
	print("遗物解锁: ", relic_id)

func set_unlocked_relics(list: Array):
	_unlocked_relics = list.duplicate()
