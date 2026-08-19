extends CanvasLayer

@onready var slot_container = $Panel/SlotContainer
@onready var back_button = $Panel/BackButton

var _pending_delete_slot: int = -1

func _ready():
	_refresh_slots()
	back_button.pressed.connect(_on_back_pressed)

func _refresh_slots():
	for child in slot_container.get_children():
		child.queue_free()
	
	for i in range(SaveManager.SLOT_COUNT):
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var info_label = Label.new()
		var has_save = SaveManager.has_save(i)
		
		if has_save:
			var info = SaveManager.get_save_info(i)
			var time_str = Time.get_datetime_string_from_unix_time(info["time"])
			info_label.text = "存档%d: %s (%d人) 第%d天 %s" % [i + 1, info["main_unit"], info["party"], info["day"], time_str]
		else:
			info_label.text = "存档%d: 空" % (i + 1)
		
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.add_theme_font_size_override("font_size", 8)
		hbox.add_child(info_label)
		
		# ---- 加载/新游戏按钮 ----
		var load_btn = Button.new()
		load_btn.add_theme_font_size_override("font_size", 8)
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT   # 左对齐
		
		if has_save:
			load_btn.text = "加载"
			load_btn.pressed.connect(_on_load_pressed.bind(i))
		else:
			load_btn.text = "新游戏"
			load_btn.pressed.connect(_on_new_game_pressed.bind(i))
		
		hbox.add_child(load_btn)
		
		# ---- 删除按钮 ----
		var delete_btn = Button.new()
		delete_btn.text = "删除"
		delete_btn.add_theme_font_size_override("font_size", 8)
		delete_btn.visible = has_save
		delete_btn.disabled = not has_save
		if has_save:
			delete_btn.pressed.connect(_on_delete_pressed.bind(i))
		hbox.add_child(delete_btn)
		
		slot_container.add_child(hbox)

func _on_load_pressed(slot: int):
	var success = SaveManager.load_game(slot)
	if success:
		get_tree().change_scene_to_file("res://content/scenes/ui/MapScene.tscn")

func _on_new_game_pressed(slot: int):
	GameState.reset_all()
	GameState.start_new_cycle()
	GameState.interrupt_state = 1
	Globals.pending_save_slot = slot
	SaveManager.save_game(slot, false)
	SaveManager.current_slot = slot
	get_tree().change_scene_to_file("res://content/scenes/ui/Camp.tscn")

func _on_delete_pressed(slot: int):
	_pending_delete_slot = slot
	Globals.show_confirm(
		self,
		"确定删除存档槽 %d 吗？" % (slot + 1),
		"删除",
		"取消",
		_on_delete_confirmed,
		_on_delete_canceled
	)

func _on_delete_confirmed():
	if _pending_delete_slot != -1:
		SaveManager.delete_save(_pending_delete_slot)
		_pending_delete_slot = -1
		_refresh_slots()

func _on_delete_canceled():
	_pending_delete_slot = -1

func _on_back_pressed():
	queue_free()
