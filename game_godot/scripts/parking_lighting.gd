## Real, surface-lit night lighting for the Compatibility renderer. Up to five reusable
## scene spots (three on low) leave two for headlights and one for reverse (GLES: eight).
## Luminous fittings describe the source; they never substitute a white quad on the road.
class_name ParkingLighting
extends Node3D

const STATIC_BUDGET := 5
const LOW_STATIC_BUDGET := 3
const HEAD_COLOUR := Color("#FFF1D5")
const SOURCE_FADE_SECONDS := 0.55
const SELECTION_INTERVAL := 0.2
const SELECTION_DISTANCE := 0.25
var headlights: Array[SpotLight3D] = []
var reverse_light: SpotLight3D
var tail_light: OmniLight3D
var reverse_lenses: Array[MeshInstance3D] = []
var static_slots: Array[Dictionary] = []
var sources: Array = []
var _brakes: Array[StandardMaterial3D] = []
var _static_shadows := true
var _first_focus := true
var _static_budget := STATIC_BUDGET
var _wanted: Array[int] = []
var _selection_elapsed := 0.0
var _selection_at := Vector3.ZERO
var _selection_dirty := true
var _last_reverse := -1
var _last_braking := -1


static func apply_environment(sun: DirectionalLight3D, environment: Environment,
		night: bool, indoor: bool, season: String, shadows: bool) -> void:
	MiniGameLighting.apply(sun, environment, season)
	sun.visible = not (night and indoor)
	if night:
		# A cool, readable base preserves kerbs and dark cars between warm pools of light.
		# The garage is a cutaway: no moon or sunlight should enter through its removed roof.
		sun.rotation_degrees = Vector3(-48, -32, 0)
		sun.light_color = Color("#9CB5DD")
		sun.light_energy = 0.0 if indoor else 0.16
		# The low moon angle needs more normal offset than the daytime sun; otherwise
		# the newly shadow-casting player body develops diagonal self-shadow bands.
		sun.shadow_normal_bias = 2.5
		environment.background_color = Color("#101A2C")
		environment.ambient_light_color = Color("#BCCAE3") if not indoor else Color("#BFCAD0")
		environment.ambient_light_energy = 0.32 if indoor else 0.28
		environment.fog_light_color = Color("#17243A")
		environment.fog_depth_begin = 48.0
		environment.fog_depth_end = 155.0
		environment.fog_depth_curve = 1.3
		environment.fog_enabled = not indoor
		# Roll off overlapping beams on pale concrete/snow instead of clipping the
		# manoeuvring area to white. Daylight keeps MiniGameLighting's own tonemapper.
		environment.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
		environment.tonemap_white = 4.0
	# Quality caches reference energies. Refresh them on EVERY transition, including restart.
	sun.set_meta("lit_energy", sun.light_energy)
	sun.set_meta("lit_ambient", environment.ambient_light_energy)
	Quality.set_sun_shadows(sun, environment, shadows)
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.5


