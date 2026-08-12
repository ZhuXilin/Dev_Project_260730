extends CanvasLayer

@onready var panel = $ItemPanel
@onready var icon = $ItemPanel/BoxContainer/Icon
@onready var name_label = $ItemPanel/BoxContainer/Name
@onready var count_label = $ItemPanel/BoxContainer/Count

func show_item(item_id: String, count: int):
	var data = ItemManager.get_item_data(item_id)
	if not data:
		queue_free()
		return

	_setup_popup()
	icon.visible = true
	count_label.visible = true
	icon.texture = data.icon
	name_label.text = data.name
	count_label.text = "x" + str(count)
	panel.visible = true
	_auto_close()

func show_unit_unlock(units: Array):
	_setup_popup()
	icon.visible = false
	count_label.visible = false
	name_label.text = "解锁单位：\n" + ", ".join(units)
	panel.visible = true
	_auto_close()

func _setup_popup():
	Globals.is_item_get_popup_active = true
	MusicManager.pause_and_save()
	SoundManager.play_get_item_sound()

func _auto_close():
	await get_tree().create_timer(2.0).timeout
	Globals.is_item_get_popup_active = false
	MusicManager.resume_saved()
	queue_free()
