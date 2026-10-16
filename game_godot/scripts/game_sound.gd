## Shared Flutter feedback recordings and procedural transport ported from
## assets/game/ambient-audio.js. One mixer for all three games; no audio copies.
class_name GameSound
extends Node

const RATE := 22050.0
const DURATION := {
	"click": 0.03, "crash": 0.32, "scrape": 0.25,
	"bell": 1.3,
}
const EFFECT_VOLUMES := {"correct": 0.55, "incorrect": 0.45, "tick": 0.35, "streak": 0.70}
# Original WebAudio engine ranges, including the electric tram motor.
const ENGINES := {"car": Vector2(70, 150), "suv": Vector2(62, 135),
	"truck": Vector2(45, 95), "bus": Vector2(48, 100),
	"motorcycle": Vector2(110, 260), "police": Vector2(70, 150),
	"emergency": Vector2(64, 140), "tram": Vector2(110, 190)}
const MAX_VOICES := 4
const VOICE_TAIL := 0.20


# Typed state keeps the per-sample mixer cheap on phones. Filter coefficients
# and motor pitch change only when the vehicle's speed changes.
class TransportVoice:
	var phase := 0.0
	var lp := 0.0
	var tyre_lp := 0.0
	var age := 0.0
	var level := 0.0
	var kind := ""
	var speed := -1.0
	var siren := false
	var gain := 1.0
	var seen := 0.0
	var phase_step := 0.0
	var filter_alpha := 0.0
	var motor_gain := 0.045
	var tyre_gain := 0.0
	var electric := false

	func configure(next_kind: String, velocity: float) -> void:
		if kind == next_kind and is_equal_approx(speed, velocity): return
		kind = next_kind
		speed = velocity
		var profile: Vector2 = ENGINES.get(kind, ENGINES.car)
		var rev := clampf(velocity / 14.0, 0.0, 1.0)
		phase_step = lerpf(profile.x, profile.y, rev) / RATE
		filter_alpha = 1.0 - exp(-TAU * lerpf(380.0, 900.0, rev) / RATE)
		motor_gain = 0.06 if kind in ["truck", "bus"] else 0.045
		tyre_gain = 0.003 * rev
		electric = kind == "tram"

var suspended := false
var enabled := true
var speed := 0.0                  # m/s, set by the world every frame
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _impact_lp := 0.0
var _buffer := PackedVector2Array()
var _events: Array = []
var _answers: Dictionary = {}
var _vehicles: Dictionary = {}
var _mix_voices: Array[TransportVoice] = []
var _clock := 0.0
var player_kind := "car"
var _player_voice := TransportVoice.new()



func _ready() -> void:
	# Headless checks have no listener and use the Dummy audio backend, which retains its generator
	# playback at shutdown. Do not allocate or synthesize an audio stream in that environment.
	if DisplayServer.get_name() == "headless":
		return
	for kind in EFFECT_VOLUMES:
		var answer := AudioStreamPlayer.new()
		answer.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		answer.volume_db = linear_to_db(EFFECT_VOLUMES[kind])
		add_child(answer)
		_answers[kind] = answer
		var path := "res://answer_audio/%s.wav" % kind
		PackFiles.fetch(path, GameSound._answer_loaded.bind(weakref(self), kind, path))
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.24
	_player = AudioStreamPlayer.new()
	# Procedural generators need streaming on Web too; the default sample backend cannot play them.
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_player.stream = gen
	_player.volume_db = -3.0
	add_child(_player)
	if enabled:
		_start_playback()


func _start_playback() -> void:
	_player.play()
	_playback = _player.get_stream_playback()


func _exit_tree() -> void:
	if is_instance_valid(_player):
		_player.stop()
	_playback = null
	_events.clear()
	_vehicles.clear()
	_mix_voices.clear()
	for answer in _answers.values():
		answer.stop()


static func _answer_loaded(ok: bool, holder: WeakRef, kind: String, path: String) -> void:
	var sound: GameSound = holder.get_ref()
	if sound == null or not sound.is_inside_tree() or not ok:
		return
	var data := PackFiles.bytes(path)
	if not data.is_empty():
		sound._answers[kind].stream = AudioStreamWAV.load_from_buffer(data)


## One-shot sound by name (see DURATION). Silent when sound is off.
func play(kind: String) -> void:
	if enabled:
		if kind in EFFECT_VOLUMES:
			var answer: AudioStreamPlayer = _answers.get(kind)
			if answer != null and answer.stream != null:
				answer.play()
			return
		if kind == "crash" and _events.any(func(e): return e.kind == "crash"):
			return
		_events.append({ "kind": kind, "t": 0.0, "dur": DURATION.get(kind, 0.1) })


## The app's existing celebration fanfare for a new car or colour.
func play_unlock() -> void:
	play("streak")


static var haptics := true         # the app's setting («Вибрация»): off, the phone stays quiet

## Short vibration for sharp events (the phone's own motor; not on desktop).
static func buzz(ms: int) -> void:
	if haptics:
		Input.vibrate_handheld(ms)


func _process(delta: float) -> void:
	if not enabled or suspended:
		for answer in _answers.values():
			answer.stop()
		if _player != null and _player.playing:
			_player.stop()
		_playback = null
		_events.clear()
		_vehicles.clear()
		_mix_voices.clear()
		return
	_clock += delta
	for id in _vehicles.keys():
		if _clock - float(_vehicles[id].seen) > VOICE_TAIL:
			_vehicles.erase(id)
			_mix_voices.assign(_vehicles.values())
	if _player == null:
		return
	if _playback == null:
		_start_playback()
	if _playback == null:
		return
	_player_voice.configure(player_kind, absf(speed))
	# Submit one block per frame, rather than thousands of engine API calls.
	# A 240 ms ring keeps audio fed through short rendering/streaming stalls.
	var frames := _playback.get_frames_available()
	_buffer.resize(frames)
	for i in frames:
		var s := _sample()
		_buffer[i] = Vector2(s, s)
	if frames > 0: _playback.push_buffer(_buffer)


