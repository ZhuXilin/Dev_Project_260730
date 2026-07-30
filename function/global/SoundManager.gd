extends Node

var config : SoundConfig
var player : AudioStreamPlayer
var looping_player : AudioStreamPlayer

const CONFIG_PATH : String = "res://content/scenes/levels/SoundConfig.tres"

func _ready():
	_load_config()
	_setup_players()
	# 从全局加载音量设置
	_sync_volume_from_global()

func _load_config():
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
		if config:
			print("音效配置加载成功")
		else:
			push_error("音效配置资源类型错误：", CONFIG_PATH)
	else:
		push_error("音效配置文件未找到：", CONFIG_PATH)

func _setup_players():
	player = AudioStreamPlayer.new()
	add_child(player)
	looping_player = AudioStreamPlayer.new()
	add_child(looping_player)
	# 音量由 _sync_volume_from_global 设置

func _sync_volume_from_global():
	if player and looping_player:
		var vol = Globals.sound_volume
		var db = linear_to_db(vol) if vol > 0 else -80.0
		player.volume_db = db
		looping_player.volume_db = db
		print("音效音量已同步为: ", vol, " (", db, " dB)")

func set_sound_volume(value: float):
	# 更新全局变量
	Globals.sound_volume = value
	var db = linear_to_db(value) if value > 0 else -80.0
	player.volume_db = db
	looping_player.volume_db = db

func get_sound_volume() -> float:
	return db_to_linear(player.volume_db)

func play_sound(stream: AudioStream):
	if config == null or stream == null:
		return
	player.stop()
	player.stream = stream
	player.play()

func play_move_sound(_unit: Unit = null):
	if config == null:
		return
	var stream = config.move_sound
	if stream == null:
		return
	if looping_player.stream == stream and looping_player.playing:
		return
	stop_looping()
	looping_player.stream = stream
	looping_player.play()

func stop_looping():
	if looping_player.playing:
		looping_player.stop()
		looping_player.stream = null

func play_select_sound():
	if config:
		play_sound(config.select_unit)

func play_hit_sound():
	if config:
		play_sound(config.hit)

func play_miss_sound():
	if config:
		play_sound(config.miss)

func play_heal_sound():
	if config:
		play_sound(config.heal)

func play_cancel_sound():
	if config:
		play_sound(config.cancel)

func play_invalid_sound():
	if config:
		play_sound(config.invalid_click)

func play_wait_sound():
	if config:
		play_sound(config.wait)

func play_get_item_sound():
	if config:
		play_sound(config.get_item)
