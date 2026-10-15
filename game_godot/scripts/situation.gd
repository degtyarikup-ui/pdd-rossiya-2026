## One exam situation exported from the WebView game
## (the data of game_godot/situations/): the junction scene, its
## roadside props, traffic lights and participants, plus everything the
## engine computed for it (scene.json: paths, exits, stop line, lanes).
## Coordinates: origin = junction centre, the player approaches along +Z.
class_name Situation
extends Node3D

var id: String
var data: Dictionary
var lights: Array[Node3D] = []
var _signs: Array[Node3D] = []
var officers: Array[Node3D] = []
var actors: Array[Node3D] = []       # same order as data.actors
var tram_plan := {}                 # derived paths/rails; authored scene data is never rewritten
var _surface_cache := {}
var _surface_signature := 0
var _surface_cuts: Array[Transform3D] = []
var _cut_bindings: Array = []
var _clipped_surface_cache := {}
var _surface_material: ShaderMaterial
var _ground_maps := {}
var _ground_scenery: Scenery
var _pool_nodes := {}
var _pools := {}                     # prop -> MultiMesh
var _baked_scene: Node3D
var network: RoadNetwork             # the road network (network/<id>.json); the source of truth
var _mask: Image                     # legacy drivable area (road.png) for scenes without a network
var _crop := 90.0
var _guide: Node3D                   # route ribbons (visible while the question is open)
var _evidence: Array[Node3D] = []    # letter tokens
var _badges: Array[Node3D] = []      # name plates over the participants


static var _tasks: Array[int] = []
static var _native_resources := {}
static var _ready_ids := {}          # web: junctions whose files are in memory


static func _uses_shared_model(kind: String) -> bool:
	return kind == "pedestrian" or kind == "special" or kind in NpcVehicle.KINDS


## Read saved swatches even for scenes exported before paint was supported.
## Match by id: editor order can differ from the archived actor order.
static func _actor_config(actor: Dictionary, source: Dictionary = {}) -> Dictionary:
	var config: Dictionary = actor.get("config", {}).duplicate(true)
	var paint = actor.get("paint")
	for authored in source.get("actors", []):
		if str(authored.id) == str(actor.id):
			paint = authored.get("paint")
			break
	if paint is String and Color.html_is_valid(paint):
		config["color"] = paint
		config["cabColor"] = paint
	return config


## Web: the junction's files come over the network (PackFiles). Native: always.
static func prepared(situation_id: String) -> bool:
	return _ready_ids.has(situation_id)


## Web: fetches the junction's files and parses its models, then on_done(ok).
## Native: at once, nothing to fetch.
static func prepare(situation_id: String, on_done: Callable) -> void:
	if prepared(situation_id):
		if on_done.is_valid(): on_done.call(true)
		return
	if not PackFiles.web():
		_native_prepare(situation_id, on_done)
		return
	var dir := "res://situations/%s/" % situation_id
	var first: Array = [dir + "scene.json", dir + "scene.glb"]
	if not FileAccess.file_exists("res://network/%s.json" % situation_id):
		first.append(dir + "road.png")   # the mask: only for a scene without a network
	PackFiles.fetch_all(first, func(ok: bool):
		if not ok or not PackFiles.exists(dir + "scene.json"):
			if on_done.is_valid(): on_done.call(false)
			return
		var data = JSON.parse_string(PackFiles.text(dir + "scene.json"))
		if not (data is Dictionary):
			if on_done.is_valid(): on_done.call(false)
			return
		# Required: the lights and participants the scene names (they must be here).
		var more: Array = []
		for i in data.lights.size():
			if not TrafficSignal.supports(data.lights[i]): more.append(dir + "light_%d.glb" % i)
		for i in data.actors.size():
			if not _uses_shared_model(str(data.actors[i].type)):
				more.append(dir + "actor_%d.glb" % i)
		# Optional: the route guide (only for a scene without trajectories) and the ticket picture.
		var optional: Array = []
		if not (data.get("trajectories", []) is Array) or data.trajectories.is_empty():
			optional.append(dir + "guide.glb")
		var picture := GameUi.picture_name(situation_id)
		if picture != "":
			optional.append("res://questions/%s.webp" % picture)
		PackFiles.fetch_all(more + optional, func(ok2: bool):
			var parsed := ok2
			for p in first + more:
				if not PackFiles.exists(p):
					parsed = false
			for p in first + more + optional:
				if p.ends_with(".glb"): await (Engine.get_main_loop() as SceneTree).process_frame
				if not on_done.is_valid(): return
				if p.ends_with(".glb") and PackFiles.exists(p) and not PackFiles.parse_glb(p):
					parsed = false
			if parsed:
				_ready_ids[situation_id] = true
			if on_done.is_valid(): on_done.call(parsed)))


## Web: frees the junction's files once it is built.
static func forget(situation_id: String) -> void:
	_ready_ids.erase(situation_id)
	_native_resources.erase(situation_id)
	PackFiles.forget("res://situations/%s/" % situation_id)


static func load_scene(situation_id: String, scenery: Scenery) -> Situation:
	return load_scene_staged.call(situation_id, scenery)


