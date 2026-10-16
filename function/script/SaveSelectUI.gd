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
			var save_data = SaveManager.load_save_data(i)
			var time_str = Time.get_datetime_string_from_unix_time(save_data.save_time)

			if save_data and not save_data.party_data.is_empty() and save_data.current_day > 0:
				var unit_names = []
				for j in range(save_data.party_data.size()):
					var party_info = save_data.party_data[j]
					var unit_name = party_info.get("display_name", party_info.get("unit_name", "未知"))
					unit_names.append(unit_name)
				var unit_list_str = "、".join(unit_names)
				var day_str = "第" + str(save_data.current_day) + "天"
				var state_suffix = ""
				# ★ 第八批：在存档列表上标注"战斗中"状态，让玩家有预期
				if save_data.interrupt_state == GameState.InterruptState.BATTLEFIELD:
					state_suffix = " [战斗中]"
				info_label.text = "存档%d：%s %s  %s%s" % [
					i + 1, unit_list_str, day_str, time_str, state_suffix]
			else:
				info_label.text = "存档%d：营地休息中  %s" % [i + 1, time_str]
		else:
			info_label.text = "存档%d：空" % (i + 1)

		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.add_theme_font_size_override("font_size", 8)
		hbox.add_child(info_label)

		var load_btn = Button.new()
		load_btn.add_theme_font_size_override("font_size", 8)
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		if has_save:
			load_btn.text = "加载"
			load_btn.pressed.connect(_on_load_pressed.bind(i))
		else:
			load_btn.text = "新游戏"
			load_btn.pressed.connect(_on_new_game_pressed.bind(i))

		hbox.add_child(load_btn)

		var delete_btn = Button.new()
		delete_btn.text = "删除"
		delete_btn.add_theme_font_size_override("font_size", 8)
		delete_btn.visible = has_save
		delete_btn.disabled = not has_save
		if has_save:
			delete_btn.pressed.connect(_on_delete_pressed.bind(i))
		hbox.add_child(delete_btn)

		slot_container.add_child(hbox)


# ============================================================
#  ★ 第八批：加载前先看 interrupt_state，战场上弹确认
# ============================================================
func _on_load_pressed(slot: int):
	# 先 dry-run 检查状态，不 apply
	var save_data : SaveData = SaveManager.load_save_data(slot)
	if not save_data:
		return

	if save_data.interrupt_state == GameState.InterruptState.BATTLEFIELD:
		Globals.show_confirm(
			self,
			"该存档在战斗中，无法恢复战斗进度。\n是否回到营地继续？\n（战场上的临时资源将丢失）",
			"回到营地", "取消",
			func(): _do_load_and_go_camp(slot),
			func(): pass
		)
		return

	_do_load_and_go(slot)


func _do_load_and_go(slot: int):
	var success = SaveManager.load_game(slot)
	if not success:
		return

	var state : int = GameState.interrupt_state

	match state:
		GameState.InterruptState.CAMP:
			get_tree().change_scene_to_file(Config.PATHS.CAMP)
		GameState.InterruptState.MAP:
			if GameState.party.is_empty():
				GameState.interrupt_state = GameState.InterruptState.CAMP
				get_tree().change_scene_to_file(Config.PATHS.CAMP)
			else:
				get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)
		_:
			if GameState.party.is_empty():
				get_tree().change_scene_to_file(Config.PATHS.CAMP)
			else:
				get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)


func _do_load_and_go_camp(slot: int):
	var success = SaveManager.load_game(slot)
	if not success:
		return
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(slot, false)
	get_tree().change_scene_to_file(Config.PATHS.CAMP)


func _on_new_game_pressed(slot: int):
	GameState.reset_all()
	GameState.start_new_cycle()
	GameState.interrupt_state = GameState.InterruptState.CAMP
	Globals.pending_save_slot = slot
	SaveManager.save_game(slot, false)
	SaveManager.current_slot = slot
	get_tree().change_scene_to_file(Config.PATHS.CAMP)


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