func setup(level: Dictionary, car: Node3D, _geo: Dictionary, vehicle_id: String) -> void:
	sources = level.get("night_lights", [])
	for source: Dictionary in sources:
		var size: Vector3 = source.get("fixture", Vector3.ZERO)
		if size.length_squared() > 0.0:
			_fitting(self, source.pos, size, source.colour, 1.2)
	for i in STATIC_BUDGET:
		var light := SpotLight3D.new()
		light.name = "SceneLight%d" % i
		light.visible = false
		light.shadow_bias = 0.06
		light.shadow_normal_bias = 1.5
		light.shadow_blur = 1.5
		add_child(light)
		static_slots.append({"light": light, "index": -1, "weight": 0.0})
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/index.json"))
	var meta: Dictionary = index["vehicles/" + vehicle_id].meta
	var half_w: float = meta.halfWidth
	var half_l: float = meta.halfLength
	var cyber := vehicle_id == "cyber"
	for side: float in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.name = "HeadlightLeft" if side > 0 else "HeadlightRight"
		car.add_child(light)
		light.position = Vector3(side * (0.70 if cyber else half_w * 0.68), 0.86 if cyber else 0.65, 2.57 if cyber else half_l + 0.12)
		# Local +Z is forward. A dipping beam forms a long soft pool on the road and
		# catches the sides of cars/columns, instead of drawing a transparent cone in air.
		light.basis = Basis.looking_at(Vector3(side * 0.025, -0.14, 1.0).normalized())
		light.light_color = Color("#EAF2FF") if cyber else HEAD_COLOUR
		light.light_energy = 1.0
		light.spot_range = 22.0
		light.spot_angle = 30.0
		light.spot_angle_attenuation = 1.6
		light.spot_attenuation = 0.75
		light.shadow_enabled = true
		# Grazing rays otherwise self-shadow the round posts and planters ahead.
		light.shadow_bias = 0.30
		light.shadow_normal_bias = 0.8
		light.shadow_blur = 1.4
		headlights.append(light)
		var halo := ParkingHeadlightGlow.make(light.light_color, 0.55)
		halo.position = light.position
		car.add_child(halo)
		# White reverse sections are separate from the red stop/tail lamps.
		var lens := _fitting(car, Vector3(side * half_w * 0.46, 0.60, -2.55 if cyber else -half_l - 0.13), Vector3(0.16, 0.07, 0.024), Color("#F3F6FF"), 0.9)
		lens.visible = false
		reverse_lenses.append(lens)
	for mesh: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(s)
			if mat is ShaderMaterial and mat.shader == preload("res://shaders/npc_vehicle.gdshader"):
				mat.set_shader_parameter("headlamps_on", true)
			elif cyber and mesh.name == "cyber_lens" and mat is StandardMaterial3D and mat.resource_name == "lens":
				# The imported headlight bar is cyber_lens. Indicators and the rear
				# brake bar also use a material named lens; leave their states alone.
				var own := mat.duplicate() as StandardMaterial3D
				own.emission_enabled = true
				own.emission = Color("#FFF0D8")
				own.emission_energy_multiplier = 0.65
				mesh.set_surface_override_material(s, own)
	for mesh: MeshInstance3D in car.find_children("brake_*", "MeshInstance3D", true, false):
		var mat := mesh.material_override as StandardMaterial3D
		if mat != null and mat not in _brakes:
			mat.emission_enabled = true
			_brakes.append(mat)
	reverse_light = SpotLight3D.new()
	reverse_light.name = "ReverseLight"
	car.add_child(reverse_light)
	reverse_light.position = Vector3(0, 0.65, -half_l - 0.2)
	reverse_light.basis = Basis.looking_at(Vector3(0, -0.35, -1).normalized())
	reverse_light.light_color = Color("#E3EDFF")
	reverse_light.light_energy = 0.85
	reverse_light.spot_range = 7.0
	reverse_light.spot_angle = 55.0
	reverse_light.spot_angle_attenuation = 1.2
	reverse_light.spot_attenuation = 1.2
	reverse_light.shadow_enabled = true
	reverse_light.shadow_bias = 0.04
	reverse_light.shadow_normal_bias = 1.0
	reverse_light.visible = false
	tail_light = OmniLight3D.new()
	tail_light.name = "TailBounce"
	car.add_child(tail_light)
	tail_light.position = Vector3(0, 0.60, -half_l - 0.22)
	tail_light.light_color = Color("#FF3022")
	tail_light.omni_range = 2.0
	tail_light.omni_attenuation = 1.8
	tail_light.light_energy = 0.08
	update_state(1, false, 0.0)


func set_quality(shadows: bool) -> void:
	# Preserve headlight occlusion even on low: otherwise a beam penetrates a parked
	# car or a garage wall. Reduce decorative fixture count and shadows on weak devices.
	if _static_shadows == shadows: return
	_static_shadows = shadows
	_static_budget = STATIC_BUDGET if shadows else LOW_STATIC_BUDGET
	_selection_dirty = true


func update_state(gear: int, braking: bool, _dt: float) -> void:
	# Upload lamp/material state only when the driver changes it, not on every frame.
	var reversing := int(gear < 0)
	if reversing != _last_reverse:
		_last_reverse = reversing
		reverse_light.visible = gear < 0
		for lens in reverse_lenses: lens.visible = gear < 0
	if int(braking) == _last_braking: return
	_last_braking = int(braking)
	tail_light.light_energy = 0.38 if braking else 0.08
	for mat in _brakes:
		mat.albedo_color = Color("#F04438") if braking else Color("#A52B25")
		mat.emission = Color("#FF3022")
		mat.emission_energy_multiplier = 0.9 if braking else 0.28


