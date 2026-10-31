## Authored night lighting for five parking locations. The sources are part of the place:
## lamp diffusers, canopy luminaires, windows and ceiling rails. They never mark the answer.
## The renderer budgets real lights separately; distant luminous fixtures remain visible.
class_name ParkingNightLayout
extends RefCounted

const LOCATIONS := ["hotel", "fuel", "quay", "underground", "cafe_exit"]
const WARM := Color("#FFD6A0")
const STREET := Color("#FFE0B0")
const NEUTRAL := Color("#E2ECFF")


static func configure(l: Dictionary) -> void:
	l.night = str(l.id) in LOCATIONS
	l.night_lights = []
	if not l.night: return
	match str(l.id):
		"hotel": _hotel(l)
		"fuel": _fuel(l)
		"quay": _quay(l)
		"underground": _underground(l)
		"cafe_exit": _cafe(l)


static func _light(l: Dictionary, pos: Vector3, target: Vector3, colour: Color,
		energy: float, reach: float, angle: float, fixture: Vector3, role: String) -> void:
	l.night_lights.append({"pos": pos, "target": target, "colour": colour,
		"energy": energy, "range": reach, "angle": angle, "fixture": fixture, "role": role})


## Ground boxes use the same data format as ParkingLevels, without a circular preload.
static func _box(l: Dictionary, centre: Vector3, size: Vector3, colour: String) -> void:
	l.walls.append({"box": {"c": Vector2(centre.x, centre.z), "half": Vector2(size.x, size.z) * 0.5,
		"yaw": 0.0}, "h": size.y, "y0": centre.y - size.y * 0.5, "colour": colour, "solid": false})


static func _kerb_height(l: Dictionary, at: Vector2) -> float:
	for side: Dictionary in l.sidewalks:
		var d: Vector2 = at - side.c
		var yaw: float = side.yaw
		var p := Vector2(d.dot(Vector2(cos(yaw), -sin(yaw))), d.dot(Vector2(sin(yaw), cos(yaw))))
		if absf(p.x) < side.half.x and absf(p.y) < side.half.y: return 0.15
	return 0.0


## street/lamp's existing diffuser is at (-1.23, 5.025, 0), under the arm pointing -X.
## All parking lamps have yaw=0. The source sits just below the housing, not inside it.
static func _street_lamp(l: Dictionary, at: Vector2, target_x: float, real := true) -> void:
	var p := Vector3(at.x - 1.23, 5.002 + _kerb_height(l, at), at.y)
	var lens := Vector3(0.46, 0.025, 0.20)
	if real:
		_light(l, p, Vector3(target_x, 0.1, at.y), STREET, 1.3, 19.0, 66.0, lens, "street")
	else:
		_box(l, p, lens, "emit:#FFE0B0:1.8")


## Keep dark rooms among the warm ones. The wide ground-floor lobby/shop windows are lit;
## individual upper windows have a stable occupied/unoccupied pattern and two warm hues.
## windowlit retains the existing window map: mullions remain dark instead of glowing too.
static func _windows(l: Dictionary, salt: int) -> void:
	var i := 0
	for wall: Dictionary in l.walls:
		if not str(wall.colour).begins_with("tex:window:"): continue
		var b: Dictionary = wall.box
		var broad := maxf(b.half.x, b.half.y) > 2.0
		if broad or (i * 7 + salt) % 5 < 3:
			wall.colour = "windowlit:#FFD7A0:0.70" if broad or i % 3 else "windowlit:#FFE8BE:0.60"
		i += 1


static func _hotel(l: Dictionary) -> void:
	_windows(l, 2)
	# The two original street lamps serve the approach. New poles stand on the pedestrian
	# edge, outside the driving loop and away from the portico columns and planting tubs.
	l.lamps.append_array([Vector2(1.5, 5.0), Vector2(20.5, -12.0), Vector2(20.5, -42.0)])
	for at: Vector2 in l.lamps:
		_street_lamp(l, at, -3.0 if at.x < 5.0 else 14.0)
	# Recessed diffusers beneath the entrance canopy light the actual stopping kerb.
	for z: float in [-28.5, -24.5]:
		_box(l, Vector3(17.0, 3.55, z), Vector3(0.98, 0.12, 0.43), "#69747E")
		_light(l, Vector3(17.0, 3.48, z), Vector3(15.7, 0.1, z), WARM,
			1.1, 10.0, 70.0, Vector3(0.9, 0.06, 0.35), "canopy")
	# Lobby spill is aimed out from the west-facing glazing, along both ends of the portico.
	for z: float in [-28.2, -24.8]:
		_light(l, Vector3(21.78, 2.1, z), Vector3(17.0, 0.3, z), WARM,
			0.5, 9.0, 62.0, Vector3.ZERO, "window")


