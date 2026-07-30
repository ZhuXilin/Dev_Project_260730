@tool
extends Node2D
class_name BattleStartEvent

@export var event_id: String = "":
	set(value):
		event_id = value
		if Engine.is_editor_hint():
			_update_preview()

const CELL_SIZE = 16

func _ready():
	if Engine.is_editor_hint():
		_update_preview()
	else:
		hide()

func _update_preview():
	for child in get_children():
		child.queue_free()

	var rect = ColorRect.new()
	rect.size = Vector2(CELL_SIZE, CELL_SIZE)
	rect.position = Vector2(CELL_SIZE/2.0, CELL_SIZE/2.0) - rect.size / 2
	rect.color = Color(0.7, 0.3, 0.9, 0.3)  # 紫色
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -1
	add_child(rect)

	var label = Label.new()
	label.text = "BS" if event_id.is_empty() else event_id.substr(0, 4)
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(CELL_SIZE, CELL_SIZE)
	label.position = Vector2(CELL_SIZE/2.0, CELL_SIZE/2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

func _get_configuration_warnings():
	if event_id.is_empty():
		return ["Event ID 不能为空"]
	return []

func export_config() -> Dictionary:
	return {
		"type": "battle_start",
		"event_id": event_id,
		"position": Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	}
