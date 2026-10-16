class_name ChipMusicPlayer
extends Node

# ============================================================
#  ChipMusicPlayer — 把 ChipSong 通过 AudioStreamGenerator 播放
#  v3 更新（P0-P3）：
#    - MIX_RATE 统一为 22050（8bit 音质无损，CPU 减半）
#    - 修复 play_song_from_tick 会先播放头部 buffer 的 bug：
#      统一走 _prepare(song, start_tick)，先 start 再 seek
#    - _fill_buffer_initial 加安全上限，避免异常情况下死循环
# ============================================================

const MIX_RATE: int = 22050
const BUFFER_LENGTH: float = 0.15
const CHUNK_MAX: int = 512
## 单次 _process 最多生成的帧数（防止 buffer 空时一次性补满 → 卡帧）
const MAX_FRAMES_PER_PROCESS: int = 1024
## 启动预填最大循环次数（仅作保护，正常 1~2 次即可填满）
const INITIAL_FILL_MAX_ITER: int = 256

var _player: AudioStreamPlayer = null
var _generator: AudioStreamGenerator = null
var _playback: AudioStreamGeneratorPlayback = null
var _sequencer: ChipSequencer = null
var _is_chip_playing: bool = false

# 通道静音状态
var _muted: Array[bool] = [false, false, false, false]


func _ready():
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	add_child(_player)

	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = MIX_RATE
	_generator.buffer_length = BUFFER_LENGTH


func play_song(song: ChipSong):
	_prepare(song, 0)


func play_song_from_tick(song: ChipSong, start_tick: int):
	_prepare(song, maxi(start_tick, 0))


## ★ 统一的启动路径。先 start 再 seek，避免 buffer 里残留开头音频。
func _prepare(song: ChipSong, start_tick: int):
	stop()
	if song == null:
		return

	_sequencer = ChipSequencer.new()
	_sequencer.load_song(song, MIX_RATE)

	# 应用当前静音状态到新的 synth
	_apply_mute_to_synth()

	# 先 start（重置 note-off 队列和 voice），再 seek（覆盖 cursor / event_idx）
	_sequencer.start()
	if start_tick > 0:
		_sequencer.seek_to_tick(start_tick)

	_player.stream = _generator
	_player.play()
	_playback = _player.get_stream_playback()
	_is_chip_playing = true

	# 启动预填：一次性填满，避免开头静音（启动卡顿可接受）
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
## 设置通道静音（播放中平滑过渡生效，无咔哒）
func set_channel_muted(channel: int, muted: bool):
	if channel < 0: return
	while _muted.size() <= channel:
		_muted.append(false)
	if _muted[channel] == muted:
		return
	_muted[channel] = muted

	# 直接改 synth 的通道目标增益，播放中平滑过渡
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

	# 每帧最多生成 MAX_FRAMES_PER_PROCESS 帧
	var budget: int = mini(avail, MAX_FRAMES_PER_PROCESS)
	while budget > 0:
		var chunk: int = mini(budget, CHUNK_MAX)
		var frames: PackedVector2Array = _sequencer.generate_frames(chunk)
		_playback.push_buffer(frames)
		budget -= chunk


## 启动预填：一次性填满（只在 _prepare 里调用一次）
func _fill_buffer_initial():
	if _playback == null or _sequencer == null:
		return
	var safety := 0
	while safety < INITIAL_FILL_MAX_ITER:
		var avail: int = _playback.get_frames_available()
		if avail <= 0:
			break
		var chunk: int = mini(avail, CHUNK_MAX)
		var frames: PackedVector2Array = _sequencer.generate_frames(chunk)
		_playback.push_buffer(frames)
		safety += 1


## 跳到指定 tick（播放中有效）
func seek_to_tick(tick: int):
	if _sequencer:
		_sequencer.seek_to_tick(tick)
	# ★ 第十二批：清空残留 audio buffer，再预填新位置的内容
	# 否则会听到 seek 前的那段尾巴（约 BUFFER_LENGTH 秒）
	if _playback and _is_chip_playing:
		_playback.clear_buffer()
		_fill_buffer_initial()


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
