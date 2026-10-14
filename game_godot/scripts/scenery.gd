## Scenery: buildings rebuilt by tools/godot_export/build_buildings.py;
## trees/street props by build_environment.py, retaining original local envelopes. Props in
## scenery/<group>/<name>.glb, detail maps in textures/detail/<kind>.png,
## sizes / texture params / season palettes in scenery/index.json.
class_name Scenery
extends RefCounted

## How much the detail map shows, per kind. The painted maps vary by only about 3 %, which
## reads as flat colour on a phone: the road and the ground get a clearly visible grain.
## The live value is the "gain" field of scenery/index.json (the network editor edits it);
## this table is only the fallback for a texture that has none.
const GAIN := { "asphalt": 4.0, "pavement": 3.5, "gravel": 2.5, "ballast": 2.5, "sleeper": 2.5,
	"grass": 1.3, "leaves": 1.0, "bark": 1.0, "plaster": 1.6, "brick": 1.6, "wood": 1.4, "deck": 1.6,
	"roofTile": 1.4, "roofFlat": 1.3, "metal": 1.3 }

var index: Dictionary
var layers: Array = []            # kind names, layer i -> kind
var kinds := {}                   # kind -> params (period, macro ...)
var material: ShaderMaterial
var occluder_material: ShaderMaterial
var building_material: ShaderMaterial
var occluders: Array[Dictionary] = []
var season: Dictionary