static func load_scene_staged(situation_id: String, scenery: Scenery, frames: SceneTree = null, staging_parent: Node = null) -> Situation:
	if frames != null and Host.is_exiting(frames): return null
	var s := Situation.new()
	s._ground_scenery = scenery
	if staging_parent:
		s.visible = false
		staging_parent.add_child(s)
	s.id = situation_id
	s.name = situation_id
	var dir := "res://situations/%s/" % situation_id
	s.data = JSON.parse_string(PackFiles.text(dir + "scene.json"))
	# Some scenes were exported before these fields existed: the game's own
	# defaults (game.js buildIntersectionSegment) stand in for them.
	for key in ["approachW", "leftLane", "rightLane", "kerbZ", "kerbX"]:
		if not s.data.has(key) or s.data[key] == null:
			s.data[key] = 8.4 if key == "approachW" else (4.2 if key.begins_with("kerb") else 1.8)
	if not s.data.has("exitWidths") or not (s.data.exitWidths is Dictionary):
		s.data["exitWidths"] = {}
	var scene: Node3D = PackFiles.instance(dir + "scene.glb")
	s._baked_scene = scene
	# Attach immediately: cancelling during a mesh job must also free this GLB node tree.
	s.add_child(scene)
	s.network = RoadNetwork.load_scene(situation_id)
	# Derive rails from the saved tram motion, never by rewriting the author's
	# roads, props or routes. Native builds do the corridor search off-thread.
	var tram_data: Dictionary = s.data
	var tram_network: RoadNetwork = s.network
	# Imported model pivots are not always centred. Capture their real bounds
	# on the main thread before the immutable corridor search starts.
	TramTracks.prepare_tram(tram_data)
	var prop_slice := Time.get_ticks_usec()
	for prop in tram_data.get("props", []):
		TramTracks.prepare_props({"props": [prop], "actors": tram_data.get("actors", [])})
		if frames and Time.get_ticks_usec() - prop_slice > 2000:
			await frames.process_frame
			if _staging_cancelled(s, frames): return null
			prop_slice = Time.get_ticks_usec()
	if frames and not PackFiles.web():
		var staged_tram_plan := await _data_in_background(func(): return TramTracks.plan(tram_data, tram_network, scenery), frames)
		if _staging_cancelled(s, frames): return null
		s.tram_plan = staged_tram_plan
	else:
		s.tram_plan = TramTracks.plan(tram_data, tram_network, scenery)
	if s.network:
		s.network.tram_surfaces = TramGeometry.surfaces(s.tram_plan)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == "static":
			if frames and PackFiles.web():
				var processed := await _without_baked_ground_staged(mi.mesh, s.network, frames)
				if _staging_cancelled(s, frames): return null
				mi.mesh = processed
			elif frames:
				var immutable_mesh := mi.mesh
				var immutable_network := s.network
				var processed := await _mesh_in_background(func(): return _without_baked_ground(immutable_mesh, immutable_network), frames)
				if _staging_cancelled(s, frames): return null
				mi.mesh = processed
			else:
				mi.mesh = _without_baked_ground(mi.mesh, s.network)
			mi.material_override = scenery.material
		# tex_0: the web game's dirt strips along the exits (a brown track over the asphalt). The
		# exits are asphalt in the game, the same as the entrance: the strips are not drawn.
		if mi.name == "tex_0":
			mi.visible = false
		elif s.network and str(mi.name).begins_with("tex_"):
			# Old soil photographs are also tex_1/tex_2 in some scenes. Retain sign faces,
			# but remove flat texture overlays where the editable network draws the ground.
			mi.mesh = _without_covered_texture(mi.mesh, s.network)
		# The exported sign pictures (tex_1...): a scene with its own signs (the editor) draws them anew.
		if s.network and mi.name in s.network.data.get("bakedSigns", []):
			mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s._crop = s.data.crop
	if s.network:
		if frames:
			var surf := MeshInstance3D.new()
			surf.name = "surfaces"
			surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.add_child(surf)
			if PackFiles.web():
				var processed: Mesh = await s.network.surface_mesh_staged(scenery, frames)
				if _staging_cancelled(s, frames): return null
				surf.mesh = processed
			else:
				var immutable_network := s.network
				var processed: Mesh = await _mesh_in_background(func(): return immutable_network.surface_mesh(scenery), frames)
				if _staging_cancelled(s, frames): return null
				surf.mesh = processed
		else:
			s.add_child(_surface_node(s.network, scenery))
	else:
		s._mask = PackFiles.image(dir + "road.png")
		if s._mask.is_compressed():
			s._mask.decompress()
	if frames:
		await s._place_props(scenery, frames)
		if _staging_cancelled(s, frames): return null
	else:
		s._place_props.call(scenery)
	for i in s.data.lights.size():
		if frames: await frames.process_frame
		if _staging_cancelled(s, frames): return null
		var l: Dictionary = s.data.lights[i]
		var light: Node3D = TrafficSignal.make(l) if TrafficSignal.supports(l) else PackFiles.instance(dir + "light_%d.glb" % i)
		light = RoadBuild.light_with_signs(light, l.get("mountedSigns", []), l.get("mountedMainRoad", []))
		light.position = _v(l.pos)
		light.rotation.y = l.yaw
		light.scale = Vector3.ONE * float(l.scale)
		s.add_child(light)
		s.lights.append(light)
	s._build_evidence(dir)
	for i in s.data.actors.size():
		if frames: await frames.process_frame
		if _staging_cancelled(s, frames): return null
		var a: Dictionary = s.data.actors[i]
		var actor: Node3D
		if a.type == "special":
			# An emergency car of the tickets is a traffic police car (ДПС) with its lights (fleet.gd).
			actor = Fleet.dps_car()
		elif a.type == "pedestrian":
			var person := Pedestrian.new()
			person.configure(posmod((situation_id + str(a.id)).hash(), Models.WALKERS), Color(str(a.config.get("color", "#5A7891"))))
			actor = person
		elif a.type in NpcVehicle.KINDS:
			var config := _actor_config(a, s.network.data if s.network else {})
			actor = NpcVehicle.make(str(a.type), Color(str(config.get("color", "#8D9AA8"))), config)
		else:
			actor = PackFiles.instance(dir + "actor_%d.glb" % i)
			_vertex_colours_as_albedo(actor)
		actor.position = _v(a.pos)
		actor.rotation.y = a.yaw
		actor.scale = _v(a.scale)
		# Prepare lenses while loading; they start together when the question opens.
		var plan = a.get("signalPlan")
		if a.type in Fleet.SIGNAL_KINDS and (Fleet.actor_signal_side(a) != "" or (plan is Array and not plan.is_empty())):
			var k := maxf(0.01, float(a.scale[0]))
			Fleet.add_blinkers(actor, "", float(a.get("halfLength", 2.1)) / k, float(a.get("halfWidth", 0.9)) / k)
		Fleet.set_hazards(actor, Fleet.actor_has_hazards(a))
		s.add_child(actor)
		s.actors.append(actor)
		if a.badge != null:
			var plate := _badge_node(a.badge.text.get(Ui.lang, a.badge.text.ru), Color(a.badge.color))
			plate.position = Vector3(0, float(a.badge.height), 0)
			plate.scale = Vector3.ONE / actor.scale
			actor.add_child(plate)
			s._badges.append(plate)
	# Traffic controllers (the editor's «Регулировщик»): the model in the signal the ticket shows.
	for of in (s.network.data.get("officers", []) if s.network else s.data.get("officers", [])):
		var cop := Fleet.officer(str(of.get("gesture", "sides")))
		cop.position = Vector3(of.pos[0], 0.0, of.pos[1])
		cop.rotation.y = float(of.get("yaw", 0.0))
		s.add_child(cop)
		s.officers.append(cop)
	# Road signs of the junction (the editor's «Знаки»): faces towards their yaw, as the lights.
	if s.network:
		for sg in s.network.data.get("signs", []):
			if frames: await frames.process_frame
			if _staging_cancelled(s, frames): return null
			var plate: String = sg.get("plate") if sg.get("plate") is String else ""
			var plate_sign: String = sg.get("plateSign") if sg.get("plateSign") is String else ""
			var main_road: Array = sg.get("mainRoad") if sg.get("mainRoad") is Array else []
			var roads: Array = sg.get("roads") if sg.get("roads") is Array else []
			var sign := RoadBuild.sign_node(str(sg.code), plate, plate_sign, main_road, roads, true, sg)
			if sign == null:
				continue
			sign.position = Vector3(sg.pos[0], 0.0, sg.pos[1])
			sign.rotation.y = float(sg.get("yaw", PI)) - PI
			s.add_child(sign)
			s._signs.append(sign)
	s.set_evidence_visible(false)
	if s.network:
		s._surface_signature=hash(s.network.stitch_bindings)
		s._surface_cache[s._surface_signature]=s.get_node("surfaces").mesh
		s.refresh_uv(scenery)
	return s


