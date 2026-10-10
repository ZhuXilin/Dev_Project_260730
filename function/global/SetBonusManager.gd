extends Node

# ============================================================
#  SetBonusManager — 套装效果（同标签防具 3 件触发）
# ============================================================

var _bonuses : Dictionary = {}


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
	_bonuses = data
	print("[SetBonusManager] 加载 %d 个套装" % _bonuses.size())


func get_bonus(tag: String) -> Dictionary:
	return _bonuses.get(tag, {})


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
