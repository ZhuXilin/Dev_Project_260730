@tool
extends Node2D
class_name VictoryObjectiveTrigger

## ============================================================
##  VictoryObjectiveTrigger — 战场地图胜利条件触发器（v6.58）
## ============================================================
##  每张战场地图 .tscn 里放一个（且仅一个）本节点，胜利条件跟着"地图"走，
##  而不是跟着"地图节点/布局槽位"走——这样随机地图节点类型也不会错配目标。
##
##  数据流：
##    本节点 export_config()
##      → MapLoader 加载地图场景时提取，存到 Battlefield.victory_objective_config
##      → ObjectiveManager.setup_for_config(config) 读取并判定胜利
##      → MapGenerator 预读 scene → MapNode.objective_type → 地图节点按钮显示标记
##
##  没有本节点 / 配置为空 → 默认全灭（ANNIHILATE）。
##  配置方式沿用原 MapData.ObjectiveType 枚举，与参数字典一致。
## ============================================================

@export var objective_type: MapData.ObjectiveType = MapData.ObjectiveType.ANNIHILATE:
	set(value):
		objective_type = value
		if Engine.is_editor_hint():
			_update_preview()

## 目标参数字典（JSON 友好：坐标用 [x,y]，运行时 ObjectiveManager 会转 Vector2i）。
## CAPTURE: {"target_cell": [x, y], "hold_turns": n}
## FLAG:    {"flag_cell": [x, y], "goal_cell": [x, y]}
## ASSAULT: {"target_unit_name": "id"}（留空自动选 Boss）
@export var objective_params: Dictionary = {}:
	set(value):
		objective_params = value
		if Engine.is_editor_hint():
			_update_preview()

## 是否允许动态目标（仅在 objective_type=ANNIHILATE 且 params 为空时生效）。
@export var allow_dynamic_objective: bool = false:
	set(value):
		allow_dynamic_objective = value
		if Engine.is_editor_hint():
			_update_preview()

## 动态目标候选池（ObjectiveType 整数值，空=默认全部）。
@export var dynamic_objective_pool: Array[int] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_preview()
	else:
		hide()


func _update_preview() -> void:
	for child in get_children():
		child.queue_free()

	var s := float(MapConst.CELL_SIZE)
	var rect := ColorRect.new()
	rect.size = Vector2(s, s)
	rect.position = Vector2(s / 2.0, s / 2.0) - rect.size / 2
	rect.color = MapConst.HIGHLIGHT_OBJECTIVE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -1
	add_child(rect)

	var label := Label.new()
	label.text = _type_mark()
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(s, s)
	label.position = Vector2(s / 2.0, s / 2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _type_mark() -> String:
	match objective_type:
		MapData.ObjectiveType.CAPTURE: return "占"
		MapData.ObjectiveType.FLAG: return "旗"
		MapData.ObjectiveType.ASSAULT: return "突"
		_: return "灭" if not allow_dynamic_objective else "？"


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if objective_params.is_empty():
		return warnings
	# 参数键做轻量校验，避免拼错导致目标 fallback 到默认值
	var valid_keys := ["target_cell", "hold_turns", "flag_cell", "goal_cell", "target_unit_name"]
	for k in objective_params:
		if not valid_keys.has(str(k)):
			warnings.append("objective_params 含未知键「%s」（可用：%s）" % [
				str(k), ", ".join(valid_keys)])
	return warnings


## 导出胜利条件配置。MapLoader / MapGenerator 都通过此接口读取。
func export_config() -> Dictionary:
	return {
		"type": "victory_objective",
		"objective_type": int(objective_type),
		"objective_params": objective_params.duplicate(true),
		"allow_dynamic_objective": allow_dynamic_objective,
		"dynamic_objective_pool": dynamic_objective_pool.duplicate(),
	}
