## Whole-building fading retains sparse batching, restores opaque slots and survives ring recycling.
extends SceneTree
# MultiMesh buffer round trips require the real renderer; the native run is the verification.
var bad:=0
var checks:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: bad+=1;print("FAIL ",label)
func _initialize() -> void:
	if DisplayServer.get_name()=="headless":
		print("building fading visual test: run without --headless (native renderer verified)")
		quit(0);return
	call_deferred("run")
func run() -> void:
	var scenery:=Scenery.new("winter")
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(10,12,6)
	var parent:=Node3D.new()
	root.add_child(parent)
	var camera:=Camera3D.new()
	parent.add_child(camera)
	camera.position=Vector3(0,18,-22)
	camera.look_at(Vector3(0,1,0))
	var pool:=Scenery.Pool.new(parent,mesh,scenery.material,2,1,false)
	scenery.register_building_pool(pool.node)
	pool.begin(0)
	var original:=Transform3D(Basis(),Vector3(0,6,-8))
	pool.put(0,original,Color(1,1,1,1))
	pool.finish(0)
	var targets: Array[Vector3]=[Vector3(0,1.2,0)]
	scenery.update_occluders(camera,targets,0.5)
	var state: Dictionary=scenery.occluders[0]

	check(state.fade_node.multimesh.instance_count==8 and state.fade_node.multimesh.visible_instance_count==1,"dense sparse batch renders exactly one faded building")
	check(state.fades.size()==1,"only blocking instance faded")
	check(absf(state.fades[0]-0.25)<0.001,"whole building opacity0.25")
	check(pool.multi.get_instance_transform(0).origin.y < -10,"opaque slot moved out of view")
	check(state.fade_node.multimesh.get_instance_transform(0).is_equal_approx(original),"transparent slot retains actual transform")
	check(absf(state.fade_node.multimesh.get_instance_custom_data(0).a-1.125)<0.001,"winter snow flag and opacity packed independently")
	var ghost:=Node3D.new()
	parent.add_child(ghost)
	pool.snapshot(ghost)
	var copy:=ghost.get_child(0) as MultiMeshInstance3D
	check(copy.multimesh.instance_count==1,"snapshot compacts hidden slots")
	check(copy.multimesh.get_instance_transform(0).is_equal_approx(original),"snapshot retains faded building")
	ghost.rotation.y=0.7
	check((ghost.global_transform*copy.multimesh.get_instance_transform(0)).origin.is_equal_approx(ghost.global_transform*original.origin),"rebased snapshot retains building")
	pool.begin(0)
	var replacement:=Transform3D(Basis(),Vector3(100,6,100))
	pool.put(0,replacement,Color.WHITE)
	pool.finish(0)
	check(state.fades.is_empty() and state.originals.is_empty(),"recycle clears all cached fade state")
	check(state.fade_node.multimesh.visible_instance_count==0 and not state.fade_node.visible,"recycle hides old transparent building immediately")
	scenery.update_occluders(camera,targets,0.5)
	check(pool.multi.get_instance_transform(0).is_equal_approx(replacement),"replacement remains opaque")
	pool.begin(0)
	pool.finish(0)
	check(pool.multi.get_instance_transform(0).origin.y < -10,"unused recycled slot hidden")
	parent.queue_free()
	await process_frame
	print("building fading: ",checks," checks, ",bad," failures")
	quit(1 if bad else 0)
