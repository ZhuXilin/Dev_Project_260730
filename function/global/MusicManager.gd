extends Node

var config : MusicConfig
var player : AudioStreamPlayer
var _saved_stream : AudioStream = null
var _saved_position : float = 0.0

const CONFIG_PATH : String = Config.PATHS.MUSIC_CONFIG

func _ready():
	_load_config()
	_setup_player()
	_sync_volume_from_global()
	if config:
		print("音乐配置加载成功，包含: ", config.get_property_list())
	else:
		push_error("音乐配置加载失败！")

func _load_config():
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
		if config:
			print("音乐配置加载成功")
		else:
			push_error("音乐配置资源类型错误：", CONFIG_PATH)
	else:
		push_error("音乐配置文件未找到：", CONFIG_PATH)

func _setup_player():
	player = AudioStreamPlayer.new()
	add_child(player)
	# 音量由 _sync_volume_from_global 设置

func _sync_volume_from_global():
	if player:
		var vol = Globals.music_volume
		var db = linear_to_db(vol) if vol > 0 else -80.0
		player.volume_db = db
		print("音乐音量已同步为: ", vol, " (", db, " dB)")

func set_music_volume(value: float):
	# 更新全局变量
	Globals.music_volume = value
	# 应用到播放器
	var db = linear_to_db(value) if value > 0 else -80.0
	player.volume_db = db

func get_music_volume() -> float:
	return db_to_linear(player.volume_db)

func play_music(stream: AudioStream):
	if config == null:
		push_error("音乐配置未加载，无法播放")
		return
	if stream == null:
		push_error("尝试播放空音乐流，请检查 MusicConfig 资源")
		return
	
	if player.stream == stream and player.playing:
		return
	player.stop()
	player.stream = stream
	player.play()
	
	var vol = Globals.music_volume
	var db = linear_to_db(vol) if vol > 0 else -80.0
	player.volume_db = db

func stop_music():
	if player and player.playing:
		player.stop()
		print("音乐已停止")

func play_main_menu_music():
	if config:
		play_music(config.main_menu_music)

func play_player_turn_music():
	if config:
		play_music(config.player_turn_music)

func play_enemy_turn_music():
	if config:
		play_music(config.enemy_turn_music)

func play_victory_music():
	if config:
		play_music(config.victory_music)

func play_defeat_music():
	if config:
		play_music(config.defeat_music)

func play_win_game_music():
	if config:
		play_music(config.win_game_music)

func set_master_volume_db(volume: float):
	if player:
		player.volume_db = volume

# 暂停当前音乐并保存状态
func pause_and_save() -> bool:
	if player and player.playing:
		_saved_stream = player.stream
		_saved_position = player.get_playback_position()
		player.stop()
		print("已保存音乐: ", _saved_stream, " 位置: ", _saved_position)
		return true
	return false

# 播放对话音乐（不保存当前状态，外部已调用 pause_and_save）
func play_dialogue_music():
	if config and config.dialogue_music:
		player.stop()
		player.stream = config.dialogue_music
		player.play()
		print("播放对话音乐")
	else:
		push_warning("未设置对话音乐，跳过播放")

# 恢复之前保存的音乐
func resume_saved():
	if _saved_stream:
		player.stop()
		player.stream = _saved_stream
		player.seek(_saved_position)
		player.play()
		print("恢复音乐: ", _saved_stream, " 位置: ", _saved_position)
		# 清空保存
		_saved_stream = null
		_saved_position = 0.0
	else:
		print("没有保存的音乐可恢复")
