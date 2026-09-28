@tool
extends Node2D
class_name EventTrigger

@export var event_id: String = "":
	set(value):
		event_id = value
		if Engine.is_editor_hint():
			_update_preview()

## ★ 直接在此节点配遗物解锁（无需 event_id 也能用）
@export var unlock_relics: Array[String] = []:
	set(value):
		unlock_relics = value
		if Engine.is_editor_hint():
			_update_preview()


func _ready():
	if Engine.is_editor_hint():
		_update_preview()
	else:
		hide()


func _update_preview():
	for child in get_children():
		child.queue_free()

	var rect = ColorRect.new()
	rect.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	rect.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - rect.size / 2
	rect.color = MapConst.HIGHLIGHT_EVENT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -1
	add_child(rect)

	var label = Label.new()
	# ★ 显示：事件 ID 前 4 字 / "RL"（只有遗物）/ "E"（空）
	var txt : String = "E"
	if event_id != "":
		txt = event_id.substr(0, 4)
	elif not unlock_relics.is_empty():
		txt = "RL"
	label.text = txt
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(MapConst.CELL_SIZE, MapConst.CELL_SIZE)
	label.position = Vector2(MapConst.CELL_SIZE/2.0, MapConst.CELL_SIZE/2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _get_configuration_warnings():
	var warnings = PackedStringArray()

	if event_id.is_empty() and unlock_relics.is_empty():
		warnings.append("event_id 和 unlock_relics 不能同时为空")

	# ---- 网格顶点对齐检查 ----
	var pos = position
	var cell_size = MapConst.CELL_SIZE
	var x_mod = fmod(pos.x, cell_size)
	var y_mod = fmod(pos.y, cell_size)
	var x_aligned = abs(x_mod) < 0.01
	var y_aligned = abs(y_mod) < 0.01

	if not x_aligned or not y_aligned:
		warnings.append("节点位置未对齐到网格顶点（应位于格子角点，坐标应为 %d 的整数倍）。建议使用网格吸附功能。" % MapConst.CELL_SIZE)

	return warnings


func export_config() -> Dictionary:
	return {
		"type": "event_trigger",
		"event_id": event_id,
		"unlock_relics": unlock_relics.duplicate(),
		"position": Vector2i(floor(position.x / MapConst.CELL_SIZE), floor(position.y / MapConst.CELL_SIZE))
	}