## A hidden staged scene has no visible state to preserve once the host starts
## closing. Stop between slices so iOS can replace its owner without leaving a
## nested builder suspended with captured network/scenery resources.
static func _staging_cancelled(scene, frames: SceneTree) -> bool:
	if not is_instance_valid(scene): return true
	if frames != null and Host.is_exiting(frames):
		scene.queue_free()
		return true
	return false


## Puts the junction at world z. Its road surfaces are laid on the world grid
## (the street's texture grid), so the surface is rebuilt for that z.
func place_at(z: float, scenery: Scenery) -> void:
	position = Vector3(0.0, 0.0, z)
	var node := get_node_or_null("surfaces") as MeshInstance3D
	if node and network:
		refresh_uv(scenery)


## The detail map follows the world grid again after the world was rebased (a turn).
func refresh_uv(scenery: Scenery, texture_frame := Transform3D()) -> void:
	var node := get_node_or_null("surfaces") as MeshInstance3D
	if node and network:
		var base_signature := hash(network.stitch_bindings)
		var signature := hash([base_signature, _surface_cuts])
		if signature!=_surface_signature:
			var mesh: Mesh = _surface_cache.get(base_signature)
			if mesh == null:
				mesh = network.surface_mesh(scenery)
				_surface_cache[base_signature] = mesh
			if not _surface_cuts.is_empty():
				if not _clipped_surface_cache.has(base_signature):
					for cut in _surface_cuts:
						if mesh == null: break
						mesh = SceneStitch.clip_mesh(mesh, cut)
					_clipped_surface_cache[base_signature] = mesh
				mesh = _clipped_surface_cache[base_signature]
			node.mesh = mesh
			_surface_signature=signature
		if _surface_material==null:
			_surface_material=scenery.material.duplicate()
			_surface_material.set_shader_parameter("grid_uv",true)
			node.material_override=_surface_material
		_surface_material.set_shader_parameter("surface_frame",texture_frame)


## Every later turn gives the next scene the forward side of its join. Retain only
## the old side, even if a loop keeps this scene close enough to survive retirement.
## Cuts stay in scene coordinates and also apply to subsequently warmed mesh variants.
func trim_before_join(scenery: Scenery, texture_frame: Transform3D) -> void:
	var cut := global_transform
	# Completed scenes never need every prewarmed exit again. Retain the selected
	# base and clipped mesh only; later joins clip that one variant in place.
	var active := hash(network.stitch_bindings) if network else 0
	for signature in _surface_cache.keys():
		if signature != active: _surface_cache.erase(signature)
	for signature in _clipped_surface_cache.keys():
		if signature != active: _clipped_surface_cache.erase(signature)
	# Existing variants already contain earlier cuts; only process the new plane.
	# A variant warmed later still receives the complete sequence in refresh_uv.
	for signature in _clipped_surface_cache:
		var mesh: Mesh = _clipped_surface_cache[signature]
		if mesh: _clipped_surface_cache[signature] = SceneStitch.clip_mesh(mesh, cut)
	_surface_cuts.append(cut)
	_cut_bindings.append({"port": {"p": cut.affine_inverse().origin,
		"out": cut.basis.transposed() * Vector3.BACK}})
	_ground_maps.clear()
	_trim_end_props()
	refresh_uv(scenery, texture_frame)
	# Legacy GLB overlays can retain small tails outside the network footprint.
	# Clip those too; participant and signal models remain independent nodes.
	if _baked_scene:
		for node: MeshInstance3D in _baked_scene.find_children("*", "MeshInstance3D", true, false):
			if node.mesh and (node.name == "static" or str(node.name).begins_with("tex_")):
				node.mesh = SceneStitch.clip_mesh(node.mesh, node.global_transform)


