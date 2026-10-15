## Free question cameras reveal real parallel sightlines, including distant tall blockers.
extends SceneTree

var checks := 0
var bad := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scenery := Scenery.new("summer")
	var parent := Node3D.new()
	root.add_child(parent)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 2.0
	camera.far = 5000.0
	parent.add_child(camera)
	var pitch := deg_to_rad(10.0)
	var focus := Vector3(0.0,2.6,0.0)
	var free := 1.0-560.0/844.0
	var size := 140.0/free
	var offset := (1.0-free)*size*0.5/sin(pitch)
	var look := focus-Vector3.BACK*offset
	camera.size = size
	camera.position = look+Vector3(0.0,sin(pitch),-cos(pitch))*sqrt(3700.0)
	camera.look_at(look)
	var tall := building(scenery,parent,Vector3(8,40,8),Vector3(0,20,-130))
	var low := building(scenery,parent,Vector3(8,5,8),Vector3(0,2.5,-30))
	var beside := building(scenery,parent,Vector3(8,40,8),Vector3(30,20,-130))
	var behind := building(scenery,parent,Vector3(8,40,8),Vector3(0,20,30))
	var targets: Array[Vector3] = [Vector3(400,1.2,400),focus]
	scenery.update_occluders(camera,targets,0.5)
	check(scenery.occluders[0].fades.get(0,1.0)<0.26,"tall blocker beyond85m fades for a secondary target")
	check(scenery.occluders[1].fades.is_empty(),"short building below the parallel sightline stays opaque")
	check(scenery.occluders[2].fades.is_empty(),"building beside the sightline stays opaque")
	check(scenery.occluders[3].fades.is_empty(),"building beyond the target stays opaque")
	var focus_only: Array[Vector3] = [focus]
	scenery.update_occluders(camera,focus_only,0.5)
	check(scenery.occluders[1].fades.is_empty(),"optical-centre ray does not falsely fade a short foreground building")
	var sphere: Dictionary = scenery.occluders[0].spheres[0]
	var rebase := Transform3D(Basis(Vector3.UP,0.7),Vector3(60,0,-300))
	parent.transform = rebase
	var transformed: Array[Vector3] = []
	for target in targets: transformed.append(rebase*target)
	scenery.update_occluders(camera,transformed,0.5)
	check(scenery.occluders[0].fades.get(0,1.0)<0.26,"world rotation and translation retain the blocker")
	check(scenery.occluders[0].spheres[0]==sphere,"world rebase reuses the local broadphase sphere")
	check(scenery.occluders[1].fades.is_empty(),"rebased short building remains opaque")
	tall.begin(0)
	var moved := Transform3D(Basis(),Vector3(100,20,-130))
	tall.put(0,moved,Color.WHITE)
	tall.finish(0)
	scenery.update_occluders(camera,transformed,0.5)
	check(scenery.occluders[0].fades.is_empty(),"recycled blocker restores its opaque slot")
	check(scenery.occluders[0].spheres[0].pose==moved,"moved instances refresh their broadphase sphere")
	# The original perspective mode keeps its existing first-target85m policy.
	parent.transform = Transform3D()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = Vector3(0,18,-22)
	camera.look_at(Vector3(0,1,0))
	var close := building(scenery,parent,Vector3(10,12,6),Vector3(0,6,-8))
	var close_targets: Array[Vector3] = [Vector3(0,1.2,0)]
	scenery.update_occluders(camera,close_targets,0.5)
	check(scenery.occluders[-1].fades.get(0,1.0)<0.26,"perspective blockers retain their original fading")
	var empty: Array[Vector3] = []
	scenery.update_occluders(camera,empty,0.5)
	check(scenery.occluders[-1].fades.is_empty(),"empty target list restores faded buildings")
	# Keep each pool referenced while its metadata retains a weak reference.
	check(low!=null and beside!=null and behind!=null and close!=null,"fixture pools stay alive")
	parent.queue_free()
	await process_frame
	print("question camera occlusion: ",checks," checks, ",bad," failures")
	quit(1 if bad else 0)

func building(scenery: Scenery, parent: Node3D, size: Vector3, at: Vector3) -> Scenery.Pool:
	var mesh := BoxMesh.new()
	mesh.size = size
	var pool := Scenery.Pool.new(parent,mesh,scenery.material,1,1,false)
	scenery.register_building_pool(pool.node)
	pool.begin(0)
	pool.put(0,Transform3D(Basis(),at),Color.WHITE)
	pool.finish(0)
	return pool
