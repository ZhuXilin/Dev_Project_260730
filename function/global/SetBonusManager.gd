extends Node

# ============================================================
#  SetBonusManager — 标签套装 + 标签交叉效果
#  v5.1 口径：
#   - 同标签套装 = 单位内 2 件生效（tier1 基础）
#   - 2 件中 ≥1 件 epic+ → 质变（tier2 强化）
#   - 全队交叉套装（cross_bonuses）保持独立，不参与单位 Build
#  所有套装效果统一从 get_unit_set_effects() 出口读取，tier 判定只做一次
# ============================================================

## 品质档位（用于质变门槛）
const QUALITY_ORDER : Dictionary = {
	"common": 0, "rare": 1, "epic": 2, "legendary": 3,
}
## 套装生效件数（单位内）
const SET_THRESHOLD : int = 2
## 触发质变所需的最低品质档（epic = 2）
const TIER2_QUALITY : int = 2

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
#  单位内标签统计：件数 + 最高品质档
# ============================================================
func _collect_unit_tags(unit) -> Dictionary:
	var result : Dictionary = {}
	for slot in unit.armor_slots:
		if slot == null: continue
		var data : ItemData = ItemManager.get_item_data(slot.item_id)
		if not data: continue
		for tag in data.tags:
			if not result.has(tag):
				result[tag] = {"count": 0, "max_quality": 0}
			result[tag]["count"] += 1
			var q : int = int(QUALITY_ORDER.get(data.quality, 0))
			if q > int(result[tag]["max_quality"]):
				result[tag]["max_quality"] = q
	return result


## 返回某标签在该单位身上的 tier：0 未激活 / 1 基础 / 2 质变
func get_unit_set_tier(unit, tag: String) -> int:
	var tags : Dictionary = _collect_unit_tags(unit)
	if not tags.has(tag): return 0
	if int(tags[tag]["count"]) < SET_THRESHOLD: return 0
	return 2 if int(tags[tag]["max_quality"]) >= TIER2_QUALITY else 1


# ============================================================
#  单位内 2 件套装列表（兼容旧接口，新增 tier 字段）
# ============================================================
func get_active_sets_for_unit(unit : Unit) -> Array:
	var tags : Dictionary = _collect_unit_tags(unit)
	var active : Array = []
	for tag in tags:
		if int(tags[tag]["count"]) < SET_THRESHOLD: continue
		var b : Dictionary = get_bonus(tag)
		if b.is_empty(): continue
		var tier : int = 2 if int(tags[tag]["max_quality"]) >= TIER2_QUALITY else 1
		active.append({
			"tag": tag, "bonus": b, "count": int(tags[tag]["count"]), "tier": tier,
		})
	return active


## ★ 统一出口：返回该单位所有已按 tier 选好的效果
##   [{effect: String, value: float, tag: String, tier: int}, ...]
func get_unit_set_effects(unit : Unit) -> Array:
	var result : Array = []
	for entry in get_active_sets_for_unit(unit):
		var b : Dictionary = entry["bonus"]
		var tier : int = int(entry["tier"])
		var effects : Array = []
		if tier >= 2 and not b.get("tier2_effects", []).is_empty():
			effects = b.get("tier2_effects", [])
		elif not b.get("effects", []).is_empty():
			effects = b.get("effects", [])
		else:
			# 兜底：兼容旧版单 effect 结构
			effects = [{"effect": b.get("effect", ""), "value": b.get("value", 0)}]
		for e in effects:
			if not (e is Dictionary): continue
			result.append({
				"effect": str(e.get("effect", "")),
				"value": float(e.get("value", 0.0)),
				"tag": entry["tag"],
				"tier": tier,
			})
	return result


## 取某单位某类套装效果值之和（消费点统一读这里，免得各写一遍 tier 判定）
func get_unit_set_effect_value(unit : Unit, effect : String) -> float:
	var total : float = 0.0
	for e in get_unit_set_effects(unit):
		if str(e.get("effect", "")) == effect:
			total += float(e.get("value", 0.0))
	return total


# ============================================================
#  全队级判定（魂火上限等队伍效果）
# ============================================================
## 全队某标签的最高 tier：0 未激活 / 1 基础 / 2 质变
func get_team_set_tier(tag: String) -> int:
	var best : int = 0
	for u in GameState.party:
		if u.is_dead: continue
		var tier : int = get_unit_set_tier(u, tag)
		best = maxi(best, tier)
	return best


## 兼容旧接口：2 件即算激活
func team_has_set(tag: String) -> bool:
	return get_team_set_tier(tag) > 0


## 全队级：取某标签套装的某类效果值（按全队最高 tier 选数值）
## 用于魂火上限这类「队伍级」效果
func get_team_tag_effect_value(tag: String, effect: String) -> float:
	var tier : int = get_team_set_tier(tag)
	if tier <= 0: return 0.0
	var b : Dictionary = get_bonus(tag)
	var effects : Array = []
	if tier >= 2 and not b.get("tier2_effects", []).is_empty():
		effects = b.get("tier2_effects", [])
	elif not b.get("effects", []).is_empty():
		effects = b.get("effects", [])
	else:
		effects = [{"effect": b.get("effect", ""), "value": b.get("value", 0)}]
	var total : float = 0.0
	for e in effects:
		if not (e is Dictionary): continue
		if str(e.get("effect", "")) == effect:
			total += float(e.get("value", 0.0))
	return total


func get_all_active_tags() -> Array:
	var result : Array = []
	for tag in _bonuses:
		if team_has_set(tag):
			result.append(tag)
	return result


# ============================================================
#  标签交叉效果（全队级，两标签各 2 件）
#  与单位套装并行，不抢单位 Build 特色
# ============================================================
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
