class_name Sfx
extends Node
## Every sound synthesised in code at startup - no audio files. Roars are a pulse source
## (sawtooth with jitter and a sub-octave for the big ones) shaped by two formant filters
## whose frequencies scale with the size of the animal, plus breath noise; bites are bursts
## of crunch; bones crack; clubs and bodies thud. Played from a pool of positional players.

const RATE := 22050
const VOICES := 16
const REPEAT_GAP := 0.05

static var _mute := false

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _last := {}
var _clock := 0.0
var _enabled := true

# f0 start/peak/end (Hz), duration, F1, F2, roughness, sub-octave
const VOICE := {
	"rex":    [52.0, 66.0, 36.0, 2.4, 280.0, 640.0, 0.55, 0.6],
	"trike":  [85.0, 100.0, 70.0, 1.5, 380.0, 950.0, 0.35, 0.3],
	"anky":   [105.0, 120.0, 85.0, 0.9, 480.0, 1150.0, 0.45, 0.2],
	"stego":  [140.0, 165.0, 120.0, 1.1, 520.0, 1300.0, 0.25, 0.1],
	"allo":   [82.0, 105.0, 60.0, 1.7, 520.0, 1250.0, 0.7, 0.3],
	"raptor": [420.0, 640.0, 360.0, 0.9, 1400.0, 2900.0, 0.5, 0.0],
}


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	for id in VOICE:
		var v: Array = VOICE[id]
		_streams["roar_" + id] = _roar(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], hash(id))
		_streams["cry_" + id] = _roar(v[1] * 1.3, v[1] * 1.7, v[1] * 1.1, minf(0.7, v[3] * 0.35), v[4] * 1.2, v[5] * 1.2, v[6] + 0.2, 0.0, hash(id) + 1)
		_streams["die_" + id] = _roar(v[1], v[0], v[2] * 0.6, v[3] * 1.2, v[4], v[5] * 0.9, v[6] + 0.3, v[7], hash(id) + 2)
	_streams["crunch"] = _crunch()
	_streams["crack"] = _crack()
	_streams["thud"] = _thud(0.35, 90.0, 40.0)
	_streams["fall"] = _thud(0.9, 60.0, 25.0)
	_streams["step"] = _thud(0.16, 70.0, 35.0)
	_streams["gore"] = _gore()
	_streams["slash"] = _slash()
	_streams["whoosh"] = _whoosh()
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 22.0
		p.max_distance = 160.0
		p.max_db = 3.0
		p.panning_strength = 0.5
		add_child(p)
		_pool.append(p)


func _process(delta: float) -> void:
	_clock += delta


static func set_muted(m: bool) -> void:
	_mute = m
	AudioServer.set_bus_mute(0, m)


func play(cue: String, at: Vector3, pitch := 1.0, vol_db := 0.0) -> void:
	if not _enabled or _mute or not _streams.has(cue):
		return
	var last := float(_last.get(cue, -99.0))
	if _clock - last < REPEAT_GAP:
		return
	_last[cue] = _clock
	var p: AudioStreamPlayer3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[cue]
	p.global_position = at
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.volume_db = vol_db
	p.play()


# ---------------------------------------------------------------- recipes

static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in s:
		peak = maxf(peak, absf(v))
	var g := 0.92 / peak
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * g, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	b.fill(0.0)
	return b


