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
	for kind in ["correct", "incorrect"]:
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
	check(sound._events.is_empty(), "muted unlock does not queue delayed feedback")
	sound.enabled = true
	sound.play_unlock()
	check(sound._events.size() == 1 and sound._events[0].dur > 0.7 and sound._events[0].dur <= 1.0, "unlock queues one short chime in the shared audio stream")
	var energy := 0.0
	var peak := 0.0
	var duration: float = sound._events[0].dur
	for i in int(GameSound.RATE * duration):
		var sample: float = sound._one_shot({"kind": "unlock", "t": float(i) / GameSound.RATE, "dur": duration})
		energy += sample * sample
		peak = maxf(peak, absf(sample))
	check(energy > 1.0 and peak < 0.3, "unlock chime is audible and leaves mixing headroom")
	check(is_zero_approx(sound._unlock_chime(0.0)) and absf(sound._unlock_chime(duration - 0.001)) < 0.0001 and is_zero_approx(sound._unlock_chime(duration)), "unlock has a smooth attack and reaches silence before release")
	for i in int(GameSound.RATE * duration) + 1:
		sound._sample()
	check(sound._events.is_empty(), "unlock releases its event after the tail")
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
		sound.play_unlock()
		sound.enabled = false
		sound._process(1.0 / 60.0)
		check(not sound._answers.correct.playing and not sound._answers.incorrect.playing and not sound._player.playing and sound._playback == null and sound._events.is_empty(), "muting stops generation and clears stale feedback")
		var phase: float = sound._engine_phase
		for i in 120:
			sound._process(1.0 / 60.0)
		check(sound._engine_phase == phase, "muted frames do not synthesize zero audio buffers")
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
