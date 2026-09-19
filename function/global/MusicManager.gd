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
		print("音乐配置加载成功")
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

func _sync_volume_from_global():
	if player:
		var vol = Globals.music_volume
		var db = linear_to_db(vol) if vol > 0 else -80.0
		player.volume_db = db
		print("音乐音量已同步为: ", vol, " (", db, " dB)")

func set_music_volume(value: float):
	Globals.music_volume = value
	var db = linear_to_db(value) if value > 0 else -80.0
	player.volume_db = db

func get_music_volume() -> float:
	return db_to_linear(player.volume_db)

func play_music(stream: AudioStream):
	if config == null:
		push_error("音乐配置未加载，无法播放")
		return
	if stream == null:
		push_error("尝试播放空音乐流")
		return
	print("播放音乐：", stream.resource_path if stream.resource_path else "未命名流")
	if player.stream == stream and player.playing:
		print("音乐已在播放中，跳过")
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
	if config: play_music(config.main_menu_music)

func play_player_turn_music():
	if config: play_music(config.player_turn_music)

func play_enemy_turn_music():
	if config: play_music(config.enemy_turn_music)

func play_victory_music():
	if config: play_music(config.victory_music)

func play_defeat_music():
	if config: play_music(config.defeat_music)

func play_win_game_music():
	if config: play_music(config.win_game_music)

func set_master_volume_db(volume: float):
	if player:
		player.volume_db = volume

func play_arena_music():
	if config and config.arena_music:
		play_music(config.arena_music)
	else:
		push_warning("未设置斗技场音乐")

func play_arena_battle_music():
	if config and config.arena_battle_music:
		play_music(config.arena_battle_music)
	else:
		push_warning("未设置斗技场战斗音乐")

func play_soul_altar_music():
	if config and config.soul_altar_music:
		play_music(config.soul_altar_music)
	else:
		if config and config.camp_music:
			play_music(config.camp_music)

func play_anvil_tavern_music():
	if config and config.anvil_tavern_music:
		play_music(config.anvil_tavern_music)
	else:
		if config and config.camp_music:
			play_music(config.camp_music)

# ★ 新增
func play_hero_shrine_music():
	if config and config.hero_shrine_music:
		play_music(config.hero_shrine_music)
	else:
		if config and config.camp_music:
			play_music(config.camp_music)

# ★ 新增
func play_hero_shrine_convert_music():
	if config and config.hero_shrine_convert_music:
		play_music(config.hero_shrine_convert_music)
	else:
		if config and config.victory_music:
			play_music(config.victory_music)

func pause_and_save() -> bool:
	if player and player.playing:
		_saved_stream = player.stream
		_saved_position = player.get_playback_position()
		player.stop()
		print("已保存音乐: ", _saved_stream, " 位置: ", _saved_position)
		return true
	return false

func play_dialogue_music():
	if config and config.dialogue_music:
		player.stop()
		player.stream = config.dialogue_music
		player.play()
		print("播放对话音乐")
	else:
		push_warning("未设置对话音乐，跳过播放")

func resume_saved():
	if _saved_stream:
		player.stop()
		player.stream = _saved_stream
		player.seek(_saved_position)
		player.play()
		print("恢复音乐: ", _saved_stream, " 位置: ", _saved_position)
		_saved_stream = null
		_saved_position = 0.0
	else:
		print("没有保存的音乐可恢复")
