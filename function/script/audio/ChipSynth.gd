class_name ChipSynth
extends RefCounted

# ============================================================
#  ChipSynth — 8-bit 波形合成器（复音）
#  v3 更新（P0-P3）：
#    - 脉冲波/噪声改单极性 0/+1（NES 硬件特征）
#    - 输出级加 DC blocking 高通（模拟 NES 输出耦合电容）
#    - 三角波不受 ADSR 音量影响（NES 三角波无音量控制）
#    - 噪声通道支持 16 档 NES period + 短/长模式
#    - 脉冲通道支持硬件 Sweep（音高滑移）
#    - 通道增益平滑过渡（避免静音时咔哒）
#    - 单通道单音化（可选，NES 风格，默认开启）
#    - 缓存 1/mix_rate
# ============================================================

enum Wave { PULSE_12, PULSE_25, PULSE_50, PULSE_75, TRIANGLE, NOISE, SAW }

# NES 硬件噪声周期表（NTSC CPU 时钟周期数，index 0-15）
const NES_NOISE_PERIODS: Array[int] = [
	4, 8, 16, 32, 64, 96, 128, 160,
	202, 254, 380, 508, 762, 1016, 2034, 4068
]
const NES_CPU_CLOCK: float = 1789773.0

# 通道增益平滑系数（越大越快；0.02 ≈ 100 采样 / 5ms @20kHz 收敛）
const GAIN_SMOOTH_ALPHA: float = 0.02


class Voice:
	var active: bool = false
	var wave: int = Wave.PULSE_50
	var phase: float = 0.0
	var phase_inc: float = 0.0
	var frequency: float = 440.0
	var base_frequency: float = 440.0      # sweep 的基准频率
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

	# Noise LFSR
	var lfsr: int = 0x7FFF
	var noise_period_samples: float = 1.0
	var noise_counter: float = 0.0
	var noise_short_mode: bool = false

	# Sweep（脉冲通道专用）
	var sweep_enabled: bool = false
	var sweep_period: int = 0            # 每 N 个完整周期调整一次
	var sweep_shift: int = 0             # 移位量 1-7
	var sweep_negate: bool = false       # true = 下扫
	var sweep_counter: int = 0

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
var _inv_mix_rate: float = 1.0

## 是否每个通道只允许一个 voice 同时发声（NES 风格）。默认开启。
var mono_per_channel: bool = true

# 通道增益（目标值 / 平滑值）。索引 = 通道号
var channel_gain_target: Array[float] = [1.0, 1.0, 1.0, 1.0]
var channel_gain_smooth: Array[float] = [1.0, 1.0, 1.0, 1.0]

# DC blocking 高通滤波状态（模拟 NES 输出耦合电容）
var _dc_prev_in: Vector2 = Vector2.ZERO
var _dc_prev_out: Vector2 = Vector2.ZERO
var _dc_r: float = 0.9957   # fc ≈ 15Hz @ 20kHz（_init 中按 rate 重算）


func _init(pool_size: int = 12, rate: float = 44100.0):
	mix_rate = rate
	_inv_mix_rate = 1.0 / rate
	# 一阶高通截止频率 fc ≈ (1-r)*fs/(2π)，取 fc = 15Hz
	_dc_r = 1.0 - (2.0 * PI * 15.0 / rate)
	_dc_r = clampf(_dc_r, 0.0, 0.9999)
	for i in range(pool_size):
		voices.append(Voice.new())


# ============================================================
#  通道增益（静音）
# ============================================================
## 设置某通道目标增益（0.0 = 静音，1.0 = 正常），播放中平滑过渡
func set_channel_gain(ch: int, gain: float):
	if ch < 0: return
	while channel_gain_target.size() <= ch:
		channel_gain_target.append(1.0)
		channel_gain_smooth.append(1.0)
	channel_gain_target[ch] = clampf(gain, 0.0, 1.0)


func get_channel_gain(ch: int) -> float:
	if ch < 0 or ch >= channel_gain_target.size():
		return 1.0
	return channel_gain_target[ch]


func set_channel_muted(ch: int, muted: bool):
	set_channel_gain(ch, 0.0 if muted else 1.0)


