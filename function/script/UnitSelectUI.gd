extends CanvasLayer

var selected_units: Array[String] = []
var max_selection: int = 3
var _equipment_config_instance = null

var _hover_unit : String = ""
var _hover_exit_serial : int = 0
var _last_hover_unit : String = ""

@onready var unit_buttons = get_node_or_null("UnitListContainer/VBoxContainer")
@onready var main_label = get_node_or_null("MainUnitLabel")
@onready var slot1_label = get_node_or_null("Slot1Label")
@onready var slot2_label = get_node_or_null("Slot2Label")
@onready var confirm_btn = get_node_or_null("BottomBar/ConfirmButton")
@onready var back_btn = get_node_or_null("BottomBar/BackButton")
@onready var info_panel = get_node_or_null("InfoPanelContainer")

const EquipmentConfig = preload(Config.PATHS.EQUIPMENT_CONFIG_SCRIPT)
const COLOR_DISPATCHED : Color = Color(0.2, 0.2, 0.2, 1)
const COLOR_DISABLED   : Color = Color(0.4, 0.4, 0.4, 1)
const COLOR_NORMAL     : Color = Color.WHITE

func _ready():
	if MusicManager.config and MusicManager.config.unit_select_music:
		MusicManager.play_music(MusicManager.config.unit_select_music)
	
	if unit_buttons:
		unit_buttons.alignment = BoxContainer.ALIGNMENT_BEGIN
	
	if main_label: _make_label_clickable(main_label, 0)
	if slot1_label: _make_label_clickable(slot1_label, 1)
	if slot2_label: _make_label_clickable(slot2_label, 2)
	
	if confirm_btn:
		for conn in confirm_btn.pressed.get_connections():
			confirm_btn.pressed.disconnect(conn.callable)
		confirm_btn.pressed.connect(_on_confirm_pressed)
		
	if back_btn:
		for conn in back_btn.pressed.get_connections():
			back_btn.pressed.disconnect(conn.callable)
		back_btn.pressed.connect(_on_back_pressed)
	
	_setup_unit_buttons()
	_update_labels()

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var mp = get_viewport().get_mouse_position()

		var labels = [main_label, slot1_label, slot2_label]
		for i in range(max_selection):
			var lbl = labels[i]
			if lbl and lbl.visible and lbl.get_global_rect().has_point(mp):
				_on_slot_clicked(i)
				get_viewport().set_input_as_handled()
				return

		if _hover_unit != "" and info_panel:
			info_panel.toggle_mode()
			get_viewport().set_input_as_handled()
			return

func _make_label_clickable(label: Label, index: int):
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_clicked(index)
	)

func _setup_unit_buttons():
	if not unit_buttons: return
	for child in unit_buttons.get_children(): child.queue_free()
	var unlocked = Globals.get_unlocked_units(); unlocked.sort()
	var dispatched : Array = DispatchManager.get_dispatched_unit_names()

	for unit_name in unlocked:
		if UnitDataManager.get_unit_data(unit_name).is_empty(): continue
		
		var hbox := HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(0, 36) # ★ 增大高度
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# ★ 统一使用 32x32 图标
		var btn = UnitDataManager.create_unit_icon_button(unit_name, Vector2(32, 32))
		btn.custom_minimum_size = Vector2(32, 32)
		btn.set_meta("unit_name", unit_name)
		
		if unit_name in dispatched:
			btn.disabled = true
			btn.modulate = COLOR_DISPATCHED
		elif unit_name in selected_units:
			btn.disabled = false
			btn.modulate = COLOR_NORMAL
			btn.pressed.connect(_on_unit_selected.bind(unit_name, btn))
		else:
			btn.disabled = false
			btn.modulate = COLOR_DISABLED
			btn.pressed.connect(_on_unit_selected.bind(unit_name, btn))

		btn.mouse_entered.connect(_on_unit_hover.bind(unit_name))
		btn.mouse_exited.connect(_on_unit_hover_exit)
		
		hbox.add_child(btn)
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spacer)
		
		unit_buttons.add_child(hbox)

func _on_unit_hover(unit_name: String):
	_hover_exit_serial += 1
	_hover_unit = unit_name
	_last_hover_unit = unit_name
	if info_panel: info_panel.set_unit(unit_name)

func _on_unit_hover_exit():
	_hover_unit = ""
	_hover_exit_serial += 1
	var current_serial = _hover_exit_serial
	
	await get_tree().create_timer(0.1).timeout
	if current_serial == _hover_exit_serial and info_panel:
		if _last_hover_unit != "":
			info_panel.set_unit(_last_hover_unit)
		elif selected_units.size() > 0:
			info_panel.set_unit(selected_units[0])

# ★ 修复：不重建 UI，直接更新颜色
func _on_unit_selected(unit_name: String, _btn: Button):
	if unit_name in selected_units:
		_remove_unit(unit_name)
		return
	if selected_units.size() >= max_selection: return
	
	SoundManager.play_select_sound()
	selected_units.append(unit_name)
	
	for child in unit_buttons.get_children():
		if child.get_child_count() > 0 and child.get_child(0) is Button:
			var btn = child.get_child(0)
			var ut = btn.get_meta("unit_name", "")
			if ut != "":
				if ut in selected_units:
					btn.modulate = COLOR_NORMAL
				else:
					btn.modulate = COLOR_DISABLED
	_update_labels()

# ★ 修复：直接更新颜色
func _on_slot_clicked(index: int):
	if index < selected_units.size():
		var unit_name = selected_units[index]
		_remove_unit(unit_name)

func _remove_unit(unit_name: String):
	if unit_name in selected_units:
		SoundManager.play_cancel_sound()
		selected_units.erase(unit_name)
		
		for child in unit_buttons.get_children():
			if child.get_child_count() > 0 and child.get_child(0) is Button:
				var btn = child.get_child(0)
				var ut = btn.get_meta("unit_name", "")
				if ut != "":
					if ut in selected_units:
						btn.modulate = COLOR_NORMAL
					else:
						btn.modulate = COLOR_DISABLED
		_update_labels()

func _update_labels():
	if not main_label: return
	var slots = ["主单位", "辅助1", "辅助2"]
	var labels = [main_label, slot1_label, slot2_label]
	for i in range(max_selection):
		if labels[i] == null: continue
		if i < selected_units.size():
			labels[i].text = slots[i] + ": " + UnitDataManager.get_display_name(selected_units[i])
		else:
			labels[i].text = slots[i] + ": (未选择)"
	if confirm_btn: confirm_btn.disabled = selected_units.size() < max_selection

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
