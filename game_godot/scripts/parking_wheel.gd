## The steering wheel of «Парковка», in place of the city's left/right arrows: a black game-style
## wheel (icons/parking_wheel.svg) with a blue mark at twelve o'clock and the «P» badge, turned as
## a whole above its shadow. A finger turns it
## around its centre like a real wheel (near the hub a sideways drag turns it too); it stays
## where it is left, so the front wheels keep their lock. Half a turn each way is full lock,
## a light click marks straight ahead and the lock, a double tap straightens the wheel.
## value: 1 = full left .. -1 = full right, as Controls.steer.
class_name ParkingWheel
extends Control

const TURN := PI                 # rotation of the wheel at full lock
const DOUBLE_TAP := 0.35         # s between two taps that straighten the wheel
const TAP_SLOP := 10.0           # px a tap may move
const CENTRE_RATE := 2.5         # value/s while straightening
const DETENT := 0.04             # released this close to straight, the wheel snaps straight


var value := 0.0
var active := true
var _finger := -1                # touch index holding the wheel, -1 none
var _last_angle := 0.0
var _last_point := Vector2.ZERO
var _travel := 0.0
var _last_tap := -10.0
var _centring := false
var _face: TextureRect


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_face = TextureRect.new()
	_face.texture = load("res://icons/parking_wheel.svg")
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_SCALE
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_face)


func held() -> bool:
	return _finger >= 0


## Set by the game (a new level, the autopilot); the wheel does not click.
func set_value(v: float) -> void:
	value = clampf(v, -1.0, 1.0)
	_centring = false
	_refresh()


## The keyboard turns the wheel at a rate while A/D or the arrows are held.
func nudge(amount: float) -> void:
	if held() or is_zero_approx(amount): return
	_centring = false
	_turn_to(value + amount)


func release() -> void:
	_finger = -1
	_centring = false
	_refresh()


func _centre() -> Vector2:
	return get_global_rect().get_center()


func _radius() -> float:
	return get_global_rect().size.x * 0.5


func _input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree(): return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _finger < 0 and touch.position.distance_to(_centre()) <= _radius() * 1.12:
			_finger = touch.index
			_last_point = touch.position
			_last_angle = (touch.position - _centre()).angle()
			_travel = 0.0
			_centring = false
			_refresh()
			get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _finger:
			_finger = -1
			var now := Time.get_ticks_msec() / 1000.0
			if _travel < TAP_SLOP:
				if now - _last_tap < DOUBLE_TAP:
					_centring = true
					_last_tap = -10.0
				else:
					_last_tap = now
			elif absf(value) < DETENT:
				value = 0.0
			_refresh()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _finger:
		var drag := event as InputEventScreenDrag
		var offset := drag.position - _centre()
		var angle := offset.angle()
		var turn := 0.0
		if offset.length() > _radius() * 0.28:
			turn = wrapf(angle - _last_angle, -PI, PI)
		else:
			# Around the hub the angle jumps about: a sideways drag turns the wheel instead.
			turn = (drag.position.x - _last_point.x) / (_radius() * 0.9)
		_travel += drag.position.distance_to(_last_point)
		_last_angle = angle
		_last_point = drag.position
		# Screen rotation is clockwise, i.e. to the right: the value goes down.
		_turn_to(value - turn / TURN)
		get_viewport().set_input_as_handled()


func _turn_to(v: float) -> void:
	var next := clampf(v, -1.0, 1.0)
	var crossed := signf(next) != signf(value) and not is_zero_approx(value)
	var locked := absf(next) >= 1.0 and absf(value) < 1.0
	if crossed or locked: GameSound.buzz(6)
	value = next
	_refresh()


func _process(delta: float) -> void:
	if not _centring: return
	value = move_toward(value, 0.0, CENTRE_RATE * delta)
	if is_zero_approx(value): _centring = false
	_refresh()


func _draw() -> void:
	# A soft shadow on the ground; it stays put while the wheel turns above it.
	var r := size.x * 0.5
	for k in 5:
		draw_circle(size * 0.5 + Vector2(0, r * 0.06), r * (0.99 - k * 0.03), Color(0, 0, 0, 0.06), true, -1.0, true)


func _refresh() -> void:
	_face.size = size
	_face.pivot_offset = size * 0.5
	_face.rotation = -value * TURN
	# Pressed like the app's buttons: 97%.
	_face.scale = Vector2.ONE * (0.97 if held() else 1.0)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(_face): _refresh()
