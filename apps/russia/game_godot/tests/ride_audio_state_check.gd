## Exercise World's actual freeze/thaw order with a live generator, not manual flags.
extends SceneTree
class AudioWorld extends "res://scripts/world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _notification(_what: int) -> void: pass
	func _exit_tree() -> void: pass
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var world := AudioWorld.new()
	root.add_child(world)
	world.sound = GameSound.new()
	world.add_child(world.sound)
	if DisplayServer.get_name() == "headless":
		# Real audio node even with the Dummy backend; bypass GameSound's headless shortcut.
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 22050
		world.sound._player = AudioStreamPlayer.new()
		world.sound._player.stream = generator
		world.sound.add_child(world.sound._player)
		world.sound._start_playback()
	world.sound.speed = 10.0
	for i in 3: await process_frame
	check(not world.sound._player.stream_paused, "generator begins unpaused")
	for cycle in 3:
		world._freeze_world_actors()
		check(world.sound._player.stream_paused, "garage pauses generator")
		world.sound.enabled = false
		world.sound.enabled = true
		await process_frame
		world._thaw_world_actors()
		for i in 3: await process_frame
		check(world.sound._player.playing and not world.sound._player.stream_paused,
			"World restores audible driving after garage cycle %d" % cycle)
	world.queue_free()
	await process_frame
	print("ride_audio_state_check: %d failures" % failures)
	quit(1 if failures else 0)
