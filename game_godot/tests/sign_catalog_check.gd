## Full app vector catalogue must import, retain silhouettes and build actual roadside signs.
extends SceneTree

func visible_face(face: MeshInstance3D) -> Vector2:
	var outline: Vector4 = (face.material_override as ShaderMaterial).get_shader_parameter("outline_rect")
	return (face.mesh as QuadMesh).size * Vector2(outline.z, outline.w)

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://signs/catalog.json"))
	assert(catalog.size() == 312)
	var panels := {}
	for code in catalog:
		var tex := SignFace.texture(code)
		assert(tex != null, code + ": imported texture exists")
		var image := tex.get_image()
		assert(image != null and image.get_used_rect().has_area(), code + ": vector has visible artwork")
		var sign := RoadBuild.sign_node(code)
		assert(sign != null and sign.get_node_or_null("sign_board/face_top") != null, code + ": actual game sign builds")
		sign.free()
		if code.begins_with("2.3.") and code != "2.3.1":
			panels[hash(image.get_data())] = true
	assert(panels.size() == 6, "Six adjoining-road signs are distinct individual panels, not the entire sheet")
	assert(SignFace.outline_shape("2.6") == 1)
	assert(SignFace.outline_shape("4.8.1") == 0)
	assert(SignFace.outline_shape("1.34.1") == 3)
	var pair := RoadBuild.sign_node("3.28", "", "8.2.2")
	assert(pair.get_node("sign_board").get_child_count() == 2, "Parking sign and zone-of-effect plate share a support")
	pair.free()
	for code in catalog:
		if not code.begins_with("8."): continue
		for second in [false, true]:
			var settings := {"secondSign": {"code": code}} if second else {}
			var mounted := RoadBuild.sign_node("3.28", "", "" if second else code, [], [], true, settings)
			var board := mounted.get_node("sign_board")
			var top := visible_face(board.get_node("face_top"))
			var plate := visible_face(board.get_child(0))
			assert(plate.x <= top.x * .801 and plate.y <= top.y * .951,
				code + ": supplementary plate stays smaller than the main sign in both mounting modes")
			mounted.free()
	print("Sign catalogue: all 312 textures and actual sign models, distinct panels and attached plates PASS")
	quit(0)
