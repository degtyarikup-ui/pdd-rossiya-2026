## Closing an owner must unwind a nested worker await before its scene is freed.
extends SceneTree

class Owner extends Node3D:
	var closing := false
	func staging_cancelled() -> bool: return closing

var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func prepare(scene: Situation, result: Array) -> void:
	result[0] = await Situation._mesh_in_background(func():
		OS.delay_msec(40)
		return ArrayMesh.new(), self, weakref(scene))
	result[1] = true

func run() -> void:
	for cancellation in ["none", "closing", "queued", "host"]:
		var owner := Owner.new()
		root.add_child(owner)
		var scene := Situation.new()
		scene._staging_owner = weakref(owner)
		owner.add_child(scene)
		var result := [null, false]
		prepare(scene, result)
		check(not Situation._tasks.is_empty(), cancellation + " starts an asynchronous worker")
		match cancellation:
			"closing": owner.closing = true
			"queued": owner.queue_free()
			"host": root.set_meta(Host.EXIT_META, 1)
		for frame in 120:
			if result[1]: break
			await process_frame
		check(result[1], cancellation + " resumes the suspended caller")
		check(Situation._tasks.is_empty(), cancellation + " joins and forgets the worker")
		check((result[0] is ArrayMesh) if cancellation == "none" else result[0] == null,
			cancellation + " returns geometry only to a live owner")
		if is_instance_valid(owner): owner.queue_free()
		root.remove_meta(Host.EXIT_META)
		await process_frame
		await process_frame
	print("staging cancellation: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