## The point (situation coordinates) is inside this junction's own streets.
func covers(local: Vector3) -> bool:
	return absf(local.x) <= _crop and absf(local.z) <= _crop and SceneStitch.contains(local, _cut_bindings) and (network == null or SceneStitch.contains(local,network.stitch_bindings))


## A retained tram must not cross a seam after its rail mesh has been cut.
## The complete body, not only its centre, stays on the scene-owned side.
func tram_body_supported(p: Vector3, yaw: float, hw: float, hl: float) -> bool:
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var right := SceneStitch.right(forward)
	for along in [-hl, hl]:
		for across in [-hw, hw]:
			var corner: Vector3 = p + forward * along + right * across
			if absf(corner.x) > _crop or absf(corner.z) > _crop: return false
			if not SceneStitch.contains(corner, _cut_bindings): return false
			if network and not SceneStitch.contains(corner, network.stitch_bindings): return false
	return true


## game.js roadSupports at this point: from the road network (or, for a scene
## without one, the exported mask).
func road_at(local: Vector3) -> bool:
	if not SceneStitch.contains(local, _cut_bindings): return false
	if network:
		var map := ground_map()
		return (map.at(local) & GroundMap.ROAD) != 0 if map else network.is_drivable(local)
	var m: Dictionary = data.roadMask
	var xi := int(floor((local.x - float(m.x)) / float(m.cell)))
	var zi := int(floor((local.z - float(m.z)) / float(m.cell)))
	if xi < 0 or zi < 0 or xi >= _mask.get_width() or zi >= _mask.get_height():
		return false
	return _mask.get_pixel(xi, zi).r > 0.5


func ground_map() -> GroundMap:
	var surface := get_node_or_null("surfaces") as MeshInstance3D
	if surface == null or surface.mesh == null or _ground_scenery == null: return null
	var key := surface.mesh.get_instance_id()
	if not _ground_maps.has(key): _ground_maps[key] = GroundMap.new(surface.mesh, _ground_scenery)
	return _ground_maps[key]


func pavement_at(local: Vector3) -> bool:
	var map := ground_map()
	return map != null and (map.at(local) & GroundMap.WALK) != 0


static func _surface_node(net: RoadNetwork, scenery: Scenery) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "surfaces"
	node.mesh = net.surface_mesh(scenery)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A participant's colours are in its vertices (a pedestrian or a cyclist is built from coloured
## parts): the material has to take them, or the figure draws white.
static func _vertex_colours_as_albedo(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).vertex_color_use_as_albedo = true


## The baked junction carries its own pavement and lawn, overlapping the network's ones; its lawn is in three overlapping layers 3-5 mm apart, which
## flicker against each other and the world's lawn. Flat triangles below the carriageway are
## dropped: the world's one lawn (world.gd) is under the junction.
static func _without_baked_ground(mesh: Mesh, net: RoadNetwork = null) -> Mesh:
	return _without_baked_ground_staged.call(mesh, net)


static func _without_baked_ground_staged(mesh: Mesh, net: RoadNetwork = null, frames: SceneTree = null) -> Mesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		var keep := PackedInt32Array()
		var slice := Time.get_ticks_usec()
		for k in range(0, idx.size(), 3):
			if frames and Time.get_ticks_usec()-slice > 2000:
				await frames.process_frame
				slice = Time.get_ticks_usec()
			var a := verts[idx[k]]
			var b := verts[idx[k + 1]]
			var c := verts[idx[k + 2]]
			if _legacy_rail_triangle(a, b, c, colours, idx[k], idx[k + 1], idx[k + 2]): continue
			var flat := absf(a.y - b.y) < 0.001 and absf(a.y - c.y) < 0.001
			if flat and a.y < -0.001 and a.y > -0.5:
				continue
			# Its own pavement (0.18 m, ~200 000 m2 over all scenes) and lawns 6 mm above it lie
			# exactly on the network's pavement (build.py): the network draws the pavement.
			if flat and a.y > 0.17 and a.y < 0.215:
				continue
			# The scene's own road copy (0..3.5 cm: asphalt, islands, lawns at the network's level)
			# lies under the network's surfaces at a few centimetres: two layers of different colour
			# and texture shimmer and show seams. Dropped where the network draws the same ground.
			if flat and net and a.y >= -0.001 and a.y < 0.035:
				var centre := Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0)
				if net.covers(centre):
					continue
			# Its own kerb walls (0..0.2 m) stand exactly on the network's kerbs: two walls in one
			# place shimmer (kerb corners, the whole ring of a roundabout). The network draws them.
			var lo := minf(a.y, minf(b.y, c.y))
			var hi := maxf(a.y, maxf(b.y, c.y))
			if not flat and lo > -0.02 and hi < 0.215:
				continue
			# Drop hills/mounds ("горки"), terrain skirts and elevated terraced terrain:
			if not flat and (hi >= 0.215 or lo <= -0.05):
				continue
			if flat and a.y >= 0.215:
				continue
			if a.y < -0.05:
				continue
			keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		# A scene laid out in the editor's road plan draws all its ground itself: nothing may be left.
		if keep.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


