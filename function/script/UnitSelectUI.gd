# UnitSelectUI.gd
extends CanvasLayer

var selected_units: Array[String] = []   # 存储选中的 unit_name（类型）
var max_selection: int = 3

@onready var unit_buttons = $UnitListContainer/VBoxContainer
@onready var main_label = $MainUnitLabel
@onready var slot1_label = $Slot1Label
@onready var slot2_label = $Slot2Label
@onready var confirm_btn = $BottomBar/ConfirmButton
@onready var back_btn = $BottomBar/BackButton

const EquipmentConfig = preload("res://function/script/EquipmentConfig.gd")

func _ready():
	if MusicManager.config and MusicManager.config.unit_select_music:
		MusicManager.play_music(MusicManager.config.unit_select_music)
	
	_make_label_clickable(main_label, 0)
	_make_label_clickable(slot1_label, 1)
	_make_label_clickable(slot2_label, 2)
	
	_setup_unit_buttons()
	_update_labels()

func _make_label_clickable(label: Label, index: int):
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_slot_clicked(index)
	)
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _setup_unit_buttons():
	for child in unit_buttons.get_children():
		child.queue_free()

	var unlocked = Globals.get_unlocked_units()
	unlocked.sort()

	for unit_name in unlocked:
		var btn = Button.new()
		btn.text = UnitDataManager.get_display_name(unit_name)
		btn.set_meta("unit_name", unit_name)
		btn.add_theme_font_size_override("font_size", 8)
		btn.size = Vector2(100, 30)
		var selected = unit_name in selected_units
		btn.disabled = selected
		btn.modulate = Color(0.5, 0.5, 0.5) if selected else Color.WHITE
		btn.pressed.connect(_on_unit_selected.bind(unit_name, btn))
		unit_buttons.add_child(btn)

func _on_unit_selected(unit_name: String, btn: Button):
	if unit_name in selected_units:
		selected_units.erase(unit_name)
		btn.disabled = false
		btn.modulate = Color.WHITE
		_update_labels()
		SoundManager.play_cancel_sound()
		return

	if selected_units.size() >= max_selection:
		SoundManager.play_invalid_sound()
		return

	selected_units.append(unit_name)
	btn.disabled = true
	btn.modulate = Color(0.5, 0.5, 0.5)
	_update_labels()
	SoundManager.play_select_sound()

func _on_slot_clicked(index: int):
	if index < selected_units.size():
		var unit_name = selected_units[index]
		selected_units.remove_at(index)
		for child in unit_buttons.get_children():
			if child is Button and child.get_meta("unit_name") == unit_name:
				child.disabled = false
				child.modulate = Color.WHITE
				break
		_update_labels()
		SoundManager.play_cancel_sound()

func _update_labels():
	var slots = ["主单位", "辅助1", "辅助2"]
	var labels = [main_label, slot1_label, slot2_label]
	for i in range(max_selection):
		if i < selected_units.size():
			var unit_name = selected_units[i]
			labels[i].text = slots[i] + ": " + UnitDataManager.get_display_name(unit_name)
		else:
			labels[i].text = slots[i] + ": (未选择)"
	confirm_btn.disabled = selected_units.size() < max_selection

func _on_confirm_pressed():
	# 检查是否有空存档槽
	var target_slot = -1
	if SaveManager.current_slot != -1:
		target_slot = SaveManager.current_slot
	elif Globals.pending_save_slot != -1:
		target_slot = Globals.pending_save_slot
	else:
		target_slot = SaveManager.find_empty_slot()
		if target_slot == -1:
			var dialog = AcceptDialog.new()
			dialog.dialog_text = "所有存档槽已满，请先删除一个存档。"
			add_child(dialog)
			dialog.popup_centered()
			return

	# 打开装备配置面板
	var config = load("res://content/scenes/ui/EquipmentConfig.tscn").instantiate()
	add_child(config)
	config.init(selected_units, target_slot, EquipmentConfig.Mode.DEPLOY)

func _on_back_pressed():
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")
