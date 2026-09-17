extends Node

var _stories : Dictionary = {}   # npc_id -> { name, topics: [] }

func _ready():
	load_stories()

func load_stories():
	var path = Config.PATHS.STORY_DATA
	if not FileAccess.file_exists(path):
		push_error("故事数据文件不存在: ", path)
		return
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	var data = JSON.parse_string(content)
	if data == null or not data is Dictionary:
		push_error("故事 JSON 解析失败")
		return
	_stories = data
	print("成功加载 ", _stories.size(), " 个酒馆 NPC")

func get_npcs() -> Array:
	var result : Array = []
	for npc_id in _stories:
		var entry = _stories[npc_id]
		result.append({
			"id": npc_id,
			"name": entry.get("name", npc_id),
			"topics": entry.get("topics", []),
		})
	return result

func get_npc(npc_id: String) -> Dictionary:
	return _stories.get(npc_id, {})

func check_condition(condition: String) -> bool:
	if condition == "" or condition == "always":
		return true
	if condition.begins_with("day>="):
		var n = int(condition.substr(5))
		return GameState.current_day >= n
	if condition.begins_with("day=="):
		var n = int(condition.substr(5))
		return GameState.current_day == n
	return true
