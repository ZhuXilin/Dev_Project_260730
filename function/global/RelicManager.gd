extends Node

signal relic_unlocked(relic_id: String)

var _relic_db: Dictionary = {}      # relic_id -> Dictionary
var _unlocked_relics: Array = []    # 已解锁的 relic_id 列表
# 删除 _default_granted 变量

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

# ============================================================
#  遗物解锁来源
# ============================================================
func get_unlock_source(relic_id: String) -> String:
	var d : Dictionary = get_relic_data(relic_id)
	return d.get("unlock_source", "default")


func get_soul_cost(relic_id: String) -> int:
	var d : Dictionary = get_relic_data(relic_id)
	return int(d.get("soul_cost", 0))


## 按来源批量解锁（返回新解锁的遗物 id 列表）
func unlock_relics_by_source(source: String) -> Array:
	var new_unlocked : Array = []
	for rid in _relic_db:
		if get_unlock_source(rid) != source:
			continue
		if rid in _unlocked_relics:
			continue
		_unlocked_relics.append(rid)
		new_unlocked.append(rid)
	if not new_unlocked.is_empty():
		print("[RelicManager] Boss 解锁遗物（%s）：%s" % [source, new_unlocked])
	return new_unlocked


# ============================================================
#  魂解锁
# ============================================================
func can_soul_unlock_relic(relic_id: String) -> bool:
	if is_relic_unlocked(relic_id):
		return false
	if get_unlock_source(relic_id) != "soul":
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


## 用于 UI 显示解锁条件
func get_unlock_hint(relic_id: String) -> String:
	if is_relic_unlocked(relic_id):
		return "已获得"
	var src : String = get_unlock_source(relic_id)
	match src:
		"default":   return "默认解锁"
		"boss_day1": return "通关 Day1 Boss 解锁"
		"boss_day2": return "通关 Day2 Boss 解锁"
		"boss_day3": return "通关 Day3 Boss 解锁"
		"soul":      return "%d 魂解锁" % get_soul_cost(relic_id)
	return "?"