func _init(season_name: String) -> void:
	index = JSON.parse_string(FileAccess.get_file_as_string("res://scenery/index.json"))
	season = index.seasons[season_name]
	var images: Array[Image] = []
	var macro := PackedFloat32Array()
	var macro_scale := PackedFloat32Array()
	var gains := PackedFloat32Array()
	var periods := PackedFloat32Array()
	var detail_texels := PackedFloat32Array()
	for t in index.textures:
		layers.append(t.kind)
		kinds[t.kind] = t
		periods.append(float(t.period))
		# Window frames are broad architectural features, not 256-pixel grain.
		# Keep them legible until the entire window is only a few screen pixels.
		detail_texels.append(16.0 if t.kind in ["window", "door"] else 256.0)
		gains.append(t.get("gain", GAIN.get(t.kind, 1.0)))
		var img: Image = (load("res://textures/detail/%s.png" % t.kind) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		images.append(img)
		macro.append(t.macro)
		macro_scale.append(t.macroScale)
	while macro.size() < 24:
		macro.append(0.0)
		macro_scale.append(1.0)
		gains.append(1.0)
		periods.append(1.0)
		detail_texels.append(256.0)
	var array := Texture2DArray.new()
	array.create_from_images(images)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/scenery.gdshader")
	material.set_shader_parameter("detail", array)
	material.set_shader_parameter("macro", macro)
	material.set_shader_parameter("macro_scale", macro_scale)
	material.set_shader_parameter("gain", gains)
	material.set_shader_parameter("texture_periods", periods)
	material.set_shader_parameter("detail_texels", detail_texels)
	occluder_material = material
	building_material = material.duplicate()
	building_material.shader = load("res://shaders/buildings.gdshader")


## A procedural surface on the same metre grid and with the same detail maps as the street.
func surface_material(kind: String, colour: Color, frame := Transform3D()) -> ShaderMaterial:
	var mat := material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("world_uv", true)
	mat.set_shader_parameter("surface_frame", frame)
	mat.set_shader_parameter("surface_layer", layer_of(kind))
	mat.set_shader_parameter("texture_period", kinds[kind].period)
	mat.set_shader_parameter("surface_colour", Vector3(colour.r, colour.g, colour.b))
	return mat


func layer_of(kind: String) -> int:
	return layers.find(kind) + 1


func size_of(prop: String) -> Vector3:
	var s: Array = index.props[prop].size
	return Vector3(s[0], s[1], s[2])


func color(key: String, i := 0) -> Color:
	var v = season[key]
	return Color(v[i % v.size()] if v is Array else v)


## Copies of one prop drawn by one MultiMesh, split into per-chunk ranges:
## ring slot s owns instances [s * per_chunk, (s + 1) * per_chunk).
class Pool:
	# Logical slots remain chunk * per_chunk + offset, including unused slots.
	# Only the node's packed active prefix is submitted to the renderer.
	var multi: MultiMesh
	var render_multi: MultiMesh
	var per_chunk: int
	var used := {}
	var node: MultiMeshInstance3D
	var transforms: Array[Transform3D] = []
	var tints: Array[Color] = []
	var render_slots: Array[int] = []
	var render_index := {}
	var render_transforms: Array[Transform3D] = []
	var render_tints: Array[Color] = []

	func _init(parent: Node, mesh: Mesh, mat: Material, chunks: int, cap: int, shadows: bool) -> void:
		per_chunk = cap
		multi = _mesh(mesh, chunks * cap)
		render_multi = _mesh(mesh, chunks * cap)
		render_multi.visible_instance_count = 0
		for i in multi.instance_count:
			transforms.append(HIDDEN)
			tints.append(Color.WHITE)
			render_transforms.append(HIDDEN)
			render_tints.append(Color.WHITE)
		node = MultiMeshInstance3D.new()
		node.multimesh = render_multi
		node.set_meta("source_pool", weakref(self))
		node.set_meta("render_slots", render_slots)
		node.set_meta("instance_transforms", render_transforms)
		node.set_meta("instance_tints", render_tints)
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Scenery.sync_pool_bounds(node)
		parent.add_child(node)

	static func _mesh(mesh: Mesh, capacity: int) -> MultiMesh:
		var result := MultiMesh.new()
		result.transform_format = MultiMesh.TRANSFORM_3D
		result.use_colors = true
		result.use_custom_data = true
		result.mesh = mesh
		result.instance_count = capacity
		for i in capacity:
			result.set_instance_color(i, Color.WHITE)
			result.set_instance_transform(i, HIDDEN)
		return result

	static var HIDDEN := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3(0, -50, 0))

	## Frozen copies use the logical original pose, including faded buildings.
	func snapshot(parent: Node3D) -> void:
		var copy := MultiMeshInstance3D.new()
		copy.material_override = node.material_override
		copy.cast_shadow = node.cast_shadow
		var visible: Array[int] = []
		for i in transforms.size():
			if transforms[i].origin.y > -10.0: visible.append(i)
		var frozen := _mesh(multi.mesh, visible.size())
		var frozen_transforms: Array[Transform3D] = []
		var frozen_tints: Array[Color] = []
		for slot in visible.size():
			var i: int = visible[slot]
			var xf: Transform3D = transforms[i]
			frozen.set_instance_transform(slot, xf)
			frozen_transforms.append(xf)
			frozen.set_instance_custom_data(slot, tints[i])
			frozen_tints.append(tints[i])
		copy.set_meta("instance_transforms", frozen_transforms)
		copy.set_meta("instance_tints", frozen_tints)
		copy.set_meta("building_pool", node.get_meta("building_pool", false))
		copy.multimesh = frozen
		Scenery.sync_pool_bounds(copy)
		parent.add_child(copy)

	func begin(slot: int) -> void:
		used[slot] = 0

	func put(slot: int, xform: Transform3D, tint := Color.WHITE) -> bool:
		var n: int = used.get(slot, 0)
		if n >= per_chunk:
			push_warning("pool full")
			return false
		var i := slot * per_chunk + n
		var rendered: int = render_index.get(i, -1)
		if rendered >= 0: Scenery.clear_fade_slot(node, rendered)
		transforms[i] = xform
		tints[i] = tint
		multi.set_instance_transform(i, xform)
		multi.set_instance_custom_data(i, tint)
		if rendered < 0:
			rendered = render_slots.size()
			render_slots.append(i)
			render_index[i] = rendered
			if rendered == 0:
				render_multi.custom_aabb = xform * multi.mesh.get_aabb()
			else:
				render_multi.custom_aabb = render_multi.custom_aabb.merge(xform * multi.mesh.get_aabb())
		else:
			# Exact shrinking happens at finish(), after the chunk's atomic build.
			render_multi.custom_aabb = render_multi.custom_aabb.merge(xform * multi.mesh.get_aabb())
		render_transforms[rendered] = xform
		render_tints[rendered] = tint
		render_multi.set_instance_transform(rendered, xform)
		render_multi.set_instance_custom_data(rendered, tint)
		render_multi.visible_instance_count = render_slots.size()
		used[slot] = n + 1
		return true

	func finish(slot: int) -> void:
		for n in range(used.get(slot, 0), per_chunk):
			var i := slot * per_chunk + n
			var rendered: int = render_index.get(i, -1)
			if rendered >= 0: Scenery.clear_fade_slot(node, rendered)
			transforms[i] = HIDDEN
			multi.set_instance_transform(i, HIDDEN)
		_sync_draw()

	func _sync_draw() -> void:
		var originals: Dictionary = node.get_meta("occlusion_originals", {})
		var fades: Dictionary = node.get_meta("occlusion_fades", {})
		var logical_originals := {}
		var logical_fades := {}
		for index in originals:
			logical_originals[render_slots[index]] = originals[index]
		for index in fades:
			logical_fades[render_slots[index]] = fades[index]
		originals.clear(); fades.clear()
		var previous_count := render_slots.size()
		render_slots.clear(); render_index.clear()
		for logical in transforms.size():
			if transforms[logical].origin.y < -10.0: continue
			var rendered := render_slots.size()
			render_slots.append(logical)
			render_index[logical] = rendered
			render_transforms[rendered] = transforms[logical]
			render_tints[rendered] = tints[logical]
			if logical_originals.has(logical): originals[rendered] = logical_originals[logical]
			if logical_fades.has(logical): fades[rendered] = logical_fades[logical]
			render_multi.set_instance_transform(rendered, HIDDEN if originals.has(rendered) else transforms[logical])
			render_multi.set_instance_color(rendered, Color.WHITE)
			render_multi.set_instance_custom_data(rendered, tints[logical])
		for rendered in range(render_slots.size(), previous_count):
			render_transforms[rendered] = HIDDEN
			render_tints[rendered] = Color.WHITE
			render_multi.set_instance_transform(rendered, HIDDEN)
		render_multi.visible_instance_count = render_slots.size()
		Scenery.sync_pool_bounds(node)
		if node.has_meta("occlusion_fade_node"): Scenery.sync_fade_batch(node)


