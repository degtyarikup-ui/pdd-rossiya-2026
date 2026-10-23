## Cancelling a staged prop loop must unwind before its owner/rendering world is destroyed.
extends SceneTree

class ClosingOwner extends Node3D:
	var closing := false
	func staging_cancelled() -> bool: return closing

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func prepare(scene: Situation, scenery: Scenery, done: Array) -> void:
	await scene._place_props(scenery, self)
	done[0] = true

func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/ticket_26_13/scene.json"))
	var groups := {}
	var trees := false
	for prop in source.props:
		groups[prop.prop] = true
		trees = trees or str(prop.prop).begins_with("trees/")
	var expected_nodes := groups.size() + (1 if trees else 0)
	for cancellation in ["none", "owner", "host"]:
		var owner := ClosingOwner.new()
		root.add_child(owner)
		var scene := Situation.new()
		scene.data = source.duplicate(true)
		scene._staging_owner = weakref(owner)
		owner.add_child(scene)
		var created := [0]
		scene.child_entered_tree.connect(func(_child): created[0] += 1)
		var scenery: Scenery = Scenery.new("autumn")
		var retained: WeakRef = weakref(scenery)
		var done := [false]
		prepare(scene, scenery, done)
		await process_frame
		expect(created[0] == 1 and not done[0], cancellation + ": first real prop group yields to the frame")
		var at_cancel := int(created[0])
		if cancellation == "owner": owner.closing = true
		elif cancellation == "host": root.set_meta(Host.EXIT_META, 1)
		# The suspended builder is now the only owner of its Scenery object.
		scenery = null
		for frame in 3: await process_frame
		if cancellation != "none":
			expect(done[0], cancellation + ": nested builder unwinds at its next frame boundary")
			expect(created[0] == at_cancel, cancellation + ": no rendering instances are constructed after cancellation")
			expect(retained.get_ref() == null, cancellation + ": cancelled coroutine releases its scenery immediately")
		for frame in expected_nodes + 4:
			if done[0]: break
			await process_frame
		expect(done[0], cancellation + ": caller resumes without a lost function state")
		if cancellation == "none":
			expect(created[0] == expected_nodes, "normal staging preserves every prop group and the contact-shadow batch")
			expect(JSON.stringify(scene.data) == JSON.stringify(source), "normal staging preserves authored scene data")
			expect(retained.get_ref() == null, "normal completed builder releases its scenery argument")
		root.remove_meta(Host.EXIT_META)
		owner.queue_free()
		for frame in 4: await process_frame
	print("props cancellation: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
