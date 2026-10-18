extends Control

@onready var map_name_label = $MapNameLabel
@onready var timer = $Timer

func _ready():
	# ★ 强制底层的 Clear Color 为纯黑，彻底杜绝任何底层颜色泄漏（比如红边）
	RenderingServer.set_default_clear_color(Color.BLACK)

	MusicManager.stop_music()
	if GameState.current_map_data:
		map_name_label.text = GameState.current_map_data.map_name
	else:
		map_name_label.text = "未命名地图"

	# ★ 显式传入纯黑作为遮罩底色
	# 这样纯黑遮罩从上往下退开时，连同黑色背景和白色文字，会像是同一层被扫开
	PanelRevealer.show_panel(self, 0.35, Color(0, 0, 0, 1))

	timer.start(2.0)
	timer.timeout.connect(_on_timer_timeout)


func _on_timer_timeout():
	MusicManager.stop_music()
	get_tree().change_scene_to_file(Config.PATHS.BATTLEFIELD_SCENE)