## Old rails are coloured ground geometry inside the combined GLB. Match all
## three vertices and the low height; similarly coloured furniture survives.
static func _legacy_rail_triangle(a: Vector3, b: Vector3, c: Vector3, colours: PackedColorArray, ia: int, ib: int, ic: int) -> bool:
	# Some original rails rise with the sidewalk: the audited GLBs reach
	# 0.214 m. A road-height-only filter leaves their upper strips behind.
	if colours.is_empty() or minf(a.y, minf(b.y, c.y)) < -0.02 or maxf(a.y, maxf(b.y, c.y)) > 0.24: return false
	for colour in [Color("#8e999c"), Color("#929a9c"), Color("#9ea6ae")]:
		for target in [colour, colour.srgb_to_linear()]:
			var matches := true
			for index in [ia, ib, ic]:
				var value: Color = colours[index]
				if maxf(absf(value.r - target.r), maxf(absf(value.g - target.g), absf(value.b - target.b))) > 1.5 / 255.0:
					matches = false
					break
			if matches: return true
	return false


static func _without_covered_texture(mesh: Mesh, net: RoadNetwork) -> Mesh:
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array: indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty(): indices = PackedInt32Array(range(verts.size()))
		var keep := PackedInt32Array()
		for k in range(0, indices.size(), 3):
			var a := verts[indices[k]];var b := verts[indices[k+1]];var c := verts[indices[k+2]]
			var ground := absf(a.y-b.y)<0.001 and absf(a.y-c.y)<0.001 and a.y>=-0.001 and a.y<0.035
			if ground and net.covers(Vector2((a.x+b.x+c.x)/3.0,(a.z+b.z+c.z)/3.0)): continue
			keep.append_array([indices[k],indices[k+1],indices[k+2]])
		if keep.is_empty(): continue
		arrays[Mesh.ARRAY_INDEX]=keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		out.surface_set_material(out.get_surface_count()-1,mesh.surface_get_material(surface))
	return out


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _place_props(scenery: Scenery, frames: SceneTree = null) -> void:
	var groups := {}
	for p in _tram_render_props():
		if not groups.has(p.prop):
			groups[p.prop] = []
		groups[p.prop].append(p)
	var winter: bool = scenery.season.precipitation == "snow"
	for prop in groups:
		if frames: await frames.process_frame
		var list: Array = groups[prop]
		var parked: bool = prop == "parked"
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = Models.mesh_of("res://models/traffic/sedan.glb" if parked else "res://scenery/%s.glb" % prop)
		multi.instance_count = list.size()
		var poses: Array[Transform3D] = []
		var tints: Array[Color] = []
		for i in list.size():
			var p: Dictionary = list[i]
			var basis := Basis(Vector3.UP, p.yaw).scaled(_v(p.scale))
			var xf: Transform3D = p.get("runtime_transform", Transform3D(basis, _v(p.pos)))
			multi.set_instance_transform(i, xf)
			poses.append(xf)
			multi.set_instance_color(i, Color.WHITE)
			var tint := Color(p.tint) if p.get("tint") else Color.WHITE
			var custom := Color(tint.r, tint.g, tint.b, 0.0 if parked else (1.0 if winter else 0.0))
			multi.set_instance_custom_data(i, custom)
			tints.append(custom)
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.set_meta("instance_transforms",poses)
		node.set_meta("authored_transforms",poses.duplicate())
		node.set_meta("instance_tints",tints)
		node.material_override = Models.traffic_material() if parked else scenery.occluder_material if prop.begins_with("buildings/") else scenery.material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if prop.begins_with("trees/") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_pools[prop] = multi
		_pool_nodes[prop] = node
		if prop.begins_with("buildings/"): scenery.register_building_pool(node)

	var trees: Array = data.props.filter(func(p): return str(p.prop).begins_with("trees/"))
	if not trees.is_empty():
		var contact := MultiMesh.new()
		contact.transform_format = MultiMesh.TRANSFORM_3D
		contact.mesh = Models.contact_mesh()
		contact.instance_count = trees.size()
		for i in trees.size():
			var p: Dictionary = trees[i]
			contact.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.4*p.scale[0],1.0,1.4*p.scale[2])),Vector3(p.pos[0],0.012,p.pos[2])))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = contact
		mi.material_override = Models.contact_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## A service driveway may open an existing fence outside the question area.
## Split the rendered instance in its own model coordinates; the stored
## location, road plan and all other props remain exactly as authored.
func _tram_render_props() -> Array:
	var out: Array = []
	var openings: Dictionary = tram_plan.get("fence_openings", {})
	for i in data.props.size():
		var prop: Dictionary = data.props[i]
		if not openings.has(i): out.append(prop); continue
		var opening: Dictionary = openings[i]
		var axis := 0 if opening.axis == "x" else 2
		var bounds: AABB = opening.bounds
		var intervals: Array = [[bounds.position[axis], bounds.end[axis]]]
		for cut: Vector2 in opening.cuts:
			var next: Array = []
			for interval in intervals:
				if cut.y <= interval[0] or cut.x >= interval[1]: next.append(interval); continue
				if cut.x > interval[0]: next.append([interval[0], cut.x])
				if cut.y < interval[1]: next.append([cut.y, interval[1]])
			intervals = next
		for interval in intervals:
			var length_: float = interval[1] - interval[0]
			if length_ < 0.2: continue
			var piece: Dictionary = prop.duplicate(true)
			var ratio: float = length_ / maxf(0.001, bounds.size[axis])
			var delta := Vector3.ZERO
			delta[axis] = (float(interval[0]) + float(interval[1])) * 0.5 - bounds.get_center()[axis] * ratio
			var local_scale := Vector3.ONE
			local_scale[axis] = ratio
			var original := Transform3D(Basis(Vector3.UP, float(prop.yaw)).scaled(_v(prop.scale)), _v(prop.pos))
			var transform := original * Transform3D(Basis.from_scale(local_scale), delta)
			var at := transform.origin
			piece.pos = [at.x, at.y, at.z]
			piece.scale[axis] = float(prop.scale[axis]) * ratio
			piece["runtime_transform"] = transform
			out.append(piece)
	return out


