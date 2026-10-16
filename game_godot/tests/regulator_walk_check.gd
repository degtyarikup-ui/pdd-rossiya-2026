## All regulator crowds use articulated gait driven by travelled distance, including pause.
extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var junction := RegulatorJunction.new()
 root.add_child(junction)
 junction.set_process(false)
 check(not junction.walkers_data.is_empty(), "regulator contains pedestrians")
 for i in junction.walkers_data.size():
  var crowd := junction.walker_crowds[i]
  var before := crowd.get_instance_custom_data(0)
  var origin := crowd.get_instance_transform(0).origin
  var w: Dictionary = junction.walkers_data[i]
  var phase: float = w.walk_phase
  check(floorf(before.a * 0.5) == 15.0, "walker %d has full leg/arm articulation" % i)
  junction._update_walkers(0.1)
  var after := crowd.get_instance_custom_data(0)
  check(not is_equal_approx(before.a, after.a), "walker %d advances the rendered gait" % i)
  check(crowd.get_instance_transform(0).origin.distance_to(origin) > 0.0, "walker %d actually walks" % i)
  check(is_equal_approx(w.walk_phase, fposmod(phase + w.spd * 0.1 * 3.5, TAU)), "walker %d stride follows distance" % i)
  check(Vector3(before.r,before.g,before.b).is_equal_approx(Vector3(after.r,after.g,after.b)), "walker %d retains clothing colour" % i)
 var frozen := junction.walker_crowds[0].get_instance_custom_data(0)
 for frame in 5: await process_frame
 check(junction.walker_crowds[0].get_instance_custom_data(0) == frozen, "paused junction freezes gait as well as position")
 junction.queue_free()
 await process_frame
 print("Regulator walking: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
