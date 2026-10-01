extends Node

# ============================================================
#  MusicManager — 音乐播放（普通 + 8-bit chip 混合）
# ============================================================

const CONFIG_PATH : String = Config.PATHS.MUSIC_CONFIG

# ---- 普通音乐 ----
var config : MusicConfig
var player : AudioStreamPlayer
var _saved_stream : AudioStream = null
var _saved_position : float = 0.0

# ---- Chip 音乐 ----
var _chip_player: ChipMusicPlayer = null
var _chip_song_cache: Dictionary = {}    # path -> ChipSong
var _chip_slot_map: Dictionary = {}      # slot_name -> json_path

# ---- 记录当前/暂停中的 chip 音乐 ----
var _chip_current_path : String = ""
var _chip_current_slot : String = ""
var _saved_chip_path : String = ""
var _saved_chip_slot : String = ""


# ============================================================
#  生命周期
# ============================================================
func _ready():
	_load_config()
	_setup_player()
	_sync_volume_from_global()

	# chip 播放器
	_chip_player = ChipMusicPlayer.new()
	add_child(_chip_player)

	# 扫描 chip JSON
	_scan_chip_music()

	if config == null:
		push_error("音乐配置加载失败！")


# ============================================================
#  配置加载
# ============================================================
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


# ============================================================
#  扫描 chip 音乐
# ============================================================
func _scan_chip_music():
	_chip_slot_map.clear()

	# 1. 自动扫描目录
	var dirs : Array = []
	if config and not config.chip_music_dirs.is_empty():
		dirs = config.chip_music_dirs
	else:
		dirs = ["res://content/music/", "res://content/sound/"]

	for dir_path in dirs:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".json"):
				var slot_name := fname.substr(0, fname.length() - 5)
				if not _chip_slot_map.has(slot_name):
					_chip_slot_map[slot_name] = dir_path + fname
			fname = dir.get_next()
		dir.list_dir_end()

	# 2. 手动覆盖（优先级更高）
	if config and not config.chip_replacements.is_empty():
		for slot in config.chip_replacements:
			var p : String = config.chip_replacements[slot]
			if p != "":
				_chip_slot_map[slot] = p

	print("[MusicManager] 扫描到 %d 个 chip 音乐:" % _chip_slot_map.size())
	for k in _chip_slot_map:
		print("  %s → %s" % [k, _chip_slot_map[k]])


## 供外部调用：重新扫描（新增 JSON 后不用重启）
func rescan_chip_music():
	_scan_chip_music()


# ============================================================
#  统一播放入口
# ============================================================
func _play_slot(slot_name: String, fallback_stream: AudioStream):
	# 1. 优先 chip
	if _chip_slot_map.has(slot_name):
		var json_path: String = _chip_slot_map[slot_name]
		if _play_chip(json_path):
			_chip_current_path = json_path
			_chip_current_slot = slot_name
			return
	# 2. 回退普通
	if fallback_stream != null:
		if _chip_player and _chip_player.is_playing():
			_chip_player.stop()
		_chip_current_path = ""
		_chip_current_slot = ""
		play_music(fallback_stream)
	else:
		stop_music()


func _play_chip(json_path: String) -> bool:
	var song: ChipSong = _chip_song_cache.get(json_path)
	if song == null:
		song = ChipSong.from_json(json_path)
		if song == null:
			push_warning("[MusicManager] chip JSON 解析失败: " + json_path)
			return false
		_chip_song_cache[json_path] = song

	# 停普通播放器
	if player and player.playing:
		player.stop()

	_chip_player.play_song(song)
	_chip_player.set_volume(Globals.music_volume)
	return true


# ============================================================
#  普通音乐 API（向后兼容）
# ============================================================
func play_music(stream: AudioStream):
	if config == null:
		push_error("音乐配置未加载，无法播放")
		return
	if stream == null:
		push_error("尝试播放空音乐流")
		return

	# ★ 停 chip
	if _chip_player and _chip_player.is_playing():
		_chip_player.stop()
	_chip_current_path = ""
	_chip_current_slot = ""

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
	if _chip_player and _chip_player.is_playing():
		_chip_player.stop()
	_chip_current_path = ""
	_chip_current_slot = ""
	if player and player.playing:
		player.stop()
		print("音乐已停止")


