extends Node

# ============================================================
#  ObjectiveManager — 胜利目标管理器（v4.3 / v6.58 改造）
#  从战场地图的 VictoryObjectiveTrigger 配置读取胜利目标，追踪进度，通知胜利。
#  唯一权威数据源 = 地图场景里的 trigger（见 setup_for_config）。
#  没有配置 / 空配置 → 默认全灭（ANNIHILATE）。
# ============================================================

enum State { INACTIVE, ACTIVE, COMPLETED, FAILED }

signal objective_progress_changed(progress: int, total: int)
signal objective_completed()

var _type : int = MapData.ObjectiveType.ANNIHILATE
var _params : Dictionary = {}
var _state : State = State.INACTIVE

var _capture_cell : Vector2i = Vector2i(-1, -1)
var _capture_hold_turns : int = 3
var _capture_progress : int = 0

var _flag_cell : Vector2i = Vector2i(-1, -1)
var _flag_goal_cell : Vector2i = Vector2i(-1, -1)
var _flag_carrier : Unit = null

var _assault_target_name : String = ""


# ============================================================
#  初始化
# ============================================================
## ★ v6.58：主入口——从战场地图的 VictoryObjectiveTrigger 配置初始化。
## config 为空 / 没有 trigger → 默认全灭，保持兼容（老战场、默认地图不会崩）。
func setup_for_config(config : Dictionary) -> void:
	_reset()
	if config.is_empty():
		_state = State.ACTIVE
		print("[Objective] 无胜利条件 trigger，默认全灭")
		return

	_type = int(config.get("objective_type", MapData.ObjectiveType.ANNIHILATE))
	var raw_params : Variant = config.get("objective_params", {})
	_params = _normalize_params(raw_params)

	# ★ v4.7：动态目标改为"显式开启"。
	#   必须同时满足：
	#     1) allow_dynamic_objective == true
	#     2) 未显式配置具体目标（_type == ANNIHILATE）
	#     3) objective_params 为空
	#   否则战斗节点一律全灭。
	var allows_dynamic : bool = (
		bool(config.get("allow_dynamic_objective", false))
		and _type == MapData.ObjectiveType.ANNIHILATE
		and _params.is_empty()
	)

	if allows_dynamic:
		var pool : Variant = config.get("dynamic_objective_pool", [])
		_type = _roll_dynamic_objective(pool if pool is Array else [])
		print("[Objective] 动态目标已启用，roll 结果：%s" % _type_name())

	_state = State.ACTIVE

	_init_by_type()

	print("[Objective] 目标：%s — %s" % [_type_name(), get_description()])


## 按当前 _type 初始化各目标子系统。
func _init_by_type() -> void:
	match _type:
		MapData.ObjectiveType.CAPTURE:
			_init_capture()
		MapData.ObjectiveType.FLAG:
			_init_flag()
		MapData.ObjectiveType.ASSAULT:
			_init_assault()
		_:
			pass


