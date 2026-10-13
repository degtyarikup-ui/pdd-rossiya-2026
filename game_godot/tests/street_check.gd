## Headless check of the ring street (scripts/street.gd, world.gd _half_at):
##   godot --headless --path game_godot --script res://tests/street_check.gd
## A 4-lane street (half 8.4) runs into an exam junction whose streets begin at z = 120. Its last
## Street.TAPER metres narrow to the 2-lane approach (4.2): the asphalt of every strip is as wide as
## _half_at says, and no prop of the chunks stands on the carriageway (parked cars sit at the kerb
## by design, they are not checked). Props are recorded, not drawn: a headless run has no
## renderer to keep MultiMesh transforms. Exit status 1 on a failure.
extends SceneTree

const L := 60.0
const WIDE := 8.4


## Stands in for a Scenery.Pool: keeps the transforms that Street puts in each slot.
class RecPool:
	extends RefCounted
	var placed := {}   # ring slot -> [Transform3D]

	func begin(slot: int) -> void:
		placed[slot] = []

	func put(slot: int, xform: Transform3D, _tint := Color.WHITE) -> bool:
		placed[slot].append(xform)
		return true

	func finish(_slot: int) -> void:
		pass


func _initialize() -> void:
	var world_script = load("res://scripts/world.gd")
	var world = world_script.new()
	world.blanks = [[120.0, 300.0]]
	world.street_half = WIDE
	var scenery := Scenery.new("summer")
	var root := Node3D.new()
	get_root().add_child(root)
	var street := Street.new(root, scenery, L, 4)
	for prop in street.pools:
		street.pools[prop] = RecPool.new()
	var half_at := Callable(world, "_half_at")
	var bad := 0
	print("half at 30 m: ", snappedf(world._half_at(30.0), 0.01), ", 60 m: ", snappedf(world._half_at(60.0), 0.01),
		", 90 m: ", snappedf(world._half_at(90.0), 0.01), ", 119 m: ", snappedf(world._half_at(119.0), 0.01),
		", 120 m: ", snappedf(world._half_at(120.0), 0.01))
	# Chunk 0 is z 0..60 (ring, 4-lane), chunk 1 is z 60..120 (the taper), chunk 2 is the junction.
	var taper := street.build_chunk(0, 1, false, half_at)
	street.build_chunk(1, 2, true, half_at)
	var ring := street.build_chunk(2, 0, false, half_at)
	bad += _check_asphalt(ring, 0, half_at, "chunk 0 (ring)")
	bad += _check_asphalt(taper, 1, half_at, "chunk 1 (taper)")
	bad += _check_props(street, 0, half_at, "chunk 1 (taper)")
	bad += _check_props(street, 2, half_at, "chunk 0 (ring)")
	print("failures: ", bad)
	world.free()
	quit(1 if bad > 0 else 0)


## The carriageway's edge is the asphalt at ground level (y 0). Its widest point per strip must be
## the half-width of that strip.
func _check_asphalt(mesh: ArrayMesh, index: int, half_at: Callable, label: String) -> int:
	var bad := 0
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var widest := { }
	for v in verts:
		if absf(v.y) < 0.001:
			var z := snappedf(v.z, 0.01)
			widest[z] = maxf(widest.get(z, 0.0), absf(v.x))
	var zs := widest.keys()
	zs.sort()
	for z in zs:
		var world_z: float = index * L + z
		var want: float = half_at.call(world_z)
		var got: float = widest[z]
		if absf(got - want) > 0.02:
			bad += 1
			print("  ", label, " asphalt at z ", world_z, ": ", snappedf(got, 0.01), " m, expected ", snappedf(want, 0.01))
	print(label, ": asphalt cross-sections ", zs.size(), ", half-width from ", snappedf(widest[zs[0]], 0.01),
		" (z ", snappedf(index * L + zs[0], 0.01), ") to ", snappedf(widest[zs[zs.size() - 1]], 0.01),
		" (z ", snappedf(index * L + zs[zs.size() - 1], 0.01), ")")
	return bad


## Every recorded prop of a slot (not the parked cars) must stand off the carriageway.
func _check_props(street: Street, slot: int, half_at: Callable, label: String) -> int:
	var bad := 0
	var checked := 0
	for prop in street.pools:
		for t: Transform3D in (street.pools[prop] as RecPool).placed.get(slot, []):
			var x := absf(t.origin.x)
			var half: float = half_at.call(t.origin.z)
			checked += 1
			if x < half - 0.01:
				bad += 1
				print("  ", label, " ", prop, " on the road at x ", snappedf(t.origin.x, 0.01), " z ", snappedf(t.origin.z, 0.01), " (half ", snappedf(half, 0.01), ")")
	print(label, ": props checked ", checked, ", on the road ", bad)
	return bad
