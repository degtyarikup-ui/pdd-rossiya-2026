## Sounds of the game, made in code (no files), like assets/game/ambient-audio.js:
## engine that rises with speed, tyre hiss, indicator click, crash, scrape, the
## last-seconds tick and the answer tones. Vibration goes with the sharp events.
class_name GameSound
extends Node

const RATE := 22050.0
const DURATION := {
	"click": 0.03, "tick": 0.06, "correct": 0.35, "incorrect": 0.4, "crash": 0.7, "scrape": 0.25,
}

var enabled := true
var speed := 0.0                  # m/s, set by the world every frame
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _tyre_lp := 0.0
var _events: Array = []


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.volume_db = -3.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()


## One-shot sound by name (see DURATION). Silent when sound is off.
func play(kind: String) -> void:
	if enabled:
		_events.append({ "kind": kind, "t": 0.0, "dur": DURATION.get(kind, 0.1) })


static var haptics := true         # the app's setting («Вибрация»): off, the phone stays quiet

## Short vibration for sharp events (the phone's own motor; not on desktop).
static func buzz(ms: int) -> void:
	if haptics:
		Input.vibrate_handheld(ms)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	for _i in _playback.get_frames_available():
		var s := _sample() if enabled else 0.0
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
		"incorrect":
			return (1.0 if sin(TAU * 220.0 * t) >= 0.0 else -1.0) * 0.12 * env
		"crash":
			return (randf() * 2.0 - 1.0) * 0.5 * env + sin(TAU * 55.0 * t) * 0.4 * env
		"scrape":
			return (randf() * 2.0 - 1.0) * 0.25 * env
	return 0.0
