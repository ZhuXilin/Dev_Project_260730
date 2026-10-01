extends Node

# ============================================================
#  SoundManager — 音效播放（普通 AudioStream + chip JSON 混合）
#  - 支持多音效同时播放（chip 池化）
# ============================================================

const CONFIG_PATH : String = Config.PATHS.SOUND_CONFIG
const CHIP_SFX_DIR : String = "res://content/sound/"
const CHIP_POOL_SIZE : int = 8   # 同时最多 8 个 chip 音效

var config : SoundConfig
var player : AudioStreamPlayer
var looping_player : AudioStreamPlayer

# ---- chip 音效 ----
var _chip_players: Array[ChipMusicPlayer] = []
var _chip_song_cache: Dictionary = {}    # path -> ChipSong
var _chip_slot_map: Dictionary = {}      # slot_name -> json_path


func _ready():
	_load_config()
	_setup_players()
	_setup_chip_pool()
	_sync_volume_from_global()
	_scan_chip_sfx()


# ============================================================
#  普通配置
# ============================================================
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


func _setup_chip_pool():
	_chip_players.clear()
	for i in range(CHIP_POOL_SIZE):
		var p := ChipMusicPlayer.new()
		add_child(p)
		_chip_players.append(p)


func _sync_volume_from_global():
	if player and looping_player:
		var vol = Globals.sound_volume
		var db = linear_to_db(vol) if vol > 0 else -80.0
		player.volume_db = db
		looping_player.volume_db = db
		_sync_chip_volume()
		print("音效音量已同步为: ", vol, " (", db, " dB)")


func _sync_chip_volume():
	for p in _chip_players:
		p.set_volume(Globals.sound_volume)


# ============================================================
#  Chip 音效扫描
# ============================================================
func _scan_chip_sfx():
	_chip_slot_map.clear()
	if not DirAccess.dir_exists_absolute(CHIP_SFX_DIR):
		return
	var dir := DirAccess.open(CHIP_SFX_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var slot := fname.substr(0, fname.length() - 5)
			_chip_slot_map[slot] = CHIP_SFX_DIR + fname
		fname = dir.get_next()
	dir.list_dir_end()

	print("[SoundManager] 扫描到 %d 个 chip 音效:" % _chip_slot_map.size())
	for k in _chip_slot_map:
		print("  %s → %s" % [k, _chip_slot_map[k]])


func rescan_chip_sfx():
	_scan_chip_sfx()


# ============================================================
#  音量
# ============================================================
func set_sound_volume(value: float):
	Globals.sound_volume = value
	var db = linear_to_db(value) if value > 0 else -80.0
	if player:
		player.volume_db = db
	if looping_player:
		looping_player.volume_db = db
	_sync_chip_volume()


func get_sound_volume() -> float:
	if player:
		return db_to_linear(player.volume_db)
	return Globals.sound_volume


# ============================================================
#  统一播放入口
# ============================================================
## 优先 chip JSON，回退普通 AudioStream
func _play_sfx(slot_name: String, fallback_stream: AudioStream):
	if _chip_slot_map.has(slot_name):
		if _play_chip(slot_name):
			return
	if fallback_stream != null:
		play_sound(fallback_stream)


## 播放一个 chip 音效（多实例池化）
func _play_chip(slot_name: String) -> bool:
	var path: String = _chip_slot_map.get(slot_name, "")
	if path == "":
		return false

	var song: ChipSong = _chip_song_cache.get(path)
	if song == null:
		song = ChipSong.from_json(path)
		if song == null:
			push_warning("[SoundManager] chip JSON 解析失败: " + path)
			return false
		_chip_song_cache[path] = song

	# 找一个空闲的 player
	var p := _alloc_chip_player()
	if p == null:
		return false

	p.play_song(song)
	p.set_volume(Globals.sound_volume)
	return true


func _alloc_chip_player() -> ChipMusicPlayer:
	# 1. 找未播放的
	for p in _chip_players:
		if not p.is_playing():
			return p
	# 2. 都忙 → 偷第一个
	if _chip_players.size() > 0:
		_chip_players[0].stop()
		return _chip_players[0]
	return null


# ============================================================
#  普通音效 API（向后兼容）
# ============================================================
func play_sound(stream: AudioStream):
	if config == null or stream == null:
		return
	player.stop()
	player.stream = stream
	player.play()


func play_move_sound(_unit: Unit = null):
	# move 音效是循环的
	if _chip_slot_map.has("move_sound"):
		# chip 暂不支持循环播放音效（一个 player 一直在跑）
		# 简单处理：当成普通音效播一次
		if _play_chip("move_sound"):
			return
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


# ============================================================
#  具体音效（全部走 _play_sfx）
# ============================================================
func play_select_sound():
	if config: _play_sfx("select_unit", config.select_unit)

func play_attack_sound():
	if config: _play_sfx("attack", config.attack)

func play_hit_sound():
	if config: _play_sfx("hit", config.hit)

func play_miss_sound():
	if config: _play_sfx("miss", config.miss)

func play_heal_sound():
	if config: _play_sfx("heal", config.heal)

func play_death_sound():
	if config: _play_sfx("death", config.death)

func play_cancel_sound():
	if config: _play_sfx("cancel", config.cancel)

func play_invalid_sound():
	if config: _play_sfx("invalid_click", config.invalid_click)

func play_wait_sound():
	if config: _play_sfx("wait", config.wait)

func play_get_item_sound():
	if config: _play_sfx("get_item", config.get_item)

# ============================================================
#  调试 / 查询
# ============================================================
func get_chip_slots() -> Array:
	return _chip_slot_map.keys()


func has_chip_for_slot(slot_name: String) -> bool:
	return _chip_slot_map.has(slot_name)
