## Run composition, randomness and debug entry points, checked against the actual catalogue.
## godot --headless --path game_godot --script res://tests/parking_run_check.gd
extends SceneTree

var passed := 0
var failed := 0
var catalogue: Array[Dictionary] = []


func _init() -> void:
	for i in ParkingLevels.COUNT: catalogue.append(ParkingLevels.build(i))
	_check_pools()
	var scene := Parking.new()
	_check_random_runs(scene)
	_check_debug_runs(scene)
	scene.free()
	print("parking_run_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(description: String, ok: bool) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL: " + description)


func _category(index: int) -> int:
	var level := catalogue[index]
	return 2 if level.search else (1 if level.night else 0)


func _counts(drawn: Array[int]) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for index in drawn: counts[_category(index)] += 1
	return counts


func _unique_valid(drawn: Array[int]) -> bool:
	var seen := {}
	for index in drawn:
		if index < 0 or index >= ParkingLevels.COUNT or seen.has(index): return false
		seen[index] = true
	return true


func _prefix_order(drawn: Array[int]) -> bool:
	for slot in mini(5, drawn.size()):
		var category := 0 if slot < 3 else slot - 2
		if _category(drawn[slot]) != category: return false
	return true


func _check_pools() -> void:
	var all: Array[int] = []
	for i in catalogue.size(): all.append(i)
	_check("catalogue contains 15 daytime, 5 night and 5 search locations", _counts(all) == [15, 5, 5])
	for i in catalogue.size():
		_check("static pool metadata agrees with built location %d" % i,
			bool(catalogue[i].search) == (i >= ParkingLocations.GUIDED)
			and bool(catalogue[i].night) == (ParkingLocations.IDS[i] in ParkingNightLayout.LOCATIONS))


func _check_random_runs(scene: Parking) -> void:
	# A reproducible large sample catches an excluded location, fixed ordering or a cycling
	# shortlist. Broad distribution bounds deliberately avoid fragile statistical thresholds.
	seed(461203)
	var appearances: Array[int] = []
	appearances.resize(ParkingLevels.COUNT)
	appearances.fill(0)
	var positions: Array = [{}, {}, {}, {}, {}]
	var sequences := {}
	var valid := true
	for attempt in 1000:
		var drawn := scene._draw_levels()
		valid = valid and drawn.size() == 5 and _unique_valid(drawn) and _prefix_order(drawn)
		sequences[str(drawn)] = true
		for slot in drawn.size():
			appearances[drawn[slot]] += 1
			positions[slot][drawn[slot]] = true
	_check("1000 normal runs have exactly five distinct levels in day/day/day/night/search order", valid)
	_check("restarts produce a broad random selection rather than a fixed or cycling shortlist", sequences.size() > 850)
	for i in catalogue.size():
		_check("location %d remains reachable with a balanced random frequency (%d/1000)" % [i, appearances[i]],
			appearances[i] > 120 and appearances[i] < 300)
		if _category(i) == 0:
			for slot in 3:
				_check("day location %d can appear in ordinary slot %d" % [i, slot + 1], positions[slot].has(i))
	_check("all five night locations can appear in slot four", positions[3].size() == 5)
	_check("all five independent locations can appear in slot five", positions[4].size() == 5)
	print("normal run sample: %d unique sequences, per-location appearances %s" % [sequences.size(), appearances])


func _check_debug_runs(scene: Parking) -> void:
	for requested: int in [-7, 0, 1, 2, 3, 4, 5, 6, 12, 25, 40]:
		scene.run_size = requested
		var count := clampi(requested, 1, ParkingLevels.COUNT)
		for forced in range(-1, ParkingLevels.COUNT):
			scene._forced_level = forced
			var drawn := scene._draw_levels()
			var description := "run_size=%d forced=%d" % [requested, forced]
			_check(description + ": requested bounded length and no repeats", drawn.size() == count and _unique_valid(drawn))
			if forced >= 0:
				_check(description + ": forced level starts exactly once", drawn[0] == forced and drawn.count(forced) == 1)
				if count >= 5:
					_check(description + ": forcing replaces a level in its own category", _counts(drawn.slice(0, 5)) == [3, 1, 1])
			else:
				_check(description + ": short runs are prefixes of the standard order", _prefix_order(drawn))
			if count == ParkingLevels.COUNT:
				var sorted := drawn.duplicate()
				sorted.sort()
				_check(description + ": all-location autoplay still covers the entire catalogue", sorted == range(ParkingLevels.COUNT))
	scene._play_all = true
	scene.run_size = 1 # --all intentionally overrides the size used by a test fixture.
	for forced in range(-1, ParkingLevels.COUNT):
		scene._forced_level = forced
		_check("--all with --level=%d retains catalogue order" % forced,
			scene._draw_levels() == range(maxi(0, forced), ParkingLevels.COUNT))