func _sample() -> float:
	var dt := 1.0 / RATE
	var out := _engine_sample(_player_voice, 1.0 if absf(speed) > 0.1 else 0.0)
	for voice: TransportVoice in _mix_voices:
		var fade := clampf(1.0 - maxf(0.0, _clock - float(voice.seen) - 0.08) / (VOICE_TAIL - 0.08), 0.0, 1.0)
		out += _engine_sample(voice, voice.gain * fade)
		if voice.siren:
			out += _siren_sample(voice.age) * voice.gain * fade
	var i := 0
	while i < _events.size():
		var e: Dictionary = _events[i]
		e.t += dt
		if e.t >= e.dur:
			_events.remove_at(i)
			continue
		out += _one_shot(e)
		i += 1
	return clampf(out, -1.0, 1.0)


func _one_shot(e: Dictionary) -> float:
	var t: float = e.t
	var u: float = t / float(e.dur)
	var env := exp(-4.0 * u)
	match e.kind:
		"click":
			return sin(TAU * 1400.0 * t) * 0.25 * env
		"bell":
			return _bell_sample(t) * float(e.get("gain", 1.0))
		"crash":
			_impact_lp += ((randf() * 2.0 - 1.0) - _impact_lp) * 0.045
			var attack := minf(1.0, t / 0.012)
			return (_impact_lp * 0.14 + sin(TAU * 65.0 * t) * 0.12) * env * attack
		"scrape":
			return (randf() * 2.0 - 1.0) * 0.25 * env
	return 0.0


## Refresh only audible, actually moving vehicles (or an active special signal).
## Callers use stable IDs; no scene nodes are retained after a junction is freed.
func vehicle(id: String, kind: String, metres_per_second: float, siren := false, gain := 1.0) -> void:
	if not enabled or gain <= 0.0 or (metres_per_second <= 0.1 and not siren):
		return
	if kind in ["pedestrian", "cyclist", "cart", "barrier", "train"]:
		return
	if not _vehicles.has(id):
		if _vehicles.size() >= MAX_VOICES:
			# A quiet background motor must never occupy the last slot needed
			# by a nearby tram or an explicit special signal.
			var quietest := ""
			var lowest := INF
			for key in _vehicles:
				var candidate: TransportVoice = _vehicles[key]
				var rank := candidate.gain + (2.0 if candidate.siren else 0.0)
				if rank < lowest:
					lowest = rank
					quietest = key
			if gain + (2.0 if siren else 0.0) <= lowest: return
			_vehicles.erase(quietest)
		_vehicles[id] = TransportVoice.new()
		_mix_voices.assign(_vehicles.values())
		if kind == "tram" and metres_per_second > 0.1:
			_events.append({"kind": "bell", "t": 0.0, "dur": DURATION.bell, "gain": gain})
	var voice: TransportVoice = _vehicles[id]
	voice.configure(kind, metres_per_second)
	voice.siren = siren
	voice.gain = clampf(gain, 0.0, 1.0)
	voice.seen = _clock


## Original engine frequencies, saw/triangle oscillator, low-pass and tyre layer.
## Pitch follows motion; short smoothing ramps avoid clicks on stop/start.
func _engine_sample(voice: TransportVoice, gain: float) -> float:
	voice.age += 1.0 / RATE
	var target := gain if voice.speed > 0.1 else 0.0
	voice.level = move_toward(voice.level, target, 1.0 / (RATE * 0.08))
	if voice.level <= 0.0001:
		return 0.0
	voice.phase = fposmod(voice.phase + voice.phase_step, 1.0)
	var oscillator := (1.0 - 4.0 * absf(voice.phase - 0.5)) if voice.electric else (2.0 * voice.phase - 1.0)
	voice.lp += (oscillator - voice.lp) * voice.filter_alpha
	# Road noise must be low-passed too: raw white noise overwhelms the
	# quiet motor with broadband hiss, especially with several nearby cars.
	voice.tyre_lp += ((randf() * 2.0 - 1.0) - voice.tyre_lp) * 0.09
	return (voice.lp * voice.motor_gain + voice.tyre_lp * voice.tyre_gain) * voice.level


static func _siren_sample(t: float) -> float:
	var frequency := 960.0 if int(t / 0.36) % 2 else 720.0
	var interval := int(t / 0.36)
	var cycles := float(interval / 2) * (720.0 + 960.0) * 0.36 + (720.0 * 0.36 if interval % 2 else 0.0)
	var phase := fposmod(cycles + fmod(t, 0.36) * frequency, 1.0)
	return (1.0 - 4.0 * absf(phase - 0.5)) * 0.035 * minf(1.0, t / 0.1)


static func _bell_sample(t: float) -> float:
	var out := 0.0
	for strike in [0.0, 0.28]:
		var age: float = t - strike
		if age < 0.0 or age > 1.0: continue
		var envelope := minf(1.0, age / 0.005) * exp(-8.0 * age)
		for partial in [Vector2(1180, 0.05), Vector2(1770, 0.025), Vector2(2950, 0.012)]:
			out += sin(TAU * partial.x * age) * partial.y * envelope
	return out
