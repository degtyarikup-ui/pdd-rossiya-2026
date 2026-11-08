## Glancing a kerb at any road direction keeps the car moving along it:
##   godot --headless --path game_godot --script res://tests/kerb_angle_check.gd
## A fake world holds a 7 m wide straight road rotated by `road_yaw`; the car drives
## into its kerb at a shallow angle. Axis-aligned slide candidates used to stop it dead.
extends SceneTree

const DT := 1.0 / 60.0
var checks := 0
var failures := 0

class StraightRoad extends RefCounted:
	var yaw := 0.0
	var half := 3.5
	func road_supports(p: Vector3) -> bool:
		return absf(p.rotated(Vector3.UP, -yaw).x) <= half
	func obstacles() -> Array: return []
	func on_fault(_type: String, _key: String) -> void: pass
	func on_collision(_o) -> void: pass

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	for road_deg in [0.0, 20.0, 35.0, 50.0, 90.0, 140.0]:
		for hit_deg in [8.0, 15.0, 25.0]:
			var road := StraightRoad.new()
			road.yaw = deg_to_rad(road_deg)
			var drive := Drive.new()
			drive.world = road
			drive.assist_enabled = false
			# Start on the road's centre line, heading into the right kerb by hit_deg.
			drive.pos = Vector3.ZERO
			drive.yaw = road.yaw + deg_to_rad(hit_deg)
			drive.speed = 12.0
			drive.accelerating = true
			drive.curb_clear_time = 1.0
			var touched := -1
			for frame in 400:
				drive.integrate(DT, 12.0)
				if touched < 0 and drive.curb_clear_time == 0.0: touched = frame
				if touched >= 0 and frame >= touched + 30: break
			var label := "road %d°, hit %d°: " % [road_deg, hit_deg]
			expect(touched >= 0, label + "reaches the kerb")
			expect(drive.speed > 8.0, label + "keeps driving half a second after a graze (%.1f m/s)" % drive.speed)
			expect(drive.on_road(), label + "stays on the road")
	# An arrow held toward the edge of a road that is not along x or z (a dirt road's slanted or
	# curved side): the car rides along it like a city kerb instead of stalling into it.
	for road_deg in [0.0, 7.0, 20.0, 35.0, 140.0]:
		for side in [1.0, -1.0]:
			var road := StraightRoad.new()
			road.yaw = deg_to_rad(road_deg)
			var drive := Drive.new()
			drive.world = road
			drive.assist_enabled = false
			drive.pos = Vector3.ZERO
			drive.yaw = road.yaw
			drive.speed = 12.0
			drive.accelerating = true
			drive.curb_clear_time = 1.0
			drive.steering = side
			var slowest := INF
			var touched := false
			for frame in 240:
				drive.integrate(DT, 12.0)
				touched = touched or drive.curb_clear_time == 0.0
				if touched and frame > 120: slowest = minf(slowest, drive.speed)
			var label := "road %d°, arrow %+d held into the edge: " % [road_deg, side]
			expect(touched, label + "reaches the edge")
			expect(slowest > 4.5, label + "keeps sliding along it (slowest %.1f m/s)" % slowest)
			expect(drive.on_road(), label + "stays on the road")
	print("kerb angle: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
