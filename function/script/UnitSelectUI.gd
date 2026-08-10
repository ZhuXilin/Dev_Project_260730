extends CanvasLayer

var all_unit_names: Array[String] = ["剑士", "枪兵", "斧兵", "弓兵", "飞马", "法师", "修女", "龙人", "重甲兵"]
var selected_units: Array[String] = []
var max_selection: int = 3

@onready var unit_buttons = $UnitListContainer/VBoxContainer
@onready var main_label = $MainUnitLabel
@onready var slot1_label = $Slot1Label
@onready var slot2_label = $Slot2Label
@onready var confirm_btn = $BottomBar/ConfirmButton
@onready var back_btn = $BottomBar/BackButton

func _ready():
	if MusicManager.config and MusicManager.config.unit_select_music:
		MusicManager.play_music(MusicManager.config.unit_select_music)
	_setup_unit_buttons()
	_update_labels()

func _setup_unit_buttons():
	for child in unit_buttons.get_children():
		child.queue_free()
	for unit_name in all_unit_names:
		var btn = Button.new()
		btn.text = unit_name
		btn.add_theme_font_size_override("font_size", 8)
		btn.size = Vector2(100, 30)
		btn.pressed.connect(_on_unit_selected.bind(unit_name, btn))
		unit_buttons.add_child(btn)

func _on_unit_selected(unit_name: String, btn: Button):
	if unit_name in selected_units:
		selected_units.erase(unit_name)
		btn.modulate = Color.WHITE
		_update_labels()
		return
	if selected_units.size() >= max_selection:
		return
	selected_units.append(unit_name)
	btn.modulate = Color.GREEN
	_update_labels()

func _update_labels():
	main_label.text = "主单位: " + (selected_units[0] if selected_units.size() >= 1 else "(未选择)")
	slot1_label.text = "辅助1: " + (selected_units[1] if selected_units.size() >= 2 else "(未选择)")
	slot2_label.text = "辅助2: " + (selected_units[2] if selected_units.size() >= 3 else "(未选择)")
	confirm_btn.disabled = selected_units.size() < 3

func _on_confirm_pressed():
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

	Globals.pending_save_slot = target_slot
	GameState.initialize_party(selected_units, 0)
	GameState.start_new_cycle()
	GameState.reset_progress()
	GameState.interrupt_state = 2
	SaveManager.save_game(target_slot, false)
	LevelManager.start_game()

func _on_back_pressed():
	MusicManager.stop_music()
	GameState.interrupt_state = 1
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")
