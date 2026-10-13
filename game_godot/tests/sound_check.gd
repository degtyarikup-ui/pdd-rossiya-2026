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
	var sound := GameSound.new()
	sound.enabled = false
	root.add_child(sound)
	sound.set_process(false)
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
		check(sound._events.size() == 1, "enabled feedback is queued")
		sound.enabled = false
		sound._process(1.0 / 60.0)
		check(not sound._player.playing and sound._playback == null and sound._events.is_empty(), "muting stops generation and clears stale feedback")
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