## 把 trigger 导出的 JSON 友好参数规范化：坐标数组 [x,y] → Vector2i。
## ObjectiveManager 内部各 _init_* 都按 Vector2i 读，这里统一转换。
func _normalize_params(raw : Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var out : Dictionary = {}
	for k in (raw as Dictionary):
		var v : Variant = (raw as Dictionary)[k]
		if v is Array and (v as Array).size() == 2:
			var a : Array = v
			var t0 : int = typeof(a[0])
			var t1 : int = typeof(a[1])
			if (t0 == TYPE_INT or t0 == TYPE_FLOAT) and (t1 == TYPE_INT or t1 == TYPE_FLOAT):
				out[k] = Vector2i(int(a[0]), int(a[1]))
				continue
		if typeof(v) == TYPE_FLOAT:
			out[k] = int(v)
		else:
			out[k] = v
	return out


func _roll_dynamic_objective(pool : Array) -> int:
	var actual_pool : Array = []
	for v in pool:
		var t : int = int(v)
		if t == MapData.ObjectiveType.CAPTURE \
				or t == MapData.ObjectiveType.FLAG \
				or t == MapData.ObjectiveType.ASSAULT:
			actual_pool.append(t)
	if actual_pool.is_empty():
		actual_pool = [
			MapData.ObjectiveType.CAPTURE,
			MapData.ObjectiveType.FLAG,
			MapData.ObjectiveType.ASSAULT,
		]

	# 队伍主标签
	var tag_counts : Dictionary = {}
	for ud in GameState.party:
		if ud.is_dead: continue
		for tag in ud.tags:
			tag_counts[tag] = tag_counts.get(tag, 0) + 1

	var main_tag : String = ""
	var max_c : int = -1
	for t in tag_counts:
		if tag_counts[t] > max_c:
			max_c = tag_counts[t]
			main_tag = t

	# 主标签偏好
	var preferred : int = -1
	if main_tag == "守护" or main_tag == "献祭":
		preferred = MapData.ObjectiveType.CAPTURE
	elif main_tag == "烈焰" or main_tag == "灰烬":
		preferred = MapData.ObjectiveType.ASSAULT
	elif main_tag == "轮回" or main_tag == "余烬":
		preferred = MapData.ObjectiveType.FLAG

	# 偏好目标在池里 → 直接用；否则池里随机
	if preferred != -1 and preferred in actual_pool:
		return preferred

	return actual_pool[randi() % actual_pool.size()]


func _reset() -> void:
	_type = MapData.ObjectiveType.ANNIHILATE
	_params = {}
	_state = State.INACTIVE
	_capture_cell = Vector2i(-1, -1)
	_capture_hold_turns = 3
	_capture_progress = 0
	_flag_cell = Vector2i(-1, -1)
	_flag_goal_cell = Vector2i(-1, -1)
	_flag_carrier = null
	_assault_target_name = ""


func _init_capture() -> void:
	_capture_cell = _params.get("target_cell", Vector2i(-1, -1))
	_capture_hold_turns = int(_params.get("hold_turns", 3))
	if _capture_hold_turns <= 0:
		_capture_hold_turns = 1

	# 没配置 → 用地图中心
	if _capture_cell == Vector2i(-1, -1):
		var gs : Vector2i = TerrainManager.grid_size
		if gs.x > 0:
			_capture_cell = Vector2i(int(gs.x * 0.5), int(gs.y * 0.5))
		else:
			_capture_cell = Vector2i(10, 7)

	print("[Objective] 占领格：%s（需 %d 回合）" % [str(_capture_cell), _capture_hold_turns])


func _init_flag() -> void:
	_flag_cell = _params.get("flag_cell", Vector2i(-1, -1))
	_flag_goal_cell = _params.get("goal_cell", Vector2i(-1, -1))

	var sz : Vector2i = TerrainManager.grid_size
	if sz.x > 0:
		var mid_y : int = int(sz.y * 0.5)
		var right_x : int = int(sz.x * 0.75)
		if _flag_cell == Vector2i(-1, -1):
			_flag_cell = Vector2i(right_x, mid_y)
		if _flag_goal_cell == Vector2i(-1, -1):
			_flag_goal_cell = Vector2i(1, mid_y)
	else:
		if _flag_cell == Vector2i(-1, -1):
			_flag_cell = Vector2i(15, 7)
		if _flag_goal_cell == Vector2i(-1, -1):
			_flag_goal_cell = Vector2i(1, 7)

	print("[Objective] 旗帜：%s → 终点：%s" % [str(_flag_cell), str(_flag_goal_cell)])


func _init_assault() -> void:
	_assault_target_name = str(_params.get("target_unit_name", ""))
	print("[Objective] 突进目标：%s" % (
		_assault_target_name if _assault_target_name != "" else "（自动选 Boss）"))


# ============================================================
#  查询
# ============================================================
func is_annihilate() -> bool:
	return _type == MapData.ObjectiveType.ANNIHILATE

func get_objective_type() -> int:
	return _type

func get_objective_params() -> Dictionary:
	return _params

func get_state() -> int:
	return _state

func is_active() -> bool:
	return _state == State.ACTIVE

func is_completed() -> bool:
	return _state == State.COMPLETED


# ============================================================
#  CAPTURE 查询
# ============================================================
func get_capture_cell() -> Vector2i:
	return _capture_cell

func get_capture_progress() -> int:
	return _capture_progress

func get_capture_hold_turns() -> int:
	return _capture_hold_turns


# ============================================================
#  FLAG 查询
# ============================================================
func get_flag_cell() -> Vector2i:
	return _flag_cell

func get_flag_goal_cell() -> Vector2i:
	return _flag_goal_cell

func get_flag_carrier() -> Unit:
	return _flag_carrier


# ============================================================
#  玩家回合结束钩子（由 TurnManager 在 PLAYER→ENEMY 切换时调用）
# ============================================================
func on_player_turn_end() -> void:
	if not is_active():
		return

	match _type:
		MapData.ObjectiveType.CAPTURE:
			_update_capture()
		MapData.ObjectiveType.FLAG:
			_update_flag()
		MapData.ObjectiveType.ASSAULT:
			_update_assault()
		_:
			pass


func _update_capture() -> void:
	if _capture_cell == Vector2i(-1, -1):
		return

	var occupant : Unit = UnitManager.get_unit_at_cell(_capture_cell)
	var ok : bool = (
		occupant != null
		and occupant.unit_stats.team_id == 0
		and occupant.hit_points > 0
	)

	if ok:
		_capture_progress += 1
		print("[Objective] 占领进度：%d / %d" % [_capture_progress, _capture_hold_turns])
		objective_progress_changed.emit(_capture_progress, _capture_hold_turns)
		if _capture_progress >= _capture_hold_turns:
			_state = State.COMPLETED
			print("[Objective] 占领完成！")
			objective_completed.emit()
	else:
		if _capture_progress > 0:
			print("[Objective] 占领被打断（进度归零）")
		_capture_progress = 0
		objective_progress_changed.emit(0, _capture_hold_turns)


func _update_flag() -> void:
	if _flag_cell == Vector2i(-1, -1) or _flag_goal_cell == Vector2i(-1, -1):
		return

	# 1. 拾旗
	if _flag_carrier == null or not is_instance_valid(_flag_carrier) or _flag_carrier.hit_points <= 0:
		_flag_carrier = null
		var occupant : Unit = UnitManager.get_unit_at_cell(_flag_cell)
		if occupant != null and occupant.unit_stats.team_id == 0 and occupant.hit_points > 0:
			_flag_carrier = occupant
			print("[Objective] %s 拾起旗帜" % occupant.unit_stats.unit_name)

	# 2. 完成判定
	if _flag_carrier != null and _flag_carrier.grid_cell == _flag_goal_cell:
		_state = State.COMPLETED
		print("[Objective] 夺旗完成！")
		objective_completed.emit()


func _update_assault() -> void:
	for u in UnitManager.unit_list:
		if not is_instance_valid(u):
			continue
		if u.unit_stats.team_id != 1:
			continue
		if u.hit_points > 0:
			continue
		if _is_assault_target(u):
			_state = State.COMPLETED
			print("[Objective] 突进完成：击杀 %s" % u.unit_stats.unit_name)
			objective_completed.emit()
			return


# ============================================================
#  单位移除钩子（由 TurnManager 转发）
# ============================================================
func on_unit_removed(unit : Unit, team : int) -> void:
	if not is_active():
		return

	if _type == MapData.ObjectiveType.FLAG and _flag_carrier == unit:
		_flag_carrier = null

	if _type == MapData.ObjectiveType.ASSAULT and team == 1:
		if _is_assault_target(unit):
			_state = State.COMPLETED
			print("[Objective] 突进完成：击杀 %s" % unit.unit_stats.unit_name)
			objective_completed.emit()


func _is_assault_target(unit : Unit) -> bool:
	if _assault_target_name == "":
		return unit.unit_stats.is_boss
	return unit.unit_stats.unit_name == _assault_target_name


# ============================================================
#  文本
# ============================================================
func _type_name() -> String:
	match _type:
		MapData.ObjectiveType.ANNIHILATE: return "全灭"
		MapData.ObjectiveType.CAPTURE:    return "占领"
		MapData.ObjectiveType.FLAG:       return "夺旗"
		MapData.ObjectiveType.ASSAULT:    return "突进"
	return "?"


func get_description() -> String:
	match _type:
		MapData.ObjectiveType.ANNIHILATE:
			return "全灭所有敌人"
		MapData.ObjectiveType.CAPTURE:
			return "占领 (%d, %d) 并守住 %d 回合" % [
				_capture_cell.x, _capture_cell.y, _capture_hold_turns]
		MapData.ObjectiveType.FLAG:
			if _flag_carrier != null:
				return "将旗帜带回 (%d, %d)" % [_flag_goal_cell.x, _flag_goal_cell.y]
			return "拾取 (%d, %d) 的旗帜，带回 (%d, %d)" % [
				_flag_cell.x, _flag_cell.y, _flag_goal_cell.x, _flag_goal_cell.y]
		MapData.ObjectiveType.ASSAULT:
			if _assault_target_name != "":
				return "击杀目标：%s" % UnitDataManager.get_display_name(_assault_target_name)
			return "击杀 Boss"
	return ""


func force_complete() -> void:
	if _state == State.INACTIVE: return
	_state = State.COMPLETED
	objective_completed.emit()
	print("[Objective] 目标被 GM 强制完成")
