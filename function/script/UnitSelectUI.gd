extends CanvasLayer

var selected_units: Array[String] = []
var max_selection: int = 3
var _equipment_config_instance = null
var _hover_unit : String = ""

@onready var unit_buttons = $UnitListContainer/VBoxContainer
@onready var main_label = $MainUnitLabel
@onready var slot1_label = $Slot1Label
@onready var slot2_label = $Slot2Label
@onready var confirm_btn = $BottomBar/ConfirmButton
@onready var back_btn = $BottomBar/BackButton
@onready var info_panel = $InfoPanelContainer

const EquipmentConfig = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)
const COLOR_DISPATCHED : Color = Color(0.4, 0.4, 0.4, 1)
const COLOR_DISABLED   : Color = Color(0.5, 0.5, 0.5, 1)
const COLOR_NORMAL     : Color = Color.WHITE

func _ready():
	if MusicManager.config and MusicManager.config.unit_select_music:
		MusicManager.play_music(MusicManager.config.unit_select_music)
	_make_label_clickable(main_label, 0)
	_make_label_clickable(slot1_label, 1)
	_make_label_clickable(slot2_label, 2)
	_setup_unit_buttons()
	_update_labels()

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _hover_unit != "":
			info_panel.toggle_mode()
			get_viewport().set_input_as_handled()
			return

func _make_label_clickable(label: Label, index: int):
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_slot_clicked(index)
	)

func _setup_unit_buttons():
	for child in unit_buttons.get_children(): child.queue_free()
	var unlocked = Globals.get_unlocked_units(); unlocked.sort()
	var dispatched : Array = DispatchManager.get_dispatched_unit_names()

	for unit_name in unlocked:
		if UnitDataManager.get_unit_data(unit_name).is_empty(): continue
		var btn = Button.new()
		btn.text = UnitDataManager.get_display_name_full(unit_name)
		btn.set_meta("unit_name", unit_name)
		btn.add_theme_font_size_override("font_size", 8)
		btn.size = Vector2(100, 30)

		if unit_name in dispatched:
			btn.text += "  [派遣中]"; btn.disabled = true; btn.modulate = COLOR_DISPATCHED
		elif unit_name in selected_units:
			btn.disabled = true; btn.modulate = COLOR_DISABLED
		else:
			btn.disabled = false; btn.modulate = COLOR_NORMAL
			btn.pressed.connect(_on_unit_selected.bind(unit_name, btn))

		btn.mouse_entered.connect(func():
			_hover_unit = unit_name
			info_panel.set_unit(unit_name)
		)
		btn.mouse_exited.connect(func():
			_hover_unit = ""
			info_panel.clear_info()
		)
		unit_buttons.add_child(btn)

func _on_unit_selected(unit_name: String, btn: Button):
	if unit_name in selected_units:
		selected_units.erase(unit_name); btn.disabled = false; btn.modulate = COLOR_NORMAL; _update_labels(); return
	if selected_units.size() >= max_selection: return
	selected_units.append(unit_name); btn.disabled = true; btn.modulate = COLOR_DISABLED; _update_labels()

func _on_slot_clicked(index: int):
	if index < selected_units.size():
		var unit_name = selected_units[index]
		selected_units.remove_at(index)
		for child in unit_buttons.get_children():
			if child is Button and child.get_meta("unit_name") == unit_name:
				child.disabled = false; child.modulate = COLOR_NORMAL; break
		_update_labels()

func _update_labels():
	var slots = ["主单位", "辅助1", "辅助2"]
	var labels = [main_label, slot1_label, slot2_label]
	for i in range(max_selection):
		if i < selected_units.size():
			labels[i].text = slots[i] + ": " + UnitDataManager.get_display_name(selected_units[i])
		else:
			labels[i].text = slots[i] + ": (未选择)"
	confirm_btn.disabled = selected_units.size() < max_selection

func _on_confirm_pressed():
	if selected_units.size() < max_selection: return
	GameState.initialize_party(selected_units, 0)
	GameState.current_faction = UnitDataManager.get_unit_data(selected_units[0]).get("faction", "王国")
	LevelManager._reload_all_levels()
	var target_slot = SaveManager.current_slot if SaveManager.current_slot != -1 else SaveManager.find_empty_slot()
	if target_slot == -1: return

	Globals.pending_save_slot = target_slot
	GameState.start_new_cycle(); GameState.reset_progress()
	GameState.interrupt_state = GameState.InterruptState.MAP

	var config = load(Config.PATHS.EQUIPMENT_CONFIG).instantiate()
	add_child(config)
	_equipment_config_instance = config
	config.get_node("MainPanel").init(selected_units, target_slot, EquipmentConfig.Mode.DEPLOY)
	config.tree_exited.connect(func(): _equipment_config_instance = null)

func _on_back_pressed():
	MusicManager.stop_music()
	get_tree().change_scene_to_file(Config.PATHS.CAMP)
