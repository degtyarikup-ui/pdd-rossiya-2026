## Canonical signal geometry, independent sections, original mast/main aperture anchors.
class_name TrafficSignal
extends RefCounted

static var _body: StandardMaterial3D
static var _materials := {}
static var _scenes := {}
static var _mini_bodies := {}
static var _pedestrian_scene: PackedScene
const VEHICLE := {
	"red": [Color("#FF3838"),Color("#351719")],
	"yellow": [Color("#FFD52A"),Color("#352D14")],
	"green": [Color("#36FF88"),Color("#123126")],
	"arrow": [Color("#36FF88"),Color("#123126")],
}
const TRAM := ["bottom","mid","left","right"]

static func supports(config: Dictionary) -> bool:
	if config.get("reversible"): return true
	return _arrow(config) in ["", "left", "right", "straight"]

## Saved JSON uses null when there is no supplementary section. Stringifying it
## produces "<null>", which is not a model variant. Share normalization with the
## capability check so a supported scene always selects an existing model.
static func _arrow(config: Dictionary) -> String:
	var value: Variant = config.get("arrow")
	if value == null: return ""
	var arrow := str(value)
	return "" if arrow == "none" else arrow

static func kind(config: Dictionary) -> String:
	if config.get("reversible"): return "reversible"
	if config.get("tram"): return "tram"
	var a := _arrow(config)
	if a != "": return a
	return "standard"

static func make(config: Dictionary) -> Node3D:
	var variant:=kind(config)
	var overhead: bool = config.get("mount") == "cantilever"
	var model_key := ("head_" if overhead or variant == "reversible" else "light_") + variant
	if not _scenes.has(model_key): _scenes[model_key]=load("res://models/street/traffic_%s.glb" % model_key)
	var node: Node3D=_scenes[model_key].instantiate()
	node.set_meta("traffic_signal",true)
	if variant == "reversible": node.set_meta("reversible", str(config.reversible))
	node.set_meta("arrow_active",bool(config.get("arrowActive",true)))
	if _body==null:
		_body=StandardMaterial3D.new()
		_body.vertex_color_use_as_albedo=true
		_body.roughness=.85
		_body.metallic_specular=0
	for mesh: MeshInstance3D in node.find_children("body","MeshInstance3D",true,false):
		mesh.material_override=_body
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sections: Variant = config.get("pedestrianSections", {})
	if variant not in ["tram", "reversible"] and sections is Dictionary and not sections.is_empty():
		if _pedestrian_scene == null: _pedestrian_scene = load("res://models/street/traffic_pedestrian_info.glb")
		node.add_child(_pedestrian_scene.instantiate())
		for mesh: MeshInstance3D in node.find_children("info_body_*", "MeshInstance3D", true, false):
			mesh.material_override = _body
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("pedestrian_sections", sections.duplicate())
		set_pedestrian_phase(node, true)
	set_state(node,"red",str(config.get("tram","straight")))
	if overhead or variant == "reversible": return mount_head(node, config)
	return node

## Use the same roadside cantilever as signs, with the signal facing +Z.
static func mount_head(head: Node3D, config: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.add_child(head)
	var reverse := kind(config) == "reversible"
	var info: bool = head.has_meta("pedestrian_sections")
	var min_y := 1.745 if info else 1.91 if not reverse and config.get("tram") else 2.6
	var max_y := 3.5 if reverse else 5.30 if config.get("tram") else 4.2
	if config.get("mount") == "cantilever":
		var mounting := config.duplicate()
		mounting.armSide = "left" if config.get("armSide", "left") == "right" else "right"
		RoadBuild._cantilever(root, head, max_y - min_y, mounting)
		head.position.y -= min_y
		head.position.z = 0
		var clearance := clampf(float(config.get("clearance",5.5)),5,8)
		for x in [-.46,.46] if reverse else [0.0]:
			_mount_rod(root, Vector3(head.position.x+x, clearance+max_y-min_y+.15, .09), .3, .045)
	else:
		_mount_rod(root, Vector3(0,(max_y+.1)/2,0),max_y+.1,.08)
	return root

static func _mount_rod(root: Node3D, pos: Vector3, height: float, radius: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "signal_mount_rod"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 8
	cylinder.rings = 1
	mesh.mesh = cylinder
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#7A7F87")
	mesh.material_override = steel
	mesh.position = pos
	root.add_child(mesh)

## Same source, retaining the mini-game's original mast and aperture centres.
static func make_mini(config: Dictionary) -> Node3D:
	var values:=config.duplicate()
	values.arrowActive=bool(config.get("arrowActive",false))
	var node:=make(values)
	var variant:=kind(values)
	if variant in ["tram","reversible"] or values.get("mount") == "cantilever":return node
	var body:=node.find_child("body",true,false) as MeshInstance3D
	if not _mini_bodies.has(variant):
		var arrays:=body.mesh.surface_get_arrays(0)
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL].duplicate()
		var roles: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
		for i in points.size():
			var scale:=Vector3.ONE
			if roles[i].x<1.5:
				scale.y=4.6/4.2
				points[i].y*=scale.y
			elif roles[i].x<2.5:
				scale=Vector3(.68/.65,.52/.45,.38/.4)
				points[i]=Vector3(points[i].x*scale.x,3.5+(points[i].y-3.4)*scale.y,.22+(points[i].z-.25)*scale.z)
			else:
				scale=Vector3(.56/.64,.56/.64,.34/.4)
				var side: float=-1 if variant=="left" else 1
				points[i]=Vector3(side*.62+(points[i].x-side*.70)*scale.x,2.98+(points[i].y-2.95)*scale.y,.22+(points[i].z-.25)*scale.z)
			normals[i]=(normals[i]/scale).normalized()
		arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
		var importer:=ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},_body)
		importer.generate_lods(60,25,[])
		_mini_bodies[variant]=importer.get_mesh()
	body.mesh=_mini_bodies[variant]
	for lamp: Node3D in node.find_children("lamp_*","Node3D",true,false):
		var name:=str(lamp.name)
		if name.begins_with("lamp_info_"): continue
		lamp.position=Vector3(0,4.02 if name=="lamp_red" else 3.5 if name=="lamp_yellow" else 2.98,.42)
		lamp.scale=Vector3(.20/.21,.20/.21,1)
		if name=="lamp_arrow":
			lamp.position=Vector3(-.62 if variant=="left" else .62,2.98,.40)
			lamp.scale=Vector3(.18/.21,.18/.21,1)
	var state:=str(config.get("state","red"))
	node.set_meta("mini_flashing",state=="flashing_yellow")
	set_state(node,state)
	return node