# --- question evidence -------------------------------------------------------------

const TOKEN_BLUE := Color("#0574F8")


func _build_evidence(dir: String) -> void:
	# The question's route lines come from the network's trajectories (what the editor shows);
	var has_traj: bool = (data.trajectories is Array and not data.trajectories.is_empty()) or (data.get("spec") is Dictionary and data.get("exits") is Dictionary and data.spec.get("maneuver", "") != "" and data.exits.has(data.spec.get("maneuver", "")))
	if has_traj:
		_guide = _trajectory_guide()
		add_child(_guide)
	elif PackFiles.exists(dir + "guide.glb"):
		_guide = PackFiles.instance(dir + "guide.glb")
		for mi in _guide.find_children("*", "MeshInstance3D", true, false):
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = TOKEN_BLUE
			mat.albedo_color.a = 0.85
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.no_depth_test = false
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(mi as MeshInstance3D).position.y = 0.12
		add_child(_guide)
	for l in data.labels:
		if not l.get("letter") is String or str(l.letter).is_empty(): continue
		var token := _letter_node(l.letter, letter_colour(str(l.letter)))
		token.position = _v(l.pos)
		add_child(token)
		_evidence.append(token)


## One colour per answer letter: the route line, its arrow and the letter on the road match.
const LETTER_COLOUR := { "А": "#E0533D", "Б": "#8B5CF6", "В": "#0891B2", "Г": "#D98E04", "Д": "#16A34A" }
const GUIDE_WIDTH := 0.5      # metres: a thin line, the route can be followed by eye
const GUIDE_LIFT := 0.12


static func letter_colour(letter: String) -> Color:
	return Color(LETTER_COLOUR.get(letter, "#0574F8"))


func _trajectory_guide() -> Node3D:
	var root := Node3D.new()
	var traj_list: Array = []
	if data.trajectories is Array and not data.trajectories.is_empty():
		traj_list = data.trajectories
	elif data.get("spec") is Dictionary and data.get("exits") is Dictionary:
		var man: String = str(data.spec.get("maneuver", ""))
		if man != "" and data.exits.has(man) and data.exits[man].has("points"):
			traj_list = [{"label": "", "points": data.exits[man].points}]
	for tr in traj_list:
		var pts: Array = tr.points
		if pts.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var curve := _smooth(pts)
		var arrow: bool = tr.get("arrowhead",true) != false
		_strip(st, _shorten(curve, 1.6) if arrow else curve, GUIDE_WIDTH)
		_round_start(st, curve, GUIDE_WIDTH)
		if arrow:
			_arrowhead(st, _before_tip(curve, 1.6), curve[curve.size() - 1])
		else:
			var reverse := curve.duplicate()
			reverse.reverse()
			_round_start(st, reverse, GUIDE_WIDTH)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _guide_material(letter_colour(str(tr.get("label", ""))))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func _p2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[2] if a.size() >= 3 else a[1]))


