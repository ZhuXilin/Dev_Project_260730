class_name ChipSequencer
extends RefCounted

# ============================================================
#  ChipSequencer — 把 ChipSong 的事件表转成合成器调用
# ============================================================

var mix_rate: float = 44100.0
var song: ChipSong = null
var synth: ChipSynth = null

var _started: bool = false
var _sample_cursor: int = 0
var _next_event_idx: int = 0
var _samples_per_tick: float = 0.0
var _note_off_queue: Array = []   # [{ voice, sample_time }]


func load_song(s: ChipSong, rate: float = 44100.0):
	song = s
	mix_rate = rate
	# Voice pool 大小 = 通道数 × 3（够处理和弦），最少 8
	var pool_size: int = maxi(8, s.get_channel_count() * 3)
	synth = ChipSynth.new(pool_size, rate)
	_samples_per_tick = (60.0 / s.bpm) / float(s.ticks_per_beat) * mix_rate


func start():
	_started = true
	_sample_cursor = 0
	_next_event_idx = 0
	_note_off_queue.clear()
	if synth:
		synth.clear_all_voices()


func stop():
	_started = false
	if synth:
		synth.all_notes_off()


func is_playing() -> bool:
	return _started


## 生成 count 帧立体声
func generate_frames(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(count)
	if not _started or song == null or synth == null:
		# 全零（静音）
		return out
	for i in range(count):
		_process_one_sample()
		out[i] = synth.get_sample()
	return out


func _process_one_sample():
	# 1. 到期的 note-off
	while not _note_off_queue.is_empty():
		var ev: Dictionary = _note_off_queue[0]
		if ev["sample_time"] <= _sample_cursor:
			synth.note_off(ev["voice"])
			_note_off_queue.pop_front()
		else:
			break

	# 2. 到期的 note-on
	while _next_event_idx < song.events.size():
		var ev: Dictionary = song.events[_next_event_idx]
		var ev_sample: float = ev["tick"] * _samples_per_tick
		if ev_sample > float(_sample_cursor):
			break

		var ch: int = ev["ch"]
		var vel: float = float(ev["vel"]) / 127.0
		var ch_vol: float = song.get_channel_volume(ch)
		var pan: float = song.get_channel_pan(ch)

		# ★ wave / env 兜底：旧文件或手动添加的事件可能缺这两个字段
		var wave: int = int(ev.get("wave", ChipSynth.Wave.PULSE_50))
		var env: Dictionary = ev.get("env", {
			"attack": 0.01,
			"decay": 0.05,
			"sustain": 0.7,
			"release": 0.05,
		})

		var voice_idx: int = synth.note_on(ch, ev["note"], vel * ch_vol,
											wave, env, pan)

		var note_off_sample: float = ev_sample + ev["dur"] * _samples_per_tick
		_note_off_queue.append({
			"voice": voice_idx,
			"sample_time": note_off_sample,
		})
		_next_event_idx += 1

	_sample_cursor += 1

	# 3. 循环
	if song.loop_end > 0:
		var loop_end_sample: int = int(song.loop_end * _samples_per_tick)
		if _sample_cursor >= loop_end_sample:
			var loop_start_tick: int = song.loop_start if song.loop_start >= 0 else 0
			_sample_cursor = int(loop_start_tick * _samples_per_tick)
			# 重置事件游标到 loop_start 对应位置
			_next_event_idx = 0
			for i in range(song.events.size()):
				if song.events[i]["tick"] >= loop_start_tick:
					_next_event_idx = i
					break
			# 清空 note-off 队列（避免残留影响下一轮）
			_note_off_queue.clear()
			synth.all_notes_off()


func seek_to_tick(target_tick: int):
	if song == null or synth == null:
		return
	_sample_cursor = int(target_tick * _samples_per_tick)
	_next_event_idx = 0
	for i in range(song.events.size()):
		if song.events[i]["tick"] >= target_tick:
			_next_event_idx = i
			break
	_note_off_queue.clear()
	synth.clear_all_voices()


func get_current_tick() -> int:
	if _samples_per_tick <= 0:
		return 0
	return int(_sample_cursor / _samples_per_tick)


## 重新扫描事件游标（歌曲被编辑后调用，不重置音频位置）
func rescan_events():
	if song == null: return
	var cur_tick : int = get_current_tick()
	_next_event_idx = 0
	var found : bool = false
	for i in range(song.events.size()):
		if song.events[i]["tick"] >= cur_tick:
			_next_event_idx = i
			found = true
			break
	if not found:
		_next_event_idx = song.events.size()
