extends Node

# ============================================================
#  AffixManager — 装备词条
# ============================================================

# v6.38（C1）：词条池 20→16（按 type 去重，乘区全保留），
# 品质梯度温和收缩（原 1/2/3/4 → 1/2/2/3），减少"高品质要读4条"的负担。
const QUALITY_AFFIX_COUNT : Dictionary = {
	"common": 1,
	"rare": 2,
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


## v5.1：两阶段抽取——先「标签专属池」，再用「通用池」补满。
## 目的：带标签的防具一眼能看出流派基因（烈焰必出攻击/暴击/穿透），
## 同时低品质/冷门标签不会因为专属池不足而开天窗。
## ★ v6.54：allowed_schools 非空时，只允许这些流派的词条（专精防具锁定池）；
##   否则回退用 item_tags 匹配。空 tag 词条仍作通用池补位。
func roll_affixes(quality: String, item_tags: Array, allowed_schools: Array = []) -> Array:
	var count : int = get_affix_count_for_quality(quality)
	if count <= 0:
		return []

	var tagged_pool : Array = []
	var universal_pool : Array = []
	var pool_tags : Array = allowed_schools if not allowed_schools.is_empty() else item_tags

	for aid in _affixes:
		var d : Dictionary = _affixes[aid]
		var min_q : String = d.get("min_quality", "rare")
		if not _quality_ok(quality, min_q):
			continue
		var affix_tags : Array = d.get("tags", [])
		var is_tagged : bool = false
		if not affix_tags.is_empty():
			for t in affix_tags:
				if t in pool_tags:
					is_tagged = true
					break
			# 有标签限制但都不匹配 → 跳过（专属词条不进通用池）
			if not is_tagged:
				continue
		if is_tagged:
			tagged_pool.append(aid)
		else:
			universal_pool.append(aid)

	tagged_pool.shuffle()
	universal_pool.shuffle()

	var result : Array = []
	var used_types : Dictionary = {}

	# 第一阶段：优先吃标签专属词条
	for aid in tagged_pool:
		if result.size() >= count:
			break
		_try_append_affix(aid, used_types, result)

	# 第二阶段：通用池补满
	for aid in universal_pool:
		if result.size() >= count:
			break
		_try_append_affix(aid, used_types, result)

	return result


func _try_append_affix(aid: String, used_types: Dictionary, result: Array) -> void:
	var d : Dictionary = _affixes[aid]
	var t : String = d.get("type", "")
	if used_types.has(t):
		return
	used_types[t] = true
	var vmin : int = int(d.get("value_min", 1))
	var vmax : int = int(d.get("value_max", 1))
	var value : int = vmin if vmin == vmax else (randi() % (vmax - vmin + 1) + vmin)
	result.append({"id": aid, "value": value})


func _quality_ok(q : String, min_q : String) -> bool:
	var order : Array = ["common", "rare", "epic", "legendary"]
	return order.find(q) >= order.find(min_q)
