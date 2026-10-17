## People budgets, shared mesh channels and all anatomical officer signal directions.
extends SceneTree

var bad := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var vertices_total := 0
	for look in Models.WALKERS:
		var path := "res://models/walkers/walker_%d.glb" % look
		var scene := (load(path) as PackedScene).instantiate()
		check(scene.find_children("*","MeshInstance3D",true,false).size() == 1,"walker %d: one mesh" % look)
		scene.free()
		var mesh := Models.mesh_of(path)
		check(mesh.get_surface_count() == 1,"walker %d: one batched surface" % look)
		var a := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var pivots: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		var colors: PackedColorArray = a[Mesh.ARRAY_COLOR]
		vertices_total += vertices.size()
		check(not indices.is_empty() and indices.size()/3 <= 260 and vertices.size() <= 480,"walker %d: indexed phone budget" % look)
		var bounds := mesh.get_aabb()
		var child := look in Models.CHILD_WALKERS
		check(absf(bounds.position.y) < .001 and (bounds.end.y > 1.2 and bounds.end.y < 1.4 if child else bounds.end.y > 1.6 and bounds.end.y < 1.85),"walker %d: ground and %s height" % [look, "child" if child else "adult"])
		check(bounds.size.x < .76 and bounds.size.z < .45,"walker %d: sidewalk collision envelope" % look)
		check(uv.size() == vertices.size() and pivots.size() == vertices.size() and colors.size() == vertices.size(),"walker %d: gait and paint channels retained" % look)
		var painted := false
		var fixed_color := false
		var left_leg := false
		var right_leg := false
		var shin := false
		var knee_seam := false
		for i in vertices.size():
			painted = painted or colors[i].a > .9
			fixed_color = fixed_color or colors[i].a < .1
			left_leg = left_leg or pivots[i].x > .2
			right_leg = right_leg or pivots[i].x < -.2
			shin = shin or (uv[i].x > .9 and uv[i].y > .28 and uv[i].y < .5)
			knee_seam = knee_seam or (absf(pivots[i].x) > .2 and uv[i].y > .28 and absf(vertices[i].y-uv[i].y) < .001 and absf(uv[i].x) < .001)
		check(painted and fixed_color and left_leg and right_leg and shin and knee_seam,"walker %d: opposed limbs and closed weighted knee seam" % look)
	check(vertices_total < 5200,"all walkers use fewer vertices than the old 7560")
	check(Models.walker_material().get_shader_parameter("articulated_walk") == true,"crowd knees enabled")
	# Unset parameters read null; the shader's default for this flag is false.
	check(Models.baked_material().get_shader_parameter("articulated_walk") != true,"traffic/officer never use knee UVs")
	var cop := RegulatorOfficer.new()
	root.add_child(cop)
	var meshes := cop.find_children("*","MeshInstance3D",true,false)
	check(meshes.size() == 3,"officer: three meshes instead of 43")
	var officer_triangles := 0
	for node: MeshInstance3D in meshes:
		check(node.mesh.get_surface_count() == 1,"officer: one surface per moving part")
		var a := node.mesh.surface_get_arrays(0)
		officer_triangles += a[Mesh.ARRAY_INDEX].size()/3
		check(node.material_override == RegulatorOfficer.officer_material(),"officer: shared cached material")
	check(officer_triangles <= 400,"officer geometry budget below old 703 triangles")
	check(cop.left_arm_pivot.position.x > 0 and cop.right_arm_pivot.position.x < 0,"officer faces +Z with anatomical right on -X")
	var expected: Array[Vector3] = [Vector3.DOWN,Vector3.LEFT,Vector3.BACK,Vector3.UP]
	for approach in 4:
		cop.set_approach(approach,false)
		for gesture in 4:
			cop.set_pose(gesture,false)
			var actual := cop.right_arm_pivot.global_basis * Vector3.DOWN
			var desired := cop.body_root.global_basis * expected[gesture]
			check(actual.is_equal_approx(desired),"officer right signal %d/%d" % [approach,gesture])
	var pedestrian := Pedestrian.new()
	pedestrian.configure(2,Color("#317ED4"))
	root.add_child(pedestrian)
	pedestrian.set_process(false)
	pedestrian.position.z = .12
	pedestrian._process(.1)
	var material := (pedestrian.get_node("model") as MeshInstance3D).material_override as ShaderMaterial
	var phase: float = material.get_shader_parameter("walk_phase")
	var amount: float = material.get_shader_parameter("walk_amount")
	check(phase > .4 and amount > .7,"ticket pedestrian gait follows travelled distance")
	pedestrian._process(.1)
	check(is_equal_approx(material.get_shader_parameter("walk_phase"),phase) and material.get_shader_parameter("walk_amount") < amount,"stationary ticket pedestrian settles without stepping")
	pedestrian.position.z += 20
	pedestrian._process(.1)
	check(is_equal_approx(material.get_shader_parameter("walk_phase"),phase),"rebase does not create a footstep jump")
	var copy := pedestrian.duplicate() as Pedestrian
	root.add_child(copy)
	check((copy.get_node("model") as MeshInstance3D).material_override != material,"duplicated ticket pedestrian gets an independent gait material")
	copy._process(.1)
	check(is_equal_approx(((copy.get_node("model") as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("walk_phase"),phase),"duplicate retains the rendered pose when stationary")
	var sit := Situation.load_scene("ticket_1_13",Scenery.new("summer"))
	var replaced := 0
	for i in sit.data.actors.size():
		if sit.data.actors[i].type == "pedestrian":
			replaced += 1
			check(sit.actors[i] is Pedestrian and sit.actors[i].scale.is_equal_approx(Situation._v(sit.data.actors[i].scale)),"ticket crossing reuses new model with authored scale")
	check(replaced == 2,"actual ticket crossing replaces both pedestrians")
	sit.free()
	copy.queue_free()
	pedestrian.queue_free()
	cop.queue_free()
	await process_frame
	print("people models: ",checks," checks, ",bad," failures; walkers ",vertices_total," vertices; officer ",officer_triangles," triangles")
	quit(1 if bad else 0)