# ============================================================
#  播放控制
# ============================================================
## 分配一个 voice 播放指定 note
## 优先找空闲 voice；全忙则偷"最早启动"的
## 返回 voice 索引（-1 = 失败）
func note_on(ch: int, midi_note: int, velocity: float,
			 wave: int, env: Dictionary, pan: float = 0.0) -> int:
	# ★ 单通道单音化：先 release 同通道正在发声的 voice
	if mono_per_channel:
		for i in range(voices.size()):
			var vo := voices[i]
			if vo.active and vo.ch_owner == ch \
					and vo.env_stage != 3 and vo.env_stage != 4:
				vo.env_stage = 3
				vo.env_time = 0.0

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
	v.base_frequency = v.frequency
	v.phase_inc = v.frequency * _inv_mix_rate
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

	# ---- 噪声初始化 ----
	var noise_idx := int(env.get("noise_period", 4))   # NES index 0-15
	noise_idx = clampi(noise_idx, 0, 15)
	v.noise_period_samples = NES_NOISE_PERIODS[noise_idx] * mix_rate / NES_CPU_CLOCK
	v.noise_period_samples = maxf(v.noise_period_samples, 1.0)
	v.noise_counter = 0.0
	v.noise_short_mode = bool(env.get("noise_short", false))

	# ---- Sweep 初始化 ----
	v.sweep_enabled = bool(env.get("sweep_enabled", false))
	v.sweep_period = maxi(int(env.get("sweep_period", 0)), 0)
	v.sweep_shift  = clampi(int(env.get("sweep_shift", 0)), 0, 7)
	v.sweep_negate = bool(env.get("sweep_negate", false))
	v.sweep_counter = 0

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
	# 复位 DC 滤波状态，避免切换时产生咔哒
	_dc_prev_in = Vector2.ZERO
	_dc_prev_out = Vector2.ZERO


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

		# ★ 平滑通道增益（避免瞬间切换造成咔哒）
		var ch := v.ch_owner
		if ch >= 0 and ch < channel_gain_smooth.size():
			var cur := channel_gain_smooth[ch]
			var tgt := channel_gain_target[ch]
			if cur != tgt:
				cur += (tgt - cur) * GAIN_SMOOTH_ALPHA
				if absf(cur - tgt) < 0.0005:
					cur = tgt
				channel_gain_smooth[ch] = cur
			s *= cur

		# pan: -1 = 全左, 0 = 中, +1 = 全右
		var l_gain := sqrt(0.5 * (1.0 - v.pan))
		var r_gain := sqrt(0.5 * (1.0 + v.pan))
		sum_l += s * l_gain
		sum_r += s * r_gain

	sum_l *= master_volume
	sum_r *= master_volume

	# ★ 单极点 DC blocking 高通（模拟 NES 输出耦合电容）
	#   y[n] = x[n] - x[n-1] + r * y[n-1]
	var inp := Vector2(sum_l, sum_r)
	var out := inp - _dc_prev_in + _dc_prev_out * _dc_r
	_dc_prev_in = inp
	_dc_prev_out = out

	_sample_cursor += 1
	return Vector2(clampf(out.x, -1.0, 1.0), clampf(out.y, -1.0, 1.0))


func _sample_voice(v: Voice) -> float:
	# ---- 波形 ----
	var s := 0.0
	match v.wave:
		Wave.PULSE_12: s = 1.0 if v.phase < 0.125 else 0.0
		Wave.PULSE_25: s = 1.0 if v.phase < 0.25  else 0.0
		Wave.PULSE_50: s = 1.0 if v.phase < 0.5   else 0.0
		Wave.PULSE_75: s = 1.0 if v.phase < 0.75  else 0.0
		Wave.TRIANGLE:
			# NES 三角波：32 步阶梯（16 级对称往返），-1 → +1
			var step : int = int(v.phase * 32.0) % 32
			if step < 16:
				s = float(step) / 15.0 * 2.0 - 1.0
			else:
				s = 1.0 - float(step - 16) / 15.0 * 2.0
		Wave.SAW:      s = 2.0 * v.phase - 1.0
		Wave.NOISE:
			v.noise_counter += 1.0
			if v.noise_counter >= v.noise_period_samples:
				v.noise_counter -= v.noise_period_samples
				var bit: int
				if v.noise_short_mode:
					# 短模式：bit0 XOR bit6，周期 93
					bit = ((v.lfsr >> 0) ^ (v.lfsr >> 6)) & 1
				else:
					# 长模式：bit0 XOR bit1，周期 32767
					bit = ((v.lfsr >> 0) ^ (v.lfsr >> 1)) & 1
				v.lfsr = (v.lfsr >> 1) | (bit << 14)
			s = 1.0 if (v.lfsr & 1) == 1 else 0.0

	# ---- 相位推进 ----
	v.phase += v.phase_inc
	if v.phase >= 1.0:
		v.phase -= 1.0

		# ---- Sweep（相位回绕 = 一个完整周期） ----
		if v.sweep_enabled and v.sweep_period > 0 and v.sweep_shift > 0:
			v.sweep_counter += 1
			if v.sweep_counter >= v.sweep_period:
				v.sweep_counter = 0
				var delta : float = v.base_frequency / float(1 << v.sweep_shift)
				var new_freq : float
				if v.sweep_negate:
					new_freq = v.frequency - delta
				else:
					new_freq = v.frequency + delta
				var fmax : float = mix_rate * 0.45
				new_freq = clampf(new_freq, 20.0, fmax)
				v.frequency = new_freq
				v.phase_inc = v.frequency * _inv_mix_rate

	# ---- ADSR ----
	v.env_time += _inv_mix_rate
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

	# ★ 三角波：NES 无音量控制，不受包络量化影响
	#   （仍用 env_stage == 4 判断"是否已结束"，velocity 保留以支持通道音量）
	if v.wave == Wave.TRIANGLE:
		if v.env_stage == 4:
			return 0.0
		return s * v.velocity

	# 其它波形：4-bit 音量量化（NES 硬件 DAC）
	var env_q : float = round(v.env_value * 15.0) / 15.0
	return s * env_q * v.velocity


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
