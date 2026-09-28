class_name ChipSynth
extends RefCounted

# ============================================================
#  ChipSynth — 8-bit 波形合成器（复音）
# ============================================================

enum Wave { PULSE_12, PULSE_25, PULSE_50, PULSE_75, TRIANGLE, NOISE, SAW }


class Voice:
	var active: bool = false
	var wave: int = Wave.PULSE_50
	var phase: float = 0.0
	var phase_inc: float = 0.0
	var frequency: float = 440.0
	var velocity: float = 1.0
	var pan: float = 0.0

	# ADSR（秒）
	var attack: float = 0.01
	var decay: float = 0.05
	var sustain: float = 0.7
	var release: float = 0.05

	# 状态
	var env_stage: int = 0   # 0=att 1=dec 2=sus 3=rel 4=off
	var env_time: float = 0.0
	var env_value: float = 0.0

	# noise LFSR
	var lfsr: int = 0x7FFF

	# 追踪
	var start_sample: int = 0
	var ch_owner: int = -1


# ============================================================
#  合成器
# ============================================================
var mix_rate: float = 44100.0
var master_volume: float = 0.3
var voices: Array[Voice] = []
var _sample_cursor: int = 0


func _init(pool_size: int = 12, rate: float = 44100.0):
	mix_rate = rate
	for i in range(pool_size):
		voices.append(Voice.new())


# ============================================================
#  播放控制
# ============================================================
## 分配一个 voice 播放指定 note
## 优先找空闲 voice；全忙则偷"最早启动"的
## 返回 voice 索引（-1 = 失败）
func note_on(ch: int, midi_note: int, velocity: float,
			 wave: int, env: Dictionary, pan: float = 0.0) -> int:
	var idx := _alloc_voice()
	if idx < 0:
		return -1
	var v := voices[idx]
	v.active = true
	v.ch_owner = ch
	v.wave = wave
	v.velocity = velocity
	v.pan = pan
	v.frequency = 440.0 * pow(2.0, (midi_note - 69) / 12.0)
	v.phase_inc = v.frequency / mix_rate
	v.phase = 0.0
	v.lfsr = 0x7FFF
	v.attack  = float(env.get("attack", 0.01))
	v.decay   = float(env.get("decay", 0.05))
	v.sustain = float(env.get("sustain", 0.7))
	v.release = float(env.get("release", 0.05))
	v.env_stage = 0
	v.env_time = 0.0
	v.env_value = 0.0
	v.start_sample = _sample_cursor
	return idx


func note_off(voice_idx: int):
	if voice_idx < 0 or voice_idx >= voices.size():
		return
	var v := voices[voice_idx]
	if v.env_stage != 3 and v.env_stage != 4:
		v.env_stage = 3
		v.env_time = 0.0


func all_notes_off():
	for v in voices:
		if v.active and v.env_stage != 4:
			v.env_stage = 3
			v.env_time = 0.0


func clear_all_voices():
	for v in voices:
		v.active = false
		v.env_stage = 4
		v.env_value = 0.0


# ============================================================
#  采样生成
# ============================================================
func get_sample() -> Vector2:
	var sum_l := 0.0
	var sum_r := 0.0
	for v in voices:
		if not v.active:
			continue
		var s := _sample_voice(v)
		# pan: -1 = 全左, 0 = 中, +1 = 全右
		var l_gain := sqrt(0.5 * (1.0 - v.pan))
		var r_gain := sqrt(0.5 * (1.0 + v.pan))
		sum_l += s * l_gain
		sum_r += s * r_gain

	sum_l *= master_volume
	sum_r *= master_volume
	_sample_cursor += 1
	return Vector2(clampf(sum_l, -1.0, 1.0), clampf(sum_r, -1.0, 1.0))


func _sample_voice(v: Voice) -> float:
	# ---- 波形 ----
	var s := 0.0
	match v.wave:
		Wave.PULSE_12: s = 1.0 if v.phase < 0.125 else -1.0
		Wave.PULSE_25: s = 1.0 if v.phase < 0.25  else -1.0
		Wave.PULSE_50: s = 1.0 if v.phase < 0.5   else -1.0
		Wave.PULSE_75: s = 1.0 if v.phase < 0.75  else -1.0
		Wave.TRIANGLE: s = 4.0 * abs(v.phase - 0.5) - 1.0
		Wave.SAW:      s = 2.0 * v.phase - 1.0
		Wave.NOISE:
			var bit: int = ((v.lfsr >> 0) ^ (v.lfsr >> 1)) & 1
			v.lfsr = (v.lfsr >> 1) | (bit << 14)
			s = 1.0 if (v.lfsr & 1) == 1 else -1.0

	# ---- 相位推进 ----
	v.phase += v.phase_inc
	if v.phase >= 1.0:
		v.phase -= 1.0

	# ---- ADSR ----
	v.env_time += 1.0 / mix_rate
	match v.env_stage:
		0:  # attack
			if v.env_time >= v.attack:
				v.env_stage = 1
				v.env_time = 0.0
				v.env_value = 1.0
			else:
				v.env_value = v.env_time / maxf(v.attack, 0.0001)
		1:  # decay
			if v.env_time >= v.decay:
				v.env_stage = 2
				v.env_value = v.sustain
			else:
				var t: float = v.env_time / maxf(v.decay, 0.0001)
				v.env_value = lerpf(1.0, v.sustain, t)
		2:  # sustain
			v.env_value = v.sustain
		3:  # release
			if v.env_time >= v.release:
				v.active = false
				v.env_stage = 4
				v.env_value = 0.0
			else:
				var t: float = v.env_time / maxf(v.release, 0.0001)
				v.env_value = v.sustain * (1.0 - t)
		4:
			v.env_value = 0.0

	return s * v.env_value * v.velocity


# ============================================================
#  Voice 分配
# ============================================================
func _alloc_voice() -> int:
	# 1. 空闲
	for i in range(voices.size()):
		if not voices[i].active:
			return i
	# 2. 偷最早的（先开始播放的）
	var oldest := 0
	for i in range(1, voices.size()):
		if voices[i].start_sample < voices[oldest].start_sample:
			oldest = i
	return oldest
