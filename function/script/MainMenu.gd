extends Control

func _ready():
	MusicManager.play_main_menu_music()

func _on_start_pressed():
	LevelManager.start_game()

func _on_quit_pressed():
	get_tree().quit()
