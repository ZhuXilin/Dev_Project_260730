extends Panel
class_name SettingMenu

@onready var music_volume_slider : HSlider = $SettingMenuContainer/MusicVolumeSlider
@onready var sound_volume_slider : HSlider = $SettingMenuContainer/SoundVolumeSlider
@onready var speed_slider : HSlider = $SettingMenuContainer/SpeedSlider
@onready var speed_label : Label = $SettingMenuContainer/SpeedLabel
@onready var screen_size_option : OptionButton = $SettingMenuContainer/ScreenSizeOption
@onready var back_to_menu_btn : Button = $SettingMenuContainer/BackToMenuBtn

const BASE_WIDTH : int = Globals.BASE_WIDTH
const BASE_HEIGHT : int = Globals.BASE_HEIGHT

func _ready():
	# ---- 阻止滑杆获得焦点 ----
	speed_slider.focus_mode = Control.FOCUS_NONE

	# ---- 音量初始化 ----
	music_volume_slider.value = Globals.music_volume
	sound_volume_slider.value = Globals.sound_volume
	_on_music_volume_changed(Globals.music_volume)
	_on_sound_volume_changed(Globals.sound_volume)

	# ---- 速度初始化 ----
	speed_slider.min_value = -2
	speed_slider.max_value = 4
	speed_slider.step = 1
	speed_slider.value = Globals.game_speed
	_update_speed_label(Globals.game_speed)

	# ---- 分辨率选项 ----
	screen_size_option.clear()
	screen_size_option.add_item("1倍 (320x240)")
	screen_size_option.add_item("2倍 (640x480)")
	screen_size_option.add_item("3倍 (960x720)")
	screen_size_option.add_item("4倍 (1280x960)")
	screen_size_option.add_item("5倍 (1600x1200)")
	screen_size_option.add_item("全屏")

	var current_mode = DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		screen_size_option.selected = 5
	else:
		var current_size = DisplayServer.window_get_size()
		var found = false
		for i in range(5):
			var expected = Vector2i(BASE_WIDTH * (i + 1), BASE_HEIGHT * (i + 1))
			if abs(current_size.x - expected.x) <= 2 and abs(current_size.y - expected.y) <= 2:
				screen_size_option.selected = i
				found = true
				break
		if not found:
			var default_scale = Globals.DEFAULT_SCALE
			screen_size_option.selected = default_scale - 1
			_apply_window_size(default_scale - 1)

	# ---- 信号连接 ----
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sound_volume_slider.value_changed.connect(_on_sound_volume_changed)
	speed_slider.value_changed.connect(_on_speed_changed)
	screen_size_option.item_selected.connect(_on_screen_size_selected)

	# ---- 修改返回按钮为“中断并回到主界面” ----
	back_to_menu_btn.text = "中断并回到主界面"
	for conn in back_to_menu_btn.pressed.get_connections():
		back_to_menu_btn.pressed.disconnect(conn.callable)
	back_to_menu_btn.pressed.connect(_on_interrupt_pressed)

	SignalBus.speed_changed.connect(_on_speed_changed_from_global)

	visible = false

# ---- 音量回调 ----
func _on_music_volume_changed(value: float):
	MusicManager.set_music_volume(value)

func _on_sound_volume_changed(value: float):
	SoundManager.set_sound_volume(value)

# ---- 速度回调 ----
func _on_speed_changed(value: float):
	var int_val = int(value)
	Globals.set_game_speed(int_val)

func _on_speed_changed_from_global(new_speed: int):
	if speed_slider.value != new_speed:
		speed_slider.value = new_speed
	_update_speed_label(new_speed)

func _update_speed_label(val: int):
	speed_label.text = "速度偏移: " + str(val) + "X"

# ---- 分辨率回调 ----
func _on_screen_size_selected(index: int):
	_apply_window_size(index)

func _apply_window_size(index: int):
	if index == 5:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var multiplier = index + 1
		var width = BASE_WIDTH * multiplier
		var height = BASE_HEIGHT * multiplier
		DisplayServer.window_set_size(Vector2i(width, height))

func _on_interrupt_pressed():
	var current_scene = get_tree().current_scene
	var scene_path = current_scene.scene_file_path if current_scene else ""
	
	if scene_path.ends_with("Battlefield.tscn"):
		# 撤销当前战斗的节点访问标记，避免地图进度错误推进
		GameState.undo_battle_entry()
		GameState.interrupt_state = 2   # 回到地图（因为还在同一地图进度）
	elif scene_path.ends_with("MapScene.tscn"):
		GameState.interrupt_state = 2   # 地图中断
	# 其他场景（如营地）不修改状态
	
	SaveManager.save_game(SaveManager.current_slot, false)
	get_tree().change_scene_to_file("res://content/scenes/ui/MainMenu.tscn")
