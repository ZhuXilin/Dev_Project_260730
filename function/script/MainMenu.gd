extends Control

func _ready():
	MusicManager.play_main_menu_music()

func _on_start_pressed():
	get_tree().change_scene_to_file("res://content/scenes/ui/UnitSelectUI.tscn")

func _on_quit_pressed():
	get_tree().quit()