static func _env(t: float, attack: float, curve: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return pow(maxf(0.0, 1.0 - (t - attack) / maxf(1.0 - attack, 0.0001)), curve)


static func _lowpass(b: PackedFloat32Array, alpha: float) -> void:
	var y := 0.0
	for i in b.size():
		y += alpha * (b[i] - y)
		b[i] = y


## Two-pole resonant band-pass (RBJ cookbook), returns a filtered copy.
static func _bandpass(x: PackedFloat32Array, f: float, q: float) -> PackedFloat32Array:
	var w0 := TAU * f / RATE
	var alpha := sin(w0) / (2.0 * q)
	var b0 := alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var v := (b0 * x[i] - b0 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = v
		y[i] = v
	return y


static func _roar(f_a: float, f_b: float, f_c: float, dur: float, f1: float, f2: float, rough: float, sub: float, seed_v: int) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var src := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var ph := 0.0
	var ph2 := 0.0
	var jit := 0.0
	for i in n:
		var t := float(i) / n
		var f0: float = lerpf(f_a, f_b, t / 0.3) if t < 0.3 else lerpf(f_b, f_c, (t - 0.3) / 0.7)
		jit = lerpf(jit, rng.randf_range(-1.0, 1.0), 0.02)
		f0 *= 1.0 + jit * 0.08 * rough + sin(t * dur * TAU * 6.5) * 0.015
		ph = fmod(ph + f0 / RATE, 1.0)
		ph2 = fmod(ph2 + f0 * 0.5 / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		var s := saw + (ph2 * 2.0 - 1.0) * sub
		s += rng.randf_range(-1.0, 1.0) * rough * 0.9
		src[i] = s * _env(t, 0.12, 0.7)
	var a := _bandpass(src, f1, 2.2)
	var b := _bandpass(src, f2, 3.0)
	var lo := src.duplicate()
	_lowpass(lo, 0.06)
	var out := _buf(dur)
	for i in n:
		out[i] = a[i] * 1.0 + b[i] * 0.55 + lo[i] * 0.6
	return _wav(out)


static func _crunch() -> AudioStreamWAV:
	var dur := 0.45
	var n := int(dur * RATE)
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# a thump of the jaws closing, then grit of teeth and bone
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(110.0, 45.0, t) / RATE
		b[i] = sin(ph) * _env(t, 0.01, 4.0) * 0.8
	for k in 14:
		var at := int(rng.randf_range(0.02, 0.7) * n)
		var ln := int(rng.randf_range(0.004, 0.02) * RATE)
		var amp := rng.randf_range(0.3, 0.9) * (1.0 - float(at) / n)
		for j in ln:
			if at + j < n:
				b[at + j] += rng.randf_range(-1.0, 1.0) * amp * (1.0 - float(j) / ln)
	return _wav(b)


static func _crack() -> AudioStreamWAV:
	var dur := 0.22
	var n := int(dur * RATE)
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / n
		b[i] = rng.randf_range(-1.0, 1.0) * _env(t, 0.002, 9.0)
		if i < 60:
			b[i] += 1.0 - i / 30.0
	var hp := b.duplicate()
	_lowpass(hp, 0.5)
	for i in n:
		b[i] = b[i] - hp[i] * 0.6
	return _wav(b)


static func _thud(dur: float, f_a: float, f_b: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(f_a, f_b, pow(t, 0.4)) / RATE
		b[i] = sin(ph) * _env(t, 0.004, 3.0) + rng.randf_range(-1.0, 1.0) * _env(t, 0.001, 20.0) * 0.3
	var lo := b.duplicate()
	_lowpass(lo, 0.25)
	return _wav(lo)


static func _gore() -> AudioStreamWAV:
	var dur := 0.5
	var n := int(dur * RATE)
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += TAU * lerpf(95.0, 40.0, t) / RATE
		b[i] = sin(ph) * _env(t, 0.005, 3.0) * 0.9
	var wet := _buf(dur)
	for i in n:
		var t := float(i) / n
		wet[i] = rng.randf_range(-1.0, 1.0) * _env(t, 0.05, 2.0)
	wet = _bandpass(wet, 700.0, 1.5)
	for i in n:
		b[i] += wet[i] * 1.2
	return _wav(b)


static func _slash() -> AudioStreamWAV:
	var dur := 0.3
	var n := int(dur * RATE)
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in n:
		var t := float(i) / n
		b[i] = rng.randf_range(-1.0, 1.0) * _env(t, 0.1, 2.5)
	b = _bandpass(b, 1800.0, 1.2)
	return _wav(b)


static func _whoosh() -> AudioStreamWAV:
	var dur := 0.45
	var n := int(dur * RATE)
	var b := _buf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	for i in n:
		b[i] = rng.randf_range(-1.0, 1.0)
	_lowpass(b, 0.1)
	for i in n:
		var t := float(i) / n
		var s := sin(PI * pow(t, 0.8))
		b[i] *= s * s
	return _wav(b)
