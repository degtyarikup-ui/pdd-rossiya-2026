## A previous junction can retire while the next junction warms its seams.
extends SceneTree

class TestWorld extends "res://scripts/world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _notification(_what: int) -> void: pass

class RetiringSituation extends Situation:
	var calls := [0]
	var retire_after := 1
	func warm_bindings(_bindings: Array, _scenery: Scenery, frames: SceneTree) -> void:
		calls[0] += 1
		# Retiring from an ordinary frame while the builder is suspended is legal.
		await frames.process_frame
		if calls[0] == retire_after:
			get_parent().current = {}
			queue_free()

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func run() -> void:
	for retire_after in [1, 2]:
		await retiring_previous(retire_after)
	print("staging retirement: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func retiring_previous(retire_after: int) -> void:
	var world := TestWorld.new()
	world.scenery = Scenery.new("autumn")
	root.add_child(world)
	var previous := RetiringSituation.new()
	previous.id = "ticket_1_13"
	previous.network = RoadNetwork.load_scene(previous.id)
	previous.retire_after = retire_after
	world.add_child(previous)
	world.current = {"sit": previous}
	world.staging = true
	var calls := previous.calls
	world._build_staged("ticket_12_13")
	var deadline := Time.get_ticks_msec() + 10000
	while world.staging and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(calls[0] == retire_after, "retired previous junction receives no further warmup calls (calls=%d, retire_after=%d)" % [calls[0], retire_after])
	expect(not world.staging, "next junction finishes staging after previous junction retires")
	expect(not is_instance_valid(previous), "previous junction is actually freed during preparation")
	expect(is_instance_valid(world.staged_sit), "retiring previous junction preserves prepared next junction")
	if is_instance_valid(world.staged_sit):
		expect(world.staged_sit.id == "ticket_12_13", "prepared next question keeps its identity")
	world._exiting = true
	world.current = {}
	await process_frame
	await process_frame
	world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.12).timeout
	expect(Situation._tasks.is_empty(), "staging leaves no background workers")