## The route through its points as a smooth curve (Catmull-Rom), sampled every 0.4 m. The
## routes are simplified polylines: without this the corners read as breaks.
static func _smooth(pts: Array) -> PackedVector2Array:
	var p: Array[Vector2] = []
	for pt in pts:
		p.append(_p2(pt))
	var out := PackedVector2Array()
	var n := p.size()
	for i in n - 1:
		var p0: Vector2 = p[maxi(i - 1, 0)]
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[i + 1]
		var p3: Vector2 = p[mini(i + 2, n - 1)]
		var steps := maxi(1, ceili(p1.distance_to(p2) / 0.4))
		for s in steps:
			out.append(_catmull(p0, p1, p2, p3, float(s) / steps))
	out.append(p[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


## One continuous ribbon along the curve: every point shares its vertices with its neighbours,
## so there are no gaps at the joints.
static func _strip(st: SurfaceTool, pts: PackedVector2Array, width: float) -> void:
	var n := pts.size()
	var normals := PackedVector2Array()
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		normals.append(Vector2(-d.y, d.x) * (width * 0.5))
	for i in n - 1:
		var a0 := pts[i] + normals[i]
		var a1 := pts[i] - normals[i]
		var b0 := pts[i + 1] + normals[i + 1]
		var b1 := pts[i + 1] - normals[i + 1]
		for v in [a0, a1, b0, a1, b1, b0]:
			st.add_vertex(Vector3(v.x, GUIDE_LIFT, v.y))


## Cut the ribbon at the arrow's base: no rectangular band protrudes through the tip.
static func _shorten(pts: PackedVector2Array, metres: float) -> PackedVector2Array:
	var out := pts.duplicate()
	while out.size() > 1:
		var last := out.size() - 1
		var length := out[last].distance_to(out[last - 1])
		if length > metres:
			out[last] = out[last].lerp(out[last - 1], metres / length)
			return out
		metres -= length
		out.remove_at(last)
	return out


static func _round_start(st: SurfaceTool, pts: PackedVector2Array, width: float) -> void:
	var direction := (pts[1] - pts[0]).normalized()
	var side := Vector2(-direction.y, direction.x)
	for i in 12:
		var a := PI * i / 12.0
		var b := PI * (i + 1) / 12.0
		for v in [pts[0], pts[0] + (side * cos(a) - direction * sin(a)) * width * 0.5,
				pts[0] + (side * cos(b) - direction * sin(b)) * width * 0.5]:
			st.add_vertex(Vector3(v.x, GUIDE_LIFT, v.y))


## The curve point `metres` back from its end: the direction the arrowhead points in.
static func _before_tip(pts: PackedVector2Array, metres: float) -> Vector2:
	var tip := pts[pts.size() - 1]
	for i in range(pts.size() - 2, -1, -1):
		if pts[i].distance_to(tip) >= metres:
			return pts[i]
	return pts[0]


## The arrow at the end of a route: a triangle pointing along the last segment.
static func _arrowhead(st: SurfaceTool, prev: Vector2, tip: Vector2) -> void:
	var d := (tip - prev).normalized()
	var n := Vector2(-d.y, d.x)
	var base := tip - d * 1.6
	var w := n * 0.9
	st.add_vertex(Vector3(tip.x, GUIDE_LIFT, tip.y))
	st.add_vertex(Vector3(base.x + w.x, GUIDE_LIFT, base.y + w.y))
	st.add_vertex(Vector3(base.x - w.x, GUIDE_LIFT, base.y - w.y))


static func _guide_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func set_evidence_visible(on: bool) -> void:
	if is_instance_valid(_guide):
		_guide.visible = on
	for n in _evidence:
		if is_instance_valid(n): n.visible = on
	for n in _badges:
		if is_instance_valid(n): n.visible = on


func set_badges_visible(on: bool) -> void:
	for n in _badges:
		if is_instance_valid(n): n.visible = on


static var _plates := {}


## A rounded plate texture (the game's name badge / letter token), cached.
static func _plate(color: Color, size: Vector2i, radius: float, circle := false) -> ImageTexture:
	var key := "%s%s%s" % [color.to_html(), size, circle]
	if _plates.has(key):
		return _plates[key]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5) - half
			var d: float
			if circle:
				d = p.length() - half.x
			else:
				var q := p.abs() - (half - Vector2(radius, radius))
				d = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(0.5 - d, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_plates[key] = tex
	return tex


static func _billboard(tex: Texture2D, world_size: Vector2) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.pixel_size = world_size.x / float(tex.get_width())
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sp


static func _text3d(text: String, px: int, color: Color, weight := 700) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Ui.font(weight)
	l.font_size = px
	l.modulate = color
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	return l


## createActorBadge: a rounded plate above the roof, dark text on a light plate.
## The name plate over a participant: the text's real width sets the plate, so the text always
## lies inside it. Both are drawn over the car (no depth test) and the text on top of the plate.
const BADGE_PIXEL := 0.0125   # metres per pixel
const BADGE_FONT := 40        # font size in pixels (about 0.5 m high text)
const BADGE_PAD := 14         # plate padding around the text, pixels
const BADGE_LETTER_FONT := 64
const BADGE_LETTER_PIXEL := 0.016

static func _badge_node(text: String, color: Color) -> Node3D:
	var root := Node3D.new()
	# A/Б must be readable at the question camera's scale, rather than sized
	# like a compact descriptive name. Keep the plate fitted to the actual glyph.
	var letter := text.strip_edges().length() == 1
	var weight := 800 if letter else 600
	var font_size := BADGE_LETTER_FONT if letter else BADGE_FONT
	var pixel := BADGE_LETTER_PIXEL if letter else BADGE_PIXEL
	var text_px: Vector2 = Ui.font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var w := int(ceil(text_px.x)) + BADGE_PAD * 2
	var h := int(ceil(font_size * 1.25)) + BADGE_PAD
	var plate := _billboard(_plate(color, Vector2i(w, h), h * 0.35), Vector2(w, h) * pixel)
	_on_top(plate, 1)
	root.add_child(plate)
	var lum := 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	var label := _text3d(text, font_size, Color("#121212") if lum > 0.55 else Color.WHITE, weight)
	label.pixel_size = pixel
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_on_top(label, 2)
	root.add_child(label)
	return root


## createLetterToken: a white disc with a blue letter and a soft shadow. Drawn
## on top of the route ribbons (the game draws them without a depth test), the
## letter above its disc.
static func _letter_node(letter: String, colour := TOKEN_BLUE) -> Node3D:
	var root := Node3D.new()
	var shadow := _billboard(_plate(Color(0, 0, 0, 0.28), Vector2i(96, 96), 40, true), Vector2(2.2, 2.2))
	shadow.position = Vector3(0, -0.06, 0)
	_on_top(shadow, 1)
	root.add_child(shadow)
	var disc := _billboard(_plate(Color.WHITE, Vector2i(96, 96), 40, true), Vector2(2.2, 2.2))
	_on_top(disc, 2)
	root.add_child(disc)
	var label := _text3d(letter, 50, colour, 800)
	label.pixel_size = 2.2 / 96.0
	_on_top(label, 3)
	root.add_child(label)
	return root


static func _on_top(node: GeometryInstance3D, priority: int) -> void:
	node.no_depth_test = true
	node.render_priority = priority


## Runtime trimming affects only the outer road ends; saved geometry stays in editor coordinates.
func bind_end(port: Dictionary, width: float, scenery: Scenery, texture_frame := Transform3D(), profile: Dictionary = {}) -> void:
	if network == null or port.is_empty(): return
	network.stitch_bindings=bindings_with(network.stitch_bindings,port,width,profile)
	_trim_end_props()
	refresh_uv(scenery,texture_frame)

static func bindings_with(bindings: Array, port: Dictionary, width: float, profile: Dictionary = {}) -> Array:
	var result:=bindings.duplicate(true)
	for binding in result:
		if binding.port.id==port.id:
			binding.width=width
			binding.merge(profile,true)
			return result
	var binding: Dictionary={"port":port,"width":width,
		"median":maxf(float(port.get("median",0.0)),float(port.get("declared_median",0.0))),
		"walk":port.get("walk",true),"surface":port.get("surface","asphalt")}
	binding.merge(profile,true)
	result.append(binding)
	return result

## Precompute clipping/width variants while driving toward the question. Only immutable meshes
## run in the worker; the saved network and its current runtime bindings are never modified here.
func warm_bindings(bindings: Array, scenery: Scenery, frames: SceneTree) -> void:
	if Host.is_exiting(frames): return
	var signature:=hash(bindings)
	if _surface_cache.has(signature): return
	var work:=RoadNetwork.new()
	work.build=network.build
	work.data=network.data
	work.tram_surfaces=network.tram_surfaces
	work.stitch_bindings=bindings.duplicate(true)
	var mesh: Mesh
	if PackFiles.web(): mesh=await work.surface_mesh_staged(scenery,frames)
	else: mesh=await _mesh_in_background(func(): return work.surface_mesh(scenery),frames)
	if not is_instance_valid(self) or Host.is_exiting(frames): return
	_surface_cache[signature]=mesh


## Exact intersection of the rendered footprint with the street axis (not chunk-rounded bounds).
func street_interval() -> Array:
	var poly: Array = [Vector3(-_crop,0,-_crop),Vector3(_crop,0,-_crop),Vector3(_crop,0,_crop),Vector3(-_crop,0,_crop)]
	if network: poly=SceneStitch.clip_polygon(poly,network.stitch_bindings)
	poly = SceneStitch.clip_polygon(poly, _cut_bindings)
	var zs: Array = []
	for i in poly.size():
		var a: Vector3 = transform*poly[i]
		var b: Vector3 = transform*poly[(i+1)%poly.size()]
		if absf(a.x)<0.001: zs.append(a.z)
		if (a.x>0)!=(b.x>0) and absf(a.x-b.x)>0.0001: zs.append(a.lerp(b,a.x/(a.x-b.x)).z)
	if zs.is_empty(): return []
	return [zs.min(),zs.max()]


## Scenery beyond an end's runtime cut belongs to the adjoining scene. Original transforms remain in data.
func _trim_end_props() -> void:
	for node in lights + _signs:
		node.visible = SceneStitch.contains(node.position, _cut_bindings) and (network == null or SceneStitch.contains(node.position, network.stitch_bindings))
	for prop in _pool_nodes:
		var node: MultiMeshInstance3D = _pool_nodes[prop]
		var original: Array = node.get_meta("authored_transforms", [])
		for index in original.size():
			var xf: Transform3D = original[index]
			if not SceneStitch.contains(xf.origin, _cut_bindings) or (network and not SceneStitch.contains(xf.origin, network.stitch_bindings)):
				xf = Scenery.Pool.HIDDEN
			(node.get_meta("instance_transforms") as Array)[index] = xf
			Scenery.clear_fade_slot(node, index)
			node.multimesh.set_instance_transform(index, xf)


## Only immutable mesh processing runs off-thread; Node trees are always assembled on the main thread.
static func _mesh_in_background(work: Callable, frames: SceneTree) -> Mesh:
	var result := [null]
	var task := WorkerThreadPool.add_task(func(): result[0] = work.call())
	_tasks.append(task)
	while _tasks.has(task) and not WorkerThreadPool.is_task_completed(task):
		await frames.process_frame
	# World exit already joined/removed the task; never poll or join an invalid task ID.
	if not _tasks.has(task): return null
	WorkerThreadPool.wait_for_task_completion(task)
	_tasks.erase(task)
	return result[0]


static func _data_in_background(work: Callable, frames: SceneTree) -> Dictionary:
	var result := [{}]
	var task := WorkerThreadPool.add_task(func(): result[0] = work.call())
	_tasks.append(task)
	while _tasks.has(task) and not WorkerThreadPool.is_task_completed(task): await frames.process_frame
	if not _tasks.has(task): return {}
	WorkerThreadPool.wait_for_task_completion(task)
	_tasks.erase(task)
	return result[0]


static func _native_prepare(situation_id: String, on_done: Callable) -> void:
	var dir := "res://situations/%s/" % situation_id
	var d = JSON.parse_string(PackFiles.text(dir + "scene.json"))
	if not d is Dictionary:
		if on_done.is_valid(): on_done.call(false)
		return
	var paths: Array[String] = [dir + "scene.glb"]
	for i in d.lights.size():
		if not TrafficSignal.supports(d.lights[i]): paths.append(dir + "light_%d.glb" % i)
	for i in d.actors.size():
		if not _uses_shared_model(str(d.actors[i].type)): paths.append(dir + "actor_%d.glb" % i)
	for path in paths: ResourceLoader.load_threaded_request(path)
	var frames := Engine.get_main_loop() as SceneTree
	var resources: Array = []
	for path in paths:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await frames.process_frame
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
			if on_done.is_valid(): on_done.call(false)
			return
		resources.append(ResourceLoader.load_threaded_get(path))
	_native_resources[situation_id] = resources
	_ready_ids[situation_id] = true
	if on_done.is_valid(): on_done.call(true)


static func finish_background_work() -> void:
	# Exit can happen mid-load. Join immutable worker jobs before the rendering server shuts down.
	for task in _tasks: WorkerThreadPool.wait_for_task_completion(task)
	_tasks.clear()
	_native_resources.clear()
