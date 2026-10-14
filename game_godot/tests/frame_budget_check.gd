## Mobile quality responds to sustained work, while loads and pauses cannot lower it.
extends SceneTree
const Budget := preload("res://scripts/frame_budget.gd")
var checks := 0
var failed := 0

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failed += 1; print("FAIL ", text)

func window(b, delta: float, eligible := true, target := 60) -> Dictionary:
	var result := {}
	for i in ceili(4.1 / delta):
		var update: Dictionary = b.sample(delta, eligible, target)
		if not update.is_empty(): result = update
	return result

func _initialize() -> void:
	var b = Budget.new()
	b.reset(1.0, true, true)
	expect(window(b, 1.0/60.0).is_empty(), "stable 60 FPS keeps full detail")
	expect(window(b, 1.0/30.0, false).is_empty(), "loading frames cannot downgrade")
	expect(window(b, 1.0/30.0).get("antialias") == false, "first slow window removes MSAA")
	expect(is_equal_approx(b.scale, 1.0), "MSAA is removed before lowering resolution")
	expect(window(b, 1.0/30.0).get("scale", 0.0) < 1.0, "sustained slow frames lower 3D resolution")
	for i in 10: window(b, 1.0/30.0)
	expect(is_equal_approx(b.scale, b.MIN_SCALE) and not b.shadows, "bounded scale and eventual shadow relief")
	expect(b.capped, "minimum budget eventually caps CPU-bound phones at sustainable 30 FPS")
	expect(window(b, 1.0/60.0).is_empty(), "fast interval cannot oscillate back to expensive quality")
	b.reset(0.75, false, false)
	expect(window(b, 1.0/30.0, true, 30).is_empty(), "weak tier accepts its 30 FPS budget")
	expect(not window(b, 1.0/20.0, true, 30).is_empty(), "weak tier still responds below its frame budget")
	b.reset(1.0, true, false)
	for i in 100: b.sample(0.03, true, 60)
	b.sample(0.1, false, 60)
	expect(window(b, 1.0/60.0).is_empty(), "pause separates slow history from next active interval")
	expect(Quality.initial("Apple A13 GPU", true) == "mid", "older Apple phone avoids forced high")
	expect(Quality.initial("Apple M4", false) == "high", "desktop Apple retains high")
	expect(Quality.initial("Adreno 610", true) == "low", "weak Android retains 30 FPS tier")
	expect(Quality.initial("Adreno 740", true) == "high", "strong Android starts at high and can adapt")
	print("frame budget: ", checks, " checks, ", failed, " failures")
	quit(1 if failed else 0)
