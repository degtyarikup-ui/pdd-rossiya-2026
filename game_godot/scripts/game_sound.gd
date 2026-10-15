## Sounds of the game, made in code (no files), like assets/game/ambient-audio.js:
## engine that rises with speed, tyre hiss, indicator click, crash, scrape, the
## last-seconds tick, answer tones and a soft unlock chime. Vibration goes with the sharp events.
class_name GameSound
extends Node

const RATE := 22050.0
const DURATION := {
	"click": 0.03, "tick": 0.06, "correct": 0.35, "incorrect": 0.4, "crash": 0.32, "scrape": 0.25,
	"unlock": 0.95,
}
const UNLOCK_NOTES := [Vector2(0.0, 523.251), Vector2(0.085, 659.255), Vector2(0.17, 783.991), Vector2(0.27, 1046.502)]

var enabled := true
var speed := 0.0                  # m/s, set by the world every frame
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _tyre_lp := 0.0
var _impact_lp := 0.0
var _events: Array = []


func _ready() -> void:
	# Headless checks have no listener and use the Dummy audio backend, which retains its generator
	# playback at shutdown. Do not allocate or synthesize an audio stream in that environment.
	if DisplayServer.get_name() == "headless":
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
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


## One-shot sound by name (see DURATION). Silent when sound is off.
func play(kind: String) -> void:
	if enabled:
		if kind == "crash" and _events.any(func(e): return e.kind == "crash"):
			return
		_events.append({ "kind": kind, "t": 0.0, "dur": DURATION.get(kind, 0.1) })


## A small ascending major arpeggio for a new car or colour. Uses the same stream
## as driving sounds, so mute, pause and shutdown keep their existing behaviour.
func play_unlock() -> void:
	play("unlock")


static var haptics := true         # the app's setting («Вибрация»): off, the phone stays quiet

## Short vibration for sharp events (the phone's own motor; not on desktop).
static func buzz(ms: int) -> void:
	if haptics:
		Input.vibrate_handheld(ms)


func _process(_delta: float) -> void:
	if _player == null:
		return
	if not enabled:
		if _player.playing:
			_player.stop()
		_playback = null
		_events.clear()
		return
	if _playback == null:
		_start_playback()
	if _playback == null:
		return
	for _i in _playback.get_frames_available():
		var s := _sample()
		_playback.push_frame(Vector2(s, s))


func _sample() -> float:
	var dt := 1.0 / RATE
	# Engine: a sawtooth-like tone whose pitch rises with speed (idle when stopped).
	var f := 28.0 + absf(speed) * 3.2
	_engine_phase = fposmod(_engine_phase + f * dt, 1.0)
	var engine := (2.0 * _engine_phase - 1.0) * 0.5 + sin(TAU * _engine_phase * 2.0) * 0.2
	engine *= 0.03 + clampf(absf(speed) / 25.0, 0.0, 1.0) * 0.03
	# Tyres: low-passed noise, louder with speed.
	var noise := randf() * 2.0 - 1.0
	_tyre_lp += (noise - _tyre_lp) * 0.08
	var tyres := _tyre_lp * clampf(absf(speed) / 20.0, 0.0, 1.0) * 0.06
	var out := engine + tyres
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
		"tick":
			return sin(TAU * 1000.0 * t) * 0.2 * env
		"correct":
			return sin(TAU * (880.0 * t + 220.0 * t * u)) * 0.2 * env
		"unlock":
			return _unlock_chime(t)
		"incorrect":
			return (1.0 if sin(TAU * 220.0 * t) >= 0.0 else -1.0) * 0.12 * env
		"crash":
			_impact_lp += ((randf() * 2.0 - 1.0) - _impact_lp) * 0.045
			var attack := minf(1.0, t / 0.012)
			return (_impact_lp * 0.14 + sin(TAU * 65.0 * t) * 0.12) * env * attack
		"scrape":
			return (randf() * 2.0 - 1.0) * 0.25 * env
	return 0.0


func _unlock_chime(t: float) -> float:
	var out := 0.0
	for note in UNLOCK_NOTES:
		var age: float = t - note.x
		if age < 0.0:
			continue
		# Rounded attacks and a quiet bell overtone give the chime a gentle lift;
		# every voice reaches silence before the event ends, avoiding a cut-off click.
		var attack := smoothstep(0.0, 0.009, age)
		var release := smoothstep(0.0, 0.14, float(DURATION.unlock) - t)
		var envelope := attack * exp(-6.5 * age) * release
		var phase: float = TAU * note.y * age
		out += (sin(phase) + sin(phase * 2.0) * 0.16) * envelope * 0.085
	return out
