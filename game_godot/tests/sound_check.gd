## Native: startup, mute/unmute and stream teardown. Headless: audio is deliberately not allocated.
extends SceneTree

var failed := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)
	print("%s: %s" % ["PASS" if ok else "FAIL", message])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for kind in GameSound.EFFECT_VOLUMES:
		var path := "res://answer_audio/%s.wav" % kind
		var shared := PackFiles.bytes(path)
		var source := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path("res://").path_join("../assets/audio/%s.wav" % kind))
		check(not shared.is_empty() and shared == source, "%s uses the exact Flutter WAV bytes" % kind)
		var stream := AudioStreamWAV.load_from_buffer(shared)
		check(stream != null and stream.get_length() > 0.0, "%s WAV decodes for Godot" % kind)
	var sound := GameSound.new()
	sound.enabled = false
	root.add_child(sound)
	sound.set_process(false)
	sound.play_unlock()
	sound.play("tick")
	sound.vehicle("muted", "tram", 5.0, true)
	check(sound._events.is_empty() and sound._vehicles.is_empty(), "mute queues neither transport nor delayed reward/tick")
	sound.enabled = true
	sound.vehicle("tram", "tram", 6.8)
	check(sound._vehicles.size() == 1 and sound._events.size() == 1 and sound._events[0].kind == "bell", "moving tram starts electric motor and one bell")
	sound.vehicle("tram", "tram", 6.8)
	check(sound._events.size() == 1, "continuous tram motion does not repeat the bell every frame")
	sound.vehicle("pedestrian", "pedestrian", 2.0)
	sound.vehicle("stationary", "car", 0.0)
	check(sound._vehicles.size() == 1, "pedestrians and stopped cars do not create engines")
	sound.vehicle("emergency", "police", 0.0, true)
	check(sound._vehicles.emergency.siren, "explicit special signal sounds even while vehicle waits")
	for i in 10:
		sound.vehicle("car%d" % i, "car", 8.0)
	check(sound._vehicles.size() == GameSound.MAX_VOICES, "transport mixer has a fixed voice budget")
	sound.vehicle("priority_siren", "police", 5.0, true, 0.5)
	check(sound._vehicles.has("priority_siren") and sound._vehicles.size() == GameSound.MAX_VOICES, "active siren takes precedence over a background motor")
	var energy := 0.0
	for i in int(GameSound.RATE * 0.1):
		var sample: float = sound._sample()
		energy += sample * sample
	check(energy > 0.1, "ported transport and bell produce audible samples")
	sound._events.clear()
	sound._vehicles.clear()
	sound._mix_voices.clear()
	var profiles := []
	for kind in ["car", "truck", "bus", "motorcycle", "tram"]:
		var voice := GameSound.TransportVoice.new()
		voice.configure(kind, 8.0)
		var checksum := 0.0
		seed(42)
		for i in 2205:
			checksum += sound._engine_sample(voice, 1.0) * float(i + 1)
		profiles.append(checksum)
	check(absf(profiles[0] - profiles[1]) > 0.1 and absf(profiles[1] - profiles[2]) > 0.1 and absf(profiles[3] - profiles[4]) > 0.1, "car, truck, bus, motorcycle and tram retain distinct motors")
	check(is_zero_approx(GameSound._bell_sample(0.0)) and absf(GameSound._bell_sample(1.3)) < 0.0001, "tram bell has a smooth attack and silent tail")
	sound.enabled = false
	if DisplayServer.get_name() == "headless":
		check(sound._player == null and sound._playback == null, "headless does not allocate a dummy generator")
		sound.enabled = true
		sound._process(1.0 / 60.0)
		check(sound._playback == null, "headless remains silent after enabling sound")
	else:
		check(sound._player != null and sound._player.playback_type == AudioServer.PLAYBACK_TYPE_STREAM and not sound._player.playing and sound._playback == null, "muted startup uses the streaming backend without active playback")
		sound.enabled = true
		sound._process(1.0 / 60.0)
		check(sound._player.playing and sound._playback != null, "enabling starts native audio generation")
		sound.play("correct")
		check(sound._events.is_empty(), "answer feedback does not synthesize a second tone")
		check(sound._answers.correct.playing, "correct answer plays the shared recording")
		check(is_equal_approx(sound._answers.correct.volume_db, linear_to_db(0.55)), "correct answer matches Flutter volume")
		sound.play("incorrect")
		check(sound._answers.incorrect.playing, "incorrect answer plays the shared recording")
		check(is_equal_approx(sound._answers.incorrect.volume_db, linear_to_db(0.45)), "incorrect answer matches Flutter volume")
		sound.play("tick")
		check(sound._answers.tick.playing and is_equal_approx(sound._answers.tick.volume_db, linear_to_db(0.35)), "countdown plays the app tick at its original volume")
		sound.play_unlock()
		check(sound._answers.streak.playing and sound._events.is_empty(), "new car and paint use the existing celebration recording")
		sound.vehicle("moving", "car", 8.0)
		sound._clock += GameSound.VOICE_TAIL + 0.1
		sound._process(0.0)
		check(sound._vehicles.is_empty(), "transport voices expire when scene stops refreshing them")
		sound.enabled = false
		sound._process(1.0 / 60.0)
		check(not sound._answers.streak.playing and not sound._answers.tick.playing and not sound._answers.correct.playing and not sound._answers.incorrect.playing and not sound._player.playing and sound._playback == null and sound._events.is_empty(), "muting stops generation and clears stale feedback")
		var phase: float = sound._player_voice.phase
		for i in 120:
			sound._process(1.0 / 60.0)
		check(sound._player_voice.phase == phase, "muted frames do not synthesize zero audio buffers")
		sound.enabled = true
		sound._process(1.0 / 60.0)
		check(sound._player.playing and sound._playback != null, "unmuting resumes native playback")
		sound._exit_tree()
		check(not sound._player.playing and sound._playback == null, "teardown releases playback")
	sound.queue_free()
	# Let the native mixer consume queued stop commands before ending the process.
	if DisplayServer.get_name() != "headless":
		await create_timer(0.2).timeout
	await process_frame
	await process_frame
	print("Sound lifecycle: %d failures" % failed)
	quit(0 if failed == 0 else 1)
