extends SceneTree
func _initialize() -> void:
	var folder := OS.get_cmdline_user_args()[0]
	for code in SignFace._number_data.specs:
		for value in [1, 20, 40, 90, 130, 150] + ([3.5,500] if code not in ["3.24","3.25","4.6","4.7","6.2"] else []):
			var svg := SignFace.number_svg(code,value)
			var actual := Image.new()
			var expected := Image.new()
			assert(actual.load_svg_from_string(svg,2.0)==OK)
			assert(expected.load_svg_from_string(FileAccess.get_file_as_string(folder+"/"+code+"_"+str(value)+".svg"),2.0)==OK)
			assert(actual.get_data()==expected.get_data(),"Editor and game rasterize the same digit paths: "+code+" "+str(value))
			var tex := SignFace.number_texture(code,value)
			assert(tex.get_meta("sign_code")==code)
			assert(tex.get_meta("canvas_size")==Vector2(SignFace._number_data.specs[code].size[0],SignFace._number_data.specs[code].size[1]))
	var sign := RoadBuild.sign_node("3.24","","8.16",[],[],true,{"number":40,"secondSign":{"code":"3.25","number":90}})
	var count := 0
	for node in sign.find_children("*","MeshInstance3D",true,false):
		if node.material_override is ShaderMaterial and node.material_override.get_shader_parameter("picture").get_meta("sign_code", "") in ["3.24","3.25"]:
			assert(node.material_override.get_shader_parameter("outline_shape")==1,"Numeric speed faces retain circular silhouettes")
			count+=1
	assert(count==2)
	sign.free()
	print("Numeric speed signs runtime PASS: matching vector pixels, circular faces, shared mounting and caching")
	quit()
