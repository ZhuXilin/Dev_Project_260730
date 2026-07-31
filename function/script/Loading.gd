extends Control

@onready var map_name_label = $MapNameLabel
@onready var timer = $Timer

func _ready():
	MusicManager.stop_music()
	if Globals.current_map_data:
		map_name_label.text = Globals.current_map_data.map_name
	else:
		map_name_label.text = "未命名地图"
	timer.start(2.0)
	timer.timeout.connect(_on_timer_timeout)

func _on_timer_timeout():
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/levels/Battlefield.tscn")
