extends Control

@onready var map_name_label : Label = $MapNameLabel
@onready var timer : Timer = $Timer

func _ready():
	# ---- 停止当前正在播放的音乐（如主菜单音乐） ----
	MusicManager.stop_music()
	
	if Globals.current_map_data:
		map_name_label.text = Globals.current_map_data.map_name
	else:
		map_name_label.text = "未命名地图"
	
	timer.start(2.0)
	timer.timeout.connect(_on_timer_timeout)

func _on_timer_timeout():
	# ---- 再次确保音乐已停止，然后切换场景 ----
	MusicManager.stop_music()
	get_tree().change_scene_to_file("res://content/scenes/levels/Battlefield.tscn")