## Keep ordinary buildings in their original opaque instanced draw. Only a building that
## intersects a target sightline moves to the shared transparent batch of the same model.
func register_building_pool(node: MultiMeshInstance3D) -> void:
	if node.has_meta("fade_registered"): return
	node.set_meta("fade_registered",true)
	node.set_meta("building_pool",true)
	var originals := {}
	node.set_meta("occlusion_originals", originals)
	var fades := {}
	node.set_meta("occlusion_fades",fades)
	occluders.append({"node":weakref(node),"originals":originals,"fades":fades,"fade_node":null})

func update_occluders(camera: Camera3D, targets: Array[Vector3], delta: float) -> void:
	for state in occluders.duplicate():
		var node: MultiMeshInstance3D = state.node.get_ref()
		if node == null:
			occluders.erase(state)
			continue
		if not node.is_visible_in_tree(): continue
		var multi := node.multimesh
		var bounds := multi.mesh.get_aabb().grow(0.12)
		var poses: Array = node.get_meta("instance_transforms",[])
		var count := multi.instance_count if multi.visible_instance_count < 0 else multi.visible_instance_count
		var bounds_dirty := false
		var fades_dirty := false
		for i in count:
			var xf: Transform3D = state.originals.get(i,poses[i] if poses.size()>i else multi.get_instance_transform(i))
			if xf.origin.y < -10.0: continue
			var world: Transform3D = node.global_transform * xf
			var nearby := world.origin.distance_to(targets[0]) < 85.0
			if not nearby and not state.fades.has(i): continue
			var blocked := false
			if nearby:
				var inv := world.affine_inverse()
				var origin: Vector3 = inv * camera.global_position
				for target in targets:
					if bounds.intersects_segment(origin,inv*target) != null:
						blocked=true;break
			var opacity := move_toward(float(state.fades.get(i,1.0)),0.25 if blocked else 1.0,delta*4.0)
			if opacity >= 0.999:
				if state.originals.has(i):
					set_opaque_pose(node, i, xf)
					bounds_dirty = true
					fades_dirty = true
				state.originals.erase(i)
				state.fades.erase(i)
				continue
			if state.fade_node == null:
				var faded := MultiMeshInstance3D.new()
				var transparent := MultiMesh.new()
				transparent.transform_format=MultiMesh.TRANSFORM_3D
				transparent.use_colors=true
				transparent.use_custom_data=true
				transparent.mesh=multi.mesh
				transparent.instance_count=8
				transparent.visible_instance_count=0
				faded.multimesh=transparent
				faded.material_override=building_material
				faded.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(faded)
				state.fade_node=faded
				node.set_meta("occlusion_fade_node",weakref(faded))
			if not state.originals.has(i):
				set_opaque_pose(node, i, Pool.HIDDEN)
				bounds_dirty = true
				fades_dirty = true
			if state.fades.get(i, 1.0) != opacity: fades_dirty = true
			state.originals[i]=xf
			state.fades[i]=opacity
		if bounds_dirty: sync_pool_bounds(node)
		if state.fade_node != null and fades_dirty: sync_fade_batch(node)