static func lens_material(name: String,lit: bool) -> ShaderMaterial:
	var key:=name+str(lit)
	if not _materials.has(key):
		var palette: Array=VEHICLE.get(name,[Color("#F0F6FF"),Color("#20252C")])
		var material:=ShaderMaterial.new()
		material.shader=preload("res://shaders/traffic_lens.gdshader")
		material.set_shader_parameter("lamp_colour",palette[0])
		material.set_shader_parameter("dark_colour",palette[1])
		material.set_shader_parameter("lit",lit)
		_materials[key]=material
	return _materials[key]

static func in_assembly(root: Node3D) -> Node3D:
	if root.has_meta("traffic_signal"): return root
	for child: Node3D in root.find_children("*","Node3D",true,false):
		if child.has_meta("traffic_signal"): return child
	return null

static func set_state(node: Node3D,state: String,tram: String="straight",flash_on := true) -> void:
	var shared := in_assembly(node)
	if shared != null and shared.has_meta("reversible"):
		set_reversible_state(shared, str(shared.get_meta("reversible")))
		return
	if tram not in ["straight","left","right","stop","all","off"]: tram="straight"
	for lamp: Node3D in node.find_children("lamp_*","Node3D",true,false):
		var name:=str(lamp.name).trim_prefix("lamp_")
		if name.begins_with("info_"): continue
		var on:=false
		if name.begins_with("tram_"):
			var role:=name.trim_prefix("tram_")
			on=(role in ["bottom","mid"] if tram=="straight" else role in ["bottom","left"] if tram=="left" else role in ["bottom","right"] if tram=="right" else role!="bottom" if tram=="stop" else tram=="all")
		else:
			if name == "arrow":
				on = bool(node.get_meta("arrow_active", true))
			elif state == name:
				on = true
			elif state == "flashing_yellow" and name == "yellow":
				on = flash_on
			elif state == "flashing_green" and name == "green":
				on = flash_on
			elif state == "red_yellow" and (name == "red" or name == "yellow"):
				on = true
			else:
				on = false
		for aperture: MeshInstance3D in lamp.find_children("aperture_*","MeshInstance3D",true,false):
			aperture.material_override=lens_material(name,on)
			aperture.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not lamp.has_meta("halo"):
			var palette: Array=VEHICLE.get(name,[Color("#F0F6FF")])
			var halo:=Glow.signal_halo(palette[0],.9 if name.begins_with("tram_") else 1.15,true)
			# A sideways supplementary aperture uses its arrow glyph, without round bloom.
			if name=="arrow": halo.visible=false
			lamp.add_child(halo)
			lamp.set_meta("halo",halo)
		(lamp.get_meta("halo") as Node3D).visible=on and name!="arrow"

## Lane controls are authored per pole and do not join the junction's red/green cycle.
static func set_reversible_state(node: Node3D, state: String) -> void:
	node.set_meta("reversible", state)
	for lamp: Node3D in node.find_children("lamp_reverse_*","Node3D",true,false):
		var role := str(lamp.name).trim_prefix("lamp_reverse_")
		lamp.visible = role == "red" or role == state or (role == "green" and not state.begins_with("yellow_"))
		var colour := "yellow" if role.begins_with("yellow_") else role
		for aperture: MeshInstance3D in lamp.find_children("aperture_*","MeshInstance3D",true,false):
			aperture.material_override = lens_material(colour, role == state)
			aperture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Independent white information panels: never substitute for a main or green arrow signal.
static func set_pedestrian_phase(node: Node3D, phase: bool) -> void:
	var sections: Dictionary = node.get_meta("pedestrian_sections", {})
	for side in ["left", "right"]:
		var mode: String = str(sections.get(side, ""))
		var present: bool = mode in ["off", "on", "flashing"]
		var body := node.find_child("info_body_" + side, true, false) as Node3D
		var lamp := node.find_child("lamp_info_" + side, true, false) as Node3D
		if body: body.visible = present
		if lamp == null: continue
		lamp.visible = present
		var on: bool = mode == "on" or (mode == "flashing" and phase)
		for aperture: MeshInstance3D in lamp.find_children("aperture_*", "MeshInstance3D", true, false):
			aperture.material_override = lens_material("info", on)
			aperture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
