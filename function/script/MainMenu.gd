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
	# v5.16 修复：开局计数/新手福利/埋点 begin_run 统一由 UnitSelectUI 确认队伍后
	# 的 start_new_cycle() 触发一次。此处若调用会让一次新游戏累计 +3 局、
	# 首局误领 +600 魂。这里只重置状态并存入营地。
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