func set_music_volume(value: float):
	Globals.music_volume = value
	var db = linear_to_db(value) if value > 0 else -80.0
	if player:
		player.volume_db = db
	if _chip_player:
		_chip_player.set_volume(value)


func get_music_volume() -> float:
	return db_to_linear(player.volume_db)


func set_master_volume_db(volume: float):
	if player:
		player.volume_db = volume


# ============================================================
#  场景音乐（全部走 _play_slot）
# ============================================================
func play_main_menu_music():
	if config: _play_slot("main_menu", config.main_menu_music)

func play_player_turn_music():
	if config: _play_slot("player_turn", config.player_turn_music)

func play_enemy_turn_music():
	if config: _play_slot("enemy_turn", config.enemy_turn_music)

func play_victory_music():
	if config: _play_slot("victory", config.victory_music)

func play_defeat_music():
	if config: _play_slot("defeat", config.defeat_music)

func play_win_game_music():
	if config: _play_slot("win_game", config.win_game_music)


# ============================================================
#  营地 / 子界面音乐
# ============================================================
func play_soul_altar_music():
	if config: _play_slot("soul_altar", config.soul_altar_music)

func play_anvil_tavern_music():
	if config: _play_slot("anvil_tavern", config.anvil_tavern_music)

func play_arena_music():
	if config: _play_slot("arena", config.arena_music)

func play_arena_battle_music():
	if config: _play_slot("arena_battle", config.arena_battle_music)

func play_hero_shrine_music():
	if config: _play_slot("hero_shrine", config.hero_shrine_music)

func play_hero_shrine_convert_music():
	if config: _play_slot("hero_shrine_convert", config.hero_shrine_convert_music)


# ============================================================
#  对话音乐
# ============================================================
func play_dialogue_music():
	# dialogue 走特殊流程（会 pause 原曲），不查 chip
	if config and config.dialogue_music:
		if _chip_player and _chip_player.is_playing():
			_chip_player.stop()
		player.stop()
		player.stream = config.dialogue_music
		player.play()
		print("播放对话音乐")
	else:
		push_warning("未设置对话音乐，跳过播放")


# ============================================================
#  暂停 / 恢复（对话、过场）
# ============================================================
func pause_and_save() -> bool:
	# ★ chip 优先
	if _chip_player and _chip_player.is_playing():
		_saved_chip_path = _chip_current_path
		_saved_chip_slot = _chip_current_slot
		_chip_player.stop()
		print("已保存 chip 音乐: %s（slot=%s）" % [_saved_chip_path, _saved_chip_slot])
		return true
	if player and player.playing:
		_saved_stream = player.stream
		_saved_position = player.get_playback_position()
		player.stop()
		print("已保存音乐: ", _saved_stream, " 位置: ", _saved_position)
		return true
	return false


func resume_saved():
	# ★ 优先恢复 chip
	if _saved_chip_path != "":
		if _play_chip(_saved_chip_path):
			_chip_current_path = _saved_chip_path
			_chip_current_slot = _saved_chip_slot
			print("恢复 chip 音乐: %s（slot=%s）" % [_saved_chip_path, _saved_chip_slot])
			_saved_chip_path = ""
			_saved_chip_slot = ""
			return
		# 失败 → 清空后走普通音乐
		_saved_chip_path = ""
		_saved_chip_slot = ""

	if _saved_stream:
		if _chip_player and _chip_player.is_playing():
			_chip_player.stop()
		player.stop()
		player.stream = _saved_stream
		player.seek(_saved_position)
		player.play()
		print("恢复音乐: ", _saved_stream, " 位置: ", _saved_position)
		_saved_stream = null
		_saved_position = 0.0
	else:
		print("没有保存的音乐可恢复")


# ============================================================
#  调试 / 查询
# ============================================================
## 返回当前已扫描的 chip slot 列表
func get_chip_slots() -> Array:
	return _chip_slot_map.keys()


## 查询某 slot 是否有 chip 版本
func has_chip_for_slot(slot_name: String) -> bool:
	return _chip_slot_map.has(slot_name)


## 手动播放 chip JSON（测试用）
func play_chip_path(json_path: String) -> bool:
	return _play_chip(json_path)
