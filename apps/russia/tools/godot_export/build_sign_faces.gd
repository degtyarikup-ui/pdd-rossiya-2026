## Re-rasterize the authoritative SVG paths, retaining their original mounting slots.
## godot --headless --path game_godot --script ../tools/godot_export/build_sign_faces.gd
extends SceneTree

func _initialize() -> void:
	var regions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://signs/face_regions.json"))
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://signs/catalog.json"))
	var layout:={}
	for file in DirAccess.get_files_at("res://signs"):
		if not file.ends_with(".svg"):continue
		var path:="res://signs/"+file
		var svg:=FileAccess.get_file_as_string(path)
		var original:=Image.new()
		assert(original.load_svg_from_string(svg)==OK)
		var dense:=Image.new()
		assert(dense.load_svg_from_string(svg,4.0)==OK)
		var code:=file.trim_suffix(".svg")
		var crop:=Rect2(Vector2.ZERO,Vector2(original.get_size()))
		if regions.has(code):
			var r: Array=regions[code]
			crop=Rect2(r[0],r[1],r[2],r[3])
		var used:=dense.get_region(Rect2i(crop.position*4,crop.size*4)).get_used_rect()
		var visible:=Rect2(Vector2(used.position)/4,Vector2(used.size)/4)
		var scale:=256.0/maxf(visible.size.x,visible.size.y)
		layout[code]={"sourceSize":[original.get_width(),original.get_height()],
			"outline":[visible.position.x/crop.size.x,visible.position.y/crop.size.y,visible.size.x/crop.size.x,visible.size.y/crop.size.y],
			"scale":scale}
		# Silhouette fitted by export_sign_catalog.py: the contour the shader cuts the face with.
		var face: Dictionary=catalog.get(code,{}).get("face",{})
		if not face.is_empty():
			layout[code].shape=int(face.shape)
			layout[code].radius=float(face.radius)
		var config:=ConfigFile.new()
		assert(config.load(path+".import")==OK)
		config.set_value("params","svg/scale",scale)
		config.set_value("params","mipmaps/generate",true)
		assert(config.save(path+".import")==OK)
	var out:=FileAccess.open("res://signs/face_layout.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(layout,"\t",true)+"\n")
	print("Sign face imports: ",layout.size()," SVGs, 256-pixel visible panels, mipmaps, original slots preserved")
	quit()