static func _fuel(l: Dictionary) -> void:
	_windows(l, 1)
	# Light the approach and exit from poles on the same kerb as the price board.
	l.lamps.append_array([Vector2(0.5, 9.0), Vector2(0.5, -23.5)])
	for at: Vector2 in l.lamps: _street_lamp(l, at, -4.0)
	# Four broad, neutral ceiling panels cover the lanes on both sides of the islands.
	# Sources are below the roof; a bright roof alone would leave the pumps and car dark.
	for x: float in [8.0, 16.0]:
		for z: float in [-6.0, -17.5]:
			_box(l, Vector3(x, 5.14, z), Vector3(1.18, 0.16, 0.63), "#8A969F")
			_light(l, Vector3(x, 5.05, z), Vector3(x, 0.1, z), NEUTRAL,
				1.4, 16.0, 68.0, Vector3(1.1, 0.06, 0.55), "canopy")
	for z: float in [-15.0, -9.0]:
		_light(l, Vector3(23.28, 1.9, z), Vector3(19.0, 0.2, z), WARM,
			0.55, 9.0, 65.0, Vector3.ZERO, "window")
	# Pump displays and the price board have modest backlighting, not independent floodlights.
	for wall: Dictionary in l.walls:
		if str(wall.colour) == "#1E2A33" and is_equal_approx(float(wall.y0), 1.35):
			wall.colour = "emit:#B4DFCA:0.8"
		elif str(wall.colour) == "#F2F4F8" and is_equal_approx(float(wall.y0), 1.3):
			wall.colour = "emit:#E8F0DF:0.6"


static func _quay(l: Dictionary) -> void:
	# The promenade continues beyond the playable road. Nearby lamps wash across the parked
	# row into the lane; distant diffusers remain luminous without spending a real-light slot.
	for at: Vector2 in l.lamps:
		_street_lamp(l, at, 0.5, absf(at.y) <= 42.0)


static func _underground(l: Dictionary) -> void:
	# An open architectural cutaway: slender mounting rails, no opaque ceiling hiding the
	# manoeuvre. Panels sit on the inner edges of the parking rows, lighting aisle and bays.
	var aisle: float = l.bounds.size.y - 2.0 * 5.3 - 1.0
	for z: float in [-0.6, aisle + 0.6]:
		_box(l, Vector3(0.0, 3.16, z), Vector3(43.6, 0.10, 0.12), "#69747E")
		for x: float in [-18.0, -9.0, 0.0, 9.0, 18.0]:
			_box(l, Vector3(x, 3.10, z), Vector3(1.5, 0.08, 0.45), "#8A969F")
			_light(l, Vector3(x, 3.04, z), Vector3(x, 0.1, z + (1.4 if z < 0.0 else -1.4)),
				NEUTRAL, 1.05, 12.5, 78.0, Vector3(1.35, 0.035, 0.32), "ceiling")
	# A small backlit exit sign fixed to the existing end wall, above the green door.
	_box(l, Vector3(21.96, 2.55, aisle * 0.5), Vector3(0.05, 0.23, 1.2), "emit:#7CE7A9:0.65")


static func _cafe(l: Dictionary) -> void:
	_windows(l, 3)
	for at: Vector2 in l.lamps: _street_lamp(l, at, -1.5)
	# Warm light through the restaurant's west-facing glazing reaches the tables and kerb.
	for z: float in [-4.0, 4.0]:
		_light(l, Vector3(7.78, 2.0, z), Vector3(3.0, 0.2, z), WARM,
			0.65, 10.5, 64.0, Vector3.ZERO, "window")
	# Wall-mounted downlights frame the terrace; their housings stay above pedestrian height.
	for z: float in [-12.0, 12.0]:
		_box(l, Vector3(7.92, 3.1, z), Vector3(0.18, 0.32, 0.30), "#414850")
		_light(l, Vector3(7.78, 3.0, z), Vector3(4.2, 0.15, z), WARM,
			0.9, 10.0, 65.0, Vector3(0.12, 0.06, 0.24), "sconce")
