class_name ChipSequencer
extends RefCounted

# ============================================================
#  ChipSequencer — 把 ChipSong 的事件表转成合成器调用
#  优化点（v2）：
#    - generate_frames 循环内避免 Dictionary 重复查找
#    - 缓存 _samples_per_tick 的倒数
#    - note_off 队列用两个并行数组代替 Dictionary
# ============================================================

var mix_rate: float = 22050.0
var song: ChipSong = null
var synth: ChipSynth = null

var _started: bool = false
var _sample_cursor: int = 0
var _next_event_idx: int = 0
var _samples_per_tick: float = 0.0
var _inv_samples_per_tick: float = 0.0

# ★ note-off 队列（用两个并行数组，避免 Dictionary 开销）
var _noteoff_voice: PackedInt32Array = PackedInt32Array()
var _noteoff_sample: PackedInt32Array = PackedInt32Array()
var _noteoff_head: int = 0


func load_song(s: ChipSong, rate: float = 22050.0):
	song = s
	mix_rate = rate
	# Voice pool 大小 = 通道数 × 3（够处理和弦），最少 8
	var pool_size: int = maxi(8, s.get_channel_count() * 3)
	synth = ChipSynth.new(pool_size, rate)
	var safe_bpm : float = maxf(s.bpm, 1.0)
	var safe_tpb : int = maxi(s.ticks_per_beat, 1)
	_samples_per_tick = (60.0 / safe_bpm) / float(safe_tpb) * mix_rate
	_inv_samples_per_tick = 1.0 / maxf(_samples_per_tick, 0.0001)


func start():
	_started = true
	_sample_cursor = 0
	_next_event_idx = 0
	_noteoff_voice = PackedInt32Array()
	_noteoff_sample = PackedInt32Array()
	_noteoff_head = 0
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

	# ★ 局部变量缓存（避免每帧都走 property lookup）
	var events: Array = song.events
	var events_size: int = events.size()
	var noteoff_v: PackedInt32Array = _noteoff_voice
	var noteoff_s: PackedInt32Array = _noteoff_sample
	var head: int = _noteoff_head
	var cursor: int = _sample_cursor
	var next_idx: int = _next_event_idx
	var sp_tick: float = _samples_per_tick

	for i in range(count):
		# ---- 1. 到期 note-off ----
		while head < noteoff_s.size():
			if noteoff_s[head] <= cursor:
				synth.note_off(noteoff_v[head])
				head += 1
			else:
				break

		# ---- 2. 到期 note-on ----
		while next_idx < events_size:
			var ev: Dictionary = events[next_idx]
			var ev_sample: float = float(ev.tick) * sp_tick
			if ev_sample > float(cursor):
				break

			var ch: int = int(ev.ch)
			var vel: float = float(ev.vel) / 127.0
			var ch_vol: float = song.get_channel_volume(ch)
			var pan: float = song.get_channel_pan(ch)

			var voice_idx: int = synth.note_on(ch, int(ev.note), vel * ch_vol,
												int(ev.wave), ev.env, pan)

			var note_off_sample: int = int(ev_sample + float(ev.dur) * sp_tick)
			noteoff_v.append(voice_idx)
			noteoff_s.append(note_off_sample)
			next_idx += 1

		out[i] = synth.get_sample()
		cursor += 1

		# ---- 3. 循环 ----
		if song.loop_end > 0:
			var loop_end_sample: int = int(float(song.loop_end) * sp_tick)
			if cursor >= loop_end_sample:
				var loop_start_tick: int = song.loop_start if song.loop_start >= 0 else 0
				cursor = int(float(loop_start_tick) * sp_tick)
				# 重置事件游标
				next_idx = 0
				for k in range(events_size):
					if int(events[k].tick) >= loop_start_tick:
						next_idx = k
						break
				# 清空 note-off 队列
				noteoff_v = PackedInt32Array()
				noteoff_s = PackedInt32Array()
				head = 0
				synth.all_notes_off()

	# ★ 回写状态
	_sample_cursor = cursor
	_next_event_idx = next_idx
	_noteoff_voice = noteoff_v
	_noteoff_sample = noteoff_s
	_noteoff_head = head

	return out


func seek_to_tick(target_tick: int):
	if song == null or synth == null:
		return
	_sample_cursor = int(float(target_tick) * _samples_per_tick)
	_next_event_idx = 0
	var events: Array = song.events
	for i in range(events.size()):
		if int(events[i].tick) >= target_tick:
			_next_event_idx = i
			break
	_noteoff_voice = PackedInt32Array()
	_noteoff_sample = PackedInt32Array()
	_noteoff_head = 0
	synth.clear_all_voices()


func get_current_tick() -> int:
	if _samples_per_tick <= 0:
		return 0
	return int(float(_sample_cursor) / _samples_per_tick)
