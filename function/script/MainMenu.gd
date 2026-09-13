extends Control

func _ready():
	MusicManager.play_main_menu_music()

func _on_start_pressed():
	SaveManager.reset_current_slot()
	Globals.pending_save_slot = -1
	var slot = SaveManager.find_empty_slot()
	if slot == -1:
		Globals.show_confirm(  # ← 这里已经用了 show_confirm，没有问题
			self,
			"所有存档槽已满，请先删除一个存档。",
			"确定",
			"",
			func(): pass,
			func(): pass,
			false
		)
		return
	Globals.pending_save_slot = slot
	GameState.reset_all()
	GameState.start_new_cycle()
	GameState.interrupt_state = GameState.InterruptState.CAMP
	SaveManager.save_game(slot, false)
	SaveManager.current_slot = slot
	get_tree().change_scene_to_file(Config.PATHS.CAMP)

func _on_load_pressed():
	# 加载存档选择界面
	var save_ui = load(Config.PATHS.SAVE_SELECT_UI).instantiate()
	add_child(save_ui)

func _on_quit_pressed():
	get_tree().quit()

func _on_continue_pressed():
	var slot = SaveManager.current_slot
	if slot == -1:
		for i in range(SaveManager.SLOT_COUNT):
			if SaveManager.has_save(i):
				slot = i
				break
	if slot == -1:
		_show_continue_error("没有可继续的游戏进度。")
		return

	var save = SaveManager.load_save_data(slot)
	if not save:
		_show_continue_error("无法读取存档，可能已损坏。")
		return

	if not SaveManager.is_map_data_valid(save):
		SaveManager.clean_invalid_progress(slot)
		save = SaveManager.load_save_data(slot)
		_show_continue_error("存档数据异常，已重置地图进度，临时资源已丢弃。")
		SaveManager._apply_save_data(save)
		get_tree().change_scene_to_file(Config.PATHS.CAMP)
		return

	SaveManager._apply_save_data(save)
	match save.interrupt_state as GameState.InterruptState:
		GameState.InterruptState.MAP:
			get_tree().change_scene_to_file(Config.PATHS.MAP_SCENE)
		GameState.InterruptState.BATTLEFIELD:
			print("战场中断恢复功能开发中，直接进入营地")
			get_tree().change_scene_to_file(Config.PATHS.CAMP)
		_:
			get_tree().change_scene_to_file(Config.PATHS.CAMP)

func _show_continue_error(message: String):
	Globals.show_confirm(
		self,
		message,
		"确定",
		"",
		func(): pass,
		func(): pass,
		false
	)
