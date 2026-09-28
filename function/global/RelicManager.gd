extends Node

signal relic_unlocked(relic_id: String)

var _relic_db: Dictionary = {}          # relic_id -> Dictionary
var _unlocked_relics: Array = []        # 已解锁的 relic_id
var _default_unlocked: Array = []       # ★ 从 relic_unlock.json 读的默认解锁（用于合并）

func _ready():
	load_relics()
	load_unlock_config()


func load_relics():
	var path = Config.PATHS.RELIC_DATA
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
	var path = Config.PATHS.RELIC_UNLOCK
	_default_unlocked.clear()
	_unlocked_relics.clear()

	if not FileAccess.file_exists(path):
		_default_unlocked = ["relic_speed", "relic_magic", "relic_dexterity"]
	else:
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		var data = JSON.parse_string(content)
		if data and data is Dictionary:
			var raw = data.get("default_unlocked", [])
			for item in raw:
				if item is String:
					_default_unlocked.append(item)
		else:
			_default_unlocked = ["relic_speed", "relic_magic", "relic_dexterity"]

	# 默认解锁直接生效
	for rid in _default_unlocked:
		if rid not in _unlocked_relics:
			_unlocked_relics.append(rid)


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


func unlock_relic(relic_id: String):
	if relic_id in _unlocked_relics:
		return
	if not _relic_db.has(relic_id):
		print("警告：遗物数据不存在: ", relic_id)
		return
	_unlocked_relics.append(relic_id)
	relic_unlocked.emit(relic_id)
	print("遗物解锁: ", relic_id)


## ★ 合并式设置：默认解锁永远保留，存档里的叠加
func set_unlocked_relics(list: Array):
	_unlocked_relics.clear()
	# 1. 先加入默认解锁
	for rid in _default_unlocked:
		if rid not in _unlocked_relics:
			_unlocked_relics.append(rid)
	# 2. 再加入存档里的（去重）
	for rid in list:
		if rid is String and rid != "" and rid not in _unlocked_relics:
			_unlocked_relics.append(rid)


# ============================================================
#  批量解锁（地图 / 事件调用）
# ============================================================
## 传入遗物 id 列表，已解锁的自动跳过。
## 返回本次新解锁的遗物 id 数组
func unlock_relics_by_ids(relic_ids: Array) -> Array:
	var new_unlocked : Array = []
	for rid in relic_ids:
		if not (rid is String) or rid == "":
			continue
		if rid in _unlocked_relics:
			continue
		if not _relic_db.has(rid):
			push_warning("[RelicManager] 未知遗物 id: " + rid)
			continue
		_unlocked_relics.append(rid)
		new_unlocked.append(rid)
	if not new_unlocked.is_empty():
		print("[RelicManager] 批量解锁遗物：%s" % [new_unlocked])
	return new_unlocked


# ============================================================
#  魂解锁
# ============================================================
func get_soul_cost(relic_id: String) -> int:
	var d : Dictionary = get_relic_data(relic_id)
	return int(d.get("soul_cost", 0))


func can_soul_unlock_relic(relic_id: String) -> bool:
	if is_relic_unlocked(relic_id):
		return false
	var cost : int = get_soul_cost(relic_id)
	if cost <= 0:
		return false
	return GameState.soul >= cost


func soul_unlock_relic(relic_id: String) -> bool:
	if not can_soul_unlock_relic(relic_id):
		return false
	var cost : int = get_soul_cost(relic_id)
	GameState.soul -= cost
	unlock_relic(relic_id)
	SaveManager.auto_save()
	print("[RelicManager] 魂解锁遗物：%s（花费 %d 魂）" % [relic_id, cost])
	return true
