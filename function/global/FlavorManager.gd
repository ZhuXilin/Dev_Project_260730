extends Node

var _data : Dictionary = {}

func _ready():
	load_data()

func load_data():
	var path := "res://content/data/flavor.json"
	if not FileAccess.file_exists(path):
		push_warning("[FlavorManager] flavor.json 不存在，叙事模式将显示占位文本")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[FlavorManager] 无法打开 flavor.json")
		return
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		push_warning("[FlavorManager] flavor.json 解析失败")
		return
	_data = data
	print("[FlavorManager] 加载 %d 个类别" % _data.size())

## 取某类某 id 的叙事文本；不存在时返回空串
func get_flavor(category: String, id: String) -> String:
	var cat : Dictionary = _data.get(category, {})
	return str(cat.get(id, ""))

## 是否存在该叙事条目
func has_flavor(category: String, id: String) -> bool:
	var cat : Dictionary = _data.get(category, {})
	return cat.has(id)

## 是否处于叙事模式
func is_narrative_mode() -> bool:
	return Globals.info_mode == Globals.InfoMode.NARRATIVE
