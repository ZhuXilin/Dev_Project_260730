extends Node
## ★ v6.37：单位间 build 配合——站位阵型系统（主线战棋专用）。
## 配合靠「格子相邻（曼哈顿 ≤ 1）」触发，效果为机制变化而非数值加成。
## 状态全部为战斗内临时，不进存档；竞技场 1v1 不调用本管理器。

const SCHOOLS : Array[String] = ["烈焰", "灰烬", "守护", "轮回", "献祭", "余烬"]

## 配合表：{受益流派: {相邻锚点流派: 配合key}}
## 注意 F1/F6 双向但效果不同：烈焰看灰烬→燎原，灰烬看烈焰→灰烬火墙
const PAIR_MAP : Dictionary = {
	"烈焰": {"灰烬": "F1_燎原"},
	"守护": {"余烬": "F5_余烬引爆"},
	"灰烬": {"烈焰": "F6_灰烬火墙"},
	"轮回": {},
	"献祭": {},
	"余烬": {},
}
## 通用型：任意受益流派 + 相邻锚点流派
const UNIVERSAL_ANCHORS : Dictionary = {
	"守护": "F2_铁壁护卫",
	"轮回": "F3_轮回链",
	"献祭": "F4_血祭传递",
}

## 阵型缓存：{受益单位grid_cell: {"keys": [配合key...], "anchors": {key: 锚点单位}}}
var _state : Dictionary = {}
## 血祭传递每战限一次（key = "受益单位名|锚点单位名"）
var _bloodrite_used : Dictionary = {}

func reset_battle() -> void:
	_state.clear()
	_bloodrite_used.clear()


func is_adjacent(a: Unit, b: Unit) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var d : int = absi(a.grid_cell.x - b.grid_cell.x) + absi(a.grid_cell.y - b.grid_cell.y)
	return d <= 1


## 相邻格中指定流派的同队友军（排除自己）；无则返回 null
func adjacent_ally_with_school(unit: Unit, school: String) -> Unit:
	if not is_instance_valid(unit):
		return null
	for u in UnitManager.unit_list:
		if not is_instance_valid(u) or u == unit or u.hit_points <= 0:
			continue
		if u.unit_stats.team_id != unit.unit_stats.team_id:
			continue
		if BuildManager.get_effective_school_level(u, school) <= 0:
			continue
		if is_adjacent(unit, u):
			return u
	return null


## 单位的主流派（有效 Lv 最高）
func dominant_school(unit: Unit) -> String:
	var best : String = ""
	var best_lv : int = 0
	for s in SCHOOLS:
		var lv : int = BuildManager.get_effective_school_level(unit, s)
		if lv > best_lv:
			best_lv = lv
			best = s
	return best


## 全场重算阵型：移动落格 / 单位阵亡 / 战斗开始时调用
func rebuild() -> void:
	_state.clear()
	for unit in UnitManager.unit_list:
		if not is_instance_valid(unit) or unit.hit_points <= 0:
			continue
		if unit.unit_stats.team_id != 0:  # 只对玩家方生效
			continue
		var keys : Array = []
		var anchors : Dictionary = {}
		var my_dom : String = dominant_school(unit)
		# 专精配对（受益流派 → 相邻锚点流派）
		if PAIR_MAP.has(my_dom):
			for anchor_school in PAIR_MAP[my_dom]:
				var anchor : Unit = adjacent_ally_with_school(unit, anchor_school)
				if anchor != null:
					var k : String = PAIR_MAP[my_dom][anchor_school]
					keys.append(k)
					anchors[k] = anchor
		# 通用锚点（任意流派受益）
		for anchor_school in UNIVERSAL_ANCHORS:
			var anchor : Unit = adjacent_ally_with_school(unit, anchor_school)
			if anchor != null:
				var k : String = UNIVERSAL_ANCHORS[anchor_school]
				if not keys.has(k):
					keys.append(k)
					anchors[k] = anchor
		if keys.size() > 0:
			_state[unit.grid_cell] = {"unit": unit, "keys": keys, "anchors": anchors}
	SignalBus.request_formation_changed.emit()


## 某单位当前是否激活某配合
func has_synergy(unit: Unit, key: String) -> bool:
	if not is_instance_valid(unit):
		return false
	var entry : Variant = _state.get(unit.grid_cell, null)
	if entry == null:
		return false
	# 触发时再校验一次相邻，防止状态过期
	var d : Dictionary = entry
	if not d.get("keys", []).has(key):
		return false
	var anchor : Unit = d.get("anchors", {}).get(key, null)
	return is_adjacent(unit, anchor)


## 取某单位某配合的锚点单位（用于"以队友为圆心"类效果）
func get_anchor(unit: Unit, key: String) -> Unit:
	var entry : Variant = _state.get(unit.grid_cell, null)
	if entry == null:
		return null
	return (entry as Dictionary).get("anchors", {}).get(key, null)


## 取某格单位的激活配合列表（UI 用）
func keys_at(cell: Vector2i) -> Array:
	var entry : Variant = _state.get(cell, null)
	if entry == null:
		return []
	return (entry as Dictionary).get("keys", [])


func all_formation_pairs() -> Array:
	## 返回 [[受益单位, 锚点单位, key], ...] 供连线绘制
	var out : Array = []
	for cell in _state:
		var d : Dictionary = _state[cell]
		var unit : Unit = d.get("unit", null)
		if not is_instance_valid(unit):
			continue
		for k in d.get("keys", []):
			var anchor : Unit = d.get("anchors", {}).get(k, null)
			if is_instance_valid(anchor):
				out.append([unit, anchor, k])
	return out


func consume_bloodrite(unit: Unit, anchor: Unit) -> bool:
	## 血祭传递：每对组合每战一次
	if not is_instance_valid(unit) or not is_instance_valid(anchor):
		return false
	var key : String = "%s|%s" % [unit.unit_stats.unit_name, anchor.unit_stats.unit_name]
	if _bloodrite_used.has(key):
		return false
	_bloodrite_used[key] = true
	return true
