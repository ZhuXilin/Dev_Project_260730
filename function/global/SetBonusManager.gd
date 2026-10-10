extends Node

# ============================================================
#  SetBonusManager — 套装 + 标签交叉效果
# ============================================================

var _bonuses : Dictionary = {}
var _cross_bonuses : Dictionary = {}


func _ready():
	load_bonuses()


func load_bonuses():
	var path : String = Config.PATHS.SET_BONUS_DATA
	if not FileAccess.file_exists(path):
		push_error("套装数据不存在: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	_bonuses.clear()
	_cross_bonuses.clear()
	for key in data:
		if key == "cross_bonuses":
			var cb : Dictionary = data[key]
			for cid in cb:
				_cross_bonuses[cid] = cb[cid]
		else:
			_bonuses[key] = data[key]
	print("[SetBonusManager] 加载 %d 个套装 + %d 个交叉效果" % [
		_bonuses.size(), _cross_bonuses.size()])


func get_bonus(tag: String) -> Dictionary:
	return _bonuses.get(tag, {})


# ============================================================
#  同标签 3 件套装（单位级）
# ============================================================
func get_active_sets_for_unit(unit : Unit) -> Array:
	var tag_count : Dictionary = {}
	for slot in unit.armor_slots:
		if slot == null: continue
		var data : ItemData = ItemManager.get_item_data(slot.item_id)
		if not data: continue
		for tag in data.tags:
			tag_count[tag] = tag_count.get(tag, 0) + 1
	var active : Array = []
	for tag in tag_count:
		if tag_count[tag] >= 3:
			var b : Dictionary = get_bonus(tag)
			if not b.is_empty():
				active.append({"tag": tag, "bonus": b, "count": tag_count[tag]})
	return active


func team_has_set(tag: String) -> bool:
	for u in GameState.party:
		if u.is_dead: continue
		var count : int = 0
		for slot in u.armor_slots:
			if slot == null: continue
			var data : ItemData = ItemManager.get_item_data(slot.item_id)
			if data and tag in data.tags:
				count += 1
		if count >= 3:
			return true
	return false


func get_all_active_tags() -> Array:
	var result : Array = []
	for tag in _bonuses:
		if team_has_set(tag):
			result.append(tag)
	return result


# ============================================================
#  标签交叉效果（全队级，方向 2）
# ============================================================
## 统计全队每个标签的装备件数
func _count_team_tag_items() -> Dictionary:
	var counts : Dictionary = {}
	for u in GameState.party:
		if u.is_dead: continue
		for slot in u.armor_slots:
			if slot == null: continue
			var data : ItemData = ItemManager.get_item_data(slot.item_id)
			if not data: continue
			for tag in data.tags:
				counts[tag] = counts.get(tag, 0) + 1
	return counts


## 返回所有激活的交叉效果：[{id, data}, ...]
func get_active_cross_bonuses() -> Array:
	var result : Array = []
	if _cross_bonuses.is_empty():
		return result
	var counts : Dictionary = _count_team_tag_items()
	for cid in _cross_bonuses:
		var b : Dictionary = _cross_bonuses[cid]
		var tags : Array = b.get("tags", [])
		var min_each : int = int(b.get("min_each", 2))
		var ok : bool = true
		for tag in tags:
			if int(counts.get(tag, 0)) < min_each:
				ok = false
				break
		if ok:
			result.append({"id": cid, "data": b})
	return result
