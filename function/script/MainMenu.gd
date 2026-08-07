extends Control

func _ready():
	MusicManager.play_main_menu_music()

func _on_start_pressed():
	SaveManager.reset_current_slot()
	Globals.pending_save_slot = -1
	get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")

func _on_load_pressed():
	# 加载存档选择界面
	var save_ui = load("res://content/scenes/ui/SaveSelectUI.tscn").instantiate()
	add_child(save_ui)

func _on_quit_pressed():
	get_tree().quit()
