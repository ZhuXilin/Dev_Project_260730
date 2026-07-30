@tool
extends Node2D
class_name HpFunction

@export var hp_amount: int = 5:
	set(value):
		hp_amount = value
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
	rect.color = Color.GREEN if hp_amount > 0 else Color.RED
	rect.color.a = 0.3
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = -1
	add_child(rect)

	var label = Label.new()
	label.text = str(hp_amount)
	label.add_theme_font_size_override("font_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(CELL_SIZE, CELL_SIZE)
	label.position = Vector2(CELL_SIZE/2.0, CELL_SIZE/2.0) - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

func _get_configuration_warnings():
	if hp_amount == 0:
		return ["hp_amount 为 0 无效果"]
	return []

func export_config() -> Dictionary:
	return {
		"type": "hp_function",
		"hp_amount": hp_amount,
		"position": Vector2i(floor(position.x / CELL_SIZE), floor(position.y / CELL_SIZE))
	}
