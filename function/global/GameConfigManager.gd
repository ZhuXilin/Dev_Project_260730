extends Node

const CONFIG_DIR : String = "res://content/data/config/"
const FILES : Array = [
	"economy_config.json",
	"combat_config.json",
	"progression_config.json",
	"arena_config.json",
]

var _data : Dictionary = {}   # {filename: Dictionary}


func _ready():
	load_all()


func load_all():
	_data.clear()
	for fname in FILES:
		_data[fname] = _load_file(CONFIG_DIR + fname)
	print("[GameConfigManager] 加载 %d 个配置文件" % _data.size())


func _load_file(path : String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[GameConfigManager] 文件不存在: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		push_error("[GameConfigManager] 解析失败: " + path)
		return {}
	return data


func get_file(fname : String) -> Dictionary:
	return _data.get(fname, {})


func get_value(fname : String, path : String, default = null):
	var cur : Variant = _data.get(fname, {})
	for p in path.split("."):
		if cur is Dictionary:
			if not (cur as Dictionary).has(p): return default
			cur = (cur as Dictionary)[p]
		elif cur is Array:
			var idx : int = int(p)
			if idx < 0 or idx >= (cur as Array).size(): return default
			cur = (cur as Array)[idx]
		else:
			return default
	return cur


func reload(fname : String):
	_data[fname] = _load_file(CONFIG_DIR + fname)


func reload_all():
	load_all()