## Keep the public logical buffer in sync when a packed building changes batch.
static func set_opaque_pose(node: MultiMeshInstance3D, index: int, pose: Transform3D) -> void:
	node.multimesh.set_instance_transform(index, pose)
	if node.has_meta("source_pool"):
		var pool: Pool = node.get_meta("source_pool").get_ref()
		if pool != null: pool.multi.set_instance_transform(pool.render_slots[index], pose)


## Capacity tails must not pull a far-away batch's bounds toward (0,-50,0).
static func sync_pool_bounds(node: MultiMeshInstance3D) -> void:
	var multi := node.multimesh
	if multi == null or multi.mesh == null: return
	var count := multi.instance_count if multi.visible_instance_count < 0 else multi.visible_instance_count
	var poses: Array = node.get_meta("instance_transforms", [])
	var originals: Dictionary = node.get_meta("occlusion_originals", {})
	var bounds := AABB()
	var first := true
	for i in count:
		if originals.has(i): continue # drawn by the independent transparent child
		var pose: Transform3D = poses[i] if i < poses.size() else multi.get_instance_transform(i)
		if pose.origin.y < -10.0: continue
		var box: AABB = pose * multi.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	# An empty AABB asks Godot to recalculate it from the full reserved buffer.
	multi.custom_aabb = AABB(Vector3(0,-50,0),Vector3(0.001,0.001,0.001)) if first else bounds


static func clear_fade_slot(node: MultiMeshInstance3D, index: int) -> void:
	(node.get_meta("occlusion_originals",{}) as Dictionary).erase(index)
	var fades: Dictionary = node.get_meta("occlusion_fades",{})
	fades.erase(index)
	if node.has_meta("occlusion_fade_node"): sync_fade_batch(node)

static func sync_fade_batch(node: MultiMeshInstance3D) -> void:
	var faded: MultiMeshInstance3D=node.get_meta("occlusion_fade_node").get_ref()
	if faded == null: return
	var fades: Dictionary=node.get_meta("occlusion_fades",{})
	var originals: Dictionary=node.get_meta("occlusion_originals",{})
	var ids:=fades.keys()
	var multi:=faded.multimesh
	if ids.size()>multi.instance_count:
		multi.instance_count=maxi(8,int(pow(2.0,ceil(log(float(ids.size()))/log(2.0)))))
	multi.visible_instance_count=ids.size()
	var poses: Array[Transform3D] = []
	for slot in ids.size():
		var index: int=ids[slot]
		var tints: Array=node.get_meta("instance_tints",[])
		var custom: Color=tints[index] if tints.size()>index else node.multimesh.get_instance_custom_data(index)
		custom.a=floor(custom.a)+float(fades[index])*0.5
		multi.set_instance_transform(slot,originals[index])
		poses.append(originals[index])
		multi.set_instance_color(slot,Color.WHITE)
		multi.set_instance_custom_data(slot,custom)
	faded.set_meta("instance_transforms", poses)
	sync_pool_bounds(faded)
	faded.visible=not ids.is_empty()
