extends Node

# ============================================================
#  AffixManager — 装备词条
# ============================================================

const QUALITY_AFFIX_COUNT : Dictionary = {
	"common": 0,
	"rare": 1,
	"epic": 2,
	"legendary": 3,
}

var _affixes : Dictionary = {}
var _by_type : Dictionary = {}


func _ready():
	load_affixes()


func load_affixes():
	var path : String = Config.PATHS.AFFIX_DATA
	if not FileAccess.file_exists(path):
		push_error("词条数据不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	_affixes = data
	_by_type.clear()
	for aid in _affixes:
		var d : Dictionary = _affixes[aid]
		var t : String = d.get("type", "")
		if not _by_type.has(t):
			_by_type[t] = []
		_by_type[t].append(aid)
	print("[AffixManager] 加载 %d 个词条" % _affixes.size())


func get_affix(affix_id: String) -> Dictionary:
	return _affixes.get(affix_id, {})


func get_affix_count_for_quality(quality: String) -> int:
	return int(QUALITY_AFFIX_COUNT.get(quality, 0))


func format_description(affix_id: String, value: int) -> String:
	var d : Dictionary = get_affix(affix_id)
	if d.is_empty():
		return affix_id
	return str(d.get("description", "")).replace("{v}", str(value))


func roll_affixes(quality: String, item_tags: Array) -> Array:
	var count : int = get_affix_count_for_quality(quality)
	if count <= 0:
		return []

	var candidates : Array = []
	for aid in _affixes:
		var d : Dictionary = _affixes[aid]
		var min_q : String = d.get("min_quality", "rare")
		if not _quality_ok(quality, min_q):
			continue
		var affix_tags : Array = d.get("tags", [])
		if not affix_tags.is_empty():
			var matched : bool = false
			for t in affix_tags:
				if t in item_tags:
					matched = true
					break
			if not matched:
				continue
		candidates.append(aid)

	if candidates.is_empty():
		return []

	candidates.shuffle()
	var result : Array = []
	var used_types : Dictionary = {}
	for i in range(count):
		var picked : String = ""
		for aid in candidates:
			var d : Dictionary = _affixes[aid]
			var t : String = d.get("type", "")
			if used_types.has(t):
				continue
			picked = aid
			break
		if picked == "":
			break
		used_types[_affixes[picked].get("type", "")] = true
		var d2 : Dictionary = _affixes[picked]
		var vmin : int = int(d2.get("value_min", 1))
		var vmax : int = int(d2.get("value_max", 1))
		var value : int = vmin if vmin == vmax else (randi() % (vmax - vmin + 1) + vmin)
		result.append({"id": picked, "value": value})

	return result


func _quality_ok(q : String, min_q : String) -> bool:
	var order : Array = ["common", "rare", "epic", "legendary"]
	return order.find(q) >= order.find(min_q)