func update_focus(at: Vector3, dt: float) -> void:
	# Ranking nearby fittings is independent of frame rate. Only transitions need
	# per-frame work; stopped cars need no sorting or unchanged GPU state uploads.
	_selection_elapsed = minf(SELECTION_INTERVAL, _selection_elapsed + maxf(dt, 0.0))
	var moved := at.distance_squared_to(_selection_at)
	if _selection_dirty or moved > 25.0 or (_selection_elapsed >= SELECTION_INTERVAL and moved >= SELECTION_DISTANCE * SELECTION_DISTANCE):
		_select_sources(at)
	for slot_index in static_slots.size():
		var slot: Dictionary = static_slots[slot_index]
		var light: SpotLight3D = slot.light
		var enabled := slot_index < _static_budget
		var needs_change: bool = not enabled or slot.index not in _wanted or light.shadow_enabled != _static_shadows
		if needs_change and float(slot.weight) > 0.0:
			slot.weight = move_toward(float(slot.weight), 0.0, dt / SOURCE_FADE_SECONDS)
			_apply_slot(slot)
			# Show the fully dark frame before changing a light's transform or shadow
			# mode. Rebinding and fading in during this frame used to skip that frame.
			continue
		if not enabled:
			# Spare slots must stay dark on low; otherwise they would light new sources
			# while the old three fade out, temporarily exceeding the phone's budget.
			slot.index = -1
			if light.shadow_enabled: light.shadow_enabled = false
			_apply_slot(slot)
			continue
		if slot.index not in _wanted:
			slot.index = -1
			for id: int in _wanted:
				if static_slots.any(func(s: Dictionary) -> bool: return s.index == id): continue
				slot.index = id
				_configure(light, sources[id])
				break
		if needs_change:
			# A lit fixture keeps its shadows, irrespective of which one is closest.
			# In Compatibility, toggling shadows also changes the diffuse brightness.
			if light.shadow_enabled != _static_shadows: light.shadow_enabled = _static_shadows
			slot.weight = 1.0 if _first_focus and slot.index >= 0 else 0.0
		elif slot.index >= 0:
			slot.weight = move_toward(float(slot.weight), 1.0, dt / SOURCE_FADE_SECONDS)
		_apply_slot(slot)
	_first_focus = false


func _select_sources(at: Vector3) -> void:
	_selection_elapsed = 0.0
	_selection_at = at
	_selection_dirty = false
	var order: Array[int] = []
	for i in sources.size(): order.append(i)
	# Distance to the lit ground (rather than the pole) gives canopy/window sources
	# their proper importance. A small hysteresis keeps neighbouring slots stable.
	var active: Array = static_slots.map(func(slot: Dictionary): return slot.index)
	order.sort_custom(func(a: int, b: int) -> bool:
		return _distance(a, at, active) < _distance(b, at, active))
	_wanted = order.slice(0, _static_budget)


func _apply_slot(slot: Dictionary) -> void:
	var light: SpotLight3D = slot.light
	var weight: float = slot.weight
	# Smooth endpoints avoid a visible kink as a source leaves or enters the pool.
	var fade := weight * weight * (3.0 - 2.0 * weight)
	var energy := float(sources[slot.index].energy) * fade if slot.index >= 0 else 0.0
	# The renderer stores float32; exact comparison would re-upload a steady double.
	if not is_equal_approx(light.light_energy, energy): light.light_energy = energy
	var lit := energy > 0.0001
	if light.visible != lit: light.visible = lit


func _distance(i: int, at: Vector3, active: Array) -> float:
	var target: Vector3 = sources[i].target
	target.y = at.y
	return at.distance_squared_to(target) * (0.82 if i in active else 1.0)


func _configure(light: SpotLight3D, source: Dictionary) -> void:
	light.position = source.pos
	var dir: Vector3 = (source.target - source.pos).normalized()
	light.basis = Basis.looking_at(dir, Vector3.FORWARD if absf(dir.y) > 0.98 else Vector3.UP)
	light.light_color = source.colour
	light.spot_range = source.range
	light.spot_angle = source.angle
	light.spot_angle_attenuation = 0.7
	light.spot_attenuation = 0.8
	light.set_meta("role", source.role)


func _fitting(parent: Node3D, at: Vector3, size: Vector3, colour: Color, energy: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = at
	parent.add_child(mesh)
	return mesh
