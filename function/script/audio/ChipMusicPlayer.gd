class_name ChipMusicPlayer
extends Node

# ============================================================
#  ChipMusicPlayer — 把 ChipSong 通过 AudioStreamGenerator 播放
#  优化点（v2）：
#    - MIX_RATE 44100 → 22050（8bit 音质无损，CPU 减半）
#    - BUFFER_LENGTH 0.3 → 0.15
#    - CHUNK_MAX 2048 → 512
#    - 每帧生成上限 MAX_FRAMES_PER_PROCESS，避免一次性大块阻塞
# ============================================================

const MIX_RATE: int = 20000
const BUFFER_LENGTH: float = 0.15
const CHUNK_MAX: int = 512
## ★ 单次 _process 最多生成的帧数（防止 buffer 空时一次性补满 → 卡帧）
const MAX_FRAMES_PER_PROCESS: int = 1024

var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _sequencer: ChipSequencer = null
var _is_chip_playing: bool = false

# ★ 通道静音状态
var _muted: Array[bool] = [false, false, false, false]


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

	_sequencer = ChipSequencer.new()
	_sequencer.load_song(song, MIX_RATE)

	# ★ 应用当前静音状态到新的 synth
	_apply_mute_to_synth()

	_sequencer.start()

	_player.stream = _generator
	_player.play()
	_playback = _player.get_stream_playback()
	_is_chip_playing = true

	# ★ 启动预填：一次性填满，避免开头静音（启动卡顿可接受）
	_fill_buffer_initial()


func stop():
	_is_chip_playing = false
	if _sequencer:
		_sequencer.stop()
	if _player and _player.playing:
		_player.stop()
	_sequencer = null
	_playback = null


func is_playing() -> bool:
	return _is_chip_playing


func set_volume(linear: float):
	if _player:
		if linear > 0.0001:
			_player.volume_db = linear_to_db(linear)
		else:
			_player.volume_db = -80.0


# ============================================================
#  静音 API（无缝）
# ============================================================
## 设置通道静音（播放中即时生效，无断点）
func set_channel_muted(channel: int, muted: bool):
	if channel < 0: return
	while _muted.size() <= channel:
		_muted.append(false)
	if _muted[channel] == muted:
		return
	_muted[channel] = muted

	# 直接改 synth 的通道增益，播放中无缝生效
	if _sequencer and _sequencer.synth:
		_sequencer.synth.set_channel_muted(channel, muted)


func is_channel_muted(channel: int) -> bool:
	if channel < 0 or channel >= _muted.size():
		return false
	return _muted[channel]


## 一次性设置所有通道静音
func set_all_muted(mask : Array):
	for i in range(mask.size()):
		set_channel_muted(i, bool(mask[i]))


## 内部：把 _muted 状态同步到当前 synth
func _apply_mute_to_synth():
	if _sequencer == null or _sequencer.synth == null:
		return
	for i in range(_muted.size()):
		_sequencer.synth.set_channel_muted(i, _muted[i])


func _process(_delta):
	if not _is_chip_playing or _playback == null or _sequencer == null:
		return
	_fill_buffer()


# ============================================================
#  缓冲填充
# ============================================================
## 常规填充：每帧限流，避免卡顿
func _fill_buffer():
	if _playback == null or _sequencer == null:
		return
	var avail: int = _playback.get_frames_available()
	if avail <= 0:
		return

	# ★ 每帧最多生成 MAX_FRAMES_PER_PROCESS 帧
	var budget: int = mini(avail, MAX_FRAMES_PER_PROCESS)
	while budget > 0:
		var chunk: int = mini(budget, CHUNK_MAX)
		var frames: PackedVector2Array = _sequencer.generate_frames(chunk)
		_playback.push_buffer(frames)
		budget -= chunk


## 启动预填：一次性填满（只在 play_song 时调用一次）
func _fill_buffer_initial():
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
