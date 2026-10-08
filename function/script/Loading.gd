extends Control

@onready var map_name_label = $MapNameLabel
@onready var timer = $Timer

func _ready():
	MusicManager.stop_music()
	if GameState.current_map_data:
		map_name_label.text = GameState.current_map_data.map_name
	else:
		map_name_label.text = "未命名地图"

	# ★ 整屏扫描线揭示
	PanelRevealer.show_panel(self, 0.35)   # 稍慢，让过渡更明显

	timer.start(2.0)
	timer.timeout.connect(_on_timer_timeout)

func _on_timer_timeout():
	MusicManager.stop_music()
	get_tree().change_scene_to_file(Config.PATHS.BATTLEFIELD_SCENE)
