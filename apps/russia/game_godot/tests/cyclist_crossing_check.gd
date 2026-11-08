## Ticket 21/8: the saved bicycle route crosses verges beside a yard entrance.
extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scenery := Scenery.new("autumn")
	var sit := Situation.load_scene("ticket_21_8", scenery)
	root.add_child(sit)
	var junction := Junction.new(sit)
	junction.released = true
	junction.motion_ground = func(p, _kind): return sit.road_at(p) or sit.pavement_at(p)
	var cyclist: Junction.Motion
	for motion in junction.motions:
		if motion.type == "cyclist": cyclist = motion
	cyclist.active = true
	cyclist.waits_for_player = false
	cyclist.dependencies = []
	var player := {"p": Vector3(-20, 0, -20), "yaw": 0.0, "hw": 0.86, "hl": 1.75}
	for i in 600:
		junction.update_actors(1.0 / 60.0, player, 0.0)
	var crossed := cyclist.distance > 30.0 and cyclist.cleared
	# A generated tail must still stop on unsupported terrain.
	cyclist.path = Junction.Path.new([[1000, 0], [1000, 30]])
	cyclist.exported_length = 1.0
	cyclist.distance = 2.0
	cyclist.node.position = cyclist.path.point_at(2.0)
	cyclist.done = false
	cyclist.stays_put = false
	cyclist.active = true
	junction.update_actors(1.0 / 60.0, player, 0.0)
	var tail_stopped := cyclist.distance == 2.0 and cyclist.speed == 0.0
	sit.free()
	print("Cyclist crosses saved yard route: ", crossed, "; unsupported generated tail stops: ", tail_stopped)
	quit(0 if crossed and tail_stopped else 1)
