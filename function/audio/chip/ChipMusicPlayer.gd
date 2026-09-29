class_name ChipMusicPlayer
extends Node

# ============================================================
#  ChipMusicPlayer — 把 ChipSong 通过 AudioStreamGenerator 播放
# ============================================================

const MIX_RATE: int = 44100
const BUFFER_LENGTH: float = 0.3
const CHUNK_MAX: int = 2048

var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _sequencer: ChipSequencer = null
var _is_chip_playing: bool = false

# ★ 通道静音状态（0~3）
var _muted: Array[bool] = [false, false, false, false]
# ★ 记录当前正在播放的原始 song（用于静音切换时重建）
var _current_song: ChipSong = null
# ★ 记录当前播放头 tick（重建 sequencer 时保持一致）
var _current_tick_hint: int = 0


func _ready():
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	add_child(_player)

	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = MIX_RATE
	_generator.buffer_length = BUFFER_LENGTH


func play_song(song: ChipSong):
	stop()
	if song == null:
		return

	_current_song = song
	var filtered : ChipSong = _build_filtered_song(song)

	_sequencer = ChipSequencer.new()
	_sequencer.load_song(filtered, MIX_RATE)
	_sequencer.start()

	_player.stream = _generator
	_player.play()
	_playback = _player.get_stream_playback()
	_is_chip_playing = true
	_current_tick_hint = 0

	# 预填缓冲区
	_fill_buffer()


func stop():
	_is_chip_playing = false
	if _sequencer:
		_sequencer.stop()
	if _player and _player.playing:
		_player.stop()
	_sequencer = null
	_playback = null
	# 注意：不清 _current_song，方便静音切换时重建


func is_playing() -> bool:
	return _is_chip_playing


func set_volume(linear: float):
	if _player:
		if linear > 0.0001:
			_player.volume_db = linear_to_db(linear)
		else:
			_player.volume_db = -80.0


# ============================================================
#  静音 API
# ============================================================
## 设置通道静音（播放中即时生效）
func set_channel_muted(channel: int, muted: bool):
	if channel < 0 or channel >= _muted.size():
		return
	if _muted[channel] == muted:
		return
	_muted[channel] = muted

	# 如果正在播放 → 保留 tick 重建 sequencer（用过滤后的 song）
	if _is_chip_playing and _current_song != null:
		var cur : int = get_current_tick()
		_current_tick_hint = cur
		var filtered : ChipSong = _build_filtered_song(_current_song)

		_sequencer = ChipSequencer.new()
		_sequencer.load_song(filtered, MIX_RATE)
		_sequencer.start()
		_sequencer.seek_to_tick(cur)

		# 重启音频流（清空旧缓冲）
		if _player.playing:
			_player.stop()
		_player.play()
		_playback = _player.get_stream_playback()
		_fill_buffer()


func is_channel_muted(channel: int) -> bool:
	if channel < 0 or channel >= _muted.size():
		return false
	return _muted[channel]


func set_all_muted(mask : Array) -> void:
	for i in range(_muted.size()):
		_muted[i] = (i < mask.size() and bool(mask[i]))
	if _is_chip_playing and _current_song != null:
		var cur : int = get_current_tick()
		var filtered : ChipSong = _build_filtered_song(_current_song)
		_sequencer = ChipSequencer.new()
		_sequencer.load_song(filtered, MIX_RATE)
		_sequencer.start()
		_sequencer.seek_to_tick(cur)
		if _player.playing:
			_player.stop()
		_player.play()
		_playback = _player.get_stream_playback()
		_fill_buffer()


# ============================================================
#  内部：过滤静音通道
# ============================================================
func _build_filtered_song(song: ChipSong) -> ChipSong:
	# 没有任何通道静音 → 直接用原 song
	var any_muted : bool = false
	for m in _muted:
		if m: any_muted = true; break
	if not any_muted:
		return song

	var ps := ChipSong.new()
	ps.title = song.title
	ps.bpm = song.bpm
	ps.beats_per_bar = song.beats_per_bar
	ps.ticks_per_beat = song.ticks_per_beat
	ps.total_ticks = song.total_ticks
	ps.loop_start = song.loop_start
	ps.loop_end = song.loop_end
	ps.events = []

	for e in song.events:
		var ev : Dictionary = e
		var ch : int = int(ev.ch)
		if ch >= 0 and ch < _muted.size() and _muted[ch]:
			continue
		ps.events.append(ev.duplicate())

	return ps


func _process(_delta):
	if not _is_chip_playing or _playback == null or _sequencer == null:
		return
	_fill_buffer()


func _fill_buffer():
	if _playback == null or _sequencer == null:
		return
	var avail: int = _playback.get_frames_available()
	while avail > 0:
		var chunk: int = mini(avail, CHUNK_MAX)
		var frames: PackedVector2Array = _sequencer.generate_frames(chunk)
		_playback.push_buffer(frames)
		avail -= chunk


## 从指定 tick 开始播放
func play_song_from_tick(song: ChipSong, start_tick: int):
	play_song(song)
	if _sequencer:
		_sequencer.seek_to_tick(start_tick)


## 跳到指定 tick（播放中有效）
func seek_to_tick(tick: int):
	if _sequencer:
		_sequencer.seek_to_tick(tick)


## 获取当前 tick
func get_current_tick() -> int:
	if _sequencer:
		return _sequencer.get_current_tick()
	return 0


## 获取总 tick
func get_total_ticks() -> int:
	if _sequencer and _sequencer.song:
		return _sequencer.song.total_ticks
	return 0
